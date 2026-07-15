#!/usr/bin/env node
/*
 * ClawFactory chatCompletions gating proxy (Blocker 1 / Door 1).
 *
 * WHY: ClawChat -- the shipped desktop app -- sends every turn to
 *   POST http://127.0.0.1:8787/v1/chat/completions
 * which never runs the `openclaw agent` CLI, so the openclaw shim's turn gate
 * never sees it. Those turns had NEITHER the spend cap NOR the SOUL check.
 *
 * WHAT: this process owns 127.0.0.1:8787 -- the address ClawChat, the CLI, the
 * cost meter and Studio already use. The REAL gateway is moved to a private
 * loopback port (OPENCLAW_GATEWAY_PORT in its systemd unit). We:
 *   - POST /v1/chat/completions -> run the SAME gate the shim runs
 *     (clawfactory-turn-gate.sh; we do not reimplement the checks), then either
 *     forward to the real gateway or return a well-formed refusal.
 *   - everything else            -> transparent pass-through.
 *
 * FAIL-CLOSED BY CONSTRUCTION: the real gateway no longer listens on 8787. If
 * this proxy is not running, nothing answers there -- ClawChat cannot silently
 * fall through to an ungated gateway. Losing the proxy does not reopen the door.
 *
 * SPEND ACCOUNTING: an allowed turn is forwarded to the real gateway, which runs
 * it and records usage natively, so `gateway usage-cost` accounts it exactly as
 * it does a CLI turn. We add no accounting of our own.
 *
 * RE-ENTRANCY (important): the gate runs as clawuser and calls
 * `openclaw gateway usage-cost`, which resolves gateway.port = 8787 = THIS
 * proxy, and is then passed through to the real gateway. The gate must therefore
 * be spawned ASYNCHRONOUSLY -- a synchronous execFileSync would block the event
 * loop and deadlock against our own pass-through of that usage-cost request.
 */
'use strict';
const http = require('node:http');
const { execFile } = require('node:child_process');
const { randomUUID } = require('node:crypto');

const LISTEN_HOST = '127.0.0.1';
const LISTEN_PORT = Number(process.env.CLAWFACTORY_PROXY_PORT || 8787);
const REAL_HOST = '127.0.0.1';
const REAL_PORT = Number(process.env.CLAWFACTORY_REAL_GATEWAY_PORT || 8788);
const GATE = process.env.CLAWFACTORY_GATE || '/usr/local/sbin/clawfactory-turn-gate.sh';
const GATE_USER = process.env.CLAWFACTORY_GATE_USER || 'clawuser';
const CHAT_PATH = '/v1/chat/completions';

function log(msg) { process.stdout.write(`[clawfactory-proxy] ${msg}\n`); }

/**
 * Run the universal turn gate (SOUL integrity + spend cap) as clawuser.
 * Resolves {allowed:true} or {allowed:false,state,message}. Fail-SAFE: anything
 * we cannot interpret is a refusal, never a pass.
 */
function runGate() {
  return new Promise((resolve) => {
    execFile('/bin/su', [GATE_USER, '-s', '/bin/bash', '-c', GATE], { timeout: 90000 }, (err, stdout, stderr) => {
      const out = String(stdout || '') + String(stderr || '');
      if (!err) return resolve({ allowed: true });
      const m = out.match(/\{"clawfactory_gate":"blocked"[\s\S]*?\}/);
      if (m) {
        try {
          const j = JSON.parse(m[0]);
          return resolve({ allowed: false, state: j.state || 'blocked', message: j.message || 'This turn was blocked by ClawFactory.' });
        } catch (_) { /* fall through */ }
      }
      resolve({
        allowed: false,
        state: 'gate_error',
        message: 'ClawFactory could not verify that this turn is allowed, so it refused it (fail-safe). ' + out.replace(/\s+/g, ' ').slice(0, 300),
      });
    });
  });
}

/** OpenAI-shaped refusal so ClawChat renders it as a normal assistant message. */
function refuse(res, wantsStream, model, gate) {
  const id = 'chatcmpl_' + randomUUID();
  const created = Math.floor(Date.now() / 1000);
  const text = gate.message;
  if (!wantsStream) {
    const body = JSON.stringify({
      id, object: 'chat.completion', created, model,
      choices: [{ index: 0, message: { role: 'assistant', content: text }, finish_reason: 'stop' }],
      usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
      clawfactory_gate: { blocked: true, state: gate.state },
    });
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': Buffer.byteLength(body) });
    return res.end(body);
  }
  // Mirror the gateway's SSE contract exactly: role delta, content delta,
  // finish_reason stop, then [DONE].
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
  });
  const chunk = (delta, finish) => 'data: ' + JSON.stringify({
    id, object: 'chat.completion.chunk', created, model,
    choices: [{ index: 0, delta, finish_reason: finish === undefined ? null : finish }],
  }) + '\n\n';
  res.write(chunk({ role: 'assistant' }, null));
  res.write(chunk({ content: text }, null));
  res.write(chunk({}, 'stop'));
  res.write('data: [DONE]\n\n');
  res.end();
}

/** Pipe a request to the real gateway and stream the response back verbatim. */
function forward(req, res, bodyBuf) {
  const headers = Object.assign({}, req.headers);
  headers.host = `${REAL_HOST}:${REAL_PORT}`;
  if (bodyBuf) {
    delete headers['content-length'];
    headers['content-length'] = Buffer.byteLength(bodyBuf);
  }
  const up = http.request({ host: REAL_HOST, port: REAL_PORT, method: req.method, path: req.url, headers }, (ur) => {
    res.writeHead(ur.statusCode || 502, ur.headers);
    ur.pipe(res);
  });
  up.on('error', (e) => {
    if (!res.headersSent) res.writeHead(502, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ error: { message: `ClawFactory proxy: the OpenClaw gateway is not reachable on ${REAL_HOST}:${REAL_PORT} (${e.code || e.message}).`, type: 'upstream_unavailable' } }));
  });
  if (bodyBuf) up.end(bodyBuf); else req.pipe(up);
}

function handler(req, res) {
  const path = (req.url || '').split('?')[0];
  if (!(req.method === 'POST' && path === CHAT_PATH)) return forward(req, res, null);

  const chunks = [];
  let size = 0;
  req.on('data', (c) => { chunks.push(c); size += c.length; });
  req.on('error', () => { try { res.writeHead(400); res.end(); } catch (_) {} });
  req.on('end', async () => {
    const body = Buffer.concat(chunks, size);
    let wantsStream = false;
    let model = 'openclaw';
    try {
      const j = JSON.parse(body.toString('utf8'));
      wantsStream = j.stream === true;
      if (typeof j.model === 'string' && j.model) model = j.model;
    } catch (_) { /* malformed body -> let the gateway reject it, after the gate */ }
    const gate = await runGate();
    if (!gate.allowed) {
      log(`chat turn BLOCKED (${gate.state}) stream=${wantsStream}`);
      return refuse(res, wantsStream, model, gate);
    }
    forward(req, res, body);
  });
}

/*
 * WebSocket pass-through. VERIFIED the hard way: the openclaw CLI does NOT use
 * the HTTP routes for its control plane -- `openclaw gateway usage-cost` dials
 * ws://127.0.0.1:<gateway.port>. The gateway serves BOTH an HTTP surface
 * (/status, /v1/chat/completions) and a WebSocket protocol on the same port, so
 * a proxy that only speaks HTTP silently breaks the CLI (and with it the spend
 * meter, which fails the gate closed and blocks every turn).
 * We relay the upgrade verbatim and then pipe the sockets both ways. The WS
 * control plane is NOT gated here: it is not a chat-completions turn surface,
 * and the CLI turn path is already gated by the openclaw shim.
 */
function onUpgrade(req, clientSocket, head) {
  const headers = Object.assign({}, req.headers);
  headers.host = `${REAL_HOST}:${REAL_PORT}`;
  const up = http.request({ host: REAL_HOST, port: REAL_PORT, method: req.method || 'GET', path: req.url, headers });
  up.on('upgrade', (ures, upSocket, upHead) => {
    const statusLine = `HTTP/1.1 ${ures.statusCode} ${ures.statusMessage}\r\n`;
    const hdrs = Object.entries(ures.headers).map(([k, v]) => `${k}: ${v}`).join('\r\n');
    clientSocket.write(statusLine + hdrs + '\r\n\r\n');
    if (upHead && upHead.length) clientSocket.write(upHead);
    upSocket.on('error', () => clientSocket.destroy());
    clientSocket.on('error', () => upSocket.destroy());
    upSocket.pipe(clientSocket);
    clientSocket.pipe(upSocket);
  });
  up.on('response', (ures) => {
    // Upgrade refused by the gateway -- relay its answer and close.
    const hdrs = Object.entries(ures.headers).map(([k, v]) => `${k}: ${v}`).join('\r\n');
    clientSocket.write(`HTTP/1.1 ${ures.statusCode} ${ures.statusMessage}\r\n${hdrs}\r\n\r\n`);
    ures.pipe(clientSocket);
  });
  up.on('error', () => clientSocket.destroy());
  if (head && head.length) up.write(head);
  up.end();
}

// Bind BOTH loopback families, matching what the real gateway does
// (it listens on 127.0.0.1 and [::1]). A client that resolves "localhost" to
// ::1 must not get connection-refused just because we only took the v4 address.
// Loopback only, never 0.0.0.0/:: -- this must not become LAN-reachable.
const listeners = [[LISTEN_HOST, 'ipv4'], ['::1', 'ipv6']];
let bound = 0;
for (const [addr, label] of listeners) {
  const s = http.createServer(handler);
  s.on('upgrade', onUpgrade);
  s.on('error', (e) => {
    log(`WARN: could not bind ${label} ${addr}:${LISTEN_PORT}: ${e.code || e.message}`);
    if (bound === 0 && label === 'ipv6') return; // v4 is the one that must work
  });
  s.listen(LISTEN_PORT, addr, () => {
    bound++;
    log(`listening on ${addr}:${LISTEN_PORT} (${label}) -> real gateway ${REAL_HOST}:${REAL_PORT}; gating POST ${CHAT_PATH} via ${GATE} as ${GATE_USER}`);
  });
}
