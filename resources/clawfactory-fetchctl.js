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
const TOOLCHAIN_RESOLVER = '/usr/local/sbin/clawfactory-toolchain.sh';

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

/** Re-derive the toolchain set. Same reporting discipline, and the failure
 *  direction matters in the opposite way: if this fails after the user switched
 *  the toolchain OFF, the route is still open and saying "done" would be a lie
 *  in the permissive direction. The resolver flushes before it adds, so a
 *  failure part-way through leaves the set narrower rather than wider. */
function applyToolchain() {
  try {
    const out = execFileSync(TOOLCHAIN_RESOLVER, [], { encoding: 'utf8', timeout: 120000, stdio: ['ignore', 'pipe', 'pipe'] });
    return { ok: true, detail: String(out).trim() };
  } catch (e) {
    const detail = [e.stdout, e.stderr].filter(Boolean).join('\n').trim();
    return { ok: false, error: `could not apply the toolchain switch to the firewall: ${detail || e.message}` };
  }
}

/** Read the toggle as the RESOLVER reads it, including the same defaults.
 *
 *  An absent section or key means ON, because that is a policy file written
 *  before this feature existed and the documented fresh-install state is on.
 *  Only an explicit false is off. This mirrors clawfactory-toolchain.sh
 *  deliberately: if the panel and the enforcement disagreed about what an absent
 *  key means, the panel would draw a switch in the wrong position and the user
 *  would flip it the wrong way. */
function toolchainEnabled(raw) {
  const t = raw ? raw.toolchain : undefined;
  // ABSENT is ON (a policy predating the feature); MALFORMED is OFF (a fault is
  // not a preference); a boolean is itself. Must stay byte-for-byte equivalent
  // to the decision in clawfactory-toolchain.sh, because if the panel and the
  // enforcement disagreed about what a given file means, the panel would draw
  // the switch in the wrong position and the user would flip it the wrong way.
  if (t === undefined || t === null) return true;
  if (typeof t !== 'object' || Array.isArray(t)) return false;
  if (t.enabled === undefined || t.enabled === null) return true;
  return t.enabled === true;
}

/** What the firewall actually holds for the toolchain set, as opposed to what
 *  the policy says. The panel shows both, because they disagree exactly when
 *  something is wrong: a toggle reading ON with zero addresses means the switch
 *  is set but the route is not actually open. */
function toolchainLive() {
  const state = { enforced: false, addresses: 0 };
  try {
    const out = execFileSync('/usr/sbin/nft', ['list', 'set', 'inet', 'clawfactory', 'toolchain_ipv4'], {
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
  return state;
}

/** Write the toolchain toggle, preserving every section this tool does not own.
 *  read_fetch and send_actions are carried through untouched: the toolchain
 *  switch must never be the reason a user loses an allowed site or an authorized
 *  send destination. */
function writeToolchain(raw, enabled) {
  const next = raw && typeof raw === 'object' ? raw : {};
  if (!next.version) next.version = 1;
  const note = (next.toolchain && next.toolchain._note) || undefined;
  next.toolchain = { enabled: enabled === true };
  if (note) next.toolchain._note = note;
  if (!next.read_fetch || !Array.isArray(next.read_fetch.allow)) next.read_fetch = { allow: [] };
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
      '  list                 the read-fetch allowlist and the toolchain switch,',
      '                       plus what the firewall actually holds for both',
      '  add <host>           allow one site. Exact name, no scheme, no port, no path',
      '  remove <host>        revoke one site',
      '  apply                re-derive both firewall sets from the policy file',
      '  toolchain on|off     open or close the software-source route (GitHub and',
      '                       npm). It does NOT close skill installation: the skill',
      '                       hub shares an address with openclaw.ai, a permanent',
      '                       base host this switch does not cover. Never affects',
      '                       the AI provider route, which lives in another set.',
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
    if (!p.ok) {
      return out({
        ok: false, code: 'EPOLICY', error: p.error, allow: [], live: liveState(),
        // An unreadable policy denies, so reporting the switch as ON would draw
        // it in the wrong position at exactly the moment it matters.
        toolchain: { enabled: false, live: toolchainLive(), unreadable: true },
      });
    }
    return out({
      ok: true,
      allow: currentAllow(p.raw),
      live: liveState(),
      toolchain: { enabled: toolchainEnabled(p.raw), live: toolchainLive(), unreadable: false },
    });
  }

  if (cmd === 'apply') {
    const r = applyPolicy();
    const t = applyToolchain();
    if (!r.ok) return out({ ok: false, code: 'EAPPLY', error: r.error });
    if (!t.ok) return out({ ok: false, code: 'EAPPLYTOOLCHAIN', error: t.error });
    return out({
      ok: true, detail: [r.detail, t.detail].filter(Boolean).join(' | '), live: liveState(),
      toolchain: { live: toolchainLive() },
    });
  }

  if (cmd === 'toolchain') {
    const want = String(rest[0] == null ? '' : rest[0]).trim().toLowerCase();
    if (want !== 'on' && want !== 'off') {
      return out({ ok: false, code: 'EINVAL', error: "usage: clawfactory-fetchctl toolchain on|off" });
    }
    const enabled = want === 'on';

    // The SAME store lock the read-fetch writes and the send broker take. All
    // three read-modify-write one root-owned policy file, and without a shared
    // lock a simultaneous SMTP save and a toolchain switch could drop one of the
    // two writes. The one that gets dropped would be silent, and if it were the
    // send destination the user would lose something they believe they
    // authorized.
    const result = await lib.withStoreLock(cfg, async () => {
      const p = readPolicy();
      if (!p.ok) return { ok: false, code: 'EPOLICY', error: p.error };
      const before = toolchainEnabled(p.raw);
      if (before === enabled) return { ok: true, enabled, changed: false, note: `already ${want}` };
      writeToolchain(p.raw, enabled);
      return { ok: true, enabled, changed: true };
    });
    if (!result.ok) return out(result);

    // Apply unconditionally, even when the policy value did not change. The file
    // and the live set can disagree -- after a failed earlier apply, say -- and
    // the user asking for a state is a reasonable moment to make the firewall
    // match it rather than trusting that it already does.
    const applied = applyToolchain();
    if (!applied.ok) {
      // The file changed and the firewall did not. Switching OFF, that means the
      // route the user just closed is STILL OPEN, so this must not report
      // success under any circumstances.
      return out({ ok: false, code: 'EAPPLYTOOLCHAIN', error: applied.error, enabled, changed: result.changed });
    }
    const p2 = readPolicy();
    return out({
      ok: true,
      enabled: p2.ok ? toolchainEnabled(p2.raw) : enabled,
      changed: result.changed,
      note: result.note || null,
      detail: applied.detail,
      toolchain: { live: toolchainLive() },
      live: liveState(),
    });
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
