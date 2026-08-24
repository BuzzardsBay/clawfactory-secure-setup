<#
  Configure the box from the ROOT tooling, so the operator is handed a machine
  that is already set up rather than a setup task.

  WHY THIS EXISTS
  ---------------
  The previous session handed over a box on which Studio was not configured, so
  the operator redid work that had already been done on earlier boxes, and one
  step (the SMTP credential) was put on their list without anyone first checking
  what it bought. It bought two rows. Everything else the panels display can be
  written by a root-owned tool that ships with the product.

  WHAT IS SET, AND BY WHICH TOOL
  ------------------------------
    SMTP sink credential + authorised send destination
        clawfactory-sendctl credential-set, JSON on STDIN. The broker writes the
        credential AND calls setSendDestination in the same operation, so the
        credential and the policy cannot drift apart. One call sets both.
    read-fetch destination
        clawfactory-fetchctl add. Seeded so the Web access panel has an entry
        that was PERSISTED and is rendered at load, which is a different thing
        from one the panel just added in the same session.
    toolchain switch
        clawfactory-fetchctl toolchain on. Set explicitly and read back, rather
        than relied on as a default, so the position stated in the handover card
        is a measurement.

  THE CREDENTIAL IS DELIBERATELY SYNTHETIC AND DELIBERATELY DETECTABLE
  --------------------------------------------------------------------
  It points at 127.0.0.1, which is where phase 3 stands up its local sink. That
  clears every row whose blocker was "no credential file exists": the file-mode
  and unreadable-by-the-agent rows, and the whole approve-to-receipt mechanism.

  It does NOT clear the leak scans, and this script exists partly to make sure
  nobody thinks it does. Scanning the box for a password I invented five seconds
  ago and finding no copies of it says nothing about whether the product leaks a
  real credential. The probes have been taught to recognise this credential by
  its loopback host and record those rows VOID with that reason, which is the
  honest verdict and is what they already did when no credential existed at all.

  The sentinel below is not a secret. It is a marker chosen to be unmistakable in
  any transcript it turns up in.
#>
param(
    [string]$Transcript = 'C:\cfv\stagebox-out-probe.txt',
    [string]$SeedHost   = 'www.iana.org'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'v1.4.0 release gate: configure the box from the root tooling' `
    -Transcript $Transcript -Sentinel 'STAGEBOX_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'SB.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; W 'STAGEBOX_PROBE_COMPLETE rc=2'; exit 2 }

# --------------------------------------------------------- 1. SMTP credential
Section '1. SMTP sink credential and the authorised send destination, both from root'
$cred = Invoke-WslFile -Tag 'sb-cred' -User 'root' -Body @'
echo '--- BEFORE ---'
node /usr/local/sbin/clawfactory-sendctl.js credential-summary 2>&1
node -e 'const p=require("/etc/clawfactory/egress-policy.json");console.log("SEND_ACTIONS_BEFORE="+JSON.stringify(p.send_actions||[]))' 2>&1
echo '--- SET (JSON on STDIN, never on argv) ---'
printf '%s' '{"host":"127.0.0.1","port":2525,"username":"clawfactory-validation","password":"CFV-SYNTHETIC-SINK-NOT-A-SECRET-2026","from":"clawfactory-validation@example.invalid"}' \
  | node /usr/local/sbin/clawfactory-sendctl.js credential-set 2>&1
echo "set_rc=$?"
echo '--- AFTER: what the panel will read ---'
node /usr/local/sbin/clawfactory-sendctl.js credential-summary 2>&1
node -e 'const p=require("/etc/clawfactory/egress-policy.json");console.log("SEND_ACTIONS_AFTER="+JSON.stringify(p.send_actions||[]))' 2>&1
echo '--- the credential file as it actually is on disk, MEASURED not asserted ---'
stat -c 'CRED_STAT %n mode=%a owner=%U:%G' /etc/clawfactory/send-credential.json 2>&1
'@
W $cred.Out
$credOk = ($cred.Out -match '"configured"\s*:\s*true') -or ($cred.Out -match 'configured.*true')
$destOk = $cred.Out -match 'SEND_ACTIONS_AFTER=.*"host":"127\.0\.0\.1".*"port":2525'
$modeOk = $cred.Out -match 'CRED_STAT /etc/clawfactory/send-credential\.json mode=600 owner=root:root'
Record 'SB.1' 'SMTP sink credential written by the root tool, and the destination authorised with it' `
    $(if ($credOk -and $destOk) { 'PASS' } else { 'FAIL' }) `
    "credentialConfigured=$credOk sendDestinationAuthorised=$destOk"
# Reports what it MEASURED. The old S.4 evidence field printed '0600 root:root'
# as a literal regardless of the box, which is a probe printing the answer you
# wanted rather than the answer it found.
Record 'SB.1b' 'The credential file is mode 600 root:root as measured on the box' `
    $(if ($modeOk) { 'PASS' } else { 'FAIL' }) `
    ((($cred.Out -split "`n") | Where-Object { $_ -match 'CRED_STAT' } | Select-Object -First 1) -replace '^\s+','')

# ------------------------------------------------------ 2. read-fetch seeding
Section "2. One persisted read-fetch destination, so the panel renders a stored entry at load"
$fetch = Invoke-WslFile -Tag 'sb-fetch' -User 'root' -Body @"
echo '--- BEFORE ---'
/usr/local/sbin/clawfactory-fetchctl list 2>&1
echo '--- ADD $SeedHost ---'
/usr/local/sbin/clawfactory-fetchctl add $SeedHost 2>&1
echo "add_rc=`$?"
echo '--- AFTER ---'
/usr/local/sbin/clawfactory-fetchctl list 2>&1
"@
W $fetch.Out
$seeded = $fetch.Out -match ([regex]::Escape($SeedHost))
Record 'SB.2' "Read-fetch allowlist carries the seeded destination $SeedHost" `
    $(if ($seeded) { 'PASS' } else { 'FAIL' }) `
    "the panel now has a persisted entry to render at load, which a same-session add does not prove"

# --------------------------------------------------------- 3. toolchain switch
Section '3. Toolchain switch set explicitly ON and read back'
$tc = Invoke-WslFile -Tag 'sb-tc' -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl toolchain on 2>&1
echo "toolchain_rc=$?"
echo '--- READ BACK, which is the value the panel shows ---'
/usr/local/sbin/clawfactory-fetchctl list 2>&1 | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const j=JSON.parse(s);
    console.log("TOOLCHAIN_ENABLED="+(j.toolchain&&j.toolchain.enabled));
    console.log("TOOLCHAIN_ADDRESSES="+(j.toolchain&&j.toolchain.live&&j.toolchain.live.addresses));
    console.log("READ_FETCH_COUNT="+((j.allow||[]).length));
    console.log("READ_FETCH_HOSTS="+((j.allow||[]).map(x=>x.host).join(",")));
  }catch(e){console.log("PARSE_FAILED "+e.message);console.log(s.slice(0,400));}
});'
'@
W $tc.Out
$tcOn = $tc.Out -match 'TOOLCHAIN_ENABLED=true'
$tcAddr = if ($tc.Out -match 'TOOLCHAIN_ADDRESSES=(\d+)') { [int]$Matches[1] } else { -1 }
# VERDICT TRIAGE. -1 means the value was never parsed, so the switch position was
# not measured and the handover card would be quoting a guess: VOID.
Record 'SB.3' 'Toolchain switch reads ON, with a nonzero live address count' `
    $(if ($tcAddr -lt 0) { 'VOID' } elseif ($tcOn -and $tcAddr -gt 0) { 'PASS' } else { 'FAIL' }) `
    "enabled=$tcOn liveAddresses=$tcAddr (the panel line reads 'On. $tcAddr network addresses reachable.')"

# ------------------------------------------------- 4. what the card must state
Section '4. The exact state to quote in the handover card'
$state = Invoke-WslFile -Tag 'sb-state' -User 'root' -Body @'
echo "CARD_TOOLCHAIN=$(/usr/local/sbin/clawfactory-fetchctl list 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);process.stdout.write((j.toolchain&&j.toolchain.enabled?"ON":"OFF")+" addresses="+(j.toolchain&&j.toolchain.live?j.toolchain.live.addresses:"?"))})')"
echo "CARD_READFETCH=$(/usr/local/sbin/clawfactory-fetchctl list 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);process.stdout.write(((j.allow||[]).map(x=>x.host).join(",")||"(empty)"))})')"
echo "CARD_SMTP=$(node /usr/local/sbin/clawfactory-sendctl.js credential-summary 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const c=j.credential||{};process.stdout.write((c.configured?("configured "+c.host+":"+c.port+" as "+c.username):"NOT CONFIGURED"))}catch(e){process.stdout.write("unreadable")}})')"
echo "CARD_STUDIO_ASAR=$(sha256sum /mnt/c/Users/*/AppData/Local/Programs/clawfactory-studio/resources/app.asar 2>/dev/null | head -1 | cut -d' ' -f1)"
'@
W $state.Out
foreach ($line in ($state.Out -split "`n")) { if ($line -match '^CARD_') { W "HANDOVER $line" } }
Record 'SB.4' 'Box state read back for the handover card' `
    $(if ($state.Out -match 'CARD_TOOLCHAIN=ON') { 'PASS' } else { 'FAIL' }) `
    'the card quotes measurements from this block rather than intentions from this script'

Complete-Phase -ResultsJson 'C:\cfv\stagebox-results.json' -MarkerPrefix 'STAGEBOX'
