// send-lib.js -- shared helpers for the ClawFactory approval-gated send broker
// (v1 Guard 2). Loaded by the root daemon (clawfactory-sendd.js) and by the root
// CLI (clawfactory-sendctl.js). Both run as ROOT. The agent never loads this
// file, and the agent-facing client (clawfactory-send.js) deliberately does not
// require it: the client holds no credential, no policy, and no hashing logic
// that a caller could be tempted to trust.
//
// Installed to /usr/local/lib/clawfactory/send-lib.js (root:root 0644),
// alongside quarantine-lib.js whose shape this mirrors.
//
// STORE LAYOUT
//   /var/lib/clawfactory/send/                 root:root 0700
//     pending/<request-id>.json                the request record
//     staging/<request-id>/<basename>          root-owned copies of attachments
//     receipts/<request-id>.json               intent record, amended with result
//     .index.lock                              O_EXCL mutex shared by daemon + ctl
//
// THE INVARIANT THIS FILE EXISTS TO SERVE, AND IT IS PERMANENT
// No send path may ever run as uid 1000. The gateway runs as uid 1000 and
// therefore can never hold a send capability. Any future in-gateway email
// channel is FORBIDDEN, not merely blocked: the agent and the gateway are one
// security principal, so a gate placed there is a code path the agent can route
// around rather than a boundary it hits.

'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');

const CONFIG_PATH = '/etc/clawfactory/send.json';

const DEFAULTS = {
  socketPath: '/run/clawfactory/send.sock',
  store: '/var/lib/clawfactory/send',
  credentialPath: '/etc/clawfactory/send-credential.json',
  policyPath: '/etc/clawfactory/egress-policy.json',
  agentUser: 'clawuser',
  // Approval lifetime. Config-driven per spec 3.3. Ten minutes is long enough
  // for a user to read a real approval card and short enough that an unattended
  // pending request is not a standing capability.
  approvalTtlSeconds: 600,
  // Staging caps. Refuse loud when exceeded; never stage a partial set. Without
  // these, one request can fill /var/lib and take the box down, and a disk-full
  // broker is a broker that cannot write receipts.
  maxAttachmentBytes: 25 * 1024 * 1024,
  maxRequestBytes: 25 * 1024 * 1024,
  maxStagingBytes: 512 * 1024 * 1024,
  maxAttachments: 20,
  maxRecipients: 50,
  maxSubjectBytes: 998,
  maxBodyBytes: 5 * 1024 * 1024,
  // How long a consumed or denied record is kept before the GC reaps it. The
  // receipt is permanent; this only bounds the pending record.
  pendingRetentionHours: 24,
};

function loadConfig() {
  let onDisk = {};
  try {
    onDisk = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
  } catch {
    // Absent or unparseable config -> defaults. Unlike the quarantine config,
    // falling back here is safe in one direction only: every default is at
    // least as restrictive as anything the install would write.
  }
  return { ...DEFAULTS, ...(onDisk && typeof onDisk === 'object' ? onDisk : {}) };
}

const pendingDir = (cfg) => path.join(cfg.store, 'pending');
const stagingDir = (cfg) => path.join(cfg.store, 'staging');
const receiptsDir = (cfg) => path.join(cfg.store, 'receipts');
const lockPath = (cfg) => path.join(cfg.store, '.index.lock');
const pendingPath = (cfg, id) => path.join(pendingDir(cfg), `${id}.json`);
const stagingPathFor = (cfg, id) => path.join(stagingDir(cfg), id);
const receiptPath = (cfg, id) => path.join(receiptsDir(cfg), `${id}.json`);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Take the store mutex, run fn, release. O_EXCL create is the mutex; a lock
 * older than 30s is treated as stale and broken, so a killed daemon cannot
 * wedge approvals forever.
 *
 * ASYNC ON PURPOSE, and this matters more here than it did for quarantine. The
 * approve path re-enters the broker while an SMTP connection may be in flight;
 * a lock that blocked the event loop would stall every other in-flight request.
 */
async function withStoreLock(cfg, fn) {
  const lock = lockPath(cfg);
  const deadline = Date.now() + 30000;
  for (;;) {
    try {
      const fd = fs.openSync(lock, 'wx');
      fs.writeSync(fd, String(process.pid));
      fs.closeSync(fd);
      break;
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      let age = 0;
      try {
        age = Date.now() - fs.statSync(lock).mtimeMs;
      } catch {
        continue; // vanished between the failed create and the stat; retry
      }
      if (age > 30000) {
        try {
          fs.unlinkSync(lock);
        } catch {
          /* another process broke it first */
        }
        continue;
      }
      if (Date.now() > deadline) throw new Error('timed out waiting for the send store lock');
      await sleep(50);
    }
  }
  try {
    return await fn();
  } finally {
    try {
      fs.unlinkSync(lock);
    } catch {
      /* best effort */
    }
  }
}

// --- hashing ----------------------------------------------------------------

const sha256Buf = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

function sha256File(p) {
  const h = crypto.createHash('sha256');
  const fd = fs.openSync(p, 'r');
  try {
    const buf = Buffer.alloc(1024 * 1024);
    for (;;) {
      const n = fs.readSync(fd, buf, 0, buf.length, null);
      if (n <= 0) break;
      h.update(buf.subarray(0, n));
    }
  } finally {
    fs.closeSync(fd);
  }
  return h.digest('hex');
}

// Separators. Chosen from the C0 information-separator block so they cannot
// occur in an address, a filename, or a normalized subject.
const SEP_SECTION = '\x1E'; // between the six top-level sections
const SEP_ITEM = '\x1F'; // between fields inside one item
const SEP_ENTRY = '\x1D'; // between attachment entries

/**
 * THE CANONICAL PAYLOAD HASH. Reproducible by definition, and documented in the
 * close-out so a reviewer can recompute it by hand.
 *
 * SHA-256 over the UTF-8 encoding of six sections joined by SEP_SECTION:
 *
 *   1. the literal version tag "cfsend-v1"
 *   2. destination as "host:port", lowercased
 *   3. recipients: each rendered "<field>:<address>" with field in
 *      {to, cc, bcc}, address trimmed and lowercased, the set de-duplicated,
 *      sorted bytewise ascending, joined by SEP_ITEM
 *   4. subject, Unicode NFC normalized, leading/trailing whitespace trimmed
 *   5. the lowercase hex SHA-256 of the raw body bytes
 *   6. attachments: each rendered "<basename>SEP_ITEM<size>SEP_ITEM<sha256 of
 *      the STAGED copy>", entries sorted bytewise ascending, joined by SEP_ENTRY
 *
 * WHY EACH CHOICE
 * - Tagging recipients with their field means moving an address from Bcc to To
 *   changes the hash, which is a change the user must re-approve.
 * - Sorting means a reordering does not void an approval, but any change of
 *   membership, name, size or content does.
 * - The body is included as a digest rather than inline because the hash record
 *   is written to receipts and receipts are content-minimized.
 * - Attachment digests are taken over the STAGED copy, never the on-disk
 *   original. That is the whole point: the bytes the user approved and the
 *   bytes that go out are the same bytes, not the same path.
 */
function canonicalPayload(p) {
  const dest = `${String(p.destination.host).toLowerCase()}:${Number(p.destination.port)}`;

  const rcpt = [];
  for (const field of ['to', 'cc', 'bcc']) {
    for (const addr of p.recipients[field] || []) {
      rcpt.push(`${field}:${String(addr).trim().toLowerCase()}`);
    }
  }
  const recipients = [...new Set(rcpt)].sort().join(SEP_ITEM);

  const subject = String(p.subject || '')
    .normalize('NFC')
    .trim();

  const attachments = (p.attachments || [])
    .map((a) => [a.name, String(a.size), a.sha256].join(SEP_ITEM))
    .sort()
    .join(SEP_ENTRY);

  const canonical = [
    'cfsend-v1',
    dest,
    recipients,
    subject,
    p.bodySha256,
    attachments,
  ].join(SEP_SECTION);

  return { canonical, hash: sha256Buf(Buffer.from(canonical, 'utf8')) };
}

// --- policy -----------------------------------------------------------------

/**
 * The egress policy file. One root-owned file, two sections, both enforced but
 * by different mechanisms and with different strengths:
 *   read_fetch   -- destinations the agent may fetch from. Guard 3 enforces it
 *                   in the FIREWALL, by rebuilding the nft set read_fetch_ipv4
 *                   from this list. Written only by clawfactory-fetchctl.js,
 *                   which takes the same store lock this file's helpers use.
 *   send_actions -- approval-gated destinations. Guard 2 enforces this one in
 *                   the BROKER, as described below.
 *
 * ENFORCEMENT NOTE, and it is load-bearing for the close-out. Destination
 * scoping for the broker is enforced HERE, in root-owned broker code reading a
 * root-owned file. It is NOT enforced by nftables and must never be described
 * that way. The chain's first rule is `meta skuid != 1000 return`, which leaves
 * every non-1000 uid unfiltered by construction, so the broker's ability to
 * reach SMTP is emergent rather than granted. There is no firewall exemption
 * for the broker, and Guard 2 must not add one.
 *
 * It is still structural with respect to the AGENT, because the agent cannot
 * modify root-owned code or a root-owned policy file. It is broker-enforced,
 * not firewall-enforced.
 */
function loadPolicy(cfg) {
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(cfg.policyPath, 'utf8'));
  } catch (e) {
    // Fail closed. No policy means no permitted destination, not "any".
    return { ok: false, error: `cannot read egress policy ${cfg.policyPath}: ${e.message}`, sendActions: [] };
  }
  const sendActions = Array.isArray(raw.send_actions) ? raw.send_actions : [];
  return { ok: true, policy: raw, sendActions };
}

/** Exact host match, exact port match. No wildcards, no suffix matching: a
 *  wildcard in a send destination is an exfiltration channel with a nice name. */
function findSendDestination(cfg, host, port) {
  const { sendActions } = loadPolicy(cfg);
  const h = String(host || '').toLowerCase();
  const p = Number(port);
  return (
    sendActions.find(
      (d) => d && d.protocol === 'smtp' && String(d.host).toLowerCase() === h && Number(d.port) === p,
    ) || null
  );
}

/**
 * Authorize exactly one send destination, replacing whatever was there.
 *
 * Called only from the credential-set path. Configuring SMTP IS the act that
 * authorizes its destination, which keeps the two from drifting apart: there is
 * no way to end up with a credential pointing somewhere the policy does not
 * permit, and no way to leave a stale destination authorized after the user
 * repoints their mail.
 *
 * The read_fetch section is preserved untouched. Guard 3 owns it, and its writer
 * takes the same store lock, so neither side can drop the other's section.
 */
function setSendDestination(cfg, host, port) {
  let raw = {};
  try {
    raw = JSON.parse(fs.readFileSync(cfg.policyPath, 'utf8'));
  } catch {
    raw = { version: 1, read_fetch: { allow: [] } };
  }
  raw.send_actions = [
    {
      protocol: 'smtp',
      host: String(host).toLowerCase(),
      port: Number(port),
      requiresApproval: true,
      authorizedAt: new Date().toISOString(),
    },
  ];
  const tmp = `${cfg.policyPath}.tmp`;
  const fd = fs.openSync(tmp, 'w', 0o644);
  try {
    fs.writeSync(fd, JSON.stringify(raw, null, 2));
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, cfg.policyPath);
  fs.chownSync(cfg.policyPath, 0, 0);
  fs.chmodSync(cfg.policyPath, 0o644);
  return raw.send_actions[0];
}

// --- credential -------------------------------------------------------------

/**
 * Read the SMTP credential. Root only, and the mode is verified rather than
 * assumed: a credential file that has drifted to group- or world-readable is
 * refused outright, because at that point clawuser may already have read it and
 * continuing would be pretending otherwise.
 *
 * 0600 root:root, not 0644 and not 0444. Unlike quarantine.json, nothing
 * agent-side ever needs to read this.
 */
function readCredential(cfg) {
  let st;
  try {
    st = fs.statSync(cfg.credentialPath);
  } catch {
    return { ok: false, code: 'ENOCRED', error: 'no SMTP credential is configured' };
  }
  if (st.uid !== 0 || st.gid !== 0) {
    return { ok: false, code: 'EPERM', error: `${cfg.credentialPath} must be owned root:root` };
  }
  if (st.mode & 0o077) {
    return {
      ok: false,
      code: 'EPERM',
      error: `${cfg.credentialPath} is mode ${(st.mode & 0o777).toString(8)}; refusing to use a credential readable beyond root`,
    };
  }
  try {
    const c = JSON.parse(fs.readFileSync(cfg.credentialPath, 'utf8'));
    if (!c.host || !c.port || !c.username || !c.password || !c.from) {
      return { ok: false, code: 'EINVAL', error: 'credential is missing a required field' };
    }
    return { ok: true, credential: c };
  } catch (e) {
    return { ok: false, code: 'EINVAL', error: `credential unreadable: ${e.message}` };
  }
}

/** What Studio is allowed to see. Never the secret, not even masked back to the
 *  renderer: a mask still confirms length and prefix. */
function credentialSummary(cfg) {
  const r = readCredential(cfg);
  if (!r.ok) return { configured: false, reason: r.code };
  return {
    configured: true,
    from: r.credential.from,
    host: r.credential.host,
    port: r.credential.port,
    username: r.credential.username,
  };
}

function writeCredential(cfg, cred) {
  const dir = path.dirname(cfg.credentialPath);
  fs.mkdirSync(dir, { recursive: true, mode: 0o755 });
  // Create with the final mode from the outset. Writing 0644 and chmod'ing
  // afterwards leaves a window in which the secret is world-readable.
  const fd = fs.openSync(cfg.credentialPath, 'w', 0o600);
  try {
    fs.writeSync(fd, JSON.stringify(cred, null, 2));
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.chownSync(cfg.credentialPath, 0, 0);
  fs.chmodSync(cfg.credentialPath, 0o600);
}

// --- records ----------------------------------------------------------------

function newRequestId() {
  return `${new Date().toISOString().replace(/[:.]/g, '-')}-${crypto.randomBytes(4).toString('hex')}`;
}

function readPending(cfg, id) {
  try {
    return JSON.parse(fs.readFileSync(pendingPath(cfg, id), 'utf8'));
  } catch {
    return null;
  }
}

function writePending(cfg, rec) {
  fs.mkdirSync(pendingDir(cfg), { recursive: true, mode: 0o700 });
  const p = pendingPath(cfg, rec.id);
  const tmp = `${p}.tmp`;
  const fd = fs.openSync(tmp, 'w', 0o600);
  try {
    fs.writeSync(fd, JSON.stringify(rec, null, 2));
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, p);
}

function listPending(cfg) {
  let names = [];
  try {
    names = fs.readdirSync(pendingDir(cfg)).filter((n) => n.endsWith('.json'));
  } catch {
    return [];
  }
  return names
    .map((n) => readPending(cfg, n.slice(0, -5)))
    .filter(Boolean)
    .sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)));
}

/**
 * RECEIPT ORDERING, corrected per the consolidated addendum section 6.
 *
 * v3 said a send that cannot write its receipt does not execute. A receipt
 * written after the send cannot enforce that. So an INTENT record is written and
 * fsync'ed BEFORE the SMTP connection opens, and amended with the result
 * afterwards. This is the only ordering where the rule is load-bearing, and it
 * additionally leaves a crash-consistent record of an in-flight send, which the
 * original ordering loses entirely.
 *
 * The intent record lives in the same root-owned store and never anywhere
 * clawuser can observe, because it carries recipients and subject before an
 * approval decision exists.
 *
 * Content-minimized: hashes and references, never the body, never the
 * credential.
 */
function writeIntent(cfg, rec) {
  fs.mkdirSync(receiptsDir(cfg), { recursive: true, mode: 0o700 });
  const intent = {
    id: rec.id,
    intentAt: new Date().toISOString(),
    payloadHash: rec.payloadHash,
    destination: rec.destination,
    recipients: rec.recipients,
    subject: rec.subject,
    attachments: (rec.attachments || []).map((a) => ({ name: a.name, size: a.size, sha256: a.sha256 })),
    approval: {
      state: rec.approval ? rec.approval.state : 'none',
      boundHash: rec.approval ? rec.approval.boundHash : null,
      decidedAt: rec.approval ? rec.approval.decidedAt : null,
    },
    requestedBy: rec.requestedBy,
    result: null,
    host: os.hostname(),
  };
  const p = receiptPath(cfg, rec.id);
  const tmp = `${p}.tmp`;
  const fd = fs.openSync(tmp, 'w', 0o600);
  try {
    fs.writeSync(fd, JSON.stringify(intent, null, 2));
    // fsync, not just close. The rule is that the record exists on disk before
    // the connection opens; a buffered write does not satisfy that.
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, p);
  return intent;
}

function amendReceipt(cfg, id, result) {
  let intent;
  try {
    intent = JSON.parse(fs.readFileSync(receiptPath(cfg, id), 'utf8'));
  } catch {
    return false;
  }
  intent.result = { ...result, at: new Date().toISOString() };
  const p = receiptPath(cfg, id);
  const tmp = `${p}.tmp`;
  const fd = fs.openSync(tmp, 'w', 0o600);
  try {
    fs.writeSync(fd, JSON.stringify(intent, null, 2));
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, p);
  return true;
}

// --- staging ----------------------------------------------------------------

function stagingUsedBytes(cfg) {
  let total = 0;
  const root = stagingDir(cfg);
  let ids = [];
  try {
    ids = fs.readdirSync(root);
  } catch {
    return 0;
  }
  for (const id of ids) {
    let files = [];
    try {
      files = fs.readdirSync(path.join(root, id));
    } catch {
      continue;
    }
    for (const f of files) {
      try {
        total += fs.statSync(path.join(root, id, f)).size;
      } catch {
        /* raced with the GC */
      }
    }
  }
  return total;
}

function purgeStaging(cfg, id) {
  try {
    fs.rmSync(stagingPathFor(cfg, id), { recursive: true, force: true });
    return true;
  } catch {
    return false;
  }
}

const isExpired = (rec, now = Date.now()) => now >= Date.parse(rec.expiresAt);

// --- panel view state -------------------------------------------------------

/**
 * When the user last looked at the approvals panel.
 *
 * This exists because of a defect found by using the product: an approval window
 * lapsed while the user was away and the panel then showed "Nothing waiting", so
 * an expired request and one that was never queued looked identical. The fix is
 * anchored to the user's ABSENCE rather than to a clock, which is why the mark
 * is a last-viewed timestamp and not a second, shorter retention window.
 *
 * Carries no security weight whatsoever. An expired record is inert: its staging
 * is already purged and handleApprove refuses it on state. This only decides
 * what a panel draws, and it is kept root-owned purely because it lives in the
 * root-owned store next to records the agent must not read.
 */
const viewStatePath = (cfg) => path.join(cfg.store, '.view-state.json');

function readViewState(cfg) {
  try {
    const raw = JSON.parse(fs.readFileSync(viewStatePath(cfg), 'utf8'));
    return { lastViewedAt: raw && raw.lastViewedAt ? String(raw.lastViewedAt) : null };
  } catch {
    // Never viewed, or unreadable. Showing everything unseen is the harmless
    // direction to fail in: the cost is one redundant card, and the cost of the
    // other direction is the silence this was written to fix.
    return { lastViewedAt: null };
  }
}

function writeViewState(cfg, lastViewedAt) {
  const p = viewStatePath(cfg);
  const tmp = `${p}.tmp`;
  const fd = fs.openSync(tmp, 'w', 0o600);
  try {
    fs.writeSync(fd, `${JSON.stringify({ lastViewedAt }, null, 2)}\n`);
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, p);
  return { lastViewedAt };
}

module.exports = {
  CONFIG_PATH,
  DEFAULTS,
  loadConfig,
  pendingDir,
  stagingDir,
  receiptsDir,
  pendingPath,
  stagingPathFor,
  receiptPath,
  withStoreLock,
  sha256Buf,
  sha256File,
  canonicalPayload,
  loadPolicy,
  findSendDestination,
  setSendDestination,
  readCredential,
  credentialSummary,
  writeCredential,
  newRequestId,
  readPending,
  writePending,
  listPending,
  writeIntent,
  amendReceipt,
  stagingUsedBytes,
  purgeStaging,
  isExpired,
  viewStatePath,
  readViewState,
  writeViewState,
  SEP_SECTION,
  SEP_ITEM,
  SEP_ENTRY,
};
