// Adversarial probe: drives the REAL Studio turn launchers from the built dist
// so the suite can assert that a turn launched THROUGH STUDIO (not through the
// PowerShell engine) is gated. Prints a single JSON line.
//
//   node studio-turn-probe.mjs <stream|send> [studioDistServicesDir]
//
// studioDistServicesDir defaults to $CLAWFACTORY_STUDIO_DIST or the sibling
// ClawFactory-Studio checkout. Exits 0 always; the caller parses the JSON.
import { pathToFileURL } from 'node:url';

const svcDir =
  process.argv[3] ||
  process.env.CLAWFACTORY_STUDIO_DIST ||
  'C:/Users/bmcki/ClawFactory-Studio/backend/dist/services/';
const base = svcDir.replace(/\\/g, '/').replace(/\/?$/, '/');

let as, chat;
try {
  as = await import(pathToFileURL(base + 'agent-stream.js').href);
  chat = await import(pathToFileURL(base + 'chat.js').href);
} catch (e) {
  console.log(JSON.stringify({ error: 'studio_dist_unavailable', detail: String(e && e.message) }));
  process.exit(0);
}

const mode = process.argv[2] || 'stream';
const msg = 'Reply with exactly the single word STUDIOTURN and nothing else.';

if (mode === 'stream') {
  const events = [];
  const emit = (ev, data) => events.push({ ev, data });
  await as.startAgentStream('main', msg, emit);
  await new Promise((r) => {
    const iv = setInterval(() => {
      if (events.some((e) => e.ev === 'done')) { clearInterval(iv); r(); }
    }, 200);
    setTimeout(() => { clearInterval(iv); r(); }, 90000);
  });
  const blocked = events.find((e) => e.ev === 'blocked');
  const done = events.find((e) => e.ev === 'done');
  const deltas = events.filter((e) => e.ev === 'delta').map((e) => e.data.text).join('');
  console.log(JSON.stringify({
    path: 'agent-stream',
    eventNames: events.map((e) => e.ev),
    blocked: blocked ? blocked.data : null,
    doneText: (done && done.data.text ? done.data.text : deltas).slice(0, 160),
  }));
} else {
  try {
    const r = await chat.sendMessage({ agent: 'main', message: msg });
    console.log(JSON.stringify({ path: 'chat.sendMessage', ran: true, replyLen: (r.assistant && r.assistant.text ? r.assistant.text.length : 0) }));
  } catch (e) {
    console.log(JSON.stringify({ path: 'chat.sendMessage', blocked: e && e.name === 'TurnBlockedError', state: e && e.state, message: e && e.message }));
  }
}
process.exit(0);
