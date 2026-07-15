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
    [switch]$ApiKeyFromCredMan,
    # DIAGNOSTIC MODE. -Payload runs a script as clawadmin in the SAME session and
    # SAME boot as the installer, immediately after it exits -- so a FAILED install
    # can be examined in the exact state it failed in. The suite's probe step
    # reboots first, which would re-trigger auto-logon and could itself repair the
    # very state under investigation; -SkipSuite omits it.
    [string]$Payload       = "",
    [switch]$SkipSuite
)
$ErrorActionPreference = 'Stop'

# L5 -- DO NOT REDIRECT THIS SCRIPT'S STREAMS (no `*>&1`, no `2>&1`).
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords ONLY when that
# stderr is redirected. az writes deprecation WARNINGS to stderr. Combine the two
# with EAP=Stop and a harmless warning becomes a TERMINATING error -- which fires
# `finally` and tears down a healthy VM mid-install, then reports the product
# broken. That happened on cfv-0715b: `az vm create` succeeded, the installer was
# running, and a "...will be removed in a future release." warning killed the run.
# Call this script WITHOUT redirection; the caller's harness captures stderr
# anyway. Related: L4 (never `2>&1` an az call whose stdout you parse).
if ($MyInvocation.Line -match '\*>&1|2>&1') {
    throw "Refusing to run: this script's streams are redirected ($($MyInvocation.Line.Trim())). See L5 -- an az stderr WARNING becomes a terminating error under EAP=Stop and will tear down a healthy VM. Re-run without redirection."
}

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
    # L3: every child resource gets a DETERMINISTIC, explicit name at create time.
    # Without this the OS disk gets a random GUID suffix, which is why the old
    # teardown fell back to a `--query [?starts_with(...)]` filter -- the filter the
    # Windows shell mangled into matching nothing while printing "deleted".
    # Named here => deletable by name in `finally` even if create dies half-way.
    az vm create -g $ResourceGroup -n $VmName --image $Image --size $Size `
        --admin-username $AdminUser --admin-password $pw `
        --security-type Standard --public-ip-sku Standard --nsg-rule NONE `
        --os-disk-name "$VmName-osdisk" --public-ip-address "$VmName-pip" --nsg "$VmName-nsg" `
        --subnet (az network vnet subnet show -g $ResourceGroup --vnet-name bake-vmVNET -n bake-vmSubnet --query id -o tsv) `
        --output none
    # L6 -- an az failure does NOT throw. EAP=Stop governs PowerShell errors, not a
    # native command's exit code, and (per L5) we deliberately do not redirect
    # stderr. So `az vm create` can fail and the script sails on: cfv-0715d printed
    # "Provisioned." immediately after ERROR: OSProvisioningTimedOut, then spent 40
    # minutes staging onto a VM it never confirmed. Check $LASTEXITCODE explicitly
    # -- but do NOT trust it alone in the other direction either: ARM reports
    # OSProvisioningTimedOut for this custom image while the guest actually boots
    # fine (the agent reports late), and cfv-0715d's VM was up and serving
    # run-command. So ask the VM what it is actually doing.
    if ($LASTEXITCODE -ne 0) {
        Say "az vm create returned exit $LASTEXITCODE -- asking the VM whether it actually came up..." Yellow
        $codes = @(az vm get-instance-view -g $ResourceGroup -n $VmName --query "instanceView.statuses[].code" -o tsv 2>$null)
        if ($codes -notcontains 'PowerState/running') {
            throw "az vm create failed (exit $LASTEXITCODE) and the VM is not running (statuses: $($codes -join ', ')). Not proceeding."
        }
        Say "  ...VM IS running despite the deployment error (OSProvisioningTimedOut is advisory for this image). Continuing." Yellow
    }
    Say "Provisioned. (admin password generated in-memory; never printed or written)" Green

    # ---- 2. Stage the installer ------------------------------------------
    Say "Staging $Blob onto the VM (SAS, 1h) and verifying sha256 on the box..."
    $key = az storage account keys list -g $ResourceGroup -n $StorageAcct --query "[0].value" -o tsv
    $exp = (Get-Date).ToUniversalTime().AddHours(1).ToString('yyyy-MM-ddTHH:mmZ')
    $sas = az storage blob generate-sas --account-name $StorageAcct --account-key $key `
             --container-name $Container --name $Blob --permissions r --expiry $exp -o tsv
    $url = "https://$StorageAcct.blob.core.windows.net/$Container/$Blob`?$sas"

    # PAYLOAD TRANSPORT (L2): do NOT carry the payload inline through --scripts.
    # Tried that on cfv-0715c: an ~12 KB base64 blob made `run-command invoke`
    # return EMPTY stdout with no error -- L2's exact signature ("runs partially,
    # returns empty stdout"), which reads as "did nothing" rather than "was too
    # big". Instead reuse the mechanism that provably moves a 325 MB installer:
    # upload to blob, download on the VM via SAS. Keeps the arm script small --
    # the shape that worked on cfv-0715.
    $payloadDl = ""
    if ($Payload) {
        $pName = Split-Path $Payload -Leaf
        az storage blob upload --account-name $StorageAcct --account-key $key `
            --container-name $Container --name $pName --file $Payload --overwrite --output none
        $pSas = az storage blob generate-sas --account-name $StorageAcct --account-key $key `
                  --container-name $Container --name $pName --permissions r --expiry $exp -o tsv
        $pUrl = "https://$StorageAcct.blob.core.windows.net/$Container/$pName`?$pSas"
        # Prove it landed AND is non-trivial: a truncated/empty payload.ps1 would
        # otherwise only surface 20 minutes later as a silent empty diagnostic.
        $payloadDl = "Invoke-WebRequest -Uri '$pUrl' -OutFile C:\cfv\payload.ps1 -UseBasicParsing`r`n" +
                     "if (-not (Test-Path C:\cfv\payload.ps1)) { throw 'payload.ps1 did not download' }`r`n" +
                     "`"PAYLOAD_BYTES=`$((Get-Item C:\cfv\payload.ps1).Length)`""
        Say "  payload uploaded to blob '$pName' (staged by SAS, not by --scripts)" DarkGray
    }

    # run-command is SYSTEM here -- fine: this is Windows-side only, no WSL.
    $stage = @"
`$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path C:\cfv -Force | Out-Null
Invoke-WebRequest -Uri '$url' -OutFile C:\cfv\setup.exe -UseBasicParsing
`$h = (Get-FileHash C:\cfv\setup.exe -Algorithm SHA256).Hash.ToLower()
if (`$h -ne '$ExpectSha256') { throw "HASH MISMATCH on VM: `$h" }
$payloadDl
"OK staged; sha256 verified: `$h"
"@
    $r = az vm run-command invoke -g $ResourceGroup -n $VmName --command-id RunPowerShellScript --scripts $stage --query "value[0].message" -o tsv
    Save 'stage.txt' $r
    if ($r -notmatch 'sha256 verified') { throw "Stage step did not confirm sha256. Output: $r" }
    if ($Payload -and $r -notmatch 'PAYLOAD_BYTES=\d{3,}') { throw "Payload did not stage (expected PAYLOAD_BYTES). Output: $r" }
    Say "Staged + hash verified. $(($r -split "`n" | Where-Object { $_ -match 'PAYLOAD_BYTES' }) -join '')" Green

    # ---- 3. Install as clawadmin (NOT via run-command: WSL breaks under SYSTEM)
    Say "Configuring auto-logon + RunOnce wrapper so the installer runs as $AdminUser (WSL cannot run as SYSTEM)."
    # Payload (diagnostic mode): staged now, executed by wrapper.cmd right after the
    # installer exits -- same session, same boot, no reboot in between.
    # payload.ps1 is already on the box (blob+SAS, in the stage step above), so the
    # arm script stays small -- it only has to CALL it.
    $payloadCall = ""
    if ($Payload) {
        $payloadCall = "powershell -NoProfile -ExecutionPolicy Bypass -File C:\cfv\payload.ps1 > C:\cfv\diag-out.txt 2>&1`r`necho DIAG_DONE > C:\cfv\DIAG_DONE.txt"
        Say "  payload armed: $Payload (runs in-session immediately after the installer)" Yellow
    }
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
"C:\cfv\setup.exe" /SILENT /SUPPRESSMSGBOXES /NORESTART /LOG="C:\cfv\install.log" /PROVIDER=claude /LICENSE=CF-TEST-TEST-TEST-TEST
echo INSTALLER_EXIT=%ERRORLEVEL% > C:\cfv\INSTALLER_DONE.txt
$payloadCall
'@ | Set-Content `$W\wrapper.cmd -Encoding ASCII
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' CFV-Install-Wrapper "cmd /c `$W\wrapper.cmd"
'auto-logon + RunOnce armed'
"@
    # Inline --scripts, matching the shape proven on cfv-0715. The payload is NOT
    # in here (it came down from blob storage), so this stays small. The `@file`
    # form was tried on cfv-0715c and returned empty stdout -- see L2.
    $r = az vm run-command invoke -g $ResourceGroup -n $VmName --command-id RunPowerShellScript --scripts $wrapper --query "value[0].message" -o tsv
    Save 'arm.txt' $r   # $r is just the 'auto-logon + RunOnce armed' echo -- no secret
    # Guard: empty output means the wrapper may be half-written. Rebooting into a
    # half-written wrapper produces a meaningless run, so stop while it is cheap.
    if (-not $r) { throw "Arm step returned empty output -- suspect a mangled/oversized script (L2). Do not proceed: the wrapper may be half-written." }
    if ($Payload -and $r -notmatch 'armed') { throw "Arm step did not confirm: $r" }
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

    # ---- 4b. Diagnostic payload (same session/boot as the install) ---------
    if ($Payload) {
        Say "Waiting for the in-session diagnostic payload (DIAG_DONE)..."
        $dgot = $false
        foreach ($i in 1..20) {
            $d = az vm run-command invoke -g $ResourceGroup -n $VmName --command-id RunPowerShellScript `
                  --scripts "if (Test-Path C:\cfv\DIAG_DONE.txt) { Get-Content C:\cfv\diag-out.txt -Raw } else { 'PENDING' }" `
                  --query "value[0].message" -o tsv 2>$null
            if ($d -and $d -notmatch '^PENDING') { $dgot = $true; Save 'diag-out.txt' $d; Say "Diagnostic bundle captured." Green; break }
            Say "  ...waiting for diagnostic ($i/20)" DarkGray
            Start-Sleep -Seconds 30
        }
        if (-not $dgot) { Say "Diagnostic did not report -- evidence incomplete (harness issue, not a product verdict)." Red }
        else { Write-Host "`n===== DIAGNOSTIC BUNDLE =====" -ForegroundColor Cyan; Get-Content (Join-Path $dir 'diag-out.txt') }
    }

    # ---- 5. Clean-install evidence ---------------------------------------
    # Run the WSL-dependent checks from a clawadmin scheduled wrapper, writing to
    # a file that run-command (SYSTEM) can then read back. Never call wsl from
    # run-command directly.
    if ($SkipSuite) {
    Say "-SkipSuite: skipping the validation probe (on a failed install nothing it checks is reachable)." Yellow
    } else {
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
}
finally {
    # ---- 6. Teardown -- ALWAYS. A forgotten VM bills indefinitely. --------
    if ($KeepVm) {
        Say "!! -KeepVm SET: $VmName IS STILL RUNNING AND BILLING. Delete it when done. !!" Red
    } else {
        # ---- L3 HARDENED TEARDOWN ----------------------------------------
        # RULE (Lessons Learned L3): delete by EXPLICIT NAME. Never let a
        # `--query "[?starts_with(...)]"` filter decide what gets deleted -- the
        # Windows shell mangles it, it matches nothing, and the loop cheerfully
        # prints "deleted" while four resources keep billing. That happened.
        #
        # Names come from two independent sources, unioned:
        #   1. the VM's OWN record (az vm show) -- authoritative while it exists
        #   2. the deterministic names pinned at create time -- still correct if
        #      the VM never fully created, which is exactly when orphans hide
        Say "Tearing down $VmName -- resolving child resources by explicit name..." Yellow

        $nicNames  = New-Object System.Collections.Generic.List[string]
        $ipNames   = New-Object System.Collections.Generic.List[string]
        $diskNames = New-Object System.Collections.Generic.List[string]
        $nsgNames  = New-Object System.Collections.Generic.List[string]
        function AddName($list, $n) { if ($n -and -not $list.Contains($n)) { $list.Add($n) } }

        # (1) authoritative: ask the VM what it actually owns, BEFORE deleting it
        $vmJson = az vm show -g $ResourceGroup -n $VmName -o json 2>$null
        if ($vmJson) {
            $vm = $vmJson | ConvertFrom-Json          # no 2>&1 -- L4
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
        # (2) belt-and-braces: the names we pinned at create time + the az CLI's
        #     own NIC naming convention. Catches a half-created VM's orphans.
        AddName $nicNames  "${VmName}VMNic"
        AddName $ipNames   "$VmName-pip"
        AddName $nsgNames  "$VmName-nsg"
        AddName $diskNames "$VmName-osdisk"

        Say ("  targets -> nic: {0} | pip: {1} | nsg: {2} | disk: {3}" -f `
             ($nicNames -join ','), ($ipNames -join ','), ($nsgNames -join ','), ($diskNames -join ',')) DarkGray

        # Order matters: VM -> NIC -> (PIP, NSG) -> disk. A child with a live
        # parent refuses to delete, which is another way orphans survive.
        az vm delete -g $ResourceGroup -n $VmName --yes --force-deletion true --output none 2>$null
        foreach ($n in $nicNames)  { Say "  deleting nic $n" DarkGray;  az network nic delete -g $ResourceGroup -n $n --output none 2>$null }
        foreach ($n in $ipNames)   { Say "  deleting pip $n" DarkGray;  az network public-ip delete -g $ResourceGroup -n $n --output none 2>$null }
        foreach ($n in $nsgNames)  { Say "  deleting nsg $n" DarkGray;  az network nsg delete -g $ResourceGroup -n $n --output none 2>$null }
        foreach ($n in $diskNames) { Say "  deleting disk $n" DarkGray; az disk delete -g $ResourceGroup -n $n --yes --output none 2>$null }

        # ARM deletes are eventually-consistent: a disk can still be listed for a
        # while after `az disk delete` returns, especially when its VM was being
        # deleted concurrently. Polling to settle before judging -- otherwise the
        # assertion cries ORPHAN about a resource that is already on its way out,
        # and a false alarm every run is how a real alarm gets ignored.
        $survivors = @()
        foreach ($try in 1..10) {
            $survivors = @(az resource list -g $ResourceGroup --query "[].name" -o tsv 2>$null | Where-Object { $_ -like "*$VmName*" })
            if ($survivors.Count -eq 0) { break }
            Say ("  settling: still listed -> {0} (check {1}/10)" -f ($survivors -join ','), $try) DarkGray
            Start-Sleep -Seconds 15
        }

        # ---- PROOF: UNFILTERED. ------------------------------------------
        # The delete commands' output is NOT evidence -- they printed "deleted"
        # while deleting nothing. The evidence is the full listing, unfiltered,
        # read with your own eyes. No --query here on purpose: a query is the
        # thing that lied.
        $left = az resource list -g $ResourceGroup -o table | Out-String
        $vms  = az vm list -d -o table | Out-String
        $verdict = if ($survivors.Count -eq 0) { "CLEAN -- no resource matching '$VmName' remains." }
                   else { "!! ORPHANS STILL BILLING: $($survivors -join ', ') -- DELETE THESE BY HAND NOW !!" }

        Save 'teardown-proof.txt' ("=== resources remaining in $ResourceGroup (UNFILTERED) ===`n$left`n=== VMs in subscription, all RGs (UNFILTERED, must be empty) ===`n$vms`n=== verdict ===`n$verdict")
        Write-Host "`n===== TEARDOWN PROOF (unfiltered) =====" -ForegroundColor Yellow
        Write-Host $left; Write-Host $vms
        if ($survivors.Count -eq 0) { Say $verdict Green } else { Say $verdict Red }
        Say "Evidence written to $dir" Green
    }
}
