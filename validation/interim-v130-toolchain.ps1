<#
  v1.3.0 validation: the TOOLCHAIN ACCESS TOGGLE.

  Runs in the interactive auto-logon session on the VM, through the file-based
  WSL channel, same as every other phase. Uses the phase runner, so a missing
  positive control or an unmet precondition voids the phase rather than producing
  a verdict from an absent subject.

  WHAT IS ACTUALLY BEING TESTED, AND WHY THE OBVIOUS TEST IS THE WRONG ONE
  ------------------------------------------------------------------------
  The claim is not "the toolchain hosts are denied". They are reachable by
  default, on purpose. The claim is that the USER'S SWITCH WORKS IN BOTH
  DIRECTIONS AND STAYS PUT. So the shape of every test here is a transition:
  reachable, switch off, unreachable, and crucially still unreachable after the
  thing most likely to undo it.

  THE FAILURE THIS PHASE EXISTS TO CATCH. The software sources used to live in
  @allowed_ipv4, which is refreshed ADDITIVELY by hostname every five hours with
  element timeouts, so nothing is ever removed from it deliberately. Had they
  stayed there, switching the toggle off would have appeared to work and been
  silently undone by a timer up to five hours later, on a customer machine, long
  after any validation went green. Test 4 runs the REAL refresh unit, not a
  simulation, and is the single most important test in this file.

  ADDRESS-LEVEL, NOT HOSTNAME-LEVEL. Enforcement is by resolved address, so a
  toolchain host that shares an address with something else already reachable
  stays reachable when the switch is off. Test 2 therefore checks BOTH that the
  hosts became unreachable AND that the addresses actually left the set, because
  the second is the property the product controls and the first is the property
  the user experiences. Where they disagree, the disagreement is the finding.

  L17: a new probe inherits none of the preconditions of the ones beside it. The
  agent is warmed before any load-bearing turn.
#>
param(
    [string]$Transcript = 'C:\cfv\toolchain-out-probe.txt',
    [switch]$PostReboot
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

$tag = if ($PostReboot) { 'POSTREBOOT' } else { 'PRE' }
Start-Phase -Name "ClawFactory v1.3.0 toolchain access toggle, pass=$tag" `
    -Transcript $Transcript -Sentinel 'TOOLCHAIN_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id "TC.CHAN.$tag" -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) {
    W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'
    Complete-Phase -ResultsJson "C:\cfv\toolchain-results-$tag.json" -MarkerPrefix "TOOLCHAIN_$tag"
}

# Probe helper, shared by every reachability test below. A raw TCP connect rather
# than curl: it is the CONNECTION the firewall gates, and an HTTP-level failure
# would be a different measurement wearing the same result.
$ProbeFn = @'
probe() {
  if timeout 10 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then echo "$1:$2 CONNECTED"; else echo "$1:$2 blocked"; fi
}
'@

function Get-ToolchainState {
    param([string]$Label)
    $r = Invoke-WslFile -Tag "tc-state-$Label" -User 'root' -Body @'
echo "POLICY_ENABLED=$(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))' 2>/dev/null || echo unknown)"
echo "SET_COUNT=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)"
echo "FILE_COUNT=$(wc -l < /etc/clawfactory/toolchain-ips.txt 2>/dev/null | tr -d ' ')"
echo "SET_EXISTS=$(nft list set inet clawfactory toolchain_ipv4 >/dev/null 2>&1 && echo yes || echo no)"
echo "ACCEPT_PRESENT=$(nft list chain inet clawfactory output 2>/dev/null | grep -qE '@toolchain_ipv4 tcp dport 443 accept' && echo yes || echo no)"
'@
    W $r.Out
    return @{
        Policy = if ($r.Out -match 'POLICY_ENABLED=(\w+)') { $Matches[1] } else { 'unknown' }
        SetCount = if ($r.Out -match 'SET_COUNT=(\d+)') { [int]$Matches[1] } else { -1 }
        FileCount = if ($r.Out -match 'FILE_COUNT=(\d+)') { [int]$Matches[1] } else { -1 }
        SetExists = $r.Out -match 'SET_EXISTS=yes'
        Accept = $r.Out -match 'ACCEPT_PRESENT=yes'
        Raw = $r.Out
    }
}

# =========================================================================
Section '0. The control is INSTALLED. Checked before anything is measured through it.'
# An absent set and a switched-off toggle produce identical reachability results,
# so the mechanism is checked directly first, exactly as Guard 3 does.
$inst = Invoke-WslFile -Tag "tc-inst-$tag" -User 'root' -Body @'
echo "--- the resolver ---"
if [ -e /usr/local/sbin/clawfactory-toolchain.sh ]; then stat -c 'PRESENT %n %U:%G %a' /usr/local/sbin/clawfactory-toolchain.sh; else echo "ABSENT /usr/local/sbin/clawfactory-toolchain.sh"; fi
echo "--- CONTROL: a path that must be absent ---"
[ -e /usr/local/sbin/clawfactory-not-a-real-resolver.sh ] && echo "CONTROL FAILED" || echo "CONTROL OK (absent)"
echo "--- the third set and its accept ---"
nft list set inet clawfactory toolchain_ipv4 >/dev/null 2>&1 && echo "SET_PRESENT=yes" || echo "SET_PRESENT=no"
nft list chain inet clawfactory output 2>/dev/null | grep -qE '@toolchain_ipv4 tcp dport 443 accept' && echo "ACCEPT_443=yes" || echo "ACCEPT_443=no"
echo "--- CONTROL: a set name that must not exist ---"
nft list set inet clawfactory not_a_real_set >/dev/null 2>&1 && echo "CONTROL FAILED" || echo "CONTROL OK (no such set)"
echo "--- the tripwire, which must now cover all three sets ---"
/usr/local/sbin/clawfactory-fw-assert.sh 2>&1; echo "fw_assert_rc=$?"
echo "--- the toolchain hosts must NOT be in the provider set's persisted list ---"
echo "AUX_FILE_HAS_GITHUB=$(grep -c . /etc/clawfactory/allowed-ips.txt 2>/dev/null || echo 0) addresses in allowed-ips.txt"
'@
W $inst.Out
$ctlSane = ($inst.Out -match 'CONTROL OK \(absent\)') -and ($inst.Out -match 'CONTROL OK \(no such set\)')
Register-Control -Id "TC.0.CTL.$tag" -Name 'the installation probe discriminates present from absent' `
    -Fired $ctlSane -Evidence 'a bogus path was not found and a bogus set name did not resolve' | Out-Null
Record "TC.0a.$tag" 'The toolchain toggle is installed: resolver, third nft set, 443-scoped accept' `
    $(if (($inst.Out -match 'SET_PRESENT=yes') -and ($inst.Out -match 'ACCEPT_443=yes')) { 'PASS' } else { 'FAIL' }) `
    "SET_PRESENT / ACCEPT_443 read from the live ruleset"
Record "TC.0b.$tag" 'The resolver is root-owned and not agent-writable' `
    $(if ($inst.Out -match 'PRESENT /usr/local/sbin/clawfactory-toolchain\.sh root:root 755') { 'PASS' } else { 'FAIL' }) `
    'expected root:root 755'
Record "TC.0c.$tag" 'The chain-shape tripwire passes and now covers all three allowlist accepts' `
    $(if ($inst.Out -match 'fw_assert_rc=0') { 'PASS' } else { 'FAIL' }) 'fw-assert checks provider, read-fetch and toolchain accepts by name'

# =========================================================================
Section '1. Fresh install: the switch is ON and the software sources are reachable for uid 1000'
$s0 = Get-ToolchainState -Label "fresh-$tag"
Record "TC.1a.$tag" 'A fresh install has the toolchain switch ON' `
    $(if ($s0.Policy -eq 'True') { 'PASS' } else { 'FAIL' }) "policy reports enabled=$($s0.Policy)"
Record "TC.1b.$tag" 'The switch being on has actually populated the set' `
    $(if ($s0.SetCount -gt 0) { 'PASS' } else { 'FAIL' }) "$($s0.SetCount) address(es) live, $($s0.FileCount) persisted"

$reach1 = Invoke-WslFile -Tag "tc-reach-on-$tag" -User 'clawuser' -Body @"
echo "whoami=`$(id -un) uid=`$(id -u)"
$ProbeFn
echo '--- SUBJECT (MUST be reachable while the switch is ON) ---'
for h in api.github.com registry.npmjs.org raw.githubusercontent.com; do probe `$h 443; done
echo '--- CONTROL A (MUST SUCCEED): the provider route, which no switch may affect ---'
probe api.anthropic.com 443
echo '--- CONTROL B (MUST FAIL): a site nobody allowed, so the probe is not simply saying yes ---'
probe example.org 443
"@
W $reach1.Out
$tcOn      = ($reach1.Out -match 'api\.github\.com:443 CONNECTED') -and ($reach1.Out -match 'registry\.npmjs\.org:443 CONNECTED')
$provOn    = $reach1.Out -match 'api\.anthropic\.com:443 CONNECTED'
$negOn     = $reach1.Out -match 'example\.org:443 blocked'
Register-Control -Id "TC.1.CTL.$tag" -Name 'the reachability probe can both connect and be refused in the same run' `
    -Fired ($provOn -and $negOn) `
    -Evidence "provider reachable=$provOn (must be true); un-allowlisted site blocked=$negOn (must be true)" | Out-Null
Record "TC.1c.$tag" 'With the switch ON, the software sources are reachable for uid 1000' `
    $(if ($tcOn) { 'PASS' } else { 'FAIL' }) "github and npm reachable=$tcOn"

# --- TC.3's CONTROL TURN, and it is load-bearing ----------------------------
# RE-SPECIFIED 2026-08-18, card #257. The old TC.3 ran ONE turn, with the toggle
# OFF, and recorded FAIL when it did not complete. That attribution was wrong.
# On cfv-167 the turn failed with the toggle OFF and failed IDENTICALLY with it
# ON, dropping to the same provider address both times, so the finding was never
# about the toggle at all. Only a control turn with the toggle ON exposed that,
# and the old test had none, so the obvious and wrong conclusion was sitting
# right there for anyone who ran only the subject.
#
# So the control runs HERE, while the toggle is still ON, and TC.3 below is
# gated on it. A turn that cannot complete with the toggle ON says nothing
# whatever about a toggle that has not been touched yet: it says the agent
# cannot reach its model, which is a different and larger finding.
#
# The failure string is the ABSENCE of TOOLCHAINONOK. That token appears nowhere
# else in this probe's own output, so this control cannot pass by finding its own
# echo. Warmed first (L17) for the same reason TC.3 is: a cold first turn failing
# would be recorded as a product verdict it has nothing to do with.
W '--- warming the agent (L17), then the TC.3 control turn with the toggle still ON ---'
$null = Invoke-WslFile -Tag "tc-warm-$tag" -User 'clawuser' -Body @'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: WARMUP"}]}' > /var/tmp/tc-warm.json
curl -s --max-time 120 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/var/tmp/tc-warm.json | head -c 400
rm -f /var/tmp/tc-warm.json
echo
'@
$ctlTurn = Invoke-WslFile -Tag "tc-turn-on-$tag" -User 'clawuser' -Body @'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: TOOLCHAINONOK"}]}' > /var/tmp/tc-on.json
curl -s --max-time 200 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/var/tmp/tc-on.json | head -c 900
rm -f /var/tmp/tc-on.json
echo
'@
W $ctlTurn.Out
$tc3ControlOk = $ctlTurn.Out -match 'TOOLCHAINONOK'
Record "TC.1d.$tag" 'A real agent turn completes with the toolchain toggle ON' `
    $(if ($tc3ControlOk) { 'PASS' } else { 'FAIL' }) `
    'this is the control turn for TC.3. It is recorded as its own row as well as gating TC.3, because "the agent cannot reach its model with the toggle ON" is a ship-blocker in its own right and must not be visible only as the VOID reason of another row.'

# =========================================================================
Section '2. Switch OFF: the sources become unreachable AND the addresses actually leave the set'
$off = Invoke-WslFile -Tag "tc-off-$tag" -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl toolchain off 2>&1 | tail -1
'@
W $off.Out
Record "TC.2a.$tag" 'The control tool accepts the switch-off and reports success' `
    $(if ($off.Out -match '"ok":true') { 'PASS' } else { 'FAIL' }) 'root-only tool, called the same way Studio calls it'

$s1 = Get-ToolchainState -Label "off-$tag"
# BOTH halves. "Unreachable" is what the user experiences; "the addresses are
# gone" is the property the product actually controls. Checking only the first
# would pass on a box where the switch did nothing and the host simply happened
# to be down.
Record "TC.2b.$tag" 'Switching off actually emptied the live set and the persisted file' `
    $(if ($s1.SetCount -eq 0 -and $s1.FileCount -eq 0) { 'PASS' } else { 'FAIL' }) `
    "live set=$($s1.SetCount) addresses, persisted file=$($s1.FileCount) lines (both must be 0)"

$reach2 = Invoke-WslFile -Tag "tc-reach-off-$tag" -User 'clawuser' -Body @"
$ProbeFn
echo '--- SUBJECT (MUST be blocked while the switch is OFF) ---'
for h in api.github.com registry.npmjs.org raw.githubusercontent.com; do probe `$h 443; done
echo '--- CONTROL (MUST SUCCEED): the provider route is NOT affected by this switch ---'
probe api.anthropic.com 443
"@
W $reach2.Out
$tcOff   = -not ($reach2.Out -match '(api\.github\.com|registry\.npmjs\.org|raw\.githubusercontent\.com):443 CONNECTED')
$provOff = $reach2.Out -match 'api\.anthropic\.com:443 CONNECTED'
Register-Control -Id "TC.2.CTL.$tag" -Name 'the provider route still works with the toolchain switched off' `
    -Fired $provOff -Evidence 'this control failing would void every block above, and would also mean a bricked product' | Out-Null
Record "TC.2c.$tag" 'With the switch OFF, the software sources are unreachable for uid 1000' `
    $(if ($tcOff) { 'PASS' } else { 'FAIL' }) "github, npm and raw all blocked=$tcOff"

# =========================================================================
Section '3. CONTROL-GATED: a real agent turn still completes with the switch OFF'
# The point of the whole design. Narrowing the box must not brick the agent, and
# an agent that cannot reach its model is a bricked product regardless of how
# good the firewall looks.
#
# DO NOT RE-RUN THIS TEST UNTIL THE PROVIDER ROUTE WORKS. Until then the control
# below cannot pass, so this test cannot say anything, and a VOID here is the
# correct and only available outcome. Re-running it to see it go red again buys
# nothing and invites the same attribution error a second time. See card #257 and
# docs/session_reports/2026-08-18_provider_route_source_read.md.
#
# THE CONTROL IS LOAD-BEARING, which is the whole of the re-specification. The
# toggle-ON turn recorded at TC.1d must have completed for the toggle-OFF result
# to mean anything. If it did not, the subject is NOT run and TC.3 records VOID
# with a named reason, because a turn that already fails with the toggle ON
# cannot become evidence about the toggle by being run again with it OFF. That is
# precisely the inference cfv-166 made and cfv-167 refuted.
$tc3Pre = Require-Precondition -Id "TC.3.PRE.$tag" `
    -Name 'a real agent turn completes with the toolchain toggle ON' `
    -Met $tc3ControlOk `
    -Reason 'the toggle-OFF turn is only interpretable if the same turn succeeds with the toggle ON in the SAME run. A turn failing in both states is a provider-route failure, not a toggle finding, and recording it as a toggle finding is the error this rewrite exists to prevent.'

if (-not $tc3Pre) {
    Record "TC.3.$tag" 'A real agent turn completes end to end with the toolchain switch OFF' 'VOID' `
        'NOT RUN. The control turn at TC.1d did not complete with the toggle ON, so the agent could not reach its model before the toggle was touched. Nothing measured after that point is a statement about the toggle. Fix the provider route, then re-run.'
    W '--- TC.3 subject deliberately NOT run: its control did not fire ---'
} else {
$turnBody = @'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: TOOLCHAINOFFOK"}]}' > /var/tmp/tc-turn.json
curl -s --max-time 180 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/var/tmp/tc-turn.json
rm -f /var/tmp/tc-turn.json
'@
$turn = Invoke-WslFile -Tag "tc-turn-$tag" -User 'clawuser' -Body $turnBody
W $turn.Out
if ($turn.Out -notmatch 'TOOLCHAINOFFOK') {
    W '--- cold start suspected; one retry, so a cold turn is not reported as a toolchain failure ---'
    Start-Sleep -Seconds 25
    $turn = Invoke-WslFile -Tag "tc-turn2-$tag" -User 'clawuser' -Body $turnBody
    W $turn.Out
}
$turnOk = $turn.Out -match 'TOOLCHAINOFFOK'
Record "TC.3.$tag" 'A real agent turn completes end to end with the toolchain switch OFF' `
    $(if ($turnOk) { 'PASS' } else { 'FAIL' }) `
    'the switch narrows the box without bricking the agent; the model reply is the evidence. This verdict is only interpretable because the control turn at TC.1d completed with the toggle ON in this same run.'
}

# =========================================================================
Section '4. THE TEST THIS FEATURE EXISTS FOR: the switch survives a REAL five-hourly refresh'
# Not simulated. The shipped systemd unit is started, which is the same code path
# that runs unattended on a customer machine four hours after they flipped the
# switch. Had the toolchain hosts stayed in the additively-refreshed provider
# set, this is where the route would silently come back.
$refresh = Invoke-WslFile -Tag "tc-refresh-$tag" -User 'root' -Body @'
echo "--- BEFORE ---"
echo "SET_BEFORE=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)"
echo "--- running the SHIPPED refresh unit, not a simulation ---"
systemctl start clawfactory-allow-providers.service
sleep 3
systemctl is-active clawfactory-allow-providers.service 2>&1 | head -1
journalctl -u clawfactory-allow-providers.service -n 25 --no-pager 2>/dev/null | tail -25
echo "--- AFTER ---"
echo "SET_AFTER=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)"
echo "POLICY_AFTER=$(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))')"
echo "--- CONTROL: the refresh really did run and really does add PROVIDER addresses ---"
echo "PROVIDER_SET_AFTER=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)"
'@
W $refresh.Out
$setAfter  = if ($refresh.Out -match 'SET_AFTER=(\d+)') { [int]$Matches[1] } else { -1 }
$provAfter = if ($refresh.Out -match 'PROVIDER_SET_AFTER=(\d+)') { [int]$Matches[1] } else { -1 }
# THE CONTROL THAT MAKES THIS TEST MEAN ANYTHING. If the refresh did not actually
# do any work, "the toolchain addresses did not come back" is true for the wrong
# reason and proves nothing. The provider set being populated shows the refresh
# ran and did add addresses, just not these ones.
Register-Control -Id "TC.4.CTL.$tag" -Name 'the refresh actually ran and actually added provider addresses' `
    -Fired ($provAfter -gt 0) `
    -Evidence "provider set holds $provAfter addresses after the refresh; without this, 'nothing came back' would be indistinguishable from 'the refresh did nothing'" | Out-Null
Record "TC.4.$tag" 'A real five-hourly refresh does NOT re-open a route the user closed' `
    $(if ($setAfter -eq 0) { 'PASS' } else { 'FAIL' }) `
    "toolchain set holds $setAfter addresses after the refresh (must be 0); policy still reports $(if ($refresh.Out -match 'POLICY_AFTER=(\w+)') { $Matches[1] } else { '?' })"

$reach3 = Invoke-WslFile -Tag "tc-reach-postrefresh-$tag" -User 'clawuser' -Body @"
$ProbeFn
echo '--- SUBJECT (MUST still be blocked after the refresh) ---'
for h in api.github.com registry.npmjs.org; do probe `$h 443; done
echo '--- CONTROL (MUST SUCCEED) ---'
probe api.anthropic.com 443
"@
W $reach3.Out
Record "TC.4b.$tag" 'The sources are still unreachable after the refresh, measured rather than inferred' `
    $(if (-not ($reach3.Out -match '(api\.github\.com|registry\.npmjs\.org):443 CONNECTED')) { 'PASS' } else { 'FAIL' }) `
    'the set count and the actual reachability are two different claims; both are checked'

# =========================================================================
Section '5. Switching back ON restores reachability, so the switch works in BOTH directions'
$on = Invoke-WslFile -Tag "tc-on-$tag" -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl toolchain on 2>&1 | tail -1
'@
W $on.Out
$s2 = Get-ToolchainState -Label "backon-$tag"
$reach4 = Invoke-WslFile -Tag "tc-reach-backon-$tag" -User 'clawuser' -Body @"
$ProbeFn
for h in api.github.com registry.npmjs.org; do probe `$h 443; done
"@
W $reach4.Out
$backOn = ($reach4.Out -match 'api\.github\.com:443 CONNECTED') -and ($reach4.Out -match 'registry\.npmjs\.org:443 CONNECTED')
Record "TC.5.$tag" 'Switching back ON restores the route (the switch is reversible, not one-way)' `
    $(if ($backOn -and $s2.SetCount -gt 0) { 'PASS' } else { 'FAIL' }) `
    "set repopulated to $($s2.SetCount) addresses; github and npm reachable again=$backOn"

# =========================================================================
Section '6. The AGENT cannot change the switch, across every channel Guard 3 covered'
$tamper = Invoke-WslFile -Tag "tc-tamper-$tag" -User 'clawuser' -Body @'
echo "whoami=$(id -un) uid=$(id -u)"
echo '=== 1. write the policy file that holds the switch ==='
sh -c 'echo x >> /etc/clawfactory/egress-policy.json' 2>&1 | head -2
echo '=== 2. rewrite the switch value directly with node ==='
node -e 'const fs=require("fs");const p="/etc/clawfactory/egress-policy.json";const j=JSON.parse(fs.readFileSync(p,"utf8"));j.toolchain={enabled:true};fs.writeFileSync(p,JSON.stringify(j))' 2>&1 | head -2
echo '=== 3. write the persisted address list the boot path reads ==='
sh -c 'echo 9.9.9.9 >> /etc/clawfactory/toolchain-ips.txt' 2>&1 | head -2
echo '=== 4. write the firewall config ==='
sh -c 'echo x >> /etc/nftables.conf' 2>&1 | head -2
echo '=== 5. run the root-only control tool ==='
/usr/local/sbin/clawfactory-fetchctl toolchain on 2>&1 | head -2
echo '=== 6. run it via node, in case the mode on the wrapper was the only guard ==='
node /usr/local/sbin/clawfactory-fetchctl.js toolchain on 2>&1 | head -2
echo '=== 7. run the toolchain resolver directly ==='
/usr/local/sbin/clawfactory-toolchain.sh 2>&1 | head -2
echo '=== 8. add an element to the third set directly ==='
nft add element inet clawfactory toolchain_ipv4 '{ 9.9.9.9 }' 2>&1 | head -2
/usr/sbin/nft add element inet clawfactory toolchain_ipv4 '{ 9.9.9.9 }' 2>&1 | head -2
echo '=== 9. restart the refresh unit so a tampered file would be applied ==='
systemctl restart clawfactory-allow-providers.service 2>&1 | head -2
echo '=== 10. read the control tool at all ==='
head -1 /usr/local/sbin/clawfactory-fetchctl.js 2>&1 | head -1
echo '=== CONTROL: uid 1000 CAN write somewhere it owns, so the refusals above are real ==='
echo ok > /tmp/tc-control && cat /tmp/tc-control && rm -f /tmp/tc-control
'@
W $tamper.Out
$ctlWritable = $tamper.Out -match '(?m)^ok$'
Register-Control -Id "TC.6.CTL.$tag" -Name 'uid 1000 can write somewhere it owns, so the refusals above are real refusals' `
    -Fired $ctlWritable -Evidence 'without this, ten failures would only prove the probe could not write anywhere at all' | Out-Null

# Verified from ROOT afterwards. Asking the agent whether its tampering worked is
# asking the thing under test to grade itself.
$verify = Invoke-WslFile -Tag "tc-tamper-verify-$tag" -User 'root' -Body @'
echo "SWITCH_AFTER_TAMPER=$(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))' 2>/dev/null || echo PARSE_FAILED)"
nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -q '9\.9\.9\.9' && echo "INJECTED_IP=yes" || echo "INJECTED_IP=no"
grep -q '9\.9\.9\.9' /etc/clawfactory/toolchain-ips.txt 2>/dev/null && echo "INJECTED_FILE=yes" || echo "INJECTED_FILE=no"
stat -c 'POLICY_MODE %a %U:%G' /etc/clawfactory/egress-policy.json
'@
W $verify.Out
$noInject = ($verify.Out -match 'INJECTED_IP=no') -and ($verify.Out -match 'INJECTED_FILE=no')
Record "TC.6.$tag" 'The agent cannot change the toolchain switch through any channel it can reach' `
    $(if ($noInject) { 'PASS' } else { 'FAIL' }) `
    "no injected address in the live set or the persisted file; ten channels attempted"

# =========================================================================
Section '7. REGRESSION: read-fetch add, reach and revoke still work alongside the third set'
$rf = Invoke-WslFile -Tag "tc-rf-$tag" -User 'root' -Body @'
SUBJ=example.org
echo "=== add ==="
/usr/local/sbin/clawfactory-fetchctl add "$SUBJ" 2>&1 | tail -1
echo "RF_SET=$(nft list set inet clawfactory read_fetch_ipv4 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)"
echo "TC_SET_UNTOUCHED=$(nft list set inet clawfactory toolchain_ipv4 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)"
'@
W $rf.Out
$rfReach = Invoke-WslFile -Tag "tc-rf-reach-$tag" -User 'clawuser' -Body @"
$ProbeFn
probe example.org 443
"@
W $rfReach.Out
$rfOn = $rfReach.Out -match 'example\.org:443 CONNECTED'
$rfRevoke = Invoke-WslFile -Tag "tc-rf-revoke-$tag" -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl remove example.org 2>&1 | tail -1
echo "RF_SET_AFTER=$(nft list set inet clawfactory read_fetch_ipv4 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)"
echo "TC_SET_STILL=$(nft list set inet clawfactory toolchain_ipv4 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)"
'@
W $rfRevoke.Out
$rfRevReach = Invoke-WslFile -Tag "tc-rf-revreach-$tag" -User 'clawuser' -Body @"
$ProbeFn
probe example.org 443
"@
W $rfRevReach.Out
$rfOff = $rfRevReach.Out -match 'example\.org:443 blocked'
Record "TC.7a.$tag" 'G3.3a regression: a user-added destination still becomes reachable' `
    $(if ($rfOn) { 'PASS' } else { 'FAIL' }) 'read-fetch add, with the third set present'
Record "TC.7b.$tag" 'G3.3c regression: revoking still removes the route' `
    $(if ($rfOff) { 'PASS' } else { 'FAIL' }) 'read-fetch remove, with the third set present'
Record "TC.7c.$tag" 'The two user-facing sets do not disturb each other' `
    $(if (($rfRevoke.Out -match 'TC_SET_STILL=(\d+)') -and ([int]$Matches[1] -gt 0)) { 'PASS' } else { 'FAIL' }) `
    'the toolchain set kept its addresses across a read-fetch add and revoke'

# =========================================================================
Section '8. The tripwire FAILS the unit when the third set or its accept is removed'
# A tripwire that has never been seen to fire is a tripwire nobody has tested.
# Both removals are performed and then UNDONE, and the undo is verified, because
# a test that leaves the firewall broken has created the defect it was checking
# for.
$trip = Invoke-WslFile -Tag "tc-trip-$tag" -User 'root' -Body @'
echo "=== baseline: the tripwire passes on an intact chain ==="
/usr/local/sbin/clawfactory-fw-assert.sh >/dev/null 2>&1; echo "baseline_rc=$?"

# FAULT A: remove the ACCEPT RULE, by handle.
#
# NOT by deleting the set. nft refuses to delete a set that a rule still
# references ("Device or resource busy"), so a delete-the-set fault would fail to
# inject and the tripwire would then "pass" for the wrong reason -- a fault
# injection that does not inject is exactly the absent-subject problem this
# harness exists to catch. The attempt is still made below and its refusal
# recorded, because "the set cannot be removed while the accept references it"
# is itself a useful property.
echo "=== fault A: delete the toolchain ACCEPT RULE by handle ==="
H=$(nft -a list chain inet clawfactory output 2>/dev/null | grep '@toolchain_ipv4' | grep -oE 'handle [0-9]+' | awk '{print $2}' | head -1)
echo "accept_rule_handle=$H"
if [ -n "$H" ]; then
  nft delete rule inet clawfactory output handle "$H" 2>&1 | head -2
  echo "ACCEPT_GONE=$(nft list chain inet clawfactory output 2>/dev/null | grep -qE '@toolchain_ipv4 tcp dport 443 accept' && echo no || echo yes)"
else
  echo "ACCEPT_GONE=no (could not read a handle; the fault was NOT injected)"
fi
/usr/local/sbin/clawfactory-fw-assert.sh 2>&1 | grep -i 'toolchain' | head -3
/usr/local/sbin/clawfactory-fw-assert.sh >/dev/null 2>&1; echo "faultA_rc=$?"

echo "=== fault B (recorded, expected to be REFUSED): delete the set while the accept exists ==="
/usr/local/sbin/clawfactory-fw-apply.sh >/dev/null 2>&1
/usr/local/sbin/clawfactory-toolchain.sh >/dev/null 2>&1
nft delete set inet clawfactory toolchain_ipv4 2>&1 | head -2
echo "SET_STILL_THERE_AFTER_DELETE_ATTEMPT=$(nft list set inet clawfactory toolchain_ipv4 >/dev/null 2>&1 && echo yes || echo no)"

echo "=== restore, and prove the restore worked ==="
/usr/local/sbin/clawfactory-fw-apply.sh >/dev/null 2>&1
/usr/local/sbin/clawfactory-toolchain.sh >/dev/null 2>&1
/usr/local/sbin/clawfactory-read-fetch.sh >/dev/null 2>&1
/usr/local/sbin/clawfactory-fw-assert.sh >/dev/null 2>&1; echo "restored_rc=$?"
nft list set inet clawfactory toolchain_ipv4 >/dev/null 2>&1 && echo "SET_BACK=yes" || echo "SET_BACK=no"
nft list chain inet clawfactory output 2>/dev/null | grep -qE '@toolchain_ipv4 tcp dport 443 accept' && echo "ACCEPT_BACK=yes" || echo "ACCEPT_BACK=no"
'@
W $trip.Out
$baseRc  = if ($trip.Out -match 'baseline_rc=(\d+)') { [int]$Matches[1] } else { -1 }
$faultRc = if ($trip.Out -match 'faultA_rc=(\d+)') { [int]$Matches[1] } else { -1 }
$restRc  = if ($trip.Out -match 'restored_rc=(\d+)') { [int]$Matches[1] } else { -1 }
$faultInjected = $trip.Out -match 'ACCEPT_GONE=yes'
# TWO controls, because this test has two ways to score a false pass. A tripwire
# that ALWAYS fails would "detect" the fault without detecting anything, and a
# fault that never got injected would leave the tripwire correctly passing while
# this test read it as a miss.
Register-Control -Id "TC.8.CTL.$tag" -Name 'the tripwire passes on an intact chain, and the fault was genuinely injected and then undone' `
    -Fired (($baseRc -eq 0) -and ($restRc -eq 0) -and $faultInjected) `
    -Evidence "baseline_rc=$baseRc restored_rc=$restRc accept-actually-removed=$faultInjected" | Out-Null
Record "TC.8.$tag" 'The tripwire FAILS the unit when the toolchain accept rule is removed' `
    $(if ($faultRc -ne 0) { 'PASS' } else { 'FAIL' }) `
    "fw-assert returned $faultRc with the accept deleted (must be non-zero); $baseRc intact and $restRc after restore"
Record "TC.8c.$tag" 'The toolchain set cannot be deleted while its accept rule references it' `
    $(if ($trip.Out -match 'SET_STILL_THERE_AFTER_DELETE_ATTEMPT=yes') { 'PASS' } else { 'INFO' }) `
    'nft refuses a set delete while a rule references it, so removing this control takes two deliberate steps rather than one'
Record "TC.8b.$tag" 'The firewall was left intact by this test' `
    $(if (($trip.Out -match 'SET_BACK=yes') -and ($trip.Out -match 'ACCEPT_BACK=yes')) { 'PASS' } else { 'FAIL' }) `
    'a test that leaves the firewall broken has manufactured the defect it was checking for'

# =========================================================================
Section '9. Leave the box in the DEFAULT state for whatever runs next'
# The switch was toggled several times above. A later phase, or a human at the
# keyboard, inherits none of this file's context and would reasonably expect the
# shipped default. Restoring it is part of the test, not tidying.
$final = Invoke-WslFile -Tag "tc-final-$tag" -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl toolchain on 2>&1 | tail -1
echo "FINAL_POLICY=$(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))')"
echo "FINAL_SET=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)"
/usr/local/sbin/clawfactory-fw-assert.sh >/dev/null 2>&1; echo "final_assert_rc=$?"
'@
W $final.Out
Record "TC.9.$tag" 'The box is left in the shipped default state (switch on, chain intact)' `
    $(if (($final.Out -match 'FINAL_POLICY=True') -and ($final.Out -match 'final_assert_rc=0')) { 'PASS' } else { 'FAIL' }) `
    "final policy and a passing tripwire, so the next phase does not inherit a half-toggled box"

Complete-Phase -ResultsJson "C:\cfv\toolchain-results-$tag.json" -MarkerPrefix "TOOLCHAIN_$tag"
