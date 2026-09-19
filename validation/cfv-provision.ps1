<#
  cfv-provision.ps1 -- create ONE validation VM and arm persistent auto-logon on it,
  with a SINGLE generated password that no human and no file ever sees.

  This is the provisioning command that card #259 §6.1 described in prose
  ("the session generates the admin password inside the provisioning command") and
  that no script carried: cfv-192 was created by an inline command and the value was
  discarded. Persistent auto-logon needs the SAME value at two places -- the account
  (az vm create --admin-password) and Winlogon\DefaultPassword -- so the generation and
  both uses now live in ONE process, here. There is no second generation path.

  THE PASSWORD
  ------------
    generated in this process, held in one local variable, passed to exactly two
    consumers (az vm create; the run-command -Pw parameter of cfv-arm-autologon.ps1),
    then removed. Never printed, never written to a file, never in a transcript. Only
    its LENGTH is ever reported. Both az calls put it on a cmd.exe command line, which
    is visible to other processes on THIS build machine for the seconds the call runs;
    that is the same exposure class as the value sitting in the VM's registry, on a
    machine that already holds the Azure login.

  SCOPE, ENFORCED HERE AND NOT ONLY DOCUMENTED
  --------------------------------------------
    * -Rg must be 'clawfactory-validation'. Any other value throws before az is called.
    * -Vm must match ^cfv-\d+$ -- the fleet's own naming.
    * --nsg-rule NONE: no inbound path exists to the box at any time.
    * Nothing here is bundled: validation\ is in no [Files] entry of the .iss, and
      setup.ps1, resources\ and the .iss name neither this file nor its task names.
    * NEVER capture an image or snapshot from a box this creates; the value is in its
      registry.

  DOES NOT create an RDP rule, does not run az vm user update (forbidden by
  docs/VALIDATION_PREAMBLE.md), and does not touch the operator's desktop.
#>
param(
    [Parameter(Mandatory)][string]$Vm,
    [string]$Rg        = 'clawfactory-validation',
    [string]$AdminUser = 'clawadmin',
    [string]$Size      = 'Standard_D2s_v4',
    [string]$Image     = '/subscriptions/43010359-5b4c-4d16-af11-10f6544b2978/resourceGroups/clawfactory-validation/providers/Microsoft.Compute/images/clawfactory-win11-baseline-v2',
    [string]$RunIdFile,
    [string]$OutDir
)

$ErrorActionPreference = 'Continue'
$env:MSYS_NO_PATHCONV = '1'
$here = Split-Path -Parent $PSCommandPath
. (Join-Path $here 'cfv-driverlib.ps1')

# ---- scope guards: BEFORE any credential exists or any az call is made ----------
if ($Rg -ne 'clawfactory-validation') { throw "cfv-provision.ps1 only provisions into 'clawfactory-validation' (got '$Rg'). Refusing: this script writes a credential to the box's registry." }
if ($Vm -notmatch '^cfv-\d+$')        { throw "cfv-provision.ps1 only provisions boxes named cfv-<n> (got '$Vm'). Refusing." }

if (-not $RunIdFile) { $RunIdFile = Join-Path $here "diag\$Vm-runid.txt" }
New-Item -ItemType Directory -Path (Split-Path -Parent $RunIdFile) -Force | Out-Null

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Az-Check([string]$what, [int]$rc) { if ($rc -ne 0) { throw "$what exited $rc" } }

$Run = New-CfvRun -Vm $Vm -ResourceGroup $Rg -Label 'autologon' -OutDir $OutDir
[IO.File]::WriteAllText($RunIdFile, ($Run | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
Say "RunId: $($Run.RunId)" Cyan

$pw = $null
try {
    # 24 alphanumerics, regenerated until it has all three character classes Windows'
    # complexity policy requires. A password that fails the policy fails az vm create,
    # loudly; this loop only removes that coin flip.
    do {
        $pw = -join ((1..24) | ForEach-Object { [char](Get-Random -InputObject (48..57 + 65..90 + 97..122)) })
    } until (($pw -cmatch '[a-z]') -and ($pw -cmatch '[A-Z]') -and ($pw -match '[0-9]'))
    Say "password generated in-process, length=$($pw.Length), value not shown" DarkGray

    $subnet = (& cmd.exe /c "az network vnet subnet show -g $Rg --vnet-name bake-vmVNET -n bake-vmSubnet --query id -o tsv").Trim()
    Az-Check 'az network vnet subnet show' $LASTEXITCODE
    if (-not $subnet) { throw 'subnet id came back empty' }

    # Deterministic child-resource names so teardown never has to guess (measured
    # necessary on cfv-192: az chose NIC/PIP/NSG names the driver had not predicted).
    $createErr = Join-Path $Run.Scratch 'vmcreate.azerr.txt'
    & cmd.exe /c "az vm create -g $Rg -n $Vm --image $Image --size $Size --admin-username $AdminUser --admin-password $pw --security-type Standard --public-ip-sku Standard --nsg-rule NONE --os-disk-name $Vm-osdisk --public-ip-address $Vm-pip --nsg $Vm-nsg --subnet $subnet --output none 2>`"$createErr`""
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        # OSProvisioningTimedOut is reported by ARM for this image while the guest
        # boots fine (measured cfv-0715d). Ask the VM, do not trust the exit code alone.
        $stderr = if (Test-Path $createErr) { (Get-Content $createErr -Raw) -replace [regex]::Escape($pw), '<pw>' } else { '' }
        Say "az vm create exit=$rc -- asking the VM whether it actually came up" Yellow
        Say ($stderr.Substring(0, [Math]::Min(600, $stderr.Length))) DarkGray
        $codes = @(& cmd.exe /c "az vm get-instance-view -g $Rg -n $Vm --query instanceView.statuses[].code -o tsv")
        if ($codes -notcontains 'PowerState/running') { throw "az vm create failed (exit $rc) and the VM is not running: $($codes -join ', ')" }
        if ($codes -match 'ProvisioningState/failed') { throw "INFRA: $Vm reached terminal provisioning-Failed; run-command will not work on it. $($codes -join ', ')" }
    }
    Say "VM $Vm created" Green

    # ---- stage runner + arm scripts, base64 in the dispatch (no blob, no SAS) -------
    $files = @('cfv-runner.ps1', 'cfv-arm-persistence.ps1', 'cfv-arm-autologon.ps1')
    $parts = foreach ($f in $files) {
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $here $f)))
        $len = (Get-Item (Join-Path $here $f)).Length
        "[IO.File]::WriteAllBytes('C:\cfv\$f', [Convert]::FromBase64String('$b64'))`r`n" +
        "Write-Output `"STAGED $f expected=$len actual=`$((Get-Item 'C:\cfv\$f').Length)`""
    }
    $stage = Invoke-CfvBox -Run $Run -Name 'stage' -Body ("New-Item -ItemType Directory -Path 'C:\cfv' -Force | Out-Null`r`n" +
             "New-Item -ItemType Directory -Path '$($Run.JobDir)' -Force | Out-Null`r`n" + ($parts -join "`r`n"))
    if ($stage.Condition -ne 'Ok') { throw "stage dispatch: $($stage.Condition) $($stage.Stderr)" }
    foreach ($f in $files) {
        $len = (Get-Item (Join-Path $here $f)).Length
        if ($stage.Text -notmatch "STAGED $([regex]::Escape($f)) expected=$len actual=$len") { throw "staging not confirmed for $f" }
    }
    Write-CfvOwnerStamp -Run $Run | Out-Null

    # ---- arm auto-logon. The password rides as the run-command PARAMETER -Pw. -------
    $alFile = Join-Path $here 'cfv-arm-autologon.ps1'
    $alOut  = Join-Path $Run.Scratch 'arm-autologon.out.json'
    $alErr  = Join-Path $Run.Scratch 'arm-autologon.azerr.txt'
    $raw = & cmd.exe /c "az vm run-command invoke -g $Rg -n $Vm --command-id RunPowerShellScript --scripts `"@$alFile`" --parameters AdminUser=$AdminUser Pw=$pw -o json 2>`"$alErr`""
    $rc = $LASTEXITCODE
    $errText = if (Test-Path $alErr) { (Get-Content $alErr -Raw) } else { '' }
    if ($errText) { $errText = $errText -replace [regex]::Escape($pw), '<pw>' }
    if ($rc -ne 0) { throw "arm-autologon dispatch exited $rc : $errText" }
    $msg = ''
    try { $msg = (((($raw | Out-String) | ConvertFrom-Json).value | ForEach-Object { $_.message }) -join "`n") } catch { throw "could not parse arm-autologon reply: $($_.Exception.Message)" }
    # The reply is scrubbed of the value before it touches disk. The script never
    # echoes it, so this is a belt-and-braces guard, and the count is reported.
    $leak = ($msg.Contains($pw))
    $msg  = $msg.Replace($pw, '<pw>')
    [IO.File]::WriteAllText((Join-Path $Run.OutDir 'arm-autologon.txt'), $msg, (New-Object Text.UTF8Encoding($false)))
    Say "reply contained the password verbatim: $leak (must be False)" $(if ($leak) { 'Red' } else { 'DarkGray' })
    foreach ($l in ($msg -split "`r?`n")) { if ($l -match '^AL_') { Say "  $l" } }
    if ($leak) { throw 'the run-command reply carried the password; treat the box as compromised and delete it' }
    if ($msg -notmatch 'AL_RESULT=PASS') { throw 'auto-logon arming did not PASS; read arm-autologon.txt' }
} finally {
    if ($pw) { $pw = $null; Remove-Variable pw -ErrorAction SilentlyContinue }
    # az's stderr files sit in %TEMP%; they are removed even though az does not echo
    # its arguments, because "az does not echo it" is an assumption about a tool.
    Remove-Item $createErr, $alErr, $alOut -Force -ErrorAction SilentlyContinue
}

# ---- arm the two runner tasks, expecting auto-logon to be present -----------------
$arm = Invoke-CfvBox -Run $Run -Name 'arm' -Body (
    "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\cfv\cfv-arm-persistence.ps1 " +
    "-RunId '$($Run.RunId)' -AdminUser '$AdminUser' -Root '$($Run.Root)' -AutoLogonExpected 2>&1 | Out-String | Write-Output")
[IO.File]::WriteAllText((Join-Path $Run.OutDir 'arm.txt'), "$($arm.Text)", (New-Object Text.UTF8Encoding($false)))
if ($arm.Text -match 'ARM_RESULT=PASS') { Say 'ARM PASS (SYSTEM runner armed, auto-logon present)' Green }
else { throw 'arm did not PASS; read arm.txt' }
Say "provisioned. RunIdFile: $RunIdFile" Cyan
