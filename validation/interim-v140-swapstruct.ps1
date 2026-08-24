<#
  G2.6 without a transport: does a post-approval source rewrite reach the bytes
  the broker would send?

  WHY NOT MEASURE IT THE OLD WAY
  ------------------------------
  The original test proves the property by comparing what arrives at a sink. On
  this build that is unmeasurable in BOTH directions:

    * a local sink cannot receive at all, because send-smtp.js refuses cleartext
      submission and no locally-issued certificate is trusted by this node build
      (measured: "unable to verify the first certificate ... try running Node.js
      with --use-system-ca");
    * a real provider WOULD accept, but its copy cannot be read back, so the
      A-bytes-versus-B-bytes comparison cannot be made there either.

  So the transport-based version of this test cannot be completed on any box.
  The PROPERTY, though, does not involve transport. clawfactory-sendd.js reads
  a.stagedPath both when it recomputes the hash at approve time and when it
  builds the message. The source path is recorded but never read again. So the
  question "can a source rewrite change what gets sent" is answerable entirely
  on the filesystem.

  THE CONTROL IS THE WHOLE TEST
  -----------------------------
  "The staged hash still matches after I rewrote the source" is worthless on its
  own, because a hash check that never fails produces exactly that result. So
  the probe also mutates the STAGED copy directly, as root, and requires the
  approve to be REFUSED. If both the untouched case is accepted and the mutated
  case is refused, the re-hash is real. If the mutated case is ALSO accepted,
  the check is decorative and that is a serious finding.
#>
param([string]$Transcript = 'C:\cfv\swapstruct-out-probe.txt')

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'G2.6 structurally: a post-approval source rewrite cannot reach the staged bytes' `
    -Transcript $Transcript -Sentinel 'SWAPSTRUCT_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'SS.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; W 'SWAPSTRUCT_PROBE_COMPLETE rc=2'; exit 2 }

Section '1. Staging is root-owned, which is why uid 1000 cannot reach into it'
$modes = Invoke-WslFile -Tag 'ss-modes' -User 'root' -Body @'
stat -c 'STAGEDIR %n mode=%a owner=%U:%G' /var/lib/clawfactory/send/staging 2>&1
echo '--- SUBJECT: can the agent uid list or write inside staging? ---'
su -s /bin/bash -c 'ls /var/lib/clawfactory/send/staging' clawuser 2>&1 | head -2
su -s /bin/bash -c 'touch /var/lib/clawfactory/send/staging/agent-was-here' clawuser 2>&1 | head -2
echo "AGENT_FILE_LANDED=$([ -e /var/lib/clawfactory/send/staging/agent-was-here ] && echo yes || echo no)"
echo '--- CONTROL: the agent CAN write somewhere it is supposed to be able to ---'
su -s /bin/bash -c 'touch /tmp/agent-can-write && echo CONTROL_AGENT_WRITE_OK' clawuser 2>&1 | head -2
rm -f /tmp/agent-can-write
'@
W $modes.Out
$stageMode = (($modes.Out -split "`n") | Where-Object { $_ -match '^STAGEDIR ' } | Select-Object -First 1)
$agentBlocked = $modes.Out -match 'AGENT_FILE_LANDED=no'
$agentCanWrite = $modes.Out -match 'CONTROL_AGENT_WRITE_OK'
Record 'SS.1' 'The staging directory is root-owned and closed to the agent uid' `
    $(if (-not $agentCanWrite) { 'VOID' } elseif ($agentBlocked) { 'PASS' } else { 'FAIL' }) `
    "$($stageMode.Trim()); agentWriteIntoStagingLanded=$(-not $agentBlocked); CONTROL agent can write elsewhere=$agentCanWrite"

Section '2. Enqueue A, rewrite the SOURCE to B, and see which bytes staging holds'
$swap = Invoke-WslFile -Tag 'ss-swap' -User 'root' -Body @'
CTL="node /usr/local/sbin/clawfactory-sendctl.js"
idof() { grep -oE 'requestId"?[[:space:]]*[:=][[:space:]]*"?[^"[:space:],}]+' | head -1 | sed -E 's/^.*[:=][[:space:]]*"?//'; }
O=$(su -s /bin/bash -c 'printf "swap body\n" > /tmp/ss-b.txt; printf "A-bytes APPROVED\n" > /tmp/ss-a.txt; clawfactory-send --to sink@example.com --subject "SWAPSTRUCT" --body-file /tmp/ss-b.txt --attach /tmp/ss-a.txt' clawuser 2>&1)
echo "$O"
ID=$(printf '%s' "$O" | idof); H=$(printf '%s' "$O" | grep -oE '[a-f0-9]{64}' | head -1)
echo "id=$ID boundHash=$H"
echo "SHA_OF_A=$(sha256sum /tmp/ss-a.txt | cut -d' ' -f1)"
STAGED=$(find /var/lib/clawfactory/send/staging/"$ID" -type f 2>/dev/null | head -1)
echo "STAGED_PATH=$STAGED"
echo "STAGED_SHA_BEFORE=$(sha256sum "$STAGED" 2>/dev/null | cut -d' ' -f1)"
echo '--- the agent rewrites its OWN source file, after the request was staged ---'
su -s /bin/bash -c 'printf "B-bytes TAMPERED\n" > /tmp/ss-a.txt' clawuser
echo "SHA_OF_B=$(sha256sum /tmp/ss-a.txt | cut -d' ' -f1)"
echo "STAGED_SHA_AFTER=$(sha256sum "$STAGED" 2>/dev/null | cut -d' ' -f1)"
echo "STAGED_CONTENT=$(cat "$STAGED" 2>/dev/null)"
echo '--- approve: the broker re-hashes the STAGED copy and compares to the bound hash ---'
$CTL approve "$ID" "$H" 2>&1 | head -3
echo "approve_rc=$?"
echo "RECEIPT_HASH=$(node -e 'try{const j=require("/var/lib/clawfactory/send/receipts/"+process.argv[1]+".json");process.stdout.write(String(j.payloadHash||""))}catch(e){process.stdout.write("")}' "$ID")"
echo "RECEIPT_OUTCOME=$(node -e 'try{const j=require("/var/lib/clawfactory/send/receipts/"+process.argv[1]+".json");process.stdout.write(String((j.result&&j.result.outcome)||""))}catch(e){process.stdout.write("")}' "$ID")"
'@
W $swap.Out
$shaA    = if ($swap.Out -match 'SHA_OF_A=([a-f0-9]{64})') { $Matches[1] } else { '' }
$shaB    = if ($swap.Out -match 'SHA_OF_B=([a-f0-9]{64})') { $Matches[1] } else { '' }
$stgAfter= if ($swap.Out -match 'STAGED_SHA_AFTER=([a-f0-9]{64})') { $Matches[1] } else { '' }
$content = if ($swap.Out -match 'STAGED_CONTENT=(.+)') { $Matches[1].Trim() } else { '' }
# VERDICT TRIAGE. Any hash unread means the comparison was not made: VOID.
# Staged equal to B is the tamper reaching the send path, which is the claim
# failing outright: FAIL.
Record 'SS.2' 'A post-approval rewrite of the SOURCE does not change the staged bytes' `
    $(if (-not $shaA -or -not $shaB -or -not $stgAfter) { 'VOID' } `
      elseif ($stgAfter -eq $shaB) { 'FAIL' } elseif ($stgAfter -eq $shaA) { 'PASS' } else { 'FAIL' }) `
    "shaA=$shaA shaB=$shaB stagedAfterRewrite=$stgAfter equalsA=$($stgAfter -eq $shaA) equalsB=$($stgAfter -eq $shaB); staged file reads: '$content'"
Record 'SS.2b' 'The two source versions really are different, so the comparison above discriminates' `
    $(if ($shaA -and $shaB -and ($shaA -ne $shaB)) { 'PASS' } else { 'VOID' }) `
    'if A and B hashed the same, SS.2 would pass no matter what the product did'

Section '3. THE CONTROL: mutate the STAGED copy itself, and require the approve to be refused'
$ctl = Invoke-WslFile -Tag 'ss-ctl' -User 'root' -Body @'
CTL="node /usr/local/sbin/clawfactory-sendctl.js"
idof() { grep -oE 'requestId"?[[:space:]]*[:=][[:space:]]*"?[^"[:space:],}]+' | head -1 | sed -E 's/^.*[:=][[:space:]]*"?//'; }
O=$(su -s /bin/bash -c 'printf "ctl body\n" > /tmp/ss-cb.txt; printf "A-bytes APPROVED\n" > /tmp/ss-ca.txt; clawfactory-send --to sink@example.com --subject "SWAPSTRUCT-CTL" --body-file /tmp/ss-cb.txt --attach /tmp/ss-ca.txt' clawuser 2>&1)
ID=$(printf '%s' "$O" | idof); H=$(printf '%s' "$O" | grep -oE '[a-f0-9]{64}' | head -1)
echo "ctl_id=$ID boundHash=$H"
STAGED=$(find /var/lib/clawfactory/send/staging/"$ID" -type f 2>/dev/null | head -1)
echo "ctl_staged=$STAGED"
echo '--- mutate the STAGED copy directly, as root. The re-hash MUST catch this. ---'
printf 'B-bytes TAMPERED IN STAGING\n' > "$STAGED"
echo "ctl_staged_sha=$(sha256sum "$STAGED" | cut -d' ' -f1)"
$CTL approve "$ID" "$H" 2>&1 | head -3
echo "ctl_approve_rc=$?"
'@
W $ctl.Out
$refused = ($ctl.Out -match 'EHASH') -or ($ctl.Out -match 'changed') -or ($ctl.Out -match 'voided') -or ($ctl.Out -match 'ctl_approve_rc=[^0]')
$ctlRan  = $ctl.Out -match 'ctl_staged_sha=[a-f0-9]{64}'
# VERDICT TRIAGE. If the mutation never landed, the control did not inject and
# a refusal would prove nothing: VOID. If the mutated payload is ACCEPTED, the
# re-hash is decorative and SS.2's pass means nothing either.
Record 'SS.3' 'CONTROL: a mutation of the STAGED copy is detected and the approve refused' `
    $(if (-not $ctlRan) { 'VOID' } elseif ($refused) { 'PASS' } else { 'FAIL' }) `
    "mutationLanded=$ctlRan approveRefused=$refused; without this, SS.2 passing would be indistinguishable from a hash check that never fires"

Complete-Phase -ResultsJson 'C:\cfv\swapstruct-results.json' -MarkerPrefix 'SWAPSTRUCT'
