<#
  Driver for the v1.2.0 INTERIM clean-box validation.

  THIS IS NOT THE RELEASE GATE. It validates a build carrying Guards 1 and 2
  only. Guard 3, Guard 4, the guardrail config pass and the honest-copy pass are
  unbuilt. Full validation on the assembled build still happens after those land.

  SHAPE, AND WHY IT DIFFERS FROM job3-validate.ps1
  ------------------------------------------------
  JOB 3 was fire-and-forget: arm, reboot, poll one sentinel, retrieve, tear
  down. This job cannot be, for three reasons:
    * Phase 1 is a HARD CHECKPOINT -- stop and report before the guard suite.
    * Phase 3 needs Bret at the keyboard over RDP, entering the SMTP app
      password into the Studio panel himself so it never enters a script, a
      transcript, or the driver's context.
    * Studio GUI surfaces must be driven to completion, not merely observed.
  So the VM STAYS UP between phases and the driver feeds it work through the
  on-VM runner (interim-v120-runner.ps1). See that file for why the interactive
  session is mandatory rather than convenient.

  DEVIATIONS FROM THE JOB PROMPT, both verified live before deviating:
    * Size: the prompt says Standard_D2s_v5. Live quota for the DSv5 family in
      westus2 is 0 (limit=0, current=0), so D2s_v5 cannot provision at all.
      Using Standard_D2s_v4 (limit=10), which is what every recent green run
      actually used and what azure-validate.ps1 already documents.
    * Image: the prompt says clawfactory-win11-baseline. Recent green runs
      (cfv-151, cfv-152) used clawfactory-win11-baseline-v2, which carries the
      newer WSL. Using -v2.
  Both are recorded in the close-out rather than silently applied.
#>
[CmdletBinding()]
param(
    [string]$VmName        = 'cfv-153',
    [string]$ResourceGroup = 'clawfactory-validation',
    [string]$Image         = 'clawfactory-win11-baseline-v2',
    [string]$Size          = 'Standard_D2s_v4',
    [string]$StorageAcct   = 'clawfactoryvalc467',
    [string]$Container     = 'validation',
    [string]$AdminUser     = 'clawadmin',
    [string]$SeedKeyTarget = 'ClawFactory/AnthropicApiKey',
    [string]$SeedKeyB64    = '',
    [string]$OutDir        = '',
    # v1.4.0 release gate. Three additions, each defaulting to exactly what this
    # driver did before, so any earlier invocation is byte-for-byte unchanged.
    #   -Phase1Script    which probe runs as this box's install phase. cfv-172
    #                    runs the offline probe instead, which reports through
    #                    phase 1's own channels so nothing else here changes.
    #   -ExtraStage      extra local files to stage into C:\cfv by leaf name.
    #                    cfv-172 needs the v1.1.1 artifact as its abort control.
    #   -InstallProvider which provider the install is given. cfv-171 uses
    #                    'later' so interim-v135-providergate.ps1
    #                    -DeferredProvider has a deferred install to read.
    [string]$Phase1Script    = 'interim-v120-phase1.ps1',
    [string[]]$ExtraStage    = @(),
    [string]$InstallProvider = 'claude',
    #   -Phase1Extra     switches passed to the install probe, or the literal
    #                    'none' for no extra switches. cfv-172 passes 'none'
    #                    because the capture's subject host is blocked there, so
    #                    arming it would produce a silence with no meaning.
    #
    #                    'none' RATHER THAN AN EMPTY STRING, and that is not
    #                    style. `powershell -File script.ps1 -Phase1Extra ''`
    #                    DROPS the empty argument during -File parsing, so the
    #                    next token binds to the wrong parameter or the parameter
    #                    binds to nothing: this exact call failed with "Missing an
    #                    argument for parameter 'Phase1Extra'". A sentinel word
    #                    survives the round trip; an empty string does not.
    [string]$Phase1Extra     = '-LicenceCapture',
    [switch]$Resume
)

$ErrorActionPreference = 'Stop'

# [CmdletBinding()] + -File empties $PSScriptRoot inside param defaults, so
# resolve paths in the BODY. This exact trap killed build_release.ps1 before
# gate 1 (see reference: psscriptroot-cmdletbinding).
$RepoRoot    = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'validation-runs' }
$CombinedExe = Join-Path $RepoRoot 'Output\ClawFactory-Secure-Setup.exe'
# Repinned 2026-08-10 after the Invoke-WslBash stdin fix.
#
# The original input to this job was 6f378d3a..., 440,575,752 bytes. That build
# could not install: Step-InstallQuarantine needed 84,692 characters of command
# line against a 32,767 limit, and Step-InstallSend 153,912, so neither Guard 1
# nor Guard 2 was deliverable. setup.ps1 now streams the script over stdin, which
# changes the bytes, so the artifact is re-pinned to the new signed build.
# Repinned again 2026-08-10 after the Guard 1 divert fix. PATH interception did
# not work: OpenClaw prepends node's own directory after tools.exec.pathPrepend,
# and node lives in /usr/bin next to the real rm, so `rm` always resolved to the
# real binary and a real agent turn destroyed a granted-workspace file while
# reporting it quarantined. /usr/bin/rm is now dpkg-diverted to the wrapper.
# Repinned 2026-08-13. Carries ALL THREE fixes, so nothing needs hand-patching on
# the box and the run is a genuine clean-install validation:
#   D1 Invoke-WslBash streams over stdin (neither guard could install)
#   D2 /usr/bin/rm diverted to the wrapper (Guard 1 intercepted nothing)
#   D3 RuntimeDirectoryPreserve (restarting one guard killed the other's sockets)
# Repinned 2026-08-13 for the Studio panel smoke test. d429e12e was the interim
# validation's input and is still a good build of the agent-side guards, but it
# CANNOT save an SMTP credential from Studio: invokeEngineWithInput wrapped a
# two-statement PowerShell expression in the grouping operator ( ), so the script
# failed at parse time and the panel reported that the send service did not
# respond. Smoking d429e12e would therefore have found a known defect and proved
# nothing about the panels. This build carries the $( ) fix.
# Repinned 2026-08-14 for Guard 3 and the five Studio polish items. This build
# adds the read-fetch allowlist (a second nft set, its root-owned resolver, the
# root-only control tool, and the Web access panel) and carries the expired
# approval cards, the full attachment hash, the real version in the Studio
# header, and the PolyForm footer. Studio moved to 1.2.0, so the embedded
# installer is now ClawFactory-Studio-Setup-1.2.0.exe rather than a third
# payload wearing the 1.1.0 name.
#
# NOTE, and it is the same hazard one level up: the ClawFactory installer
# version is still 1.2.0, so this artifact is the THIRD distinct payload to
# carry that version. The digest below is the authority. Bumping the installer
# version is the real fix and is a release decision, not this session's.
#
# Repinned again after cfv-161: 1df51d53 aborted its own install at
# Step-InstallSend. A comment inside setup.ps1's double-quoted fw-apply
# here-string contained a backtick-n sequence, which PowerShell expanded to a
# real newline, so the tail of the comment was written to the generated script
# as a command. fw-apply exited 127 and install-send.sh refused to continue. The
# installer failing closed is correct behaviour and is why this was caught.
# Repinned 2026-08-15 for v1.3.0. Three changes ride this artifact:
#
#   1. THE VERSION IS NOW 1.3.0, which resolves the hazard the note above
#      described rather than merely restating it. The number identifies the
#      payload again, and released-versions.tsv now refuses a build that would
#      reuse a version for different bytes. Proven in both directions: a fresh
#      version was permitted and appended, and a deliberate rebuild at 1.3.0 with
#      a changed setup.ps1 was refused before signing, naming both digests.
#   2. The toolchain access toggle: a THIRD nft set, toolchain_ipv4, holding the
#      software sources (skill hub, GitHub, npm) that used to sit in the
#      always-open provider allowlist where nothing could revoke them. Default
#      ON, user-switchable from the Web access panel, honoured by the five-hourly
#      refresh.
#   3. Studio 1.3.0: the switch and its breakage text, the ratified replacement
#      footnote, the header spacing fix, and the removal of the false "Studio
#      backend unreachable" banner from the home route.
#
# The digest below is of the SIGNED artifact, which is what lands on the VM.
# released-versions.tsv records the UNSIGNED digest instead, because signing
# embeds a countersigned timestamp and a signed digest is therefore different on
# every run over identical input.
# Repinned again, minutes later, to 1.3.1. The 1.3.0 build above was SUPERSEDED
# BEFORE VALIDATION and never released. Testing the toggle's policy reader across
# every shape it can meet found that a `toolchain` section which was PRESENT but
# not an object read as ON rather than denying, which contradicted the
# fail-closed rule stated in that very file. Not reachable by the agent, which
# cannot write the policy, but a control whose code disagrees with its own
# comment is not one to ship in a security product.
#
# Bumping rather than editing the ledger is the point. The version gate refused
# the changed 1.3.0 rebuild, exactly as designed, and complying with it instead
# of deleting the row is the discipline the gate exists to enforce. The 1.3.0 row
# stays in released-versions.tsv, annotated as superseded.
# Repinned to 1.3.2 after cfv-164 measured the toolchain toggle failing to close
# the route it advertises. The removal of the toolchain hosts from the
# always-open provider allowlist had been done in ONE of the three places a
# hostname can enter that set, so the addresses were re-seeded at install and the
# switch could not revoke them. 1.3.2 removes them from $baseHosts as well, and
# resolves each toolchain host three times to cope with a rotating pool. Full
# detail in the close-out, section 8.3.
# Repinned to 1.3.3. 1.3.2 could not install: removing the toolchain hosts from
# $baseHosts left uid 1000 with no route to GitHub, npm or the skill hub between
# Step-EgressFirewall and Step-InstallReadFetch, and step 8c runs as clawuser
# inside that window. It spent 21 minutes timing out and failed the install with
# "Failed to pre-configure gateway". 1.3.3 seeds @toolchain_ipv4 at firewall time,
# which closes the window without making anything unrevocable, because the set is
# still flushed and rebuilt from policy on every later run. See close-out 8.4.
# Repinned to 1.3.4 for the provider-route diagnosis, card #257. 1.3.3 is the
# build that produced the observation under investigation: on a fresh box the
# agent could not reach its own model, three turns over ten minutes, every one
# dropped to the provider address. 1.3.4 changes only the verdict triage and the
# chain-read diagnostics, so it carries the same seeding code and reproduces the
# same condition, while being the artifact any fix would actually ship on.
# Repinned to 1.4.0, the free release, 2026-08-23. This is the artifact the
# release gate runs against: licence checking removed, Apache-2.0, the corrected
# claim copy, and Studio repinned to 1.3.1 so the packaged panel copy matches its
# source for the first time. Signed, Authenticode Valid, CN=Bret Mckinney.
$Sha256      = '257f30ff6284a3645144b70822a9c55c342d4f90df179e00705dae3c52e6c390'
$ExpectBytes = 440613512

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$run = "{0}-{1}" -f $VmName, (Get-Date -Format 'yyyyMMdd-HHmmss')
$dir = Join-Path $OutDir $run
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$stateFile = Join-Path $OutDir "$VmName.state.json"

function Say($m, $c = 'Cyan') { Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $m" -ForegroundColor $c }
function Save($name, $content) { $content | Out-File (Join-Path $dir $name) -Encoding utf8 }

$script:State = [ordered]@{ vmName = $VmName; resourceGroup = $ResourceGroup; machineId = ''; phase = 'init'; run = $run }
if ($Resume -and (Test-Path $stateFile)) {
    try {
        $prev = Get-Content $stateFile -Raw | ConvertFrom-Json
        $script:State.machineId = $prev.machineId; $script:State.phase = $prev.phase
        Say "Resuming $VmName from phase '$($prev.phase)'" Yellow
    } catch { }
}
function Set-Phase([string]$p) {
    $script:State.phase = $p
    [IO.File]::WriteAllText($stateFile, ($script:State | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    Say "  [state] phase=$p" DarkGray
}

# --- Invoke-Rc: the ONE way this harness talks to run-command (L2/L4/L7).
# az on Windows is az.cmd and cmd.exe re-parses every argument, so the script
# goes in via @file and the query carries no parentheses.
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

function Retrieve-VmFile {
    param([string]$VmPath, [string]$BlobName, [string]$LocalPath, [string]$Key, [string]$Expiry)
    $sas = az storage blob generate-sas --account-name $StorageAcct --account-key $Key `
             --container-name $Container --name $BlobName --permissions cw --expiry $Expiry -o tsv
    $url = "https://$StorageAcct.blob.core.windows.net/$Container/$BlobName`?$sas"
    $put = Invoke-Rc ("if (-not (Test-Path '$VmPath')) { 'MISSING_ON_VM' } else { Invoke-WebRequest -Uri '$url' -Method Put -Headers @{'x-ms-blob-type'='BlockBlob'} -InFile '$VmPath' -UseBasicParsing | Out-Null; `"UPLOADED=`$((Get-Item '$VmPath').Length)`" }") "upload $BlobName"
    if ($put -match 'MISSING_ON_VM')   { Say "  $VmPath absent on VM" Yellow; return $null }
    if ($put -notmatch 'UPLOADED=\d+') { Say "  upload of $BlobName did not confirm: $put" Yellow; return $null }
    if ("$(az storage blob exists --account-name $StorageAcct --account-key $Key --container-name $Container --name $BlobName --query exists -o tsv)" -ne 'true') {
        Say "  $BlobName did NOT land in blob (PUT failed)" Yellow; return $null
    }
    az storage blob download --account-name $StorageAcct --account-key $Key `
        --container-name $Container --name $BlobName --file $LocalPath --overwrite --output none
    return $LocalPath
}

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
        return System.Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(System.Text.Encoding.Unicode.GetString(blob)));
    } finally { CredFree(p); }
}
'@ -Language CSharp
    return [CFR.Cred]::ReadB64($Target)
}

# ---- 0. Preflight ---------------------------------------------------------
Say "Preflight."
$sub = az account show --query id -o tsv
# The cached profile has lied before; ask the control plane for the real state.
$sstate = az rest --method get --url "https://management.azure.com/subscriptions/$sub`?api-version=2020-01-01" --query state -o tsv
if ($sstate -ne 'Enabled') { throw "Subscription is '$sstate', not Enabled. Stop." }
Say "  subscription: Enabled" Green

if (-not (az image show -g $ResourceGroup -n $Image --query id -o tsv 2>$null)) { throw "Image $Image not found in $ResourceGroup." }
Say "  image present: $Image" Green

if (-not (Test-Path $CombinedExe)) { throw "Artifact not found at $CombinedExe." }
$len = (Get-Item $CombinedExe).Length
if ($len -ne $ExpectBytes) { throw "Artifact size $len != expected $ExpectBytes. STOP -- wrong binary." }
$localSha = (Get-FileHash $CombinedExe -Algorithm SHA256).Hash.ToLower()
if ($localSha -ne $Sha256) { throw "Artifact hash mismatch: $localSha != $Sha256. STOP. Do not proceed with a different binary." }
Say "  artifact digest verified: $localSha ($len bytes)" Green

# Signature validity only. The Authenticode TIMESTAMP test is DECOUPLED from this
# job by instruction: it needs a date after 2026-08-06 19:31Z and no VM, and it
# lives on the pre-launch checklist. This check is not that test.
$sig = Get-AuthenticodeSignature $CombinedExe
if ($sig.Status -ne 'Valid') { throw "Artifact Authenticode is '$($sig.Status)', not Valid. Refusing to validate an unsigned build." }
Say "  signature: Valid ($($sig.SignerCertificate.Subject))" Green

if (-not $Resume -and (az vm list -g $ResourceGroup --query "[?name=='$VmName'].name" -o tsv)) {
    throw "VM $VmName already exists. Use -Resume, or tear it down first."
}
if (-not $SeedKeyB64) { $SeedKeyB64 = Read-CredAsBase64 $SeedKeyTarget }
if (-not $SeedKeyB64) { throw "Provider key absent from Credential Manager at '$SeedKeyTarget'. Guard 1 and Guard 2 both need real agent turns." }
Say "  provider key present (value never printed)" DarkGray

$resumePhase = if ($Resume) { $script:State.phase } else { 'init' }
$skipTo = @{ init = 0; provisioned = 1; staged = 2; armed = 3; phase1done = 4 }
$at = if ($skipTo.ContainsKey($resumePhase)) { $skipTo[$resumePhase] } else { 0 }

try {
    # ---- 1. Provision -----------------------------------------------------
    if ($at -lt 1) {
        Say "Provisioning $VmName ($Size, $Image, security-type Standard)..."
        $pw = -join ((65..90)+(97..122)+(48..57)+(33,35,37,42) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
        az vm create -g $ResourceGroup -n $VmName --image $Image --size $Size `
            --admin-username $AdminUser --admin-password $pw `
            --security-type Standard --public-ip-sku Standard --nsg-rule NONE `
            --os-disk-name "$VmName-osdisk" --public-ip-address "$VmName-pip" --nsg "$VmName-nsg" `
            --subnet (az network vnet subnet show -g $ResourceGroup --vnet-name bake-vmVNET -n bake-vmSubnet --query id -o tsv) `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Say "az vm create exit $LASTEXITCODE -- asking the VM whether it came up..." Yellow
            $codes = @(az vm get-instance-view -g $ResourceGroup -n $VmName --query "instanceView.statuses[].code" -o tsv 2>$null)
            if ($codes -notcontains 'PowerState/running') { throw "az vm create failed and VM not running (statuses: $($codes -join ', '))." }
            if ($codes -match 'ProvisioningState/failed') { throw "INFRA: terminal provisioning-Failed (OSProvisioningTimedOut lottery). Retry a FRESH VM name. Not a product fault." }
            Say "  ...VM running. Continuing." Yellow
        }
        # Sweep list: a killed process cannot run finally, and a leftover VM is a
        # real cost and a real finding.
        Add-Content -Path (Join-Path $OutDir 'ACTIVE_VMS.txt') -Value "$VmName $ResourceGroup $(Get-Date -Format s)" -Encoding ascii
        Set-Phase 'provisioned'
        Say "Provisioned. Admin password generated in memory, never printed or written." Green

        Say "Waiting for the VM agent to report Ready..."
        $agentOk = $false
        foreach ($i in 1..24) {
            $ag = @(az vm get-instance-view -g $ResourceGroup -n $VmName --query "instanceView.vmAgent.statuses[].displayStatus" -o tsv 2>$null)
            if ($ag -match 'Ready') { $agentOk = $true; Say "  agent: Ready" Green; break }
            Say "  agent: $($ag -join ',') ($i/24)" DarkGray; Start-Sleep -Seconds 15
        }
        if (-not $agentOk) { throw "VM agent never Ready after ~6 min. INFRA failure, not a product verdict." }

        $script:State.machineId = (Invoke-Rc "(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' MachineGuid).MachineGuid" 'machine-id').Trim()
        Set-Phase 'provisioned'
        Say "  machine_id: $($script:State.machineId)" DarkGray
    } else { Say "Resume: provision already done." Yellow }

    # ---- 2. Stage ---------------------------------------------------------
    if ($at -lt 2) {
        Say "Staging artifact + probe + runner + WSL channel..."
        $key = az storage account keys list -g $ResourceGroup -n $StorageAcct --query "[0].value" -o tsv
        if ($LASTEXITCODE -ne 0 -or -not $key) { throw "Could not read a storage key for $StorageAcct." }
        $exp = (Get-Date).ToUniversalTime().AddHours(3).ToString('yyyy-MM-ddTHH:mmZ')

        # Create the container if it is absent. The first run of this harness
        # assumed '$Container' already existed; it did not (the account carries
        # 'installers' and 'logs'), every upload failed, and because an az
        # failure does NOT stop the script (L6) the harness cheerfully printed
        # "uploaded" four times before the VM told the truth with a
        # ContainerNotFound. Create it, then verify every upload by exit code.
        az storage container create --account-name $StorageAcct --account-key $key --name $Container --output none 2>$null
        if ("$(az storage container exists --account-name $StorageAcct --account-key $key --name $Container --query exists -o tsv)" -ne 'true') {
            throw "Container '$Container' does not exist in $StorageAcct and could not be created."
        }
        Say "  container '$Container' present" DarkGray
        $files = @(
            @{ p = $CombinedExe; n = "combined-$VmName.exe" },
            @{ p = (Join-Path $PSScriptRoot 'interim-v120-phase1.ps1');  n = 'interim-v120-phase1.ps1' },
            @{ p = (Join-Path $PSScriptRoot 'interim-v120-runner.ps1');  n = 'interim-v120-runner.ps1' },
            @{ p = (Join-Path $PSScriptRoot 'interim-v120-wslchan.ps1'); n = 'interim-v120-wslchan.ps1' },
            # The phase runner. Every phase dot-sources it, so a run that stages
            # the phases without it dies at the first Record call. Staged here,
            # beside the channel helper, for exactly that reason.
            @{ p = (Join-Path $PSScriptRoot 'interim-v120-phaselib.ps1'); n = 'interim-v120-phaselib.ps1' },
            # The harness self-test, so the four injected faults can be
            # demonstrated ON THE BOX rather than only on the build machine.
            @{ p = (Join-Path $PSScriptRoot 'harness-selftest.ps1'); n = 'harness-selftest.ps1' }
        )
        # The install probe, whichever one this box is using.
        $files += @{ p = (Join-Path $PSScriptRoot $Phase1Script); n = $Phase1Script }
        foreach ($x in $ExtraStage) {
            $xp = if ([IO.Path]::IsPathRooted($x)) { $x } else { Join-Path $PSScriptRoot $x }
            $files += @{ p = $xp; n = (Split-Path $xp -Leaf) }
        }
        foreach ($f in $files) {
            if (-not (Test-Path $f.p)) { throw "Cannot stage '$($f.p)' -- not found." }
            az storage blob upload --account-name $StorageAcct --account-key $key --container-name $Container `
                --name $f.n --file $f.p --overwrite --output none
            # L6: an az failure does not stop the script. Verify by exit code AND
            # by asking the service for the blob's actual size, because "the
            # command returned" and "the bytes are there" are different claims.
            if ($LASTEXITCODE -ne 0) { throw "Upload of $($f.n) failed (az exit $LASTEXITCODE)." }
            $remote = az storage blob show --account-name $StorageAcct --account-key $key --container-name $Container `
                        --name $f.n --query "properties.contentLength" -o tsv
            $localLen = (Get-Item $f.p).Length
            if ("$remote" -ne "$localLen") { throw "Upload of $($f.n) landed $remote bytes, expected $localLen." }
            Say "  uploaded $($f.n) ($localLen bytes, size confirmed at the service)" DarkGray
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
        Set-Phase 'staged'; Say "Staged, hash re-verified on the VM. $r" Green
    } else { Say "Resume: staging already done." Yellow }

    # ---- 3. Seed key + arm auto-logon ------------------------------------
    if ($at -lt 3) {
        Say "Seeding provider key and arming the auto-logon session..."
        $pw = -join ((65..90)+(97..122)+(48..57)+(33,35,37,42) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
        # CHECKED, because the next thing this does is write $pw into Winlogon's
        # DefaultPassword and reboot. If the reset silently fails, the account
        # keeps its provisioning password while Winlogon is told the new one:
        # auto-logon then fails, no interactive session exists, the runner never
        # starts, and the poll below burns 75 minutes before anyone finds out.
        # That is what cfv-162 did. An unchecked az call is L6 and this was the
        # one place in the chain still missing the check.
        az vm user update -g $ResourceGroup -n $VmName --username $AdminUser --password $pw --output none
        if ($LASTEXITCODE -ne 0) {
            throw "az vm user update exited $LASTEXITCODE. Refusing to arm auto-logon with a password the account may not have."
        }
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

        # wrapper.cmd. The runner starts BEFORE the probe so that a wedged
        # install still leaves a live diagnostic channel. Each command and its
        # redirect are ONE joined physical line: cfv-149 lost an entire run to a
        # multi-line concat inside an array literal, which PowerShell parsed as
        # separate elements and silently orphaned the redirect.
        $probeArgs = @(
            '-NoProfile','-ExecutionPolicy','Bypass',
            '-File',"C:\cfv\$Phase1Script",
            '-CombinedExe','C:\cfv\combined-setup.exe',
            # Switches that belong to whichever probe is acting as this box's
            # install phase. Default is '-LicenceCapture', which brackets the
            # install with the licence-call capture; its calibration window rides
            # inside the probe, so the instrument is proven in the same run rather
            # than assumed from a previous one. cfv-172 passes '' instead: the
            # capture's subject host is BLOCKED on that box, so arming it there
            # would produce a silence with no meaning.
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
            throw "wrapper.cmd builder produced $($cmdLines.Count) lines, expected 5. The probe command was likely re-split from its redirect (cfv-149 signature). Refusing to arm a broken wrapper."
        }
        $cmdB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(($cmdLines -join "`r`n") + "`r`n"))
        # AUTO-LOGON NEEDS THE ACCOUNT CREDENTIAL TO EQUAL THE ONE IT WRITES.
        #
        # $pw is generated in memory above and never printed, and until 2026-08-23
        # it was the only credential the account ever had, so the two agreed by
        # construction. They stop agreeing the moment the OPERATOR sets their own
        # for RDP, which the release runbook asks them to do at provisioning: the
        # registry then carries $pw while the account carries theirs,
        # AutoAdminLogon fails silently, wrapper.cmd never runs, and the poll
        # below burns twelve minutes before fail-fast can name it. That is the
        # cfv-162 shape reached from a different direction.
        #
        # run-command executes as SYSTEM, which can reset a local account on this
        # throwaway validation VM without presenting the old value. So force the
        # two back into agreement here rather than hoping nobody touched it. This
        # DELIBERATELY overwrites an operator-chosen value: the operator sets
        # theirs again before the first reboot, which is the same card they
        # already receive for starting the runner by hand, so it costs no extra
        # round trip. Nothing is printed, saved, or returned to the driver.
        $arm = "`$ErrorActionPreference='Stop'; " +
               "[IO.File]::WriteAllBytes('C:\cfv\wrapper.cmd', [Convert]::FromBase64String('$cmdB64')); " +
               "net user '$AdminUser' '$pw' | Out-Null; " +
               "`$w='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; " +
               "Set-ItemProperty `$w AutoAdminLogon '1'; Set-ItemProperty `$w DefaultUserName '$AdminUser'; " +
               "Set-ItemProperty `$w DefaultPassword '$pw'; Set-ItemProperty `$w AutoLogonCount 1 -Type DWord; " +
               "Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' CFV-Interim 'cmd /c C:\cfv\wrapper.cmd'; " +
               "'armed'"
        $r = Invoke-Rc $arm 'arm'; Save 'arm.txt' $r
        if ($r -notmatch 'armed') { throw "Arm did not confirm. Do not reboot into a half-written wrapper. Output: $r" }
        Set-Phase 'armed'
        Say "Armed. Rebooting into the auto-logon session to run Phase 1..." Yellow
        az vm restart -g $ResourceGroup -n $VmName --output none
    } else { Say "Resume: already armed." Yellow }

    # ---- 4. Poll for Phase 1 ---------------------------------------------
    if ($at -lt 4) {
        Say "Polling for PHASE1_DONE (install ~15-25 min; allow up to ~75 min)..."
        $done = $false
        foreach ($i in 1..100) {
            Start-Sleep -Seconds 45
            $p = Invoke-Rc "if (Test-Path C:\cfv\PHASE1_DONE.txt) { 'PHASE1_DONE' } else { `$m=(Get-ChildItem C:\cfv\*.marker -EA SilentlyContinue | ForEach-Object Name) -join ','; `$hb=if (Test-Path C:\cfv\jobs\_runner.heartbeat) { Get-Content C:\cfv\jobs\_runner.heartbeat -Raw } else { 'no-runner' }; `"PENDING markers=`$m runner=`$hb`" }" 'poll'
            if ($p -match 'PHASE1_DONE') { $done = $true; Say "Phase 1 finished on the VM." Green; break }
            if ($i % 4 -eq 0) { Say "  ...running ($i/100, ~$([int]($i*0.75))min) $p" DarkGray }

            # FAIL FAST ON A SESSION THAT NEVER CAME UP. The runner is started by
            # wrapper.cmd, which RunOnce launches only after an interactive
            # logon. So a persistent 'no-runner' does not mean a slow install, it
            # means nothing is running at all and never will be. cfv-162 polled
            # this state for 48 minutes. Sixteen polls is twelve minutes, which
            # is well past any normal boot.
            if ($p -match 'runner=no-runner' -and $i -ge 16) {
                throw ("No interactive session after ~12 min: the runner heartbeat never appeared, so wrapper.cmd never ran. " +
                       "This is an auto-logon failure, not a slow install. Check AutoAdminLogon / DefaultPassword under " +
                       "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon and the Security event log for a failed logon. " +
                       "Do not wait out the full 75 minutes: nothing is going to start.")
            }
        }
        if (-not $done) { throw "Phase 1 did not report PHASE1_DONE within ~75 min. Resume with -Resume before blaming the product." }
        Set-Phase 'phase1done'
    }

    # ---- 5. Retrieve both evidence channels -------------------------------
    Say "Retrieving both evidence channels..."
    $key  = az storage account keys list -g $ResourceGroup -n $StorageAcct --query "[0].value" -o tsv
    $dExp = (Get-Date).ToUniversalTime().AddHours(3).ToString('yyyy-MM-ddTHH:mmZ')
    $main  = Retrieve-VmFile 'C:\cfv\phase1-out.txt'       "phase1-out-$VmName.txt"       (Join-Path $dir 'phase1-out.txt')       $key $dExp
    $probe = Retrieve-VmFile 'C:\cfv\phase1-out-probe.txt' "phase1-out-probe-$VmName.txt" (Join-Path $dir 'phase1-out-probe.txt') $key $dExp
    $null  = Retrieve-VmFile 'C:\cfv\phase1-results.json'  "phase1-results-$VmName.json"  (Join-Path $dir 'phase1-results.json')  $key $dExp
    $null  = Retrieve-VmFile 'C:\ProgramData\ClawFactory\logs\setup.log' "setup-$VmName.log" (Join-Path $dir 'setup.log') $key $dExp
    Say ("  main: {0} | probe transcript: {1}" -f `
        $(if ($main)  { "$((Get-Item $main).Length) B" }  else { 'MISSING' }),
        $(if ($probe) { "$((Get-Item $probe).Length) B" } else { 'MISSING' })) Cyan

    # ---- 5b. Evidence gate -------------------------------------------------
    $haveEvidence = $false
    foreach ($f in @($main, $probe)) {
        if ($f -and (Test-Path $f) -and (Get-Item $f).Length -ge 512 -and (Get-Content $f -Raw) -match 'PHASE1_PROBE_COMPLETE') { $haveEvidence = $true }
    }
    if (-not $haveEvidence) {
        Write-Host "`n===== EVIDENCE_MISSING =====" -ForegroundColor Red
        Say "No channel carries PHASE1_PROBE_COMPLETE above 512 B. Deallocating and PRESERVING $VmName for salvage." Red
        az vm deallocate -g $ResourceGroup -n $VmName --output none 2>$null
        Save 'EVIDENCE-MISSING.txt' "EVIDENCE_MISSING at $(Get-Date -Format s). $VmName deallocated + preserved."
        throw "EVIDENCE_MISSING: $VmName deallocated and preserved, not torn down."
    }
    Say "Evidence gate PASSED." Green

    Write-Host "`n===== PHASE 1 EVIDENCE (producer transcript) =====" -ForegroundColor Cyan
    if ($probe) { Get-Content $probe } elseif ($main) { Get-Content $main }

    Write-Host "`n===== CHECKPOINT =====" -ForegroundColor Yellow
    Say "$VmName IS STILL RUNNING AND BILLING, by design: Phase 3 needs an interactive session." Yellow
    Say "Evidence in $dir" Green
}
catch {
    Say "DRIVER ERROR: $($_.Exception.Message)" Red
    Say "$VmName left in place for diagnosis. Tear down with validation\job3-teardown.ps1 -VmName $VmName" Red
    throw
}
