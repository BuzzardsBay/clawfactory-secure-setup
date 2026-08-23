<#
  Driver for the Guard 4 ground-truth probe and the card #197 follow-up.

  READ-ONLY WITH RESPECT TO THE PRODUCT. It installs a signed 1.3.3 artifact on a
  throwaway VM and measures it. It modifies no product source, builds nothing,
  and everything it writes on the box lives under /var/tmp or C:\cfv.

  WHY THIS DRIVER IS STEP-BASED RATHER THAN FIRE-AND-FORGET
  ---------------------------------------------------------
  Because it cannot run unattended and pretending otherwise is how runs get
  lost. az vm run-command executes as SYSTEM and cannot see a WSL distro
  registered to clawadmin, so every probe here needs the interactive session.
  This job reboots at least twice, and after each reboot a human has to log in
  over RDP and start the on-VM runner by hand before any WSL work can proceed.
  So the driver stops at each of those points and prints a self-contained card.

  WHAT A CARD HAS TO CONTAIN, AND WHY
  ------------------------------------
  Everything needed to act, with real values already substituted. A card that
  says what to do but not the exact command is not a card: it sends the operator
  to reconstruct a step or to ask a different session what to do, and both are
  ways this run stalls silently while the VM bills.

  THE PASSWORD, AND THE ONE THING THAT MUST NOT ORIGINATE HERE
  ------------------------------------------------------------
  The VM admin password cannot come from this session, because the operator has
  to be able to read it later and nothing that reaches this session should be
  readable later. So the operator chooses it, at provisioning, and this driver
  never generates one, never prints one, never asks for one and never calls
  az vm user update.

  That last prohibition has a consequence worth stating rather than working
  around: the driver cannot arm Winlogon auto-logon, because arming it means
  writing the account password into DefaultPassword and the driver does not have
  it. So there is NO auto-logon in this run. The human logs in over RDP for the
  install boot as well as after each reboot, which is one extra login and buys
  the guarantee that the password exists in exactly one place, the operator's
  password manager. Setting it once at az vm create also puts the VMAccess risk
  at the start of the run rather than between reboots, which is what cost an hour
  on cfv-162.
#>
[CmdletBinding()]
param(
    [ValidateSet('plan', 'stage', 'restage', 'install', 'probes', 'reboot', 'postreboot', 'collect', 'teardown', 'status')]
    [string]$Step = 'plan',
    # Comma-separated phase ids to run, e.g. "02-q1,05-q3". Empty means all.
    [string]$Only = '',
    # Clear the .done barrier for the selected phases so they actually re-run.
    # Without this the on-VM runner skips anything already completed, which is
    # the right default after a driver crash and the wrong one after a probe fix.
    [switch]$Rerun,
    [string]$VmName        = 'cfv-165',
    [string]$ResourceGroup = 'clawfactory-validation',
    [string]$Image         = 'clawfactory-win11-baseline-v2',
    [string]$Size          = 'Standard_D2s_v4',
    [string]$StorageAcct   = 'clawfactoryvalc467',
    [string]$Container     = 'validation',
    [string]$AdminUser     = 'clawadmin',
    [string]$SeedKeyTarget = 'ClawFactory/AnthropicApiKey',
    [string]$OutDir        = ''
)

$ErrorActionPreference = 'Stop'

# [CmdletBinding()] + -File empties $PSScriptRoot inside param defaults, so paths
# resolve in the BODY. This exact trap killed build_release.ps1 before gate 1.
$DiagDir  = $PSScriptRoot
$ValDir   = Split-Path -Parent $DiagDir
$RepoRoot = Split-Path -Parent $ValDir
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'validation-runs' }
$CombinedExe = Join-Path $RepoRoot 'Output\ClawFactory-Secure-Setup.exe'

# The pinned input artifact. 1.3.3, signed. Bytes and digest are both checked:
# a size match with a digest mismatch is a different failure from an absent file
# and the message should say which.
$Sha256      = '5bef35dc3a4a944583470bdb0afe893d413d96eafcdf1df0ba66311a417522ab'
$ExpectBytes = 440606872

$dir = Join-Path $OutDir $VmName
New-Item -ItemType Directory -Path $dir -Force | Out-Null

function Say($m, $c = 'Cyan') { Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $m" -ForegroundColor $c }
function Card($title, [string[]]$lines) {
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor Yellow
    Write-Host "  $title" -ForegroundColor Yellow
    Write-Host ('=' * 78) -ForegroundColor Yellow
    foreach ($l in $lines) { Write-Host $l }
    Write-Host ('=' * 78) -ForegroundColor Yellow
    ($lines -join "`r`n") | Out-File (Join-Path $dir ("CARD-" + ($title -replace '[^A-Za-z0-9]', '-') + '.txt')) -Encoding utf8
}

# --- Invoke-Rc: the ONE way this harness talks to run-command (L2/L3/L7).
# az on Windows is az.cmd and cmd.exe re-parses every argument, so the script
# goes in via @file and the query carries no parentheses. Both streams are read.
function Invoke-Rc {
    param([string]$Script, [string]$Label = 'run-command', [int]$Attempts = 3)
    $f = Join-Path ([IO.Path]::GetTempPath()) ("g4-rc-{0}.ps1" -f [Guid]::NewGuid())
    try {
        [IO.File]::WriteAllText($f, $Script, (New-Object Text.UTF8Encoding($false)))
        # RETRIED, because the ARM control plane times out transiently and it did
        # so twice in this run: once reading a storage key, once seeding a
        # credential, both with 'Connection to management.azure.com timed out'.
        # That is not a product fault and it must not be able to end a run that
        # has a live VM billing behind it. A genuine failure fails the same way
        # every attempt and is still reported, with the last error preserved.
        $lastErr = ''
        foreach ($i in 1..$Attempts) {
            # EAP IS DROPPED TO Continue AROUND THE az CALL, and this is the whole
            # reason the retry above exists at all.
            #
            # az writes progress and errors to stderr. Redirecting a NATIVE
            # command's stderr with 2>&1 wraps each line in an ErrorRecord, and
            # under $ErrorActionPreference = 'Stop' that ErrorRecord TERMINATES.
            # So the first timeout threw straight past this loop: the retry was
            # present, correct, and unreachable. Four ARM timeouts in one session
            # and the one that killed a run was the harness, not the network.
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $out = az vm run-command invoke -g $ResourceGroup -n $VmName `
                         --command-id RunPowerShellScript --scripts "@$f" `
                         --query "value[].message" -o tsv 2>&1
            } finally { $ErrorActionPreference = $prevEap }
            if ($LASTEXITCODE -eq 0) { return (($out | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] }) -join "`n") }
            $lastErr = ($out | Out-String).Trim()
            if ($i -lt $Attempts) {
                Write-Host "  [$Label] az exited $LASTEXITCODE on attempt $i of $Attempts, retrying in 20s" -ForegroundColor DarkYellow
                Start-Sleep -Seconds 20
            }
        }
        throw "$Label : az run-command failed $Attempts times. Last error: $lastErr"
    } finally { Remove-Item $f -Force -ErrorAction SilentlyContinue }
}

function Get-StorageKey {
    <#
      The ARM control plane has timed out five times in this session. Invoke-Rc
      retries, but the storage key read is a DIFFERENT az call and was not
      covered, so a collection that had nothing to do with run-command died on
      the same transient. Anything that talks to management.azure.com needs the
      same treatment; this is the second such call and it is now the last one.
    #>
    foreach ($i in 1..3) {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $k = az storage account keys list -g $ResourceGroup -n $StorageAcct --query "[0].value" -o tsv 2>&1
        } finally { $ErrorActionPreference = $prevEap }
        if ($LASTEXITCODE -eq 0 -and $k) { return ("$k").Trim() }
        if ($i -lt 3) { Say "  storage key read failed (attempt $i of 3), retrying in 20s" DarkYellow; Start-Sleep -Seconds 20 }
    }
    throw "could not read a storage key for $StorageAcct after 3 attempts."
}

function Get-VmIp {
    $ip = az vm list-ip-addresses -g $ResourceGroup -n $VmName `
            --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv
    if ($LASTEXITCODE -ne 0) { throw "could not read the VM public IP (az exit $LASTEXITCODE)" }
    return "$ip".Trim()
}

function Assert-Artifact {
    if (-not (Test-Path $CombinedExe)) { throw "Artifact not found at $CombinedExe." }
    $len = (Get-Item $CombinedExe).Length
    if ($len -ne $ExpectBytes) { throw "Artifact size $len != expected $ExpectBytes. STOP, wrong binary." }
    $sha = (Get-FileHash $CombinedExe -Algorithm SHA256).Hash.ToLower()
    if ($sha -ne $Sha256) { throw "Artifact digest $sha != $Sha256. STOP, do not validate a different binary." }
    $sig = Get-AuthenticodeSignature $CombinedExe
    if ($sig.Status -ne 'Valid') { throw "Authenticode is '$($sig.Status)', not Valid." }
    Say "  artifact verified: $sha ($len bytes), signature Valid" Green
}

# ============================================================================
switch ($Step) {

'plan' {
    Say "Preflight for $VmName."
    $sub = az account show --query id -o tsv
    if ($LASTEXITCODE -ne 0) { throw "az account show failed ($LASTEXITCODE)." }
    # The cached profile has lied before; ask the control plane for the real state.
    $sstate = az rest --method get --url "https://management.azure.com/subscriptions/$sub`?api-version=2020-01-01" --query state -o tsv
    if ($sstate -ne 'Enabled') { throw "Subscription is '$sstate', not Enabled." }
    Say "  subscription: Enabled" Green
    if (-not (az image show -g $ResourceGroup -n $Image --query id -o tsv 2>$null)) { throw "Image $Image not found." }
    Say "  image present: $Image" Green
    Assert-Artifact
    if (az vm list -g $ResourceGroup --query "[?name=='$VmName'].name" -o tsv) {
        throw "VM $VmName already exists. Pick a fresh name or tear it down first."
    }
    $subnet = az network vnet subnet show -g $ResourceGroup --vnet-name bake-vmVNET -n bake-vmSubnet --query id -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $subnet) { throw "could not resolve the subnet id." }

    $myIp = ''
    try { $myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 15).Trim() } catch { }
    $hostName = [Environment]::MachineName

    $create = "az vm create -g $ResourceGroup -n $VmName --image $Image --size $Size " +
              "--admin-username $AdminUser --admin-password ""<CHOOSE-A-PASSWORD-AND-SAVE-IT>"" " +
              "--security-type Standard --public-ip-sku Standard --nsg-rule NONE " +
              "--os-disk-name $VmName-osdisk --public-ip-address $VmName-pip --nsg $VmName-nsg " +
              "--subnet $subnet --output none"

    Card "CARD 1 of 3  PROVISION $VmName" @(
        "",
        "WHAT THIS IS. The VM for the Guard 4 ground-truth probe. It has to be created",
        "by you rather than by this session, because you choose the admin password and",
        "nothing that reaches this session should be readable afterwards.",
        "",
        "WHAT YOU DO",
        "  1. Choose a password. Save it in your password manager.",
        "  2. Run the command below with your password in place of the placeholder.",
        "  3. Do NOT paste the password back into this session or into chat.",
        "",
        "THE COMMAND, real values already substituted, one placeholder:",
        "",
        "  $create",
        "",
        "WHAT SUCCESS LOOKS LIKE",
        "  The command returns with no output and exit code 0. It takes 2 to 4 minutes.",
        "  Confirm with:  az vm get-instance-view -g $ResourceGroup -n $VmName --query instanceView.statuses[].code -o tsv",
        "  You want to see PowerState/running.",
        "",
        "IF IT DOES NOT APPEAR",
        "  ProvisioningState/failed is the OSProvisioningTimedOut lottery, not a product",
        "  fault. Delete and retry with a FRESH VM name:",
        "    az vm delete -g $ResourceGroup -n $VmName --yes",
        "  then tell me the new name and I will re-run this step against it.",
        "",
        "ABOUT RDP ACCESS, so you can confirm before you connect later",
        "  Your detected public address is: $(if ($myIp) { $myIp } else { '(detection failed, I will ask you for it)' })",
        "  That address belongs to THIS machine, $hostName, the one running this session.",
        "  The next step scopes the RDP rule to $(if ($myIp) { "$myIp/32" } else { '<your address>/32' }) and nothing else.",
        "  If you will connect from a different machine, or over a VPN that changes your",
        "  exit address, say so now and I will scope the rule to that address instead.",
        "",
        "TELL ME WHEN THE VM IS RUNNING and I will continue with the staging step."
    )
    Say "Waiting on you. Nothing bills until the VM exists." Yellow
}

'stage' {
    Assert-Artifact
    Say "Confirming $VmName exists and is running..."
    $codes = @(az vm get-instance-view -g $ResourceGroup -n $VmName --query "instanceView.statuses[].code" -o tsv)
    if ($LASTEXITCODE -ne 0) { throw "az vm get-instance-view failed ($LASTEXITCODE). Was the VM created?" }
    if ($codes -notcontains 'PowerState/running') { throw "VM is not running (statuses: $($codes -join ', '))." }
    Say "  running" Green
    Add-Content -Path (Join-Path $OutDir 'ACTIVE_VMS.txt') -Value "$VmName $ResourceGroup $(Get-Date -Format s)" -Encoding ascii

    Say "Waiting for the VM agent to report Ready..."
    $agentOk = $false
    foreach ($i in 1..24) {
        $ag = @(az vm get-instance-view -g $ResourceGroup -n $VmName --query "instanceView.vmAgent.statuses[].displayStatus" -o tsv 2>$null)
        if ($ag -match 'Ready') { $agentOk = $true; Say "  agent: Ready" Green; break }
        Say "  agent: $($ag -join ',') ($i/24)" DarkGray; Start-Sleep -Seconds 15
    }
    if (-not $agentOk) { throw "VM agent never Ready after ~6 min. INFRA failure, not a product verdict." }

    # --- RDP, scoped to a /32 -------------------------------------------------
    $myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 15).Trim()
    if (-not ($myIp -match '^\d{1,3}(\.\d{1,3}){3}$')) { throw "public IP detection returned '$myIp', which is not an address." }
    az network nsg rule create -g $ResourceGroup --nsg-name "$VmName-nsg" -n allow-rdp-probe `
        --priority 300 --source-address-prefixes "$myIp/32" --destination-port-ranges 3389 `
        --access Allow --protocol Tcp --direction Inbound --output none
    if ($LASTEXITCODE -ne 0) { throw "could not create the RDP rule (az exit $LASTEXITCODE)." }
    $ruleSrc = az network nsg rule show -g $ResourceGroup --nsg-name "$VmName-nsg" -n allow-rdp-probe --query "sourceAddressPrefix" -o tsv
    Say "  RDP allowed from $ruleSrc only" Green

    # --- stage ---------------------------------------------------------------
    # IDEMPOTENT BY DIGEST. A transient ARM timeout AFTER a successful upload
    # must not cost another 440 MB, and it did exactly that once in this run. So
    # re-running this step skips straight to whatever did not finish.
    #
    # The check is the ARTIFACT DIGEST ON THE VM rather than a local flag,
    # because a local flag is a claim about a box that may have been rebuilt
    # underneath it, and the last probe script is checked alongside it so a
    # half-finished upload cannot read as a complete one.
    $dl = ''
    $alreadyStaged = (Invoke-Rc ("if ((Test-Path C:\cfv\combined-setup.exe) -and " +
        "((Get-FileHash C:\cfv\combined-setup.exe -Algorithm SHA256).Hash.ToLower() -eq '$Sha256') -and " +
        "(Test-Path C:\cfv\g4-q7-baseurl.ps1)) { 'ALREADY_STAGED' } else { 'NOT_STAGED' }") 'stage-check') -match 'ALREADY_STAGED'
    if ($alreadyStaged) {
        Say "Artifact and probe scripts are already on the VM at the pinned digest; skipping the upload." Green
    } else {
    Say "Staging artifact, runner, channel, phase runner and probe phases..."
    $key = Get-StorageKey
    if ($LASTEXITCODE -ne 0 -or -not $key) { throw "could not read a storage key for $StorageAcct." }
    $exp = (Get-Date).ToUniversalTime().AddHours(6).ToString('yyyy-MM-ddTHH:mmZ')
    az storage container create --account-name $StorageAcct --account-key $key --name $Container --output none 2>$null

    $files = @(
        @{ p = $CombinedExe; n = "combined-$VmName.exe" },
        @{ p = (Join-Path $ValDir 'interim-v120-runner.ps1');  n = 'interim-v120-runner.ps1' },
        @{ p = (Join-Path $ValDir 'interim-v120-wslchan.ps1'); n = 'interim-v120-wslchan.ps1' },
        @{ p = (Join-Path $ValDir 'interim-v120-phaselib.ps1'); n = 'interim-v120-phaselib.ps1' },
        @{ p = (Join-Path $ValDir 'interim-v120-phase1.ps1');  n = 'interim-v120-phase1.ps1' },
        @{ p = (Join-Path $DiagDir 'g4-py.ps1');          n = 'g4-py.ps1' },
        @{ p = (Join-Path $DiagDir 'g4-common.ps1');      n = 'g4-common.ps1' },
        @{ p = (Join-Path $DiagDir 'g4-q1-fanotify.ps1'); n = 'g4-q1-fanotify.ps1' },
        @{ p = (Join-Path $DiagDir 'g4-q2-scope.ps1');    n = 'g4-q2-scope.ps1' },
        @{ p = (Join-Path $DiagDir 'g4-q3-volume.ps1');   n = 'g4-q3-volume.ps1' },
        @{ p = (Join-Path $DiagDir 'g4-q4-fuse.ps1');     n = 'g4-q4-fuse.ps1' },
        @{ p = (Join-Path $DiagDir 'g4-q5-cost.ps1');     n = 'g4-q5-cost.ps1' },
        @{ p = (Join-Path $DiagDir 'g4-q6-paths.ps1');    n = 'g4-q6-paths.ps1' },
        @{ p = (Join-Path $DiagDir 'g4-q7-baseurl.ps1');  n = 'g4-q7-baseurl.ps1' }
    )
    $dl = ''
    foreach ($f in $files) {
        if (-not (Test-Path $f.p)) { throw "cannot stage '$($f.p)', not found." }
        az storage blob upload --account-name $StorageAcct --account-key $key --container-name $Container `
            --name $f.n --file $f.p --overwrite --output none
        if ($LASTEXITCODE -ne 0) { throw "upload of $($f.n) failed (az exit $LASTEXITCODE)." }
        # L6: "the command returned" and "the bytes are there" are different claims.
        $remote = az storage blob show --account-name $StorageAcct --account-key $key --container-name $Container `
                    --name $f.n --query "properties.contentLength" -o tsv
        $localLen = (Get-Item $f.p).Length
        if ("$remote" -ne "$localLen") { throw "upload of $($f.n) landed $remote bytes, expected $localLen." }
        $sas = az storage blob generate-sas --account-name $StorageAcct --account-key $key `
                 --container-name $Container --name $f.n --permissions r --expiry $exp -o tsv
        $url = "https://$StorageAcct.blob.core.windows.net/$Container/$($f.n)`?$sas"
        $dest = if ($f.n -like 'combined-*') { 'C:\cfv\combined-setup.exe' } else { "C:\cfv\$($f.n)" }
        $dl += "Invoke-WebRequest -Uri '$url' -OutFile $dest -UseBasicParsing; "
        Say "  uploaded $($f.n) ($localLen bytes, size confirmed at the service)" DarkGray
    }
    }

    # Seed the provider key. Read from Credential Manager, never printed.
    # Runs on every pass, including a resumed one: it is cheap, and the seed is
    # the step that failed the first time round.
    Add-Type -Namespace G4R -Name Cred -MemberDefinition @'
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
    $seedKeyB64 = [G4R.Cred]::ReadB64($SeedKeyTarget)
    if (-not $seedKeyB64) { throw "Provider key absent from Credential Manager at '$SeedKeyTarget'. Questions 3, 5 and 7 all need real agent turns." }
    Say "  provider key present (value never printed)" DarkGray

    $seedPs = @"
`$ErrorActionPreference='Stop'
Add-Type -Namespace G4W -Name Cred -MemberDefinition @'
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
`$k=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$seedKeyB64'))
if(-not [G4W.Cred]::Write('$SeedKeyTarget',`$k)){ throw 'CredWrite failed' }
`$k=`$null
'seeded' | Out-File C:\cfv\seed-ok.txt -Encoding ascii
"@

    $stage = "`$ErrorActionPreference='Stop'; New-Item -ItemType Directory -Path C:\cfv\jobs -Force | Out-Null; " +
             "New-Item -ItemType Directory -Path C:\cfv\wsl -Force | Out-Null; " + $dl +
             "`$h=(Get-FileHash C:\cfv\combined-setup.exe -Algorithm SHA256).Hash.ToLower(); " +
             "if (`$h -ne '$Sha256') { throw `"ARTIFACT HASH MISMATCH ON VM: `$h`" }; " +
             "`"OK staged; artifact=`$h size=`$((Get-Item C:\cfv\combined-setup.exe).Length)`""
    $r = Invoke-Rc $stage 'stage'
    $r | Out-File (Join-Path $dir 'stage.txt') -Encoding utf8
    if ($r -notmatch 'OK staged') { throw "stage did not confirm the artifact hash on the VM. Output: $r" }
    Say "Staged, digest re-verified on the VM. $r" Green

    $rs = Invoke-Rc $seedPs 'seed-key'
    # PARENTHESISED, and the reason is worth a line. Without them PowerShell
    # binds -notmatch as a PARAMETER of Invoke-Rc rather than applying it as an
    # operator, so the check cannot report what it claims to check. It failed
    # closed here, which is the only reason it was noticed at all.
    $seedCheck = Invoke-Rc "Test-Path C:\cfv\seed-ok.txt" 'seed-check'
    if ($seedCheck -notmatch 'True') { throw "the provider key did not land on the VM. seed-check returned: '$seedCheck'" }
    Say "  provider key seeded on the VM" Green

    $ip = Get-VmIp
    Card "CARD 2 of 3  LOG IN AND START THE RUNNER on $VmName" @(
        "",
        "WHY THIS NEEDS YOU. az vm run-command executes as SYSTEM, and a WSL distro is",
        "registered per user, so SYSTEM cannot see it. Every probe in this job is a WSL",
        "probe. They have to run inside an interactive $AdminUser session.",
        "",
        "THERE IS NO AUTO-LOGON IN THIS RUN. The driver would have to know your password",
        "to arm it, and it deliberately does not. So this login is required, not a",
        "fallback for one that failed.",
        "",
        "CONNECT",
        "  Address   : $ip",
        "  Username  : $AdminUser",
        "  Password  : the one you chose at Card 1, from your password manager",
        "  RDP rule  : present, scoped to $ruleSrc and nothing else",
        "",
        "  From this machine:   mstsc /v:$ip",
        "",
        "THEN RUN THIS, ONE LINE, in the PowerShell window on the VM:",
        "",
        "  powershell -NoProfile -ExecutionPolicy Bypass -File C:\cfv\interim-v120-runner.ps1",
        "",
        "WHAT SUCCESS LOOKS LIKE",
        "  The window stays open and prints nothing much. That is correct: it is a loop.",
        "  I will see it within about 15 seconds, because it writes a heartbeat file.",
        "  Leave that window OPEN for the whole run. Closing it stops every probe.",
        "",
        "WHAT FAILURE LOOKS LIKE",
        "  The window exits immediately, or reports that the file does not exist. That",
        "  means staging did not land. Tell me and I will re-stage rather than guess.",
        "",
        "TELL ME WHEN THE RUNNER IS UP and I will start the install."
    )
}

'restage' {
    # Re-upload ONLY the probe scripts. The artifact is 440 MB and unchanged, so
    # re-running 'stage' would either skip everything (its digest check is
    # satisfied) or waste the upload. A probe fix needs neither.
    Say "Re-staging the probe scripts only..."
    $key = Get-StorageKey
    if ($LASTEXITCODE -ne 0 -or -not $key) { throw "could not read a storage key for $StorageAcct." }
    $exp = (Get-Date).ToUniversalTime().AddHours(4).ToString('yyyy-MM-ddTHH:mmZ')
    $dl = ''
    foreach ($f in @(Get-ChildItem (Join-Path $DiagDir 'g4-*.ps1') | Where-Object { $_.Name -ne 'g4-probe.ps1' })) {
        az storage blob upload --account-name $StorageAcct --account-key $key --container-name $Container `
            --name $f.Name --file $f.FullName --overwrite --output none
        if ($LASTEXITCODE -ne 0) { throw "upload of $($f.Name) failed (az exit $LASTEXITCODE)." }
        $remote = az storage blob show --account-name $StorageAcct --account-key $key --container-name $Container `
                    --name $f.Name --query "properties.contentLength" -o tsv
        if ("$remote" -ne "$($f.Length)") { throw "upload of $($f.Name) landed $remote bytes, expected $($f.Length)." }
        $sas = az storage blob generate-sas --account-name $StorageAcct --account-key $key `
                 --container-name $Container --name $f.Name --permissions r --expiry $exp -o tsv
        $dl += "Invoke-WebRequest -Uri 'https://$StorageAcct.blob.core.windows.net/$Container/$($f.Name)`?$sas' -OutFile C:\cfv\$($f.Name) -UseBasicParsing; "
        Say "  uploaded $($f.Name) ($($f.Length) bytes, size confirmed at the service)" DarkGray
    }
    # Byte counts are re-verified ON THE VM, because "the download ran" and "the
    # file on the box is the file I just fixed" are different claims and only the
    # second one matters.
    $verify = "`$ErrorActionPreference='Stop'; $dl " +
              "(Get-ChildItem C:\cfv\g4-*.ps1 | ForEach-Object { `"`$(`$_.Name)=`$(`$_.Length)`" }) -join ' '"
    $r = Invoke-Rc $verify 'restage'
    Say "on-VM sizes: $r" Cyan
    foreach ($f in @(Get-ChildItem (Join-Path $DiagDir 'g4-*.ps1') | Where-Object { $_.Name -ne 'g4-probe.ps1' })) {
        if ($r -notmatch [regex]::Escape("$($f.Name)=$($f.Length)")) {
            throw "$($f.Name) on the VM does not match the local size $($f.Length). Refusing to re-run probes against a stale script."
        }
    }
    Say "All probe scripts on the VM match the local byte counts." Green
}

'install' {
    Say "Checking the runner heartbeat before queueing anything..."
    $hb = Invoke-Rc "if (Test-Path C:\cfv\jobs\_runner.heartbeat) { 'HB=' + (Get-Content C:\cfv\jobs\_runner.heartbeat -Raw) } else { 'HB=NONE' }" 'heartbeat'
    Say "  $hb"
    if ($hb -match 'HB=NONE') { throw "no runner heartbeat. The interactive session is not running the runner; see Card 2." }

    $job = "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\cfv\interim-v120-phase1.ps1 -CombinedExe C:\cfv\combined-setup.exe"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($job))
    Invoke-Rc "[IO.File]::WriteAllBytes('C:\cfv\jobs\01-install.job.ps1', [Convert]::FromBase64String('$b64')); 'queued'" 'queue-install' | Out-Null
    Say "Install queued. This takes 15 to 25 minutes." Yellow

    $done = $false
    foreach ($i in 1..90) {
        Start-Sleep -Seconds 45
        $p = Invoke-Rc "if (Test-Path C:\cfv\jobs\01-install.done) { 'DONE=' + (Get-Content C:\cfv\jobs\01-install.done -Raw) } else { `$hb = if (Test-Path C:\cfv\jobs\_runner.heartbeat) { Get-Content C:\cfv\jobs\_runner.heartbeat -Raw } else { 'no-runner' }; `"PENDING runner=`$hb`" }" 'poll'
        if ($p -match 'DONE=') { $done = $true; Say "Install job finished: $p" Green; break }
        if ($i % 4 -eq 0) { Say "  ...installing ($i/90, ~$([int]($i*0.75))min) $p" DarkGray }
        if ($p -match 'runner=no-runner' -and $i -ge 8) {
            throw "the runner heartbeat stopped. The interactive session died or its window was closed. Nothing will progress until it is restarted; see Card 2."
        }
    }
    if (-not $done) { throw "install did not finish within ~65 min." }

    $out = Invoke-Rc "Get-Content C:\cfv\jobs\01-install.out -Raw" 'install-out'
    $out | Out-File (Join-Path $dir 'install.out.txt') -Encoding utf8
    $verdict = Invoke-Rc "if (Test-Path C:\ProgramData\ClawFactory\install-result.txt) { Get-Content C:\ProgramData\ClawFactory\install-result.txt -Raw } else { 'ABSENT' }" 'install-result'
    Say "install-result.txt: $verdict" $(if ($verdict -match 'success') { 'Green' } else { 'Red' })
    if ($verdict -notmatch 'success') {
        throw "the install did not report success. That failure is the output of this session; the probes do not run on a broken box. Transcript saved to $dir\install.out.txt"
    }
    Say "Install GREEN. Ready for the probe phases." Green
}

'probes' {
    # Order is deliberate. The mechanism questions first, because Q1 decides
    # whether anything else is worth measuring. The agent-dependent questions
    # next, while the gateway is untouched. Q7 last, because it restarts the
    # gateway and edits a config, and Q2 after that because it tears the distro
    # down on purpose.
    $phases = @(
        @{ n = '02-q1'; f = 'g4-q1-fanotify.ps1'; a = ''; label = 'Q1 fanotify enforcement, ext4 and drvfs' },
        @{ n = '03-q6'; f = 'g4-q6-paths.ps1';    a = ''; label = 'Q6 second paths to the workspace' },
        @{ n = '04-q4'; f = 'g4-q4-fuse.ps1';     a = ''; label = 'Q4 FUSE passthrough' },
        @{ n = '05-q3'; f = 'g4-q3-volume.ps1';   a = ''; label = 'Q3 write volume and exclusion placement' },
        @{ n = '06-q5'; f = 'g4-q5-cost.ps1';     a = ''; label = 'Q5 cost of enforcement and copying'; mins = 75 },
        @{ n = '07-q7'; f = 'g4-q7-baseurl.ps1';  a = ''; label = 'Q7 card #197 model.baseUrl'; mins = 45 },
        @{ n = '08-q2'; f = 'g4-q2-scope.ps1';    a = ''; label = 'Q2 mark scope and restart survival (pre-reboot)' }
    )
    if ($Only) {
        $want = @($Only -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $phases = @($phases | Where-Object { $want -contains $_.n })
        Say "Running only: $($phases.n -join ', ')" Yellow
        if (-not $phases.Count) { throw "-Only '$Only' matched no phase. Valid ids: 02-q1 03-q6 04-q4 05-q3 06-q5 07-q7 08-q2" }
    }
    foreach ($ph in $phases) {
        Say "=== $($ph.label) ===" Cyan
        if ($Rerun) {
            Invoke-Rc "Remove-Item 'C:\cfv\jobs\$($ph.n).done','C:\cfv\jobs\$($ph.n).out' -Force -ErrorAction SilentlyContinue; 'cleared'" "clear $($ph.n)" | Out-Null
            Say "  cleared the previous .done barrier so this phase actually re-runs" DarkGray
        }
        # `exit $LASTEXITCODE` IS LOAD-BEARING. Without it the job script runs a
        # nested powershell and then exits 0 on its own account, so the runner
        # records rc=0 for a phase that exited 4 (VOID) or 1 (FAIL). Every one of
        # the first seven phases reported "DONE=rc=0" while three had FAILED and
        # two had VOIDED. The transcripts were right and the driver's summary was
        # a fiction, which is the exact failure mode the phase runner exists to
        # prevent, reappearing one layer up where the runner cannot see it.
        $job = "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\cfv\$($ph.f) $($ph.a)`r`nexit `$LASTEXITCODE"
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($job))
        Invoke-Rc "[IO.File]::WriteAllBytes('C:\cfv\jobs\$($ph.n).job.ps1', [Convert]::FromBase64String('$b64')); 'queued'" "queue $($ph.n)" | Out-Null
        # 60s, not 30s. Every poll is an ARM round trip and the control plane has
        # timed out four times in this session, each costing a 300s connect
        # timeout. Halving the poll rate halves the exposure and costs nothing:
        # these phases run in minutes, not seconds.
        #
        # Re-running this step is safe. The runner skips any job that already has
        # a .done beside it, so a phase completed before a driver crash is not
        # re-executed, and its result is picked up on the next poll.
        # Per-phase budget. A single 40 minute figure was wrong for Q5, which
        # repeats a warmed agent turn plus a dependency install three times and
        # legitimately needs longer. When it overran, the driver moved on and
        # started the next phase against a box the previous one still held, which
        # turned one slow phase into two lost ones.
        $budget = if ($ph.mins) { [int]$ph.mins } else { 40 }
        $done = $false
        foreach ($i in 1..$budget) {
            Start-Sleep -Seconds 60
            $p = Invoke-Rc "if (Test-Path C:\cfv\jobs\$($ph.n).done) { 'DONE=' + (Get-Content C:\cfv\jobs\$($ph.n).done -Raw) } else { 'PENDING' }" 'poll'
            if ($p -match 'DONE=') { $done = $true; Say "  $($ph.n) finished: $p" Green; break }
            if ($i % 3 -eq 0) { Say "  ...$($ph.n) running ($i min)" DarkGray }
        }
        if (-not $done) { Say "  $($ph.n) did not finish in 40 min; continuing and recording the gap." Yellow }
        $out = Invoke-Rc "if (Test-Path C:\cfv\jobs\$($ph.n).out) { Get-Content C:\cfv\jobs\$($ph.n).out -Raw } else { 'NO OUTPUT FILE' }" "out $($ph.n)"
        $out | Out-File (Join-Path $dir "$($ph.n).out.txt") -Encoding utf8
        Say "  transcript saved: $dir\$($ph.n).out.txt ($($out.Length) chars)" DarkGray
    }
    Say "All pre-reboot phases complete." Green
}

'reboot' {
    $ip = Get-VmIp
    $ruleSrc = az network nsg rule show -g $ResourceGroup --nsg-name "$VmName-nsg" -n allow-rdp-probe --query "sourceAddressPrefix" -o tsv
    Card "CARD 3 of 3  REBOOT AND LOG IN AGAIN on $VmName" @(
        "",
        "WHY. Questions 2 and 4 both ask whether a candidate survives a full reboot.",
        "That cannot be faked and it cannot be run from SYSTEM, so the VM restarts and",
        "you log in once more to restart the runner.",
        "",
        "I AM REBOOTING THE VM NOW. Give it about three minutes before connecting.",
        "",
        "CONNECT",
        "  Address   : $ip   (unchanged by the reboot, the public IP is Standard SKU)",
        "  Username  : $AdminUser",
        "  Password  : the one you chose at Card 1",
        "  RDP rule  : still present, still scoped to $ruleSrc",
        "",
        "  From this machine:   mstsc /v:$ip",
        "",
        "THERE WILL BE NO AUTO-LOGON SESSION WAITING FOR YOU. This run never armed one,",
        "so do not wait for one to appear and do not treat its absence as a fault.",
        "",
        "THEN RUN THIS, ONE LINE, in a PowerShell window on the VM:",
        "",
        "  powershell -NoProfile -ExecutionPolicy Bypass -File C:\cfv\interim-v120-runner.ps1",
        "",
        "WHAT SUCCESS LOOKS LIKE",
        "  The window stays open. I see the heartbeat within about 15 seconds.",
        "",
        "WHAT FAILURE LOOKS LIKE",
        "  It exits at once, or C:\cfv is empty. That would mean the OS disk did not come",
        "  back as expected. Tell me rather than re-staging by hand.",
        "",
        "TELL ME WHEN THE RUNNER IS UP and I will run the post-reboot pass."
    )
    az vm restart -g $ResourceGroup -n $VmName --output none
    if ($LASTEXITCODE -ne 0) { throw "az vm restart exited $LASTEXITCODE." }
    Say "Reboot issued. Waiting on your login." Yellow
}

'postreboot' {
    $hb = Invoke-Rc "if (Test-Path C:\cfv\jobs\_runner.heartbeat) { 'HB=' + (Get-Content C:\cfv\jobs\_runner.heartbeat -Raw) } else { 'HB=NONE' }" 'heartbeat'
    Say "  $hb"
    if ($hb -match 'HB=NONE') { throw "no runner heartbeat after the reboot; see Card 3." }
    $job = "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\cfv\g4-q2-scope.ps1 -PostReboot"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($job))
    Invoke-Rc "[IO.File]::WriteAllBytes('C:\cfv\jobs\09-q2post.job.ps1', [Convert]::FromBase64String('$b64')); 'queued'" 'queue-q2post' | Out-Null
    $done = $false
    foreach ($i in 1..40) {
        Start-Sleep -Seconds 30
        $p = Invoke-Rc "if (Test-Path C:\cfv\jobs\09-q2post.done) { 'DONE=' + (Get-Content C:\cfv\jobs\09-q2post.done -Raw) } else { 'PENDING' }" 'poll'
        if ($p -match 'DONE=') { $done = $true; Say "  post-reboot pass finished: $p" Green; break }
    }
    if (-not $done) { Say "  post-reboot pass did not finish in 20 min." Yellow }
    $out = Invoke-Rc "if (Test-Path C:\cfv\jobs\09-q2post.out) { Get-Content C:\cfv\jobs\09-q2post.out -Raw } else { 'NO OUTPUT FILE' }" 'out-q2post'
    $out | Out-File (Join-Path $dir '09-q2post.out.txt') -Encoding utf8
    Say "  transcript saved: $dir\09-q2post.out.txt" DarkGray
}

'collect' {
    # RETRIEVAL GOES THROUGH BLOB STORAGE, NOT run-command.
    #
    # The first collection read files with Get-Content -Raw over run-command and
    # every transcript came back exactly 4097 characters, because az truncates
    # the message payload. Five files, identical size, and the verdict lines
    # happened to survive: an evidence channel that silently keeps the tail is
    # worse than one that fails, because a truncated transcript reads as a
    # complete one and nobody checks a byte count they were not warned about.
    Say "Collecting every result file and transcript through blob storage..."
    $key = Get-StorageKey
    if ($LASTEXITCODE -ne 0 -or -not $key) { throw "could not read a storage key for $StorageAcct." }
    $exp = (Get-Date).ToUniversalTime().AddHours(4).ToString('yyyy-MM-ddTHH:mmZ')
    az storage container create --account-name $StorageAcct --account-key $key --name $Container --output none 2>$null

    $names = @('g4-q1-results.json', 'g4-q2-results-PRE.json', 'g4-q2-results-POSTREBOOT.json',
               'g4-q3-results.json', 'g4-q4-results.json', 'g4-q5-results.json',
               'g4-q6-results.json', 'g4-q7-results.json',
               'g4-q1-out-probe.txt', 'g4-q2-out-probe.txt', 'g4-q3-out-probe.txt',
               'g4-q4-out-probe.txt', 'g4-q5-out-probe.txt', 'g4-q6-out-probe.txt',
               'g4-q7-out-probe.txt',
               'jobs\02-q1.out', 'jobs\03-q6.out', 'jobs\04-q4.out', 'jobs\05-q3.out',
               'jobs\06-q5.out', 'jobs\07-q7.out', 'jobs\08-q2.out', 'jobs\09-q2post.out')
    foreach ($n in $names) {
        $blob  = "cfv165-" + ($n -replace '\\', '-')
        $local = Join-Path $dir ($n -replace '\\', '-')
        $sas = az storage blob generate-sas --account-name $StorageAcct --account-key $key `
                 --container-name $Container --name $blob --permissions cw --expiry $exp -o tsv
        $url = "https://$StorageAcct.blob.core.windows.net/$Container/$blob`?$sas"
        $put = Invoke-Rc ("if (-not (Test-Path 'C:\cfv\$n')) { 'MISSING_ON_VM' } else { " +
                          "Invoke-WebRequest -Uri '$url' -Method Put -Headers @{'x-ms-blob-type'='BlockBlob'} " +
                          "-InFile 'C:\cfv\$n' -UseBasicParsing | Out-Null; " +
                          "`"UPLOADED=`$((Get-Item 'C:\cfv\$n').Length)`" }") "put $n"
        if ($put -match 'MISSING_ON_VM') { Say "  $n : ABSENT on VM" Yellow; continue }
        if ($put -notmatch 'UPLOADED=(\d+)') { Say "  $n : upload did not confirm" Yellow; continue }
        $srcLen = [int]$Matches[1]
        az storage blob download --account-name $StorageAcct --account-key $key `
            --container-name $Container --name $blob --file $local --overwrite --output none
        if ($LASTEXITCODE -ne 0) { Say "  $n : download failed" Yellow; continue }
        # Byte-for-byte, because a silently truncated transcript is what this
        # whole rewrite exists to stop happening again.
        $gotLen = (Get-Item $local).Length
        if ($gotLen -ne $srcLen) { Say "  $n : TRUNCATED, $gotLen of $srcLen bytes" Red }
        else { Say "  $n : $gotLen bytes, byte count matches the VM" DarkGray }
    }
    Say "Collected into $dir" Green
}

'teardown' {
    Say "Tearing down $VmName..."
    az vm delete -g $ResourceGroup -n $VmName --yes --output none
    if ($LASTEXITCODE -ne 0) { throw "az vm delete exited $LASTEXITCODE." }
    # DEPENDENCY ORDER, and the previous order was wrong. The NIC references both
    # the public IP and the NSG, so deleting those first fails and leaves all
    # three behind. It failed loudly rather than silently, which is the only
    # reason nothing was orphaned, but a teardown that needs a human to finish it
    # is not a teardown.
    az disk delete -g $ResourceGroup -n "$VmName-osdisk" --yes --output none 2>$null
    az network nic delete -g $ResourceGroup -n "$($VmName)VMNic" --output none 2>$null
    az network nsg delete -g $ResourceGroup -n "$VmName-nsg" --output none 2>$null
    az network public-ip delete -g $ResourceGroup -n "$VmName-pip" --output none 2>$null
    Start-Sleep -Seconds 10
    # UNFILTERED. A teardown proof that greps for the VM name cannot show a
    # resource that was left behind under a different name.
    Say "Resource group contents, unfiltered:" Yellow
    $left = az resource list -g $ResourceGroup --query "[].{name:name,type:type}" -o table
    Write-Host $left
    $left | Out-File (Join-Path $dir 'teardown-unfiltered.txt') -Encoding utf8
    $vms = az vm list -g $ResourceGroup -o table
    Write-Host "VMs:"; Write-Host $vms
    $vms | Out-File (Join-Path $dir 'teardown-vms.txt') -Encoding utf8
}

'status' {
    $codes = @(az vm get-instance-view -g $ResourceGroup -n $VmName --query "instanceView.statuses[].code" -o tsv 2>$null)
    Say "VM statuses: $($codes -join ', ')"
    try {
        $hb = Invoke-Rc "if (Test-Path C:\cfv\jobs\_runner.heartbeat) { 'HB=' + (Get-Content C:\cfv\jobs\_runner.heartbeat -Raw) } else { 'HB=NONE' }; (Get-ChildItem C:\cfv\jobs\*.done -EA SilentlyContinue | ForEach-Object Name) -join ','" 'status'
        Say "  $hb"
    } catch { Say "  run-command unavailable: $($_.Exception.Message)" Yellow }
}

}
