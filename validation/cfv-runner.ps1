<#
  cfv-runner.ps1 -- the on-VM job runner, run-scoped and reboot-surviving.

  This REPLACES interim-v120-runner.ps1 for new runs. That file is left in place
  because eighty files in this tree reference the C:\cfv namespace it created and
  a tree-wide rename would be a far larger change than the defect warrants; see
  docs/session_reports/2026-09-01_unattended_harness_closeout.md section 4.3.

  WHAT IS DIFFERENT, AND WHY EACH DIFFERENCE EXISTS
  -------------------------------------------------

  1. THE HEARTBEAT KEEPS BEATING WHILE A JOB RUNS.

     interim-v120-runner.ps1 stamps the heartbeat at the top of its poll loop and
     then executes the job INSIDE that loop, synchronously. So for the whole of a
     sixteen-minute install the heartbeat does not move, and "runner alive, job
     slow" is indistinguishable from "runner dead" -- which its own header says is
     the exact ambiguity it exists to prevent. interim-v146-runner.ps1 then wrote
     that freeze down as expected behaviour, which made a defect into a contract.

     Here the job is launched with Start-Process -PassThru and the runner stamps
     the heartbeat from the wait loop around it. The heartbeat is stamped from
     somewhere that keeps running, and it NAMES what it is waiting on:

         2026-09-01T12:34:56Z state=running job=install pid=4212 elapsed=931

     so the driver can tell alive-and-busy from alive-and-idle from dead, which
     are three conditions and were previously two.

  2. EVERYTHING THIS RUN TOUCHES LIVES UNDER ONE OWNED DIRECTORY.

     C:\cfv was an unscoped cross-session namespace: markers, job files and
     evidence from different runs, boxes and sessions accumulated in one directory
     with no owner and no way to tell them apart. A second run over a box that has
     already been run is not the same measurement as the first, and the old layout
     could not even tell you that it had happened.

     Every run now owns C:\cfv\runs\<RunId>\, and drops _owner.json naming the
     run, the VM, the driver that created it and when. Nothing outside that
     directory is written by this runner.

  3. STDOUT AND STDERR ARE CAPTURED SEPARATELY.

     The preamble requires reading probe stderr rather than only the phase
     transcript, because a probe that dies early is invisible in the transcript by
     construction. The old runner merged both streams with *> so there was nothing
     separate to read. Here they are two files, and .out is assembled from both at
     the end so the existing read contract is unchanged.

  4. THE .done BARRIER IS UNCHANGED, DELIBERATELY.

     .out is complete on disk before .done appears. That property was right and is
     preserved verbatim: .done is still the driver's read barrier and a partial
     .out can still never be read as a complete one.

  5. THE WINDOWS-SIDE INSTANCE SURVIVES A REBOOT BECAUSE IT NEEDS NO LOGON.

     interim-v120-runner.ps1 is started by hand from an elevated PowerShell inside
     an interactive session, so a reboot ends it and a human has to start it again.
     cfv-arm-persistence.ps1 registers this one as a SYSTEM AtStartup scheduled
     task instead, which needs no stored credential and no session.

  WHAT THIS RUNNER CANNOT DO, STATED HERE RATHER THAN DISCOVERED
  --------------------------------------------------------------
  wsl.exe refuses NT AUTHORITY\SYSTEM BY NAME -- measured on cfv-192:
  WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED, exit -1. So the SYSTEM instance can take every
  Windows-side measurement and NO WSL measurement.

  An S4U principal would have given a non-SYSTEM boot context with no credential,
  and it was tried first. It is DENIED on this build, from four paths, with two
  controls succeeding in the same run -- see cfv-arm-persistence.ps1's header for
  the measurement. So the WSL instance runs under an Interactive clawadmin
  principal and exists only while a session does.

  The consequence is stated rather than hidden: Windows-side work is unattended
  across reboots; WSL work is not, and cannot be without a credential. A WSL job
  dropped with no session leaves the wsljobs heartbeat ABSENT, which the driver
  reports as RunnerAbsent -- a NAMED PRECONDITION, and a missing precondition is
  never a product verdict.

  This runner still probes its own WSL capability once at startup, with a control,
  and records the answer in _wslcontext.json. "Not SYSTEM" and "WSL works here"
  are different claims and the second one is measured, not inferred.
#>
param(
    [Parameter(Mandatory)][string]$RunId,
    [string]$Root = 'C:\cfv\runs',
    # Which job directory this instance services.
    #
    # The SYSTEM instance takes jobs\ -- every Windows-side measurement. It comes
    # back at every boot with no logon and no credential.
    #
    # The clawadmin Interactive instance takes wsljobs\ -- anything touching
    # wsl.exe, which refuses NT AUTHORITY\SYSTEM by name. An Interactive
    # principal only runs while a session exists, so this instance cannot come
    # back on its own after a reboot.
    #
    # TWO DIRECTORIES rather than one queue with tagged jobs, so that a WSL job
    # dropped on a box with no session is VISIBLY unserviced -- the wsljobs
    # heartbeat is simply absent -- instead of sitting silently behind a runner
    # that could never have executed it.
    [string]$JobSubdir = 'jobs'
)

$ErrorActionPreference = 'Continue'

$RunDir = Join-Path $Root $RunId
$JobDir = Join-Path $RunDir $JobSubdir
foreach ($d in @($RunDir, $JobDir, (Join-Path $RunDir 'evidence'))) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}
$HeartbeatPath = Join-Path $JobDir '_runner.heartbeat'
$RunnerLog     = Join-Path $JobDir '_runner.log'

function Stamp-Heartbeat {
    <#
      Written with WriteAllText so a reader never sees a partially written line.

      BUILT BY CONCATENATION, NOT BY -f, AND THE CATCH IS NOT SILENT. Both of
      those are scar tissue from this function's first run on cfv-192.

      It was written as

          '{0} state={1} ...' -f `
              (Get-Date).ToUniversalTime().ToString('s') + 'Z', $State, ...

      and -f binds TIGHTER than +, so the format string received exactly one
      argument, threw "Index (zero based) must be ... less than the size of the
      argument list", and an empty `catch { }` swallowed it. The runner then ran
      perfectly while never stamping a heartbeat, and the driver correctly
      reported RunnerDead against a live runner -- a false negative manufactured
      by the liveness signal itself.

      A silent catch inside the one function whose purpose is to prevent silence
      is the defect this whole job is about, committed in the fix for it. So the
      failure now goes to the runner log AND to the heartbeat file, because a
      heartbeat that cannot be written must not look like a runner that is gone.
    #>
    param([string]$State, [string]$Job = '', [int]$JobPid = 0, [int]$Elapsed = 0)
    $stamp = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    $j = if ($Job) { $Job } else { '-' }
    $line = $stamp + ' state=' + $State + ' job=' + $j + ' pid=' + $JobPid + ' elapsed=' + $Elapsed + ' runid=' + $RunId
    try {
        [IO.File]::WriteAllText($HeartbeatPath, $line)
    } catch {
        $msg = 'HEARTBEAT_WRITE_FAILED: ' + $_.Exception.Message
        try { ($stamp + ' ' + $msg) | Out-File $RunnerLog -Encoding utf8 -Append } catch { }
        try { [IO.File]::WriteAllText($HeartbeatPath, ($stamp + ' state=STAMP_FAILED runid=' + $RunId)) } catch { }
    }
}

function Log([string]$m) {
    try { ('{0}Z {1}' -f (Get-Date).ToUniversalTime().ToString('s'), $m) | Out-File $RunnerLog -Encoding utf8 -Append } catch { }
}

# ---------------------------------------------------------------------------
# WSL context probe. Taken ONCE, at startup, and recorded rather than assumed.
#
# The whole reason the job-file mechanism exists is that run-command is SYSTEM and
# wsl.exe refuses LocalSystem. This runner is not SYSTEM. But "not SYSTEM" is not
# the same claim as "WSL works here", and the difference between those two claims
# is the difference between an unattended run and a false verdict, so it is
# measured rather than reasoned about.
#
# The probe carries its own control: it asserts BOTH that a trivially-true command
# succeeds AND that a command which must fail does fail. A wsl.exe that returns 0
# for everything -- or a wrapper that swallows exit codes -- would otherwise read
# as a healthy WSL.
# ---------------------------------------------------------------------------
function Test-WslTextMatch {
    <# See cfv-driverlib.ps1's Test-CfvWslTextMatch for the full reason. Short
       version: wsl.exe writes its own messages in UTF-16LE, so read through an
       8-bit console encoding they arrive with a NUL after every character and a
       plain -match fails against the exact string it is looking for. Duplicated
       here rather than shared because this file runs alone on the box. #>
    param([string]$Haystack, [string]$Needle)
    if ([string]::IsNullOrEmpty($Haystack)) { return $false }
    if ($Haystack -match [regex]::Escape($Needle)) { return $true }
    $h = $Haystack -replace "`0", ''
    if ($h -match [regex]::Escape($Needle)) { return $true }
    $pat = ($Needle.ToCharArray() | ForEach-Object { [regex]::Escape([string]$_) }) -join '[\s\x00]?'
    return ($h -match $pat)
}

function Probe-WslContext {
    $r = [ordered]@{
        RunId          = $RunId
        StampUtc       = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        WhoAmI         = ''
        SessionId      = -1
        WslExePresent  = $false
        SubjectOk      = $false      # a command that MUST succeed
        SubjectOut     = ''
        SubjectExit    = -999
        ControlFailed  = $false      # a command that MUST fail
        ControlExit    = -999
        WslOk          = $false
        Reason         = ''
    }
    try { $r.WhoAmI = (& whoami.exe 2>&1 | Out-String).Trim() } catch { }
    try { $r.SessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId } catch { }

    $wsl = Join-Path $env:SystemRoot 'System32\wsl.exe'
    $r.WslExePresent = Test-Path $wsl
    if (-not $r.WslExePresent) { $r.Reason = 'wsl.exe not present on this machine'; return $r }

    # SUBJECT: must succeed and must print the sentinel. Run through a distro so
    # this tests the thing jobs actually need, not merely that the launcher parses.
    try {
        $out = & $wsl -d Ubuntu -u root -- /bin/sh -c 'echo CFV_WSL_ALIVE' 2>&1 | Out-String
        $r.SubjectExit = $LASTEXITCODE
        $r.SubjectOut  = $out.Trim()
        $r.SubjectOk   = ($r.SubjectExit -eq 0 -and (Test-WslTextMatch $out 'CFV_WSL_ALIVE'))
    } catch { $r.SubjectOut = "threw: $($_.Exception.Message)" }

    # CONTROL: must FAIL. If this exits 0, exit codes are not propagating through
    # wsl.exe in this context and the subject's 0 means nothing.
    # The sentinel CFV_WSL_ALIVE deliberately does not appear anywhere in this
    # control, so the control cannot be satisfied by the subject's own echo.
    try {
        & $wsl -d Ubuntu -u root -- /bin/sh -c 'exit 33' 2>&1 | Out-Null
        $r.ControlExit   = $LASTEXITCODE
        $r.ControlFailed = ($r.ControlExit -eq 33)
    } catch { }

    $r.WslOk = ($r.SubjectOk -and $r.ControlFailed)
    if (-not $r.WslOk) {
        if (-not $r.SubjectOk)          { $r.Reason = "wsl subject did not succeed (exit=$($r.SubjectExit)): $($r.SubjectOut)" }
        elseif (-not $r.ControlFailed)  { $r.Reason = "wsl control did not fail (exit=$($r.ControlExit)) -- exit codes are not propagating, so the subject's 0 is not evidence" }
    }
    return $r
}

# ---------------------------------------------------------------------------

Stamp-Heartbeat -State 'starting'
Log "runner-started runid=$RunId whoami=$(try { (& whoami.exe 2>&1 | Out-String).Trim() } catch { '?' }) session=$([Diagnostics.Process]::GetCurrentProcess().SessionId)"

$ctx = Probe-WslContext
try {
    [IO.File]::WriteAllText((Join-Path $JobDir '_wslcontext.json'), ($ctx | ConvertTo-Json -Depth 4))
} catch { Log "could not write _wslcontext.json: $($_.Exception.Message)" }
Log "wslcontext WslOk=$($ctx.WslOk) subjectExit=$($ctx.SubjectExit) controlExit=$($ctx.ControlExit) reason=$($ctx.Reason)"

while ($true) {
    try {
        Stamp-Heartbeat -State 'idle'

        $pending = @(Get-ChildItem (Join-Path $JobDir '*.job.ps1') -ErrorAction SilentlyContinue | Where-Object {
            -not (Test-Path ($_.FullName -replace '\.job\.ps1$', '.done'))
        } | Sort-Object Name)

        foreach ($j in $pending) {
            $base    = $j.FullName -replace '\.job\.ps1$', ''
            $name    = [IO.Path]::GetFileName($base)
            $outPath = "$base.out"
            $soPath  = "$base.stdout"
            $sePath  = "$base.stderr"
            Remove-Item $soPath, $sePath -Force -ErrorAction SilentlyContinue

            Log "=== job $name started ==="
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $rc = 9009
            $procPid = 0
            try {
                # Start-Process, not the call operator: the runner must keep
                # executing while the job runs so the heartbeat can be stamped.
                # A child process also preserves the old runner's property that a
                # job which corrupts state or calls exit cannot take the runner
                # down with it.
                # Start-Process refuses the same file for both streams, so they
                # are captured separately and merged into .out below. That also
                # leaves a real .stderr to read, which the preamble requires and
                # the merged-stream runner could not provide.
                $p = Start-Process -FilePath 'powershell.exe' `
                        -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', $j.FullName) `
                        -RedirectStandardOutput $soPath -RedirectStandardError $sePath `
                        -WindowStyle Hidden -PassThru
                $procPid = $p.Id
                # TOUCH .Handle BEFORE WAITING. Without this, a process started
                # with -PassThru and redirected streams returns a NULL ExitCode
                # after it exits: .NET releases the process handle and the code
                # is no longer readable. Measured on cfv-192 -- p1 completed and
                # wrote RUNNER_EXITCODE= with nothing after it, which makes a job
                # that failed and a job that passed identical to the driver.
                # Reading .Handle forces the handle to be cached.
                $null = $p.Handle
                Stamp-Heartbeat -State 'running' -Job $name -JobPid $procPid -Elapsed 0

                while (-not $p.HasExited) {
                    Start-Sleep -Seconds 5
                    Stamp-Heartbeat -State 'running' -Job $name -JobPid $procPid -Elapsed ([int]$sw.Elapsed.TotalSeconds)
                }
                $p.WaitForExit()
                # An UNREADABLE exit code is not the same as exit 0, and must
                # never be emitted as an empty string that a reader can mistake
                # for either. Name it.
                if ($null -eq $p.ExitCode) { $rc = 'UNREADABLE' } else { $rc = $p.ExitCode }
            } catch {
                try { "RUNNER_CAUGHT: $($_.Exception.Message)" | Out-File $sePath -Encoding utf8 -Append } catch { }
                $rc = 9009
            }
            Stamp-Heartbeat -State 'finishing' -Job $name -JobPid $procPid -Elapsed ([int]$sw.Elapsed.TotalSeconds)

            # Assemble .out: stdout, then stderr under a header that a reader
            # cannot miss, then the exit code. .out must be COMPLETE on disk
            # before .done appears -- .done is the driver's read barrier.
            $sb = New-Object Text.StringBuilder
            foreach ($pair in @(@($soPath, ''), @($sePath, '---- STDERR ----'))) {
                if (Test-Path $pair[0]) {
                    $txt = Get-Content $pair[0] -Raw -ErrorAction SilentlyContinue
                    if ($null -ne $txt -and $txt.Length -gt 0) {
                        if ($pair[1]) { [void]$sb.AppendLine($pair[1]) }
                        [void]$sb.AppendLine($txt.TrimEnd())
                    }
                }
            }
            [void]$sb.AppendLine("RUNNER_EXITCODE=$rc")
            [void]$sb.AppendLine("RUNNER_ELAPSED_S=$([int]$sw.Elapsed.TotalSeconds)")
            try { [IO.File]::WriteAllText($outPath, $sb.ToString()) }
            catch { Log "could not write $outPath : $($_.Exception.Message)" }

            [IO.File]::WriteAllText("$base.done", "rc=$rc elapsed=$([int]$sw.Elapsed.TotalSeconds) at $((Get-Date).ToUniversalTime().ToString('s'))Z")
            Log "=== job $name done rc=$rc elapsed=$([int]$sw.Elapsed.TotalSeconds)s ==="
            Stamp-Heartbeat -State 'idle'
        }
    } catch {
        Log "RUNNER_LOOP_ERROR: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 5
}
