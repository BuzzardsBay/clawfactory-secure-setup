#!/usr/bin/env node
// clawfactory-quarantine-rm.js — the `rm` the AGENT sees.
//
// Installed TWICE, deliberately:
//   1. /usr/bin/rm, via dpkg-divert (the real binary moves to /usr/bin/rm.real)
//   2. /usr/local/lib/clawfactory/execbin/rm, kept as defence in depth
//
// WHY THE DIVERT, added 2026-08-10
// PATH-based interception alone DID NOT WORK, and validation on a clean box
// caught it. `tools.exec.pathPrepend` does put execbin on the agent's PATH, but
// OpenClaw prepends the directory of the running node binary AFTER applying it,
// and node lives in /usr/bin alongside the real rm. The agent's PATH came out as
// `/usr/bin:/usr/local/lib/clawfactory/execbin:/usr/bin:...`, so `rm` resolved
// to /usr/bin/rm every time. A real agent turn asked to delete a file in a
// granted workspace destroyed it permanently, and then told the user it had been
// safely quarantined for 30 days. No config value can win that race, because the
// directory OpenClaw prepends is chosen from the node binary's own location.
//
// Diverting the name itself removes PATH from the question entirely.
//
// WHAT THIS IS AND IS NOT
// With the divert, routing is STRUCTURAL for uid 1000 with respect to the NAME
// `rm`: /bin/rm resolves here too, because /bin is a usrmerge symlink to
// /usr/bin. It still does not catch `unlink`, `find -delete`, `fs.rmSync`,
// `os.remove`, or truncation via `>`, and it must not be described as if it
// did. The other STRUCTURAL half is the broker: once a file is held, it is held.
//
// ROOT IS OUT OF SCOPE BY DESIGN. See the uid check in main().
//
// SCOPE: only paths under the configured quarantine roots (default
// /workspaces -- the granted-folder mounts, i.e. the user's own files) are
// routed. Everything else is handed to the real rm unchanged, so builds,
// package managers and scratch files behave exactly as before. Scope is
// computed here to avoid a socket round trip per argument; the broker
// re-derives it authoritatively and is the one that decides.

'use strict';

const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// The real rm, AFTER the dpkg-divert performed by install-quarantine.sh.
//
// This must never resolve back to this file. /bin is a usrmerge symlink to
// /usr/bin, so once the wrapper is installed at /usr/bin/rm the old constant
// '/bin/rm' pointed at the wrapper itself and every pass-through would have
// forked bombs of recursive rm. Resolve the diverted binary first and fall back
// only to paths that cannot be this file.
const REAL_RM = (() => {
  for (const c of ['/usr/bin/rm.real', '/usr/bin/rm.distrib', '/bin/rm.real']) {
    try { fs.accessSync(c, fs.constants.X_OK); return c; } catch { /* next */ }
  }
  // Not diverted (execbin-only install). /bin/rm is the genuine binary then.
  return '/bin/rm';
})();
const CONFIG_PATH = '/etc/clawfactory/quarantine.json';
const DEFAULT_SOCKET = '/run/clawfactory/quarantine.sock';
const DEFAULT_ROOTS = ['/workspaces'];
const DEFAULT_SKIP = ['node_modules', '.git'];

function loadConfig() {
  try {
    const c = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    return {
      socketPath: c.socketPath || DEFAULT_SOCKET,
      quarantineRoots: Array.isArray(c.quarantineRoots) ? c.quarantineRoots : DEFAULT_ROOTS,
      skipSegments: Array.isArray(c.skipSegments) ? c.skipSegments : DEFAULT_SKIP,
    };
  } catch {
    return { socketPath: DEFAULT_SOCKET, quarantineRoots: DEFAULT_ROOTS, skipSegments: DEFAULT_SKIP };
  }
}
const cfg = loadConfig();

function realRm(args) {
  const r = spawnSync(REAL_RM, args, { stdio: 'inherit' });
  return typeof r.status === 'number' ? r.status : 1;
}

// --- argv ------------------------------------------------------------------

/** Split rm's argv into flags and targets, honouring `--` and clustered shorts. */
function parseArgs(argv) {
  const flags = [];
  const targets = [];
  let recursive = false;
  let force = false;
  let endOfFlags = false;

  for (const a of argv) {
    if (endOfFlags || a === '-' || !a.startsWith('-')) {
      targets.push(a);
      continue;
    }
    if (a === '--') {
      endOfFlags = true;
      flags.push(a);
      continue;
    }
    flags.push(a);
    if (a.startsWith('--')) {
      if (a === '--recursive') recursive = true;
      if (a === '--force') force = true;
    } else {
      // Clustered shorts: -rf, -fr, -rvf ...
      if (a.includes('r') || a.includes('R')) recursive = true;
      if (a.includes('f')) force = true;
    }
  }
  return { flags, targets, recursive, force };
}

// --- scope -----------------------------------------------------------------

function isUnder(parent, child) {
  const a = path.resolve(parent);
  const b = path.resolve(child);
  return b === a || b.startsWith(a.endsWith('/') ? a : `${a}/`);
}

/** Resolve the parent through symlinks so scope matches what the broker sees. */
function resolveLeaf(p) {
  const abs = path.resolve(p);
  try {
    return path.join(fs.realpathSync(path.dirname(abs)), path.basename(abs));
  } catch {
    return abs;
  }
}

function inScope(resolved) {
  if (!cfg.quarantineRoots.some((r) => isUnder(r, resolved))) return false;
  const skip = new Set(cfg.skipSegments);
  return !resolved.split('/').some((s) => skip.has(s));
}

/** lstat, not existsSync: a BROKEN symlink is a real directory entry the user
 *  may want back, and existsSync follows the link and reports it missing --
 *  which would quietly route it past the broker to a permanent delete. */
function entryExists(p) {
  try {
    fs.lstatSync(p);
    return true;
  } catch {
    return false;
  }
}

// --- broker ----------------------------------------------------------------

function ask(req) {
  return new Promise((resolve) => {
    const sock = net.createConnection(cfg.socketPath);
    let buf = '';
    const done = (res) => {
      sock.destroy();
      resolve(res);
    };
    sock.setEncoding('utf8');
    sock.setTimeout(120_000, () => done({ ok: false, error: 'quarantine service timed out' }));
    sock.on('connect', () => sock.write(`${JSON.stringify(req)}\n`));
    sock.on('data', (d) => {
      buf += d;
      const nl = buf.indexOf('\n');
      if (nl >= 0) {
        try {
          done(JSON.parse(buf.slice(0, nl)));
        } catch (e) {
          done({ ok: false, error: `bad reply from quarantine service: ${e.message}` });
        }
      }
    });
    sock.on('error', (e) =>
      done({ ok: false, unreachable: true, error: `quarantine service unreachable: ${e.message}` }),
    );
  });
}

// --- main ------------------------------------------------------------------

async function main() {
  const argv = process.argv.slice(2);

  // ROOT PASSES THROUGH, ALWAYS AND FIRST.
  //
  // Since the dpkg-divert this wrapper now sits behind, EVERY rm on the system
  // reaches this file: apt maintainer scripts, systemd units, the installer
  // itself, and anything an administrator types. Routing those through a node
  // process and a socket would put the whole distro's delete path behind a
  // service that can be down, which is a far worse failure than the one this
  // guard prevents.
  //
  // The guard's subject is the AGENT (uid 1000). Root was never in scope: the
  // threat model has always been "the agent deletes the user's files", and a
  // root that wanted to bypass this could simply call the diverted binary. So
  // root keeps the stock behaviour, exactly as before the divert, and the
  // system cannot be bricked by a broker outage.
  if (typeof process.getuid === 'function' && process.getuid() === 0) {
    process.exit(realRm(argv));
  }

  // Let the real rm own its own help/version text rather than inventing ours.
  if (argv.some((a) => a === '--help' || a === '--version')) process.exit(realRm(argv));

  const { flags, targets, recursive, force } = parseArgs(argv);
  if (targets.length === 0) process.exit(realRm(argv));

  const routed = [];
  const passThrough = [];
  for (const t of targets) {
    const resolved = resolveLeaf(t);
    // A target that is not there goes to the real rm so its -f semantics and
    // its exact error text stay canonical.
    if (inScope(resolved) && entryExists(resolved)) routed.push({ arg: t, resolved });
    else passThrough.push(t);
  }

  let status = 0;

  for (const { arg, resolved } of routed) {
    const res = await ask({
      op: 'delete',
      path: resolved,
      recursive,
      taskId: process.env.OPENCLAW_TASK_ID || process.env.OPENCLAW_SESSION_ID || null,
    });

    if (res.ok && res.quarantined) {
      process.stderr.write(
        `rm: '${arg}' moved to ClawFactory quarantine (restorable from Studio > Recently deleted)\n`,
      );
      continue;
    }
    // The broker declared it out of scope -- it is authoritative, so honour that
    // and delete for real.
    if (res.ok && res.quarantined === false) {
      passThrough.push(arg);
      continue;
    }
    if (res.code === 'ENOENT' && force) continue;

    // FAIL LOUD, DO NOT FALL BACK. Falling through to the real rm here would
    // turn every broker outage into a silent permanent delete of exactly the
    // files this guard exists to protect. A failed delete is recoverable; a
    // silent one is not.
    status = 1;
    process.stderr.write(`rm: cannot remove '${arg}': ${res.error || res.code || 'quarantine failed'}\n`);
  }

  if (passThrough.length > 0) {
    const rc = realRm([...flags, ...passThrough]);
    if (rc !== 0) status = rc;
  }
  process.exit(status);
}

main().catch((e) => {
  process.stderr.write(`rm: quarantine wrapper failed: ${e.message}\n`);
  process.exit(1);
});
