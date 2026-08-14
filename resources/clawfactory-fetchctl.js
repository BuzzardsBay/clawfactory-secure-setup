#!/usr/bin/env node
// clawfactory-fetchctl.js -- the ROOT-ONLY control tool for Guard 3's
// read-fetch allowlist.
//
// Installed to /usr/local/sbin/clawfactory-fetchctl.js, root:root 0750.
//
// THIS IS THE ONLY WRITE PATH TO read_fetch, AND IT NEVER RUNS AS UID 1000.
// Studio reaches it through the same hardcoded `wsl -u root` channel that the
// approval path uses. Three independent things stop the agent adding its own
// destination: the mode on this program, the mode on the policy file it writes
// (root:root 0644), and the fact that applying a change requires talking to
// nftables, which refuses a non-root caller outright.
//
// There is deliberately NO daemon and NO socket here. Guard 2 needs a daemon
// because it owns a store and performs sends; Guard 3 owns one list. Adding a
// listening socket to serve four commands would create attack surface to solve
// a problem that does not exist.
//
// The store lock is SHARED with the send broker on purpose. Both programs
// read-modify-write the same root-owned egress policy file, and without a
// shared lock a simultaneous SMTP save and destination add could silently drop
// one of the two. A lost update here would revoke something the user believes
// they authorized.

'use strict';

const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

const lib = require('/usr/local/lib/clawfactory/send-lib.js');

const RESOLVER = '/usr/local/sbin/clawfactory-read-fetch.sh';

if (typeof process.getuid !== 'function' || process.getuid() !== 0) {
  process.stderr.write('clawfactory-fetchctl: must run as root\n');
  process.exit(1);
}

const cfg = lib.loadConfig();

// Strict by construction. A destination is a bare hostname or an IPv4 literal:
// no scheme, no port, no path, no wildcard. A wildcard in an egress allowlist
// is an exfiltration channel with a friendly name, which is the same reasoning
// the send destination matcher is built on.
//
// The resolver script carries its own copy of this check. That duplication is
// deliberate: the resolver reads a file on disk and must not assume this
// program was the thing that wrote it.
const HOST_RE = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/;

function normalizeHost(input) {
  const s = String(input == null ? '' : input).trim().toLowerCase();
  if (!s) return { ok: false, error: 'no destination given' };
  if (s.length > 253) return { ok: false, error: 'destination is too long' };
  if (s.includes('*')) {
    return { ok: false, error: 'wildcards are not accepted: name each site you want the agent to read' };
  }
  if (s.includes('/') || s.includes(':')) {
    return {
      ok: false,
      error: 'give a site name only, with no https:// prefix, no port and no path (for example: docs.python.org)',
    };
  }
  if (!HOST_RE.test(s)) return { ok: false, error: `not a valid site name: ${s}` };
  return { ok: true, host: s };
}

function readPolicy() {
  try {
    const raw = JSON.parse(fs.readFileSync(cfg.policyPath, 'utf8'));
    return { ok: true, raw };
  } catch (e) {
    return { ok: false, error: `cannot read egress policy ${cfg.policyPath}: ${e.message}` };
  }
}

function currentAllow(raw) {
  const rf = raw && raw.read_fetch;
  const list = rf && Array.isArray(rf.allow) ? rf.allow : [];
  const out = [];
  for (const e of list) {
    const h = typeof e === 'string' ? e : e && e.host;
    const n = normalizeHost(h);
    if (!n.ok) continue;
    if (!out.some((x) => x.host === n.host)) {
      out.push({ host: n.host, addedAt: (e && e.addedAt) || null });
    }
  }
  return out;
}

/** Write the policy atomically, preserving every section this tool does not own.
 *  send_actions is read back from disk and written straight through: Guard 3
 *  must never be the reason a user's authorized send destination disappears. */
function writeAllow(raw, allow) {
  const next = raw && typeof raw === 'object' ? raw : {};
  if (!next.version) next.version = 1;
  const note = (next.read_fetch && next.read_fetch._note) || undefined;
  next.read_fetch = { allow };
  if (note) next.read_fetch._note = note;
  if (!Array.isArray(next.send_actions)) next.send_actions = [];

  const tmp = `${cfg.policyPath}.tmp`;
  const fd = fs.openSync(tmp, 'w', 0o644);
  try {
    fs.writeSync(fd, `${JSON.stringify(next, null, 2)}\n`);
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, cfg.policyPath);
  fs.chownSync(cfg.policyPath, 0, 0);
  fs.chmodSync(cfg.policyPath, 0o644);
}

/** Re-derive the live firewall set from the policy file. Reported rather than
 *  swallowed: if this fails the destination is in the list but has no route, and
 *  telling the user "added" would be a lie in the permissive direction. */
function applyPolicy() {
  try {
    const out = execFileSync(RESOLVER, [], { encoding: 'utf8', timeout: 120000, stdio: ['ignore', 'pipe', 'pipe'] });
    return { ok: true, detail: String(out).trim() };
  } catch (e) {
    const detail = [e.stdout, e.stderr].filter(Boolean).join('\n').trim();
    return { ok: false, error: `could not apply the list to the firewall: ${detail || e.message}` };
  }
}

/** What the firewall actually holds, as opposed to what the file says it should.
 *  These disagree exactly when something is wrong, so the panel shows both. */
function liveState() {
  const backend = (() => {
    try {
      return fs.readFileSync('/etc/clawfactory/fw-backend', 'utf8').trim() || 'nftables';
    } catch {
      return 'nftables';
    }
  })();
  const state = { backend, enforced: false, addresses: 0 };
  if (backend === 'nftables') {
    try {
      const out = execFileSync('/usr/sbin/nft', ['list', 'set', 'inet', 'clawfactory', 'read_fetch_ipv4'], {
        encoding: 'utf8',
        timeout: 15000,
        stdio: ['ignore', 'pipe', 'ignore'],
      });
      state.enforced = true;
      const m = String(out).match(/\b\d{1,3}(?:\.\d{1,3}){3}\b/g);
      state.addresses = m ? new Set(m).size : 0;
    } catch {
      state.enforced = false;
    }
  } else {
    try {
      state.addresses = fs
        .readFileSync('/etc/clawfactory/read-fetch-ips.txt', 'utf8')
        .split('\n')
        .filter(Boolean).length;
      state.enforced = true;
    } catch {
      state.enforced = false;
    }
  }
  return state;
}

function usage() {
  process.stderr.write(
    [
      'usage: clawfactory-fetchctl <command>',
      '',
      '  list             the read-fetch allowlist, plus what the firewall holds',
      '  add <host>       allow one site. Exact name, no scheme, no port, no path',
      '  remove <host>    revoke one site',
      '  apply            re-derive the firewall set from the policy file',
      '',
    ].join('\n'),
  );
}

function out(obj) {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
  process.exit(obj && obj.ok ? 0 : 1);
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  if (!cmd) {
    usage();
    process.exit(2);
  }

  if (cmd === 'list') {
    const p = readPolicy();
    if (!p.ok) return out({ ok: false, code: 'EPOLICY', error: p.error, allow: [], live: liveState() });
    return out({ ok: true, allow: currentAllow(p.raw), live: liveState() });
  }

  if (cmd === 'apply') {
    const r = applyPolicy();
    return out(r.ok ? { ok: true, detail: r.detail, live: liveState() } : { ok: false, code: 'EAPPLY', error: r.error });
  }

  if (cmd === 'add' || cmd === 'remove') {
    const n = normalizeHost(rest[0]);
    if (!n.ok) return out({ ok: false, code: 'EINVAL', error: n.error });

    const result = await lib.withStoreLock(cfg, async () => {
      const p = readPolicy();
      if (!p.ok) return { ok: false, code: 'EPOLICY', error: p.error };
      const allow = currentAllow(p.raw);
      const at = allow.findIndex((x) => x.host === n.host);

      if (cmd === 'add') {
        if (at >= 0) return { ok: true, host: n.host, changed: false, note: 'already allowed' };
        allow.push({ host: n.host, addedAt: new Date().toISOString() });
      } else {
        if (at < 0) return { ok: true, host: n.host, changed: false, note: 'was not on the list' };
        allow.splice(at, 1);
      }
      writeAllow(p.raw, allow);
      return { ok: true, host: n.host, changed: true, allow };
    });

    if (!result.ok) return out(result);
    const applied = applyPolicy();
    if (!applied.ok) {
      // The file changed and the firewall did not. For `remove` that is merely
      // stale; for `add` it means the site is listed and still unreachable.
      return out({ ok: false, code: 'EAPPLY', error: applied.error, host: n.host, changed: result.changed });
    }
    const p2 = readPolicy();
    return out({
      ok: true,
      host: n.host,
      changed: result.changed,
      note: result.note || null,
      allow: p2.ok ? currentAllow(p2.raw) : [],
      live: liveState(),
    });
  }

  usage();
  process.exit(2);
}

main().catch((e) => {
  process.stderr.write(`clawfactory-fetchctl: ${e.message}\n`);
  process.exit(1);
});
