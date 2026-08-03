// send-smtp.js -- minimal SMTP submission client for the ClawFactory send broker
// (v1 Guard 2). Root only, loaded by clawfactory-sendd.js.
//
// WHY THIS IS HAND-ROLLED
// The install has no npm dependency surface for the security path, and adding
// one would put a third-party package inside the only component on the box that
// holds the SMTP credential. Submission is a small, stable protocol; this
// implements exactly the subset needed and nothing else.
//
// SUPPORTED: implicit TLS (port 465), STARTTLS (port 587 and 25), AUTH PLAIN and
// AUTH LOGIN, multipart/mixed with base64 attachments.
// NOT SUPPORTED, deliberately: cleartext submission without STARTTLS, OAuth,
// and any form of credential the user did not type in themselves.

'use strict';

const net = require('node:net');
const tls = require('node:tls');
const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');

const CRLF = '\r\n';

/** RFC 2047 encoded-word for any header value that is not plain ASCII. */
function encodeHeader(value) {
  const v = String(value == null ? '' : value);
  // eslint-disable-next-line no-control-regex
  if (/^[\x20-\x7E]*$/.test(v)) return v;
  return `=?UTF-8?B?${Buffer.from(v, 'utf8').toString('base64')}?=`;
}

function foldBase64(buf) {
  const b64 = buf.toString('base64');
  const lines = [];
  for (let i = 0; i < b64.length; i += 76) lines.push(b64.slice(i, i + 76));
  return lines.join(CRLF);
}

/**
 * Build the RFC 5322 message.
 *
 * Bcc recipients appear in the ENVELOPE only and never in a header, which is
 * the entire point of Bcc. They are still covered by the canonical payload hash,
 * so a Bcc addition voids an approval even though it is invisible in the
 * rendered message.
 *
 * Attachments are read from the STAGED copies. This function is never given an
 * agent-controlled path.
 */
function buildMessage(msg) {
  const boundary = `----=_cf_${crypto.randomBytes(16).toString('hex')}`;
  const hasAttachments = (msg.attachments || []).length > 0;
  const headers = [
    `From: ${encodeHeader(msg.from)}`,
    `To: ${(msg.to || []).map(encodeHeader).join(', ')}`,
  ];
  if ((msg.cc || []).length) headers.push(`Cc: ${msg.cc.map(encodeHeader).join(', ')}`);
  headers.push(`Subject: ${encodeHeader(msg.subject)}`);
  headers.push(`Date: ${new Date().toUTCString()}`);
  headers.push(`Message-ID: <${crypto.randomBytes(16).toString('hex')}@clawfactory.local>`);
  headers.push('MIME-Version: 1.0');

  const body = Buffer.isBuffer(msg.body) ? msg.body : Buffer.from(String(msg.body || ''), 'utf8');

  if (!hasAttachments) {
    headers.push('Content-Type: text/plain; charset=UTF-8');
    headers.push('Content-Transfer-Encoding: base64');
    return `${headers.join(CRLF)}${CRLF}${CRLF}${foldBase64(body)}${CRLF}`;
  }

  headers.push(`Content-Type: multipart/mixed; boundary="${boundary}"`);
  const parts = [
    `--${boundary}`,
    'Content-Type: text/plain; charset=UTF-8',
    'Content-Transfer-Encoding: base64',
    '',
    foldBase64(body),
  ];
  for (const a of msg.attachments) {
    const data = fs.readFileSync(a.stagedPath);
    parts.push(
      `--${boundary}`,
      `Content-Type: application/octet-stream; name="${encodeHeader(path.basename(a.name))}"`,
      'Content-Transfer-Encoding: base64',
      `Content-Disposition: attachment; filename="${encodeHeader(path.basename(a.name))}"`,
      '',
      foldBase64(data),
    );
  }
  parts.push(`--${boundary}--`, '');
  return `${headers.join(CRLF)}${CRLF}${CRLF}${parts.join(CRLF)}`;
}

/** Dot-stuffing per RFC 5321: a line consisting of a single dot ends DATA. */
function dotStuff(text) {
  return text.replace(/\r\n\./g, '\r\n..');
}

class SmtpSession {
  constructor(sock, timeoutMs) {
    this.sock = sock;
    this.buf = '';
    this.timeoutMs = timeoutMs;
    this.waiters = [];
    sock.setEncoding('utf8');
    sock.on('data', (d) => {
      this.buf += d;
      this.drain();
    });
  }

  drain() {
    for (;;) {
      // A reply is complete when a line's 4th character is a space rather than
      // a hyphen, which is how multi-line replies are delimited.
      const m = this.buf.match(/^(?:\d{3}-[^\r\n]*\r\n)*(\d{3}) [^\r\n]*\r\n/);
      if (!m) return;
      const raw = this.buf.slice(0, m[0].length);
      this.buf = this.buf.slice(m[0].length);
      const w = this.waiters.shift();
      if (w) w.resolve({ code: Number(m[1]), text: raw.trim() });
    }
  }

  read() {
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error('SMTP read timed out')), this.timeoutMs);
      this.waiters.push({
        resolve: (v) => {
          clearTimeout(t);
          resolve(v);
        },
      });
      this.drain();
    });
  }

  write(line) {
    this.sock.write(line + CRLF);
  }

  async cmd(line, expect) {
    this.write(line);
    const r = await this.read();
    if (expect && !expect.includes(r.code)) {
      // Never echo the command back: AUTH lines carry the credential.
      const safe = line.startsWith('AUTH') || /^[A-Za-z0-9+/=]+$/.test(line) ? '<redacted>' : line;
      throw new Error(`SMTP ${safe} rejected: ${r.text}`);
    }
    return r;
  }
}

function connectPlain(host, port, timeoutMs) {
  return new Promise((resolve, reject) => {
    const s = net.connect({ host, port });
    s.setTimeout(timeoutMs);
    s.once('connect', () => resolve(s));
    s.once('timeout', () => {
      s.destroy();
      reject(new Error(`connect to ${host}:${port} timed out`));
    });
    s.once('error', reject);
  });
}

function upgradeTls(sock, host, timeoutMs) {
  return new Promise((resolve, reject) => {
    const t = tls.connect({ socket: sock, servername: host }, () => resolve(t));
    t.setTimeout(timeoutMs);
    t.once('error', reject);
  });
}

function connectTls(host, port, timeoutMs) {
  return new Promise((resolve, reject) => {
    const t = tls.connect({ host, port, servername: host });
    t.setTimeout(timeoutMs);
    t.once('secureConnect', () => resolve(t));
    t.once('timeout', () => {
      t.destroy();
      reject(new Error(`TLS connect to ${host}:${port} timed out`));
    });
    t.once('error', reject);
  });
}

/**
 * Send one message. Resolves with a provider reference (the server's reply to
 * the final DATA terminator, which carries the queue id on most servers).
 *
 * Throws on any failure. The caller treats a throw as "did not send" and records
 * it in the receipt; there is no silent retry, per the fail-closed table.
 */
async function sendMail(opts) {
  const { credential, envelope, message, timeoutMs = 30000 } = opts;
  const host = credential.host;
  const port = Number(credential.port);
  const implicitTls = port === 465;

  let sock = implicitTls
    ? await connectTls(host, port, timeoutMs)
    : await connectPlain(host, port, timeoutMs);

  let s = new SmtpSession(sock, timeoutMs);
  const greeting = await s.read();
  if (greeting.code !== 220) throw new Error(`unexpected SMTP greeting: ${greeting.text}`);

  const ehloName = 'clawfactory.local';
  let ehlo = await s.cmd(`EHLO ${ehloName}`, [250]);

  if (!implicitTls) {
    if (!/STARTTLS/i.test(ehlo.text)) {
      // Refuse to authenticate in the clear. A credential is at stake and the
      // fail-closed rule applies to transport too.
      throw new Error(`${host}:${port} does not offer STARTTLS; refusing to submit in cleartext`);
    }
    await s.cmd('STARTTLS', [220]);
    sock = await upgradeTls(sock, host, timeoutMs);
    s = new SmtpSession(sock, timeoutMs);
    ehlo = await s.cmd(`EHLO ${ehloName}`, [250]);
  }

  // AUTH. PLAIN preferred, LOGIN as the fallback; both only after TLS.
  const user = credential.username;
  const pass = credential.password;
  if (/AUTH[ -][^\r\n]*PLAIN/i.test(ehlo.text)) {
    const token = Buffer.from(`\0${user}\0${pass}`, 'utf8').toString('base64');
    await s.cmd(`AUTH PLAIN ${token}`, [235]);
  } else if (/AUTH[ -][^\r\n]*LOGIN/i.test(ehlo.text)) {
    await s.cmd('AUTH LOGIN', [334]);
    await s.cmd(Buffer.from(user, 'utf8').toString('base64'), [334]);
    await s.cmd(Buffer.from(pass, 'utf8').toString('base64'), [235]);
  } else {
    throw new Error(`${host}:${port} offers no supported AUTH mechanism`);
  }

  await s.cmd(`MAIL FROM:<${envelope.from}>`, [250]);
  for (const rcpt of envelope.recipients) {
    await s.cmd(`RCPT TO:<${rcpt}>`, [250, 251]);
  }
  await s.cmd('DATA', [354]);
  sock.write(dotStuff(message.endsWith(CRLF) ? message : message + CRLF));
  const done = await s.cmd('.', [250]);

  try {
    await s.cmd('QUIT', [221]);
  } catch {
    // The message is already accepted at this point; a rude close is not a
    // delivery failure and must not be reported as one.
  }
  try {
    sock.destroy();
  } catch {
    /* closing anyway */
  }

  return done.text;
}

module.exports = { buildMessage, sendMail, encodeHeader, dotStuff };
