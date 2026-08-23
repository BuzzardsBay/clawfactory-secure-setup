<#
.SYNOPSIS
  JOB 3 clean-box functional-validation DRIVER for the COMBINED ClawFactory v1.1.0
  installer (core sandbox + agent + Studio in ONE download / ONE consent flow).

.DESCRIPTION
  Provisions ONE disposable Windows VM from the baked baseline, stages ONLY the
  SIGNED combined installer + the VM-side probe (job3-probe.ps1) + the Tier 1
  adversarial suite, drives the full JOB 3 sequence in a real interactive clawadmin
  session (auto-logon + RunOnce -- WSL and an Electron GUI both need a session, and
  run-command is SYSTEM), retrieves the verbatim evidence bundle, and ALWAYS tears
  down.

  Derived from the proven JOB 2 driver (ClawFactory-Studio/validation/job2-validate.ps1)
  -- COPIED into this repo, not shared, so JOB 3C is self-contained (the Studio repo
  is a read-only reference, never a runtime dependency of the combined-installer run).

  The on-VM sequence (job3-probe.ps1) is, in order:
    1. install the COMBINED installer (core first, Studio last, de-elevated)
    A. Studio landed in the invoking user's profile (the elevation rule held)
    B. installed Studio binaries verify Authenticode = Valid
    4. agent liveness (warm-up loop)
    5. functional matrix (5.2/5.3)
    6. adversarial (Tier 1 suite + Studio-specific)
  The JOB 2 "engine-absent" cell is intentionally ABSENT: the combined installer
  always installs the core (grant engine) before Studio, so that ordering cannot be
  reproduced. Its standing proof is cfv-150 / cfv-151 (JOB 2).

  RESUMABLE. Each phase writes <OutDir>\<VmName>.state.json. A killed run can be
  swept (azure-sweep / ACTIVE_VMS.txt) and re-driven with -Resume without
  re-provisioning blindness; teardown is a STANDALONE script (job3-teardown.ps1)
  runnable by hand even if this driver died.

  This harness encodes every Lessons Learned rule it depends on -- see the inline
  L-tags. The big ones: L2/L7 (script via @file, one line, base64 for multi-line,
  paren-free --query, read BOTH streams), L4/L5/L6 (never 2>&1/*>&1 an az call;
  check $LASTEXITCODE; ask the VM on non-zero create), L3 (teardown by explicit
  name), L16 (fresh
  retrieval SAS; verify the blob landed), L17/L19 (warm the agent; grant probe
  reads /workspaces/<grant-id> -- enforced in the probe), L20/L21 (single-joined
  wrapper command line + Count guard; CR-strip bash into WSL).

.EXAMPLE
  .\job3-validate.ps1 -VmName cfv-152
  .\job3-validate.ps1 -VmName cfv-152 -Resume        # continue a killed run
  .\job3-teardown.ps1 -VmName cfv-152                # tear down by hand

.NOTES
  Do NOT redirect this script's streams (L5). Requires: az logged in (subscription
  Enabled), the provider key in Credential Manager at -ProviderKeyTarget (needed
  for the live agent; without it the functional matrix cannot run), and the SIGNED
  combined installer present at -CombinedExe with sha256 -CombinedSha256.
#>
[CmdletBinding()]
param(
    [string]$VmName          = 'cfv-152',
    [string]$ResourceGroup   = 'clawfactory-validation',
    [string]$Location        = 'westus2',
    [string]$Image           = 'clawfactory-win11-baseline-v2',
    [string]$Size            = 'Standard_D2s_v4',          # NOT D2s_v5: quota 0 in westus2 (azure-validate L note 3)
    [string]$StorageAcct     = 'clawfactoryvalc467',
    [string]$Container       = 'installers',
    # --- The artifact under test: the SIGNED combined v1.1.0 installer (JOB 3B pin) ---
    [string]$CombinedExe     = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Output\ClawFactory-Secure-Setup.exe'),
    [string]$CombinedBlob    = 'ClawFactory-Secure-Setup-v1.1.0.exe',
    [string]$CombinedSha256  = 'ffe86406df651b27ba6ec4d22563e2391baa4bf77f4454ff3889d70dc16e3aed',
    # --- read-only reference staged from this repo ---
    [string]$AdversarialSuite = (Join-Path (Split-Path -Parent $PSScriptRoot) 'adversarial-suite.ps1'),
    [string]$ProbeScript     = (Join-Path $PSScriptRoot 'job3-probe.ps1'),
    [string]$AdminUser       = 'clawadmin',
    # Provider key: read from THIS box's Credential Manager, base64'd, seeded to the
    # VM's Credential Manager (UTF-16LE) where the installer's CredRead reads it.
    # The value is never printed here or on the VM.
    [string]$ProviderKeyTarget = 'ClawFactory/AnthropicApiKey',
    [string]$SeedKeyTarget   = 'ClawFactory/AnthropicApiKey',
    [string]$SeedKeyB64      = '',                          # override: pass base64(UTF8(key)) directly
    [string]$OutDir          = (Join-Path (Split-Path -Parent $PSScriptRoot) 'validation-runs'),
    [switch]$Resume,
    [switch]$KeepVm,
    [switch]$PreserveOnFail                                 # FAIL path: deallocate + preserve instead of delete
)
$ErrorActionPreference = 'Stop'

# Shared, render-tested wrapper builder + evidence-gate predicate (see
# validation/wrapper-builder.ps1 and validation/test-wrapper-render.ps1). Isolated
# so the render test exercises the EXACT code this driver arms/gates on.
. (Join-Path $PSScriptRoot 'wrapper-builder.ps1')

# L5 -- DO NOT REDIRECT THIS SCRIPT'S STREAMS. An az stderr WARNING becomes a
# terminating error under EAP=Stop, fires `finally`, and tears down a healthy VM.
if ($MyInvocation.Line -match '\*>&1|2>&1') {
    throw "Refusing to run: streams are redirected ($($MyInvocation.Line.Trim())). See L5. Re-run without redirection."
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$run = "{0}-{1}" -f $VmName, (Get-Date -Format 'yyyyMMdd-HHmmss')
$dir = Join-Path $OutDir $run
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$stateFile = Join-Path $OutDir "$VmName.state.json"
function Say($m, $c = 'Cyan') { Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $m" -ForegroundColor $c }
function Save($name, $content) { $content | Out-File (Join-Path $dir $name) -Encoding utf8 }

# --- resumable state --------------------------------------------------------
$script:State = [ordered]@{ vmName = $VmName; resourceGroup = $ResourceGroup; phase = 'init'; child = @{}; run = $run }
if ($Resume -and (Test-Path $stateFile)) {
    try { $prev = Get-Content $stateFile -Raw | ConvertFrom-Json
          $script:State.phase = $prev.phase
          Say "Resuming $VmName from phase '$($prev.phase)'" Yellow } catch { }
}
function Set-Phase([string]$p) {
    $script:State.phase = $p
    [IO.File]::WriteAllText($stateFile, (($script:State | ConvertTo-Json -Depth 5)), (New-Object Text.UTF8Encoding($false)))
    Say "  [state] phase=$p (written to $stateFile)" DarkGray
}

# --- Invoke-Rc -- the ONE way this harness talks to run-command (L2/L4/L7) ----
function Invoke-Rc {
    param([string]$Script, [string]$Label = 'run-command')
    $f = Join-Path ([IO.Path]::GetTempPath()) ("cfv-rc-{0}.ps1" -f [Guid]::NewGuid())
    try {
        [IO.File]::WriteAllText($f, $Script, (New-Object Text.UTF8Encoding($false)))
        $out = az vm run-command invoke -g $ResourceGroup -n $VmName `
                 --command-id RunPowerShellScript --scripts "@$f" `
                 --query "value[].message" -o tsv
        if ($LASTEXITCODE -ne 0) { throw "$Label : az run-command exited $LASTEXITCODE" }
        return ($out -join "`n")
    } finally { Remove-Item $f -Force -ErrorAction SilentlyContinue }
}

# --- Retrieve-VmFile -- pull one VM file out via a FRESH SAS PUT + verified
# download. Returns the local path if it landed, else $null (loud, non-fatal --
# the caller's evidence gate decides what a missing channel means). L16: a PUT
# can fail while the local size still prints, so verify the blob actually exists.
function Retrieve-VmFile {
    param([string]$VmPath, [string]$BlobName, [string]$LocalPath, [string]$Key, [string]$Expiry)
    $sas = az storage blob generate-sas --account-name $StorageAcct --account-key $Key --container-name $Container --name $BlobName --permissions cw --expiry $Expiry -o tsv
    $url = "https://$StorageAcct.blob.core.windows.net/$Container/$BlobName`?$sas"
    $put = Invoke-Rc ("if (-not (Test-Path '$VmPath')) { 'MISSING_ON_VM' } else { Invoke-WebRequest -Uri '$url' -Method Put -Headers @{'x-ms-blob-type'='BlockBlob'} -InFile '$VmPath' -UseBasicParsing | Out-Null; `"UPLOADED=`$((Get-Item '$VmPath').Length)`" }") "upload $BlobName"
    if ($put -match 'MISSING_ON_VM')   { Say "  $VmPath absent on VM (channel missing)" Yellow; return $null }
    if ($put -notmatch 'UPLOADED=\d+') { Say "  upload of $BlobName did not confirm: $put" Yellow; return $null }
    if ("$(az storage blob exists --account-name $StorageAcct --account-key $Key --container-name $Container --name $BlobName --query exists -o tsv)" -ne 'true') {
        Say "  $BlobName did NOT land in blob (PUT failed -- SAS/network)" Yellow; return $null
    }
    az storage blob download --account-name $StorageAcct --account-key $Key --container-name $Container --name $BlobName --file $LocalPath --overwrite --output none
    return $LocalPath
}

# --- read the provider key from Credential Manager as base64(UTF8), no echo ---
function Read-CredAsBase64([string]$Target) {
    Add-Type -Namespace CFR -Name Cred -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential, CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public struct CREDENTIAL { public uint Flags; public uint Type; public string TargetName; public string Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public uint CredentialBlobSize; public System.IntPtr CredentialBlob; public uint Persist; public uint AttributeCount; public System.IntPtr Attributes; public string TargetAlias; public string UserName; }
[System.Runtime.InteropServices.DllImport("Advapi32.dll", EntryPoint="CredReadW", CharSet=System.Runtime.InteropServices.CharSet.Unicode, SetLastError=true)]
public static extern bool CredRead(string target, uint type, uint flags, out System.IntPtr credential);
[System.Runtime.InteropServices.DllImport("Advapi32.dll", EntryPoint="CredFree")]
public static extern void CredFree(System.IntPtr cred);
public static string ReadB64(string target) {
    System.IntPtr p;
    if (!CredRead(target, 1, 0, out p)) return null;
    try {
        CREDENTIAL c = (CREDENTIAL)System.Runtime.InteropServices.Marshal.PtrToStructure(p, typeof(CREDENTIAL));
        byte[] blob = new byte[c.CredentialBlobSize];
        System.Runtime.InteropServices.Marshal.Copy(c.CredentialBlob, blob, 0, (int)c.CredentialBlobSize);
        string secret = System.Text.Encoding.Unicode.GetString(blob);        // stored UTF-16LE
        return System.Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(secret));
    } finally { CredFree(p); }
}
'@ -Language CSharp
    return [CFR.Cred]::ReadB64($Target)
}


try {
    # ---- 0. Preflight -----------------------------------------------------
    Say "Preflight: subscription Enabled (verify via az rest -- the cached profile has lied), image present, combined artifact present + hash + SIGNED."
    $sub = az account show --query id -o tsv
    $sstate = az rest --method get --url "https://management.azure.com/subscriptions/$sub`?api-version=2020-01-01" --query state -o tsv
    if ($sstate -ne 'Enabled') { throw "Subscription is '$sstate', not Enabled. Stop." }
    if (-not (az image show -g $ResourceGroup -n $Image --query id -o tsv 2>$null)) { throw "Baseline image $Image not found in $ResourceGroup." }
    if (-not (Test-Path $CombinedExe)) { throw "Combined installer not found at $CombinedExe -- build+sign it first (scripts\build_release.ps1)." }
    $localSha = (Get-FileHash $CombinedExe -Algorithm SHA256).Hash.ToLower()
    if ($localSha -ne $CombinedSha256.ToLower()) { throw "Combined installer hash mismatch: local $localSha != expected $CombinedSha256. STOP (L: hash mismatch anywhere = stop) -- a rebuild would change the bytes; re-pin only from a fresh signed build." }
    Say "  local combined artifact sha256 verified: $localSha" Green
    # The combined installer MUST be signed -- an unsigned build (graceful signing gate)
    # is a silent ship-blocker. Verify Authenticode locally before we validate behavior.
    $sig = Get-AuthenticodeSignature $CombinedExe
    if ($sig.Status -ne 'Valid') { throw "Combined installer Authenticode is '$($sig.Status)', not Valid. Refusing to validate an unsigned/broken build." }
    Say "  combined artifact signature: Valid ($($sig.SignerCertificate.Subject); timestamped=$([bool]$sig.TimeStamperCertificate))" Green
    if (-not $Resume) {
        if (az vm list -g $ResourceGroup --query "[?name=='$VmName'].name" -o tsv) { throw "VM $VmName already exists -- refusing to double-provision. Use -Resume, or tear it down." }
    }
    # Provider key must be readable now, or the functional matrix (live agent) cannot run.
    if (-not $SeedKeyB64) { $SeedKeyB64 = Read-CredAsBase64 $ProviderKeyTarget }
    if (-not $SeedKeyB64) { throw "Provider key not found in Credential Manager at '$ProviderKeyTarget'. The live-agent functional matrix (5.2) cannot run without it. Seed it, or pass -SeedKeyB64." }
    Say "  provider key present (read from Credential Manager; value never printed)" DarkGray

    $resumePhase = if ($Resume) { $script:State.phase } else { 'init' }
    $skipTo = @{ init = 0; provisioned = 1; staged = 2; armed = 3; done = 4 }
    $at = if ($skipTo.ContainsKey($resumePhase)) { $skipTo[$resumePhase] } else { 0 }

    # ---- 1. Provision -----------------------------------------------------
    if ($at -lt 1) {
        Say "Provisioning $VmName ($Size, $Image, security-type Standard, non-zonal)..."
        $pw = -join ((65..90)+(97..122)+(48..57)+(33,35,37,42) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
        az vm create -g $ResourceGroup -n $VmName --image $Image --size $Size `
            --admin-username $AdminUser --admin-password $pw `
            --security-type Standard --public-ip-sku Standard --nsg-rule NONE `
            --os-disk-name "$VmName-osdisk" --public-ip-address "$VmName-pip" --nsg "$VmName-nsg" `
            --subnet (az network vnet subnet show -g $ResourceGroup --vnet-name bake-vmVNET -n bake-vmSubnet --query id -o tsv) `
            --output none
        # L6: an az failure does NOT throw. Check $LASTEXITCODE, then ASK THE VM
        # (OSProvisioningTimedOut is advisory for this custom image; a Failed
        # provisioning state means run-command will not work -- catch it fast).
        if ($LASTEXITCODE -ne 0) {
            Say "az vm create exit $LASTEXITCODE -- asking the VM whether it came up..." Yellow
            $codes = @(az vm get-instance-view -g $ResourceGroup -n $VmName --query "instanceView.statuses[].code" -o tsv 2>$null)
            if ($codes -notcontains 'PowerState/running') { throw "az vm create failed (exit $LASTEXITCODE) and VM not running (statuses: $($codes -join ', '))." }
            if ($codes -match 'ProvisioningState/failed') { throw "INFRA: $VmName reached terminal provisioning-Failed (OSProvisioningTimedOut lottery). run-command will not work -- retry a FRESH VM name. Not a product/harness fault." }
            Say "  ...VM running, provisioning not failed. Continuing." Yellow
        }
        # SWEEP LIST -- a killed process cannot run finally (L8). Record now so a
        # leftover is deletable by name via job3-teardown.ps1 / azure-sweep.
        Add-Content -Path (Join-Path $OutDir 'ACTIVE_VMS.txt') -Value "$VmName $ResourceGroup" -Encoding ascii
        $script:State.child = @{ osDisk = "$VmName-osdisk"; pip = "$VmName-pip"; nsg = "$VmName-nsg"; nic = "${VmName}VMNic" }
        Set-Phase 'provisioned'
        Say "Provisioned. (admin password generated in-memory; never printed or written)" Green

        # Wait for the guest agent Ready (run-command wedges with no timeout otherwise -- trap 6).
        Say "Waiting for the VM agent to report Ready..."
        $agentOk = $false
        foreach ($i in 1..24) {
            $ag = @(az vm get-instance-view -g $ResourceGroup -n $VmName --query "instanceView.vmAgent.statuses[].displayStatus" -o tsv 2>$null)
            if ($ag -match 'Ready') { $agentOk = $true; Say "  agent: Ready" Green; break }
            Say "  agent: $($ag -join ',') ($i/24)" DarkGray; Start-Sleep -Seconds 15
        }
        if (-not $agentOk) { throw "VM agent never Ready after ~6 min -- HARNESS/INFRA failure (bad deploy), NOT a product verdict. Redeploy a fresh VM name." }
        if ((az vm show -g $ResourceGroup -n $VmName --query "provisioningState" -o tsv 2>$null) -eq 'Failed') { throw "INFRA: provisioningState=Failed. run-command will not work -- retry a fresh VM name." }

        Set-Phase 'provisioned'
    } else { Say "Resume: provision already done (VM $VmName)." Yellow }

    # ---- 2. Stage combined installer + probe + suite ----------------------
    if ($at -lt 2) {
        Say "Staging the SIGNED combined installer + probe + adversarial suite..."
        $key = az storage account keys list -g $ResourceGroup -n $StorageAcct --query "[0].value" -o tsv
        $exp = (Get-Date).ToUniversalTime().AddHours(2).ToString('yyyy-MM-ddTHH:mmZ')
        foreach ($f in @(@{p=$CombinedExe;n=$CombinedBlob}, @{p=$ProbeScript;n='job3-probe.ps1'}, @{p=$AdversarialSuite;n='adversarial-suite.ps1'})) {
            if (-not (Test-Path $f.p)) { throw "Cannot stage '$($f.p)' -- not found." }
            az storage blob upload --account-name $StorageAcct --account-key $key --container-name $Container --name $f.n --file $f.p --overwrite --output none
            Say "  uploaded $($f.n)" DarkGray
        }
        function Sas([string]$name, [string]$perm='r') {
            $s = az storage blob generate-sas --account-name $StorageAcct --account-key $key --container-name $Container --name $name --permissions $perm --expiry $exp -o tsv
            return "https://$StorageAcct.blob.core.windows.net/$Container/$name`?$s"
        }
        $combinedUrl = Sas $CombinedBlob; $probeUrl = Sas 'job3-probe.ps1'; $advUrl = Sas 'adversarial-suite.ps1'
        # ONE-LINE stage script (L2/L7): download all three, verify the combined hash on the VM.
        $stage = "`$ErrorActionPreference='Stop'; New-Item -ItemType Directory -Path C:\cfv -Force | Out-Null; " +
                 "Invoke-WebRequest -Uri '$combinedUrl' -OutFile C:\cfv\combined-setup.exe -UseBasicParsing; " +
                 "Invoke-WebRequest -Uri '$probeUrl' -OutFile C:\cfv\job3-probe.ps1 -UseBasicParsing; " +
                 "Invoke-WebRequest -Uri '$advUrl' -OutFile C:\cfv\adversarial-suite.ps1 -UseBasicParsing; " +
                 "`$hc=(Get-FileHash C:\cfv\combined-setup.exe -Algorithm SHA256).Hash.ToLower(); if (`$hc -ne '$($CombinedSha256.ToLower())') { throw `"COMBINED HASH MISMATCH: `$hc`" }; " +
                 "`"OK staged; combined=`$hc probe=`$((Get-Item C:\cfv\job3-probe.ps1).Length) suite=`$((Get-Item C:\cfv\adversarial-suite.ps1).Length)`""
        $r = Invoke-Rc $stage 'stage'; Save 'stage.txt' $r
        if ($r -notmatch 'OK staged') { throw "Stage did not confirm the combined hash. Output: $r" }
        Set-Phase 'staged'; Say "Staged + combined installer hash verified on the VM. $r" Green
    } else { Say "Resume: staging already done." Yellow }

    # ---- 3. Seed provider key + arm the auto-logon wrapper -----------------
    if ($at -lt 3) {
        Say "Seeding the provider key into $AdminUser's Credential Manager (UTF-16LE), then arming auto-logon + RunOnce -> job3-probe.ps1."
        $pw = -join ((65..90)+(97..122)+(48..57)+(33,35,37,42) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
        # NB (resume): if provisioning happened in a PRIOR run, $pw here is a NEW
        # password. az vm can reset the admin password so auto-logon matches:
        az vm user update -g $ResourceGroup -n $VmName --username $AdminUser --password $pw --output none
        # seed script (CredWrite UTF-16LE), carried base64, key never printed
        $seedPs = @"
`$ErrorActionPreference='Stop'
Add-Type -Namespace CFW -Name Cred -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential, CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public struct CREDENTIAL { public uint Flags; public uint Type; public string TargetName; public string Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public uint CredentialBlobSize; public System.IntPtr CredentialBlob; public uint Persist; public uint AttributeCount; public System.IntPtr Attributes; public string TargetAlias; public string UserName; }
[System.Runtime.InteropServices.DllImport("Advapi32.dll", EntryPoint="CredWriteW", CharSet=System.Runtime.InteropServices.CharSet.Unicode, SetLastError=true)]
public static extern bool CredWrite(ref CREDENTIAL c, uint f);
public static bool Write(string target, string secret) {
    byte[] blob = System.Text.Encoding.Unicode.GetBytes(secret);
    System.IntPtr p = System.Runtime.InteropServices.Marshal.AllocHGlobal(blob.Length);
    System.Runtime.InteropServices.Marshal.Copy(blob, 0, p, blob.Length);
    CREDENTIAL c = new CREDENTIAL(); c.Type = 1; c.TargetName = target; c.CredentialBlobSize = (uint)blob.Length;
    c.CredentialBlob = p; c.Persist = 2; c.UserName = "clawfactory";
    bool ok = CredWrite(ref c, 0); System.Runtime.InteropServices.Marshal.FreeHGlobal(p); return ok;
}
'@ -Language CSharp
`$k=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$SeedKeyB64'))
if(-not [CFW.Cred]::Write('$SeedKeyTarget',`$k)){ throw 'CredWrite failed' }
`$k=`$null
'seeded' | Out-File C:\cfv\seed-ok.txt -Encoding ascii
"@
        $seedEnc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($seedPs))
        # wrapper.cmd runs in the clawadmin session on next boot: seed, then the probe.
        # Built via the shared, render-tested builder -- the probe command is ONE
        # joined line WITH its redirect (cfv-149 split them and lost all evidence).
        $cmdLines = Build-Job3CmdLines -SeedEnc $seedEnc -SeedKeyTarget $SeedKeyTarget
        # Loud guard: exactly 4 cmd lines. A reintroduced multi-line concat re-splits
        # the probe command from its redirect and changes this count -- fail BEFORE
        # arming a broken wrapper rather than after losing a whole run.
        if ($cmdLines.Count -ne 4) {
            throw "wrapper.cmd builder produced $($cmdLines.Count) cmd lines, expected 4 -- the probe command was likely re-split from its output redirect (cfv-149 signature). Refusing to arm a broken wrapper."
        }
        $cmdB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(($cmdLines -join "`r`n") + "`r`n"))
        $arm = "`$ErrorActionPreference='Stop'; " +
               "[IO.File]::WriteAllBytes('C:\cfv\wrapper.cmd', [Convert]::FromBase64String('$cmdB64')); " +
               "`$w='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; " +
               "Set-ItemProperty `$w AutoAdminLogon '1'; Set-ItemProperty `$w DefaultUserName '$AdminUser'; " +
               "Set-ItemProperty `$w DefaultPassword '$pw'; Set-ItemProperty `$w AutoLogonCount 1 -Type DWord; " +
               "Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' CFV-Job3 'cmd /c C:\cfv\wrapper.cmd'; " +
               "'armed'"
        $r = Invoke-Rc $arm 'arm'; Save 'arm.txt' $r
        if ($r -notmatch 'armed') { throw "Arm did not confirm (suspect a mangled/oversized script, L2). Do not reboot into a half-written wrapper. Output: $r" }
        Set-Phase 'armed'
        Say "Armed. Rebooting into the auto-logon clawadmin session to run the JOB 3 sequence..." Yellow
        az vm restart -g $ResourceGroup -n $VmName --output none
    } else { Say "Resume: wrapper already armed." Yellow }

    # ---- 4. Poll for JOB3_DONE (combined install + matrix + adversarial) ---
    if ($at -lt 4) {
        Say "Polling for JOB3_DONE (combined install ~15min + agent warm-up + matrix + adversarial; up to ~90 min)..."
        $done = $false
        foreach ($i in 1..120) {
            Start-Sleep -Seconds 45
            # surface incremental markers so a watcher (or a resumed run) can see progress
            $p = Invoke-Rc "if (Test-Path C:\cfv\JOB3_DONE.txt) { 'JOB3_DONE' } else { (Get-ChildItem C:\cfv\*.marker -EA SilentlyContinue | ForEach-Object Name) -join ',' -replace '^$','PENDING' }" 'poll'
            if ($p -match 'JOB3_DONE') { $done = $true; Say "JOB 3 sequence finished on the VM." Green; break }
            if ($i % 4 -eq 0) { Say "  ...running ($i/120, ~$([int]($i*0.75))min) markers: $p" DarkGray }
        }
        if (-not $done) { throw "JOB 3 sequence did not report JOB3_DONE within ~90 min. If run-command wedged this is a HARNESS failure -- resume (-Resume) or retry a fresh VM before blaming the product." }
        Set-Phase 'done'
    }

    # ---- 5. Retrieve BOTH evidence channels (fresh SAS -- L16) -------------
    # cfv-149 relied on ONE channel (the wrapper's redirect) and lost everything
    # when a builder bug orphaned it. Retrieve TWO independent channels: the
    # wrapper redirect (job3-out.txt) AND the probe's own transcript
    # (job3-out-probe.txt, producer-owned). The gate below requires a valid one.
    Say "Retrieving BOTH evidence channels via blob (wrapper redirect + probe transcript)..."
    $key  = az storage account keys list -g $ResourceGroup -n $StorageAcct --query "[0].value" -o tsv
    $dExp = (Get-Date).ToUniversalTime().AddHours(2).ToString('yyyy-MM-ddTHH:mmZ')     # FRESH, not the staging window
    $localMain  = Retrieve-VmFile 'C:\cfv\job3-out.txt'       "job3-out-$VmName.txt"       (Join-Path $dir 'job3-out.txt')       $key $dExp
    $localProbe = Retrieve-VmFile 'C:\cfv\job3-out-probe.txt' "job3-out-probe-$VmName.txt" (Join-Path $dir 'job3-out-probe.txt') $key $dExp
    Say ("  channels retrieved -> main: {0} | probe-transcript: {1}" -f `
         $(if ($localMain)  { "$((Get-Item $localMain).Length) B" }  else { 'MISSING' }),
         $(if ($localProbe) { "$((Get-Item $localProbe).Length) B" } else { 'MISSING' })) Cyan

    # ---- 5b. EVIDENCE-BEFORE-TEARDOWN GATE (never fake-success again) ------
    # cfv-149 tore down on a 102-byte cmd-error "bundle" and reported exit 0.
    # Require the producer sentinel JOB3_PROBE_COMPLETE above the size floor in at
    # least one retrieved channel; otherwise DEALLOCATE + PRESERVE (do not delete).
    if (Test-Job3Evidence -Files @($localMain, $localProbe) -FloorBytes 512) {
        Say "Evidence gate PASSED: JOB3_PROBE_COMPLETE present above the 512-byte floor." Green
    } else {
        $script:Preserved = $true    # tell `finally` NOT to tear down (unconditional preserve)
        Write-Host "`n===== EVIDENCE_MISSING =====" -ForegroundColor Red
        Say "No retrieved channel carries JOB3_PROBE_COMPLETE above 512 B -- refusing to tear down $VmName." Red
        Say ("  main={0}  probe-transcript={1}" -f `
             $(if ($localMain)  { "$localMain ($((Get-Item $localMain).Length) B)" }  else { 'NONE' }),
             $(if ($localProbe) { "$localProbe ($((Get-Item $localProbe).Length) B)" } else { 'NONE' })) Red
        Say "  DEALLOCATING + PRESERVING $VmName for salvage, then: .\job3-teardown.ps1 -VmName $VmName" Red
        az vm deallocate -g $ResourceGroup -n $VmName --output none 2>$null
        Save 'EVIDENCE-MISSING-preserved.txt' "EVIDENCE_MISSING at $(Get-Date -Format s). $VmName deallocated + preserved. main=$localMain probe=$localProbe. Salvage C:\cfv\job3-out*.txt on the VM, then job3-teardown.ps1 -VmName $VmName."
        throw "EVIDENCE_MISSING: no valid evidence channel; $VmName deallocated + preserved (not torn down)."
    }
    Write-Host "`n===== JOB 3 EVIDENCE BUNDLE (main channel) =====" -ForegroundColor Cyan
    if ($localMain) { Get-Content $localMain } else { Say "(main channel missing; probe transcript retrieved at $localProbe)" Yellow }
}
catch {
    Say "DRIVER ERROR: $($_.Exception.Message)" Red
    if ($PreserveOnFail -and -not $KeepVm) {
        Say "FAIL path (-PreserveOnFail): DEALLOCATING (stop compute cost) and PRESERVING $VmName for diagnosis." Red
        az vm deallocate -g $ResourceGroup -n $VmName --output none 2>$null
        Say "  $VmName deallocated. Still incurring DISK cost. Diagnose, then: .\job3-teardown.ps1 -VmName $VmName" Red
        Save 'FAIL-preserved.txt' "Preserved (deallocated) for diagnosis at $(Get-Date -Format s). Tear down by hand with job3-teardown.ps1 -VmName $VmName."
        $script:Preserved = $true
    }
    throw
}
finally {
    # ---- 6. Teardown -- ALWAYS, via the STANDALONE script (L3/L10). --------
    if ($KeepVm) {
        Say "!! -KeepVm SET: $VmName IS STILL RUNNING AND BILLING. Delete with job3-teardown.ps1 when done. !!" Red
    } elseif ($script:Preserved) {
        Say "FAIL-preserved: leaving $VmName deallocated for diagnosis (see FAIL-preserved.txt). Not deleting." Yellow
    } else {
        & (Join-Path $PSScriptRoot 'job3-teardown.ps1') -VmName $VmName -ResourceGroup $ResourceGroup -OutDir $OutDir
        Copy-Item (Join-Path $OutDir "$VmName.teardown-proof.txt") $dir -ErrorAction SilentlyContinue
    }
    Say "Evidence in $dir" Green
}
