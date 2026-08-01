// quarantine-lib.js — shared store/index helpers for the ClawFactory delete
// quarantine. Loaded by the root daemon (clawfactory-quarantined.js) and by the
// root CLI (clawfactory-quarantinectl.js). Both run as ROOT; the agent never
// loads this file.
//
// Installed to /usr/local/lib/clawfactory/quarantine-lib.js (root:root 0644),
// alongside the existing gateway-wait.sh helper.
//
// STORE LAYOUT
//   /var/lib/clawfactory/quarantine/            root:root 0700
//     index.json                                the record set (array)
//     .index.lock                               O_EXCL mutex
//     <entry-id>/<original basename>            the held payload, chowned root
//
// Payload is chowned root:root INSIDE a 0700 root-owned store, which is what
// makes held items un-purgeable by clawuser. See the close-out for the
// structural-vs-advisory split: holding is structural, ROUTING is not.

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const CONFIG_PATH = '/etc/clawfactory/quarantine.json';

const DEFAULTS = {
  // Days a held item survives before the cleanup timer may reap it. Reviewed
  // default per the Three-Guard spec; change here and in the Studio empty-state
  // copy together, they are a promise pair.
  retentionDays: 30,
  // Refuse to hold anything larger than this (bytes). Without a cap, one
  // `rm -rf` of a huge tree fills /var/lib and takes the box down. Refusing
  // loudly is better than a silent disk-fill.
  maxEntryBytes: 2 * 1024 * 1024 * 1024,
  // ONLY paths under these roots are quarantined. Everything else passes
  // through to the real rm. /workspaces is the granted-folder mount root --
  // i.e. exactly "the user's files", which is the whole promise. Agent scratch
  // under /home and /tmp deletes normally so builds are not affected.
  quarantineRoots: ['/workspaces'],
  // Path segments that pass through even inside a quarantine root: canonically
  // regenerable trees whose deletion is routine and whose size is pathological.
  skipSegments: ['node_modules', '.git'],
  socketPath: '/run/clawfactory/quarantine.sock',
  store: '/var/lib/clawfactory/quarantine',
};

function loadConfig() {
  let onDisk = {};
  try {
    onDisk = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
  } catch {
    // Absent or unparseable config -> defaults. The install writes this file;
    // falling back keeps the delete path working rather than failing open to a
    // raw unlink.
  }
  return { ...DEFAULTS, ...(onDisk && typeof onDisk === 'object' ? onDisk : {}) };
}

const indexPath = (cfg) => path.join(cfg.store, 'index.json');
const lockPath = (cfg) => path.join(cfg.store, '.index.lock');
const entryDir = (cfg, id) => path.join(cfg.store, id);

/**
 * Take the index mutex, run fn, release. O_EXCL create is the mutex; a lock
 * older than 30s is considered stale (a killed daemon must not wedge deletes
 * forever) and is broken.
 */
function withIndexLock(cfg, fn) {
  const lp = lockPath(cfg);
  const deadline = Date.now() + 10_000;
  let fd = null;
  for (;;) {
    try {
      fd = fs.openSync(lp, 'wx');
      break;
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      try {
        if (Date.now() - fs.statSync(lp).mtimeMs > 30_000) {
          fs.unlinkSync(lp);
          continue;
        }
      } catch {
        continue; // lock vanished under us; retry the create
      }
      if (Date.now() > deadline) throw new Error('quarantine index is locked');
      // Node has no sleep; a short blocking wait is fine here (deletes are rare
      // and this process has nothing else to do).
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50);
    }
  }
  try {
    return fn();
  } finally {
    try {
      fs.closeSync(fd);
    } catch {
      /* already closed */
    }
    try {
      fs.unlinkSync(lp);
    } catch {
      /* already gone */
    }
  }
}

function readIndex(cfg) {
  try {
    const parsed = JSON.parse(fs.readFileSync(indexPath(cfg), 'utf8'));
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

/** Atomic replace so a crash mid-write cannot truncate the record set. */
function writeIndex(cfg, records) {
  const tmp = `${indexPath(cfg)}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(records, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(tmp, indexPath(cfg));
}

function sha256File(p) {
  const h = crypto.createHash('sha256');
  h.update(fs.readFileSync(p));
  return h.digest('hex');
}

/** Recursive apparent size. Symlinks count as their own link size, not target. */
function pathSize(p) {
  const st = fs.lstatSync(p);
  if (st.isSymbolicLink() || st.isFile()) return st.size;
  if (!st.isDirectory()) return 0;
  let total = 0;
  for (const name of fs.readdirSync(p)) {
    try {
      total += pathSize(path.join(p, name));
    } catch {
      // Unreadable child: skip its size rather than abort the whole measure.
    }
  }
  return total;
}

/**
 * Copy src -> dst preserving symlinks, in both directions (into the store and
 * back out on restore).
 *
 * fs.cpSync cannot handle a DANGLING symlink even with dereference:false -- it
 * stats the source and throws ENOENT. A broken link is still a real directory
 * entry the user may want back, so recreate the link itself rather than trying
 * to copy through it.
 */
function copyPreservingLinks(src, dst) {
  const st = fs.lstatSync(src);
  if (st.isSymbolicLink()) {
    fs.symlinkSync(fs.readlinkSync(src), dst);
    return;
  }
  fs.cpSync(src, dst, {
    recursive: true,
    dereference: false,
    preserveTimestamps: true,
    force: true,
  });
}

/** chown -R root:root, so clawuser cannot unlink the held payload. */
function chownRootRecursive(p) {
  fs.lchownSync(p, 0, 0);
  let st;
  try {
    st = fs.lstatSync(p);
  } catch {
    return;
  }
  if (!st.isDirectory()) return;
  for (const name of fs.readdirSync(p)) chownRootRecursive(path.join(p, name));
}

/** True when `child` is `parent` itself or sits underneath it. */
function isUnder(parent, child) {
  const a = path.resolve(parent);
  const b = path.resolve(child);
  return b === a || b.startsWith(a.endsWith('/') ? a : `${a}/`);
}

module.exports = {
  CONFIG_PATH,
  DEFAULTS,
  loadConfig,
  indexPath,
  entryDir,
  withIndexLock,
  readIndex,
  writeIndex,
  sha256File,
  pathSize,
  copyPreservingLinks,
  chownRootRecursive,
  isUnder,
};
