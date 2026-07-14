#!/usr/bin/env node
// ClawFactory spend parser (Defect 3). Reads `openclaw gateway usage-cost --json`
// on stdin and prints "TODAY MONTH" (USD, 6dp) using the same date logic as the
// PowerShell Get-Spend. Exits non-zero if the meter data is unusable, so the
// turn gate fails SAFE (blocks) rather than treating unknown as $0.00.
let s = '';
process.stdin.on('data', (d) => (s += d));
process.stdin.on('end', () => {
  let j;
  try {
    j = JSON.parse(s);
  } catch {
    process.exit(2);
  }
  if (!j || !Array.isArray(j.daily)) process.exit(2);
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const today = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
  const month = `${now.getFullYear()}-${pad(now.getMonth() + 1)}`;
  let t = 0;
  let m = 0;
  for (const d of j.daily) {
    if (!d || d.totalCost === undefined) continue;
    const c = Number(d.totalCost) || 0;
    if (d.date === today) t += c;
    if (('' + d.date).startsWith(month)) m += c;
  }
  process.stdout.write(t.toFixed(6) + ' ' + m.toFixed(6));
});
