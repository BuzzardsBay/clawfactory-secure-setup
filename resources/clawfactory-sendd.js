#!/usr/bin/env node
// clawfactory-sendd.js -- the ROOT send broker (v1 Guard 2).
//
// Introduces an email send capability in order to gate it. There is no email
// send anywhere else in this product, and there must never be one at uid 1000.
//
// THE PERMANENT INVARIANT
// No send path may ever run as uid 1000. The gateway runs as uid 1000, so it can
// never hold a send capability, and any future in-gateway email channel is
// FORBIDDEN rather than merely blocked. The agent and the gateway are one
// security principal; a gate placed there is a code path the agent routes
// around, not a boundary it hits.
//
// TWO SOCKETS, DELIBERATELY DISJOINT
//   /run/clawfactory/send.sock        0660 root:clawuser   REQUEST channel
//       ping, send, status. Enqueues only. Cannot approve. This is the only
//       channel the agent can reach.
//   /run/clawfactory/send-admin.sock  0600 root:root       APPROVAL channel
//       list, preview, approve, deny, credential, gc. clawuser cannot connect:
//       the mode denies it. Studio reaches this through `wsl -u root`, never
//       through the agent socket, and never as uid 1000.
//
// WHY A ROOT BROKER HOLDING A CREDENTIAL IS NOT AN ESCALATION
// A root process that acts on request from a non-root caller is an escalation
// shape. The concrete risk is file read: the broker becoming a root-read
// primitive that mails out a root-only file. Guard 1's mechanism is reused and
// strengthened. Entitlement is not merely CHECKED as the agent, the attachment
// is READ as the agent: the copy into staging is performed by a setpriv child
// running at the agent uid, so the broker cannot read anything the caller could
// not have read itself, and there is no window between the check and the copy in
// which the path could be swapped.
//
// TRUST MODEL: the request socket is root:clawuser 0660, so the caller is the
// agent account by construction. There is no additional authentication and none
// is claimed. Entitlement is always re-derived at the AGENT uid regardless of
// who connected, so even a root caller on the request socket gets agent-level
// reach and no more.

'use strict';

const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const lib = require('/usr/local/lib/clawfactory/send-lib.js');
const smtp = require('/usr/local/lib/clawfactory/send-smtp.js');

const cfg = lib.loadConfig();
const AGENT_USER = cfg.agentUser || 'clawuser';
const ADMIN_SOCKET = cfg.adminSocketPath || '/run/clawfactory/send-admin.sock';
const KILLSWITCH = cfg.killSwitchPath || '/etc/clawfactory/send-killswitch';

function log(msg) {
  process.stdout.write(`[sendd] ${msg}\n`);
}

function resolveAgent() {
  const u = spawnSync('id', ['-u', AGENT_USER], { encoding: 'utf8' });
  const g = spawnSync('id', ['-g', AGENT_USER], { encoding: 'utf8' });
  if (u.status !== 0 || g.status !== 0) {
    log(`FATAL: agent account "${AGENT_USER}" not found`);
    process.exit(1);
  }
  const uid = Number(u.stdout.trim());
  if (uid === 0) {
    log('FATAL: agent account resolves to uid 0; refusing to run');
    process.exit(1);
  }
  return { uid, gid: Number(g.stdout.trim()) };
}
const AGENT = resolveAgent();

/** The kill switch. Presence of the file blocks every op and purges staging. */
function killSwitchActive() {
  try {
    fs.statSync(KILLSWITCH);
    return true;
  } catch {
    return false;
  }
}

// --- entitlement + staging --------------------------------------------------

/**
 * Would the agent account have been allowed to READ this path itself?
 * Explicit test first, for a clean refusal message. The authoritative answer is
 * the staged copy below, which performs the read AS the agent.
 */
function agentCouldRead(target) {
  const r = spawnSync(
    'setpriv',
    [`--reuid=${AGENT.uid}`, `--regid=${AGENT.gid}`, '--clear-groups', '/usr/bin/test', '-r', target],
    { encoding: 'utf8' },
  );
  return !r.error && r.status === 0;
}

/**
 * Copy one attachment into root-owned staging by READING IT AS THE AGENT.
 *
 * This is the heart of the escalation guard and of the TOCTOU fix at once:
 *   - The read runs at the agent uid, so a root-only file simply fails. The
 *     broker never lends its privilege out.
 *   - Because the check and the read are the same operation, there is no window
 *     in which the agent can swap the path for a symlink to something it could
 *     not read.
 *   - The bytes land in a 0700 root:root directory, so once staged the agent
 *     cannot alter them. That is what makes the approved bytes and the sent
 *     bytes the same bytes rather than the same name.
 */
function stageAttachment(id, srcPath, limitBytes) {
  const dir = lib.stagingPathFor(cfg, id);
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  fs.chownSync(dir, 0, 0);
  fs.chmodSync(dir, 0o700);

  const name = path.basename(srcPath);
  const dest = path.join(dir, name);

  const r = spawnSync(
    'setpriv',
    [`--reuid=${AGENT.uid}`, `--regid=${AGENT.gid}`, '--clear-groups', '/bin/cat', '--', srcPath],
    { encoding: 'buffer', maxBuffer: limitBytes + 1 },
  );
  if (r.error) {
    if (r.error.code === 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER') {
      return { ok: false, code: 'E2BIG', error: `${srcPath} exceeds the ${limitBytes}-byte attachment cap` };
    }
    return { ok: false, code: 'EIO', error: `cannot stage ${srcPath}: ${r.error.message}` };
  }
  if (r.status !== 0) {
    return { ok: false, code: 'EACCES', error: `permission denied reading ${srcPath} as ${AGENT_USER}` };
  }
  const data = r.stdout || Buffer.alloc(0);
  if (data.length > limitBytes) {
    return { ok: false, code: 'E2BIG', error: `${srcPath} exceeds the ${limitBytes}-byte attachment cap` };
  }

  const fd = fs.openSync(dest, 'w', 0o600);
  try {
    fs.writeSync(fd, data);
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.chownSync(dest, 0, 0);
  fs.chmodSync(dest, 0o600);

  return { ok: true, name, size: data.length, sha256: lib.sha256Buf(data), stagedPath: dest };
}

// --- the request path -------------------------------------------------------

let chain = Promise.resolve();
function serialize(fn) {
  const run = chain.then(fn, fn);
  chain = run.then(
    () => {},
    () => {},
  );
  return run;
}

function normalizeList(v, cap) {
  if (v == null) return [];
  const arr = Array.isArray(v) ? v : [v];
  return arr
    .map((x) => String(x).trim())
    .filter(Boolean)
    .slice(0, cap + 1);
}

/** A send request. Enqueues and returns pending. Sends NOTHING. */
async function handleSend(req) {
  if (killSwitchActive()) {
    return { ok: false, code: 'EKILL', error: 'the send kill switch is active; no request may be enqueued' };
  }

  const to = normalizeList(req.to, cfg.maxRecipients);
  const cc = normalizeList(req.cc, cfg.maxRecipients);
  const bcc = normalizeList(req.bcc, cfg.maxRecipients);
  const all = [...to, ...cc, ...bcc];
  if (!all.length) return { ok: false, code: 'EINVAL', error: 'at least one recipient is required' };
  if (all.length > cfg.maxRecipients) {
    return { ok: false, code: 'E2BIG', error: `more than ${cfg.maxRecipients} recipients` };
  }
  for (const a of all) {
    // Deliberately strict. A permissive address parser in the one component
    // that holds the credential is not worth the convenience.
    if (!/^[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+$/.test(a)) {
      return { ok: false, code: 'EINVAL', error: `not a usable address: ${a}` };
    }
  }

  const subject = String(req.subject || '');
  if (Buffer.byteLength(subject, 'utf8') > cfg.maxSubjectBytes) {
    return { ok: false, code: 'E2BIG', error: 'subject too long' };
  }
  const body = Buffer.from(String(req.body || ''), 'utf8');
  if (body.length > cfg.maxBodyBytes) {
    return { ok: false, code: 'E2BIG', error: 'body too long' };
  }

  // Credential first: the destination comes from the configured credential, not
  // from the caller. The agent may not choose where mail goes.
  const cred = lib.readCredential(cfg);
  if (!cred.ok) return { ok: false, code: cred.code, error: cred.error };
  const destination = { host: cred.credential.host, port: Number(cred.credential.port) };

  // Policy scope. Refuse any destination outside the send_actions section.
  // Broker-enforced, reading a root-owned policy file. NOT firewall-enforced.
  const allowed = lib.findSendDestination(cfg, destination.host, destination.port);
  if (!allowed) {
    log(`BLOCKED destination ${destination.host}:${destination.port} (not in send_actions)`);
    return {
      ok: false,
      code: 'EDEST',
      error: `${destination.host}:${destination.port} is not a permitted send destination`,
    };
  }

  const attachPaths = normalizeList(req.attachments, cfg.maxAttachments);
  if (attachPaths.length > cfg.maxAttachments) {
    return { ok: false, code: 'E2BIG', error: `more than ${cfg.maxAttachments} attachments` };
  }
  for (const p of attachPaths) {
    if (!p.startsWith('/')) return { ok: false, code: 'EINVAL', error: `absolute path required: ${p}` };
  }

  // Entitlement, explicit pass. The authoritative pass is the staged read.
  for (const p of attachPaths) {
    if (!agentCouldRead(p)) {
      return { ok: false, code: 'EACCES', error: `permission denied: ${p}` };
    }
  }

  // Aggregate staging ceiling, checked BEFORE anything is written so that an
  // over-cap request stages nothing partial.
  const used = lib.stagingUsedBytes(cfg);
  if (used >= cfg.maxStagingBytes) {
    return { ok: false, code: 'ENOSPC', error: `send staging is full (${used} bytes); refusing` };
  }

  const id = lib.newRequestId();
  const attachments = [];
  let total = 0;
  for (const p of attachPaths) {
    const r = stageAttachment(id, p, Math.min(cfg.maxAttachmentBytes, cfg.maxRequestBytes - total));
    if (!r.ok) {
      lib.purgeStaging(cfg, id);
      return { ok: false, code: r.code, error: r.error };
    }
    total += r.size;
    if (total > cfg.maxRequestBytes || used + total > cfg.maxStagingBytes) {
      lib.purgeStaging(cfg, id);
      return { ok: false, code: 'E2BIG', error: 'request exceeds the staging cap; nothing was staged' };
    }
    attachments.push({ name: r.name, size: r.size, sha256: r.sha256, stagedPath: r.stagedPath, sourcePath: p });
  }

  const { hash } = lib.canonicalPayload({
    destination,
    recipients: { to, cc, bcc },
    subject,
    bodySha256: lib.sha256Buf(body),
    attachments,
  });

  const now = Date.now();
  const rec = {
    id,
    createdAt: new Date(now).toISOString(),
    expiresAt: new Date(now + cfg.approvalTtlSeconds * 1000).toISOString(),
    state: 'pending',
    destination,
    recipients: { to, cc, bcc },
    subject,
    bodySha256: lib.sha256Buf(body),
    bodyPreview: body.toString('utf8'),
    attachments: attachments.map((a) => ({
      name: a.name,
      size: a.size,
      sha256: a.sha256,
      stagedPath: a.stagedPath,
      sourcePath: a.sourcePath,
    })),
    payloadHash: hash,
    approval: { state: 'none', boundHash: null, decidedAt: null },
    requestedBy: AGENT_USER,
    taskId: typeof req.taskId === 'string' && req.taskId ? req.taskId : null,
  };

  // The body is held in the ROOT-owned pending record, not re-read from any
  // agent-writable location at execution time. Same reasoning as attachment
  // staging: what was approved is what is sent.
  await lib.withStoreLock(cfg, () => lib.writePending(cfg, rec));

  log(`pending ${id} -> ${destination.host}:${destination.port} (${all.length} rcpt, ${attachments.length} att)`);
  return {
    ok: true,
    status: 'pending',
    requestId: id,
    payloadHash: hash,
    expiresAt: rec.expiresAt,
    message: 'Queued for your approval. Nothing has been sent.',
  };
}

function publicStatus(rec) {
  // What the AGENT may see. No staged paths, no body echo, no destination
  // credential detail beyond the host it already had to be told.
  return {
    ok: true,
    requestId: rec.id,
    status: rec.state,
    payloadHash: rec.payloadHash,
    expiresAt: rec.expiresAt,
    approval: rec.approval.state,
    result: rec.result ? { sent: rec.result.sent, reference: rec.result.reference || null } : null,
  };
}

async function handleStatus(req) {
  const rec = lib.readPending(cfg, String(req.requestId || ''));
  if (!rec) return { ok: false, code: 'ENOENT', error: 'no such request' };
  return publicStatus(rec);
}

// --- the approval path (admin socket only) ----------------------------------

async function handleList() {
  const recs = lib.listPending(cfg).filter((r) => r.state === 'pending');
  return {
    ok: true,
    pending: recs.map((r) => ({
      id: r.id,
      createdAt: r.createdAt,
      expiresAt: r.expiresAt,
      expired: lib.isExpired(r),
      destination: r.destination,
      recipients: r.recipients,
      subject: r.subject,
      // The full body, so the approval card can show the payload itself rather
      // than the model's summary of it.
      body: r.bodyPreview,
      bodySha256: r.bodySha256,
      attachments: (r.attachments || []).map((a) => ({ name: a.name, size: a.size, sha256: a.sha256 })),
      payloadHash: r.payloadHash,
      requestedBy: r.requestedBy,
    })),
  };
}

/** Recompute the hash from the STAGED copies. This is what makes a mutation
 *  detectable rather than merely improbable. */
function recomputeHash(rec) {
  const attachments = [];
  for (const a of rec.attachments || []) {
    let sha;
    try {
      sha = lib.sha256File(a.stagedPath);
    } catch (e) {
      return { ok: false, error: `staged attachment missing: ${a.name} (${e.message})` };
    }
    attachments.push({ name: a.name, size: fs.statSync(a.stagedPath).size, sha256: sha });
  }
  const { hash } = lib.canonicalPayload({
    destination: rec.destination,
    recipients: rec.recipients,
    subject: rec.subject,
    bodySha256: rec.bodySha256,
    attachments,
  });
  return { ok: true, hash };
}

async function handleApprove(req) {
  if (killSwitchActive()) {
    return { ok: false, code: 'EKILL', error: 'the send kill switch is active' };
  }
  const id = String(req.requestId || '');
  const supplied = String(req.payloadHash || '');

  return lib.withStoreLock(cfg, async () => {
    const rec = lib.readPending(cfg, id);
    if (!rec) return { ok: false, code: 'ENOENT', error: 'no such request' };
    if (rec.state !== 'pending') {
      // Single use. A consumed approval is not reusable, and this is where that
      // is enforced rather than in the caller.
      return { ok: false, code: 'ESTATE', error: `request is already ${rec.state}` };
    }
    // Re-checked under the lock immediately before anything opens a connection,
    // so an approval racing the expiry boundary denies.
    if (lib.isExpired(rec)) {
      rec.state = 'expired';
      lib.writePending(cfg, rec);
      lib.purgeStaging(cfg, id);
      lib.writeIntent(cfg, rec);
      lib.amendReceipt(cfg, id, { sent: false, outcome: 'expired' });
      return { ok: false, code: 'EEXPIRED', error: 'the approval window has closed' };
    }

    const re = recomputeHash(rec);
    if (!re.ok) return { ok: false, code: 'EIO', error: re.error };
    if (re.hash !== rec.payloadHash) {
      rec.state = 'invalidated';
      lib.writePending(cfg, rec);
      lib.writeIntent(cfg, rec);
      lib.amendReceipt(cfg, id, { sent: false, outcome: 'payload_changed' });
      lib.purgeStaging(cfg, id);
      return { ok: false, code: 'EHASH', error: 'the payload changed after it was previewed; approval voided' };
    }
    if (supplied && supplied !== rec.payloadHash) {
      return { ok: false, code: 'EHASH', error: 'approval is bound to a different payload' };
    }

    const cred = lib.readCredential(cfg);
    if (!cred.ok) return { ok: false, code: cred.code, error: cred.error };
    if (!lib.findSendDestination(cfg, rec.destination.host, rec.destination.port)) {
      return { ok: false, code: 'EDEST', error: 'destination is no longer permitted by policy' };
    }

    rec.approval = { state: 'approved', boundHash: rec.payloadHash, decidedAt: new Date().toISOString() };
    rec.state = 'approved';
    lib.writePending(cfg, rec);

    // INTENT RECORD BEFORE THE CONNECTION. A send that cannot write its receipt
    // does not execute, and this ordering is the only one where that rule is
    // load-bearing. It also leaves a crash-consistent record of an in-flight
    // send, which writing the receipt afterwards loses entirely.
    try {
      lib.writeIntent(cfg, rec);
    } catch (e) {
      rec.state = 'pending';
      rec.approval = { state: 'none', boundHash: null, decidedAt: null };
      lib.writePending(cfg, rec);
      return { ok: false, code: 'ERECEIPT', error: `cannot write the receipt; refusing to send: ${e.message}` };
    }

    const message = smtp.buildMessage({
      from: cred.credential.from,
      to: rec.recipients.to,
      cc: rec.recipients.cc,
      subject: rec.subject,
      body: Buffer.from(rec.bodyPreview, 'utf8'),
      attachments: (rec.attachments || []).map((a) => ({ name: a.name, stagedPath: a.stagedPath })),
    });

    let reference = null;
    try {
      reference = await smtp.sendMail({
        credential: cred.credential,
        envelope: {
          from: cred.credential.from,
          recipients: [...rec.recipients.to, ...rec.recipients.cc, ...rec.recipients.bcc],
        },
        message,
      });
    } catch (e) {
      rec.state = 'failed';
      rec.result = { sent: false, error: e.message };
      lib.writePending(cfg, rec);
      lib.amendReceipt(cfg, id, { sent: false, outcome: 'smtp_error', error: e.message });
      lib.purgeStaging(cfg, id);
      // No silent retry, per the fail-closed table.
      log(`FAILED ${id}: ${e.message}`);
      return { ok: false, code: 'ESMTP', error: e.message };
    }

    rec.state = 'sent';
    rec.result = { sent: true, reference, at: new Date().toISOString() };
    lib.writePending(cfg, rec);
    lib.amendReceipt(cfg, id, { sent: true, outcome: 'sent', reference });
    lib.purgeStaging(cfg, id);
    log(`sent ${id} (${reference})`);
    return { ok: true, status: 'sent', requestId: id, reference };
  });
}

async function handleDeny(req) {
  const id = String(req.requestId || '');
  return lib.withStoreLock(cfg, async () => {
    const rec = lib.readPending(cfg, id);
    if (!rec) return { ok: false, code: 'ENOENT', error: 'no such request' };
    if (rec.state !== 'pending') return { ok: false, code: 'ESTATE', error: `request is already ${rec.state}` };
    rec.state = 'denied';
    rec.approval = { state: 'denied', boundHash: rec.payloadHash, decidedAt: new Date().toISOString() };
    lib.writePending(cfg, rec);
    lib.writeIntent(cfg, rec);
    lib.amendReceipt(cfg, id, { sent: false, outcome: 'denied' });
    // Purged immediately rather than left for the timer: a denied payload has no
    // reason to exist on disk for another minute.
    lib.purgeStaging(cfg, id);
    log(`denied ${id}`);
    return { ok: true, status: 'denied', requestId: id };
  });
}

async function handleGc() {
  const now = Date.now();
  let expired = 0;
  let reaped = 0;
  await lib.withStoreLock(cfg, async () => {
    for (const rec of lib.listPending(cfg)) {
      if (rec.state === 'pending' && lib.isExpired(rec, now)) {
        rec.state = 'expired';
        lib.writePending(cfg, rec);
        lib.writeIntent(cfg, rec);
        lib.amendReceipt(cfg, rec.id, { sent: false, outcome: 'expired' });
        lib.purgeStaging(cfg, rec.id);
        expired += 1;
      }
      const age = now - Date.parse(rec.createdAt);
      if (rec.state !== 'pending' && age > cfg.pendingRetentionHours * 3600 * 1000) {
        lib.purgeStaging(cfg, rec.id);
        try {
          fs.unlinkSync(lib.pendingPath(cfg, rec.id));
          reaped += 1;
        } catch {
          /* already gone */
        }
      }
    }
    // Orphaned staging: a directory with no pending record at all.
    let ids = [];
    try {
      ids = fs.readdirSync(lib.stagingDir(cfg));
    } catch {
      ids = [];
    }
    for (const sid of ids) {
      if (!lib.readPending(cfg, sid)) lib.purgeStaging(cfg, sid);
    }
  });
  return { ok: true, expired, reaped };
}

/** Kill switch: cancel pending, purge staging, block new. */
async function handleKill() {
  let cancelled = 0;
  await lib.withStoreLock(cfg, async () => {
    for (const rec of lib.listPending(cfg)) {
      if (rec.state === 'pending') {
        rec.state = 'cancelled';
        lib.writePending(cfg, rec);
        lib.writeIntent(cfg, rec);
        lib.amendReceipt(cfg, rec.id, { sent: false, outcome: 'kill_switch' });
        cancelled += 1;
      }
      lib.purgeStaging(cfg, rec.id);
    }
  });
  return { ok: true, cancelled };
}

// --- dispatch ---------------------------------------------------------------

async function handleRequestChannel(req) {
  switch (req && req.op) {
    case 'ping':
      return { ok: true, pong: true, destinationConfigured: lib.credentialSummary(cfg).configured };
    case 'send':
      return serialize(() => handleSend(req));
    case 'status':
      return handleStatus(req);
    // Explicitly enumerated so an admin op arriving on the agent socket is a
    // refusal with a name, not an accident of routing.
    case 'approve':
    case 'deny':
    case 'list':
    case 'credential-set':
      return { ok: false, code: 'EPERM', error: `${req.op} is not available on the request channel` };
    default:
      return { ok: false, code: 'EINVAL', error: `unknown op: ${req && req.op}` };
  }
}

async function handleAdminChannel(req) {
  switch (req && req.op) {
    case 'ping':
      return { ok: true, pong: true, admin: true };
    case 'list':
      return handleList();
    case 'approve':
      return handleApprove(req);
    case 'deny':
      return handleDeny(req);
    case 'status':
      return handleStatus(req);
    case 'gc':
      return handleGc();
    case 'kill':
      return handleKill();
    case 'credential-summary':
      return { ok: true, credential: lib.credentialSummary(cfg) };
    case 'credential-set':
      try {
        lib.writeCredential(cfg, {
          host: String(req.host),
          port: Number(req.port),
          username: String(req.username),
          password: String(req.password),
          from: String(req.from),
        });
        // Configuring SMTP is the act that authorizes its destination. Doing it
        // here keeps credential and policy from drifting apart: there is no way
        // to hold a credential pointing somewhere the policy does not permit,
        // and no way to leave a stale destination authorized after a repoint.
        const dest = lib.setSendDestination(cfg, req.host, req.port);
        log(`credential set; authorized destination ${dest.host}:${dest.port}`);
        // Summary only. The secret is never echoed back, not even masked: a mask
        // still confirms length and prefix.
        return { ok: true, credential: lib.credentialSummary(cfg), destination: { host: dest.host, port: dest.port } };
      } catch (e) {
        return { ok: false, code: 'EIO', error: `cannot write the credential: ${e.message}` };
      }
    default:
      return { ok: false, code: 'EINVAL', error: `unknown op: ${req && req.op}` };
  }
}

// --- sockets ----------------------------------------------------------------

for (const d of [cfg.store, lib.pendingDir(cfg), lib.stagingDir(cfg), lib.receiptsDir(cfg)]) {
  fs.mkdirSync(d, { recursive: true, mode: 0o700 });
  fs.chownSync(d, 0, 0);
  fs.chmodSync(d, 0o700);
}

function serve(socketPath, handler, secure) {
  try {
    fs.unlinkSync(socketPath);
  } catch {
    /* no stale socket */
  }
  fs.mkdirSync(path.dirname(socketPath), { recursive: true, mode: 0o755 });

  const server = net.createServer((sock) => {
    let buf = '';
    sock.setEncoding('utf8');
    sock.on('data', async (chunk) => {
      buf += chunk;
      if (buf.length > 8 * 1024 * 1024) {
        sock.end(`${JSON.stringify({ ok: false, code: 'E2BIG', error: 'request too large' })}\n`);
        return;
      }
      const nl = buf.indexOf('\n');
      if (nl < 0) return;
      const line = buf.slice(0, nl);
      buf = '';
      let res;
      try {
        res = await handler(JSON.parse(line));
      } catch (e) {
        res = { ok: false, code: 'EINVAL', error: `bad request: ${e.message}` };
      }
      sock.end(`${JSON.stringify(res)}\n`);
    });
    sock.on('error', () => sock.destroy());
  });

  server.on('error', (e) => {
    log(`FATAL on ${socketPath}: ${e.message}`);
    process.exit(1);
  });

  server.listen(socketPath, () => {
    try {
      secure(socketPath);
    } catch (e) {
      log(`FATAL: cannot secure ${socketPath}: ${e.message}`);
      process.exit(1);
    }
    log(`listening on ${socketPath}`);
  });
  return server;
}

const servers = [
  // Agent-reachable. This mode IS the caller authentication; see the trust note.
  serve(cfg.socketPath, handleRequestChannel, (p) => {
    fs.chownSync(p, 0, AGENT.gid);
    fs.chmodSync(p, 0o660);
  }),
  // Root only. clawuser cannot connect at all, which is what makes "the agent
  // cannot approve" structural rather than a policy check inside the handler.
  serve(ADMIN_SOCKET, handleAdminChannel, (p) => {
    fs.chownSync(p, 0, 0);
    fs.chmodSync(p, 0o600);
  }),
];

log(
  `send broker up (agent=${AGENT_USER}/${AGENT.uid}, ttl=${cfg.approvalTtlSeconds}s, ` +
    `store=${cfg.store}, host=${os.hostname()})`,
);

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    for (const s of servers) {
      try {
        s.close();
      } catch {
        /* shutting down anyway */
      }
    }
    for (const p of [cfg.socketPath, ADMIN_SOCKET]) {
      try {
        fs.unlinkSync(p);
      } catch {
        /* shutting down anyway */
      }
    }
    process.exit(0);
  });
}
