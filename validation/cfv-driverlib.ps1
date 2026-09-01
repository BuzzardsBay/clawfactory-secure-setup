<#
  cfv-driverlib.ps1 -- the BUILD-MACHINE side of the validation harness.

  WHY THIS FILE EXISTS
  --------------------
  interim-v120-phaselib.ps1 encodes the discipline for the VERDICT layer, and its
  self-test passes 15/15. Every one of the twelve instrument defects recorded in
  docs/session_reports/2026-08-31_systemd_reboot_persistence_closeout.md 4.7 lived
  in a layer that had no library at all: the DRIVER. Each cycle copies the previous
  cycle's interim-vNNN-runner.ps1 -- v120 to v145 to v146 -- and inherits its
  transport bugs along with its shape. That copying is the mechanism by which the
  same four defects keep arriving, so the fix is a library, not another copy.

  THE FOUR DEFECTS THIS LIBRARY OWNS, AND HOW EACH IS CLOSED
  ----------------------------------------------------------

  1. THE HEARTBEAT FROZE DURING A SYNCHRONOUS JOB (closed in cfv-runner.ps1, read
     here). The old runner stamped the heartbeat at the top of the loop that also
     executed the job, so a long job and a dead runner looked identical -- the
     exact ambiguity the runner's own header says it exists to prevent, later
     written into interim-v146-runner.ps1's header as expected behaviour. The new
     runner stamps from the wait loop around a Start-Process child and NAMES its
     state. Wait-CfvJob reads that state and reports five distinct conditions
     where the old poll reported two.

  2. az vm run-command SILENTLY DISCARDS THE FRONT OF A LARGE REPLY WHILE az
     EXITS ZERO. One poll showed nothing for forty minutes while the .done
     barrier had existed the whole time; trusted, it would have concluded the
     install hung.

     MEASURED ON cfv-192, 2026-09-01, AND BOTH HALVES OF THE INHERITED BELIEF
     WERE WRONG:

       - The limit is 4096 BYTES, not "roughly 16 KB". Bracketed: 3584 bytes came
         back whole, 4096 did not.
       - It does not return EMPTY. It returns THE LAST 4096 BYTES and silently
         drops everything before them. A payload emitting 900 numbered lines came
         back as 78, beginning mid-word at "INE00822" and running to LINE00900.

     This library's first version carried only a TAIL sentinel, reasoning that a
     reply missing its last line had not arrived whole. The tail is exactly what
     survives, so that sentinel reported Ok on a reply that had lost 91% of its
     content -- a FALSE PASS manufactured by the instrument built to prevent one.

     So every payload now carries a HEAD sentinel and a TAIL sentinel, both with
     the same per-dispatch nonce, and they name different faults:

       head gone, tail present -> OutputTruncated. The channel dropped the front.
       head present, tail gone -> PayloadDied. It never reached its own last line.
       both gone               -> PayloadDied. Nothing recognisable arrived.

     A bound inherited from a close-out is a guess; Measure-CfvOutputLimit
     measures it, and Receive-CfvJobOutput's chunk size is derived from the
     measurement rather than chosen.

  3. C:\cfv WAS AN UNSCOPED CROSS-SESSION NAMESPACE. Markers from different runs,
     boxes and sessions accumulated in one directory with no owner. Every run now
     owns C:\cfv\runs\<RunId>\ and stamps _owner.json. Eighty files in this tree
     reference C:\cfv, so the root is kept and the SCOPE is added beneath it; a
     tree-wide rename would be a far larger change than the defect warrants.

  4. A SUCCESS LINE PRINTED UNCONDITIONALLY AFTER THE CALL IT DESCRIBES. Ten
     uploads returned AuthenticationFailed and the script printed "uploaded" for
     every one, because the success line sat after the call rather than after a
     check of it. Publish-CfvFile confirms the byte count AT THE SERVICE before it
     says anything, and says the failure otherwise. cfv-successline-census.ps1
     enumerates the shape tree-wide rather than fixing the one that was noticed.

  FAILURE MODES ARE CONDITIONS, NOT RESULTS
  -----------------------------------------
  Every function here returns an object with a .Condition naming exactly one of a
  closed vocabulary. Nothing returns a bare string, and nothing returns $null to
  mean "it did not work", because a null that means four different things is how
  "the box did not come back" gets scored as "the job failed".

      Ok                  the dispatch ran and its sentinel came back
      DispatchFailed      az exited non-zero
      DispatchConflict    a prior run-command is still in flight on this VM
      OutputTruncated     az exited zero, sentinel absent, output at the limit
      PayloadDied         az exited zero, sentinel absent, output short
      BoxUnreachable      the VM is not in a state that can accept a dispatch
      RunnerDead          a heartbeat that existed has gone stale
      RunnerAbsent        no runner has ever beaten on this queue and its task is
                          not running. On the WSL queue this means there is no
                          interactive session -- an unmet PRECONDITION, never a
                          product verdict. Kept distinct from RunnerDead because
                          collapsing them reports "this needs a logon" as "the
                          runner crashed"
      RunnerIdle          runner alive, job file present, job never picked up
      JobRunning          runner alive and executing the job
      JobDone             the .done barrier exists
      Timeout             the deadline passed without any of the above resolving

  ONE az vm run-command invoke AT A TIME. They queue and interfere, and a TaskStop
  does NOT cancel one in flight -- the next dispatch dies with (Conflict). This
  library never issues two concurrently and treats a Conflict as a condition to
  wait out and re-read, never as a failure of the thing being measured.
#>

$script:CfvDefaultRoot = 'C:\cfv\runs'

# ---------------------------------------------------------------------------
# The az seam.
#
# Every run-command dispatch goes through this one function so that the
# self-test can replace it with a rigged one. Without the seam the library
# could only ever be exercised on a run that worked, and a harness that has
# only been seen to work on a run that succeeded is unmeasured -- which is the
# whole reason this library exists.
#
# It returns a hashtable, not a string, because a bare string cannot carry the
# exit code and stderr that the condition vocabulary is derived from.
# ---------------------------------------------------------------------------
$script:CfvAzInvoker = {
    param([string]$Rg, [string]$Vm, [string]$ScriptFile, [string]$ErrFile)
    $out = & cmd.exe /c "az vm run-command invoke -g $Rg -n $Vm --command-id RunPowerShellScript --scripts `"@$ScriptFile`" -o json 2>`"$ErrFile`""
    @{
        Stdout   = ($out | Out-String)
        ExitCode = $LASTEXITCODE
        Stderr   = $(if (Test-Path $ErrFile) { Get-Content $ErrFile -Raw } else { '' })
    }
}

function Set-CfvAzInvoker {
<# Replace the dispatch primitive. FOR THE SELF-TEST ONLY. A run that calls this
   is not measuring a VM and must never report a product verdict. #>
    param([Parameter(Mandatory)][scriptblock]$Invoker)
    $script:CfvAzInvoker = $Invoker
}
$script:CfvAzInvokerReal = $script:CfvAzInvoker
function Reset-CfvAzInvoker { $script:CfvAzInvoker = $script:CfvAzInvokerReal }

# ---------------------------------------------------------------------------
# Run identity
# ---------------------------------------------------------------------------

function New-CfvRun {
<#
  Mints a run identity and the local evidence directory for it. The RunId is
  stable for the whole cycle and appears in: the on-VM directory name, the
  scheduled task's arguments, every job name, every dispatch nonce and every
  local evidence filename -- so a file found anywhere can be traced to the run
  that produced it, which was the whole complaint about C:\cfv.
#>
    param(
        [Parameter(Mandatory)][string]$Vm,
        [Parameter(Mandatory)][string]$ResourceGroup,
        [string]$Root = $script:CfvDefaultRoot,
        [string]$OutDir,
        [string]$Label = ''
    )
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmss')
    $rand  = -join ((1..4) | ForEach-Object { '0123456789abcdef'[(Get-Random -Maximum 16)] })
    $id    = if ($Label) { "$Vm-$Label-$stamp-$rand" } else { "$Vm-$stamp-$rand" }
    if (-not $OutDir) {
        $OutDir = Join-Path (Split-Path -Parent $PSCommandPath) "diag\$id"
    }
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    $scratch = Join-Path $env:TEMP "cfv-$id"
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null

    [pscustomobject]@{
        RunId         = $id
        Vm            = $Vm
        ResourceGroup = $ResourceGroup
        Root          = $Root
        RunDir        = "$Root\$id"
        JobDir        = "$Root\$id\jobs"
        WslJobDir     = "$Root\$id\wsljobs"
        OutDir        = $OutDir
        Scratch       = $scratch
        StartedUtc    = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        BuildMachine  = $env:COMPUTERNAME
    }
}

function Write-CfvOwnerStamp {
<#
  Drops _owner.json into the run directory on the box. This is what makes a
  stray directory on a reused box attributable instead of anonymous, and it is
  what Get-CfvRunsOnBox reads back.
#>
    param([Parameter(Mandatory)]$Run)
    $json = ([ordered]@{
        RunId        = $Run.RunId
        Vm           = $Run.Vm
        BuildMachine = $Run.BuildMachine
        StartedUtc   = $Run.StartedUtc
        Driver       = $PSCommandPath
    } | ConvertTo-Json -Compress)
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    Invoke-CfvBox -Run $Run -Name 'ownerstamp' -Body @"
New-Item -ItemType Directory -Path '$($Run.JobDir)' -Force | Out-Null
New-Item -ItemType Directory -Path '$($Run.WslJobDir)' -Force | Out-Null
New-Item -ItemType Directory -Path '$($Run.RunDir)\evidence' -Force | Out-Null
[IO.File]::WriteAllBytes('$($Run.RunDir)\_owner.json', [Convert]::FromBase64String('$b64'))
Write-Output "OWNER_STAMPED=`$((Get-Item '$($Run.RunDir)\_owner.json').Length)"
"@
}

function Get-CfvRunsOnBox {
<#
  Enumerates every run directory on the box with its owner stamp. Answers the
  question the flat C:\cfv could not: what else has been done to this machine,
  and by whom. A second run over a box that has already been run is not the same
  measurement as the first, and this is how a driver finds that out BEFORE it
  measures rather than after.
#>
    param([Parameter(Mandatory)]$Run)
    Invoke-CfvBox -Run $Run -Name 'runcensus' -Body @"
`$root = '$($Run.Root)'
if (-not (Test-Path `$root)) { Write-Output 'RUNS_PRESENT=0'; return }
`$dirs = @(Get-ChildItem `$root -Directory -ErrorAction SilentlyContinue)
Write-Output "RUNS_PRESENT=`$(`$dirs.Count)"
foreach (`$d in `$dirs) {
    `$o = Join-Path `$d.FullName '_owner.json'
    if (Test-Path `$o) { Write-Output "RUN `$(`$d.Name) owner=`$((Get-Content `$o -Raw) -replace '\s+',' ')" }
    else               { Write-Output "RUN `$(`$d.Name) owner=UNSTAMPED -- predates the scoped harness or was written by something else" }
}
Write-Output "LEGACY_CFV_LOOSE_FILES=`$(@(Get-ChildItem 'C:\cfv' -File -ErrorAction SilentlyContinue).Count)"
"@
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

function Invoke-CfvBox {
<#
  ONE az vm run-command invoke. Never two concurrently.

  The payload goes to a FILE and is passed as @file, because az on Windows is
  az.cmd and cmd.exe re-parses an inline --scripts argument. Both streams are
  read and the exit code is checked.

  Every payload gets a tail sentinel appended. Its absence from the returned text
  is the ONLY reliable evidence that the output did not arrive whole, because az
  exits zero either way. -NoSentinel exists for the one caller that measures where
  the limit is and must therefore be able to dispatch without one.
#>
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Body,
        [switch]$NoSentinel,
        [int]$ConflictRetries = 10,
        [int]$ConflictWaitSeconds = 30,
        [switch]$Quiet
    )
    # HEAD SENTINEL AND TAIL SENTINEL. Both, and the head one is the load-bearing
    # half.
    #
    # This library originally carried only a tail sentinel, on the reasoning that
    # a reply missing its last line had not arrived whole. MEASURED ON cfv-192,
    # that reasoning is exactly backwards for this channel: az vm run-command
    # keeps the LAST 4096 BYTES and silently discards everything before them. A
    # payload emitting 900 numbered lines came back as 78 of them, beginning
    # mid-word at "INE00822" and running to LINE00900 -- so the tail sentinel
    # survived every truncation and the detector reported Ok on a reply that had
    # lost 91% of its content.
    #
    # That is a FALSE PASS produced by the instrument built to prevent one, which
    # is the worst outcome available to this harness. The head sentinel closes it:
    # truncation destroys the FRONT, so a missing CFV_BOF is positive evidence of
    # it. The tail sentinel is kept because it still catches the other failure --
    # a payload that died before reaching its own last line.
    #
    # Note also that the real limit is 4096 bytes, not the "roughly 16 KB" the
    # v1.4.5 close-out recorded. A bound inherited from a close-out is a guess;
    # Measure-CfvOutputLimit measures it.
    $nonce   = "$($Run.RunId)-$Name-" + (-join ((1..6) | ForEach-Object { '0123456789abcdef'[(Get-Random -Maximum 16)] }))
    $payload = if ($NoSentinel) { $Body }
               else { "Write-Output `"CFV_BOF:$nonce`"`r`n" + $Body + "`r`nWrite-Output `"CFV_EOF:$nonce`"`r`n" }
    $f       = Join-Path $Run.Scratch "$Name.ps1"
    [IO.File]::WriteAllText($f, $payload, (New-Object Text.UTF8Encoding($false)))

    $attempt = 0
    while ($true) {
        $attempt++
        if (-not $Quiet) { Write-Host "---- dispatch: $Name (attempt $attempt) ----" -ForegroundColor Cyan }
        $sw  = [Diagnostics.Stopwatch]::StartNew()
        $err = Join-Path $Run.Scratch "$Name.azerr.txt"
        # Do NOT use *>&1 here: under a caller running with EAP=Stop that turns
        # az's stderr chatter into a terminating error. Redirect stderr to a file
        # and read it, which is also what makes a Conflict detectable at all.
        $inv = & $script:CfvAzInvoker $Run.ResourceGroup $Run.Vm $f $err
        $raw = $inv.Stdout
        $rc  = $inv.ExitCode
        $stderrText = "$($inv.Stderr)"
        $elapsed = [int]$sw.Elapsed.TotalSeconds
        if (-not $Quiet) { Write-Host "az exit=$rc elapsed=${elapsed}s" }

        if ($rc -ne 0) {
            # A run-command already in flight on this VM. TaskStop does not cancel
            # one, so the only correct response is to let the queue drain and then
            # READ what the interrupted dispatch left. This is a condition of the
            # channel, never a result about the product.
            if ($stderrText -match '(?i)conflict|another operation|operation is in progress|is in progress') {
                if ($attempt -le $ConflictRetries) {
                    if (-not $Quiet) { Write-Host "  a prior run-command is still in flight; waiting ${ConflictWaitSeconds}s and re-dispatching (this is a channel condition, not a result)" -ForegroundColor Yellow }
                    Start-Sleep -Seconds $ConflictWaitSeconds
                    continue
                }
                return New-CfvResult -Condition 'DispatchConflict' -Name $Name -Nonce $nonce -AzExit $rc -Text '' -Stderr $stderrText -Elapsed $elapsed
            }
            if ($stderrText -match '(?i)not found|deallocated|VM.*not running|is not currently|ResourceNotFound') {
                return New-CfvResult -Condition 'BoxUnreachable' -Name $Name -Nonce $nonce -AzExit $rc -Text '' -Stderr $stderrText -Elapsed $elapsed
            }
            return New-CfvResult -Condition 'DispatchFailed' -Name $Name -Nonce $nonce -AzExit $rc -Text '' -Stderr $stderrText -Elapsed $elapsed
        }

        $text = ''
        try {
            $o = ($raw | Out-String) | ConvertFrom-Json
            $text = (($o.value | ForEach-Object { $_.message }) -join "`n")
        } catch {
            return New-CfvResult -Condition 'PayloadDied' -Name $Name -Nonce $nonce -AzExit $rc -Text ($raw | Out-String) -Stderr "could not parse az json: $($_.Exception.Message)" -Elapsed $elapsed
        }

        if ($NoSentinel) {
            return New-CfvResult -Condition 'Ok' -Name $Name -Nonce $nonce -AzExit $rc -Text $text -Stderr $stderrText -Elapsed $elapsed
        }

        $bof = $text -match [regex]::Escape("CFV_BOF:$nonce")
        $eof = $text -match [regex]::Escape("CFV_EOF:$nonce")

        if ($bof -and $eof) {
            if (-not $Quiet) { foreach ($line in ($text -split "`n")) { Write-Host $line } }
            return New-CfvResult -Condition 'Ok' -Name $Name -Nonce $nonce -AzExit $rc -Text $text -Stderr $stderrText -Elapsed $elapsed
        }

        # The three ways a reply arrives incomplete, NAMED SEPARATELY because they
        # need different responses and guessing between them has cost this project
        # whole runs.
        #
        #   head gone, tail present  -> the channel truncated. Retrieve in chunks.
        #   head present, tail gone  -> the payload died before its last line.
        #                               Read the runner log / stderr.
        #   both gone                -> nothing recognisable came back at all.
        $cond   = if     ($eof -and -not $bof) { 'OutputTruncated' }
                  elseif ($bof -and -not $eof) { 'PayloadDied' }
                  else                          { 'PayloadDied' }
        $why    = if     ($eof -and -not $bof) { "the channel discarded the FRONT of this reply -- $($text.Length) bytes came back and the head sentinel is gone. az vm run-command keeps only the last 4096 bytes. Retrieve in bounded chunks instead." }
                  elseif ($bof -and -not $eof) { "the payload did not reach its own last line -- it died early. Read stderr and the runner log; a probe that dies early is invisible in a transcript by construction." }
                  else                          { "neither sentinel came back: nothing recognisable arrived ($($text.Length) bytes)." }
        if (-not $Quiet) {
            Write-Host "  INCOMPLETE REPLY after az exit 0. bof=$bof eof=$eof bytes=$($text.Length) -> $cond" -ForegroundColor Red
            Write-Host "  $why" -ForegroundColor Red
            Write-Host "  This is NOT an empty result and NOT a clean one. Do not read it as either." -ForegroundColor Red
        }
        return New-CfvResult -Condition $cond -Name $Name -Nonce $nonce -AzExit $rc -Text $text -Stderr ($stderrText + " | " + $why) -Elapsed $elapsed
    }
}

function Test-CfvWslTextMatch {
<#
  Match a string against wsl.exe output. Do NOT use a plain -match for this.

  wsl.exe writes ITS OWN messages in UTF-16LE while a distro's stdout is UTF-8.
  Read through the console's 8-bit encoding, the UTF-16 half arrives with a NUL
  after every character, which surfaces as \0 or as a space depending on the
  transport. So `$out -match 'WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED'` returns FALSE
  against output that literally reads

      W S L _ E _ L O C A L _ S Y S T E M _ N O T _ S U P P O R T E D

  Measured on cfv-192 at 19:41 on 2026-09-01: the control fired on the box and
  the driver reported that it had not. The measurement was right and the reader
  was wrong.

  This one failed SAFE -- it under-reported a control. The same defect on an
  assertion looking for a SUCCESS string fails UNSAFE, which is why it is fixed
  as a class here rather than at the one call site that showed it.
#>
    param([string]$Haystack, [string]$Needle)
    if ([string]::IsNullOrEmpty($Haystack)) { return $false }
    if ($Haystack -match [regex]::Escape($Needle)) { return $true }
    $h = $Haystack -replace "`0", ''
    if ($h -match [regex]::Escape($Needle)) { return $true }
    # One optional space or NUL between every character.
    $pat = ($Needle.ToCharArray() | ForEach-Object { [regex]::Escape([string]$_) }) -join '[\s\x00]?'
    return ($h -match $pat)
}

function New-CfvResult {
    param(
        [Parameter(Mandatory)][ValidateSet('Ok','DispatchFailed','DispatchConflict','OutputTruncated',
                                           'PayloadDied','BoxUnreachable','RunnerDead','RunnerIdle',
                                           'JobRunning','JobDone','Timeout','RunnerAbsent')]
        [string]$Condition,
        [string]$Name = '', [string]$Nonce = '', [int]$AzExit = -1,
        [string]$Text = '', [string]$Stderr = '', [int]$Elapsed = 0, $Extra = $null
    )
    [pscustomobject]@{
        Condition = $Condition
        Ok        = ($Condition -eq 'Ok' -or $Condition -eq 'JobDone')
        Name      = $Name
        Nonce     = $Nonce
        AzExit    = $AzExit
        Text      = $Text
        Bytes     = $Text.Length
        Stderr    = $Stderr
        ElapsedS  = $Elapsed
        Extra     = $Extra
    }
}

# ---------------------------------------------------------------------------
# Jobs
# ---------------------------------------------------------------------------

function Start-CfvJob {
<# Drops a job file into the run's own job directory. #>
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$JobBody,
        # Route to the wsljobs queue, which only the Interactive clawadmin runner
        # services. A WSL job on a box with no session is then VISIBLY unserviced
        # rather than queued behind a SYSTEM runner that could never execute it.
        [switch]$Wsl
    )
    $qd = if ($Wsl) { $Run.WslJobDir } else { $Run.JobDir }
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($JobBody))
    Invoke-CfvBox -Run $Run -Name "drop-$Name" -Body @"
New-Item -ItemType Directory -Path '$qd' -Force | Out-Null
Remove-Item '$qd\$Name.done','$qd\$Name.out','$qd\$Name.stdout','$qd\$Name.stderr' -Force -ErrorAction SilentlyContinue
[IO.File]::WriteAllBytes('$qd\$Name.job.ps1', [Convert]::FromBase64String('$b64'))
Write-Output "JOB_DROPPED_BYTES=`$((Get-Item '$qd\$Name.job.ps1').Length)"
`$hb = '$qd\_runner.heartbeat'
Write-Output "HEARTBEAT=`$(if (Test-Path `$hb) { (Get-Content `$hb -Raw).Trim() } else { 'ABSENT' })"
"@
}

function Get-CfvJobStatus {
<#
  ONE poll. Asks ONLY for the barrier and the liveness facts -- never for the
  .out. That is defect 2's fix at the call site: a poller that returned a 16.6 KB
  .out blew the run-command output limit and came back empty with az still
  exiting zero, showing nothing for forty minutes while the .done barrier had
  existed the whole time.

  The reply is a handful of key=value lines and can never approach the limit, and
  it still carries the sentinel so that even THIS cannot come back silently short.
#>
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][string]$Name, [int]$StaleSeconds = 90, [switch]$Wsl)
    $qd   = if ($Wsl) { $Run.WslJobDir }        else { $Run.JobDir }
    $task = if ($Wsl) { 'CFV-Runner-User' }     else { 'CFV-Runner-System' }
    $r = Invoke-CfvBox -Run $Run -Name "poll-$Name" -Quiet -Body @"
`$jd = '$qd'
Write-Output "DONE=`$(Test-Path "`$jd\$Name.done")"
Write-Output "JOBFILE=`$(Test-Path "`$jd\$Name.job.ps1")"
Write-Output "OUTBYTES=`$(if (Test-Path "`$jd\$Name.out") { (Get-Item "`$jd\$Name.out").Length } else { 0 })"
Write-Output "STDOUTBYTES=`$(if (Test-Path "`$jd\$Name.stdout") { (Get-Item "`$jd\$Name.stdout").Length } else { 0 })"
Write-Output "STDERRBYTES=`$(if (Test-Path "`$jd\$Name.stderr") { (Get-Item "`$jd\$Name.stderr").Length } else { 0 })"
Write-Output "HBBYTES=`$(if (Test-Path "`$jd\_runner.heartbeat") { (Get-Item "`$jd\_runner.heartbeat").Length } else { -1 })"
Write-Output "HEARTBEAT=`$(if (-not (Test-Path "`$jd\_runner.heartbeat")) { 'ABSENT' } elseif ((Get-Item "`$jd\_runner.heartbeat").Length -eq 0) { 'EMPTY' } else { ((Get-Content "`$jd\_runner.heartbeat" -Raw) + '').Trim() })"
Write-Output "NOWUTC=`$((Get-Date).ToUniversalTime().ToString('s'))Z"
Write-Output "TASKSTATE=`$(try { (Get-ScheduledTask -TaskName '$task' -ErrorAction Stop).State } catch { 'NO-TASK' })"
"@
    if ($r.Condition -ne 'Ok') { return $r }

    $kv = @{}
    foreach ($line in ($r.Text -split "`r?`n")) {
        if ($line -match '^([A-Z_]+)=(.*)$') { $kv[$Matches[1]] = $Matches[2].Trim() }
    }

    if ($kv['DONE'] -eq 'True') {
        return New-CfvResult -Condition 'JobDone' -Name $Name -Text $r.Text -Extra $kv
    }

    # Heartbeat age, computed against the BOX's clock rather than this machine's,
    # so a clock skew between build machine and VM cannot manufacture a dead runner.
    $age = $null
    $hb  = "$($kv['HEARTBEAT'])"
    if ($hb -and $hb -ne 'ABSENT' -and $hb -match '^(\S+Z)' -and $kv['NOWUTC']) {
        try { $age = [int]([datetime]::Parse($kv['NOWUTC']) - [datetime]::Parse($Matches[1])).TotalSeconds } catch { }
    }
    $kv['HEARTBEAT_AGE_S'] = "$age"

    # RunnerAbsent and RunnerDead are DIFFERENT conditions and collapsing them is
    # how "this needs a logon and there isn't one" gets reported as "the runner
    # crashed". A heartbeat that has NEVER existed on a queue whose task is not
    # running is an unmet precondition; a heartbeat that existed and went stale is
    # a dead runner. Only the second is a fault.
    # An EMPTY heartbeat under a RUNNING task is neither absent nor stale: the
    # runner is alive and its stamping is broken. Measured on cfv-192, where a
    # -f precedence bug in the runner produced a zero-byte file and the driver
    # reported RunnerDead against a perfectly live runner. Named separately so
    # the next occurrence points at the stamper rather than at the box.
    if ($hb -eq 'EMPTY' -or ($hb -ne 'ABSENT' -and [string]::IsNullOrWhiteSpace($hb))) {
        return New-CfvResult -Condition 'RunnerDead' -Name $Name -Text $r.Text -Extra $kv `
                 -Stderr "the heartbeat file exists but is EMPTY ($($kv['HBBYTES']) bytes) while the task state is '$($kv['TASKSTATE'])'. This is a BROKEN STAMPER, not necessarily a dead runner -- read the runner log before concluding the box is gone."
    }
    if ($hb -eq 'ABSENT' -and $kv['TASKSTATE'] -ne 'Running') {
        return New-CfvResult -Condition 'RunnerAbsent' -Name $Name -Text $r.Text -Extra $kv `
                 -Stderr "no runner has ever beaten on this queue and its task state is '$($kv['TASKSTATE'])'. For the WSL queue this means there is no interactive session, which is an unmet PRECONDITION and never a product verdict."
    }
    if ($hb -eq 'ABSENT' -or $null -eq $age -or $age -gt $StaleSeconds) {
        return New-CfvResult -Condition 'RunnerDead' -Name $Name -Text $r.Text -Extra $kv
    }
    if ($hb -match "state=running\s+job=$([regex]::Escape($Name))\b") {
        return New-CfvResult -Condition 'JobRunning' -Name $Name -Text $r.Text -Extra $kv
    }
    # Runner alive, job file present, but the runner is not on it. Either it is
    # working through an earlier job or it is not seeing this one. Both are
    # "alive but not doing what I asked", which the old poller could not say.
    return New-CfvResult -Condition 'RunnerIdle' -Name $Name -Text $r.Text -Extra $kv
}

function Wait-CfvJob {
<#
  Polls to the barrier, reporting the CONDITION at every transition rather than
  printing dots. Returns the last status; the caller reads .Condition.

  The five outcomes are distinct and none of them is null:
    JobDone      .done exists. Retrieve the .out with Receive-CfvJobOutput.
    RunnerDead   the box answers but the heartbeat is stale or absent.
    RunnerIdle   the runner is alive and is not executing this job.
    BoxUnreachable / DispatchFailed / DispatchConflict from the channel.
    Timeout      the deadline passed. Read the .out before concluding anything;
                 a probe that dies early is invisible in the transcript.
#>
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][string]$Name,
        [int]$Minutes = 60,
        [int]$IntervalSeconds = 60,
        [int]$StaleSeconds = 90,
        [int]$DeadTolerance = 2,
        [switch]$Wsl
    )
    $deadline = (Get-Date).AddMinutes($Minutes)
    $deadStreak = 0
    $last = $null
    while ((Get-Date) -lt $deadline) {
        $st = Get-CfvJobStatus -Run $Run -Name $Name -StaleSeconds $StaleSeconds -Wsl:$Wsl
        $last = $st
        $hb = if ($st.Extra) { $st.Extra['HEARTBEAT'] } else { '' }
        Write-Host ("  [{0}] {1,-16} hb={2}" -f (Get-Date -Format 'HH:mm:ss'), $st.Condition, $hb)

        switch ($st.Condition) {
            'JobDone' { Write-Host "  job '$Name' reached its .done barrier." -ForegroundColor Green; return $st }
            'RunnerDead' {
                # One stale reading can be a dispatch landing mid-write. Two in a
                # row on a box that is answering is a dead runner, and that is a
                # different condition from a slow job -- which is the whole point
                # of the heartbeat and the thing the old runner could not deliver.
                $deadStreak++
                if ($deadStreak -ge $DeadTolerance) {
                    Write-Host "  RUNNER DEAD: the box answers but the heartbeat is stale ($($st.Extra['HEARTBEAT_AGE_S'])s). This is NOT a slow job." -ForegroundColor Red
                    return $st
                }
            }
            default { $deadStreak = 0 }
        }
        if ($st.Condition -eq 'RunnerAbsent') {
            Write-Host "  RUNNER ABSENT on this queue: $($st.Stderr)" -ForegroundColor Yellow
            return $st
        }
        if ($st.Condition -in @('BoxUnreachable','DispatchConflict','DispatchFailed')) {
            Write-Host "  channel condition '$($st.Condition)' -- this says nothing about the product." -ForegroundColor Yellow
            if ($st.Condition -eq 'BoxUnreachable') { return $st }
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
    Write-Host "  job '$Name' did not complete within $Minutes minutes. READ THE .out BEFORE CONCLUDING ANYTHING." -ForegroundColor Red
    return (New-CfvResult -Condition 'Timeout' -Name $Name -Text $(if ($last) { $last.Text } else { '' }) -Extra $(if ($last) { $last.Extra } else { $null }))
}

function Receive-CfvJobOutput {
<#
  Retrieves a job's .out in BOUNDED CHUNKS and asserts the reassembled length
  against the length the box reported. That assertion is the point: it is what
  turns "the transfer was silently short" into a failure rather than into a
  shorter transcript that reads as complete.
#>
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][string]$Name,
        # 2048 RAW bytes, because base64 expands 4/3 and the whole reply must fit
        # under the channel's MEASURED 4096-byte ceiling alongside both sentinels
        # and the CHUNK_OFFSET line. The previous default of 6000 exceeded the
        # ceiling on its own, so every chunk of a large .out was head-truncated;
        # only the reassembled-byte-count assertion below caught it.
        [int]$ChunkBytes = 2048,
        [int]$MaxChunks = 400,
        [switch]$Wsl
    )
    $qd = if ($Wsl) { $Run.WslJobDir } else { $Run.JobDir }
    $sizeR = Invoke-CfvBox -Run $Run -Name "size-$Name" -Quiet -Body @"
Write-Output "OUTBYTES=`$(if (Test-Path '$qd\$Name.out') { (Get-Item '$qd\$Name.out').Length } else { -1 })"
"@
    if ($sizeR.Condition -ne 'Ok') { return $sizeR }
    if ($sizeR.Text -notmatch 'OUTBYTES=(-?\d+)') {
        return (New-CfvResult -Condition 'PayloadDied' -Name $Name -Text $sizeR.Text -Stderr 'size probe returned no OUTBYTES line')
    }
    $total = [int]$Matches[1]
    if ($total -lt 0) {
        return (New-CfvResult -Condition 'PayloadDied' -Name $Name -Text '' -Stderr "no .out file for job '$Name' on the box")
    }
    Write-Host "  retrieving $Name.out: $total bytes in chunks of $ChunkBytes" -ForegroundColor DarkGray

    $sb = New-Object Text.StringBuilder
    $offset = 0; $chunks = 0
    while ($offset -lt $total -and $chunks -lt $MaxChunks) {
        $chunks++
        $r = Invoke-CfvBox -Run $Run -Name "chunk$chunks-$Name" -Quiet -Body @"
`$fs = [IO.File]::OpenRead('$qd\$Name.out')
try {
    `$fs.Position = $offset
    `$buf = New-Object byte[] $ChunkBytes
    `$n = `$fs.Read(`$buf, 0, $ChunkBytes)
    Write-Output "CHUNK_OFFSET=$offset CHUNK_READ=`$n"
    Write-Output '---8<---'
    Write-Output ([Convert]::ToBase64String(`$buf, 0, `$n))
} finally { `$fs.Dispose() }
"@
        if ($r.Condition -ne 'Ok') { return $r }
        # Take everything after the marker, then remove the tail sentinel line.
        # A bare (\S+) capture can match the sentinel itself once the payload is
        # empty, which turns "the chunk came back with nothing in it" into a
        # base64 parse error several lines away from its cause.
        $idx = $r.Text.IndexOf('---8<---')
        if ($idx -lt 0) {
            return (New-CfvResult -Condition 'PayloadDied' -Name $Name -Text $r.Text -Stderr "chunk $chunks returned no payload marker")
        }
        $b64 = ($r.Text.Substring($idx + 8) -replace 'CFV_EOF:\S+', '') -replace '\s', ''
        if ([string]::IsNullOrEmpty($b64)) {
            return (New-CfvResult -Condition 'OutputTruncated' -Name $Name -Text $sb.ToString() `
                     -Stderr "chunk $chunks came back empty at offset $offset of $total; the channel returned less than the box holds")
        }
        # A chunk that will not decode is a channel condition, not an exception.
        # Left to throw, it surfaces as a base64 error inside the library rather
        # than as "this transfer did not arrive whole", which is what it is.
        try { $bytes = [Convert]::FromBase64String($b64) }
        catch {
            return (New-CfvResult -Condition 'OutputTruncated' -Name $Name -Text $sb.ToString() `
                     -Stderr "chunk $chunks did not decode at offset $offset of $total ($($b64.Length) chars): $($_.Exception.Message)")
        }
        [void]$sb.Append([Text.Encoding]::UTF8.GetString($bytes))
        $offset += $bytes.Length
        if ($bytes.Length -eq 0) { break }
    }

    $text = $sb.ToString()
    $local = Join-Path $Run.OutDir "$Name.out.txt"
    [IO.File]::WriteAllText($local, $text, (New-Object Text.UTF8Encoding($false)))

    # THE ASSERTION. Byte counts, not character counts: the box reported bytes.
    $got = [Text.Encoding]::UTF8.GetByteCount($text)
    if ($got -ne $total) {
        Write-Host "  SHORT TRANSFER: reassembled $got bytes, the box reported $total. Do not read this as the job's output." -ForegroundColor Red
        return (New-CfvResult -Condition 'OutputTruncated' -Name $Name -Text $text -Stderr "reassembled $got of $total bytes in $chunks chunks" -Extra @{ Path = $local })
    }
    Write-Host "  retrieved $got bytes to $local (byte count confirmed against the box)" -ForegroundColor Green
    return (New-CfvResult -Condition 'Ok' -Name $Name -Text $text -Extra @{ Path = $local; Bytes = $got })
}

# ---------------------------------------------------------------------------
# Reboot
# ---------------------------------------------------------------------------

function Restart-CfvBox {
<#
  Restarts the VM and waits on STATE, never on a sleep, then discriminates the
  three things that used to look alike after a reboot:

     the box did not come back            -> BoxUnreachable
     the box came back, the runner did not -> RunnerDead
     both came back                        -> Ok

  It proves the reboot happened by reading LastBootUpTime either side rather than
  asserting it, because a restart that silently did not happen leaves every later
  "survived the reboot" row measuring nothing.
#>
    param(
        [Parameter(Mandatory)]$Run,
        [int]$WaitMinutes = 20,
        [int]$RunnerGraceSeconds = 300
    )
    $before = Invoke-CfvBox -Run $Run -Name 'boot-before' -Quiet -Body @'
$os = Get-CimInstance Win32_OperatingSystem
Write-Output "LASTBOOT=$($os.LastBootUpTime.ToUniversalTime().ToString('s'))Z"
Write-Output "UPTIME_S=$([int]((Get-Date) - $os.LastBootUpTime).TotalSeconds)"
'@
    if ($before.Condition -ne 'Ok') { return $before }
    $bootBefore = if ($before.Text -match 'LASTBOOT=(\S+)') { $Matches[1] } else { '' }
    Write-Host "  boot before restart: $bootBefore" -ForegroundColor DarkGray

    & cmd.exe /c "az vm restart -g $($Run.ResourceGroup) -n $($Run.Vm) -o none" | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        return (New-CfvResult -Condition 'DispatchFailed' -Name 'restart' -AzExit $rc -Stderr "az vm restart exited $rc")
    }
    Write-Host "  az vm restart exit=0; waiting on the box to answer again" -ForegroundColor DarkGray

    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    $bootAfter = ''
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 30
        $p = Invoke-CfvBox -Run $Run -Name 'boot-after' -Quiet -Body @'
$os = Get-CimInstance Win32_OperatingSystem
Write-Output "LASTBOOT=$($os.LastBootUpTime.ToUniversalTime().ToString('s'))Z"
Write-Output "UPTIME_S=$([int]((Get-Date) - $os.LastBootUpTime).TotalSeconds)"
'@
        if ($p.Condition -eq 'Ok' -and $p.Text -match 'LASTBOOT=(\S+)') {
            $bootAfter = $Matches[1]
            if ($bootAfter -ne $bootBefore) { break }
            Write-Host "  box answers but LastBootUpTime is unchanged -- the restart has not landed yet" -ForegroundColor DarkGray
        } else {
            Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] box not answering yet ($($p.Condition))" -ForegroundColor DarkGray
        }
    }
    if (-not $bootAfter -or $bootAfter -eq $bootBefore) {
        return (New-CfvResult -Condition 'BoxUnreachable' -Name 'restart' `
                 -Stderr "the box did not come back within $WaitMinutes minutes, or came back without rebooting (before=$bootBefore after=$bootAfter)" `
                 -Extra @{ BootBefore = $bootBefore; BootAfter = $bootAfter })
    }
    Write-Host "  REBOOT PROVED: $bootBefore -> $bootAfter" -ForegroundColor Green

    # Now the separate claim: did the runner come back on its own?
    $graceEnd = (Get-Date).AddSeconds($RunnerGraceSeconds)
    while ((Get-Date) -lt $graceEnd) {
        $hb = Invoke-CfvBox -Run $Run -Name 'hb-after' -Quiet -Body @"
`$p = '$($Run.JobDir)\_runner.heartbeat'
Write-Output "HEARTBEAT=`$(if (Test-Path `$p) { (Get-Content `$p -Raw).Trim() } else { 'ABSENT' })"
Write-Output "NOWUTC=`$((Get-Date).ToUniversalTime().ToString('s'))Z"
Write-Output "TASKSTATE=`$(try { (Get-ScheduledTask -TaskName 'CFV-Runner' -ErrorAction Stop).State } catch { 'NO-TASK' })"
Write-Output "TASKLAST=`$(try { (Get-ScheduledTaskInfo -TaskName 'CFV-Runner' -ErrorAction Stop).LastTaskResult } catch { 'NO-TASK' })"
"@
        if ($hb.Condition -eq 'Ok' -and $hb.Text -match 'HEARTBEAT=(\S+Z)' -and $hb.Text -match 'NOWUTC=(\S+)') {
            $hbT = ([regex]::Match($hb.Text,'HEARTBEAT=(\S+Z)')).Groups[1].Value
            $now = ([regex]::Match($hb.Text,'NOWUTC=(\S+)')).Groups[1].Value
            try {
                $age = [int]([datetime]::Parse($now) - [datetime]::Parse($hbT)).TotalSeconds
                if ($age -lt 90) {
                    Write-Host "  RUNNER RESTARTED ITSELF: heartbeat ${age}s old after the reboot, with no interactive login." -ForegroundColor Green
                    return (New-CfvResult -Condition 'Ok' -Name 'restart' -Text $hb.Text `
                             -Extra @{ BootBefore = $bootBefore; BootAfter = $bootAfter; HeartbeatAgeS = $age })
                }
            } catch { }
        }
        Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] box up, runner not yet beating" -ForegroundColor DarkGray
        Start-Sleep -Seconds 20
    }
    return (New-CfvResult -Condition 'RunnerDead' -Name 'restart' `
             -Stderr "the box came back ($bootBefore -> $bootAfter) but the runner did not restart within ${RunnerGraceSeconds}s. These are different conditions and this is the second one." `
             -Extra @{ BootBefore = $bootBefore; BootAfter = $bootAfter })
}

# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------

function Publish-CfvFile {
<#
  Uploads a local file to the validation container and CONFIRMS IT AT THE SERVICE
  before saying anything succeeded.

  This is defect 4's fix. A SAS expiry built from local time and labelled Z made
  ten uploads return AuthenticationFailed, and the script printed "uploaded
  <file>" for every one of them because the success line sat unconditionally
  after the call. The rule this encodes: the sentence that reports an outcome is
  emitted by the check, not by the code path.
#>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$StorageAccount,
        [Parameter(Mandatory)][string]$AccountKey,
        [string]$Container = 'validation',
        [string]$BlobName
    )
    if (-not (Test-Path $Path)) { return [pscustomobject]@{ Ok = $false; Reason = "local file absent: $Path" } }
    if (-not $BlobName) { $BlobName = [IO.Path]::GetFileName($Path) }
    $localLen = (Get-Item $Path).Length

    & cmd.exe /c "az storage blob upload --account-name $StorageAccount --account-key $AccountKey --container-name $Container --name $BlobName --file `"$Path`" --overwrite --output none" | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        Write-Host "  UPLOAD FAILED: $BlobName (az exit $rc)" -ForegroundColor Red
        return [pscustomobject]@{ Ok = $false; Reason = "az storage blob upload exited $rc"; Blob = $BlobName }
    }

    # The independent read-back. az exiting zero is the claim that the command
    # ran; this is the claim that the bytes are there.
    $remote = & cmd.exe /c "az storage blob show --account-name $StorageAccount --account-key $AccountKey --container-name $Container --name $BlobName --query properties.contentLength -o tsv"
    $rc2 = $LASTEXITCODE
    $remote = "$remote".Trim()
    if ($rc2 -ne 0 -or "$remote" -ne "$localLen") {
        Write-Host "  UPLOAD NOT CONFIRMED: $BlobName landed '$remote', expected $localLen (show exit $rc2)" -ForegroundColor Red
        return [pscustomobject]@{ Ok = $false; Reason = "service reports $remote bytes, expected $localLen"; Blob = $BlobName }
    }
    Write-Host "  uploaded $BlobName ($localLen bytes, size confirmed at the service)" -ForegroundColor DarkGray
    return [pscustomobject]@{ Ok = $true; Blob = $BlobName; Bytes = $localLen }
}

# ---------------------------------------------------------------------------
# Calibration
# ---------------------------------------------------------------------------

function Measure-CfvOutputLimit {
<#
  Determines where az vm run-command actually stops returning output on THIS
  fleet, rather than assuming the roughly-16-KB figure from the close-out.

  Dispatches payloads that print a known number of bytes and then a sentinel, and
  reports the largest size at which the sentinel still comes back. This is a
  probe calibrated against a rigged input: the correct answer for each size is
  known before it is asked.

  Run it once per fleet change. It is the only caller permitted to dispatch
  without a sentinel, and it does so only for the control half.
#>
    param([Parameter(Mandatory)]$Run, [int[]]$Sizes = @(512, 1024, 2048, 3072, 3584, 4096, 6144, 8192, 16384, 65536))
    $rows = @()
    foreach ($n in $Sizes) {
        $r = Invoke-CfvBox -Run $Run -Name "limit$n" -Quiet -Body @"
`$chunk = 'X' * 64
for (`$i = 0; `$i -lt [math]::Ceiling($n / 64); `$i++) { Write-Output `$chunk }
"@
        $rows += [pscustomobject]@{
            RequestedBytes = $n
            Condition      = $r.Condition
            ReturnedBytes  = $r.Bytes
            SentinelBack   = ($r.Condition -eq 'Ok')
        }
        Write-Host ("  {0,7} bytes requested -> {1,-16} {2,7} bytes returned, sentinel={3}" -f $n, $r.Condition, $r.Bytes, ($r.Condition -eq 'Ok'))
    }
    $lastOk  = ($rows | Where-Object SentinelBack | Select-Object -Last 1)
    $firstNo = ($rows | Where-Object { -not $_.SentinelBack } | Select-Object -First 1)
    [pscustomobject]@{
        Rows              = $rows
        LargestReturned   = if ($lastOk)  { $lastOk.RequestedBytes }  else { 0 }
        SmallestTruncated = if ($firstNo) { $firstNo.RequestedBytes } else { $null }
    }
}
