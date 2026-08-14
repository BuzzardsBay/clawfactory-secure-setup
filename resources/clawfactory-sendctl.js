#!/usr/bin/env node
// clawfactory-sendctl.js -- the ROOT-ONLY control tool for the send broker
// (v1 Guard 2).
//
// Installed to /usr/local/sbin/clawfactory-sendctl.js, root:root 0750.
//
// THIS IS THE APPROVAL PATH, AND IT NEVER RUNS AS UID 1000.
// Studio reaches it through a hardcoded `wsl -u root` channel. It talks to the
// broker's ADMIN socket (0600 root:root), which clawuser cannot open. Two
// independent things therefore stop the agent approving its own request: the
// file mode on this program, and the mode on the socket it speaks to. Neither
// is a policy check that a bug in a handler could skip.
//
// Refuses to run at any uid other than 0, so that a future caller who invokes it
// carelessly fails loudly instead of silently doing nothing useful.
//
// CREDENTIAL HANDLING: `credential-set` reads JSON on STDIN, never from argv.
// An argument would be visible in `ps` to every account on the box, including
// clawuser, for the lifetime of the process. That is the one place a
// root-only tool can still leak a secret to a non-root reader.

'use strict';

const fs = require('node:fs');
const net = require('node:net');

const ADMIN_SOCKET = '/run/clawfactory/send-admin.sock';

if (typeof process.getuid !== 'function' || process.getuid() !== 0) {
  process.stderr.write('clawfactory-sendctl: must run as root\n');
  process.exit(1);
}

function usage() {
  process.stderr.write(
    [
      'usage: clawfactory-sendctl <command>',
      '',
      '  list                        pending requests, plus what expired since the panel was last viewed',
      '  status <id>                 one request',
      '  approve <id> [payloadHash]  approve and send. Single use.',
      '  deny <id>                   deny and purge staging',
      '  dismiss <id>                clear an expired card from the panel. Keeps the audit record',
      '  mark-viewed                 advance the last-viewed mark for the panel',
      '  gc                          expire and reap',
      '  kill                        kill switch: cancel pending, purge staging',
      '  credential-summary          what is configured, never the secret',
      '  credential-set              read {host,port,username,password,from} on STDIN',
      '',
    ].join('\n'),
  );
}

function call(req) {
  return new Promise((resolve, reject) => {
    const s = net.createConnection(ADMIN_SOCKET);
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
    // Generous: an approve call performs a real SMTP submission inline.
    setTimeout(() => fail(new Error('the send broker did not answer within 120s')), 120000);
  });
}

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch (e) {
    throw new Error(`cannot read stdin: ${e.message}`);
  }
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  if (!cmd) {
    usage();
    process.exit(2);
  }

  let req;
  switch (cmd) {
    case 'list':
      req = { op: 'list' };
      break;
    case 'status':
      if (!rest[0]) return usage(), process.exit(2);
      req = { op: 'status', requestId: rest[0] };
      break;
    case 'approve':
      if (!rest[0]) return usage(), process.exit(2);
      req = { op: 'approve', requestId: rest[0], payloadHash: rest[1] || '' };
      break;
    case 'deny':
      if (!rest[0]) return usage(), process.exit(2);
      req = { op: 'deny', requestId: rest[0] };
      break;
    case 'dismiss':
      if (!rest[0]) return usage(), process.exit(2);
      req = { op: 'dismiss', requestId: rest[0] };
      break;
    case 'mark-viewed':
      req = { op: 'mark-viewed' };
      break;
    case 'gc':
      req = { op: 'gc' };
      break;
    case 'kill':
      req = { op: 'kill' };
      break;
    case 'credential-summary':
      req = { op: 'credential-summary' };
      break;
    case 'credential-set': {
      let c;
      try {
        c = JSON.parse(readStdin());
      } catch (e) {
        process.stderr.write(`clawfactory-sendctl: ${e.message}\n`);
        process.exit(2);
      }
      for (const k of ['host', 'port', 'username', 'password', 'from']) {
        if (!c || c[k] == null || String(c[k]) === '') {
          process.stderr.write(`clawfactory-sendctl: credential is missing "${k}"\n`);
          process.exit(2);
        }
      }
      req = {
        op: 'credential-set',
        host: c.host,
        port: c.port,
        username: c.username,
        password: c.password,
        from: c.from,
      };
      break;
    }
    case 'ping':
      req = { op: 'ping' };
      break;
    default:
      usage();
      process.exit(2);
  }

  let res;
  try {
    res = await call(req);
  } catch (e) {
    process.stderr.write(`clawfactory-sendctl: ${e.message}\n`);
    process.exit(1);
  }
  // Machine-readable on stdout so Studio parses one thing and one thing only.
  process.stdout.write(`${JSON.stringify(res)}\n`);
  process.exit(res && res.ok ? 0 : 1);
}

main().catch((e) => {
  process.stderr.write(`clawfactory-sendctl: ${e.message}\n`);
  process.exit(1);
});
