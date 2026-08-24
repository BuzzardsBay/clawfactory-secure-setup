// enumerate-toolchain-claims.mjs -- find EVERY site in this repo that makes a
// claim about what the software-source (toolchain) switch does.
//
// WHY THIS EXISTS AND WHY IT IS NOT A GREP. The v1.4.0 claim audit searched for
// the SHAPE OF THE OLD SENTENCE and shipped two uncorrected copies of the claim
// it was auditing: a note in the install log the user can read, and the
// toolchain._note in the policy file. A search shaped like the thing you already
// found cannot find the thing you have not.
//
// So this enumerates by CONCEPT, over LOGICAL lines rather than physical ones.
// The shape to fear here is not a template literal (there is no TypeScript in
// this repo); it is a claim broken across a shell backslash continuation or a
// PowerShell string concatenation, where every physical line holds a fragment
// and a line-based scan sees none of them whole. Continuations are joined
// before matching and the hit is reported at the line the claim STARTS on.
//
// Each hit is labelled SHIPPED or repo-only. SHIPPED means the file is in the
// .iss [Files] section, so its text reaches a customer's machine; those are the
// ones a claim audit must be complete over.
//
// A hit is a candidate for a human to read, not a defect.
//
// Usage:  node scripts/enumerate-toolchain-claims.mjs [--json] [--shipped-only]

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..');

const SKIP_DIRS = new Set([
  'node_modules', '.git', 'Output', 'validation-runs', 'dist', 'build',
]);
const SKIP_FILES = new Set(['enumerate-toolchain-claims.mjs']);
const EXT = new Set(['.ps1', '.sh', '.json', '.iss', '.md', '.js', '.mjs', '.txt', '.tsv']);

// The SUBJECT of the claim, not the wording of any known instance.
const SUBJECT = [
  'toolchain', 'software source', 'skill hub', 'clawhub',
  'skill install', 'install skill', 'installing skill', 'skills install',
  'github', 'npm',
];
// Language about the switch's EFFECT. A line with a subject and no effect is an
// incidental mention (a URL, a package name), not a claim.
// Word-bounded, because substring matching on "on" and "off" matches half the
// repo. Deliberately WIDER than the vocabulary of any claim already found:
// close/open and "no longer" are here because a sentence can describe the
// switch's effect without ever naming the switch.
// THIS LIST HAD A HOLE AND THE HOLE WAS MEASURED, not reasoned about. The first
// version omitted "break" and "off", so it silently missed
// clawfactory-grants.ps1:1139 -- "It DEFAULTS ON. Off would break skill
// installation ..." -- which is a live instance of the exact false claim this
// enumerator exists to find. It was caught by a second, cruder pass and the
// pattern was widened here. An audit regex is itself a probe and can be wrong in
// the same way the code was; the fix for that is a known-defective input the
// pattern must find, which grants.ps1:1139 now is.
const EFFECT_RE =
  /\b(switch|switches|switching|switched|toggle|toggles|toggled|toggling|turn|turns|turned|turning|enable|enables|enabled|disable|disables|disabled|close|closes|closed|closing|open|opens|opened|stop|stops|stopped|break|breaks|broke|broken|fail|fails|failing|deny|denies|denied|allow|allows|allowed|reach|reaches|reachable|unreachable|on|off|no longer)\b/;

const has = (t, list) => list.some((s) => t.includes(s));
const isSubject = (t) => has(t.toLowerCase(), SUBJECT);
const isClaim = (text) => {
  const t = text.toLowerCase();
  return has(t, SUBJECT) && EFFECT_RE.test(t);
};

function walk(dir, out) {
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

/** Physical lines folded into logical ones. A line is continued when it ends in
 *  a shell backslash, a PowerShell backtick, or an open string concatenation
 *  (`... ' +`). The returned line number is where the logical line BEGAN. */
function logicalLines(raw) {
  const phys = raw.split(/\r?\n/);
  const out = [];
  let buf = null;
  let start = 0;
  for (let i = 0; i < phys.length; i++) {
    const line = phys[i];
    const continues = /\\\s*$/.test(line) || /`\s*$/.test(line) || /\+\s*$/.test(line);
    if (buf === null) { buf = line; start = i + 1; } else { buf += ' ' + line.trim(); }
    if (!continues) { out.push({ line: start, text: buf }); buf = null; }
  }
  if (buf !== null) out.push({ line: start, text: buf });
  return out;
}

// Which files reach a customer: everything named in the .iss [Files] section.
const issText = readFileSync(join(ROOT, 'ClawFactory-Secure-Setup.iss'), 'utf8');
const shipped = new Set(
  [...issText.matchAll(/Source:\s*"([^"]+)"/g)].map((m) => m[1].replace(/\\/g, '/').toLowerCase()),
);
// setup.ps1 and the .iss itself are compiled INTO the installer, so their text
// ships too even though neither appears in its own [Files] list.
shipped.add('setup.ps1');
shipped.add('clawfactory-secure-setup.iss');
const isShipped = (rel) => shipped.has(rel.toLowerCase()) || shipped.has(rel.toLowerCase().replace(/^\.\//, ''));

const shippedOnly = process.argv.includes('--shipped-only');
const findings = [];
const mentions = [];

for (const file of walk(ROOT, [])) {
  const base = file.slice(file.lastIndexOf(sep) + 1);
  if (SKIP_FILES.has(base)) continue;
  const ext = file.slice(file.lastIndexOf('.'));
  if (!EXT.has(ext)) continue;
  const rel = relative(ROOT, file).split(sep).join('/');
  const ship = isShipped(rel);
  if (shippedOnly && !ship) continue;
  let raw;
  try { raw = readFileSync(file, 'utf8'); } catch { continue; }
  for (const l of logicalLines(raw)) {
    if (!isSubject(l.text)) continue;
    const row = { file: rel, line: l.line, shipped: ship, text: l.text.trim() };
    mentions.push(row);
    if (isClaim(l.text)) findings.push(row);
  }
}

if (process.argv.includes('--json')) {
  console.log(JSON.stringify({ claims: findings, mentions }, null, 2));
} else {
  for (const f of findings) {
    const t = f.text.length > 240 ? f.text.slice(0, 240) + ' ...' : f.text;
    console.log(`${f.shipped ? 'SHIPPED ' : 'repo    '}${f.file}:${f.line}  ${t}`);
  }
  console.log(`\nCLAIM_HITS=${findings.length}  SUBJECT_MENTIONS=${mentions.length}  SHIPPED_CLAIMS=${findings.filter((f) => f.shipped).length}`);
}
