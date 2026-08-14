<#
  Stage a LIVE approval card carrying an attachment, for the by-hand checks.

  Needed because the suite's own live control is short-lived by construction:
  it is queued after a wait that is longer than the approval TTL, so by the time
  a human reaches the panel it has expired, and an expired card deliberately
  renders no attachments. The hash-reveal control therefore has nothing to act
  on unless a fresh request is queued close to when the panel is opened.

  Queues one request with a real attachment, and reports what the panel should
  now be showing so the operator knows what they are looking for.
#>
param([string]$Transcript = 'C:\cfv\stage-manual-out.txt')

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1

function W([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line; $line | Out-File $Transcript -Encoding utf8 -Append
}

$r = Invoke-WslFile -Tag 'stage-manual' -User 'root' -Body @'
su -s /bin/bash -c 'printf "This message is staged for the by-hand panel checks. Nothing will be sent: the recipient domain cannot exist.\n" > /tmp/manual-body.txt; printf "These exact bytes were copied when the message was queued. The card should show their hash.\n" > /tmp/manual-attach.txt; clawfactory-send --to reviewer@example.invalid --subject "MANUAL-HASH-CHECK" --body-file /tmp/manual-body.txt --attach /tmp/manual-attach.txt' clawuser 2>&1 | tail -2
echo '--- what the panel should now show ---'
/usr/local/sbin/clawfactory-sendctl list | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);
console.log("PENDING:");
for (const p of (j.pending||[])) {
  console.log("  " + p.subject + "  expiresAt=" + p.expiresAt);
  for (const a of (p.attachments||[])) console.log("    attachment " + a.name + "  " + a.size + " B  sha256=" + a.sha256);
}
console.log("EXPIRED (should include EXPIRY-A, and NOT EXPIRY-B which the suite dismissed):");
for (const e of (j.expired||[])) console.log("  " + e.subject + "  state=" + e.state);
});'
'@
W $r.Out
W 'STAGE_MANUAL_COMPLETE rc=0'
exit 0
