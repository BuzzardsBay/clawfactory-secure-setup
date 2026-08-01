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
  // Aggregate ceiling on everything held at once. maxEntryBytes alone does not
  // bound the store: thirty days of ordinary deletes, or an agent quarantining
  // in a loop, fills /var/lib one under-cap entry at a time.
  //
  // On overflow the broker REFUSES LOUD. It does not evict (that would silently
  // break the 30-day promise) and it does not fall through to the real rm (that
  // would silently destroy the file). Both failure modes are worse than a
  // delete that does not happen.
  maxStoreBytes: 10 * 1024 * 1024 * 1024,
  // Floor on free space for the filesystem the store sits on, checked after
  // accounting for the incoming payload. This is the backstop that actually
  // protects the host: maxStoreBytes bounds what WE hold, this bounds what is
  // left for everything else on the disk.
  minFreeBytes: 2 * 1024 * 1024 * 1024,
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

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Take the index mutex, run fn, release. O_EXCL create is the mutex; a lock
 * older than 30s is considered stale (a killed daemon must not wedge deletes
 * forever) and is broken.
 *
 * ASYNC ON PURPOSE. This used to back off with Atomics.wait, which blocks the
 * whole event loop. That was harmless while the only caller was a broker that
 * handles one rare request at a time, but this shape is being cloned for the
 * send broker, where a blocked loop would stall in-flight approvals. Await the
 * backoff so the process stays responsive under contention.
 */
async function withIndexLock(cfg, fn) {
  const lp = lockPath(cfg);
  const deadline = Date.now() + 10_000;
  let fd = null;
  for (;;) {
    try {
      fd = fs.openSync(lp, 'wx');
      break;
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      if (Date.now() > deadline) throw new Error('quarantine index is locked');
      let stale = false;
      try {
        stale = Date.now() - fs.statSync(lp).mtimeMs > 30_000;
      } catch {
        // Lock vanished under us; retry the create straight away.
      }
      if (stale) {
        try {
          fs.unlinkSync(lp);
        } catch {
          /* someone else broke it first */
        }
      }
      // Yield even on the fast path so a wedged lock cannot spin the CPU.
      await sleep(stale ? 0 : 50);
    }
  }
  try {
    return await fn();
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
 * Bytes currently held, summed from the index rather than measured on disk.
 *
 * Measuring the real tree would mean walking up to maxStoreBytes of files on
 * every single delete. The index sum is what the 30-day promise is actually
 * made of, and it is exact for every entry the store admits to holding. The
 * thing it can miss is an orphaned payload whose index write was lost -- rare,
 * reaped by the gc sweep, and covered anyway by the free-space floor below,
 * which measures the filesystem for real.
 */
function storeUsedBytes(records) {
  return records.reduce((n, r) => n + (Number.isFinite(r.sizeBytes) ? r.sizeBytes : 0), 0);
}

/** Free bytes on the filesystem holding the store, or null if unmeasurable. */
function storeFreeBytes(cfg) {
  try {
    const st = fs.statfsSync(cfg.store);
    return st.bsize * st.bavail;
  } catch {
    return null;
  }
}

/** Human sizes for user-facing refusals. One decimal place, no false precision. */
function humanBytes(n) {
  if (!Number.isFinite(n)) return 'unknown';
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  const tb = 1024 * gb;
  if (n >= tb) return `${(n / tb).toFixed(1)} TB`;
  if (n >= gb) return `${(n / gb).toFixed(1)} GB`;
  if (n >= mb) return `${Math.round(n / mb)} MB`;
  return `${n} bytes`;
}

/**
 * Would admitting `incomingBytes` breach either ceiling? Returns null when the
 * move may proceed, or a { code, error } the caller returns verbatim.
 *
 * Deliberately has no eviction path and no soft mode. See maxStoreBytes.
 */
function capacityRefusal(cfg, records, incomingBytes) {
  const used = storeUsedBytes(records);
  const max = Number.isFinite(cfg.maxStoreBytes) ? cfg.maxStoreBytes : DEFAULTS.maxStoreBytes;
  if (used + incomingBytes > max) {
    return {
      code: 'ENOSPC',
      error:
        `the ClawFactory quarantine store is full (${humanBytes(used)} held of a ` +
        `${humanBytes(max)} limit, and this needs ${humanBytes(incomingBytes)}). ` +
        `Nothing was deleted. Open Studio > Recently deleted and restore or clear ` +
        `items, then try again.`,
    };
  }

  const free = storeFreeBytes(cfg);
  const floor = Number.isFinite(cfg.minFreeBytes) ? cfg.minFreeBytes : DEFAULTS.minFreeBytes;
  // Unmeasurable free space is not a licence to proceed: refuse rather than
  // risk filling the disk the whole box runs on.
  if (free === null) {
    return {
      code: 'ENOSPC',
      error:
        `cannot measure free space on the ClawFactory quarantine store. ` +
        `Nothing was deleted. Check disk health, then try again.`,
    };
  }
  if (free - incomingBytes < floor) {
    return {
      code: 'ENOSPC',
      error:
        `only ${humanBytes(free)} free on the ClawFactory quarantine disk, and holding ` +
        `this needs ${humanBytes(incomingBytes)} with a ${humanBytes(floor)} reserve kept ` +
        `for the rest of the system. Nothing was deleted. Free up disk space, or open ` +
        `Studio > Recently deleted and clear items, then try again.`,
    };
  }
  return null;
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
  storeUsedBytes,
  storeFreeBytes,
  humanBytes,
  capacityRefusal,
  copyPreservingLinks,
  chownRootRecursive,
  isUnder,
};
