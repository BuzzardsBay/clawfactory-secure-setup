<#
  Provision + stage a release-gate box for the v1.4.0 validation completion run.

  WHY THIS EXISTS RATHER THAN interim-v120-validate.ps1
  ------------------------------------------------------
  The v1.2.0 driver arms a ONE-SHOT auto-logon, and to do that it must know the
  admin credential. It gets there by resetting the account: `az vm user update`
  at step 3, then `net user` from SYSTEM at arm time, then DefaultPassword under
  Winlogon. PROMPT 15 forbids exactly that: the operator sets the password once,
  at provisioning, and nothing afterwards overwrites it. The previous session
  deviated from the rule, and the predicted second-order cost landed: one
  forbidden call created the need for another and the operator's credential
  stopped working.

  This script does not fix the v1.2.0 driver. Fixing the instrument that
  produced the results this run is about to trust is the wrong order, and the
  fix is carded. This script simply does not need the credential, because it
  does not arm anything.

  WHAT IT COSTS, STATED SO IT IS PLANNED FOR RATHER THAN DISCOVERED
  -----------------------------------------------------------------
  No auto-logon. wrapper.cmd is written to the box but nothing launches it, so
  the operator starts it by hand in an RDP session. That is one interactive
  login before the install and one more after the reboot pass. Two logins is the
  correct price of the rule, not a defect to engineer around.

  WHAT STILL HAPPENS WITHOUT AN INTERACTIVE SESSION
  -------------------------------------------------
  Everything that is pure Windows file work: provision, the RDP rule, the blob
  staging, the artifact hash re-verification on the box, and writing wrapper.cmd.
  run-command executes as SYSTEM and SYSTEM cannot see a WSL distro registered
  to clawadmin, so no WSL work is attempted here. That is the runner's job and
  the runner lives in the operator's session.

  SEQUENCE
  --------
    1. preflight, including the artifact digest and byte count
    2. provision, NSG rule scoped to one /32
    3. stage, and re-verify the digest ON THE BOX
    4. write wrapper.cmd (seed key, start runner, run the install probe)
    5. print Card 1 and stop. Polling is a separate step so the operator is
       never waiting on this process.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VmName,
    [string]$ResourceGroup = 'clawfactory-validation',
    [string]$Image         = 'clawfactory-win11-baseline-v2',
    [string]$Size          = 'Standard_D2s_v4',
    [string]$StorageAcct   = 'clawfactoryvalc467',
    [string]$Container     = 'validation',
    [string]$AdminUser     = 'clawadmin',
    [string]$SeedKeyTarget = 'ClawFactory/AnthropicApiKey',
    [string]$Sha256        = 'b2cd6408e5d6fe39116c6e5c559f7de6cf86b2ac2d7a4a8e9093e399edb8c6a1',
    [long]$ExpectBytes     = 440609096,
    [string]$Phase1Script  = 'interim-v120-phase1.ps1',
    [string]$Phase1Extra   = 'none',
    [string]$InstallProvider = 'claude',
    [string]$OutDir        = ''
)

$ErrorActionPreference = 'Stop'

# [CmdletBinding()] + -File empties $PSScriptRoot inside param defaults, so
# every path is resolved in the body.
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'validation-runs' }
$CombinedExe = Join-Path $RepoRoot 'Output\ClawFactory-Secure-Setup.exe'
$run = "$VmName-box-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$dir = Join-Path $OutDir $run
New-Item -ItemType Directory -Path $dir -Force | Out-Null

function Say($m, $c = 'Cyan') { Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $m" -ForegroundColor $c }
function Save($name, $content) { $content | Out-File (Join-Path $dir $name) -Encoding utf8 }

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

function Read-CredAsBase64([string]$Target) {
    Add-Type -Namespace CFR2 -Name Cred -MemberDefinition @'
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
        return System.Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(System.Text.Encoding.Unicode.GetString(blob)));
    } finally { CredFree(p); }
}
'@ -Language CSharp
    return [CFR2.Cred]::ReadB64($Target)
}

# ---- 1. Preflight ----------------------------------------------------------
Say 'Preflight.'
$sub = az account show --query id -o tsv
$sstate = az rest --method get --url "https://management.azure.com/subscriptions/$sub`?api-version=2020-01-01" --query state -o tsv
if ($sstate -ne 'Enabled') { throw "Subscription is '$sstate', not Enabled. Stop." }
Say '  subscription: Enabled' Green

if (-not (az image show -g $ResourceGroup -n $Image --query id -o tsv 2>$null)) { throw "Image $Image not found in $ResourceGroup." }
Say "  image present: $Image" Green

if (-not (Test-Path $CombinedExe)) { throw "Artifact not found at $CombinedExe." }
$len = (Get-Item $CombinedExe).Length
if ($len -ne $ExpectBytes) { throw "Artifact size $len != expected $ExpectBytes. STOP, wrong binary." }
$localSha = (Get-FileHash $CombinedExe -Algorithm SHA256).Hash.ToLower()
if ($localSha -ne $Sha256) { throw "Artifact hash mismatch: $localSha != $Sha256. STOP." }
$sig = Get-AuthenticodeSignature $CombinedExe
if ($sig.Status -ne 'Valid') { throw "Artifact Authenticode is '$($sig.Status)', not Valid." }
Say "  artifact verified: $localSha ($len bytes), Authenticode Valid" Green

if (az vm list -g $ResourceGroup --query "[?name=='$VmName'].name" -o tsv) { throw "VM $VmName already exists." }

$SeedKeyB64 = Read-CredAsBase64 $SeedKeyTarget
if (-not $SeedKeyB64) { throw "Provider key absent from Credential Manager at '$SeedKeyTarget'." }
Say '  provider key present (value never printed)' DarkGray

# The /32 for the RDP rule. Detected live rather than carried forward from a
# previous run, because a stale address opens a hole for someone else and closes
# the door on the operator.
$myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 20).ip
if ($myIp -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw "Could not detect a public IPv4 for the RDP rule (got '$myIp')." }
Say "  build machine public IP: $myIp" Green

# ---- 2. Provision ----------------------------------------------------------
Say "Provisioning $VmName ($Size, $Image)..."
# Generated here only so `az vm create` has a value. The operator replaces it at
# Card 1 and NOTHING in this harness ever writes the account password again.
$bootstrapPw = -join ((65..90)+(97..122)+(48..57)+(33,35,37,42) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
az vm create -g $ResourceGroup -n $VmName --image $Image --size $Size `
    --admin-username $AdminUser --admin-password $bootstrapPw `
    --security-type Standard --public-ip-sku Standard --nsg-rule NONE `
    --os-disk-name "$VmName-osdisk" --public-ip-address "$VmName-pip" --nsg "$VmName-nsg" `
    --subnet (az network vnet subnet show -g $ResourceGroup --vnet-name bake-vmVNET -n bake-vmSubnet --query id -o tsv) `
    --output none
if ($LASTEXITCODE -ne 0) {
    $codes = @(az vm get-instance-view -g $ResourceGroup -n $VmName --query "instanceView.statuses[].code" -o tsv 2>$null)
    if ($codes -notcontains 'PowerState/running') { throw "az vm create failed and VM not running (statuses: $($codes -join ', '))." }
    if ($codes -match 'ProvisioningState/failed') { throw 'INFRA: terminal provisioning-Failed. Retry a FRESH VM name.' }
    Say '  ...VM running despite a nonzero exit. Continuing.' Yellow
}
$bootstrapPw = $null
Add-Content -Path (Join-Path $OutDir 'ACTIVE_VMS.txt') -Value "$VmName $ResourceGroup $(Get-Date -Format s)" -Encoding ascii
Say 'Provisioned.' Green

az network nsg rule create -g $ResourceGroup --nsg-name "$VmName-nsg" -n allow-rdp `
    --priority 300 --access Allow --protocol Tcp --direction Inbound `
    --source-address-prefixes "$myIp/32" --destination-port-ranges 3389 --output none
if ($LASTEXITCODE -ne 0) { throw "Could not create the RDP rule (az exit $LASTEXITCODE)." }
$rdpBack = az network nsg rule show -g $ResourceGroup --nsg-name "$VmName-nsg" -n allow-rdp --query "sourceAddressPrefix" -o tsv
if ($rdpBack -ne "$myIp/32") { throw "RDP rule read back as '$rdpBack', expected '$myIp/32'." }
Say "  RDP rule confirmed by read-back: $rdpBack" Green

$pip = az network public-ip show -g $ResourceGroup -n "$VmName-pip" --query ipAddress -o tsv
Say "  public IP: $pip" Green

Say 'Waiting for the VM agent to report Ready...'
$agentOk = $false
foreach ($i in 1..24) {
    $ag = @(az vm get-instance-view -g $ResourceGroup -n $VmName --query "instanceView.vmAgent.statuses[].displayStatus" -o tsv 2>$null)
    if ($ag -match 'Ready') { $agentOk = $true; Say '  agent: Ready' Green; break }
    Say "  agent: $($ag -join ',') ($i/24)" DarkGray; Start-Sleep -Seconds 15
}
if (-not $agentOk) { throw 'VM agent never Ready after ~6 min. INFRA failure, not a product verdict.' }

# ---- 3. Stage --------------------------------------------------------------
Say 'Staging artifact, probe, runner, channel and phase runner...'
$key = az storage account keys list -g $ResourceGroup -n $StorageAcct --query "[0].value" -o tsv
if ($LASTEXITCODE -ne 0 -or -not $key) { throw "Could not read a storage key for $StorageAcct." }
$exp = (Get-Date).ToUniversalTime().AddHours(4).ToString('yyyy-MM-ddTHH:mmZ')
az storage container create --account-name $StorageAcct --account-key $key --name $Container --output none 2>$null

$files = @(
    @{ p = $CombinedExe; n = "combined-$VmName.exe" },
    @{ p = (Join-Path $PSScriptRoot $Phase1Script);               n = $Phase1Script },
    @{ p = (Join-Path $PSScriptRoot 'interim-v120-runner.ps1');   n = 'interim-v120-runner.ps1' },
    @{ p = (Join-Path $PSScriptRoot 'interim-v120-wslchan.ps1');  n = 'interim-v120-wslchan.ps1' },
    @{ p = (Join-Path $PSScriptRoot 'interim-v120-phaselib.ps1'); n = 'interim-v120-phaselib.ps1' },
    @{ p = (Join-Path $PSScriptRoot 'harness-selftest.ps1');      n = 'harness-selftest.ps1' }
)
foreach ($f in $files) {
    if (-not (Test-Path $f.p)) { throw "Cannot stage '$($f.p)', not found." }
    az storage blob upload --account-name $StorageAcct --account-key $key --container-name $Container `
        --name $f.n --file $f.p --overwrite --output none
    if ($LASTEXITCODE -ne 0) { throw "Upload of $($f.n) failed (az exit $LASTEXITCODE)." }
    $remote = az storage blob show --account-name $StorageAcct --account-key $key --container-name $Container `
                --name $f.n --query "properties.contentLength" -o tsv
    $localLen = (Get-Item $f.p).Length
    if ("$remote" -ne "$localLen") { throw "Upload of $($f.n) landed $remote bytes, expected $localLen." }
    Say "  uploaded $($f.n) ($localLen bytes, confirmed at the service)" DarkGray
}
function Sas([string]$name) {
    $s = az storage blob generate-sas --account-name $StorageAcct --account-key $key `
           --container-name $Container --name $name --permissions r --expiry $exp -o tsv
    return "https://$StorageAcct.blob.core.windows.net/$Container/$name`?$s"
}
$uExe = Sas "combined-$VmName.exe"; $uP1 = Sas $Phase1Script
$uRun = Sas 'interim-v120-runner.ps1'; $uCh = Sas 'interim-v120-wslchan.ps1'
$uLib = Sas 'interim-v120-phaselib.ps1'; $uSt = Sas 'harness-selftest.ps1'

$stage = "`$ErrorActionPreference='Stop'; New-Item -ItemType Directory -Path C:\cfv\jobs -Force | Out-Null; New-Item -ItemType Directory -Path C:\cfv\wsl -Force | Out-Null; " +
         "Invoke-WebRequest -Uri '$uExe' -OutFile C:\cfv\combined-setup.exe -UseBasicParsing; " +
         "Invoke-WebRequest -Uri '$uP1' -OutFile C:\cfv\$Phase1Script -UseBasicParsing; " +
         "Invoke-WebRequest -Uri '$uRun' -OutFile C:\cfv\interim-v120-runner.ps1 -UseBasicParsing; " +
         "Invoke-WebRequest -Uri '$uCh' -OutFile C:\cfv\interim-v120-wslchan.ps1 -UseBasicParsing; " +
         "Invoke-WebRequest -Uri '$uLib' -OutFile C:\cfv\interim-v120-phaselib.ps1 -UseBasicParsing; " +
         "Invoke-WebRequest -Uri '$uSt' -OutFile C:\cfv\harness-selftest.ps1 -UseBasicParsing; " +
         "`$h=(Get-FileHash C:\cfv\combined-setup.exe -Algorithm SHA256).Hash.ToLower(); " +
         "if (`$h -ne '$Sha256') { throw `"ARTIFACT HASH MISMATCH ON VM: `$h`" }; " +
         "`"OK staged; artifact=`$h size=`$((Get-Item C:\cfv\combined-setup.exe).Length)`""
$r = Invoke-Rc $stage 'stage'; Save 'stage.txt' $r
if ($r -notmatch 'OK staged') { throw "Stage did not confirm the artifact hash on the VM. Output: $r" }
Say "Staged, digest re-verified ON THE BOX. $r" Green

# ---- 4. Write wrapper.cmd, but arm NOTHING ---------------------------------
# Same four lines the v1.2.0 driver writes, and the same one-physical-line rule
# per command: cfv-149 lost a run to a multi-line concat that PowerShell parsed
# as separate array elements and silently orphaned a redirect.
Say 'Writing wrapper.cmd. No auto-logon is armed and no account password is written.'
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
$probeArgs = @(
    '-NoProfile','-ExecutionPolicy','Bypass',
    '-File',"C:\cfv\$Phase1Script",
    '-CombinedExe','C:\cfv\combined-setup.exe',
    $(if ($Phase1Extra -and $Phase1Extra -ne 'none') { $Phase1Extra }),
    '-Provider', $InstallProvider
) -join ' '
$cmdLines = @(
    '@echo off',
    "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $seedEnc",
    'start "cfrunner" powershell -NoProfile -ExecutionPolicy Bypass -File C:\cfv\interim-v120-runner.ps1',
    "powershell $probeArgs > C:\cfv\phase1-out.txt 2>&1",
    'echo PHASE1_DONE > C:\cfv\PHASE1_DONE.txt'
)
if ($cmdLines.Count -ne 5) {
    throw "wrapper.cmd builder produced $($cmdLines.Count) lines, expected 5 (cfv-149 signature). Refusing to write a broken wrapper."
}
$cmdB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(($cmdLines -join "`r`n") + "`r`n"))

# A SEPARATE runner-only launcher, for the SECOND login after the reboot pass.
# wrapper.cmd re-runs the install; after a reboot only the runner is wanted.
$runOnlyB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(
    ("@echo off`r`nstart `"cfrunner`" powershell -NoProfile -ExecutionPolicy Bypass -File C:\cfv\interim-v120-runner.ps1`r`n")))

$write = "`$ErrorActionPreference='Stop'; " +
         "[IO.File]::WriteAllBytes('C:\cfv\wrapper.cmd', [Convert]::FromBase64String('$cmdB64')); " +
         "[IO.File]::WriteAllBytes('C:\cfv\start-runner.cmd', [Convert]::FromBase64String('$runOnlyB64')); " +
         "`$w='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; " +
         # Assert, do not set. If a baked-in auto-logon exists it would consume
         # the operator's session before they see it, and a silent surprise is
         # worse than a loud one.
         "`$al=(Get-ItemProperty `$w -Name AutoAdminLogon -EA SilentlyContinue).AutoAdminLogon; " +
         "`"WROTE wrapper=`$((Get-Item C:\cfv\wrapper.cmd).Length) runner=`$((Get-Item C:\cfv\start-runner.cmd).Length) AutoAdminLogon=`$al`""
$r = Invoke-Rc $write 'write-wrapper'; Save 'wrapper.txt' $r
if ($r -notmatch 'WROTE wrapper=\d+') { throw "wrapper.cmd was not written: $r" }
Say "  $r" Green

Save 'card1.txt' @"
VM        : $VmName
RG        : $ResourceGroup
public IP : $pip
admin user: $AdminUser
RDP rule  : $rdpBack (the build machine, $myIp)
artifact  : $Sha256 ($len bytes), re-verified on the box
"@

Write-Host ''
Write-Host '===== BOX READY, WAITING ON THE OPERATOR =====' -ForegroundColor Yellow
Say "VM $VmName is RUNNING and billing. No auto-logon is armed, by design." Yellow
Say "Evidence dir: $dir" Green
