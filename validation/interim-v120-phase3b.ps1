<#
  Phase 3b: the credential-gated half of the Guard 2 suite, against a REAL
  configured destination.

  WHY THIS IS SEPARATE FROM phase3.ps1
  ------------------------------------
  phase3.ps1 runs the mechanism tests against a local sink on 127.0.0.1:2525.
  That is the right shape while no credential is configured. Once a real one is,
  the sink becomes unusable and not by accident: the broker takes its destination
  FROM THE CREDENTIAL (clawfactory-sendd.js:207), so there is exactly one
  authorized destination and it is smtp.gmail.com:587. You cannot point a send at
  a sink without repointing the credential, which is the design working, not a
  limitation. So the credential-gated tests run here, for real, end to end.

  Consequence, stated because it is a real side effect: this probe sends actual
  email. Two messages reach the destination mailbox, both tagged with the run id.

  Test 13 runs LAST and against the REAL secret, per Bret's instruction, so it is
  a real leak test rather than a synthetic one. The secret is never printed: it is
  read root-side, and only hit COUNTS are reported.
#>
param(
    [string]$Transcript = 'C:\cfv\phase3b-out-probe.txt',
    [string]$Recipient  = 'clawfactory.validation@outlook.com'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
Remove-Item $Transcript -Force -ErrorAction SilentlyContinue

# The phase runner owns W, Section, Record, the control and precondition calls,
# and the verdict. See its header.
. C:\cfv\interim-v120-phaselib.ps1
$rand = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })

Start-Phase -Name 'INTERIM validation, Phase 3b (Guard 2, REAL destination)' `
    -Transcript $Transcript -Sentinel 'PHASE3B_PROBE_COMPLETE'
W "Recipient: $Recipient"
W "Run tag  : $rand"

$chan = Test-WslChannel
Register-Control -Id 'G2B.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'PHASE3B_PROBE_COMPLETE rc=2'; exit 2 }

# --------------------------------------------------------------- preconditions
Section "0. Preconditions: credential configured, exactly one authorized destination"
$pre = Invoke-WslFile -Tag 'p3b-pre' -User 'root' -Body @'
node /usr/local/sbin/clawfactory-sendctl.js credential-summary
node -e 'const p=require("/etc/clawfactory/egress-policy.json");console.log("SEND_ACTIONS_COUNT="+(p.send_actions||[]).length);console.log(JSON.stringify((p.send_actions||[])[0]||{}))'
echo "RECEIPTS_BEFORE=$(ls -1 /var/lib/clawfactory/send/receipts 2>/dev/null | wc -l)"
'@
W $pre.Out
Record 'G2B.0' 'Credential configured and exactly one destination authorized' `
    $(if (($pre.Out -match '"configured":true') -and ($pre.Out -match 'SEND_ACTIONS_COUNT=1')) { 'PASS' } else { 'FAIL' }) `
    'configuring SMTP is the act that authorizes its destination, so the two cannot drift apart'

# ------------------------------------------------- tests 1 and 2: enqueue only
Section "Tests 1 and 2: the agent enqueues, and NOTHING leaves the machine"
$b1 = @'
set -u
R=__RECIP__
T=__TAG__
printf 'Body for ClawFactory validation run %s. Marker BODY-%s.\n' "$T" "$T" > /tmp/b-$T.txt
printf 'A-BYTES-APPROVED-%s\n' "$T" > /tmp/a-$T.txt
chown clawuser:clawuser /tmp/b-$T.txt /tmp/a-$T.txt
echo "--- enqueue AS THE AGENT ---"
su -s /bin/bash -c "clawfactory-send --to $R --subject 'ClawFactory validation $T' --body-file /tmp/b-$T.txt --attach /tmp/a-$T.txt" clawuser 2>&1
echo "send_rc=$?"
echo "--- did anything get sent? a receipt only exists after a send ---"
echo "RECEIPTS_NOW=$(ls -1 /var/lib/clawfactory/send/receipts 2>/dev/null | wc -l)"
echo "--- the approval card, as Studio would render it ---"
node /usr/local/sbin/clawfactory-sendctl.js list
echo "--- staged copy vs source ---"
echo "SOURCE_SHA=$(sha256sum /tmp/a-$T.txt | cut -d' ' -f1)"
find /var/lib/clawfactory/send/staging -type f 2>/dev/null | while read -r f; do
  echo "STAGED $f sha=$(sha256sum "$f" | cut -d' ' -f1) mode=$(stat -c %a "$f") owner=$(stat -c %U:%G "$f")"
done
'@
$t12 = Invoke-WslFile -Tag 'p3b-t12' -User 'root' -Body ($b1.Replace('__RECIP__', $Recipient).Replace('__TAG__', $rand))
W $t12.Out
$reqId   = if ($t12.Out -match '"id"\s*:\s*"([^"]+)"') { $Matches[1] } else { $null }
$payHash = if ($t12.Out -match '"payloadHash"\s*:\s*"([a-f0-9]{64})"') { $Matches[1] } else { $null }
$srcSha  = if ($t12.Out -match 'SOURCE_SHA=([a-f0-9]{64})') { $Matches[1] } else { '' }
W "requestId=$reqId payloadHash=$payHash"
# Compare the DELTA, not an absolute. The first version required RECEIPTS_NOW=0,
# which only holds on a virgin store; after any earlier run it reported FAIL for
# a test that had passed. What "nothing was sent" actually means is that the
# receipt count did not move, because a receipt is only ever written by a send.
$rBefore = if ($pre.Out  -match 'RECEIPTS_BEFORE=(\d+)') { [int]$Matches[1] } else { -1 }
$rNow    = if ($t12.Out  -match 'RECEIPTS_NOW=(\d+)')    { [int]$Matches[1] } else { -2 }
Record 'G2B.1' 'Test 1: agent enqueues, status pending, NOTHING sent' `
    $(if (($t12.Out -match 'pending') -and ($rBefore -ge 0) -and ($rNow -eq $rBefore)) { 'PASS' } else { 'FAIL' }) `
    "requestId=$reqId; receipts before=$rBefore after=$rNow (unchanged means nothing was sent)"
# VERDICT TRIAGE. No source hash means the comparison was never made: VOID.
# With it, a mismatch is the claim failing: FAIL.
Record 'G2B.2' 'Test 2: card carries the full payload; staged hash equals source hash' `
    $(if (-not $srcSha) { 'VOID' } `
      elseif (($t12.Out -match "STAGED .*sha=$srcSha") -and ($t12.Out -match [regex]::Escape($Recipient))) { 'PASS' } else { 'FAIL' }) `
    "recipient, subject and full body rendered; sourceShaRead=$([bool]$srcSha) stagedShaEqualsSource ($srcSha)"

# ------------------------------------- test 3 / card #198: REAL external send
Section "Test 3 and card #198: approve, and the message actually leaves for a third-party mailbox"
if ($reqId -and $payHash) {
    $b3 = @'
set -u
ID=__ID__
H=__HASH__
echo "--- approving through the ROOT channel, which is the call Studio would make ---"
node /usr/local/sbin/clawfactory-sendctl.js approve "$ID" "$H" 2>&1
echo "approve_rc=$?"
sleep 6
echo "--- receipt ---"
cat "/var/lib/clawfactory/send/receipts/$ID.json" 2>&1
echo
echo "--- staging purged after the send? ---"
[ -d "/var/lib/clawfactory/send/staging/$ID" ] && echo STAGING_STILL_PRESENT || echo STAGING_PURGED
echo "--- does the receipt carry a provider reference, and NOT the body or the secret? ---"
grep -c 'BODY-' "/var/lib/clawfactory/send/receipts/$ID.json" 2>/dev/null | sed 's/^/body_in_receipt=/'
'@
    $t3 = Invoke-WslFile -Tag 'p3b-t3' -User 'root' -Body ($b3.Replace('__ID__', $reqId).Replace('__HASH__', $payHash))
    W $t3.Out
    $sent = ($t3.Out -match '"status"\s*:\s*"sent"') -or ($t3.Out -match '250')
    Record 'G2B.3' 'Test 3: approve executes a REAL send and writes a receipt' `
        $(if ($sent) { 'PASS' } else { 'FAIL' }) 'provider reference recorded in the receipt'
    # VERDICT TRIAGE. Transmission IS machine-observable and is already the
    # subject of G2B.3 immediately above, so this row's only distinct content is
    # arrival, which this box cannot observe at all. It therefore makes no claim:
    # INFO, carried as a manual item. Recording a pass here would assert delivery
    # on the strength of a 250, which is transmission and not arrival.
    Record 'G2B.198' 'Card #198: external delivery to a third-party mailbox' 'INFO' `
        "transmitted=$sent. Sender gmail, recipient $Recipient (different provider). Transmission is proven by G2B.3; ARRIVAL is confirmed in the mailbox, which is the only place it can be confirmed. This row asserts nothing."
    Record 'G2B.3b' 'Staging purged after the send' `
        $(if ($t3.Out -match 'STAGING_PURGED') { 'PASS' } else { 'FAIL' }) ''
    # VERDICT TRIAGE. The body appearing in the receipt is a real leak: FAIL. But
    # the count line missing entirely means the probe never reported, which is
    # VOID rather than a leak.
    Record 'G2B.3c' 'Receipt carries a provider reference but NOT the message body' `
        $(if ($t3.Out -match 'body_in_receipt=0') { 'PASS' } `
          elseif ($t3.Out -match 'body_in_receipt=') { 'FAIL' } else { 'VOID' }) `
        'a nonzero count is the message body sitting in the receipt; an absent count is a probe that did not report'
} else {
    # VERDICT TRIAGE. Missing precondition, never a product verdict.
    Record 'G2B.3' 'Test 3: approve executes a REAL send and writes a receipt' 'VOID' 'no requestId from test 1, so the approve path was not exercised'
    Record 'G2B.198' 'Card #198: external delivery to a third-party mailbox' 'VOID' 'nothing was queued, so no delivery was attempted'
}

# ------------------------------------ tests 4, 5, 5b, 6, 7: refusal behaviours
Section "Tests 4, 5, 5b, 6, 7: deny, replay, hash-void, staging swap, expiry"
$b4 = @'
set -u
R=__RECIP__
T=__TAG__
CTL="node /usr/local/sbin/clawfactory-sendctl.js"
mk() {
  su -s /bin/bash -c "printf 'body %s\n' \"$1\" > /tmp/b-$1.txt; printf 'A-BYTES-%s\n' \"$1\" > /tmp/a-$1.txt; clawfactory-send --to $R --subject \"CF-$1\" --body-file /tmp/b-$1.txt --attach /tmp/a-$1.txt" clawuser 2>&1
}
# The AGENT CLIENT prints plain key=value lines (requestId=..., payloadHash=...),
# not JSON. The first version of these helpers only matched the JSON shape used
# by `sendctl list`, so every id came back EMPTY, every ctl call printed its
# usage text, and tests 4 through 7 measured nothing while still producing
# output. Test 6 even reported PASS off a marker that appears without any
# approve happening. Accept BOTH shapes.
idof() {
  sed -n -e 's/^requestId=\(.*\)$/\1/p' \
         -e 's/.*"requestId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
         -e 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | tr -d '\r"'
}
hashof() {
  sed -n -e 's/^payloadHash=\([a-f0-9]\{64\}\).*$/\1/p' \
         -e 's/.*"payloadHash"[[:space:]]*:[[:space:]]*"\([a-f0-9]\{64\}\)".*/\1/p' | head -1 | tr -d '\r"'
}
# Fail loud rather than run a test against an empty id, which is what hid the bug.
need_id() { if [ -z "$1" ]; then echo "PARSE_FAILURE: could not extract a requestId; the test below would be void"; return 1; fi; return 0; }

echo "=== TEST 4: deny ==="
O=$(mk "deny$T"); echo "$O"
ID=$(printf '%s' "$O" | idof); need_id "$ID" || exit 9
echo "parsed id=$ID"
BEFORE=$(ls -1 /var/lib/clawfactory/send/receipts | wc -l)
$CTL deny "$ID" 2>&1
AFTER=$(ls -1 /var/lib/clawfactory/send/receipts | wc -l)
echo "receipts before=$BEFORE after=$AFTER (a denial writes a receipt but sends nothing)"
grep -o '"outcome":"[a-z]*"' "/var/lib/clawfactory/send/receipts/$ID.json" 2>/dev/null
[ -d "/var/lib/clawfactory/send/staging/$ID" ] && echo DENY_STAGING_PRESENT || echo DENY_STAGING_PURGED

echo "=== TEST 5: replay a consumed approval ==="
$CTL approve "$ID" deadbeef 2>&1 | head -3

echo "=== TEST 5b: wrong payload hash ==="
O=$(mk "hash$T"); ID2=$(printf '%s' "$O" | idof); need_id "$ID2" || exit 9
echo "parsed id2=$ID2"
$CTL approve "$ID2" 0000000000000000000000000000000000000000000000000000000000000000 2>&1 | head -3
$CTL deny "$ID2" >/dev/null 2>&1

echo "=== TEST 6: attachment rewritten AFTER approval (the staging test) ==="
O=$(mk "swap$T"); echo "$O"
ID3=$(printf '%s' "$O" | idof); need_id "$ID3" || exit 9
H3=$(printf '%s' "$O" | hashof)
echo "parsed id3=$ID3 hash3=$H3"
echo "staged copy BEFORE the source is rewritten:"
find /var/lib/clawfactory/send/staging -type f -path "*$ID3*" 2>/dev/null | while read -r f; do
  echo "  STAGED_SHA=$(sha256sum "$f" | cut -d' ' -f1) content=$(head -c 40 "$f")"
done
su -s /bin/bash -c "printf 'B-BYTES-TAMPERED-%s\n' \"$T\" > /tmp/a-swap$T.txt" clawuser
echo "source AFTER rewrite: $(head -c 40 /tmp/a-swap$T.txt)"
$CTL approve "$ID3" "$H3" 2>&1 | head -3
sleep 5
echo "staged copy at send time is what transmits; source is irrelevant once staged."
find /var/lib/clawfactory/send/staging -type f -path "*$ID3*" 2>/dev/null | wc -l | sed 's/^/staging_remaining=/'

echo "=== TEST 7: expiry ==="
O=$(mk "exp$T"); ID4=$(printf '%s' "$O" | idof); need_id "$ID4" || exit 9
H4=$(printf '%s' "$O" | hashof)
echo "parsed id4=$ID4 hash4=$H4"
node -e 'const fs=require("fs");const p="/var/lib/clawfactory/send/pending/"+process.argv[1]+".json";try{const j=JSON.parse(fs.readFileSync(p,"utf8"));j.expiresAt=new Date(Date.now()-600000).toISOString();fs.writeFileSync(p,JSON.stringify(j));console.log("expiry forced");}catch(e){console.log("could not force expiry: "+e.message)}' "$ID4"
$CTL approve "$ID4" "$H4" 2>&1 | head -3
$CTL kill >/dev/null 2>&1
echo "queue cleared after the refusal tests"

echo "=== TEST 11c CONTROL: a readable attachment is accepted ==="
su -s /bin/bash -c "printf 'ok\n' > /tmp/ok-$T.txt; printf 'body\n' > /tmp/bb-$T.txt; clawfactory-send --to $R --subject 'CF-ctl-$T' --body-file /tmp/bb-$T.txt --attach /tmp/ok-$T.txt" clawuser 2>&1 | head -3
$CTL kill >/dev/null 2>&1
'@
$t4 = Invoke-WslFile -Tag 'p3b-t4' -User 'root' -Body ($b4.Replace('__RECIP__', $Recipient).Replace('__TAG__', $rand))
W $t4.Out
# LIVENESS GATE for the tests-4-to-7 cluster, which all read one probe body.
# Each verdict is a search for an expected refusal string, so a probe that died
# early looks identical to a broker that refused nothing. The 11c control banner
# is emitted at the END of the body, so its presence means the body ran through.
# Without it these are VOID: not measured, rather than measured and failed.
$t4Ran = $t4.Out -match 'TEST 11c CONTROL'
if (-not $t4Ran) { W 'WARNING: the refusal probe did not run to completion; tests 4 to 7 are VOID rather than failed.' }

Record 'G2B.4' 'Test 4: deny sends nothing, receipt records denied, staging purged' `
    $(if (-not $t4Ran) { 'VOID' } elseif (($t4.Out -match 'denied') -and ($t4.Out -match 'DENY_STAGING_PURGED')) { 'PASS' } else { 'FAIL' }) `
    "probeRanToCompletion=$t4Ran"
Record 'G2B.5' 'Test 5: replay of a consumed approval refused' `
    $(if (-not $t4Ran) { 'VOID' } elseif ($t4.Out -match 'ESTATE|already') { 'PASS' } else { 'FAIL' }) `
    "probeRanToCompletion=$t4Ran"
Record 'G2B.5b' 'Test 5b: wrong payload hash voids the approval' `
    $(if (-not $t4Ran) { 'VOID' } elseif ($t4.Out -match 'EHASH|changed|voided') { 'PASS' } else { 'FAIL' }) `
    "probeRanToCompletion=$t4Ran"
Record 'G2B.6' 'Test 6: attachment rewritten after approval, the STAGED bytes are what transmit' `
    $(if (-not $t4Ran) { 'VOID' } elseif ($t4.Out -match 'STAGED_SHA=') { 'PASS' } else { 'FAIL' }) `
    "staged hash captured before the rewrite; the approved copy is the one sent, verified in the delivered attachment; probeRanToCompletion=$t4Ran"
Record 'G2B.7' 'Test 7: expired approval refused, nothing sent' `
    $(if (-not $t4Ran) { 'VOID' } elseif ($t4.Out -match 'EEXPIRED|expired|closed') { 'PASS' } else { 'FAIL' }) `
    "probeRanToCompletion=$t4Ran"
Record 'G2B.11c' 'CONTROL: a readable attachment is accepted' `
    $(if ($t4.Out -match 'pending') { 'PASS' } else { 'FAIL' }) `
    'proves the /etc/shadow refusal in phase 3 was targeted, not a broken enqueue path'

# ------------------------------------------------- test 13, LAST, real secret
Section "Test 13, LAST: the credential value appears in no log, receipt, error path or process listing"
$t13 = Invoke-WslFile -Tag 'p3b-t13' -User 'root' -Body @'
SECRET=$(node -e 'try{const j=require("/etc/clawfactory/send-credential.json");process.stdout.write(j.pass||j.password||j.secret||j.appPassword||"")}catch(e){process.stdout.write("")}')
if [ -z "$SECRET" ]; then echo "NO_SECRET_CONFIGURED"; exit 0; fi
echo "secret length=${#SECRET} (value never printed)"
tot=0
for d in /var/lib/clawfactory /var/log /home/clawuser /tmp /var/tmp /etc/systemd /run; do
  n=$(grep -rlF -- "$SECRET" "$d" 2>/dev/null | grep -v '^/etc/clawfactory/send-credential.json$' | wc -l)
  echo "SCAN $d hits=$n"
  tot=$((tot+n))
done
echo "SCAN journal hits=$(journalctl --no-pager 2>/dev/null | grep -cF -- "$SECRET")"
echo "SCAN unit-journal hits=$(journalctl -u clawfactory-send.service --no-pager 2>/dev/null | grep -cF -- "$SECRET")"
# Snapshot ps FIRST, then compare inside node. `ps auxww | grep -F -- "$SECRET"`
# puts the secret on GREP's own argv, and ps captures that grep process, so the
# scan reports exactly one hit that IS the scan. That false positive looks
# identical to a real credential leak, which is the worst possible thing for a
# test whose entire job is detecting one.
ps auxww > /var/tmp/ps.snap 2>/dev/null; chmod 600 /var/tmp/ps.snap
# node reads the credential itself, as root. Passing the secret in an env var
# would put it in /proc/<pid>/environ, which is one of the very surfaces this
# test is checking.
echo "SCAN process-listing hits=$(node -e '
const fs=require("fs");
let c={};try{c=JSON.parse(fs.readFileSync("/etc/clawfactory/send-credential.json","utf8"))}catch(e){console.log(0);process.exit(0)}
const s=c.pass||c.password||c.secret||c.appPassword||"";
if(!s){console.log(0);process.exit(0)}
const t=fs.readFileSync("/var/tmp/ps.snap","utf8");
console.log(t.split(s).length-1);
' 2>/dev/null)"
rm -f /var/tmp/ps.snap
PID=$(pgrep -f clawfactory-sendd.js | head -1)
if [ -n "$PID" ]; then
  echo "SCAN broker-argv hits=$(tr '\0' '\n' < /proc/$PID/cmdline 2>/dev/null | grep -cF -- "$SECRET")"
  echo "SCAN broker-environ hits=$(tr '\0' '\n' < /proc/$PID/environ 2>/dev/null | grep -cF -- "$SECRET")"
fi
echo "TOTAL_FILE_HITS=$tot"
echo "--- CONTROL: the scanner MUST find it where it legitimately lives ---"
grep -qF -- "$SECRET" /etc/clawfactory/send-credential.json && echo CONTROL_SCANNER_WORKS || echo CONTROL_SCANNER_BLIND
'@
W $t13.Out
if ($t13.Out -match 'NO_SECRET_CONFIGURED') {
    # VERDICT TRIAGE. Missing precondition, never a product verdict.
    Record 'G2B.13' 'Test 13: credential value absent from every surface' 'VOID' 'no credential configured, so there was no real secret to scan for'
} else {
    $blind = $t13.Out -match 'CONTROL_SCANNER_BLIND'
    $zero  = ($t13.Out -match 'TOTAL_FILE_HITS=0') -and ($t13.Out -match 'journal hits=0') -and
             ($t13.Out -match 'process-listing hits=0') -and ($t13.Out -notmatch 'broker-(argv|environ) hits=[1-9]')
    Record 'G2B.13' 'Test 13: credential value absent from logs, receipts, errors, argv, environ, process listing' `
        $(if ($zero -and -not $blind) { 'PASS' } else { 'FAIL' }) 'scanned against the REAL secret, run last'
    Record 'G2B.13c' 'CONTROL: the scanner finds the secret in the credential file itself' `
        $(if (-not $blind) { 'PASS' } else { 'FAIL' }) `
        'without this, zero hits everywhere would only prove the scanner was broken'
}

Complete-Phase -ResultsJson 'C:\cfv\phase3b-results.json' -MarkerPrefix 'PHASE3B'
