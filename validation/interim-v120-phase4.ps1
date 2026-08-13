<#
  Phase 4: structural properties, on the installed product.

  "Structural" here means a property that holds because of how the system is
  built, not because a component chose to behave. The distinction matters for
  the close-out: an advisory control is one an attacker with the agent's
  privileges can step around, and every one of those must be named rather than
  counted as a guarantee.

  The single most important discipline in this phase is the paired control.
  L22 records a run where an inline probe reported that clawuser had CONNECTED
  to smtp.gmail.com on 465 and 587. That was fabricated by the channel, and it
  would have been filed as a ship-blocking hole in a firewall that was working
  correctly. It was caught by one thing only: a control that also reported
  success when success was impossible. So every block assertion below carries a
  control that MUST succeed and, where meaningful, one that MUST fail.

  Test 6 re-runs 1, 3 and 4 after a reboot, because a property that only holds
  until the next restart is not a property. The nft allowlist has been shown to
  survive `wsl --shutdown` and a full Windows reboot on v1.0.47; this confirms
  it on v1.2.0 rather than inheriting the result.

  Pass -PostReboot to run only the subset that test 6 requires.
#>
param(
    [string]$Transcript = 'C:\cfv\phase4-out-probe.txt',
    [switch]$PostReboot
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1

function W([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line; $line | Out-File $Transcript -Encoding utf8 -Append
}
function Section($t) { W ''; W ("=" * 72); W $t; W ("=" * 72) }
$script:Results = New-Object System.Collections.ArrayList
function Record($id, $name, $verdict, $evidence) {
    [void]$script:Results.Add([pscustomobject]@{ Id = $id; Name = $name; Verdict = $verdict; Evidence = $evidence })
    W ("  [{0}] {1} :: {2}" -f $verdict, $id, $name)
    if ($evidence) { W ("        {0}" -f ($evidence -replace "`r?`n", ' | ')) }
}
$tag = if ($PostReboot) { 'POSTREBOOT' } else { 'PRE' }

Section "ClawFactory v1.2.0 INTERIM validation, Phase 4 (structural), pass=$tag. $(Get-Date -Format s)"

$chan = Test-WslChannel
Record "S.CHAN.$tag" 'File-based WSL channel discriminates' $(if ($chan.Ok) { 'PASS' } else { 'FAIL' }) $chan.Detail
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; W 'PHASE4_PROBE_COMPLETE rc=2'; exit 2 }

# ------------------------------------------------------- 1. SMTP blocked
Section "1. As the agent uid: SMTP blocked at EVERY destination, with the 443 control that must succeed"
$net = Invoke-WslFile -Tag "s1-$tag" -User 'clawuser' -Body @'
echo "whoami=$(id -un) uid=$(id -u)"
probe() {
  if timeout 8 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then echo "$1:$2 CONNECTED"; else echo "$1:$2 blocked"; fi
}
echo '--- SUBJECT: SMTP, several providers plus loopback and a raw IP ---'
for h in smtp.gmail.com smtp.office365.com smtp.mail.yahoo.com 127.0.0.1 1.1.1.1; do
  for p in 25 465 587 2525; do probe $h $p; done
done
echo '--- CONTROL A (MUST SUCCEED): allowlisted provider on 443 ---'
probe api.anthropic.com 443
echo '--- CONTROL B (MUST FAIL): non-allowlisted host on 443 ---'
probe example.org 443
echo '--- CONTROL C (MUST SUCCEED): the probe mechanism itself can see a live listener ---'
(node -e "require(\"net\").createServer(s=>s.end()).listen(19999,\"127.0.0.1\")" &) >/dev/null 2>&1
sleep 2
probe 127.0.0.1 19999
pkill -f "listen(19999" 2>/dev/null
'@
W $net.Out
$anySmtp   = $net.Out -match ':(25|465|587|2525) CONNECTED'
$ctlA      = $net.Out -match 'api\.anthropic\.com:443 CONNECTED'
$ctlB      = $net.Out -match 'example\.org:443 blocked'
$ctlC      = $net.Out -match '127\.0\.0\.1:19999 CONNECTED'
Record "S.1.$tag" 'No route to SMTP for uid 1000 at any destination' `
    $(if (-not $anySmtp) { 'PASS' } else { 'FAIL' }) 'no CONNECTED on 25/465/587/2525 anywhere'
Record "S.1ctlA.$tag" 'CONTROL (must succeed): allowlisted 443 connects' `
    $(if ($ctlA) { 'PASS' } else { 'FAIL' }) 'without this the blocks above could be a dead network'
Record "S.1ctlB.$tag" 'CONTROL (must fail): non-allowlisted 443 blocked' `
    $(if ($ctlB) { 'PASS' } else { 'FAIL' }) 'proves the allowlist discriminates by host, not just by port'
Record "S.1ctlC.$tag" 'CONTROL (must succeed): the probe can observe a real listener' `
    $(if ($ctlC) { 'PASS' } else { 'REVIEW' }) 'proves /dev/tcp probing works at all in this shell'

if (-not $PostReboot) {
    # -------------------------------------------------- 2. shipped refresh
    Section "2. Run the SHIPPED refresh, then re-run test 1. The block must hold."
    $refresh = Invoke-WslFile -Tag 's2' -User 'root' -Body @'
echo '--- units involved in the refresh cycle ---'
systemctl list-units --all --no-pager 2>/dev/null | grep -iE 'clawfactory-(fw|allow)' || echo '(none listed)'
echo '--- running the shipped refresh ---'
if systemctl list-unit-files 2>/dev/null | grep -q clawfactory-allow-providers.service; then
  systemctl restart clawfactory-allow-providers.service 2>&1
  echo "restart_rc=$?"
elif [ -x /usr/local/sbin/clawfactory-fw-apply.sh ]; then
  /usr/local/sbin/clawfactory-fw-apply.sh 2>&1
  echo "apply_rc=$?"
else
  echo 'NO_REFRESH_MECHANISM_FOUND'
fi
sleep 3
echo '--- assert the chain shape after refresh ---'
/usr/local/sbin/clawfactory-fw-assert.sh 2>&1
echo "assert_rc=$?"
'@
    W $refresh.Out
    $net2 = Invoke-WslFile -Tag 's2b' -User 'clawuser' -Body @'
probe() { if timeout 8 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then echo "$1:$2 CONNECTED"; else echo "$1:$2 blocked"; fi }
for p in 25 465 587; do probe smtp.gmail.com $p; done
echo '--- CONTROL (MUST SUCCEED) ---'
probe api.anthropic.com 443
'@
    W $net2.Out
    Record 'S.2' 'Block holds across the shipped refresh' `
        $(if (($net2.Out -notmatch ':(25|465|587) CONNECTED') -and ($net2.Out -match 'api\.anthropic\.com:443 CONNECTED')) { 'PASS' } else { 'FAIL' }) `
        'the refresh is the thing that silently erases hand-written rules; the property must survive it'

    # ------------------------------------------------------- 3. tripwire
    Section "3. Chain-shape tripwire fires on a deliberately widened accept, and returns clean"
    $trip = Invoke-WslFile -Tag 's3' -User 'root' -Body @'
ASSERT=/usr/local/sbin/clawfactory-fw-assert.sh
echo '--- BASELINE: tripwire on the shipped shape must be CLEAN ---'
$ASSERT 2>&1; echo "baseline_rc=$?"

echo '--- locate the chain ---'
TBL=$(nft list ruleset 2>/dev/null | grep -m1 -oE 'table [a-z0-9]+ [a-z_]+' | awk "{print \$2\" \"\$3}")
CH=$(nft list ruleset 2>/dev/null | grep -m1 -oE 'chain [a-z_]+' | awk "{print \$2}")
echo "table=$TBL chain=$CH"

echo '--- WIDEN: add an accept naming an SMTP port (the exact drift the tripwire exists to catch) ---'
nft add rule $TBL $CH tcp dport 587 accept 2>&1
echo "widen_rc=$?"
nft list ruleset 2>/dev/null | grep -nE 'dport 587' | head -3

echo '--- tripwire MUST now FAIL ---'
$ASSERT 2>&1; echo "widened_rc=$?"

echo '--- REVERT: delete the widened rule ---'
HANDLE=$(nft -a list ruleset 2>/dev/null | grep -E 'tcp dport 587 accept' | grep -oE 'handle [0-9]+' | head -1 | awk "{print \$2}")
echo "handle=$HANDLE"
[ -n "$HANDLE" ] && nft delete rule $TBL $CH handle $HANDLE 2>&1
echo "revert_rc=$?"
nft list ruleset 2>/dev/null | grep -cE 'dport 587 accept' | sed "s/^/remaining_587_accepts=/"

echo '--- tripwire MUST be CLEAN again ---'
$ASSERT 2>&1; echo "reverted_rc=$?"
'@
    W $trip.Out
    $baseClean = $trip.Out -match 'baseline_rc=0'
    $firedOnWiden = ($trip.Out -match 'widened_rc=[1-9]') -or ($trip.Out -match 'FAIL: an accept rule names an SMTP port')
    $cleanAgain = $trip.Out -match 'reverted_rc=0'
    Record 'S.3' 'Tripwire fires on a widened accept and returns clean after revert' `
        $(if ($baseClean -and $firedOnWiden -and $cleanAgain) { 'PASS' } else { 'FAIL' }) `
        "baselineClean=$baseClean firedOnWiden=$firedOnWiden cleanAfterRevert=$cleanAgain"
    Record 'S.3c' 'CONTROL: the tripwire was clean BEFORE the widening' `
        $(if ($baseClean) { 'PASS' } else { 'FAIL' }) `
        'a checker that always fails would also "fire", and would prove nothing'
}

# --------------------------------------------- 4. credential confidentiality
Section "4. Credential unreadable by the agent uid, and absent from every surface"
$cred = Invoke-WslFile -Tag "s4-$tag" -User 'root' -Body @'
echo "--- mode ---"
stat -c '%n %a %U:%G' /etc/clawfactory/send-credential.json 2>&1
echo '--- SUBJECT: as the agent uid ---'
su -s /bin/bash -c 'cat /etc/clawfactory/send-credential.json' clawuser 2>&1 | head -2
echo '--- CONTROL: a file the agent CAN read ---'
su -s /bin/bash -c 'head -1 /etc/clawfactory/send.json' clawuser 2>&1 | head -2
echo '--- leak scan against the REAL secret; the value is never printed ---'
SECRET=$(node -e '
try{const j=require("/etc/clawfactory/send-credential.json");
process.stdout.write(j.pass||j.password||j.secret||j.appPassword||"");}catch(e){process.stdout.write("");}
')
if [ -z "$SECRET" ]; then echo "NO_SECRET_CONFIGURED"; exit 0; fi
echo "secret configured, length=${#SECRET}"
tot=0
for d in /var/lib/clawfactory /var/log /home/clawuser /tmp /etc/systemd; do
  n=$(grep -rlF -- "$SECRET" "$d" 2>/dev/null | grep -v '^/etc/clawfactory/send-credential.json$' | wc -l)
  echo "SCAN $d hits=$n"
  tot=$((tot+n))
done
echo "SCAN journal hits=$(journalctl --no-pager 2>/dev/null | grep -cF -- "$SECRET")"
# Snapshot ps FIRST and compare inside node. Piping ps into `grep -F -- "$SECRET"`
# puts the secret on grep's own argv, which ps then captures, so the scan reports
# exactly one hit that IS the scan. That false positive is indistinguishable from
# a real credential leak, in the one test whose whole purpose is finding one.
ps auxww > /var/tmp/ps.snap 2>/dev/null; chmod 600 /var/tmp/ps.snap
echo "SCAN ps hits=$(node -e '
const fs=require("fs");
let c={};try{c=JSON.parse(fs.readFileSync("/etc/clawfactory/send-credential.json","utf8"))}catch(e){console.log(0);process.exit(0)}
const s=c.pass||c.password||c.secret||c.appPassword||"";
if(!s){console.log(0);process.exit(0)}
console.log(fs.readFileSync("/var/tmp/ps.snap","utf8").split(s).length-1);
' 2>/dev/null)"
rm -f /var/tmp/ps.snap
echo "SCAN env-of-broker hits=$(tr '\0' '\n' < /proc/$(pgrep -f clawfactory-sendd.js | head -1)/environ 2>/dev/null | grep -cF -- "$SECRET")"
echo "TOTAL_HITS=$tot"
echo '--- CONTROL: the scanner MUST find it where it legitimately lives ---'
grep -qF -- "$SECRET" /etc/clawfactory/send-credential.json && echo CONTROL_SCANNER_WORKS || echo CONTROL_SCANNER_BLIND
'@
W $cred.Out
$unreadable = $cred.Out -match 'Permission denied'
Record "S.4.$tag" 'Credential unreadable by the agent uid' `
    $(if ($unreadable) { 'PASS' } else { 'FAIL' }) '0600 root:root'
if ($cred.Out -match 'NO_SECRET_CONFIGURED') {
    Record "S.4leak.$tag" 'Credential value absent from logs, receipts, errors, process listing' 'BLOCKED' `
        'no real credential configured at run time; a synthetic secret would make this a synthetic test'
} else {
    $blind = $cred.Out -match 'CONTROL_SCANNER_BLIND'
    $zero  = ($cred.Out -match 'TOTAL_HITS=0') -and ($cred.Out -match 'journal hits=0') -and ($cred.Out -match 'ps hits=0')
    Record "S.4leak.$tag" 'Credential value absent from logs, receipts, errors, process listing' `
        $(if ($zero -and -not $blind) { 'PASS' } else { 'FAIL' }) 'scanned against the real secret'
    Record "S.4ctl.$tag" 'CONTROL: scanner finds the secret in the credential file itself' `
        $(if (-not $blind) { 'PASS' } else { 'FAIL' }) 'zero hits from a blind scanner would be a false pass'
}

if (-not $PostReboot) {
    # ----------------------------------------------------- 5. kill switch
    Section "5. Kill switch cancels pending sends and purges staging"
    $kill = Invoke-WslFile -Tag 's5' -User 'root' -Body @'
CTL='node /usr/local/sbin/clawfactory-sendctl.js'
echo '--- queue two requests as the agent ---'
for i in 1 2; do
  su -s /bin/bash -c "printf 'kill body %s\n' $i > /tmp/kb$i.txt; printf 'kill attach %s\n' $i > /tmp/ka$i.txt; clawfactory-send --to sink@example.com --subject \"KILL-$i\" --body-file /tmp/kb$i.txt --attach /tmp/ka$i.txt" clawuser 2>&1 | head -3
done
echo '--- BEFORE ---'
echo "pending files : $(ls -1 /var/lib/clawfactory/send/pending 2>/dev/null | wc -l)"
echo "staging dirs  : $(ls -1 /var/lib/clawfactory/send/staging 2>/dev/null | wc -l)"
echo '--- KILL ---'
$CTL kill 2>&1
echo "kill_rc=$?"
sleep 2
echo '--- AFTER ---'
echo "pending files : $(ls -1 /var/lib/clawfactory/send/pending 2>/dev/null | wc -l)"
echo "staging dirs  : $(ls -1 /var/lib/clawfactory/send/staging 2>/dev/null | wc -l)"
# The LIVE queue, which is what "cancelled" means. Counting files in the pending
# directory conflates live requests with retained historical records, and those
# records are deliberately kept so a cancellation is auditable rather than
# vanishing. The first version asserted on the file count and reported REVIEW for
# a kill that had correctly cancelled everything live.
echo "LIVE_PENDING_AFTER=$(node /usr/local/sbin/clawfactory-sendctl.js list 2>/dev/null | grep -o '"requestId"' | wc -l)"
echo '--- receipts should record the cancellation rather than losing it silently ---'
grep -lE 'cancel|kill|denied' /var/lib/clawfactory/send/receipts/*.json 2>/dev/null | wc -l | sed 's/^/cancel_receipts=/'
echo '--- CONTROL: after the kill, a NEW request must still be acceptable ---'
su -s /bin/bash -c "printf 'post kill\n' > /tmp/kb3.txt; clawfactory-send --to sink@example.com --subject 'KILL-CTL' --body-file /tmp/kb3.txt" clawuser 2>&1 | head -3
'@
    W $kill.Out
    $liveAfter = if ($kill.Out -match 'LIVE_PENDING_AFTER=(\d+)') { [int]$Matches[1] } else { -1 }
    $stagAfter = if ($kill.Out -match '(?s)--- AFTER ---.*?staging dirs  : (\d+)') { [int]$Matches[1] } else { -1 }
    $cancelled = if ($kill.Out -match '"cancelled"\s*:\s*(\d+)') { [int]$Matches[1] } else { -1 }
    Record 'S.5' 'Kill switch cancels pending sends and purges staging' `
        $(if ($liveAfter -eq 0 -and $stagAfter -eq 0 -and $cancelled -gt 0) { 'PASS' } else { 'REVIEW' }) `
        "broker reported cancelled=$cancelled; live queue after=$liveAfter; staging dirs after=$stagAfter"
    Record 'S.5c' 'CONTROL: the broker still accepts a new request after the kill' `
        $(if ($kill.Out -match 'pending') { 'PASS' } else { 'REVIEW' }) `
        'proves kill cancelled the queue rather than bricking the broker'
}

Section "Phase 4 result table (pass=$tag)"
foreach ($row in $script:Results) { W ("{0,-20} {1,-10} {2}" -f $row.Id, $row.Verdict, $row.Name) }
$outJson = if ($PostReboot) { 'C:\cfv\phase4-results-postreboot.json' } else { 'C:\cfv\phase4-results.json' }
$script:Results | ConvertTo-Json -Depth 4 | Out-File $outJson -Encoding utf8
$f = @($script:Results | Where-Object { $_.Verdict -eq 'FAIL' })
W ''
W "FAIL=$($f.Count)"
foreach ($x in $f) { W "   FAIL $($x.Id) $($x.Name) :: $($x.Evidence)" }
W "PHASE4_PROBE_COMPLETE rc=$($f.Count)"
exit $f.Count
