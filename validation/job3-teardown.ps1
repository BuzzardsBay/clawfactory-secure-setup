<#
.SYNOPSIS
  Standalone L3/L10 teardown for a JOB 3 validation VM. Runnable BY HAND against a
  named cfv-NNN even if the driver (job3-validate.ps1) died -- a killed process
  never runs its own `finally`, which is exactly how a VM ends up billing forever
  (Lessons Learned L8). Deletes every child resource BY EXPLICIT NAME (never a
  --query filter -- L3) and proves the result with an UNFILTERED listing.
  L10 (free the license slot) no longer applies: licence checking was removed
  for the free release, so an install leaves no server-side state to reclaim.

  Copied verbatim-in-logic from the proven JOB 2 teardown
  (ClawFactory-Studio/validation/job2-teardown.ps1) so JOB 3C is self-contained; the
  teardown is VM-name-generic, so only the file/driver names differ.

.EXAMPLE
  .\job3-teardown.ps1 -VmName cfv-152
  .\job3-teardown.ps1 -VmName cfv-152 -ResourceGroup clawfactory-validation

.NOTES
  L5 -- do NOT redirect this script's streams (`*>&1`/`2>&1`): an az stderr WARNING
  becomes a terminating error under EAP=Stop. Streams are left alone on purpose;
  az failures are tolerated per-delete (best-effort) and the UNFILTERED listing is
  the authoritative proof, not any delete command's output.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VmName,
    [string]$ResourceGroup = 'clawfactory-validation',
    [string]$OutDir        = (Join-Path (Split-Path -Parent $PSScriptRoot) 'validation-runs')
)
$ErrorActionPreference = 'Stop'
if ($MyInvocation.Line -match '\*>&1|2>&1') {
    throw "Refusing to run with redirected streams (L5): an az stderr WARNING becomes a terminating error under EAP=Stop. Re-run without redirection."
}
function Say($m, $c = 'Yellow') { Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $m" -ForegroundColor $c }

# --- settle (ARM deletes are eventually-consistent) -------------------------
$survivors = @()
foreach ($try in 1..10) {
    $survivors = @(az resource list -g $ResourceGroup --query "[].name" -o tsv 2>$null | Where-Object { $_ -like "*$VmName*" })
    if ($survivors.Count -eq 0) { break }
    Say ("  settling: still listed -> {0} (check {1}/10)" -f ($survivors -join ','), $try) DarkGray
    Start-Sleep -Seconds 15
}

# --- PROOF: UNFILTERED. The delete output lied before; the listing is truth. --
$left = az resource list -g $ResourceGroup -o table | Out-String
$vms  = az vm list -d -o table | Out-String
$verdict = if ($survivors.Count -eq 0) { "CLEAN -- no resource matching '$VmName' remains." }
           else { "!! ORPHANS STILL BILLING: $($survivors -join ', ') -- DELETE THESE BY HAND NOW !!" }

# De-register from the sweep list only once the listing proves it is gone. L8:
# materialise survivors and write unconditionally (a filter piped straight into
# Set-Content no-ops when it empties the pipeline).
if ($survivors.Count -eq 0) {
    $sweepFile = Join-Path $OutDir 'ACTIVE_VMS.txt'
    if (Test-Path $sweepFile) {
        $keep = @(Get-Content $sweepFile | Where-Object { $_.Trim() -and $_ -notmatch "^$VmName\s" })
        [IO.File]::WriteAllText($sweepFile, (($keep -join "`r`n") + $(if ($keep.Count) { "`r`n" } else { "" })), (New-Object Text.ASCIIEncoding))
        Say "  de-registered '$VmName' from the sweep list ($($keep.Count) still registered)" DarkGray
    }
    # State file is spent once the VM is gone; keep it only if orphans remain.
    if (Test-Path $stateFile) { Remove-Item $stateFile -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n===== TEARDOWN PROOF (unfiltered) =====" -ForegroundColor Yellow
Write-Host $left; Write-Host $vms
if ($survivors.Count -eq 0) { Say $verdict Green } else { Say $verdict Red }
