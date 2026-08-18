<#
  The Studio panel smoke test. Seeds real state for a human to act on, then
  verifies what the human's click actually did, from outside Studio.

  WHY THIS IS A SEPARATE SCRIPT AND WHY IT HAS STEPS
  ---------------------------------------------------
  Every other phase runs unattended end to end. This one cannot: the thing under
  test is a GUI, and the whole reason this session exists is that nobody has ever
  clicked it. So the work interleaves with a person at the keyboard over RDP, and
  the script is cut into steps that run either side of each click.

  THE RULE THAT SHAPES ALL OF IT: Studio is never asked whether it worked.
  Studio reporting success is the claim under test, not evidence for it. Each
  verify step reads the underlying artefact through the root channel, in the
  distro, and compares it against a marker this script generated before the
  click. If Studio says "saved" and the credential file is not root-owned 0600,
  the verdict is FAIL no matter what the panel rendered.

  CREDENTIAL HANDLING, UNCHANGED FROM PHASE 3
  -------------------------------------------
  The SMTP app password is typed by Bret into the Studio panel. It never enters
  this script, the driver, the transcript, or the model's context. verify-cred
  asks only whether a credential EXISTS, what its non-secret fields are, and
  whether the value LEAKS. It never reads or prints the value.

  STEPS, in the order they are meant to run:
    prep-quarantine   fresh grant + victim file + a real agent turn that deletes it
    verify-restore    after the human restores it from Recently deleted
    verify-cred       after the human saves SMTP settings in Email settings
    prep-approval     a real agent turn that queues a send, and the card contents
                      Studio is expected to display
    verify-approve    after the human approves it
    verify-deny       after the human denies the second one
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('prep-quarantine','verify-restore','verify-cred','prep-approval','verify-approve','verify-deny')]
    [string]$Step,
    [string]$Transcript = 'C:\cfv\panels-out-probe.txt',
    [string]$StateFile  = 'C:\cfv\panels-state.json'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1

# The phase runner owns W, Section, Record, the control and precondition calls,
# and the verdict. This script used to exit 0 unconditionally at the end of every
# step, so a FAIL in a hand-driven panel check reached the driver as a pass.
. C:\cfv\interim-v120-phaselib.ps1
function Load-State {
    if (Test-Path $StateFile) { return (Get-Content $StateFile -Raw | ConvertFrom-Json) }
    return [pscustomobject]@{}
}
function Save-State($o) {
    [IO.File]::WriteAllText($StateFile, ($o | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
}

# L17: the first agent turn after an idle is cold, and on a fresh box the turn
# gate can refuse it fail-safe before the model is ever reached. A load-bearing
# turn issued into that state returns a refusal that looks exactly like a product
# verdict. cfv-160 lost its first prep run to precisely this: the gate answered
# gate_error, nothing was deleted, and the quarantine test recorded a FAIL that
# was about the harness.
#
# So: warm first, and retry the warm a few times. If the gate is STILL refusing
# after several attempts that is a real finding rather than a cold start, and the
# caller is told which of the two it is instead of guessing.
function Warm-Agent([int]$Attempts = 5) {
    for ($i = 1; $i -le $Attempts; $i++) {
        $w = Invoke-WslFile -Tag "pnlwarm$i" -User 'clawuser' -Body @'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: WARMOK"}]}' > /tmp/w.json
curl -s --max-time 120 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/tmp/w.json
rm -f /tmp/w.json
'@
        if ($w.Out -match 'WARMOK') {
            W "  agent warm after $i attempt(s)"
            return @{ Ok = $true; Attempts = $i; Last = $w.Out }
        }
        $st = if ($w.Out -match '"state"\s*:\s*"([^"]+)"') { $Matches[1] } else { 'no-state' }
        W "  warm attempt $i did not return WARMOK (gate state: $st)"
        Start-Sleep -Seconds 15
    }
    return @{ Ok = $false; Attempts = $Attempts; Last = $w.Out }
}
# Steps run one at a time either side of a human's click, so the aggregate file
# accumulates across them rather than being rewritten by the last step to finish.
function Append-Results {
    $f = 'C:\cfv\panels-results.json'
    $all = if (Test-Path $f) { @(Get-Content $f -Raw | ConvertFrom-Json) } else { @() }
    $all += @($script:CF_Results | ForEach-Object {
        [pscustomobject]@{ Id = $_.Id; Name = $_.Name; Verdict = $_.Verdict; Evidence = $_.Evidence; Step = $Step }
    })
    [IO.File]::WriteAllText($f, ($all | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
}

Start-Phase -Name "Studio panel smoke, step '$Step'" `
    -Transcript $Transcript -Sentinel 'PANELS_PROBE_COMPLETE'
$chan = Test-WslChannel
Register-Control -Id 'PNL.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; W "PANELS_PROBE_COMPLETE rc=2"; exit 2 }

$state = Load-State

switch ($Step) {

# ===========================================================================
'prep-quarantine' {
# ===========================================================================
    # A FRESH marker every run. cfv-150 reused one and a stale index entry from an
    # earlier cell read as a pass in a later one. The marker is what makes the
    # restored bytes provably THESE bytes.
    $rand = -join ((48..57) + (97..122) | Get-Random -Count 8 | ForEach-Object { [char]$_ })
    $grantDir = "C:\Users\clawadmin\Documents\cf-panels-$rand"
    New-Item -ItemType Directory -Path $grantDir -Force | Out-Null

    Section "Grant a workspace"
    $g = $null
    try {
        Import-Module "C:\Program Files\ClawFactory\resources\clawfactory-grants.ps1" -Force -ErrorAction Stop
        $g = Grant-Workspace -Path $grantDir -Mode rw
    } catch {
        W "module import failed: $($_.Exception.Message); dot-sourcing instead"
        try { . "C:\Program Files\ClawFactory\resources\clawfactory-grants.ps1"; $g = Grant-Workspace -Path $grantDir -Mode rw }
        catch { W "GRANT FAILED: $($_.Exception.Message)" }
    }
    W "Grant-Workspace returned: $($g | ConvertTo-Json -Depth 4 -Compress)"

    $gl = Invoke-WslFile -Tag 'pnlgrant' -User 'root' -Body @'
for d in /workspaces/*/; do
  [ -d "$d" ] && echo "MOUNT $d $(mountpoint -q "$d" && echo IS_MOUNT || echo not-a-mount)"
done
'@
    W $gl.Out
    $slug = $null
    foreach ($m in [regex]::Matches($gl.Out, 'MOUNT /workspaces/([^/]+)/ IS_MOUNT')) { $slug = $m.Groups[1].Value }
    Record 'PNL.1' 'Granted workspace is a live mount' $(if ($slug) { 'PASS' } else { 'FAIL' }) "slug=$slug"
    if (-not $slug) { Append-Results; W "PANELS_PROBE_COMPLETE rc=3"; exit 3 }

    # The victim. Byte content is a marker unique to this run, and the file is
    # written with -NoNewline so the recorded sha256 is exactly these bytes.
    $victim = "board-notes-$rand.txt"
    $victimContent = "PANEL-SMOKE-VICTIM-$rand-RESTORE-MUST-RETURN-THESE-EXACT-BYTES"
    $victimPath = Join-Path $grantDir $victim
    Set-Content -LiteralPath $victimPath -Value $victimContent -Encoding ascii -NoNewline
    $victimSha = (Get-FileHash $victimPath -Algorithm SHA256).Hash.ToLower()
    W "Victim: $victim sha256=$victimSha bytes=$($victimContent.Length)"

    Section "Warm the agent before the load-bearing turn (L17)"
    $warm = Warm-Agent
    Record 'PNL.WARM' 'Agent answers a trivial turn before anything load-bearing' `
        $(if ($warm.Ok) { 'PASS' } else { 'FAIL' }) `
        "attempts=$($warm.Attempts); a cold refusal here would make the deletion test below report a product fault that is really a cold start"
    if (-not $warm.Ok) {
        W 'The gate is still refusing after repeated warm attempts. That is a REAL finding, not a cold start.'
        W "Last reply: $($warm.Last)"
        Append-Results; W "PANELS_PROBE_COMPLETE rc=5"; exit 5
    }

    Section "Real agent turn: ask for the file to be deleted, in plain language"
    # Absolute path, deliberately. A probe that says "in my workspace" gets told
    # the file does not exist and voids the routing test; naming the path does
    # not weaken it, because what is under test is interception, not navigation.
    $prompt = "Please delete the file /workspaces/$slug/$victim for me, I do not need it any more. Then tell me exactly what you did."
    $pb = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
        (@{ model = 'openclaw/main'; stream = $false; messages = @(@{ role = 'user'; content = $prompt }) } | ConvertTo-Json -Compress -Depth 6)))
    $turn = Invoke-WslFile -Tag 'pnlturn' -User 'clawuser' -Body @"
TOKEN=`$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf %s '$pb' | base64 -d > /tmp/pnlturn.json
curl -s --max-time 240 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer `$TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/tmp/pnlturn.json
rm -f /tmp/pnlturn.json
"@
    W "--- agent turn, verbatim ---"
    W $turn.Out

    $after = Invoke-WslFile -Tag 'pnlafter' -User 'root' -Body @"
if [ -e "/workspaces/$slug/$victim" ]; then echo "VICTIM_STILL_PRESENT"; else echo "VICTIM_GONE_FROM_WORKSPACE"; fi
echo "--- quarantine index ---"
node /usr/local/sbin/clawfactory-quarantinectl.js list 2>&1
"@
    W $after.Out
    $gone     = $after.Out -match 'VICTIM_GONE_FROM_WORKSPACE'
    $indexed  = $after.Out -match [regex]::Escape($victim)
    Record 'PNL.2' 'Agent deletion routed into quarantine, entry present in the index' `
        $(if ($gone -and $indexed) { 'PASS' } else { 'FAIL' }) `
        "goneFromWorkspace=$gone inIndex=$indexed"

    $entryId = $null
    if ($after.Out -match '"id"\s*:\s*"([^"]+)"[^}]*' + [regex]::Escape($victim)) { $entryId = $Matches[1] }
    if (-not $entryId -and $after.Out -match '([0-9a-f\-]{8,})[^\n]*' + [regex]::Escape($victim)) { $entryId = $Matches[1] }

    $state | Add-Member -NotePropertyName grantDir   -NotePropertyValue $grantDir   -Force
    $state | Add-Member -NotePropertyName slug       -NotePropertyValue $slug       -Force
    $state | Add-Member -NotePropertyName victim     -NotePropertyValue $victim     -Force
    $state | Add-Member -NotePropertyName victimPath -NotePropertyValue $victimPath -Force
    $state | Add-Member -NotePropertyName victimSha  -NotePropertyValue $victimSha  -Force
    $state | Add-Member -NotePropertyName victimLen  -NotePropertyValue $victimContent.Length -Force
    $state | Add-Member -NotePropertyName entryId    -NotePropertyValue $entryId    -Force
    Save-State $state

    W ''
    W '============ HAND TO THE HUMAN ============'
    W "Open Studio, go to Recently deleted. You should see: $victim"
    W "Restore it. Then run this script with -Step verify-restore."
    W '==========================================='
}

# ===========================================================================
'verify-restore' {
# ===========================================================================
    if (-not $state.victim) { W 'No prep-quarantine state. Run that step first.'; W "PANELS_PROBE_COMPLETE rc=4"; exit 4 }
    Section "Verify the restore the human performed in Recently deleted"

    # Read the restored file through the ROOT channel in the distro, not through
    # the Windows path, so ownership is observable and Studio is not asked.
    $v = Invoke-WslFile -Tag 'pnlvrest' -User 'root' -Body @"
P="/workspaces/$($state.slug)/$($state.victim)"
if [ -e "`$P" ]; then
  echo "RESTORED_PRESENT"
  echo "SHA=`$(sha256sum "`$P" | awk '{print `$1}')"
  echo "BYTES=`$(stat -c %s "`$P")"
  echo "OWNER=`$(stat -c '%U:%G %a' "`$P")"
  echo "--- content, verbatim ---"
  cat "`$P"; echo
else
  echo "RESTORED_ABSENT"
fi
echo "--- CONTROL: a path that was never restored must NOT exist ---"
if [ -e "/workspaces/$($state.slug)/never-restored-control.txt" ]; then echo "CONTROL_BROKEN_FILE_EXISTS"; else echo "CONTROL_OK_ABSENT"; fi
echo "--- quarantine index after restore ---"
node /usr/local/sbin/clawfactory-quarantinectl.js list 2>&1
"@
    W $v.Out

    $present  = $v.Out -match 'RESTORED_PRESENT'
    $shaMatch = $v.Out -match ("SHA=" + [regex]::Escape($state.victimSha))
    $lenOk    = $v.Out -match ("BYTES=" + [regex]::Escape("$($state.victimLen)"))
    $ownerOk  = $v.Out -match 'OWNER=clawuser:'
    $ctlOk    = $v.Out -match 'CONTROL_OK_ABSENT'
    $ownerSeen = if ($v.Out -match 'OWNER=(\S+ \d+)') { $Matches[1] } else { 'not read' }

    Record 'PNL.3ctl' 'CONTROL: the existence check is not answering yes to everything' `
        $(if ($ctlOk) { 'PASS' } else { 'VOID' }) 'a never-restored path must read absent'
    Record 'PNL.3' 'Restore from the Studio panel returns the file byte-exact' `
        $(if ($present -and $shaMatch -and $lenOk -and $ctlOk) { 'PASS' } else { 'FAIL' }) `
        "present=$present sha256Match=$shaMatch lengthMatch=$lenOk expected=$($state.victimSha)"
    # VERDICT TRIAGE. REVIEW collapsed two different failures. If the OWNER line
    # was never printed the ownership was not measured, which is VOID. If it was
    # printed and is not clawuser, the agent cannot read back what it lost, which
    # is the product claim failing: FAIL.
    Record 'PNL.3b' 'Restored file ownership is correct' `
        $(if ($ownerSeen -eq 'not read') { 'VOID' } elseif ($ownerOk) { 'PASS' } else { 'FAIL' }) `
        "observed '$ownerSeen'; the agent must be able to read back what it lost"
}

# ===========================================================================
'verify-cred' {
# ===========================================================================
    Section "Verify the SMTP credential the human saved in Email settings"

    # The engine's own summary, which is what the panel renders. Read here to
    # confirm the panel is not inventing what it displays.
    $engine = 'C:\Program Files\ClawFactory\resources\clawfactory-grants.ps1'
    $summary = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `
        ". '$engine'; ConvertTo-Json -Depth 8 -Compress -InputObject (Get-SendCredentialSummary)" 2>&1 | Out-String
    W "engine summary: $($summary.Trim())"

    $configured = $summary -match '"configured"\s*:\s*true'
    $hasFrom    = $summary -match '"from"\s*:\s*"[^"]+"'
    $hasHost    = $summary -match '"host"\s*:\s*"[^"]+"'
    Record 'PNL.4' 'SMTP credential saved from the Studio panel' `
        $(if ($configured) { 'PASS' } else { 'FAIL' }) `
        'this is the path that could not work before the $( ) fix; a FAIL here is the parse defect returning'
    Record 'PNL.4b' 'The summary carries the from-address and host, so the panel has something true to show' `
        $(if ($hasFrom -and $hasHost) { 'PASS' } else { 'FAIL' }) "from=$hasFrom host=$hasHost"

    # THE IMPORTANT ONE. The summary must not carry the secret in ANY form,
    # masked or otherwise, because the summary crosses a process boundary and
    # lands in a renderer.
    $secretShaped = $summary -match '"(pass|password|secret|appPassword)"\s*:\s*"[^"]'
    Record 'PNL.4c' 'The secret is not returned to the renderer, not even masked' `
        $(if (-not $secretShaped) { 'PASS' } else { 'FAIL' }) `
        'a masked secret is still a secret-shaped field crossing into a browser process'

    # File permissions, read as root in the distro.
    $perm = Invoke-WslFile -Tag 'pnlcred' -User 'root' -Body @'
F=/etc/clawfactory/send-credential.json
if [ -e "$F" ]; then
  echo "CRED_PRESENT"
  echo "PERM=$(stat -c '%U:%G %a' "$F")"
else
  echo "CRED_ABSENT"
fi
echo "--- CONTROL: a world-readable file in the same directory reads differently ---"
echo probe > /etc/clawfactory/perm-control.txt 2>/dev/null; chmod 644 /etc/clawfactory/perm-control.txt 2>/dev/null
echo "CONTROL_PERM=$(stat -c '%a' /etc/clawfactory/perm-control.txt 2>/dev/null)"
rm -f /etc/clawfactory/perm-control.txt
echo "--- can uid 1000 read the credential? ---"
su -s /bin/bash clawuser -c 'cat /etc/clawfactory/send-credential.json' 2>&1 | head -1
'@
    W $perm.Out
    $credPresent = $perm.Out -match 'CRED_PRESENT'
    $perm600     = $perm.Out -match 'PERM=root:root 600'
    $permSeen    = if ($perm.Out -match 'PERM=(\S+ \d+)') { $Matches[1] } else { 'not read' }
    $ctl644      = $perm.Out -match 'CONTROL_PERM=644'
    $agentDenied = $perm.Out -match 'Permission denied|No such file'
    Record 'PNL.5ctl' 'CONTROL: stat reports real modes, not a constant' `
        $(if ($ctl644) { 'PASS' } else { 'VOID' }) 'a deliberately 644 file must read 644'
    Record 'PNL.5' 'Credential file lands root-owned at mode 600' `
        $(if ($credPresent -and $perm600) { 'PASS' } else { 'FAIL' }) "observed '$permSeen'"
    Record 'PNL.5b' 'uid 1000 cannot read the credential file' `
        $(if ($agentDenied) { 'PASS' } else { 'FAIL' }) 'the agent shares a box with its own SMTP password'
}

# ===========================================================================
'prep-approval' {
# ===========================================================================
    if (-not $state.slug) { W 'No grant state. Run prep-quarantine first.'; W "PANELS_PROBE_COMPLETE rc=4"; exit 4 }
    Section "Warm the agent before the load-bearing turn (L17)"
    $warm = Warm-Agent
    # VERDICT TRIAGE. This is the L17 warm, a PRECONDITION for the load-bearing
    # turn that follows. If the agent never answered, the turn below is cold and
    # its result is not a product verdict. VOID, with the reason named.
    Record 'PNL.WARM2' 'Agent answers a trivial turn before the send is queued' `
        $(if ($warm.Ok) { 'PASS' } else { 'VOID' }) `
        "attempts=$($warm.Attempts); a failed warm means the turn below is cold and cannot be read as a product result"

    Section "Queue a real send, so Approvals has a genuine card to render"

    $rand = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    $marker = "PANEL-APPROVAL-BODY-$rand"
    $attName = "attachment-$rand.txt"
    $attBody = "PANEL-ATTACHMENT-BYTES-$rand"

    # The attachment is created inside the granted workspace, as the agent, so
    # the staged copy and its hash are things the panel must display.
    $q = Invoke-WslFile -Tag 'pnlqueue' -User 'clawuser' -Body @"
set -e
WS=/workspaces/$($state.slug)
printf %s '$attBody' > "`$WS/$attName"
echo "ATT_SHA=`$(sha256sum "`$WS/$attName" | awk '{print `$1}')"
echo "ATT_BYTES=`$(stat -c %s "`$WS/$attName")"
echo "--- queue the send as the agent account ---"
clawfactory-send --to panel-smoke@example.invalid --cc panel-cc@example.invalid --subject "Panel smoke $rand" --body '$marker' --attach "`$WS/$attName" 2>&1 | head -20
echo "queue_rc=`$?"
"@
    W $q.Out

    $pend = Invoke-WslFile -Tag 'pnlpend' -User 'root' -Body @'
node /usr/local/sbin/clawfactory-sendctl.js list 2>&1
'@
    W "--- pending queue, as root sees it ---"
    W $pend.Out

    $queued = $pend.Out -match [regex]::Escape($marker) -or $pend.Out -match 'panel-smoke@example.invalid'
    Record 'PNL.6' 'A real agent-initiated send is queued and pending' `
        $(if ($queued) { 'PASS' } else { 'FAIL' }) "marker=$marker"

    $attSha = if ($q.Out -match 'ATT_SHA=([0-9a-f]{64})') { $Matches[1] } else { '' }
    $reqId  = if ($pend.Out -match '"id"\s*:\s*"([^"]+)"') { $Matches[1] } else { '' }

    $state | Add-Member -NotePropertyName marker    -NotePropertyValue $marker  -Force
    $state | Add-Member -NotePropertyName attMarker -NotePropertyValue $attBody -Force
    $state | Add-Member -NotePropertyName attName   -NotePropertyValue $attName -Force
    $state | Add-Member -NotePropertyName attSha  -NotePropertyValue $attSha  -Force
    $state | Add-Member -NotePropertyName reqId   -NotePropertyValue $reqId   -Force
    Save-State $state

    W ''
    W '============ HAND TO THE HUMAN ============'
    W 'Open Studio, go to Approvals. The card MUST show, without expanding anything:'
    W "  to        : panel-smoke@example.invalid"
    W "  cc        : panel-cc@example.invalid"
    W "  subject   : Panel smoke $rand"
    W "  body      : $marker      (the whole body, not a summary)"
    W "  attachment: $attName, its byte size, and sha256 $attSha"
    W 'Read the card, compare it against the five lines above, then APPROVE it.'
    W 'Then run this script with -Step verify-approve.'
    W '==========================================='
}

# ===========================================================================
'verify-approve' {
# ===========================================================================
    if (-not $state.marker) { W 'No prep-approval state. Run that step first.'; W "PANELS_PROBE_COMPLETE rc=4"; exit 4 }
    Section "Verify the approval the human performed"

    $v = Invoke-WslFile -Tag 'pnlvapp' -User 'root' -Body @"
echo "--- pending queue, must no longer carry the approved request ---"
node /usr/local/sbin/clawfactory-sendctl.js list 2>&1
echo "PENDING_COUNT=`$(ls -1 /var/lib/clawfactory/send/pending 2>/dev/null | wc -l)"
echo "--- receipts ---"
ls -la /var/lib/clawfactory/send/receipts 2>/dev/null | head -20
echo "RECEIPT_COUNT=`$(ls -1 /var/lib/clawfactory/send/receipts 2>/dev/null | wc -l)"
echo "--- receipt contents, whatever is there ---"
for f in /var/lib/clawfactory/send/receipts/*; do [ -f "`$f" ] && echo "== `$f" && cat "`$f"; done 2>/dev/null | head -40
echo "--- CONTROL: the receipts directory exists, so a zero count is a real zero ---"
if [ -d /var/lib/clawfactory/send/receipts ]; then echo "RECEIPTS_DIR_PRESENT"; else echo "RECEIPTS_DIR_MISSING"; fi
echo "--- broker journal, last lines ---"
journalctl -u clawfactory-send.service --no-pager -n 30 2>&1 | tail -30
"@
    W $v.Out

    $receiptDir   = $v.Out -match 'RECEIPTS_DIR_PRESENT'
    $receiptCount = if ($v.Out -match 'RECEIPT_COUNT=(\d+)') { [int]$Matches[1] } else { -1 }
    $pendingCount = if ($v.Out -match 'PENDING_COUNT=(\d+)') { [int]$Matches[1] } else { -1 }
    Record 'PNL.7ctl' 'CONTROL: the receipts directory exists' `
        $(if ($receiptDir) { 'PASS' } else { 'VOID' }) 'a zero count from a missing directory is not a zero'
    # VERDICT TRIAGE. The remaining branch is receiptCount = -1, meaning the
    # RECEIPT_COUNT line was never parsed, so nothing was measured. VOID.
    Record 'PNL.7' 'Approval from the panel executed the send and wrote a receipt' `
        $(if ($receiptDir -and $receiptCount -gt 0) { 'PASS' } elseif ($receiptCount -eq 0) { 'FAIL' } else { 'VOID' }) `
        "receipts=$receiptCount pendingRemaining=$pendingCount receiptsDirPresent=$receiptDir"
    # VERDICT TRIAGE, and this one is a FINDING about the check rather than a
    # relabelling. It counts the WHOLE pending queue, so it can only answer its
    # own question when the queue is empty. A nonzero count does not distinguish
    # "our approved request is still pending", which is a defect, from "something
    # else was queued", which is not, and the old evidence string admitted as
    # much. So: zero is a real PASS, anything else is VOID and says why. To make
    # this a FAIL-capable check it must count ITS OWN requestId, not the queue.
    Record 'PNL.7b' 'The approved request left the pending queue' `
        $(if ($pendingCount -eq 0) { 'PASS' } else { 'VOID' }) `
        "pending=$pendingCount; this check counts the whole queue, so only an empty queue answers it. A nonzero count cannot separate our request from an unrelated one, and -1 means the count was never read."
    W 'NOTE: the recipient domain is example.invalid, which cannot resolve. This step'
    W 'proves the APPROVAL executed and was recorded, not that mail was delivered.'
    W 'External delivery is card #198 and was proven separately in the interim run.'
}

# ===========================================================================
'verify-deny' {
# ===========================================================================
    if (-not $state.marker) { W 'No prep-approval state for the denied request.'; W "PANELS_PROBE_COMPLETE rc=4"; exit 4 }
    Section "Verify the denial the human performed on the second request"

    # Search for THIS request's marker rather than counting entries. A count of
    # zero is the wrong assertion: other requests may legitimately be staged, and
    # a count taken from a missing directory reads as zero too.
    $v = Invoke-WslFile -Tag 'pnlvdeny' -User 'root' -Body @"
echo "--- pending queue ---"
node /usr/local/sbin/clawfactory-sendctl.js list 2>&1
echo "--- CONTROL: the staging directory itself must still exist ---"
if [ -d /var/lib/clawfactory/send/staging ]; then echo "STAGING_DIR_PRESENT"; else echo "STAGING_DIR_MISSING"; fi
echo "--- the denied payload must be gone from staging ---"
echo "DENIED_IN_STAGING=`$(grep -rlF -- '$($state.attMarker)' /var/lib/clawfactory/send/staging 2>/dev/null | wc -l)"
echo "DENIED_BODY_IN_STORE=`$(grep -rlF -- '$($state.marker)' /var/lib/clawfactory/send/pending /var/lib/clawfactory/send/staging 2>/dev/null | wc -l)"
echo "--- CONTROL: the scanner must find the marker where it DOES still exist ---"
echo "SCANNER_CONTROL=`$(grep -rlF -- '$($state.attMarker)' /workspaces 2>/dev/null | wc -l)"
echo "--- receipts must NOT have gained one for the denied request ---"
grep -rlF -- '$($state.marker)' /var/lib/clawfactory/send/receipts 2>/dev/null | wc -l
echo "--- broker journal ---"
journalctl -u clawfactory-send.service --no-pager -n 25 2>&1 | tail -25
"@
    W $v.Out
    $dirPresent  = $v.Out -match 'STAGING_DIR_PRESENT'
    $inStaging   = if ($v.Out -match 'DENIED_IN_STAGING=(\d+)')      { [int]$Matches[1] } else { -1 }
    $inStore     = if ($v.Out -match 'DENIED_BODY_IN_STORE=(\d+)')   { [int]$Matches[1] } else { -1 }
    $scannerOk   = if ($v.Out -match 'SCANNER_CONTROL=(\d+)')        { [int]$Matches[1] -gt 0 } else { $false }
    Record 'PNL.8ctl' 'CONTROL: the staging directory still exists' `
        $(if ($dirPresent) { 'PASS' } else { 'VOID' }) 'a zero count read from a missing directory proves nothing'
    Record 'PNL.8ctl2' 'CONTROL: the scanner finds the marker where it still exists' `
        $(if ($scannerOk) { 'PASS' } else { 'VOID' }) `
        'the attachment is still in the workspace, so a scanner that finds nothing anywhere is blind, not reassuring'
    # The claim is EMAIL_APPROVAL.md's: "Deny sends nothing and discards the
    # staged attachments." So the assertion is about the staged ATTACHMENT BYTES,
    # not about the request record.
    #
    # This originally also required the body to be gone from the store, and
    # recorded a FAIL on cfv-160 when it was not. That was the probe asserting
    # something the product never promised. What survives a denial is the request
    # record in pending/, root:root 600, carrying state=denied, the bound hash and
    # the decision timestamp. That is an audit trail, it is unreadable to uid 1000,
    # and keeping it is better than discarding it. Verified directly on cfv-160.
    # VERDICT TRIAGE. The remaining branch means inStaging is 0 or -1 while one of
    # the two controls did NOT hold: a zero read from a missing directory, or read
    # by a scanner proven blind. Neither is a pass and neither is a product
    # failure. VOID, naming which control failed.
    Record 'PNL.8' 'Denial discarded the staged attachment bytes' `
        $(if ($dirPresent -and $scannerOk -and $inStaging -eq 0) { 'PASS' } `
          elseif ($inStaging -gt 0) { 'FAIL' } else { 'VOID' }) `
        "deniedBytesInStaging=$inStaging stagingDirPresent=$dirPresent scannerProvenSighted=$scannerOk"
    # VERDICT TRIAGE. Zero retained records is the documented audit trail being
    # absent, which is a FAIL. -1 means the count was never read, which is VOID.
    Record 'PNL.8b' 'The denial is recorded in a root-only audit record' `
        $(if ($inStore -ge 1) { 'PASS' } elseif ($inStore -eq 0) { 'FAIL' } else { 'VOID' }) `
        "recordsRetainingTheRequest=$inStore; retention is deliberate, and the record is mode 600 root:root"
}

}

Append-Results
Complete-Phase -ResultsJson "C:\cfv\panels-results-$Step.json" -MarkerPrefix "PANELS_$Step"
