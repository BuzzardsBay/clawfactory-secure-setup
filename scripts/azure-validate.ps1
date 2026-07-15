<#
.SYNOPSIS
  Azure clean-install validation harness for ClawFactory.

.DESCRIPTION
  Provisions ONE disposable Windows VM from the baked baseline, installs a staged
  ClawFactory build, runs the clean-install-only checks (the ones that CANNOT be
  tested on a drifted box), collects verbatim evidence, and ALWAYS tears the VM
  down. Reusable: `.\scripts\azure-validate.ps1 -VmName cfv-138`.

  WHY THIS EXISTS: Bret's box has drifted to automount=true, so the headline claim
  -- "the agent cannot see files you did not grant" -- cannot be tested there. It
  can only be proven on a machine the installer actually built.

  ---------------------------------------------------------------------------
  TRAPS THIS HARNESS ENCODES (each one cost a validation cycle to learn):

  1. `az vm run-command` ALWAYS runs as NT AUTHORITY\SYSTEM, and WSL REFUSES to
     run as LocalSystem (WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED). So every `wsl ...`
     check returns an error string, not output -- which silently fails every
     WSL-dependent assertion. run-command is therefore used ONLY for
     Windows-side work (staging files, reading results, polling). All WSL work
     runs from a wrapper executed as clawadmin via auto-logon + RunOnce.
     (v1.0.15 lineage.)
  2. Trusted Launch breaks the baseline image -- `--security-type Standard` is
     mandatory.
  3. DSv5 quota is 0 in westus2 -> use Standard_D2s_v4, not D2s_v5.
  4. Non-zonal, existing `bake-vmSubnet`, `--nsg-rule NONE` + Standard public IP
     is the combination that provisions cleanly against this image.
  5. Git Bash mangles az `/subscriptions/...` paths -> this harness is
     PowerShell on purpose (no MSYS path conversion).
  6. run-command has wedged on freshly provisioned VMs. That is a HARNESS
     failure, not a product failure -- retry, or redeploy; never report the
     product broken because the harness stalled.

  COST DISCIPLINE: teardown runs in `finally`. If anything throws, the VM is
  still destroyed. -KeepVm is opt-in and prints a loud warning; use it only when
  actively debugging, and never leave a session with it set.

  KEYLESS BY DEFAULT: no provider key is placed on the VM. The headline claim is
  proven MODEL-INDEPENDENTLY -- with automount=false, /mnt/c is not mounted, so
  nothing in the VM (agent included) can read it. Agent-narrated checks and the
  agent-result cold-start need -ApiKeyFromCredMan and are skipped otherwise.
#>
[CmdletBinding()]
param(
    [string]$VmName        = "cfv-138",
    [string]$ResourceGroup = "clawfactory-validation",
    [string]$Location      = "westus2",
    [string]$Image         = "clawfactory-win11-baseline-v2",
    [string]$Size          = "Standard_D2s_v4",     # NOT D2s_v5: quota 0 in westus2
    [string]$StorageAcct   = "clawfactoryvalc467",
    [string]$Container     = "installers",
    [string]$Blob          = "ClawFactory-Secure-Setup-v1.0.38.exe",
    [string]$ExpectSha256  = "bd76a4ada7a5ae0641e520df11b58f445ec5b4abe371506452c3b0a591b064f3",
    [string]$AdminUser     = "clawadmin",
    [string]$OutDir        = (Join-Path (Split-Path -Parent $PSScriptRoot) "validation-runs"),
    [switch]$KeepVm,
    [switch]$ApiKeyFromCredMan
)
$ErrorActionPreference = 'Stop'
$run = "{0}-{1}" -f $VmName, (Get-Date -Format 'yyyyMMdd-HHmmss')
$dir = Join-Path $OutDir $run
New-Item -ItemType Directory -Path $dir -Force | Out-Null
function Say($m, $c = 'Cyan') { Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $m" -ForegroundColor $c }
function Save($name, $content) { $content | Out-File (Join-Path $dir $name) -Encoding utf8; }

try {
    # ---- 0. Preflight -----------------------------------------------------
    Say "Preflight: subscription must be live (verify via az rest -- the cached profile has lied before)."
    $sub = az account show --query id -o tsv
    $state = az rest --method get --url "https://management.azure.com/subscriptions/$sub`?api-version=2020-01-01" --query state -o tsv
    if ($state -ne 'Enabled') { throw "Subscription is '$state', not Enabled. Stop -- do not thrash." }
    $imgId = az image show -g $ResourceGroup -n $Image --query id -o tsv 2>$null
    if (-not $imgId) { throw "Baseline image $Image not found in $ResourceGroup." }
    $already = az vm list -g $ResourceGroup --query "[?name=='$VmName'].name" -o tsv
    if ($already) { throw "VM $VmName already exists -- refusing to double-provision (it would bill twice)." }

    # ---- 1. Provision -----------------------------------------------------
    Say "Provisioning $VmName ($Size, $Image, security-type Standard, non-zonal)..."
    $pw = -join ((65..90) + (97..122) + (48..57) + (33,35,37,42) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
    az vm create -g $ResourceGroup -n $VmName --image $Image --size $Size `
        --admin-username $AdminUser --admin-password $pw `
        --security-type Standard --public-ip-sku Standard --nsg-rule NONE `
        --subnet (az network vnet subnet show -g $ResourceGroup --vnet-name bake-vmVNET -n bake-vmSubnet --query id -o tsv) `
        --output none
    Say "Provisioned. (admin password generated in-memory; never printed or written)" Green

    # ---- 2. Stage the installer ------------------------------------------
    Say "Staging $Blob onto the VM (SAS, 1h) and verifying sha256 on the box..."
    $key = az storage account keys list -g $ResourceGroup -n $StorageAcct --query "[0].value" -o tsv
    $exp = (Get-Date).ToUniversalTime().AddHours(1).ToString('yyyy-MM-ddTHH:mmZ')
    $sas = az storage blob generate-sas --account-name $StorageAcct --account-key $key `
             --container-name $Container --name $Blob --permissions r --expiry $exp -o tsv
    $url = "https://$StorageAcct.blob.core.windows.net/$Container/$Blob`?$sas"
    # run-command is SYSTEM here -- fine: this is Windows-side only, no WSL.
    $stage = @"
`$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path C:\cfv -Force | Out-Null
Invoke-WebRequest -Uri '$url' -OutFile C:\cfv\setup.exe -UseBasicParsing
`$h = (Get-FileHash C:\cfv\setup.exe -Algorithm SHA256).Hash.ToLower()
if (`$h -ne '$ExpectSha256') { throw "HASH MISMATCH on VM: `$h" }
"OK staged; sha256 verified: `$h"
"@
    $r = az vm run-command invoke -g $ResourceGroup -n $VmName --command-id RunPowerShellScript --scripts $stage --query "value[0].message" -o tsv
    Save 'stage.txt' $r; Say "Staged + hash verified." Green

    # ---- 3. Install as clawadmin (NOT via run-command: WSL breaks under SYSTEM)
    Say "Configuring auto-logon + RunOnce wrapper so the installer runs as $AdminUser (WSL cannot run as SYSTEM)."
    $wrapper = @"
`$ErrorActionPreference='Stop'
`$W='C:\cfv'
# Auto-logon once, so a real interactive clawadmin session exists for WSL.
`$k='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty `$k AutoAdminLogon '1'
Set-ItemProperty `$k DefaultUserName '$AdminUser'
Set-ItemProperty `$k DefaultPassword '$pw'
Set-ItemProperty `$k AutoLogonCount 1 -Type DWord
# RunOnce -> wrapper.cmd runs in the clawadmin session (batch-logon rights make
# a scheduled task unreliable on Win11; wrapper.cmd from RunOnce is the pattern
# proven in the v1.0.15+ cycles).
@'
@echo off
"C:\cfv\setup.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG="C:\cfv\install.log"
echo INSTALLER_EXIT=%ERRORLEVEL% > C:\cfv\INSTALLER_DONE.txt
'@ | Set-Content `$W\wrapper.cmd -Encoding ASCII
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' CFV-Install-Wrapper "cmd /c `$W\wrapper.cmd"
'auto-logon + RunOnce armed'
"@
    $r = az vm run-command invoke -g $ResourceGroup -n $VmName --command-id RunPowerShellScript --scripts $wrapper --query "value[0].message" -o tsv
    Save 'arm.txt' $r
    Say "Rebooting into the auto-logon session to run the installer..."
    az vm restart -g $ResourceGroup -n $VmName --output none

    # ---- 4. Poll for INSTALLER_DONE --------------------------------------
    Say "Polling for INSTALLER_DONE (install is 10-20 min)..."
    $done = $false
    foreach ($i in 1..40) {
        Start-Sleep -Seconds 45
        $p = az vm run-command invoke -g $ResourceGroup -n $VmName --command-id RunPowerShellScript `
              --scripts "if (Test-Path C:\cfv\INSTALLER_DONE.txt) { Get-Content C:\cfv\INSTALLER_DONE.txt } else { 'PENDING' }" `
              --query "value[0].message" -o tsv 2>$null
        if ($p -match 'INSTALLER_EXIT') { $done = $true; Save 'installer_done.txt' $p; Say "Install finished: $p" Green; break }
        Say "  ...still installing ($i/40)" DarkGray
    }
    if (-not $done) { throw "Installer did not report INSTALLER_DONE within ~30 min. If run-command wedged this is a HARNESS failure -- retry on a fresh VM before blaming the product." }
    Save 'install.log' (az vm run-command invoke -g $ResourceGroup -n $VmName --command-id RunPowerShellScript --scripts "Get-Content C:\cfv\install.log -Tail 200" --query "value[0].message" -o tsv)

    # ---- 5. Clean-install evidence ---------------------------------------
    # Run the WSL-dependent checks from a clawadmin scheduled wrapper, writing to
    # a file that run-command (SYSTEM) can then read back. Never call wsl from
    # run-command directly.
    Say "Collecting clean-install evidence (headline isolation, install-path changes)..."
    $probe = Get-Content (Join-Path $PSScriptRoot 'azure-probe.ps1') -Raw
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($probe))
    $runProbe = @"
`$ErrorActionPreference='Continue'
[IO.File]::WriteAllBytes('C:\cfv\probe.ps1', [Convert]::FromBase64String('$b64'))
@'
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File C:\cfv\probe.ps1 > C:\cfv\probe-out.txt 2>&1
echo PROBE_DONE > C:\cfv\PROBE_DONE.txt
'@ | Set-Content C:\cfv\probe.cmd -Encoding ASCII
`$k='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty `$k AutoAdminLogon '1'; Set-ItemProperty `$k AutoLogonCount 1 -Type DWord
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' CFV-Probe "cmd /c C:\cfv\probe.cmd"
'probe armed'
"@
    az vm run-command invoke -g $ResourceGroup -n $VmName --command-id RunPowerShellScript --scripts $runProbe --output none
    az vm restart -g $ResourceGroup -n $VmName --output none
    $got = $false
    foreach ($i in 1..20) {
        Start-Sleep -Seconds 30
        $p = az vm run-command invoke -g $ResourceGroup -n $VmName --command-id RunPowerShellScript `
              --scripts "if (Test-Path C:\cfv\PROBE_DONE.txt) { Get-Content C:\cfv\probe-out.txt -Raw } else { 'PENDING' }" `
              --query "value[0].message" -o tsv 2>$null
        if ($p -and $p -notmatch '^PENDING') { $got = $true; Save 'probe-out.txt' $p; Say "Probe results captured." Green; break }
        Say "  ...waiting for probe ($i/20)" DarkGray
    }
    if (-not $got) { Say "Probe did not report -- harness issue; evidence incomplete." Red }
    Write-Host "`n===== PROBE OUTPUT =====" -ForegroundColor Cyan
    if (Test-Path (Join-Path $dir 'probe-out.txt')) { Get-Content (Join-Path $dir 'probe-out.txt') }
}
finally {
    # ---- 6. Teardown -- ALWAYS. A forgotten VM bills indefinitely. --------
    if ($KeepVm) {
        Say "!! -KeepVm SET: $VmName IS STILL RUNNING AND BILLING. Delete it when done. !!" Red
    } else {
        Say "Tearing down $VmName (VM + NIC + public IP + disk + NSG)..." Yellow
        az vm delete -g $ResourceGroup -n $VmName --yes --force-deletion true --output none 2>$null
        foreach ($t in @('nic','public-ip','disk','nsg')) {
            switch ($t) {
                'nic'       { az network nic list -g $ResourceGroup --query "[?starts_with(name,'$VmName')].name" -o tsv | ForEach-Object { az network nic delete -g $ResourceGroup -n $_ --output none 2>$null } }
                'public-ip' { az network public-ip list -g $ResourceGroup --query "[?starts_with(name,'$VmName')].name" -o tsv | ForEach-Object { az network public-ip delete -g $ResourceGroup -n $_ --output none 2>$null } }
                'disk'      { az disk list -g $ResourceGroup --query "[?starts_with(name,'$VmName')].name" -o tsv | ForEach-Object { az disk delete -g $ResourceGroup -n $_ --yes --output none 2>$null } }
                'nsg'       { az network nsg list -g $ResourceGroup --query "[?starts_with(name,'$VmName')].name" -o tsv | ForEach-Object { az network nsg delete -g $ResourceGroup -n $_ --output none 2>$null } }
            }
        }
        # Teardown PROOF -- a close-out that says "torn down" without this listing
        # is not acceptable.
        $left = az resource list -g $ResourceGroup --query "[].{name:name,type:type}" -o table | Out-String
        $vms  = az vm list -d --query "[].{name:name,power:powerState}" -o table | Out-String
        Save 'teardown-proof.txt' ("=== resources remaining in $ResourceGroup ===`n$left`n=== VMs in subscription (must be empty) ===`n$vms")
        Write-Host "`n===== TEARDOWN PROOF =====" -ForegroundColor Yellow
        Write-Host $left; Write-Host $vms
        Say "Evidence written to $dir" Green
    }
}
