<#
  Stage the TIMED subjects, immediately before the operator is pinged.

  WHY THIS IS SEPARATE FROM interim-v140-stagebox.ps1
  ---------------------------------------------------
  Everything stagebox writes is durable: a credential, an allowlist entry, a
  switch position. Everything here has a fuse. The approval TTL is 600 seconds,
  so a live card queued at the start of a phase run is dead long before anyone
  reaches the panel. Two hand checks have already been lost that way in one
  session. This runs LAST, right before the ping, and it prints the remaining
  window in minutes so the card can quote it.

  IT MUST ALSO RUN AFTER PHASE 4
  ------------------------------
  S.5 exercises the kill switch, and kill cancels every live request in the
  queue. A card staged before phase 4 would be destroyed by the test rather than
  by its timer, and the operator would arrive at an empty panel with no
  explanation. Order: stagebox, phase 4, phase 3, THEN this.

  THE EXPIRED CARD HAS A SECOND, QUIETER PRECONDITION
  ---------------------------------------------------
  handleList only returns an expired record whose expiry is LATER than
  lastViewedAt. So an expired card is invisible to anyone who opened the
  Approvals panel after it lapsed. Nothing here calls mark-viewed, and the box
  is handed over with the panel never yet opened, so `since` is 0 and the record
  is visible. If that stops being true the check silently has no subject, which
  is exactly the shape worth writing down.
#>
param(
    [string]$Transcript = 'C:\cfv\stagecards-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'v1.4.0 release gate: stage the timed approval subjects' `
    -Transcript $Transcript -Sentinel 'STAGECARDS_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'SC.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; W 'STAGECARDS_PROBE_COMPLETE rc=2'; exit 2 }

Section '1. One EXPIRED card, forced past its window from the root-owned record'
$exp = Invoke-WslFile -Tag 'sc-expired' -User 'root' -Body @'
O=$(su -s /bin/bash -c 'printf "This request was deliberately allowed to lapse, so the expired-card control has a subject.\n" > /tmp/expired-body.txt; clawfactory-send --to lapsed@example.invalid --subject "MANUAL-EXPIRED-CARD" --body-file /tmp/expired-body.txt' clawuser 2>&1)
echo "$O"
ID=$(printf '%s' "$O" | grep -oE 'requestId"?[[:space:]]*[:=][[:space:]]*"?[^"[:space:],}]+' | head -1 | sed -E 's/^.*[:=][[:space:]]*"?//')
echo "expired_id=$ID"
node -e 'const fs=require("fs");const p="/var/lib/clawfactory/send/pending/"+process.argv[1]+".json";try{const j=JSON.parse(fs.readFileSync(p,"utf8"));j.expiresAt=new Date(Date.now()-900000).toISOString();fs.writeFileSync(p,JSON.stringify(j));console.log("expiry forced to 15 minutes ago");}catch(e){console.log("could not force expiry: "+e.message);}' "$ID"
echo '--- touch the record through the broker so the state transition is stamped ---'
node /usr/local/sbin/clawfactory-sendctl.js approve "$ID" deadbeef 2>&1 | head -3
echo '--- does the broker now REPORT it as expired? ---'
node /usr/local/sbin/clawfactory-sendctl.js list 2>/dev/null | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);
console.log("EXPIRED_COUNT="+((j.expired||[]).length));
for(const e of (j.expired||[])) console.log("  EXPIRED_SUBJECT="+e.subject);
console.log("LAST_VIEWED_AT="+j.lastViewedAt);
}catch(e){console.log("LIST_PARSE_FAILED "+e.message)}});'
'@
W $exp.Out
$expCount = if ($exp.Out -match 'EXPIRED_COUNT=(\d+)') { [int]$Matches[1] } else { -1 }
$expSubj  = $exp.Out -match 'EXPIRED_SUBJECT=MANUAL-EXPIRED-CARD'
$neverViewed = $exp.Out -match 'LAST_VIEWED_AT=(null|)$' -or $exp.Out -match 'LAST_VIEWED_AT=null'
# VERDICT TRIAGE. -1 means the broker's list was never parsed, so nothing was
# measured about what the panel will show: VOID. A parsed list that does not
# carry the card means the subject is not there to be checked, which makes the
# hand check unrunnable rather than failed, so it is also reported as the
# staging failing rather than as a product verdict.
Record 'SC.1' 'An expired approval card exists AND the broker reports it in the expired list' `
    $(if ($expCount -lt 0) { 'VOID' } elseif ($expSubj) { 'PASS' } else { 'FAIL' }) `
    "expiredCount=$expCount carriesMANUAL-EXPIRED-CARD=$expSubj lastViewedAtIsNull=$neverViewed (a non-null lastViewedAt later than the lapse would hide it)"

Section '2. One LIVE pending card carrying an attachment, with the hash the panel must show'
$live = Invoke-WslFile -Tag 'sc-live' -User 'root' -Body @'
su -s /bin/bash -c 'printf "This message is staged for the by-hand panel checks. Nothing will be sent: the recipient domain cannot exist.\n" > /tmp/manual-body.txt; printf "These exact bytes were copied when the message was queued. The card should show their hash.\n" > /tmp/manual-attach.txt; clawfactory-send --to reviewer@example.invalid --subject "MANUAL-HASH-CHECK" --body-file /tmp/manual-body.txt --attach /tmp/manual-attach.txt' clawuser 2>&1 | tail -2
echo "SOURCE_ATTACH_SHA=$(sha256sum /tmp/manual-attach.txt | cut -d' ' -f1)"
echo '--- what the panel will now show, read from the broker ---'
node /usr/local/sbin/clawfactory-sendctl.js list 2>/dev/null | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);
for (const p of (j.pending||[])) {
  console.log("PENDING_SUBJECT="+p.subject);
  console.log("PENDING_TO="+JSON.stringify(p.to||p.recipients||[]));
  console.log("PENDING_EXPIRES="+p.expiresAt);
  const left=Math.round((Date.parse(p.expiresAt)-Date.now())/60000);
  console.log("PENDING_MINUTES_LEFT="+left);
  for (const a of (p.attachments||[])) console.log("PENDING_ATTACH="+a.name+" "+a.size+" B sha256="+a.sha256);
}
console.log("PENDING_COUNT="+((j.pending||[]).length));
}catch(e){console.log("LIST_PARSE_FAILED "+e.message)}});'
'@
W $live.Out
$srcSha  = if ($live.Out -match 'SOURCE_ATTACH_SHA=([a-f0-9]{64})') { $Matches[1] } else { '' }
$cardSha = if ($live.Out -match 'PENDING_ATTACH=\S+ \d+ B sha256=([a-f0-9]{64})') { $Matches[1] } else { '' }
$minsLeft = if ($live.Out -match 'PENDING_MINUTES_LEFT=(-?\d+)') { [int]$Matches[1] } else { -999 }
# The two hashes are compared HERE, so the value quoted in the handover card is
# one this script verified against the source bytes rather than one it copied
# out of the broker's own answer.
Record 'SC.2' 'A live pending card exists, and the hash the panel will show equals the source bytes' `
    $(if (-not $srcSha -or -not $cardSha) { 'VOID' } elseif ($srcSha -eq $cardSha) { 'PASS' } else { 'FAIL' }) `
    "sourceSha=$srcSha cardSha=$cardSha equal=$($srcSha -eq $cardSha) minutesLeft=$minsLeft"

Section '3. Independent confirmation that the SHIPPED Studio is the rebuilt 1.3.1'
# Check 6f asks the operator to read a version string off a page. That is worth
# having, because it is what a customer sees, but it is the weakest possible
# evidence about which payload actually landed: a stale bundle can render any
# string its author typed. The asar digest is the real identity, and it is
# compared here against the value the build pinned.
#
# NOTE ON THE PATH. The first version of this globbed for 'clawfactory-studio'
# and matched nothing, silently. Studio is a PER-USER NSIS app and installs to
# %LOCALAPPDATA%\Programs\ClawFactory Studio, WITH A SPACE, per
# resources/uninstall.ps1 step 4.5. A glob that matches nothing returns an empty
# string, which reads exactly like a missing file rather than a wrong path.
# ASK WINDOWS, NOT THE DISTRO. The first version of this globbed through
# /mnt/c and found nothing, which looked exactly like "Studio is not installed"
# and was in fact "the distro cannot see C:\ at all". Automount is OFF by design
# on this product, and /mnt/c exists as an EMPTY STUB, so a path test there is
# not a valid check for Windows visibility. Studio is a Windows program and the
# question is answered from Windows.
$asarPath = @(Get-ChildItem 'C:\Users' -Recurse -Filter 'app.asar' -ErrorAction SilentlyContinue -Force |
              Where-Object { $_.FullName -match 'ClawFactory Studio' } | Select-Object -First 1)
$asarSha = if ($asarPath.Count -gt 0) { (Get-FileHash $asarPath[0].FullName -Algorithm SHA256).Hash.ToLower() } else { '' }
foreach ($a in $asarPath) { W "ASAR_PATH=$($a.FullName) bytes=$($a.Length)" }
W "ASAR_SHA=$asarSha"
# CONTROL: the same search restricted to a name that cannot exist must find
# nothing, or a search that matches everything would read as a pass.
$asarCtl = @(Get-ChildItem 'C:\Users' -Recurse -Filter 'app.asar' -ErrorAction SilentlyContinue -Force |
             Where-Object { $_.FullName -match 'ClawFactory Studio NOT REAL' })
$asar = @{ Out = "CONTROL_FALSE_PATH_FOUND=$($asarCtl.Count)" }
W $asar.Out
$pinned  = '5c4ffbf420814939579f00f0b8e69e949ba34af20d239ddcdc6cf4da383e2d85'
$globSane = $asar.Out -match 'CONTROL_FALSE_PATH_FOUND=0'
# VERDICT TRIAGE. A glob that matches a path it must not match means the search
# is not discriminating, so a hit proves nothing: VOID. No asar at all means
# Studio is not installed where the product says it installs, which is a real
# finding and a FAIL. A digest that differs from the pin means the shipped
# payload is not the rebuilt 1.3.1, which is the exact drift the pin exists for.
Record 'SC.3' 'The installed Studio app.asar equals the digest this build pinned' `
    $(if (-not $globSane) { 'VOID' } elseif ($asarSha -eq $pinned) { 'PASS' } elseif (-not $asarSha) { 'FAIL' } else { 'FAIL' }) `
    "installedAsarSha=$(if ($asarSha) { $asarSha } else { 'NOT FOUND' }) pinnedAsarSha=$pinned equal=$($asarSha -eq $pinned) globDiscriminates=$globSane"

W ''
W '================ VALUES FOR THE HANDOVER CARD ================'
W "HANDOVER_STUDIO_ASAR=$asarSha"
W "HANDOVER_ATTACH_SHA256=$cardSha"
W "HANDOVER_MINUTES_LEFT=$minsLeft"
W "HANDOVER_STAGED_AT_UTC=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
W '=============================================================='

Complete-Phase -ResultsJson 'C:\cfv\stagecards-results.json' -MarkerPrefix 'STAGECARDS'
