<#
  v1.4.4 box A: diagnose the TC.1d gate_error.

  THIS IS REVISION 2. REVISION 1 WAS DEFECTIVE AND ITS RESULTS ARE RETRACTED.
  ---------------------------------------------------------------------------
  Revision 1 read the gateway token from /home/clawuser/.openclaw/gateway-token,
  a path that does not exist. Both of its turns therefore went out with an EMPTY
  Bearer and came back {"error":{"message":"Unauthorized"}}, never reaching the
  gate logic at all. That is the documented 401 trap: a normal proxy turn needs
  the ClawChat auth shape or it is rejected before anything interesting happens.

  Worse, revision 1's GD.4a PASSED on that Unauthorized response, because it
  only tested for the ABSENCE of '"blocked":true'. An auth error contains no such
  string, so a turn that never ran scored as a turn that was not blocked. Its
  positive control was equally weak: it matched the word 'error', so it confirmed
  "a body came back" and called that "reached the gate".

  Both are the defect class this project keeps paying for: a check that passes
  when nothing happened. Revision 2 fixes them structurally:

    * the token is read the way the toolchain phase reads it, from
      openclaw.json -> gateway.auth.token, and its NON-EMPTINESS is asserted as
      a precondition before any turn verdict is allowed to mean anything;
    * every turn is classified into exactly one of UNAUTHORIZED / GATE_BLOCKED /
      MARKER_OK / OTHER, so "blocked", "never authenticated" and "answered" can
      never collapse into one another;
    * the success marker is a string that appears nowhere else in this probe's
      own output, so the control cannot pass by finding its own echo.

  WHAT IS ACTUALLY UNDER TEST
  ---------------------------
  The toolchain phase got a REAL gate response with zero model tokens:
    clawfactory_gate:{"blocked":true,"state":"gate_error"}
  The provider route was reachable in that same run (TC.1.CTL PASS), so this is
  not the toolchain toggle. The install log warned
    Step-EnableChatCompletions returned exit=1
  and this probe tests whether the two are the same fault.

  If turn 1 is blocked and turn 2 answers, this is a COLD-START regression of the
  v1.0.45 prime-and-retry fix. If both are blocked, it is not a priming problem.
  Both readings are taken in ONE run so they are comparable.

  L17: a new probe inherits NONE of the preconditions of the phases beside it.
#>
param(
    [string]$Transcript = 'C:\cfv\gatediag-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'v1.4.4 box A: gate_error diagnosis (revision 2)' `
    -Transcript $Transcript -Sentinel 'GATEDIAG_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'GD.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) {
    W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'
    Complete-Phase -ResultsJson 'C:\cfv\gatediag-results.json' -MarkerPrefix 'GATEDIAG'
}

# =========================================================================
Section '1. Discover the real unit and file names rather than guessing them'
# Revision 1 asserted on a unit name it invented, and a systemctl query for a
# unit that does not exist reports inactive, which reads exactly like a stopped
# service. Enumerate instead.
$units = Invoke-WslFile -Tag 'gd1' -User 'root' -Body @'
echo "--- every clawfactory unit and its state ---"
systemctl list-units --all --no-legend --no-pager 'clawfactory*' 2>&1 | sed 's/^[[:space:]]*//'
echo "--- every clawfactory unit FILE (catches units that exist but never ran) ---"
systemctl list-unit-files --no-legend --no-pager 'clawfactory*' 2>&1 | sed 's/^[[:space:]]*//'
echo "--- openclaw user units, as clawuser owns the gateway ---"
runuser -u clawuser -- systemctl --user list-units --all --no-legend --no-pager 'openclaw*' 2>&1 | sed 's/^[[:space:]]*//'
echo "--- listeners on 8787 / 8788 ---"
ss -lntp 2>/dev/null | grep -E '8787|8788' || echo "NO_LISTENER_8787_8788"
'@
W $units.Out

$sawAnyUnit = $units.Out -match 'clawfactory'
Record 'GD.1.CTL' 'POSITIVE CONTROL: the unit enumeration returns clawfactory units at all' `
    $(if ($sawAnyUnit) { 'PASS' } else { 'FAIL' }) `
    'an empty enumeration would make every "not active" reading below vacuous'

$proxyListening = $units.Out -match ':8787'
Record 'GD.1' 'Something is listening on 8787, the gating proxy port' `
    $(if ($proxyListening) { 'PASS' } else { 'FAIL' }) `
    "listener on 8787 present=$proxyListening. The root-owned gating proxy owns 8787; the real gateway sits behind it on 8788."

# =========================================================================
Section '2. The gate configuration the proxy reads'
$cfg = Invoke-WslFile -Tag 'gd2' -User 'root' -Body @'
for f in /etc/clawfactory/soul.sha256 /etc/clawfactory/workspace-soul.sha256 /etc/clawfactory/spend.json /etc/clawfactory/gate.json /etc/clawfactory/chatgate.json; do
  if [ -e "$f" ]; then echo "EXISTS $f mode=$(stat -c %a "$f") owner=$(stat -c %U:%G "$f") bytes=$(stat -c %s "$f")"; else echo "ABSENT $f"; fi
done
echo "--- anything spend/meter shaped ---"
find /var/lib/clawfactory /etc/clawfactory -maxdepth 2 \( -name '*spend*' -o -name '*meter*' -o -name '*gate*' \) 2>/dev/null | while read f; do
  echo "FOUND $f mode=$(stat -c %a "$f") owner=$(stat -c %U:%G "$f") bytes=$(stat -c %s "$f")"
done
echo "--- CONTROL: a path that cannot exist must report ABSENT ---"
f=/etc/clawfactory/this-cannot-exist-4b71c.json
if [ -e "$f" ]; then echo "CTL_BAD_EXISTS"; else echo "CTL_ABSENT_OK"; fi
'@
W $cfg.Out
Record 'GD.2.CTL' 'POSITIVE CONTROL: the existence probe tells present from absent' `
    $(if ($cfg.Out -match 'CTL_ABSENT_OK') { 'PASS' } else { 'FAIL' }) `
    'without this, every ABSENT above could mean the test cannot see anything'

# =========================================================================
Section '3. The proxy journal, which is where a gate_error explains itself'
$jr = Invoke-WslFile -Tag 'gd3' -User 'root' -Body @'
for u in clawfactory-chatgate clawfactory-gate clawfactory-proxy clawfactory-chatproxy; do
  echo "===== journalctl -u $u ====="
  journalctl -u "$u" -n 30 --no-pager 2>&1 | tail -30
done
echo "===== any journal line mentioning gate_error ====="
journalctl --no-pager --since "-2 hours" 2>/dev/null | grep -i 'gate_error\|spend\|chatgate' | tail -40 || echo "NO_GATE_ERROR_LINES"
'@
W $jr.Out

# =========================================================================
Section '4. THE SUBJECT: two consecutive turns, with the CORRECT auth shape'
# Marker chosen so it appears nowhere else in this probe's own output.
$turns = Invoke-WslFile -Tag 'gd4' -User 'clawuser' -Body @'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
if [ -z "$TOKEN" ]; then echo "TOKEN_EMPTY"; else echo "TOKEN_PRESENT_LEN=${#TOKEN}"; fi
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: ZQ7GATEPROOF"}]}' > /var/tmp/gd-turn.json
for n in 1 2; do
  echo "===== TURN $n ====="
  curl -s --max-time 200 -X POST http://127.0.0.1:8787/v1/chat/completions \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -H "x-openclaw-agent-id: main" --data @/var/tmp/gd-turn.json | head -c 900
  echo ""
  [ "$n" = "1" ] && sleep 25
done
rm -f /var/tmp/gd-turn.json
'@
W $turns.Out

# PRECONDITION, not a verdict: without a token nothing below is interpretable.
$tokenOk = $turns.Out -match 'TOKEN_PRESENT_LEN=[1-9]'
Require-Precondition -Id 'GD.4.PRE' -Name 'the gateway token was actually read' -Met $tokenOk `
    -Reason 'revision 1 read an empty token and both of its turns returned Unauthorized, which it then scored as "not blocked". Without a token, a turn verdict is a statement about authentication, not about the gate.' | Out-Null

function Get-TurnClass([string]$t) {
    if ($t -match 'ZQ7GATEPROOF')            { return 'MARKER_OK' }
    if ($t -match '"unauthorized"|Unauthorized') { return 'UNAUTHORIZED' }
    if ($t -match '"blocked":true')          { return 'GATE_BLOCKED' }
    if ([string]::IsNullOrWhiteSpace($t))    { return 'EMPTY' }
    return 'OTHER'
}
$p1 = ($turns.Out -split '===== TURN 1 =====')[-1]
$s1 = ($p1 -split '===== TURN 2 =====')[0]
$s2 = if ($turns.Out -match '===== TURN 2 =====') { ($turns.Out -split '===== TURN 2 =====')[-1] } else { '' }
$c1 = Get-TurnClass $s1
$c2 = Get-TurnClass $s2
W "TURN1_CLASS=$c1"
W "TURN2_CLASS=$c2"

Record 'GD.4a' 'Turn 1 returns real model output rather than a gate refusal' `
    $(if ($c1 -eq 'MARKER_OK') { 'PASS' } else { 'FAIL' }) `
    "turn1Class=$c1. Classified into exactly one of MARKER_OK / GATE_BLOCKED / UNAUTHORIZED / EMPTY / OTHER, so a turn that never ran cannot score as a turn that was not blocked."

Record 'GD.4b' 'Turn 2 returns real model output' `
    $(if ($c2 -eq 'MARKER_OK') { 'PASS' } else { 'FAIL' }) `
    "turn2Class=$c2. If turn1=GATE_BLOCKED and turn2=MARKER_OK this is a COLD-START regression of the v1.0.45 prime-and-retry fix. If both are GATE_BLOCKED it is not a priming problem."

Record 'GD.4c' 'DIAGNOSIS: which fault is this' 'INFO' `
    "turn1=$c1 turn2=$c2. GATE_BLOCKED on both => the gate cannot verify at all on a clean install. MARKER_OK on both => TC.1d was transient and the toolchain phase's own warm-up did not cover it. GATE_BLOCKED then MARKER_OK => cold start."

Complete-Phase -ResultsJson 'C:\cfv\gatediag-results.json' -MarkerPrefix 'GATEDIAG'
