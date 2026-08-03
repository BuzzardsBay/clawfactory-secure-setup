#!/usr/bin/env node
// clawfactory-send.js -- the AGENT-FACING send client (v1 Guard 2).
//
// Installed to /usr/local/bin/clawfactory-send, root:root 0755. World-executable
// and not writable by the agent: the agent runs it but cannot edit it out of the
// way.
//
// THIS FILE HOLDS NO CAPABILITY. It contains no SMTP code, no credential, no
// policy, and no hashing logic. All it can do is hand a request to the root
// broker over a unix socket and print what comes back. If someone deleted the
// broker, this program could not send mail by any means, which is the property
// that makes the guard structural rather than a convention.
//
// It cannot approve. Approval does not traverse this socket at all; it arrives
// on a separate root-only socket that clawuser cannot open.

'use strict';

const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');

const SOCKET = '/run/clawfactory/send.sock';
const DRAFTS = path.join(os.homedir(), '.clawfactory', 'drafts');

function usage() {
  process.stderr.write(
    [
      'usage:',
      '  clawfactory-send --to <addr> [--cc <addr>] [--bcc <addr>] --subject <s>',
      '                   (--body <text> | --body-file <path>) [--attach <path>]...',
      '  clawfactory-send status <request-id>',
      '',
      'Queues an email for YOUR approval. Nothing is sent until you approve it',
      'in ClawFactory Studio. Repeat --to, --cc, --bcc and --attach as needed.',
      '',
    ].join('\n'),
  );
}

function parseArgs(argv) {
  const out = { to: [], cc: [], bcc: [], attachments: [], subject: '', body: null };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    const next = () => {
      i += 1;
      if (i >= argv.length) throw new Error(`${a} needs a value`);
      return argv[i];
    };
    switch (a) {
      case '--to':
        out.to.push(next());
        break;
      case '--cc':
        out.cc.push(next());
        break;
      case '--bcc':
        out.bcc.push(next());
        break;
      case '--attach':
        out.attachments.push(path.resolve(next()));
        break;
      case '--subject':
        out.subject = next();
        break;
      case '--body':
        out.body = next();
        break;
      case '--body-file':
        out.body = fs.readFileSync(next(), 'utf8');
        break;
      case '--task-id':
        out.taskId = next();
        break;
      case '-h':
      case '--help':
        usage();
        process.exit(0);
        break;
      default:
        throw new Error(`unknown option: ${a}`);
    }
  }
  return out;
}

/**
 * Preserve the draft when the broker is unreachable. Nothing the user dictated
 * should be lost because a service was down, and there is deliberately no
 * fallback send path to lose it to.
 */
function preserveDraft(req, reason) {
  try {
    fs.mkdirSync(DRAFTS, { recursive: true, mode: 0o700 });
    const p = path.join(DRAFTS, `${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
    fs.writeFileSync(p, JSON.stringify({ savedAt: new Date().toISOString(), reason, request: req }, null, 2), {
      mode: 0o600,
    });
    return p;
  } catch {
    return null;
  }
}

function call(req) {
  return new Promise((resolve, reject) => {
    const s = net.createConnection(SOCKET);
    let buf = '';
    const fail = (e) => {
      try {
        s.destroy();
      } catch {
        /* already gone */
      }
      reject(e);
    };
    s.on('connect', () => s.write(`${JSON.stringify(req)}\n`));
    s.on('data', (d) => {
      buf += d;
      const nl = buf.indexOf('\n');
      if (nl < 0) return;
      try {
        resolve(JSON.parse(buf.slice(0, nl)));
      } catch (e) {
        fail(e);
      }
      try {
        s.destroy();
      } catch {
        /* done */
      }
    });
    s.on('error', fail);
    setTimeout(() => fail(new Error('the send broker did not answer within 60s')), 60000);
  });
}

async function main() {
  const argv = process.argv.slice(2);
  if (!argv.length) {
    usage();
    process.exit(2);
  }

  if (argv[0] === 'status') {
    if (!argv[1]) {
      usage();
      process.exit(2);
    }
    const res = await call({ op: 'status', requestId: argv[1] });
    process.stdout.write(`${JSON.stringify(res, null, 2)}\n`);
    process.exit(res.ok ? 0 : 1);
  }

  let args;
  try {
    args = parseArgs(argv);
  } catch (e) {
    process.stderr.write(`clawfactory-send: ${e.message}\n`);
    usage();
    process.exit(2);
  }
  if (!args.to.length && !args.cc.length && !args.bcc.length) {
    process.stderr.write('clawfactory-send: at least one --to is required\n');
    process.exit(2);
  }

  const req = {
    op: 'send',
    to: args.to,
    cc: args.cc,
    bcc: args.bcc,
    subject: args.subject,
    body: args.body == null ? '' : args.body,
    attachments: args.attachments,
    taskId: args.taskId || null,
  };

  let res;
  try {
    res = await call(req);
  } catch (e) {
    // Fail loud. Deny, preserve, and do NOT fall through to anything.
    const saved = preserveDraft(req, e.message);
    process.stderr.write(
      [
        `clawfactory-send: the send broker is unreachable (${e.message}).`,
        'Nothing was sent and there is no alternative path: this command holds no',
        'credential and no mail transport of its own.',
        saved ? `Your draft was preserved at ${saved}` : 'The draft could NOT be preserved.',
        '',
      ].join('\n'),
    );
    process.exit(1);
  }

  if (!res.ok) {
    process.stderr.write(`clawfactory-send: ${res.error || res.code || 'refused'}\n`);
    process.exit(1);
  }

  process.stdout.write(
    [
      `status=${res.status}`,
      `requestId=${res.requestId}`,
      `payloadHash=${res.payloadHash}`,
      `expiresAt=${res.expiresAt}`,
      '',
      'Queued for approval in ClawFactory Studio. Nothing has been sent.',
      '',
    ].join('\n'),
  );
}

main().catch((e) => {
  process.stderr.write(`clawfactory-send: ${e.message}\n`);
  process.exit(1);
});
