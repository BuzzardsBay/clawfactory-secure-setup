<#
  cfv-driverlib-selftest.ps1 -- prove the DRIVER against deliberately broken runs.

  WHY A GREEN RUN WOULD NOT DO, AND WHY THIS FILE IS THE POINT OF CARD #259
  -------------------------------------------------------------------------
  harness-selftest.ps1 does this for the VERDICT layer and passes 15/15. Every one
  of the twelve instrument defects in the v1.4.5 reboot-persistence cycle lived in
  the layer with no self-test at all: the transport. A driver that has only been
  seen to work on a run that succeeded is unmeasured, and the last three cycles
  show that the harness fails more often than the product does -- twelve instrument
  defects against zero product defects in the last cycle.

  So each of the ways this harness has ACTUALLY broken is constructed here as a
  rigged dispatch, and the library's answer is asserted:

    a job that fails                    -> the failure is reported, not swallowed
    a box that does not come back       -> BoxUnreachable, distinct from a dead runner
    output that exceeds the size limit  -> OutputTruncated, NEVER an empty result
    a payload that dies early           -> PayloadDied, distinct from truncation
    a dispatch that collides            -> DispatchConflict, waited out, not a verdict
    a runner that has died              -> RunnerDead, distinct from a slow job
    a runner alive but not on the job   -> RunnerIdle, which had no name before
    a slow job with a live heartbeat    -> JobRunning, the reading the old runner
                                           could not produce during a long job

  CALIBRATED IN BOTH DIRECTIONS (TASK 5.3)
  ----------------------------------------
  A harness that reported everything as broken would pass a one-sided test, so
  every fault is paired with a control that must come back clean through the
  SAME code path. The controls are not decoration: SELF.D2ctl is the one that
  would catch a library which had simply been made to always say OutputTruncated.

  THE RANKING RULE (TASK 5.4)
  ---------------------------
  A failure mode that produces a FALSE PASS outranks everything else. Those cases
  are marked CRITICAL below and are reported first and separately: if any of them
  fails, the exit code is 4 and the run stops rather than continuing to a summary.

  Touches no VM, no WSL, no Azure and no product state -- the az dispatch primitive
  is replaced through Set-CfvAzInvoker. Cheap enough to run before every cycle.
#>
[CmdletBinding()]
param([string]$WorkDir = (Join-Path $env:TEMP "cfv-driverlib-selftest-$PID"))

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
. (Join-Path (Split-Path -Parent $PSCommandPath) 'cfv-driverlib.ps1')

$script:Findings = @()
function Assert-Case {
    param([string]$Id, [string]$Name, [bool]$Ok, [string]$Evidence, [switch]$Critical)
    $script:Findings += [pscustomobject]@{ Id = $Id; Name = $Name; Ok = $Ok; Evidence = $Evidence; Critical = [bool]$Critical }
    $c = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1} :: {2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Id, $Name) -ForegroundColor $c
    Write-Host ("        {0}" -f $Evidence) -ForegroundColor DarkGray
}

# A run object that points at nothing real. Nothing here dispatches for real.
$Run = New-CfvRun -Vm 'cfv-selftest' -ResourceGroup 'no-such-rg' -OutDir (Join-Path $WorkDir 'out') -Label 'selftest'

function Set-Rig {
    <# Builds an az invoker that returns exactly the shape being tested. The
       sentinel is read out of the payload file when the rig is meant to echo it,
       so a rig cannot accidentally satisfy the check with a stale nonce. #>
    param([int]$ExitCode = 0, [string]$Stderr = '', [scriptblock]$MakeStdout)
    Set-CfvAzInvoker {
        param($Rg, $Vm, $ScriptFile, $ErrFile)
        $payload = Get-Content $ScriptFile -Raw
        $msg = & $MakeStdout $payload
        @{
            Stdout   = (@{ value = @(@{ code = 'ComponentStatus/StdOut/succeeded'; message = $msg }) } | ConvertTo-Json -Depth 5)
            ExitCode = $ExitCode
            Stderr   = $Stderr
        }.GetEnumerator() | ForEach-Object -Begin { $h = @{} } -Process { $h[$_.Key] = $_.Value } -End { $h }
    }.GetNewClosure()
}
function Get-Sentinel([string]$payload) {
    if ($payload -match 'CFV_EOF:(\S+?)"') { return $Matches[1] }
    return ''
}

Write-Host ''
Write-Host '=== CRITICAL: failure modes that could produce a FALSE PASS ===' -ForegroundColor Cyan

# --- D1. Output over the limit. az exits ZERO and returns EMPTY. -------------
# This is the exact shape from the close-out: 16.6 KB asked for, nothing back,
# az exit 0, and forty minutes spent believing the install had hung.
# The REAL truncation shape, measured on cfv-192: the channel keeps the LAST
# 4096 bytes, so the TAIL SENTINEL SURVIVES and the head one is gone. The first
# version of this rig emitted no sentinel at all, which is not what this channel
# does, and it is why the tail-only design passed its own self-test while being
# unable to detect the truncation it existed to detect.
Set-Rig -ExitCode 0 -MakeStdout { param($p) ('X' * 4000) + "`nCFV_EOF:" + (Get-Sentinel $p) }
$r = Invoke-CfvBox -Run $Run -Name 'over-limit' -Quiet -Body 'Write-Output "anything"'
Assert-Case -Id 'SELF.D1' -Critical `
  -Name 'output over the size limit reports OutputTruncated, and is NEVER readable as a clean empty result' `
  -Ok (($r.Condition -eq 'OutputTruncated') -and (-not $r.Ok)) `
  -Evidence "Condition=$($r.Condition) Ok=$($r.Ok) bytes=$($r.Bytes) azExit=$($r.AzExit)"

# --- D1b. The same channel with the output actually EMPTY. ------------------
# The genuinely dangerous variant: az exit 0, zero bytes. The old code path read
# this as "the probe found nothing", which is how an absence gets scored clean.
Set-Rig -ExitCode 0 -MakeStdout { param($p) '' }
$r = Invoke-CfvBox -Run $Run -Name 'empty-zero' -Quiet -Body 'Write-Output "anything"'
Assert-Case -Id 'SELF.D1b' -Critical `
  -Name 'az exit 0 with EMPTY output is a named condition, not a clean empty result' `
  -Ok (($r.Condition -eq 'PayloadDied') -and (-not $r.Ok)) `
  -Evidence "Condition=$($r.Condition) Ok=$($r.Ok) bytes=$($r.Bytes)"

# --- D1ctl. THE OTHER DIRECTION. A large-but-complete reply must be Ok. -----
# Without this, a library hard-wired to say OutputTruncated would pass D1.
Set-Rig -ExitCode 0 -MakeStdout { param($p) "CFV_BOF:" + (Get-Sentinel $p) + "`n" + ('Y' * 12000) + "`nCFV_EOF:" + (Get-Sentinel $p) }
$r = Invoke-CfvBox -Run $Run -Name 'big-complete' -Quiet -Body 'Write-Output "anything"'
Assert-Case -Id 'SELF.D1ctl' -Critical `
  -Name 'CONTROL: a large reply that DID arrive whole reports Ok (the check discriminates on the sentinel, not on size)' `
  -Ok (($r.Condition -eq 'Ok') -and $r.Ok -and $r.Bytes -gt 10000) `
  -Evidence "Condition=$($r.Condition) bytes=$($r.Bytes)"

# --- D2. A job that FAILED must not read as a job that passed. --------------
$hbNow = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
Set-CfvAzInvoker {
    param($Rg, $Vm, $ScriptFile, $ErrFile)
    $p = Get-Content $ScriptFile -Raw
    $s = if ($p -match 'CFV_EOF:(\S+?)"') { $Matches[1] } else { '' }
    $now = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    $msg = "CFV_BOF:$s`nDONE=True`nJOBFILE=True`nOUTBYTES=412`nSTDOUTBYTES=100`nSTDERRBYTES=312`nHEARTBEAT=$now state=idle job=- pid=0 elapsed=0 runid=x`nNOWUTC=$now`nTASKSTATE=Running`nCFV_EOF:$s"
    @{ Stdout = (@{ value = @(@{ code='ComponentStatus/StdOut/succeeded'; message=$msg }) } | ConvertTo-Json -Depth 5); ExitCode = 0; Stderr = '' }
}
$st = Get-CfvJobStatus -Run $Run -Name 'failedjob'
Assert-Case -Id 'SELF.D2' -Critical `
  -Name 'a job that reached .done is JobDone, and its STDERR bytes are carried so a job that died is not read as one that passed' `
  -Ok (($st.Condition -eq 'JobDone') -and ($st.Extra['STDERRBYTES'] -eq '312')) `
  -Evidence "Condition=$($st.Condition) stderrBytes=$($st.Extra['STDERRBYTES']) outBytes=$($st.Extra['OUTBYTES'])"

# --- D3. A short transfer must not be read as the job's output. -------------
# The box says 5000 bytes; the channel delivers 10. Reassembly must refuse.
$script:chunkCall = 0
Set-CfvAzInvoker {
    param($Rg, $Vm, $ScriptFile, $ErrFile)
    $p = Get-Content $ScriptFile -Raw
    $s = if ($p -match 'CFV_EOF:(\S+?)"') { $Matches[1] } else { '' }
    if ($p -match 'OUTBYTES=') { $msg = "CFV_BOF:$s`nOUTBYTES=5000`nCFV_EOF:$s" }
    else {
        $script:chunkCall++
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('SHORT'))
        # Returns 5 bytes and then nothing, so the loop ends far short of 5000.
        $payload = if ($script:chunkCall -le 1) { $b64 } else { '' }
        $msg = "CFV_BOF:$s`nCHUNK_OFFSET=0 CHUNK_READ=5`n---8<---`n$payload`nCFV_EOF:$s"
    }
    @{ Stdout = (@{ value = @(@{ code='ComponentStatus/StdOut/succeeded'; message=$msg }) } | ConvertTo-Json -Depth 5); ExitCode = 0; Stderr = '' }
}
$rv = Receive-CfvJobOutput -Run $Run -Name 'shortjob' -ChunkBytes 6000 -MaxChunks 3
Assert-Case -Id 'SELF.D3' -Critical `
  -Name 'a SHORT transfer reports OutputTruncated rather than returning the fragment as the job output' `
  -Ok (($rv.Condition -eq 'OutputTruncated') -and (-not $rv.Ok)) `
  -Evidence "Condition=$($rv.Condition) got=$($rv.Bytes) expected=5000 stderr=$($rv.Stderr)"

$criticalBad = @($script:Findings | Where-Object { $_.Critical -and -not $_.Ok })
if ($criticalBad.Count -gt 0) {
    Write-Host ''
    Write-Host "A FAILURE MODE PRODUCES A FALSE PASS. That outranks everything else in this harness." -ForegroundColor Red
    foreach ($b in $criticalBad) { Write-Host "  $($b.Id): $($b.Name)" -ForegroundColor Red }
    Write-Host 'Stopping here rather than reporting a summary over it.' -ForegroundColor Red
    exit 4
}

Write-Host ''
Write-Host '=== the remaining failure modes, and their controls ===' -ForegroundColor Cyan

# --- D4. A dispatch that collides with one in flight. -----------------------
$script:conflictCalls = 0
Set-CfvAzInvoker {
    param($Rg, $Vm, $ScriptFile, $ErrFile)
    $script:conflictCalls++
    if ($script:conflictCalls -le 2) {
        return @{ Stdout = ''; ExitCode = 1; Stderr = "(Conflict) Run command extension execution is in progress. Please wait for completion before invoking a run command." }
    }
    $p = Get-Content $ScriptFile -Raw
    $s = if ($p -match 'CFV_EOF:(\S+?)"') { $Matches[1] } else { '' }
    @{ Stdout = (@{ value = @(@{ code='ComponentStatus/StdOut/succeeded'; message="CFV_BOF:$s`nrecovered`nCFV_EOF:$s" }) } | ConvertTo-Json -Depth 5); ExitCode = 0; Stderr = '' }
}
$r = Invoke-CfvBox -Run $Run -Name 'collide' -Quiet -Body 'Write-Output "x"' -ConflictRetries 5 -ConflictWaitSeconds 0
Assert-Case -Id 'SELF.D4' `
  -Name 'a colliding dispatch is waited out and re-read; a Conflict is a CHANNEL condition and never a verdict about the product' `
  -Ok (($r.Condition -eq 'Ok') -and ($script:conflictCalls -eq 3)) `
  -Evidence "Condition=$($r.Condition) after $($script:conflictCalls) attempts (2 conflicts, then the real reply)"

# --- D4b. A collision that never clears must give up NAMED, not as a failure of the job.
$script:conflictCalls = 0
Set-CfvAzInvoker {
    param($Rg, $Vm, $ScriptFile, $ErrFile)
    $script:conflictCalls++
    @{ Stdout = ''; ExitCode = 1; Stderr = '(Conflict) another operation is in progress' }
}
$r = Invoke-CfvBox -Run $Run -Name 'collide-forever' -Quiet -Body 'Write-Output "x"' -ConflictRetries 2 -ConflictWaitSeconds 0
Assert-Case -Id 'SELF.D4b' `
  -Name 'a collision that never clears reports DispatchConflict by name, not DispatchFailed and not an empty result' `
  -Ok ($r.Condition -eq 'DispatchConflict') `
  -Evidence "Condition=$($r.Condition) attempts=$($script:conflictCalls)"

# --- D5. A box that does not come back. -------------------------------------
Set-CfvAzInvoker {
    param($Rg, $Vm, $ScriptFile, $ErrFile)
    @{ Stdout = ''; ExitCode = 1; Stderr = "ResourceNotFound: The Resource 'Microsoft.Compute/virtualMachines/$Vm' was not found, or the VM is deallocated" }
}
$r = Invoke-CfvBox -Run $Run -Name 'gone' -Quiet -Body 'Write-Output "x"'
Assert-Case -Id 'SELF.D5' `
  -Name 'a box that is not there reports BoxUnreachable, which is a different condition from a dead runner and from a failed job' `
  -Ok ($r.Condition -eq 'BoxUnreachable') `
  -Evidence "Condition=$($r.Condition) stderr=$(($r.Stderr -replace '\s+',' ').Substring(0, [Math]::Min(70, $r.Stderr.Length)))"

# --- D6. The heartbeat cases: dead vs running vs idle. ----------------------
# This is defect 4.1's acceptance test. The old runner could produce only two of
# these three readings, and the third is the one that matters during a long job.
function Set-HeartbeatRig([string]$state, [string]$job, [int]$ageSeconds) {
    Set-CfvAzInvoker {
        param($Rg, $Vm, $ScriptFile, $ErrFile)
        $p = Get-Content $ScriptFile -Raw
        $s = if ($p -match 'CFV_EOF:(\S+?)"') { $Matches[1] } else { '' }
        $now = (Get-Date).ToUniversalTime()
        $hbT = $now.AddSeconds(-1 * $ageSeconds).ToString('s') + 'Z'
        $hb  = if ($state -eq 'ABSENT') { 'ABSENT' } else { "$hbT state=$state job=$job pid=4212 elapsed=$ageSeconds runid=x" }
        $msg = "CFV_BOF:$s`nDONE=False`nJOBFILE=True`nOUTBYTES=0`nSTDOUTBYTES=0`nSTDERRBYTES=0`nHEARTBEAT=$hb`nNOWUTC=$($now.ToString('s'))Z`nTASKSTATE=Running`nCFV_EOF:$s"
        @{ Stdout = (@{ value = @(@{ code='ComponentStatus/StdOut/succeeded'; message=$msg }) } | ConvertTo-Json -Depth 5); ExitCode = 0; Stderr = '' }
    }.GetNewClosure()
}

Set-HeartbeatRig 'running' 'install' 10
$st = Get-CfvJobStatus -Run $Run -Name 'install'
Assert-Case -Id 'SELF.D6a' `
  -Name 'a LONG job with a live heartbeat reads JobRunning -- the reading the old runner could not produce, because its heartbeat froze for the whole job' `
  -Ok ($st.Condition -eq 'JobRunning') -Evidence "Condition=$($st.Condition) age=$($st.Extra['HEARTBEAT_AGE_S'])s"

Set-HeartbeatRig 'running' 'install' 600
$st = Get-CfvJobStatus -Run $Run -Name 'install'
Assert-Case -Id 'SELF.D6b' `
  -Name 'a STALE heartbeat reads RunnerDead, distinct from a slow job' `
  -Ok ($st.Condition -eq 'RunnerDead') -Evidence "Condition=$($st.Condition) age=$($st.Extra['HEARTBEAT_AGE_S'])s"

Set-HeartbeatRig 'ABSENT' '-' 0
$st = Get-CfvJobStatus -Run $Run -Name 'install'
Assert-Case -Id 'SELF.D6c' `
  -Name 'NO heartbeat file at all reads RunnerDead rather than passing silently' `
  -Ok ($st.Condition -eq 'RunnerDead') -Evidence "Condition=$($st.Condition) hb=$($st.Extra['HEARTBEAT'])"

Set-HeartbeatRig 'idle' '-' 5
$st = Get-CfvJobStatus -Run $Run -Name 'install'
Assert-Case -Id 'SELF.D6d' `
  -Name 'a live runner that is NOT on this job reads RunnerIdle -- a third condition, which had no name before' `
  -Ok ($st.Condition -eq 'RunnerIdle') -Evidence "Condition=$($st.Condition) hb=$($st.Extra['HEARTBEAT'])"

# --- D6ctl. THE OTHER DIRECTION for the whole heartbeat family. -------------
Set-CfvAzInvoker {
    param($Rg, $Vm, $ScriptFile, $ErrFile)
    $p = Get-Content $ScriptFile -Raw
    $s = if ($p -match 'CFV_EOF:(\S+?)"') { $Matches[1] } else { '' }
    $now = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    $msg = "CFV_BOF:$s`nDONE=True`nJOBFILE=True`nOUTBYTES=900`nSTDOUTBYTES=900`nSTDERRBYTES=0`nHEARTBEAT=$now state=idle job=- pid=0 elapsed=0 runid=x`nNOWUTC=$now`nTASKSTATE=Running`nCFV_EOF:$s"
    @{ Stdout = (@{ value = @(@{ code='ComponentStatus/StdOut/succeeded'; message=$msg }) } | ConvertTo-Json -Depth 5); ExitCode = 0; Stderr = '' }
}
$st = Get-CfvJobStatus -Run $Run -Name 'install'
Assert-Case -Id 'SELF.D6ctl' `
  -Name 'CONTROL: a finished job on a live runner reads JobDone -- the family is not simply reporting everything as broken' `
  -Ok (($st.Condition -eq 'JobDone') -and $st.Ok) -Evidence "Condition=$($st.Condition) Ok=$($st.Ok)"

# --- D7. A complete retrieval must reassemble and confirm its byte count. ---
$body = ('A' * 3000) + "`n" + ('B' * 2000)
$bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
$script:d7 = 0
Set-CfvAzInvoker {
    param($Rg, $Vm, $ScriptFile, $ErrFile)
    $p = Get-Content $ScriptFile -Raw
    $s = if ($p -match 'CFV_EOF:(\S+?)"') { $Matches[1] } else { '' }
    if ($p -match 'OUTBYTES=') { $msg = "CFV_BOF:$s`nOUTBYTES=$($bodyBytes.Length)`nCFV_EOF:$s" }
    else {
        $off = if ($p -match '\$fs\.Position = (\d+)') { [int]$Matches[1] } else { 0 }
        $n = [Math]::Min(4000, $bodyBytes.Length - $off)
        $b64 = [Convert]::ToBase64String($bodyBytes, $off, $n)
        $msg = "CFV_BOF:$s`nCHUNK_OFFSET=$off CHUNK_READ=$n`n---8<---`n$b64`nCFV_EOF:$s"
    }
    @{ Stdout = (@{ value = @(@{ code='ComponentStatus/StdOut/succeeded'; message=$msg }) } | ConvertTo-Json -Depth 5); ExitCode = 0; Stderr = '' }
}.GetNewClosure()
$rv = Receive-CfvJobOutput -Run $Run -Name 'wholejob' -ChunkBytes 4000 -MaxChunks 10
Assert-Case -Id 'SELF.D7' `
  -Name 'CONTROL: a COMPLETE multi-chunk retrieval reassembles and its byte count matches the box' `
  -Ok ($rv.Condition -eq 'Ok' -and $rv.Extra.Bytes -eq $bodyBytes.Length) `
  -Evidence "Condition=$($rv.Condition) got=$($rv.Extra.Bytes) expected=$($bodyBytes.Length)"

# --- D8. Publish-CfvFile must not announce an upload it did not confirm. ----
# The literal 4.4 defect, exercised end to end rather than only counted by the
# AST census: a local file that does not exist cannot produce a success line.
$rv = Publish-CfvFile -Path (Join-Path $WorkDir 'no-such-file.bin') -StorageAccount 'x' -AccountKey 'y'
Assert-Case -Id 'SELF.D8' `
  -Name 'Publish-CfvFile refuses before dispatching when the source is absent, and returns Ok=false with a reason' `
  -Ok ((-not $rv.Ok) -and $rv.Reason -match 'absent') -Evidence "Ok=$($rv.Ok) Reason=$($rv.Reason)"

Reset-CfvAzInvoker

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '===== DRIVER SELF-TEST RESULT =====' -ForegroundColor Cyan
foreach ($f in $script:Findings) {
    Write-Host ("{0,-12} {1,-5} {2}{3}" -f $f.Id, $(if ($f.Ok) { 'PASS' } else { 'FAIL' }), $(if ($f.Critical) { '[CRITICAL] ' } else { '' }), $f.Name)
}
$bad = @($script:Findings | Where-Object { -not $_.Ok })
$summary = Join-Path $WorkDir 'cfv-driverlib-selftest-results.json'
$script:Findings | ConvertTo-Json -Depth 5 | Out-File $summary -Encoding utf8
if (Test-Path $summary) { Write-Host "`nDetail written to $summary ($((Get-Item $summary).Length) bytes)" }
else { Write-Host "`nDETAIL NOT WRITTEN: $summary is absent after the write." -ForegroundColor Red }

if ($bad.Count -gt 0) {
    Write-Host "`nDRIVER SELF-TEST FAILED: $($bad.Count) of $($script:Findings.Count)." -ForegroundColor Red
    Write-Host 'The transport does NOT behave as documented. Do not trust a validation run made with it.' -ForegroundColor Red
    Write-Host 'DRIVER_SELFTEST_COMPLETE rc=1'
    exit 1
}
Write-Host "`nDRIVER SELF-TEST PASSED: $($script:Findings.Count)/$($script:Findings.Count)." -ForegroundColor Green
Write-Host 'Each way this harness has actually broken was constructed and reported as the real condition,'
Write-Host 'and each paired control shows the library discriminates rather than reporting everything broken.'
Write-Host 'DRIVER_SELFTEST_COMPLETE rc=0'
exit 0
