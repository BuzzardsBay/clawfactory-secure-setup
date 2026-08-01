#!/usr/bin/env node
// clawfactory-quarantined.js — the ROOT quarantine broker.
//
// Listens on a unix socket. On request it MOVES the target into the root-owned
// quarantine store and chowns it to root, so a delete becomes recoverable and
// the held copy is beyond the agent's reach. Installed to
// /usr/local/sbin/clawfactory-quarantined.js and run by
// clawfactory-quarantine.service.
//
// WHY ROOT, AND WHY THAT IS SAFE
// Root is required for exactly one reason: only root can chown the held payload
// away from clawuser, and an un-chowned payload in a clawuser-writable place is
// one `rm -rf` from being no safety net at all.
//
// Running a root service that deletes files on request from a non-root caller
// is a privilege-escalation shape, so the broker refuses to do anything the
// CALLER could not already have done itself. Before any move it re-derives the
// POSIX unlink permission as clawuser (setpriv drops to the agent uid and tests
// the parent directory; sticky-bit ownership is checked separately). A request
// to quarantine a root-owned file in a root-only directory is denied, exactly
// as a raw `rm` by clawuser would have been. The broker is a safety net on an
// existing capability, never a new one.
//
// TRUST MODEL: the socket is root:clawuser 0660, so the caller is the agent
// account by construction; there is no additional authentication and none is
// claimed. Nothing here defends against clawuser choosing NOT to call the
// broker -- see the close-out's structural-vs-advisory statement.

'use strict';

const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const lib = require('/usr/local/lib/clawfactory/quarantine-lib.js');

const cfg = lib.loadConfig();
const AGENT_USER = cfg.agentUser || 'clawuser';

function log(msg) {
  process.stdout.write(`[quarantined] ${msg}\n`);
}

/** Resolve the agent account once at startup; refuse to run without it. */
function resolveAgent() {
  const r = spawnSync('id', ['-u', AGENT_USER], { encoding: 'utf8' });
  const g = spawnSync('id', ['-g', AGENT_USER], { encoding: 'utf8' });
  if (r.status !== 0 || g.status !== 0) {
    log(`FATAL: agent account "${AGENT_USER}" not found`);
    process.exit(1);
  }
  return { uid: Number(r.stdout.trim()), gid: Number(g.stdout.trim()) };
}
const AGENT = resolveAgent();

/**
 * Would the agent account have been allowed to unlink `target` itself?
 * Mirrors POSIX: write + execute on the parent directory, plus the sticky-bit
 * ownership rule. Evaluated by actually dropping to the agent uid, so ancestor
 * traversal bits are covered too rather than approximated.
 */
function agentCouldUnlink(target) {
  const parent = path.dirname(target);
  const r = spawnSync(
    'setpriv',
    [
      `--reuid=${AGENT.uid}`,
      `--regid=${AGENT.gid}`,
      '--clear-groups',
      '/usr/bin/test',
      '-w',
      parent,
      '-a',
      '-x',
      parent,
    ],
    { encoding: 'utf8' },
  );
  if (r.error || r.status !== 0) return false;

  // Sticky parent (/tmp-style): only the file's owner or the directory's owner
  // may unlink.
  let pst;
  let tst;
  try {
    pst = fs.statSync(parent);
    tst = fs.lstatSync(target);
  } catch {
    return false;
  }
  if (pst.mode & 0o1000) {
    if (tst.uid !== AGENT.uid && pst.uid !== AGENT.uid) return false;
  }
  return true;
}

/** Resolve the PARENT through symlinks, then re-attach the leaf name. Keeps a
 *  symlinked leaf as itself while defeating `granted/link-to-etc/passwd`. */
function resolveLeaf(p) {
  const abs = path.resolve(p);
  const parent = fs.realpathSync(path.dirname(abs));
  return path.join(parent, path.basename(abs));
}

function inScope(target) {
  const roots = Array.isArray(cfg.quarantineRoots) ? cfg.quarantineRoots : [];
  if (!roots.some((r) => lib.isUnder(r, target))) return false;
  const segs = new Set(Array.isArray(cfg.skipSegments) ? cfg.skipSegments : []);
  return !target.split('/').some((s) => segs.has(s));
}

/** A directory whose device differs from its parent's is a mount point. */
function isMountPoint(target, st) {
  if (!st.isDirectory()) return false;
  try {
    return fs.statSync(path.dirname(target)).dev !== st.dev;
  } catch {
    return true; // cannot prove it is safe -> treat as a mount and refuse
  }
}

function newEntryId() {
  return `${new Date().toISOString().replace(/[:.]/g, '-')}-${process.hrtime.bigint().toString(36).slice(-6)}`;
}

/**
 * Serialize the delete path. The store-capacity check reads the index, decides,
 * and only then moves; two deletes interleaving between those steps could both
 * pass a check that only one of them fits through. The broker is one process,
 * so a promise chain is a complete mutex for it -- the on-disk index lock is
 * what guards against the ctl and gc processes.
 */
let chain = Promise.resolve();
function serialize(fn) {
  const run = chain.then(fn, fn);
  chain = run.then(
    () => {},
    () => {},
  );
  return run;
}

/** The delete path. Returns the response object; never throws to the socket. */
async function handleDelete(req) {
  const raw = typeof req.path === 'string' ? req.path : '';
  if (!raw.startsWith('/')) return { ok: false, code: 'EINVAL', error: 'absolute path required' };

  let target;
  try {
    target = resolveLeaf(raw);
  } catch {
    return { ok: false, code: 'ENOENT', error: `no such path: ${raw}` };
  }

  // Never let the store be fed to itself, and never hold the broker's own
  // machinery.
  if (lib.isUnder(cfg.store, target)) {
    return { ok: false, code: 'EPERM', error: 'refusing to quarantine the quarantine store' };
  }
  if (!inScope(target)) {
    // Out of scope is a normal outcome, not a failure: the caller falls through
    // to a real delete. Scope is decided HERE so the config stays root-owned.
    return { ok: true, quarantined: false, reason: 'out-of-scope', path: target };
  }

  let st;
  try {
    st = fs.lstatSync(target);
  } catch {
    return { ok: false, code: 'ENOENT', error: `no such file or directory: ${target}` };
  }
  if (isMountPoint(target, st)) {
    return { ok: false, code: 'EBUSY', error: `refusing to delete a mount point: ${target}` };
  }
  if (st.isDirectory() && req.recursive !== true) {
    return { ok: false, code: 'EISDIR', error: `is a directory: ${target}` };
  }
  if (!agentCouldUnlink(target)) {
    return { ok: false, code: 'EACCES', error: `permission denied: ${target}` };
  }

  let size;
  try {
    size = lib.pathSize(target);
  } catch (e) {
    return { ok: false, code: 'EIO', error: `cannot measure ${target}: ${e.message}` };
  }
  if (size > cfg.maxEntryBytes) {
    return {
      ok: false,
      code: 'E2BIG',
      error:
        `${target} is ${size} bytes, over the ${cfg.maxEntryBytes}-byte quarantine limit. ` +
        `Not deleted -- a delete this large has to be done deliberately by the user.`,
    };
  }

  // Aggregate ceiling and free-space floor. REFUSE, never evict and never fall
  // through: evicting would silently break the retention promise, and falling
  // through would silently destroy the file this guard exists to protect.
  const refusal = lib.capacityRefusal(cfg, lib.readIndex(cfg), size);
  if (refusal) {
    log(`REFUSED ${target}: ${refusal.code} (${refusal.error})`);
    return { ok: false, code: refusal.code, error: refusal.error };
  }

  const id = newEntryId();
  const dir = lib.entryDir(cfg, id);
  const stored = path.join(dir, path.basename(target));
  try {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    // Symlinks are recreated, not followed: copying through a link would lose
    // fidelity and pull in data from outside the grant, and a DANGLING link
    // cannot be cpSync'd at all.
    lib.copyPreservingLinks(target, stored);
    // The move is a copy+remove, not a rename: /workspaces is a drvfs mount and
    // the store is on the root filesystem, so rename(2) is cross-device (EXDEV).
    lib.chownRootRecursive(stored);
    fs.rmSync(target, { recursive: true, force: true });
  } catch (e) {
    // Leave the source alone on any failure and drop the half-written entry.
    try {
      fs.rmSync(dir, { recursive: true, force: true });
    } catch {
      /* best effort */
    }
    return { ok: false, code: 'EIO', error: `quarantine failed for ${target}: ${e.message}` };
  }

  const record = {
    id,
    originalPath: target,
    name: path.basename(target),
    type: st.isSymbolicLink() ? 'symlink' : st.isDirectory() ? 'directory' : 'file',
    sizeBytes: size,
    // Directories get no digest: a tree hash would need a manifest format this
    // guard does not need. Recorded honestly as null rather than faked.
    sha256: st.isFile() && !st.isSymbolicLink() ? safeHash(stored) : null,
    deletedAt: new Date().toISOString(),
    taskId: typeof req.taskId === 'string' && req.taskId ? req.taskId : null,
    requestedBy: AGENT_USER,
  };
  try {
    await lib.withIndexLock(cfg, () => {
      const records = lib.readIndex(cfg);
      records.push(record);
      lib.writeIndex(cfg, records);
    });
  } catch (e) {
    // The payload IS held; only the record failed. Say so rather than implying
    // the file is lost.
    log(`WARN: held ${target} as ${id} but could not write the index: ${e.message}`);
  }
  log(`held ${target} -> ${id} (${size} bytes)`);
  return { ok: true, quarantined: true, id, path: target, sizeBytes: size };
}

function safeHash(p) {
  try {
    return lib.sha256File(p);
  } catch {
    return null;
  }
}

async function handle(req) {
  switch (req && req.op) {
    case 'ping':
      return { ok: true, pong: true, store: cfg.store, retentionDays: cfg.retentionDays };
    case 'delete':
      return serialize(() => handleDelete(req));
    default:
      return { ok: false, code: 'EINVAL', error: `unknown op: ${req && req.op}` };
  }
}

// --- socket -----------------------------------------------------------------

fs.mkdirSync(cfg.store, { recursive: true, mode: 0o700 });
fs.chmodSync(cfg.store, 0o700);

try {
  fs.unlinkSync(cfg.socketPath);
} catch {
  /* no stale socket */
}
fs.mkdirSync(path.dirname(cfg.socketPath), { recursive: true, mode: 0o755 });

const server = net.createServer((sock) => {
  let buf = '';
  sock.setEncoding('utf8');
  sock.on('data', async (chunk) => {
    buf += chunk;
    // Requests are single-line JSON; anything absurd is a bad client.
    if (buf.length > 64 * 1024) {
      sock.end(`${JSON.stringify({ ok: false, code: 'E2BIG', error: 'request too large' })}\n`);
      return;
    }
    const nl = buf.indexOf('\n');
    if (nl < 0) return;
    const line = buf.slice(0, nl);
    buf = '';
    let res;
    try {
      res = await handle(JSON.parse(line));
    } catch (e) {
      res = { ok: false, code: 'EINVAL', error: `bad request: ${e.message}` };
    }
    sock.end(`${JSON.stringify(res)}\n`);
  });
  sock.on('error', () => sock.destroy());
});

server.on('error', (e) => {
  log(`FATAL: ${e.message}`);
  process.exit(1);
});

server.listen(cfg.socketPath, () => {
  // root:clawuser 0660 -- the agent account may call the broker; nothing else
  // on the box can. This IS the caller authentication; see the trust note above.
  try {
    fs.chownSync(cfg.socketPath, 0, AGENT.gid);
    fs.chmodSync(cfg.socketPath, 0o660);
  } catch (e) {
    log(`FATAL: cannot secure ${cfg.socketPath}: ${e.message}`);
    process.exit(1);
  }
  log(
    `listening on ${cfg.socketPath} (store=${cfg.store}, retention=${cfg.retentionDays}d, ` +
      `roots=${(cfg.quarantineRoots || []).join(',')}, host=${os.hostname()})`,
  );
});

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    try {
      server.close();
      fs.unlinkSync(cfg.socketPath);
    } catch {
      /* shutting down anyway */
    }
    process.exit(0);
  });
}
