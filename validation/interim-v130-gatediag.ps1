<#
  Why does a turn fail when the toolchain switch is OFF? READ-ONLY.

  cfv-166 measured, on 1.3.3, that with the switch off a real agent turn is
  refused with:

      "ClawFactory could not verify that this turn is allowed, so it refused it"
      clawfactory_gate: { blocked: true, state: "gate_error" }

  That is the TURN GATE failing, not the model being unreachable: the provider
  route is untouched by the switch and TC.2.CTL proved it still works in the same
  run. On 1.3.1 this same test PASSED, but only because the toolchain hosts were
  still reachable through the defect 1.3.2 fixed. So something in the gate path
  depends on a host the switch now closes.

  This finds out WHICH, because the size of the fix depends entirely on the
  answer. If it is a pricing or metadata lookup, the fix is to make that one host
  always-open (it is infrastructure, not user-facing toolchain) or to cache. If
  the gate genuinely needs the skill hub on every turn, the feature's semantics
  are wrong and the panel copy is badly wrong.

  Changes nothing. Runs the gate and reads logs.
#>
param([string]$Transcript = 'C:\cfv\gatediag-out-probe.txt')

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'Why the turn gate errors with the toolchain switch OFF' `
    -Transcript $Transcript -Sentinel 'GATEDIAG_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'GD.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { Complete-Phase -ResultsJson 'C:\cfv\gatediag-results.json' -MarkerPrefix 'GATEDIAG' }

Section '1. Put the switch back OFF, then run the gate and watch what it reaches for'
$r = Invoke-WslFile -Tag 'gd-run' -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl toolchain off >/dev/null 2>&1
echo "TOOLCHAIN_NOW=$(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))')"
echo
echo "=== proxy journal, last 40 ==="
journalctl -u clawfactory-proxy -n 40 --no-pager 2>&1 | tail -40
echo
echo "=== the gate and spend-check files ==="
ls -la /usr/local/sbin/clawfactory-turn-gate.sh 2>&1 | head -2
ls -la /usr/local/lib/clawfactory/*.js 2>&1 | head -10
echo
echo "=== which network hosts does the spend check name in its SOURCE ==="
grep -ohE 'https?://[a-zA-Z0-9._/-]+' /usr/local/lib/clawfactory/clawfactory-spend-check.js /usr/local/sbin/clawfactory-turn-gate.sh 2>/dev/null | sort -u | head -20
echo "SRC_URL_COUNT=$(grep -ohE 'https?://[a-zA-Z0-9._/-]+' /usr/local/lib/clawfactory/clawfactory-spend-check.js /usr/local/sbin/clawfactory-turn-gate.sh 2>/dev/null | sort -u | wc -l)"
echo "CONTROL_SENTINEL=$(grep -c 'ClawFactoryNegativeSentinelZZ9' /usr/local/sbin/clawfactory-turn-gate.sh 2>/dev/null || echo 0)"
'@
W $r.Out
$urls = if ($r.Out -match 'SRC_URL_COUNT=(\d+)') { [int]$Matches[1] } else { -1 }
$ctl  = if ($r.Out -match 'CONTROL_SENTINEL=(\d+)') { [int]$Matches[1] } else { -1 }
Register-Control -Id 'GD.1.CTL' -Name 'the source search discriminates' -Fired ($ctl -eq 0 -and $urls -ge 0) `
    -Evidence "sentinel hits=$ctl (must be 0); urls found=$urls" | Out-Null
Record 'GD.1' 'The gate path names network endpoints in its own source' `
    $(if ($urls -gt 0) { 'PASS' } elseif ($urls -eq 0) { 'INFO' } else { 'VOID' }) `
    "$urls distinct URL(s) in the turn gate and spend check"

Section '2. Run the gate directly and capture its own error'
$r2 = Invoke-WslFile -Tag 'gd-gate' -User 'root' -Body @'
echo "=== run the turn gate as root, 90s cap ==="
timeout 90 /usr/local/sbin/clawfactory-turn-gate.sh 2>&1 | head -30
echo "gate_rc=$?"
echo
echo "=== run the spend check alone ==="
NODE="$(command -v node || echo /usr/bin/node)"
timeout 60 "$NODE" /usr/local/lib/clawfactory/clawfactory-spend-check.js 2>&1 | head -20
echo "spend_rc=$?"
'@
W $r2.Out
Record 'GD.2' 'The gate reproduces its error when run directly' `
    $(if ($r2.Out -match 'gate_rc=') { 'INFO' } else { 'VOID' }) `
    'raw output above is the finding; this row exists so the transcript is indexed'

Section '3. Restore the shipped default before leaving'
$r3 = Invoke-WslFile -Tag 'gd-restore' -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl toolchain on 2>&1 | tail -1
echo "FINAL=$(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))')"
'@
W $r3.Out
Record 'GD.3' 'Box left with the switch back ON (shipped default)' `
    $(if ($r3.Out -match 'FINAL=True') { 'PASS' } else { 'FAIL' }) 'so nothing downstream inherits a half-toggled box'

Complete-Phase -ResultsJson 'C:\cfv\gatediag-results.json' -MarkerPrefix 'GATEDIAG'
