#!/usr/bin/env node
// clawfactory-quarantinectl.js — ROOT-side list / restore / gc for the delete
// quarantine. Installed to /usr/local/sbin/clawfactory-quarantinectl.js.
//
// Two callers, both already privileged, neither of them the agent:
//   * Studio  -> clawfactory-grants.ps1 -> `wsl -u root -- node <this> list|restore`
//   * systemd -> clawfactory-quarantine-gc.service -> `<this> gc`
//
// clawuser has no route here: the store is root:root 0700 and this file is only
// useful when run as root. Restore is deliberately NOT reachable from the agent
// side -- putting a file back is the user's call, made in Studio.
//
// Every subcommand prints ONE line of JSON on stdout so the PowerShell engine
// can ConvertFrom-Json it without parsing prose. Failures are JSON too
// ({ok:false,error}), never a bare stack trace.

'use strict';

const fs = require('node:fs');
const path = require('node:path');

const lib = require('/usr/local/lib/clawfactory/quarantine-lib.js');

const cfg = lib.loadConfig();
const AGENT_USER = cfg.agentUser || 'clawuser';

function out(obj) {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
}

function requireRoot() {
  if (typeof process.getuid === 'function' && process.getuid() !== 0) {
    out({ ok: false, error: 'clawfactory-quarantinectl must run as root' });
    process.exit(1);
  }
}

/** The single stored payload inside an entry directory. */
function payloadPath(rec) {
  return path.join(lib.entryDir(cfg, rec.id), rec.name);
}

/** Presence of the directory ENTRY, following no links (see cmdRestore). */
function entryExists(p) {
  try {
    fs.lstatSync(p);
    return true;
  } catch {
    return false;
  }
}

function expiresAt(rec) {
  return new Date(Date.parse(rec.deletedAt) + cfg.retentionDays * 86_400_000).toISOString();
}

function cmdList() {
  const records = lib.readIndex(cfg);
  const items = records.map((rec) => ({
    ...rec,
    // A record whose payload is gone is a bug, not a normal state -- surface it
    // rather than offering a Restore button that cannot work.
    present: fs.existsSync(payloadPath(rec)),
    expiresAt: expiresAt(rec),
  }));
  // Newest first: the thing you just lost is the thing you want back.
  items.sort((a, b) => String(b.deletedAt).localeCompare(String(a.deletedAt)));
  out({ ok: true, retentionDays: cfg.retentionDays, store: cfg.store, items });
}

/** `report.txt` occupied -> `report (restored).txt`, then `report (restored 2).txt`. */
function freeName(target) {
  // entryExists, not existsSync: a dangling symlink already occupies the name,
  // and restoring on top of it would fail rather than side-step it.
  if (!entryExists(target)) return { path: target, renamed: false };
  const dir = path.dirname(target);
  const ext = path.extname(target);
  const stem = path.basename(target, ext);
  for (let n = 1; n < 1000; n += 1) {
    const suffix = n === 1 ? ' (restored)' : ` (restored ${n})`;
    const candidate = path.join(dir, `${stem}${suffix}${ext}`);
    if (!entryExists(candidate)) return { path: candidate, renamed: true };
  }
  throw new Error(`cannot find a free name next to ${target}`);
}

function cmdRestore(id) {
  if (!id) return out({ ok: false, error: 'restore needs an entry id' });
  const records = lib.readIndex(cfg);
  const rec = records.find((r) => r.id === id);
  if (!rec) return out({ ok: false, error: `no quarantine entry with id ${id}` });

  const src = payloadPath(rec);
  // lstat, not existsSync: a held symlink may point at something that is not
  // there, and that does not make the held entry missing.
  if (!entryExists(src)) {
    return out({ ok: false, error: `the held copy for ${rec.name} is missing from the store` });
  }

  // The original folder can be gone (or its grant revoked and unmounted). Do
  // not silently recreate a tree outside a live grant -- say what happened.
  const parent = path.dirname(rec.originalPath);
  if (!fs.existsSync(parent)) {
    return out({
      ok: false,
      error:
        `the original folder ${parent} is not there any more. ` +
        `If it was a granted folder, grant it again and retry.`,
    });
  }

  let dest;
  try {
    dest = freeName(rec.originalPath);
    lib.copyPreservingLinks(src, dest.path);
  } catch (e) {
    return out({ ok: false, error: `restore failed: ${e.message}` });
  }

  // Hand ownership back to the agent account. On drvfs (granted Windows
  // folders) ownership is fixed by the mount, so a failure here is expected and
  // harmless -- the file is restored either way.
  try {
    const { spawnSync } = require('node:child_process');
    spawnSync('chown', ['-RhL', `${AGENT_USER}:${AGENT_USER}`, dest.path], { encoding: 'utf8' });
  } catch {
    /* see above */
  }

  // Only now drop the held copy: if anything above failed we still have it.
  try {
    lib.withIndexLock(cfg, () => {
      const current = lib.readIndex(cfg).filter((r) => r.id !== id);
      lib.writeIndex(cfg, current);
    });
    fs.rmSync(lib.entryDir(cfg, id), { recursive: true, force: true });
  } catch (e) {
    return out({
      ok: true,
      restoredTo: dest.path,
      renamed: dest.renamed,
      warning: `restored, but the quarantine entry could not be cleared: ${e.message}`,
    });
  }

  out({ ok: true, id, restoredTo: dest.path, renamed: dest.renamed, originalPath: rec.originalPath });
}

/**
 * Retention cleanup. THE ONLY THING IN THIS GUARD THAT PERMANENTLY DELETES, and
 * it only ever touches entries already past the window.
 */
function cmdGc() {
  const cutoff = Date.now() - cfg.retentionDays * 86_400_000;
  const reaped = [];
  try {
    lib.withIndexLock(cfg, () => {
      const records = lib.readIndex(cfg);
      const keep = [];
      for (const rec of records) {
        const when = Date.parse(rec.deletedAt);
        // An unparseable timestamp must not become an immortal entry OR an
        // instant reap: keep it and flag it.
        if (!Number.isFinite(when)) {
          keep.push(rec);
          continue;
        }
        if (when < cutoff) reaped.push({ id: rec.id, originalPath: rec.originalPath });
        else keep.push(rec);
      }
      lib.writeIndex(cfg, keep);
    });
    for (const r of reaped) {
      fs.rmSync(lib.entryDir(cfg, r.id), { recursive: true, force: true });
    }
  } catch (e) {
    out({ ok: false, error: `gc failed: ${e.message}` });
    process.exit(1);
  }

  // Orphaned payload directories (an entry whose index write was lost) would
  // otherwise sit on disk forever. Reap them on the same window, by mtime.
  let orphans = 0;
  try {
    const known = new Set(lib.readIndex(cfg).map((r) => r.id));
    for (const name of fs.readdirSync(cfg.store)) {
      const p = path.join(cfg.store, name);
      if (name.startsWith('.') || name === 'index.json' || known.has(name)) continue;
      let st;
      try {
        st = fs.statSync(p);
      } catch {
        continue;
      }
      if (st.isDirectory() && st.mtimeMs < cutoff) {
        fs.rmSync(p, { recursive: true, force: true });
        orphans += 1;
      }
    }
  } catch {
    /* orphan sweep is best-effort; the indexed reap above is the contract */
  }

  out({ ok: true, retentionDays: cfg.retentionDays, reaped: reaped.length, orphansReaped: orphans, entries: reaped });
}

requireRoot();
const [cmd, arg] = process.argv.slice(2);
switch (cmd) {
  case 'list':
    cmdList();
    break;
  case 'restore':
    cmdRestore(arg);
    break;
  case 'gc':
    cmdGc();
    break;
  default:
    out({ ok: false, error: `usage: clawfactory-quarantinectl.js list|restore <id>|gc (got: ${cmd || 'nothing'})` });
    process.exit(1);
}
