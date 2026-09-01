<#
  cfv-harness-proof.ps1 -- TASK 5. Prove the harness against a broken run.

  This is the task card #259 exists for. A harness that has only been seen to work
  on a run that succeeded is unmeasured, and the last three cycles show the harness
  fails more often than the product does.

  IT MEASURES NO PRODUCT ROW AND MUST NEVER REPORT ONE. The subject is the
  transport. Nothing here installs ClawFactory, reads an install.log for a verdict,
  or touches a shipped file.

  WHY THE BAKED IMAGE, NAMED IN THE RUN PLAN AS THE BASELINE CLAUSE REQUIRES
  --------------------------------------------------------------------------
  clawfactory-win11-baseline-v2. The clause requiring at least one stock box per
  cycle exists so that install steps an image has already performed are still
  measured. No install step is measured here at all. The baked image is chosen
  because it carries the WSL engine (2.7.8 by MSI), which is the precondition for
  the S4U/WSL question, and a stock box would spend fifteen minutes installing WSL
  for no reason connected to this job.

  ROWS THIS BOX CANNOT ANSWER: none, because no product row is asked.

  NO RDP RULE IS CREATED. Deliberately.
  -------------------------------------
  The job's own instruction is that the failure path must not need the operator.
  An RDP rule opened "just in case" is the safety net that let three cycles paper
  over the fact that the harness could not restart itself. If the mechanism fails,
  the evidence is collected through az -- which is independent of RDP -- and
  reported. Needing RDP would itself be the finding.

  ORDER IS LOAD-BEARING:

    stage     push the runner + the arming script onto the box   nothing measured
    ctl       CONTROL: wsl.exe under SYSTEM must FAIL by name    without this an
                                                                 S4U success proves
                                                                 nothing
    arm       register the S4U boot task, read every field back  TASK 1.1/1.2
    probe1    a 3-minute job; the heartbeat must beat THROUGHOUT TASK 4.1
    wslctx    read _wslcontext.json                              TASK 1.3
    reboot1   restart; the runner must come back with NO login   TASK 1.3
    probe2    a job on the far side of reboot 1                  proves it works,
                                                                 not merely that a
                                                                 process exists
    reboot2   restart AGAIN, consecutively                       TASK 1.2's "at
                                                                 least two"
    probe3    a job on the far side of reboot 2
    limit     measure where run-command actually truncates       TASK 4.2
    breakit   the deliberate breaks that need a real box         TASK 5.2
    fetch     retrieve every transcript, bounded and asserted
    teardown  NIC first, unfiltered residual                     the ledger
#>
param(
    [string]$Vm = 'cfv-192',
    [string]$Rg = 'clawfactory-validation',
    [Parameter(Mandatory)]
    [ValidateSet('stage','ctl','arm','probe1','wslctx','reboot1','probe2','reboot2','probe3',
                 'limit','breakit','fetch','status','deallocate','start','teardown')]
    [string]$Step,
    [string]$AdminUser = 'clawadmin',
    [string]$RunIdFile = 'C:\Users\bmcki\ClawFactory-Secure-Setup\validation\diag\cfv-192-runid.txt',
    # Minting a new RunId is an EXPLICIT act, not a side effect of re-running the
    # stage step. Re-staging a corrected script mid-run must keep the run's
    # identity, or the evidence splits across two directories and the owner stamp
    # stops describing the run that produced it.
    [switch]$NewRun
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $PSCommandPath
. (Join-Path $here 'cfv-driverlib.ps1')

New-Item -ItemType Directory -Path (Split-Path -Parent $RunIdFile) -Force | Out-Null

# The RunId is minted ONCE and reused by every later step, so all of this run's
# state on the box sits under one owned directory. That is the whole point of
# scoping; a step that minted its own would recreate the flat C:\cfv problem
# inside the fix for it.
if ($NewRun -or -not (Test-Path $RunIdFile)) {
    $Run = New-CfvRun -Vm $Vm -ResourceGroup $Rg -Label 'harnessproof'
    [IO.File]::WriteAllText($RunIdFile, ($Run | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
} else {
    $Run = Get-Content $RunIdFile -Raw | ConvertFrom-Json
}
Write-Host "RunId: $($Run.RunId)   RunDir: $($Run.RunDir)   OutDir: $($Run.OutDir)" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $Run.OutDir, $Run.Scratch -Force | Out-Null

function Save-Result($name, $res) {
    $p = Join-Path $Run.OutDir "$name.txt"
    $txt = "CONDITION=$($res.Condition)`nAZEXIT=$($res.AzExit)`nBYTES=$($res.Bytes)`nELAPSED=$($res.ElapsedS)`nSTDERR=$($res.Stderr)`n---- TEXT ----`n$($res.Text)"
    [IO.File]::WriteAllText($p, $txt, (New-Object Text.UTF8Encoding($false)))
    Write-Host "  saved -> $p" -ForegroundColor DarkGray
}

# A job that sleeps, so the driver can OBSERVE the heartbeat beating during it.
# Three minutes is chosen to exceed the 90-second staleness threshold comfortably:
# with the old runner this window produced a frozen heartbeat and therefore an
# unavoidable RunnerDead reading, which is the defect being closed.
function Get-SlowJobBody([string]$tag, [int]$sleepSeconds = 180) {
@"
Write-Output "JOB_TAG=$tag"
Write-Output "JOB_WHOAMI=`$((& whoami.exe) -join '')"
Write-Output "JOB_SESSION=`$([Diagnostics.Process]::GetCurrentProcess().SessionId)"
Write-Output "JOB_BOOT=`$((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('s'))Z"
Write-Output "JOB_START=`$((Get-Date).ToUniversalTime().ToString('s'))Z"
Start-Sleep -Seconds $sleepSeconds
Write-Output "JOB_END=`$((Get-Date).ToUniversalTime().ToString('s'))Z"
Write-Output "JOB_SLEPT_S=$sleepSeconds"
"@
}

switch ($Step) {

'stage' {
    # The two scripts are pushed as base64 inside the dispatch payload rather than
    # through blob + SAS. That deletes an entire failure class from this run: the
    # SAS interpolation defect, the local-time expiry defect and the unchecked
    # generate-sas are all in the ledger, and none of them can occur if no SAS
    # exists. Input to run-command has a far larger budget than its output.
    $files = @('cfv-runner.ps1','cfv-arm-persistence.ps1')
    $parts = foreach ($f in $files) {
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $here $f)))
        $len = (Get-Item (Join-Path $here $f)).Length
        "[IO.File]::WriteAllBytes('C:\cfv\$f', [Convert]::FromBase64String('$b64'))`r`n" +
        "Write-Output `"STAGED $f expected=$len actual=`$((Get-Item 'C:\cfv\$f').Length)`""
    }
    $body = "New-Item -ItemType Directory -Path 'C:\cfv' -Force | Out-Null`r`n" +
            "New-Item -ItemType Directory -Path '$($Run.JobDir)' -Force | Out-Null`r`n" +
            ($parts -join "`r`n")
    $r = Invoke-CfvBox -Run $Run -Name 'stage' -Body $body
    Save-Result 'stage' $r
    # The staging claim is the byte-count comparison, not the dispatch's exit code.
    $ok = $true
    foreach ($f in $files) {
        $len = (Get-Item (Join-Path $here $f)).Length
        if ($r.Text -notmatch "STAGED $([regex]::Escape($f)) expected=$len actual=$len") { $ok = $false; Write-Host "  STAGING NOT CONFIRMED for $f" -ForegroundColor Red }
    }
    Write-Host $(if ($ok) { "  both files staged, byte counts confirmed on the box" } else { "  STAGING FAILED -- do not proceed" }) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    Write-CfvOwnerStamp -Run $Run | Out-Null
    Get-CfvRunsOnBox -Run $Run | ForEach-Object { Save-Result 'runcensus' $_ }
}

'ctl' {
    # THE CONTROL FOR THE WHOLE S4U CLAIM. Run-command is SYSTEM. wsl.exe must
    # refuse it BY NAME. If this succeeds, then "not SYSTEM" was never the
    # constraint, the S4U result proves nothing, and this run's central premise
    # is wrong -- which is a finding and not a failure.
    $r = Invoke-CfvBox -Run $Run -Name 'ctl-wsl-system' -Body @'
Write-Output "CTL_WHOAMI=$((& whoami.exe) -join '')"
Write-Output "CTL_SESSION=$([Diagnostics.Process]::GetCurrentProcess().SessionId)"
$out = & "$env:SystemRoot\System32\wsl.exe" --status 2>&1 | Out-String
Write-Output "CTL_WSL_EXIT=$LASTEXITCODE"
Write-Output "CTL_WSL_OUT_START"
Write-Output $out
Write-Output "CTL_WSL_OUT_END"
$out2 = & "$env:SystemRoot\System32\wsl.exe" --list --verbose 2>&1 | Out-String
Write-Output "CTL_WSL_LIST_EXIT=$LASTEXITCODE"
Write-Output $out2
'@
    Save-Result 'ctl-wsl-system' $r
    # Test-CfvWslTextMatch, not -match. wsl.exe's own messages are UTF-16LE and a
    # plain match fails against the exact error name it is looking for; measured
    # on this fleet, see that function's comment.
    $refused = (Test-CfvWslTextMatch $r.Text 'WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED') -or
               (Test-CfvWslTextMatch $r.Text 'Running WSL as local system is not supported')
    # The other half of the calibration, in the same run: a string that MUST NOT
    # be found. Without it a matcher loose enough to find anything would read as
    # a working control.
    $absent = -not (Test-CfvWslTextMatch $r.Text 'WSL_E_THIS_ERROR_DOES_NOT_EXIST')
    Write-Host "  matcher calibration: refusal-found=$refused absent-string-not-found=$absent" -ForegroundColor DarkGray
    if ($refused -and $absent) {
        Write-Host "  CONTROL FIRED: wsl.exe refuses SYSTEM by name. An S4U success below is therefore meaningful." -ForegroundColor Green
    } else {
        Write-Host "  CONTROL DID NOT FIRE. Read the transcript before believing any S4U result." -ForegroundColor Red
    }
}

'arm' {
    $r = Invoke-CfvBox -Run $Run -Name 'arm' -Body (
        "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\cfv\cfv-arm-persistence.ps1 " +
        "-RunId '$($Run.RunId)' -AdminUser '$AdminUser' -Root '$($Run.Root)' 2>&1 | Out-String | Write-Output")
    Save-Result 'arm' $r
    if ($r.Text -match 'ARM_RESULT=PASS') { Write-Host "  ARM PASS -- every read-back field matched and both controls discriminated." -ForegroundColor Green }
    else { Write-Host "  ARM did not pass. Read the ARM_RB_* lines above; do not proceed to the reboot." -ForegroundColor Red }
}

'probe1'  {
    $j = Start-CfvJob -Run $Run -Name 'p1' -JobBody (Get-SlowJobBody 'pre-reboot' 180); Save-Result 'p1-drop' $j
    $w = Wait-CfvJob -Run $Run -Name 'p1' -Minutes 15 -IntervalSeconds 30; Save-Result 'p1-wait' $w
    if ($w.Condition -eq 'JobDone') { Save-Result 'p1-out' (Receive-CfvJobOutput -Run $Run -Name 'p1') }
}

'wslctx' {
    $r = Invoke-CfvBox -Run $Run -Name 'wslctx' -Body @"
`$p = '$($Run.JobDir)\_wslcontext.json'
if (Test-Path `$p) { Get-Content `$p -Raw } else { Write-Output 'WSLCONTEXT_ABSENT -- the runner has not started, or started before this file existed' }
"@
    Save-Result 'wslctx' $r
}

'reboot1' { Save-Result 'reboot1' (Restart-CfvBox -Run $Run -WaitMinutes 20 -RunnerGraceSeconds 420) }

'probe2'  {
    $j = Start-CfvJob -Run $Run -Name 'p2' -JobBody (Get-SlowJobBody 'post-reboot-1' 60); Save-Result 'p2-drop' $j
    $w = Wait-CfvJob -Run $Run -Name 'p2' -Minutes 10 -IntervalSeconds 30; Save-Result 'p2-wait' $w
    if ($w.Condition -eq 'JobDone') { Save-Result 'p2-out' (Receive-CfvJobOutput -Run $Run -Name 'p2') }
}

'reboot2' { Save-Result 'reboot2' (Restart-CfvBox -Run $Run -WaitMinutes 20 -RunnerGraceSeconds 420) }

'probe3'  {
    $j = Start-CfvJob -Run $Run -Name 'p3' -JobBody (Get-SlowJobBody 'post-reboot-2' 60); Save-Result 'p3-drop' $j
    $w = Wait-CfvJob -Run $Run -Name 'p3' -Minutes 10 -IntervalSeconds 30; Save-Result 'p3-wait' $w
    if ($w.Condition -eq 'JobDone') { Save-Result 'p3-out' (Receive-CfvJobOutput -Run $Run -Name 'p3') }
}

'limit' {
    $m = Measure-CfvOutputLimit -Run $Run
    $p = Join-Path $Run.OutDir 'output-limit.json'
    [IO.File]::WriteAllText($p, ($m | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    Write-Host "  largest reply that came back WHOLE: $($m.LargestReturned) bytes" -ForegroundColor Green
    Write-Host "  smallest reply that did NOT: $($m.SmallestTruncated)" -ForegroundColor Yellow
    Write-Host "  saved -> $p" -ForegroundColor DarkGray
}

'breakit' {
    # ---- BREAK 1: a job that FAILS. The runner must still produce .out and .done,
    # carry the non-zero exit code, and carry the stderr -- because a job that dies
    # silently and a job that never ran look identical to the driver.
    $j = Start-CfvJob -Run $Run -Name 'bfail' -JobBody @'
Write-Output "about to fail deliberately"
Write-Error "DELIBERATE_STDERR_MARKER"
throw "DELIBERATE_TERMINATING_FAILURE"
'@
    Save-Result 'bfail-drop' $j
    $w = Wait-CfvJob -Run $Run -Name 'bfail' -Minutes 6 -IntervalSeconds 20
    Save-Result 'bfail-wait' $w
    if ($w.Condition -eq 'JobDone') { Save-Result 'bfail-out' (Receive-CfvJobOutput -Run $Run -Name 'bfail') }

    # ---- BREAK 1ctl: the identical shape that SUCCEEDS, so the reading above is
    # not simply "everything fails".
    $j = Start-CfvJob -Run $Run -Name 'bok' -JobBody 'Write-Output "DELIBERATE_SUCCESS_MARKER"; exit 0'
    Save-Result 'bok-drop' $j
    $w = Wait-CfvJob -Run $Run -Name 'bok' -Minutes 6 -IntervalSeconds 20
    Save-Result 'bok-wait' $w
    if ($w.Condition -eq 'JobDone') { Save-Result 'bok-out' (Receive-CfvJobOutput -Run $Run -Name 'bok') }

    # ---- BREAK 2: output that EXCEEDS the limit, dispatched directly. The
    # sentinel must be absent and the condition must be named.
    $r = Invoke-CfvBox -Run $Run -Name 'boverlimit' -Body @'
$chunk = 'Z' * 100
for ($i = 0; $i -lt 400; $i++) { Write-Output $chunk }
'@
    Save-Result 'boverlimit' $r
    Write-Host "  over-limit dispatch condition: $($r.Condition) ($($r.Bytes) bytes back)" -ForegroundColor $(if ($r.Condition -eq 'Ok') { 'Yellow' } else { 'Green' })

    # ---- BREAK 3: a COLLIDING dispatch. Start a long run-command as a background
    # job on this machine, then dispatch a second one into it while it is in flight.
    Write-Host "  starting a 150-second dispatch, then colliding with it deliberately..." -ForegroundColor Cyan
    $long = Join-Path $Run.Scratch 'long.ps1'
    [IO.File]::WriteAllText($long, "Start-Sleep -Seconds 150`r`nWrite-Output 'LONG_DONE'", (New-Object Text.UTF8Encoding($false)))
    $bg = Start-Job -ScriptBlock {
        param($rg, $vm, $f)
        & cmd.exe /c "az vm run-command invoke -g $rg -n $vm --command-id RunPowerShellScript --scripts `"@$f`" -o json" 2>&1 | Out-String
    } -ArgumentList $Rg, $Vm, $long
    Start-Sleep -Seconds 25
    $r = Invoke-CfvBox -Run $Run -Name 'bcollide' -Body 'Write-Output "COLLIDER"' -ConflictRetries 8 -ConflictWaitSeconds 30
    Save-Result 'bcollide' $r
    Write-Host "  collider condition: $($r.Condition) after $($r.ElapsedS)s" -ForegroundColor Green
    Wait-Job $bg -Timeout 300 | Out-Null
    $bgOut = Receive-Job $bg -ErrorAction SilentlyContinue | Out-String
    [IO.File]::WriteAllText((Join-Path $Run.OutDir 'bcollide-long.txt'), $bgOut, (New-Object Text.UTF8Encoding($false)))
    Remove-Job $bg -Force -ErrorAction SilentlyContinue

    # ---- BREAK 4: a box that does not come back, WITHOUT destroying it. Deallocate,
    # dispatch into the absence, then start it again. Real, reversible, and it is
    # the condition the harness has never been able to name.
    Write-Host "  deallocating to construct 'the box did not come back'..." -ForegroundColor Cyan
    & cmd.exe /c "az vm deallocate -g $Rg -n $Vm -o none" | Out-Null
    Write-Host "  az vm deallocate exit=$LASTEXITCODE"
    $r = Invoke-CfvBox -Run $Run -Name 'bgone' -Body 'Write-Output "SHOULD NOT ARRIVE"' -ConflictRetries 0
    Save-Result 'bgone' $r
    Write-Host "  dispatch into a deallocated box: $($r.Condition)" -ForegroundColor Green
    & cmd.exe /c "az vm start -g $Rg -n $Vm -o none" | Out-Null
    Write-Host "  az vm start exit=$LASTEXITCODE"
}

'fetch' {
    $r = Invoke-CfvBox -Run $Run -Name 'fetch' -Body @"
Write-Output "RUNDIR=$($Run.RunDir)"
Get-ChildItem '$($Run.JobDir)' -File -ErrorAction SilentlyContinue | ForEach-Object { "FILE `$(`$_.Name) `$(`$_.Length) `$(`$_.LastWriteTimeUtc.ToString('s'))Z" }
Write-Output '---- runner log tail ----'
Get-Content '$($Run.JobDir)\_runner.log' -Tail 40 -ErrorAction SilentlyContinue
Write-Output '---- wsl context ----'
Get-Content '$($Run.JobDir)\_wslcontext.json' -Raw -ErrorAction SilentlyContinue
Write-Output '---- scheduled task ----'
`$t = Get-ScheduledTask -TaskName 'CFV-Runner' -ErrorAction SilentlyContinue
Write-Output "TASK_STATE=`$(`$t.State) LOGON=`$(`$t.Principal.LogonType) USER=`$(`$t.Principal.UserId)"
Write-Output "TASK_LASTRESULT=`$((Get-ScheduledTaskInfo -TaskName 'CFV-Runner' -EA SilentlyContinue).LastTaskResult)"
Write-Output "TASK_LASTRUN=`$((Get-ScheduledTaskInfo -TaskName 'CFV-Runner' -EA SilentlyContinue).LastRunTime)"
Write-Output "SESSIONS:"
& query.exe session 2>&1 | Out-String
"@
    Save-Result 'fetch' $r
}

'status' {
    $r = Invoke-CfvBox -Run $Run -Name 'status' -Body @"
Write-Output "NOWUTC=`$((Get-Date).ToUniversalTime().ToString('s'))Z"
Write-Output "LASTBOOT=`$((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('s'))Z"
`$hb = '$($Run.JobDir)\_runner.heartbeat'
Write-Output "HEARTBEAT=`$(if (Test-Path `$hb) { (Get-Content `$hb -Raw).Trim() } else { 'ABSENT' })"
Write-Output "TASK=`$(try { (Get-ScheduledTask -TaskName 'CFV-Runner' -EA Stop).State } catch { 'NO-TASK' })"
& query.exe session 2>&1 | Out-String
"@
    Save-Result 'status' $r
}

'deallocate' {
    & cmd.exe /c "az vm deallocate -g $Rg -n $Vm -o none" | Out-Null
    Write-Host "az vm deallocate exit=$LASTEXITCODE"
    & cmd.exe /c "az vm get-instance-view -g $Rg -n $Vm --query instanceView.statuses[].code -o tsv"
}

'start' {
    & cmd.exe /c "az vm start -g $Rg -n $Vm -o none" | Out-Null
    Write-Host "az vm start exit=$LASTEXITCODE"
    & cmd.exe /c "az vm get-instance-view -g $Rg -n $Vm --query instanceView.statuses[].code -o tsv"
}

'teardown' {
    # The names az vm create chooses have differed between cycles -- cfv-186-nic
    # and cfv-shared-nsg in one, <vm>VMNic and <vm>NSG in another -- so this
    # ENUMERATES rather than guessing. A delete aimed at a name that does not
    # exist reports success against nothing, which is the failure the unfiltered
    # residual below exists to catch and which should not be relied on.
    #
    # Paren-free --query throughout: az on Windows is az.cmd and cmd.exe
    # re-parses a bracketed filter expression. A failed enumeration deletes
    # nothing and the loop is silent about it.
    function Get-Names([string]$cmd) {
        $out = & cmd.exe /c $cmd
        $rc = $LASTEXITCODE
        if ($rc -ne 0) { Write-Host "  ENUMERATION FAILED (exit $rc): $cmd -- nothing below is a complete list" -ForegroundColor Red; return @() }
        return @($out -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    $keep = @('bake-vmVNET','clawfactory-win11-baseline','clawfactory-win11-baseline-v2','clawfactoryvalc467')

    & cmd.exe /c "az vm delete -g $Rg -n $Vm --yes -o none" | Out-Null; Write-Host "vm delete exit=$LASTEXITCODE"

    # NIC FIRST -- it references the public IP and the NSG.
    foreach ($n in (Get-Names "az network nic list -g $Rg --query [].name -o tsv" | Where-Object { $_ -like "$Vm*" })) {
        & cmd.exe /c "az network nic delete -g $Rg -n $n -o none" | Out-Null; Write-Host "nic $n delete exit=$LASTEXITCODE"
    }
    foreach ($n in (Get-Names "az network public-ip list -g $Rg --query [].name -o tsv" | Where-Object { $_ -like "$Vm*" })) {
        & cmd.exe /c "az network public-ip delete -g $Rg -n $n -o none" | Out-Null; Write-Host "pip $n delete exit=$LASTEXITCODE"
    }
    foreach ($n in (Get-Names "az network nsg list -g $Rg --query [].name -o tsv" | Where-Object { $_ -like "$Vm*" -or $_ -like 'cfv-*' })) {
        & cmd.exe /c "az network nsg delete -g $Rg -n $n -o none" | Out-Null; Write-Host "nsg $n delete exit=$LASTEXITCODE"
    }
    foreach ($n in (Get-Names "az network vnet list -g $Rg --query [].name -o tsv" | Where-Object { $keep -notcontains $_ })) {
        & cmd.exe /c "az network vnet delete -g $Rg -n $n -o none" | Out-Null; Write-Host "vnet $n delete exit=$LASTEXITCODE"
    }
    foreach ($n in (Get-Names "az disk list -g $Rg --query [].name -o tsv" | Where-Object { $_ -like "$Vm*" })) {
        & cmd.exe /c "az disk delete -g $Rg -n $n --yes -o none" | Out-Null; Write-Host "disk $n delete exit=$LASTEXITCODE"
    }

    Write-Host '--- UNFILTERED residual, which is the claim that matters ---'
    & cmd.exe /c "az resource list -g $Rg --query [].[name,type] -o tsv"; Write-Host "resource list exit=$LASTEXITCODE"
    Write-Host '--- re-check, because "it said deleted" is not the same claim as "it is gone" ---'
    Start-Sleep -Seconds 25
    & cmd.exe /c "az resource list -g $Rg --query [].[name,type] -o tsv"; Write-Host "resource list exit=$LASTEXITCODE"
}

}
