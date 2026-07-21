<#
.SYNOPSIS
  Standalone L3/L10 teardown for a JOB 3 validation VM. Runnable BY HAND against a
  named cfv-NNN even if the driver (job3-validate.ps1) died -- a killed process
  never runs its own `finally`, which is exactly how a VM ends up billing forever
  (Lessons Learned L8). Deletes every child resource BY EXPLICIT NAME (never a
  --query filter -- L3), frees the license slot with the SAME machine_id the
  install activated (L10), and proves the result with an UNFILTERED listing.

  Copied verbatim-in-logic from the proven JOB 2 teardown
  (ClawFactory-Studio/validation/job2-teardown.ps1) so JOB 3C is self-contained; the
  teardown is VM-name-generic, so only the file/driver names differ.

.EXAMPLE
  .\job3-teardown.ps1 -VmName cfv-152
  .\job3-teardown.ps1 -VmName cfv-152 -MachineId 1234... -ResourceGroup clawfactory-validation

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
    # The license machine_id (MachineGuid) the install activated. If omitted, read
    # from the per-VM state file, else from the VM if still alive, else skip the
    # deactivate with a loud warning (a missed slot is a logged leak, never fatal).
    [string]$MachineId     = '',
    [string]$OutDir        = (Join-Path (Split-Path -Parent $PSScriptRoot) 'validation-runs'),
    [string]$LicenseKey    = 'CF-TEST-TEST-TEST-TEST'
)
$ErrorActionPreference = 'Stop'
if ($MyInvocation.Line -match '\*>&1|2>&1') {
    throw "Refusing to run with redirected streams (L5): an az stderr WARNING becomes a terminating error under EAP=Stop. Re-run without redirection."
}
function Say($m, $c = 'Yellow') { Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $m" -ForegroundColor $c }

# --- recover machine_id if not supplied -------------------------------------
$stateFile = Join-Path $OutDir "$VmName.state.json"
if (-not $MachineId -and (Test-Path $stateFile)) {
    try { $MachineId = (Get-Content $stateFile -Raw | ConvertFrom-Json).machineId } catch { }
    if ($MachineId) { Say "  machine_id recovered from state file: $MachineId" DarkGray }
}
if (-not $MachineId) {
    # VM may still be alive (e.g. a FAIL-preserve deallocate that is now being
    # cleaned up). Reading MachineGuid while it lives == what the install used.
    $alive = az vm show -g $ResourceGroup -n $VmName --query name -o tsv 2>$null
    if ($alive) {
        $f = Join-Path ([IO.Path]::GetTempPath()) ("cfv-mid-{0}.ps1" -f [Guid]::NewGuid())
        [IO.File]::WriteAllText($f, "(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' MachineGuid).MachineGuid", (New-Object Text.UTF8Encoding($false)))
        $MachineId = (az vm run-command invoke -g $ResourceGroup -n $VmName --command-id RunPowerShellScript --scripts "@$f" --query "value[].message" -o tsv)
        if ($MachineId) { $MachineId = $MachineId.Trim() }
        Remove-Item $f -Force -ErrorAction SilentlyContinue
        Say "  machine_id read from live VM: $MachineId" DarkGray
    }
}

# --- L3: resolve child resources by explicit name (union of two sources) -----
Say "Tearing down $VmName -- resolving child resources by explicit name..."
$nicNames  = New-Object System.Collections.Generic.List[string]
$ipNames   = New-Object System.Collections.Generic.List[string]
$diskNames = New-Object System.Collections.Generic.List[string]
$nsgNames  = New-Object System.Collections.Generic.List[string]
function AddName($list, $n) { if ($n -and -not $list.Contains($n)) { $list.Add($n) } }

# (1) authoritative: ask the VM what it owns, BEFORE deleting it (no 2>&1 -- L4)
$vmJson = az vm show -g $ResourceGroup -n $VmName -o json 2>$null
if ($vmJson) {
    $vm = $vmJson | ConvertFrom-Json
    AddName $diskNames $vm.storageProfile.osDisk.name
    foreach ($ref in @($vm.networkProfile.networkInterfaces)) {
        $nicName = $ref.id.Split('/')[-1]
        AddName $nicNames $nicName
        $nicJson = az network nic show -g $ResourceGroup -n $nicName -o json 2>$null
        if ($nicJson) {
            $nic = $nicJson | ConvertFrom-Json
            if ($nic.networkSecurityGroup) { AddName $nsgNames $nic.networkSecurityGroup.id.Split('/')[-1] }
            foreach ($cfg in @($nic.ipConfigurations)) {
                if ($cfg.publicIPAddress) { AddName $ipNames $cfg.publicIPAddress.id.Split('/')[-1] }
            }
        }
    }
} else {
    Say "  az vm show returned nothing -- VM absent or create failed. Using pinned names." DarkGray
}
# (2) belt-and-braces: the deterministic names job3-validate.ps1 pins at create
#     time + the az CLI's own NIC naming convention. Catches a half-created VM.
AddName $nicNames  "${VmName}VMNic"
AddName $ipNames   "$VmName-pip"
AddName $nsgNames  "$VmName-nsg"
AddName $diskNames "$VmName-osdisk"

Say ("  targets -> nic: {0} | pip: {1} | nsg: {2} | disk: {3}" -f `
     ($nicNames -join ','), ($ipNames -join ','), ($nsgNames -join ','), ($diskNames -join ',')) DarkGray

# Order: VM -> NIC -> (PIP, NSG) -> disk. A child with a live parent refuses to delete.
az vm delete -g $ResourceGroup -n $VmName --yes --force-deletion true --output none 2>$null
foreach ($n in $nicNames)  { Say "  deleting nic $n" DarkGray;  az network nic delete -g $ResourceGroup -n $n --output none 2>$null }
foreach ($n in $ipNames)   { Say "  deleting pip $n" DarkGray;  az network public-ip delete -g $ResourceGroup -n $n --output none 2>$null }
foreach ($n in $nsgNames)  { Say "  deleting nsg $n" DarkGray;  az network nsg delete -g $ResourceGroup -n $n --output none 2>$null }
foreach ($n in $diskNames) { Say "  deleting disk $n" DarkGray; az disk delete -g $ResourceGroup -n $n --yes --output none 2>$null }

# --- L10: free the license slot (same machine_id) ---------------------------
$deactLine = ''
if ($MachineId -match '^[0-9a-fA-F-]{32,40}$') {
    $dbody = (@{ key = $LicenseKey; machine_id = $MachineId; product = 'clawfactory' } | ConvertTo-Json -Compress)
    try {
        $dresp = Invoke-RestMethod -Uri 'https://api.clawfactory.app/deactivate' -Method Post -Body $dbody -ContentType 'application/json' -TimeoutSec 20
        $deactLine = "license slot deactivate ($MachineId): success=$($dresp.success) msg=$($dresp.message)"
        if ($dresp.success -eq $true) { Say "  $deactLine" Green } else { Say "  !! $deactLine -- SLOT MAY STILL BE OCCUPIED (leak); free it manually" Red }
    } catch {
        $deactLine = "license deactivate FAILED for $MachineId : $($_.Exception.Message) -- SLOT MAY LEAK; free it manually"
        Say "  !! $deactLine (Not a teardown failure.)" Red
    }
} else {
    $deactLine = "(no valid machine_id -- nothing to deactivate; if the install activated a slot it may leak)"
    Say "  $deactLine" DarkGray
}

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
Write-Host "=== license slot (L10) ===`n$deactLine"
if ($survivors.Count -eq 0) { Say $verdict Green } else { Say $verdict Red }
