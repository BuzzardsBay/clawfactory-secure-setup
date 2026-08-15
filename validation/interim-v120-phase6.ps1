<#
  Phase 6: v1 Guard 3 (web off by default) plus the approvals-panel polish.

  Runs in the interactive auto-logon session on the VM, through the file-based
  WSL channel, same as phases 2 to 5.

  EVERY BLOCK ASSERTION CARRIES A CONTROL THAT MUST FAIL IN THE SAME RUN. A test
  whose control does not fail is recorded VOID, not PASS, because a probe that
  cannot observe a success cannot be trusted when it observes a failure.

  THE TRAP THIS PHASE IS BUILT AROUND. Guard 3's default state is an EMPTY
  allowlist, and "no read-fetch destination is reachable" is true on a machine
  where Guard 3 was never installed at all. So the deny tests alone prove
  nothing about the control. What proves it is the pair: a destination becomes
  reachable when the user adds it, and stops being reachable when the user takes
  it away. Both halves are here.

  A SECOND TRAP, and it decides how test 3 is scored. Enforcement is by resolved
  ADDRESS. If the subject host and the control host share an address, or if the
  control host is already reachable through the provider and toolchain route,
  then "only that destination became reachable" cannot be measured at all. This
  phase resolves both and checks disjointness FIRST, and records VOID rather
  than inventing a verdict when the addressing does not permit the measurement.

  L17: a new probe inherits none of the preconditions of the ones beside it. The
  agent is warmed before any load-bearing turn.
#>
param(
    [string]$Transcript = 'C:\cfv\phase6-out-probe.txt',
    [switch]$PostReboot
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1

# The phase runner owns W, Section, Record, the control and precondition calls,
# and the verdict. This phase's own tail used to compute rc from the FAIL count
# alone and ignore VOIDs entirely, so a phase that measured nothing exited 0.
. C:\cfv\interim-v120-phaselib.ps1
$tag = if ($PostReboot) { 'POSTREBOOT' } else { 'PRE' }

Start-Phase -Name "ClawFactory v1 Guard 3 validation, Phase 6, pass=$tag" `
    -Transcript $Transcript -Sentinel 'PHASE6_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id "G3.CHAN.$tag" -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; W 'PHASE6_PROBE_COMPLETE rc=2'; exit 2 }

# =========================================================================
Section "0. The control is INSTALLED. Checked before anything is measured through it."
# An empty allowlist and an absent guard produce identical outcomes on every
# reachability test below. So the mechanism is checked directly, first.
$inst = Invoke-WslFile -Tag "g3-inst-$tag" -User 'root' -Body @'
echo "--- the two programs ---"
for f in /usr/local/sbin/clawfactory-read-fetch.sh /usr/local/sbin/clawfactory-fetchctl.js /usr/local/sbin/clawfactory-fetchctl; do
  if [ -e "$f" ]; then stat -c 'PRESENT %n %U:%G %a' "$f"; else echo "ABSENT  $f"; fi
done
echo "--- CONTROL: a path that must be absent ---"
[ -e /usr/local/sbin/clawfactory-not-a-real-tool ] && echo "CONTROL FAILED" || echo "CONTROL OK (absent)"
echo "--- the nft set and its accept ---"
nft list set inet clawfactory read_fetch_ipv4 >/dev/null 2>&1 && echo "SET_PRESENT=yes" || echo "SET_PRESENT=no"
nft list chain inet clawfactory output 2>/dev/null | grep -qE '@read_fetch_ipv4 tcp dport 443 accept' && echo "ACCEPT_443=yes" || echo "ACCEPT_443=no"
echo "--- CONTROL: a set name that must not exist ---"
nft list set inet clawfactory not_a_real_set >/dev/null 2>&1 && echo "CONTROL FAILED" || echo "CONTROL OK (no such set)"
echo "--- the chain-shape tripwire, which now covers Guard 3 ---"
/usr/local/sbin/clawfactory-fw-assert.sh 2>&1; echo "fw_assert_rc=$?"
echo "--- the policy file ---"
stat -c '%n %U:%G %a' /etc/clawfactory/egress-policy.json
node -e 'const p=require("/etc/clawfactory/egress-policy.json");console.log("READ_FETCH_COUNT="+(p.read_fetch&&p.read_fetch.allow?p.read_fetch.allow.length:-1))'
'@
W $inst.Out
$setOk    = $inst.Out -match 'SET_PRESENT=yes'
$acceptOk = $inst.Out -match 'ACCEPT_443=yes'
$ctlModes = ([regex]::Matches($inst.Out, 'PRESENT /usr/local/sbin/clawfactory-fetchctl(\.js)? root:root 750')).Count
$asrtOk   = $inst.Out -match 'fw_assert_rc=0'
$ctlSane  = ($inst.Out -match 'CONTROL OK \(absent\)') -and ($inst.Out -match 'CONTROL OK \(no such set\)')
Record "G3.0a.$tag" 'Guard 3 is installed: resolver, control tool, nft set, 443-scoped accept' `
    $(if ($setOk -and $acceptOk -and $ctlSane) { 'PASS' } else { 'FAIL' }) `
    "SET_PRESENT=$setOk ACCEPT_443=$acceptOk; absence controls behaved=$ctlSane"
Record "G3.0b.$tag" 'The write path is root-only (0750 root:root on both fetchctl files)' `
    $(if ($ctlModes -ge 2) { 'PASS' } else { 'FAIL' }) `
    "matched $ctlModes of 2 expected 0750 root:root entries"
Record "G3.0c.$tag" 'The chain-shape tripwire passes and now covers Guard 3' `
    $(if ($asrtOk) { 'PASS' } else { 'FAIL' }) 'fw-assert checks both allowlist accepts and the read_fetch set'
Record "G3.0d.$tag" 'A fresh install has an EMPTY read-fetch allowlist' `
    $(if ($inst.Out -match 'READ_FETCH_COUNT=0') { 'PASS' } elseif ($inst.Out -match 'READ_FETCH_COUNT=-1') { 'FAIL' } else { 'INFO' }) `
    'empty is the denied state; a later test adds to it and takes it back'

# =========================================================================
Section "1. A non-allowlisted site is denied for the agent uid, with a control that MUST succeed"
$deny = Invoke-WslFile -Tag "g3-deny-$tag" -User 'clawuser' -Body @'
echo "whoami=$(id -un) uid=$(id -u)"
probe() {
  if timeout 10 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then echo "$1:$2 CONNECTED"; else echo "$1:$2 blocked"; fi
}
echo '--- SUBJECT (MUST be blocked): sites nobody allowed ---'
for h in example.org example.net wikipedia.org neverssl.com; do probe $h 443; done
echo '--- CONTROL A (MUST SUCCEED): the model provider, which has to keep working ---'
probe api.anthropic.com 443
echo '--- CONTROL B (MUST SUCCEED): the probe can see a live listener, so a block is real ---'
(node -e "require(\"net\").createServer(s=>s.end()).listen(19998,\"127.0.0.1\")" &) >/dev/null 2>&1
sleep 2
probe 127.0.0.1 19998
pkill -f "listen(19998" 2>/dev/null
echo '--- DNS still resolves, so the control is the CONNECTION and not the lookup ---'
getent ahostsv4 example.org | head -1
'@
W $deny.Out
$blockedAll = -not ($deny.Out -match '(example\.org|example\.net|wikipedia\.org|neverssl\.com):443 CONNECTED')
$ctlProvider = $deny.Out -match 'api\.anthropic\.com:443 CONNECTED'
$ctlListener = $deny.Out -match '127\.0\.0\.1:19998 CONNECTED'
$verdict1 = if (-not $ctlProvider -or -not $ctlListener) { 'VOID' } elseif ($blockedAll) { 'PASS' } else { 'FAIL' }
Record "G3.1.$tag" 'Non-allowlisted sites are unreachable for uid 1000' $verdict1 `
    "four subjects blocked=$blockedAll; CONTROL provider reachable=$ctlProvider; CONTROL probe sees a live listener=$ctlListener"
Record "G3.1b.$tag" 'CONTROL: the provider route still works (an agent that cannot reach its model is bricked)' `
    $(if ($ctlProvider) { 'PASS' } else { 'FAIL' }) 'this control failing would void every block above'

# =========================================================================
Section "2. The provider route works end to end: a real agent turn completes"
# Warmed first. L17: the first turn after an idle is cold, and a cold turn's
# failure would be recorded as a Guard 3 regression it has nothing to do with.
$warm = Invoke-WslFile -Tag "g3-warm-$tag" -User 'clawuser' -Body @'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: WARMOK"}]}' > /tmp/warm6.json
curl -s --max-time 120 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/tmp/warm6.json
rm -f /tmp/warm6.json
'@
W $warm.Out
if ($warm.Out -notmatch 'WARMOK') {
    W '--- cold start suspected; one retry, so a cold turn is not reported as a failure ---'
    Start-Sleep -Seconds 20
    $warm = Invoke-WslFile -Tag "g3-warm2-$tag" -User 'clawuser' -Body @'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: WARMOK"}]}' > /tmp/warm6.json
curl -s --max-time 180 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/tmp/warm6.json
rm -f /tmp/warm6.json
'@
    W $warm.Out
}
$turnOk = $warm.Out -match 'WARMOK'
Record "G3.2.$tag" 'A real agent turn completes through the gating proxy with Guard 3 installed' `
    $(if ($turnOk) { 'PASS' } else { 'FAIL' }) `
    'the model provider is reached over the same 443 path Guard 3 filters; retried once for a cold start (L17)'

# =========================================================================
Section "3. A destination the USER adds becomes reachable, and only that one, and revoking it takes effect"
# The whole guard rests on this pair. Deny-by-default is measurable on a machine
# where Guard 3 was never installed; add-then-revoke is not.
$addrs = Invoke-WslFile -Tag "g3-addr-$tag" -User 'root' -Body @'
# Enforcement is by ADDRESS. If the subject and the control share one, or if the
# control is already reachable through the provider set, the "only that one"
# claim cannot be measured at all. Work that out BEFORE choosing them.
SUBJ=example.org
echo "SUBJECT=$SUBJ"
echo "SUBJ_IPS=$(getent ahostsv4 $SUBJ | awk '{print $1}' | sort -u | tr '\n' ' ')"
ALLOWED=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u)
for C in example.net neverssl.com wikipedia.org ubuntu.com; do
  CIPS=$(getent ahostsv4 $C 2>/dev/null | awk '{print $1}' | sort -u)
  [ -n "$CIPS" ] || continue
  SIPS=$(getent ahostsv4 $SUBJ | awk '{print $1}' | sort -u)
  OVERLAP=$(comm -12 <(echo "$SIPS") <(echo "$CIPS") | wc -l)
  INPROV=$(comm -12 <(echo "$CIPS") <(echo "$ALLOWED") | wc -l)
  echo "CAND $C overlap_with_subject=$OVERLAP already_in_provider_set=$INPROV ips=$(echo $CIPS | tr '\n' ' ')"
  if [ "$OVERLAP" = "0" ] && [ "$INPROV" = "0" ]; then echo "CONTROL_HOST=$C"; break; fi
done
'@
W $addrs.Out
$ctlHost = if ($addrs.Out -match 'CONTROL_HOST=(\S+)') { $Matches[1] } else { '' }

if (-not $ctlHost) {
    Record "G3.3.$tag" 'A user-added destination becomes reachable, and only that one' 'VOID' `
        'no candidate control host had an address set disjoint from both the subject and the provider allowlist, so the claim is not measurable on this network. Not scored as a pass.'
} else {
    W "--- control host chosen by disjointness: $ctlHost ---"
    $add = Invoke-WslFile -Tag "g3-add-$tag" -User 'root' -Body @"
set -x
echo '--- BEFORE: neither reachable ---'
su -s /bin/bash -c 'timeout 10 bash -c "exec 3<>/dev/tcp/example.org/443" 2>/dev/null && echo "SUBJ_BEFORE=CONNECTED" || echo "SUBJ_BEFORE=blocked"' clawuser
su -s /bin/bash -c 'timeout 10 bash -c "exec 3<>/dev/tcp/$ctlHost/443" 2>/dev/null && echo "CTL_BEFORE=CONNECTED" || echo "CTL_BEFORE=blocked"' clawuser
echo '--- the user adds one site, through the root-only tool Studio calls ---'
/usr/local/sbin/clawfactory-fetchctl add example.org
echo '--- AFTER ADD ---'
su -s /bin/bash -c 'timeout 15 bash -c "exec 3<>/dev/tcp/example.org/443" 2>/dev/null && echo "SUBJ_AFTER=CONNECTED" || echo "SUBJ_AFTER=blocked"' clawuser
su -s /bin/bash -c 'timeout 10 bash -c "exec 3<>/dev/tcp/$ctlHost/443" 2>/dev/null && echo "CTL_AFTER=CONNECTED" || echo "CTL_AFTER=blocked"' clawuser
echo '--- the set now holds addresses, and the policy records the host ---'
nft list set inet clawfactory read_fetch_ipv4 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' '; echo
node -e 'const p=require("/etc/clawfactory/egress-policy.json");console.log("POLICY_AFTER_ADD="+JSON.stringify(p.read_fetch.allow))'
echo '--- the user takes it back ---'
/usr/local/sbin/clawfactory-fetchctl remove example.org
echo '--- AFTER REMOVE ---'
su -s /bin/bash -c 'timeout 10 bash -c "exec 3<>/dev/tcp/example.org/443" 2>/dev/null && echo "SUBJ_REVOKED=CONNECTED" || echo "SUBJ_REVOKED=blocked"' clawuser
nft list set inet clawfactory read_fetch_ipv4 | grep -cE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^/SET_LINES_AFTER_REMOVE=/'
node -e 'const p=require("/etc/clawfactory/egress-policy.json");console.log("POLICY_AFTER_REMOVE="+JSON.stringify(p.read_fetch.allow)+" SEND_ACTIONS_PRESERVED="+JSON.stringify(p.send_actions.length))'
"@
    W $add.Out
    $sBefore = $add.Out -match 'SUBJ_BEFORE=blocked'
    $sAfter  = $add.Out -match 'SUBJ_AFTER=CONNECTED'
    $cAfter  = $add.Out -match 'CTL_AFTER=blocked'
    $sRevok  = $add.Out -match 'SUBJ_REVOKED=blocked'
    Record "G3.3a.$tag" 'A user-added destination becomes reachable' `
        $(if ($sBefore -and $sAfter) { 'PASS' } else { 'FAIL' }) `
        "blocked before the add=$sBefore, reachable after=$sAfter"
    Record "G3.3b.$tag" "CONTROL: only that destination. $ctlHost was NOT added and stays blocked" `
        $(if ($cAfter) { 'PASS' } else { 'FAIL' }) `
        'address sets verified disjoint from the subject and from the provider allowlist before choosing this host'
    Record "G3.3c.$tag" 'Revoking in the UI actually removes the route' `
        $(if ($sRevok) { 'PASS' } else { 'FAIL' }) `
        'this is why read_fetch_ipv4 is a separate set: the provider set is refreshed additively and could not be revoked'
    Record "G3.3d.$tag" 'The send destination survived a read-fetch write (shared policy file, shared lock)' `
        $(if ($add.Out -match 'SEND_ACTIONS_PRESERVED=[1-9]') { 'PASS' } elseif ($add.Out -match 'SEND_ACTIONS_PRESERVED=0') { 'INFO' } else { 'REVIEW' }) `
        'Guard 3 must never be the reason a user loses their authorized SMTP destination'
}

# =========================================================================
Section "4. The AGENT cannot modify the read-fetch list, across every channel it can reach"
$tamper = Invoke-WslFile -Tag "g3-tamper-$tag" -User 'clawuser' -Body @'
echo "whoami=$(id -un) uid=$(id -u)"
try() { echo "--- $1 ---"; shift; "$@" 2>&1 | head -3; echo "rc=$?"; }
echo '=== 1. write the policy file ==='
sh -c 'echo x >> /etc/clawfactory/egress-policy.json' 2>&1 | head -2
echo '=== 2. write the resolved address list the boot path reads ==='
sh -c 'echo 1.2.3.4 >> /etc/clawfactory/read-fetch-ips.txt' 2>&1 | head -2
echo '=== 3. write the host list ==='
sh -c 'echo evil.example >> /etc/clawfactory/read-fetch-hosts.txt' 2>&1 | head -2
echo '=== 4. write the firewall config ==='
sh -c 'echo x >> /etc/nftables.conf' 2>&1 | head -2
echo '=== 5. run the root-only control tool ==='
/usr/local/sbin/clawfactory-fetchctl add evil.example 2>&1 | head -2
echo '=== 6. run it via node, in case the mode on the wrapper was the only guard ==='
node /usr/local/sbin/clawfactory-fetchctl.js add evil.example 2>&1 | head -2
echo '=== 7. run the resolver directly ==='
/usr/local/sbin/clawfactory-read-fetch.sh 2>&1 | head -2
echo '=== 8. add an element to the set directly ==='
nft add element inet clawfactory read_fetch_ipv4 '{ 1.2.3.4 }' 2>&1 | head -2
/usr/sbin/nft add element inet clawfactory read_fetch_ipv4 '{ 1.2.3.4 }' 2>&1 | head -2
echo '=== 9. restart the refresh unit so a tampered file would be applied ==='
systemctl restart clawfactory-allow-providers.service 2>&1 | head -2
echo '=== 10. read the control tool at all ==='
head -1 /usr/local/sbin/clawfactory-fetchctl.js 2>&1 | head -1
echo '=== CONTROL: uid 1000 CAN write somewhere it owns, so the refusals above are real ==='
echo ok > /tmp/g3-control && cat /tmp/g3-control && rm -f /tmp/g3-control
'@
W $tamper.Out
$ctlWritable = $tamper.Out -match '(?m)^ok$'
$evilLanded  = $tamper.Out -match 'evil\.example.*added|"changed":true'
$verify = Invoke-WslFile -Tag "g3-verify-$tag" -User 'root' -Body @'
node -e 'const p=require("/etc/clawfactory/egress-policy.json");const l=(p.read_fetch&&p.read_fetch.allow)||[];console.log("ALLOW_AFTER_TAMPER="+JSON.stringify(l));console.log("EVIL_PRESENT="+(JSON.stringify(l).indexOf("evil.example")>=0))'
echo "SET_AFTER_TAMPER=$(nft list set inet clawfactory read_fetch_ipv4 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' ')"
nft list set inet clawfactory read_fetch_ipv4 | grep -q '1\.2\.3\.4' && echo "INJECTED_IP=yes" || echo "INJECTED_IP=no"
'@
W $verify.Out
$noEvil = ($verify.Out -match 'EVIL_PRESENT=false') -and ($verify.Out -match 'INJECTED_IP=no')
Record "G3.4.$tag" 'The agent cannot modify the read-fetch list through any channel it can reach' `
    $(if (-not $ctlWritable) { 'VOID' } elseif ($noEvil) { 'PASS' } else { 'FAIL' }) `
    "ten channels attempted; policy free of the injected host=$noEvil; CONTROL uid 1000 can write /tmp=$ctlWritable"

# =========================================================================
Section "5. Guard 3 survives the SHIPPED five-hourly refresh"
# Not a simulated refresh. The actual unit, with the tripwire on ExecStartPost.
$refresh = Invoke-WslFile -Tag "g3-refresh-$tag" -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl add example.org >/dev/null 2>&1
echo "BEFORE_SET=$(nft list set inet clawfactory read_fetch_ipv4 | grep -cE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')"
su -s /bin/bash -c 'timeout 15 bash -c "exec 3<>/dev/tcp/example.org/443" 2>/dev/null && echo "BEFORE_REACH=CONNECTED" || echo "BEFORE_REACH=blocked"' clawuser
echo '--- running the shipped refresh unit, tripwire and all ---'
systemctl start clawfactory-allow-providers.service
sleep 5
systemctl show clawfactory-allow-providers.service -p Result --value | sed 's/^/UNIT_RESULT=/'
echo "AFTER_SET=$(nft list set inet clawfactory read_fetch_ipv4 | grep -cE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')"
su -s /bin/bash -c 'timeout 15 bash -c "exec 3<>/dev/tcp/example.org/443" 2>/dev/null && echo "AFTER_REACH=CONNECTED" || echo "AFTER_REACH=blocked"' clawuser
echo '--- CONTROL: a site nobody added is STILL blocked after the refresh ---'
su -s /bin/bash -c 'timeout 10 bash -c "exec 3<>/dev/tcp/example.net/443" 2>/dev/null && echo "CTL_AFTER_REFRESH=CONNECTED" || echo "CTL_AFTER_REFRESH=blocked"' clawuser
echo '--- CONTROL: the provider route survived the refresh too ---'
su -s /bin/bash -c 'timeout 15 bash -c "exec 3<>/dev/tcp/api.anthropic.com/443" 2>/dev/null && echo "PROV_AFTER_REFRESH=CONNECTED" || echo "PROV_AFTER_REFRESH=blocked"' clawuser
echo '--- the tripwire ran as ExecStartPost and passed ---'
journalctl -u clawfactory-allow-providers.service -n 15 --no-pager 2>/dev/null | tail -8
/usr/local/sbin/clawfactory-fetchctl remove example.org >/dev/null 2>&1
'@
W $refresh.Out
$survived = ($refresh.Out -match 'AFTER_REACH=CONNECTED')
$stillBlocked = ($refresh.Out -match 'CTL_AFTER_REFRESH=blocked')
$provOk = ($refresh.Out -match 'PROV_AFTER_REFRESH=CONNECTED')
Record "G3.5.$tag" 'A user destination survives the shipped five-hourly refresh' `
    $(if (-not $stillBlocked -or -not $provOk) { 'VOID' } elseif ($survived) { 'PASS' } else { 'FAIL' }) `
    "reachable after refresh=$survived; CONTROL un-added site still blocked=$stillBlocked; CONTROL provider still reachable=$provOk"

if ($PostReboot) {
    Section 'Post-reboot pass complete. The reachability and refresh tests above were re-run after a full reboot.'
    Complete-Phase -ResultsJson 'C:\cfv\phase6-results-postreboot.json' -MarkerPrefix "PHASE6_$tag"
}

# =========================================================================
Section "6. Expired approval requests: they exist, they refuse approval two different ways, and dismiss keeps the record"
# The TTL is 600s and this waits it out rather than shortening it. Rewriting the
# product's own config to make a test finish sooner would mean testing something
# the customer does not run.
$ttl = Invoke-WslFile -Tag "g3-ttl-$tag" -User 'root' -Body @'
node -e 'const c=require("/etc/clawfactory/send.json");console.log("TTL_SECONDS="+c.approvalTtlSeconds)'
/usr/local/sbin/clawfactory-sendctl credential-summary
'@
W $ttl.Out

# PRECONDITION, CHECKED RATHER THAN ASSUMED. A fresh box has no SMTP credential,
# and Guard 2's fail-closed state means nothing can be enqueued at all. Every
# assertion below then runs against an empty queue: sendctl is handed an empty
# id, prints its usage text, and the probe scores that as a product failure.
#
# That is what the first run of this phase did. It reported four FAILs and one
# PASS, and all five were meaningless, because the subject did not exist. The
# PASS was the more dangerous of the two.
#
# A missing precondition is NOT a product verdict. Say so and stop.
if ($ttl.Out -notmatch '"configured"\s*:\s*true') {
    Record "G3.6.PRE" 'PRECONDITION: an SMTP credential is configured' 'VOID' `
        'No SMTP credential on this box, so nothing can be queued and the expiry tests have no subject. This is Guard 2 failing closed exactly as documented, not a defect. Configure SMTP in Studio, then re-run.'
    foreach ($id in @('G3.6a','G3.6b','G3.6c','G3.7a','G3.7b','G3.7c')) {
        Record $id 'Expired-request and dismiss behaviour' 'VOID' 'not measured: no SMTP credential, so no request could be queued'
    }
    W ''
    W 'Skipping sections 6 and 7. Re-run this phase once SMTP is configured.'
    $skipExpiry = $true
} else {
    $skipExpiry = $false
}
$ttlSecs = if ($ttl.Out -match 'TTL_SECONDS=(\d+)') { [int]$Matches[1] } else { 600 }

if (-not $skipExpiry) {
W "--- queueing two requests, then waiting out the $ttlSecs second window ---"

# A and B only. The live control C is queued AFTER the wait, not with these.
#
# Queuing C here would be a probe defect: the wait is longer than the TTL by
# design, so C would expire too, and then "approve C with a wrong hash" would
# return EEXPIRED rather than EHASH. The control would look like it had failed
# for the same reason as the subject, which makes it useless as a control.
$queue = Invoke-WslFile -Tag "g3-queue-$tag" -User 'root' -Body @'
su -s /bin/bash -c 'printf "expiry test A\n" > /tmp/exp-a.txt; clawfactory-send --to sink-a@example.invalid --subject "EXPIRY-A" --body-file /tmp/exp-a.txt' clawuser 2>&1 | tail -2
su -s /bin/bash -c 'printf "expiry test B\n" > /tmp/exp-b.txt; clawfactory-send --to sink-b@example.invalid --subject "EXPIRY-B" --body-file /tmp/exp-b.txt' clawuser 2>&1 | tail -2
echo '--- the queue as the panel sees it right now ---'
/usr/local/sbin/clawfactory-sendctl list
'@
W $queue.Out
$idA = if ($queue.Out -match '"id"\s*:\s*"([^"]+)"[^}]*"subject"\s*:\s*"EXPIRY-A"') { $Matches[1] } else { '' }
if (-not $idA) {
    # Reply shape varies with field order; fall back to pulling ids by subject.
    $ids = Invoke-WslFile -Tag "g3-ids-$tag" -User 'root' -Body @'
/usr/local/sbin/clawfactory-sendctl list | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);
for (const p of (j.pending||[])) console.log("ID "+p.subject+" "+p.id+" "+p.payloadHash);});'
'@
    W $ids.Out
    $idA = if ($ids.Out -match 'ID EXPIRY-A (\S+)') { $Matches[1] } else { '' }
    $idB = if ($ids.Out -match 'ID EXPIRY-B (\S+)') { $Matches[1] } else { '' }
}

W "--- ids: A=$idA B=$idB ---"
$idC = ''

# SECOND GUARD, because the first one can be satisfied and this can still fail.
# A configured credential does not guarantee the enqueue worked. Without ids,
# every sendctl call below is handed an empty argument, prints usage, and the
# probe reads the absence of a refusal code as a refusal that did not happen.
if (-not $idA -or -not $idB) {
    foreach ($id in @('G3.6a','G3.6b','G3.6c','G3.7a','G3.7b','G3.7c')) {
        Record $id 'Expired-request and dismiss behaviour' 'VOID' `
            "not measured: could not queue the two requests (ids A='$idA' B='$idB'). A verdict from an empty queue is not a verdict."
    }
    $skipExpiry = $true
}
}

if (-not $skipExpiry) {
W "--- waiting $($ttlSecs + 45)s for the approval window to close. This is the real TTL, not a shortened one. ---"
Start-Sleep -Seconds ($ttlSecs + 45)

# The live control, queued NOW so it is genuinely inside its window, and with an
# attachment so the approvals panel has a card carrying a staged hash for the
# reveal control to be checked against by hand.
$liveC = Invoke-WslFile -Tag "g3-livec-$tag" -User 'root' -Body @'
su -s /bin/bash -c 'printf "live control body\n" > /tmp/exp-c.txt; printf "attachment bytes for the hash reveal check\n" > /tmp/exp-c-attach.txt; clawfactory-send --to sink-c@example.invalid --subject "LIVE-CONTROL" --body-file /tmp/exp-c.txt --attach /tmp/exp-c-attach.txt' clawuser 2>&1 | tail -2
/usr/local/sbin/clawfactory-sendctl list | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);
for (const p of (j.pending||[])) console.log("ID "+p.subject+" "+p.id+" "+p.payloadHash+" attachments="+((p.attachments||[]).length));});'
'@
W $liveC.Out
$idC = if ($liveC.Out -match 'ID LIVE-CONTROL (\S+)') { $Matches[1] } else { '' }
W "--- live control id: C=$idC ---"
if (-not $idC) {
    Record 'G3.6.CTL' 'PRECONDITION: a live pending request exists to act as the control' 'VOID' `
        'could not queue the live control, so EEXPIRED and ESTATE cannot be distinguished from a blanket refusal'
}

$expired = Invoke-WslFile -Tag "g3-expired-$tag" -User 'root' -Body @"
echo '=== EEXPIRED: approve a record that is PAST its window but has not yet been swept ==='
/usr/local/sbin/clawfactory-sendctl approve '$idA'
echo
echo '=== now sweep, so B becomes state=expired ==='
/usr/local/sbin/clawfactory-sendctl gc
echo
echo '=== ESTATE: approve a record the sweep already marked expired ==='
/usr/local/sbin/clawfactory-sendctl approve '$idB'
echo
echo '=== the panel list: expired records now come back, in their own array ==='
/usr/local/sbin/clawfactory-sendctl list | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);
console.log("PENDING_COUNT="+((j.pending||[]).length));
console.log("EXPIRED_COUNT="+((j.expired||[]).length));
for (const e of (j.expired||[])) console.log("EXPIRED_ITEM "+e.subject+" state="+e.state+" expiredAt="+e.expiredAt);});'
echo
echo '=== CONTROL: the refusals above are about STATE and EXPIRY, not a blanket refusal ==='
echo '=== a live pending request refused for a different, specific reason (EHASH) ==='
/usr/local/sbin/clawfactory-sendctl approve '$idC' 0000000000000000000000000000000000000000000000000000000000000000
"@
W $expired.Out
$gotEexpired = $expired.Out -match 'EEXPIRED'
$gotEstate   = $expired.Out -match 'ESTATE'
$gotEhash    = $expired.Out -match 'EHASH'
$expCount    = if ($expired.Out -match 'EXPIRED_COUNT=(\d+)') { [int]$Matches[1] } else { -1 }
Record "G3.6a" 'EEXPIRED still refuses: approval racing the expiry boundary is denied under the store lock' `
    $(if (-not $gotEhash) { 'VOID' } elseif ($gotEexpired) { 'PASS' } else { 'FAIL' }) `
    "EEXPIRED seen=$gotEexpired; CONTROL a live request refused with the DIFFERENT code EHASH=$gotEhash"
Record "G3.6b" 'ESTATE still refuses: a record already marked expired cannot be approved' `
    $(if (-not $gotEhash) { 'VOID' } elseif ($gotEstate) { 'PASS' } else { 'FAIL' }) `
    "ESTATE seen=$gotEstate; showing a card did not make it approvable"
Record "G3.6c" 'Expired requests are returned to the panel, in a separate array from pending' `
    $(if ($expCount -ge 1) { 'PASS' } else { 'FAIL' }) `
    "EXPIRED_COUNT=$expCount; separate arrays so a renderer cannot draw approve on a dead request"

# =========================================================================
Section "7. Dismiss removes the card and leaves the audit record intact"
$dismiss = Invoke-WslFile -Tag "g3-dismiss-$tag" -User 'root' -Body @"
echo '=== the record on disk BEFORE dismiss ==='
node -e '
const fs=require("fs");const d="/var/lib/clawfactory/send/pending";
for (const f of fs.readdirSync(d)) { const r=JSON.parse(fs.readFileSync(d+"/"+f,"utf8"));
if (r.subject==="EXPIRY-B") console.log("BEFORE id="+r.id+" state="+r.state+" recipients="+JSON.stringify(r.recipients.to)+" payloadHash="+(r.payloadHash||"").slice(0,16)+" dismissedAt="+r.dismissedAt); }'
echo '=== dismiss it ==='
/usr/local/sbin/clawfactory-sendctl dismiss '$idB'
echo
echo '=== the panel no longer shows it ==='
/usr/local/sbin/clawfactory-sendctl list | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);
console.log("EXPIRED_COUNT_AFTER_DISMISS="+((j.expired||[]).length));
console.log("B_STILL_SHOWN="+((j.expired||[]).some(e=>e.subject==="EXPIRY-B")));});'
echo
echo '=== the audit record is STILL ON DISK, unchanged except for the dismiss stamp ==='
node -e '
const fs=require("fs");const d="/var/lib/clawfactory/send/pending";
let found=false;
for (const f of fs.readdirSync(d)) { const r=JSON.parse(fs.readFileSync(d+"/"+f,"utf8"));
if (r.subject==="EXPIRY-B") { found=true; console.log("AFTER id="+r.id+" state="+r.state+" recipients="+JSON.stringify(r.recipients.to)+" payloadHash="+(r.payloadHash||"").slice(0,16)+" dismissedAt="+r.dismissedAt); } }
console.log("RECORD_SURVIVES="+found);'
echo
echo '=== CONTROL: dismiss refuses a PENDING request, so it cannot hide a live decision ==='
/usr/local/sbin/clawfactory-sendctl dismiss '$idC'
"@
W $dismiss.Out
$gone      = $dismiss.Out -match 'B_STILL_SHOWN=false'
$survives  = $dismiss.Out -match 'RECORD_SURVIVES=true'
$ctlRefuse = ($dismiss.Out -split 'CONTROL: dismiss refuses')[-1] -match 'ESTATE'
Record "G3.7a" 'Dismiss removes the card from the panel' `
    $(if (-not $ctlRefuse) { 'VOID' } elseif ($gone) { 'PASS' } else { 'FAIL' }) `
    "no longer listed=$gone"
Record "G3.7b" 'Dismiss does NOT delete the audit record' `
    $(if ($survives) { 'PASS' } else { 'FAIL' }) `
    'state, recipients and payload hash all still on disk; only a dismissedAt stamp was added'
Record "G3.7c" 'CONTROL: dismiss refuses a pending request with ESTATE' `
    $(if ($ctlRefuse) { 'PASS' } else { 'FAIL' }) `
    'this control failing would void 7a: dismiss would be able to hide a live approval request'
}

# =========================================================================
Section "8. The panels are in the INSTALLED artifact (the local search over the compiled installer is blind)"
# A raw byte search over the NSIS installer finds nothing at all, proven by its
# own positive control failing, because the payload is compressed. So the check
# that means anything is this one, against what actually landed on the machine.
$asar = @'
# The install directory is "ClawFactory Studio", with a space, which is what
# phase 1 reports. The first version of this guessed "clawfactory-studio" and
# found nothing, and only the positive control stopped that being read as
# "no stale markers present". Search rather than guess.
$p = (Get-ChildItem 'C:\Users\*\AppData\Local\Programs\*\resources\app.asar' -ErrorAction SilentlyContinue |
        Select-Object -First 1).FullName
if (-not $p) {
  $p = (Get-ChildItem 'C:\' -Recurse -Filter 'app.asar' -ErrorAction SilentlyContinue -Depth 8 |
          Where-Object { $_.FullName -like '*Studio*' } | Select-Object -First 1).FullName
}
if (-not $p -or -not (Test-Path $p)) { 'ASAR_NOT_FOUND'; exit }
"ASAR=$p"
$t = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($p))
foreach ($m in @('web:list','web:allow','web:revoke','Web access','clawfactory-fetchctl','send:dismiss','send:markViewed','Expired while you were away','show full hash','PolyForm Perimeter 1.0.0','app:version','send:approve','quarantine:restore',
                 # 1.3.0: the toolchain switch, its load-bearing breakage text, the
                 # ratified footnote, and the replacement home route.
                 'web:toolchain','setToolchain','Software sources ClawFactory needs','stops skill installation',
                 'unless you switch them off above','Matching is by network address rather than by name',
                 'Running outside the ClawFactory Studio app')) {
  if ($t.Contains($m)) { "PRESENT  $m" } else { "MISSING  $m" }
}
# Stale strings. The three 1.3.0 additions are the ones this session removed, and
# each is a sentence that was FALSE in the shipped product: the home route claimed
# a retired backend was unreachable, and the old footnote omitted that a site can
# share an address with one the USER allowed, not only with the provider.
foreach ($m in @('v0.1.0','MIT licensed','ClawFactoryNegativeSentinelZZ9',
                 'Studio backend unreachable','Two things are always reachable regardless','Running on http://127.0.0.1:8080')) {
  if ($t.Contains($m)) { "STILLTHERE  $m" } else { "ABSENT      $m" }
}
if ($t.Contains('Workspace')) { 'POSCONTROL_OK' } else { 'POSCONTROL_BLIND' }
'@
$asarFile = 'C:\cfv\asar-check.ps1'
$asar | Out-File $asarFile -Encoding utf8
$asarOut = & powershell -ExecutionPolicy Bypass -File $asarFile 2>&1 | Out-String
W $asarOut
$asarBlind   = $asarOut -match 'POSCONTROL_BLIND|ASAR_NOT_FOUND'
$asarMissing = ([regex]::Matches($asarOut, 'MISSING  ')).Count
$asarStale   = $asarOut -match 'STILLTHERE'
# The searchability assertion, made a runner-level call rather than a local
# boolean. A search over a COMPRESSED payload finds nothing and reads as a clean
# all-clear: that happened, over the compiled NSIS installer, and only the
# positive control caught it. Registering it here means an unsearchable target
# voids the phase instead of quietly passing it.
Assert-Searchable -Id 'G3.8.SEARCH' -Name 'panel markers in the installed app.asar' `
    -PositiveMarkerFound (-not $asarBlind) `
    -MarkerDescription 'the positive marker Workspace inside the extracted app.asar' | Out-Null

Record "G3.8" 'The new panels are present in the app.asar that was actually installed' `
    $(if ($asarBlind) { 'VOID' } elseif ($asarMissing -eq 0 -and -not $asarStale) { 'PASS' } else { 'FAIL' }) `
    "missing markers=$asarMissing; stale markers (v0.1.0 / MIT licensed) present=$asarStale; positive control blind=$asarBlind"

$outJson6 = if ($PostReboot) { 'C:\cfv\phase6-results-postreboot.json' } else { 'C:\cfv\phase6-results.json' }
Complete-Phase -ResultsJson $outJson6 -MarkerPrefix "PHASE6_$tag"
