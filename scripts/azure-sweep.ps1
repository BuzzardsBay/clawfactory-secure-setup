<#
.SYNOPSIS
  Delete any validation VM left behind by a killed harness. Safety net for the one
  failure mode `finally` cannot cover.

.DESCRIPTION
  azure-validate.ps1 tears down in `finally` -- but a KILLED process never runs
  `finally`. That is not hypothetical: cfv-0715d wedged, the run was killed, and
  the VM had to be found and deleted by hand while it billed.

  So azure-validate.ps1 appends "<vmname> <rg>" to validation-runs/ACTIVE_VMS.txt
  the moment a VM exists, and removes the line only once an unfiltered listing
  proves it is gone. Anything still listed here is either running right now or was
  stranded. Run this after any abnormal exit.

  Deletes BY EXPLICIT NAME (L3: never let a --query filter decide what to delete)
  and proves the result with an UNFILTERED listing.

.EXAMPLE
  .\scripts\azure-sweep.ps1              # show what is stranded (no deletion)
  .\scripts\azure-sweep.ps1 -Delete      # delete it
#>
[CmdletBinding()]
param(
    [string]$SweepFile = (Join-Path (Split-Path -Parent $PSScriptRoot) "validation-runs\ACTIVE_VMS.txt"),
    [string]$ResourceGroup = "clawfactory-validation",
    [switch]$Delete
)
$ErrorActionPreference = 'Stop'
# L5: do not redirect this script's streams -- an az WARNING would become fatal.

function Say($m, $c = 'Cyan') { Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $m" -ForegroundColor $c }

Say "Live VMs in the subscription (UNFILTERED -- this, not the file, is the truth):"
az vm list -d -o table
Write-Host ""

if (-not (Test-Path $SweepFile)) { Say "No sweep file at $SweepFile -- nothing registered." Green; return }
$lines = @(Get-Content $SweepFile | Where-Object { $_.Trim() })
if (-not $lines) { Say "Sweep list empty -- every run de-registered cleanly." Green; return }

Say "Sweep list still holds $($lines.Count) entry/entries:" Yellow
$lines | ForEach-Object { Write-Host "  $_" }

if (-not $Delete) { Say "Dry run. Re-run with -Delete to remove these." Yellow; return }

foreach ($line in $lines) {
    $name, $rg = $line -split '\s+', 2
    if (-not $rg) { $rg = $ResourceGroup }
    Say "Deleting $name in $rg (by explicit name, parent -> child)..." Yellow
    az vm delete -g $rg -n $name --yes --force-deletion true --output none 2>$null
    az network nic delete -g $rg -n "${name}VMNic" --output none 2>$null
    az network public-ip delete -g $rg -n "$name-pip" --output none 2>$null
    az network nsg delete -g $rg -n "$name-nsg" --output none 2>$null
    az disk delete -g $rg -n "$name-osdisk" --yes --output none 2>$null
}

Say "Settling, then proving with an UNFILTERED listing..." DarkGray
$survivors = @()
foreach ($try in 1..10) {
    $survivors = @(az resource list -g $ResourceGroup --query "[].name" -o tsv 2>$null | Where-Object { $_ -like "cfv-*" })
    if ($survivors.Count -eq 0) { break }
    Start-Sleep -Seconds 15
}
Write-Host ""
Say "=== resources remaining in $ResourceGroup (UNFILTERED) ==="
az resource list -g $ResourceGroup -o table
Write-Host ""
Say "=== VMs in subscription (UNFILTERED, must be empty) ==="
az vm list -d -o table

if ($survivors.Count -eq 0) {
    Set-Content $SweepFile '' -Encoding ascii
    Say "CLEAN -- no cfv-* resource remains; sweep list cleared." Green
} else {
    Say "!! STILL PRESENT: $($survivors -join ', ') -- delete by hand NOW !!" Red
}
