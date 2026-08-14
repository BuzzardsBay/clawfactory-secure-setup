<#
  Finish the unattended half of the Guard 3 run, then PARK THE BOX.

  Written because the operator is away. It is a single sequential job, not a
  timer and not a schedule: it runs once, top to bottom, and exits. Nothing
  re-arms it.

  THE POINT OF THE finally BLOCK. Deallocation is unconditional. If phase 1
  failed, if phase 6 failed, if this script throws, if the driving session goes
  away, the VM still gets stopped. A validation VM left running through a human
  handoff has happened on this project before and cost real money for nothing,
  so "stop it" is not allowed to depend on anyone being present to notice.

  Deallocate rather than delete: the disk survives, so coming back costs a VM
  start rather than another forty-minute install. Compute billing stops either
  way, which is the part that matters.

  ONE THING THE OPERATOR MUST KNOW ON RETURN: stopping the VM ends the
  interactive auto-logon session, and auto-logon was one-shot and already
  consumed. So after the VM is started again, somebody has to log in over RDP
  before any WSL work can run. az run-command executes as SYSTEM and WSL refuses
  to run there (WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED), which is not a workaround
  that can be scripted around.
#>
[CmdletBinding()]
param(
    [string]$VmName        = 'cfv-162',
    [string]$ResourceGroup = 'clawfactory-validation',
    [int]$WaitMinutes      = 90
)

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$log      = Join-Path $RepoRoot "validation-runs\$VmName-finish-and-park.log"

function Say($m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line
    $line | Out-File $log -Encoding utf8 -Append
}

$phase6Ran = $false
$phase1Ok  = $false

try {
    $driverLog = Join-Path $RepoRoot "validation-runs\$VmName-driver.log"

    # ---- 1. Wait for the phase 1 driver to finish completely -----------------
    # BOTH terminal lines, not just the happy one. The first version of this
    # waited only for "Evidence in", which the driver prints on SUCCESS. When
    # cfv-162's driver was heading for an error instead, this sat out its whole
    # timeout and then deallocated the VM underneath a live run-command, which
    # turned a diagnosable failure into an OperationPreempted error on top of it.
    # Waiting for the LINE rather than the process means this does not care how
    # the driver was launched.
    Say "Waiting for the phase 1 driver to finish (up to $WaitMinutes min)..."
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    $done = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $driverLog) {
            $t = Get-Content -Raw -LiteralPath $driverLog -ErrorAction SilentlyContinue
            if ($t -match 'Evidence in ')  { $done = $true; break }
            if ($t -match 'DRIVER ERROR')  { Say "Driver reported an error. Skipping phase 6 and parking."; return }
        }
        Start-Sleep -Seconds 30
    }
    if (-not $done) { Say "Driver did not report completion within $WaitMinutes min. Parking the VM anyway."; return }
    Say "Phase 1 driver finished."

    # ---- 2. Did phase 1 actually pass? --------------------------------------
    $evidenceDir = Get-ChildItem (Join-Path $RepoRoot 'validation-runs') -Directory `
                     -Filter "$VmName-2*" -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $evidenceDir) { Say "No evidence directory found. Parking."; return }
    $probe = Join-Path $evidenceDir.FullName 'phase1-out.txt'
    if (-not (Test-Path $probe)) { Say "phase1-out.txt missing. Parking."; return }

    $p1 = Get-Content -Raw -LiteralPath $probe
    if ($p1 -match 'PASS=(\d+) FAIL=(\d+) VOID=(\d+)') {
        Say "Phase 1 tally: PASS=$($Matches[1]) FAIL=$($Matches[2]) VOID=$($Matches[3])"
        $phase1Ok = ([int]$Matches[2] -eq 0)
    }
    if (-not $phase1Ok) {
        Say "Phase 1 did NOT come back clean. Skipping phase 6 rather than measuring a broken box."
        foreach ($l in ($p1 -split "`r?`n" | Where-Object { $_ -match '\s+FAIL ' })) { Say "   $($l.Trim())" }
        return
    }
    Say "Phase 1 clean. Running the Guard 3 suite (phase 6)."

    # ---- 3. Phase 6, headless half ------------------------------------------
    # Generous timeout: phase 6 waits out the real 600s approval window rather
    # than rewriting the product's config to finish sooner.
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'interim-v120-job.ps1') `
        -PhaseScript (Join-Path $PSScriptRoot 'interim-v120-phase6.ps1') `
        -JobName 'phase6' -Sentinel 'PHASE6_PROBE_COMPLETE' `
        -VmName $VmName -TimeoutMinutes 40 2>&1 |
      ForEach-Object { if ($_ -notmatch '^Alive|^Finished') { Say "  $_" } }
    $phase6Ran = $true
    Say "Phase 6 submitted and retrieved."
}
catch {
    Say "ERROR: $($_.Exception.Message)"
}
finally {
    # UNCONDITIONAL. This is the whole reason the script exists.
    Say "Deallocating $VmName so it stops billing compute..."
    az vm deallocate -g $ResourceGroup -n $VmName --no-wait 2>&1 | Out-Null
    Start-Sleep -Seconds 45
    $state = (az vm get-instance-view -g $ResourceGroup -n $VmName `
                --query "instanceView.statuses[?starts_with(code,'PowerState')].code" -o tsv 2>$null)
    Say "PowerState now: $state (deallocation may still be finishing; it does not need supervision)"
    Say "SUMMARY: phase1Ok=$phase1Ok phase6Ran=$phase6Ran vm=$VmName"
    Say "On return: 'az vm start', then log in over RDP to recreate the interactive session before any WSL work."
}
