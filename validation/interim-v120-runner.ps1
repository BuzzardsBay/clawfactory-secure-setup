<#
  On-VM job runner for the v1.2.0 interim validation.

  WHY THIS EXISTS
  ---------------
  The JOB 3 harness (validation/job3-validate.ps1) is fire-and-forget: arm a
  wrapper.cmd, reboot into an auto-logon session, poll one sentinel, retrieve,
  tear down. That shape does not fit this job, which needs three things it
  cannot provide:

    1. A HARD CHECKPOINT after Phase 1. The driver must stop, report, and only
       then continue.
    2. A HUMAN-IN-THE-LOOP step in Phase 3. Bret RDPs into the same session and
       types the SMTP app password into the Studio panel himself, so the
       credential never enters a script, a transcript, or the driver's context.
    3. Studio GUI work driven to completion (approval card, Recently-deleted).

  All three require the interactive clawadmin session to STAY ALIVE across
  phases, and require the driver to feed it new work over time.

  WHY THE INTERACTIVE SESSION IS MANDATORY (not a convenience)
  ------------------------------------------------------------
  WSL distros are per-user. az vm run-command executes as SYSTEM, which cannot
  see a distro registered to clawadmin. Every WSL-level probe in this job must
  therefore execute inside the clawadmin session, not through run-command.
  run-command is used ONLY to drop job files and read status, never to touch WSL.

  CONTRACT
  --------
  Watches C:\cfv\jobs for <name>.job.ps1. For each job not yet done:
      - executes it, capturing stdout+stderr to C:\cfv\jobs\<name>.out
      - writes C:\cfv\jobs\<name>.done LAST, and only after .out is flushed,
        so the driver never reads a partial .out (the .done file is the barrier)
  Heartbeat to C:\cfv\jobs\_runner.heartbeat every loop so the driver can tell
  "runner alive, job slow" apart from "runner dead" -- those need different
  responses and guessing between them wasted a run in the JOB 2 lineage.

  The runner never exits on a job error. A job that throws still gets its .out
  (carrying the exception) and its .done, because a job that dies silently and
  a job that never ran look identical to the driver, and that ambiguity is
  exactly what the evidence gate exists to prevent.
#>

$ErrorActionPreference = 'Continue'
$JobDir = 'C:\cfv\jobs'
New-Item -ItemType Directory -Path $JobDir -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\cfv\wsl' -Force | Out-Null

'runner-started ' + (Get-Date -Format s) | Out-File "$JobDir\_runner.log" -Encoding utf8 -Append

while ($true) {
    try {
        [IO.File]::WriteAllText("$JobDir\_runner.heartbeat", (Get-Date -Format s))

        $pending = @(Get-ChildItem "$JobDir\*.job.ps1" -ErrorAction SilentlyContinue | Where-Object {
            -not (Test-Path ($_.FullName -replace '\.job\.ps1$', '.done'))
        } | Sort-Object Name)

        foreach ($j in $pending) {
            $base = $j.FullName -replace '\.job\.ps1$', ''
            $out  = "$base.out"
            "=== job $($j.Name) started $(Get-Date -Format s) ===" | Out-File "$JobDir\_runner.log" -Encoding utf8 -Append
            try {
                # Child powershell, not dot-source: a job that corrupts state or
                # calls exit cannot take the runner down with it.
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $j.FullName *> $out
                $rc = $LASTEXITCODE
            } catch {
                "RUNNER_CAUGHT: $($_.Exception.Message)" | Out-File $out -Encoding utf8 -Append
                $rc = 9009
            }
            # .out must be complete on disk BEFORE .done appears -- .done is the
            # driver's read barrier.
            "RUNNER_EXITCODE=$rc" | Out-File $out -Encoding utf8 -Append
            [IO.File]::WriteAllText("$base.done", "rc=$rc at $(Get-Date -Format s)")
            "=== job $($j.Name) done rc=$rc $(Get-Date -Format s) ===" | Out-File "$JobDir\_runner.log" -Encoding utf8 -Append
        }
    } catch {
        "RUNNER_LOOP_ERROR: $($_.Exception.Message)" | Out-File "$JobDir\_runner.log" -Encoding utf8 -Append
    }
    Start-Sleep -Seconds 5
}
