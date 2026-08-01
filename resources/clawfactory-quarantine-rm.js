#!/usr/bin/env node
// clawfactory-quarantine-rm.js — the `rm` the AGENT sees.
//
// Installed as /usr/local/lib/clawfactory/execbin/rm, and that directory is put
// on the front of the exec tool's PATH via `tools.exec.pathPrepend`. OpenClaw
// rejects agent-supplied env.PATH overrides for host execution, so the agent
// cannot shove this off the front of its own PATH from inside a turn.
//
// WHAT THIS IS AND IS NOT
// This is the ROUTING half of the guard, and routing is ADVISORY. It catches
// `rm <path>`, which is how a delete is actually expressed ~always. It does not
// catch `/bin/rm`, `unlink`, `find -delete`, `fs.rmSync`, `os.remove`, or
// truncation via `>`. Anyone reading this file should not claim otherwise. The
// STRUCTURAL half is the broker: once a file is held, it is held.
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

const REAL_RM = '/bin/rm';
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
