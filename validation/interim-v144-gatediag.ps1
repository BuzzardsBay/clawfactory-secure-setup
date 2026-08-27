<#
  v1.4.4 box A: diagnose the TC.1d gate_error, and read the toolchain switch state.

  WHY THIS EXISTS
  ---------------
  The toolchain phase VOIDed on an unmet precondition. Two DIFFERENT causes are
  tangled in its output and they must be separated before either is reported:

    1. TC.1a/1b/1c FAILed because the toolchain switch was OFF. The switchprovider
       phase deliberately leaves it OFF (SP.9), and the toolchain phase asserts a
       FRESH INSTALL has it ON. That is a phase-ordering artifact of running both
       on one box, predicted in section 6.3 of the close-out before dispatch. It
       is NOT a product finding and this probe confirms the mechanism rather than
       assuming it.

    2. TC.1d FAILed because a real agent turn returned
         clawfactory_gate:{"blocked":true,"state":"gate_error"}
       with zero model tokens. The provider route was reachable in the same run
       (TC.1.CTL PASS), so this is NOT the toolchain toggle. It is the gating
       proxy failing to VERIFY, which is a different claim and potentially a
       ship-blocker.

  The install log warned `Step-EnableChatCompletions returned exit=1`, and this
  probe tests whether that warning and the gate_error are the same fault.

  L17: a new probe inherits NONE of the preconditions of the phases beside it, so
  every state this probe depends on is measured here rather than carried over.
#>
param(
    [string]$Transcript = 'C:\cfv\gatediag-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'v1.4.4 box A: gate_error diagnosis and toolchain switch state' `
    -Transcript $Transcript -Sentinel 'GATEDIAG_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'GD.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) {
    W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'
    Complete-Phase -ResultsJson 'C:\cfv\gatediag-results.json' -MarkerPrefix 'GATEDIAG'
}

# =========================================================================
Section '1. The toolchain switch state, to settle cause 1 by measurement'
$sw = Invoke-WslFile -Tag 'gd1' -User 'root' -Body @'
echo "--- policy as the control tool reports it ---"
/usr/local/sbin/clawfactory-toolchainctl status 2>&1 || echo "TOOLCHAINCTL_RC=$?"
echo "--- the live nft set ---"
nft list set inet clawfactory toolchain_ipv4 2>&1 | head -20
'@
W $sw.Out

$switchOff = $sw.Out -match 'enabled=0|TOOLCHAIN=off|"enabled":false'
Record 'GD.1' 'The toolchain switch is OFF, which is what made TC.1a/1b/1c FAIL' `
    $(if ($switchOff) { 'PASS' } else { 'FAIL' }) `
    "switchReportsOff=$switchOff. SP.9 leaves the toggle OFF by design; the toolchain phase asserts a FRESH install has it ON. If this reads OFF, TC.1a/1b/1c are a phase-ordering artifact on a shared box and NOT a product finding."

# =========================================================================
Section '2. Is chatCompletions actually enabled? The install warned exit=1.'
$cc = Invoke-WslFile -Tag 'gd2' -User 'root' -Body @'
echo "--- gating proxy unit ---"
systemctl is-active clawfactory-chatgate.service 2>&1 || true
systemctl is-enabled clawfactory-chatgate.service 2>&1 || true
echo "--- who owns 8787 and 8788 ---"
ss -lntp 2>/dev/null | grep -E '8787|8788' || echo "NO_LISTENER_8787_8788"
echo "--- gate config presence ---"
for f in /etc/clawfactory/spend.json /etc/clawfactory/soul.sha256 /etc/clawfactory/gate.json; do
  if [ -e "$f" ]; then echo "EXISTS $f mode=$(stat -c %a "$f") owner=$(stat -c %U:%G "$f")"; else echo "ABSENT $f"; fi
done
echo "--- gate service journal, last 40 ---"
journalctl -u clawfactory-chatgate.service -n 40 --no-pager 2>&1 | tail -40 || echo "NO_JOURNAL"
'@
W $cc.Out

$gateUp = $cc.Out -match '(?m)^active'
Record 'GD.2' 'The gating proxy service is active' `
    $(if ($gateUp) { 'PASS' } else { 'FAIL' }) `
    "systemctl is-active reported active=$gateUp. The proxy owns :8787 and the real gateway sits behind it on :8788."

# =========================================================================
Section '3. The spend meter, which is what fail-safe-blocks a turn it cannot read'
$sp = Invoke-WslFile -Tag 'gd3' -User 'root' -Body @'
echo "--- spend state files ---"
find /var/lib/clawfactory -maxdepth 2 -name '*spend*' -o -maxdepth 2 -name '*meter*' 2>/dev/null | while read f; do
  echo "FOUND $f mode=$(stat -c %a "$f") owner=$(stat -c %U:%G "$f") bytes=$(stat -c %s "$f")"
done
echo "--- spend meter as the product reports it ---"
if [ -x /usr/local/sbin/clawfactory-spendctl ]; then /usr/local/sbin/clawfactory-spendctl status 2>&1; else echo "NO_SPENDCTL"; fi
'@
W $sp.Out

# =========================================================================
Section '4. THE SUBJECT: two consecutive turns. v1.0.45 primes and retries the meter.'
# The FIRST turn on a cold meter was the v1.0.45 defect. If turn 1 gate_errors
# and turn 2 succeeds, this is a COLD-START regression. If BOTH fail, it is a
# harder fault. Both readings are taken in ONE run so they can be compared.
$turns = Invoke-WslFile -Tag 'gd4' -User 'clawuser' -Body @'
tok=$(cat /home/clawuser/.openclaw/gateway-token 2>/dev/null || echo "")
if [ -z "$tok" ]; then echo "NO_TOKEN"; fi
for n in 1 2; do
  echo "===== TURN $n ====="
  curl -s -m 90 -X POST http://127.0.0.1:8787/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $tok" \
    -H "x-openclaw-agent-id: main" \
    -d '{"model":"openclaw/main","messages":[{"role":"user","content":"Reply with exactly the word GATEDIAGOK and nothing else."}]}' 2>&1
  echo ""
done
'@
W $turns.Out

$t1 = ($turns.Out -split '===== TURN 2 =====')[0]
$t2 = if ($turns.Out -match '===== TURN 2 =====') { ($turns.Out -split '===== TURN 2 =====')[1] } else { '' }
$t1Blocked = $t1 -match '"blocked":true'
$t2Blocked = $t2 -match '"blocked":true'
$t2Ok      = $t2 -match 'GATEDIAGOK'

Record 'GD.4.CTL' 'POSITIVE CONTROL: the probe reached the gate at all (a response body came back)' `
    $(if ($turns.Out -match 'clawfactory_gate|chatcmpl|error') { 'PASS' } else { 'FAIL' }) `
    'without a response body, "blocked" and "unreachable" would be indistinguishable'

Record 'GD.4a' 'Turn 1 on a cold meter is NOT fail-safe blocked' `
    $(if ($t1Blocked) { 'FAIL' } else { 'PASS' }) `
    "turn1Blocked=$t1Blocked. v1.0.45 primes and retries the spend meter so the FIRST turn is not fail-safe blocked."

Record 'GD.4b' 'Turn 2 completes and returns real model output' `
    $(if ($t2Ok -and -not $t2Blocked) { 'PASS' } elseif ($t2Blocked) { 'FAIL' } else { 'FAIL' }) `
    "turn2Blocked=$t2Blocked turn2SaidGATEDIAGOK=$t2Ok. If turn 1 blocks and turn 2 succeeds this is a COLD-START fault; if both block it is not a priming problem."

Complete-Phase -ResultsJson 'C:\cfv\gatediag-results.json' -MarkerPrefix 'GATEDIAG'
