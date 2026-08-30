<#
  interim-v145-pendingreboot.ps1

  THE MEASUREMENT THE FOUR v1.4.4 VALIDATION BOXES COULD NOT TAKE.

  Boxes A, B, C and D all ran from clawfactory-win11-baseline-v2, an image baked
  with the WSL engine already installed and VirtualMachinePlatform already live.
  Every one of them entered Step-EnsureWsl with a working virtualization layer.
  The first machine outside this project that ran the installer did not, and the
  install failed ninety seconds in with a message about a Linux user account.

  This probe constructs the state those four boxes could not be in -- a machine
  that has NEVER had WSL, on which VirtualMachinePlatform has been enabled and
  NOT yet rebooted -- and measures what setup.ps1's branch conditions read in it.

  WHAT IT MEASURES, AND WHY EACH ONE

    PR.C1   `wsl --status` exit code while VirtualMachinePlatform is
            Enable Pending. setup.ps1:921 sets $kernelOk from exactly this
            value, and $kernelOk true is what routes the install AWAY from the
            reboot-and-resume path at setup.ps1:937 and INTO the import path.
            If this exits 0 in the pending state, the reboot path is
            unreachable on a machine that needs it, and that single fact
            explains the whole external failure log.

    PR.C3   `wsl --install --no-launch -d Ubuntu` exit code in the same state,
            and whether a distro EXISTS afterwards. setup.ps1:502 logs
            'WSL2 install succeeded' on exit 0 and returns, with nothing between
            that line and New-ClawUserAndSetDefault checking that a distro was
            produced. This measures whether exit 0 can be had without a distro.

    PR.C4   `wsl -d Ubuntu -u root -- true` exit code. This is the call
            New-ClawUserAndSetDefault makes (via Invoke-WslBash) and whose -1
            became "Failed to pre-create clawuser stub (exit=-1)".

  THE CONFOUND, AND THE CONTROL FOR IT

    This probe runs under `az vm run-command invoke`, which is SYSTEM context,
    and WSL is known to misbehave under SYSTEM. A failure measured pre-reboot
    could therefore be the pending-reboot state OR the SYSTEM context, and those
    two look identical in a transcript.

    So every measurement is taken TWICE on the same box: once with
    VirtualMachinePlatform Enable Pending (-Stage A / A2), and once after a
    reboot with nothing else changed (-Stage B / B2). Stage B is the control. If
    the same call succeeds in stage B under the same SYSTEM context, SYSTEM is
    not the explanation and stage A's failure is the pending-reboot state. If it
    fails in stage B too, this rig cannot separate them and the rows are VOID --
    which is a result, not a dead end.

  ORDERING HAZARD, DELIBERATE

    The micro-probes claim the distro name 'Ubuntu'. The real installer run must
    therefore happen BEFORE them, never after, or the installer would find a
    distro this probe created and skip the branch under test. -Stage A runs
    census and construction only; the micro-probes are -Stage A2, dispatched
    after the installer.

  APPEND HAZARD, DELIBERATE

    C:\ProgramData\ClawFactory\install.log APPENDS (setup.ps1:154 Add-Content).
    Stage B must not read a file carrying stage A's lines. The driver moves it
    aside; this probe asserts the file it reads has at most one
    '==== ClawFactory Secure Setup - starting' banner and records VOID if not.
#>
param(
    [Parameter(Mandatory)][ValidateSet('A','A2','B','B2')][string]$Stage,
    [string]$Transcript  = '',
    [string]$ResultsJson = ''
)

$ErrorActionPreference = 'Continue'
if (-not $Transcript)  { $Transcript  = "C:\cfv\pendingreboot-$Stage-out-probe.txt" }
if (-not $ResultsJson) { $ResultsJson = "C:\cfv\pendingreboot-$Stage-results.json" }
if (-not (Test-Path 'C:\cfv')) { New-Item -ItemType Directory -Path 'C:\cfv' -Force | Out-Null }
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name "v1.4.5 diagnosis: WSL branch conditions in the pending-reboot state (stage $Stage)" `
            -Transcript $Transcript -Sentinel 'PENDINGREBOOT_PROBE_COMPLETE'

$FEATURES = @('VirtualMachinePlatform','Microsoft-Windows-Subsystem-Linux','HypervisorPlatform')

function Get-FeatureState {
    param([string]$Name)
    # DISM's own words, not a paraphrase. Returns the raw State line so the
    # transcript carries what Windows said rather than this script's reading.
    $out = & dism.exe /online /get-featureinfo "/featurename:$Name" 2>&1 | Out-String
    $m = [regex]::Match($out, '(?m)^\s*State\s*:\s*(.+?)\s*$')
    [pscustomobject]@{
        Name  = $Name
        State = $(if ($m.Success) { $m.Groups[1].Value } else { '<no State line in DISM output>' })
        Raw   = $out
    }
}

function Invoke-Native {
    <# Process.Start, the same shape setup.ps1 uses, for the same PS 5.1 reason:
       `& exe 2>&1` under $ErrorActionPreference='Stop' turns native stderr into
       terminating errors. Returns the exit code AND both streams, undecorated. #>
    param([string]$File, [string]$CmdArgs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $File
    $psi.Arguments = $CmdArgs
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    if ($File -ieq 'wsl.exe') {
        # wsl.exe emits UTF-16 LE. setup.ps1:221 sets this for the same reason;
        # without it the output decodes as null-padded bytes and every -match
        # against it silently fails, which would make this probe report
        # "no reboot sentence found" on output that plainly contains one.
        $psi.StandardOutputEncoding = [System.Text.Encoding]::Unicode
        $psi.StandardErrorEncoding  = [System.Text.Encoding]::Unicode
    }
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEnd()
    $e = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{
        Exit   = $p.ExitCode
        Out    = ($o -replace "`0", '')
        Err    = ($e -replace "`0", '')
        Joined = ((($o + "`n" + $e) -replace "`0", '') -replace "`r?`n+", ' | ').Trim(' |')
    }
}

Section '0. What this box is, before anything is done to it'
W "computername = $env:COMPUTERNAME"
W "os build     = $((Get-CimInstance Win32_OperatingSystem).BuildNumber)"
W "usercontext  = $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
W "interactive  = $([Environment]::UserInteractive)"

# The same property setup.ps1:816 reads. Recorded on every stage because the
# external machine's log carries this WARN and nobody yet knows whether it was a
# true reading or a property-absence artefact.
$cpu = @(Get-CimInstance Win32_Processor)
foreach ($c in $cpu) {
    $tn = if ($null -eq $c.VirtualizationFirmwareEnabled) { 'null' } else { $c.VirtualizationFirmwareEnabled.GetType().Name }
    W ("Win32_Processor: VirtualizationFirmwareEnabled = [{0}] (type {1})  name={2}" -f $c.VirtualizationFirmwareEnabled, $tn, $c.Name)
}
$vfe = @($cpu | ForEach-Object { $_.VirtualizationFirmwareEnabled })
W ("setup.ps1:816 would evaluate the WARN branch to: {0}  (WARN fires when this is True)" -f (-not $vfe))

$states = @{}
foreach ($f in $FEATURES) {
    $s = Get-FeatureState -Name $f
    $states[$f] = $s.State
    W ("DISM state  {0,-38} = {1}" -f $f, $s.State)
}

#=============================================================== STAGE A =====
if ($Stage -eq 'A') {

    Section '1. CONTROL: this box must NOT already be in the state the four v1.4.4 boxes were in'
    # The whole point of this run is a machine that has never had WSL. If the
    # image arrived with VirtualMachinePlatform already Enabled, this probe is
    # measuring baseline-v2 again and every row below is worthless.
    $virgin = ($states['VirtualMachinePlatform'] -match '^Disabled')
    $null = Register-Control -Id 'PR.CTL0' `
        -Name 'the box started with VirtualMachinePlatform NOT enabled (never-had-WSL, matching the external machine)' `
        -Fired $virgin `
        -Evidence ("DISM reports VirtualMachinePlatform State = '{0}'. The four v1.4.4 validation boxes all read Enabled here, which is why this path was never exercised." -f $states['VirtualMachinePlatform'])

    Section '2. The virgin readings, before wsl --update touches anything'
    $s0 = Invoke-Native -File 'wsl.exe' -CmdArgs '--status'
    W "virgin  wsl --status  exit = $($s0.Exit)"
    W "virgin  wsl --status  out  = $($s0.Joined)"
    $l0 = Invoke-Native -File 'wsl.exe' -CmdArgs '--list --quiet'
    W "virgin  wsl -l -q     exit = $($l0.Exit)"
    W "virgin  wsl -l -q     out  = $($l0.Joined)"
    Record 'PR.0a' 'wsl --status exit code on a box that has never had WSL' 'INFO' `
        "exit=$($s0.Exit). setup.ps1:921 sets kernelOk from this value. Recorded as the before-picture for PR.C1."

    Section '3. CONSTRUCT the pending-reboot state, the same way the external machine reached it'
    # The external machine reached it through `wsl --update`, which enabled
    # VirtualMachinePlatform and said in plain text that the change needs a
    # reboot. Reproduce by the same route rather than by DISM, so the state
    # under test is the state the product itself produces.
    W 'Running wsl --update -- the call Update-WslEngine (setup.ps1:247-268) makes.'
    $upd = Invoke-Native -File 'wsl.exe' -CmdArgs '--update'
    W "wsl --update exit = $($upd.Exit)"
    W "wsl --update out  = $($upd.Joined)"
    $sawRebootSentence = ($upd.Joined -match 'not be effective until the system is rebooted')
    Record 'PR.1' 'wsl --update announced a pending reboot in its own output' `
        $(if ($sawRebootSentence) { 'PASS' } else { 'INFO' }) `
        "exit=$($upd.Exit); reboot sentence present = $sawRebootSentence. Update-WslEngine logs this string and inspects it for nothing (setup.ps1:260-268), which is defect 1."

    $mid = (Get-FeatureState -Name 'VirtualMachinePlatform').State
    if ($mid -match '^Disabled') {
        W 'wsl --update did not enable the feature in this context. Falling back to DISM /norestart, which reaches the same state by a different route.'
        foreach ($f in @('VirtualMachinePlatform','Microsoft-Windows-Subsystem-Linux')) {
            $d = Invoke-Native -File 'dism.exe' -CmdArgs "/online /enable-feature /featurename:$f /all /norestart"
            W ("DISM /enable-feature {0} -> exit {1}   (3010 = success, reboot required)" -f $f, $d.Exit)
        }
        Record 'PR.1b' 'pending-reboot state constructed via DISM /norestart rather than by wsl --update' 'INFO' `
            'Recorded because the ROUTE differs from the external machine even though the STATE does not. PR.1 above says which route this run took.'
    }

    Section '4. CONTROL: prove the fault landed. A fault injection that does not inject scores a false pass.'
    $after = @{}
    foreach ($f in $FEATURES) {
        $s = Get-FeatureState -Name $f
        $after[$f] = $s.State
        W ("DISM state AFTER  {0,-38} = {1}" -f $f, $s.State)
    }
    $pending = ($after['VirtualMachinePlatform'] -match 'Pending')
    $null = Register-Control -Id 'PR.CTL1' `
        -Name 'VirtualMachinePlatform is now ENABLE PENDING -- the pending-reboot state actually exists on this box' `
        -Fired $pending `
        -Evidence ("DISM reports State = '{0}' (was '{1}'). Without this, every measurement below is taken in some other state and says nothing about the external failure." -f $after['VirtualMachinePlatform'], $states['VirtualMachinePlatform'])

    if ($after['VirtualMachinePlatform'] -match '^Enabled' -and -not $pending) {
        Record 'PR.1c' 'VirtualMachinePlatform reached Enabled with no pending state' 'VOID' `
            'This box enabled the feature without requiring a reboot, so the condition under test does not exist on it and cannot be measured here. Not a product verdict.'
    }

    Section '5. PR.C1 -- THE DECISIVE MEASUREMENT'
    # setup.ps1:910-921 runs exactly this and sets $kernelOk from the exit code.
    #   $kernelOk true  -> line 923 branch: import now, NO reboot.
    #   $kernelOk false -> line 937 branch: enable, register resume task, reboot.
    $s1 = Invoke-Native -File 'wsl.exe' -CmdArgs '--status'
    W "PENDING-STATE  wsl --status  exit = $($s1.Exit)"
    W "PENDING-STATE  wsl --status  out  = $($s1.Joined)"
    $kernelOk = ($s1.Exit -eq 0)
    W ''
    W "  setup.ps1:921   kernelOk = ($($s1.Exit) -eq 0)  ->  $kernelOk"
    W "  setup.ps1:923   if (kernelOk) { import now, NO reboot }        <- taken: $kernelOk"
    W "  setup.ps1:937   else          { enable, resume task, reboot }  <- taken: $(-not $kernelOk)"
    W ''
    Record 'PR.C1' 'wsl --status exits 0 while VirtualMachinePlatform is Enable Pending, so setup.ps1 believes the kernel is loaded' `
        $(if ($kernelOk) { 'FAIL' } else { 'PASS' }) `
        "exit=$($s1.Exit). FAIL here means the DEFECT IS CONFIRMED: kernelOk is true in a state that requires a reboot, the reboot-and-resume path at setup.ps1:937 is unreachable on a machine that needs it, and the install proceeds to import against a virtualization layer that is not live. PASS means the hypothesis is REFUTED and the external failure has another cause."

    Section '6. Leaving the box in the pending state for the installer run'
    W 'DO NOT REBOOT before the installer dispatch. The next dispatch runs the'
    W 'real v1.4.4 installer against exactly this state.'
    Marker 'pendingreboot-stageA-done'
}

#========================================================= STAGE A2 / B2 =====
if ($Stage -eq 'A2' -or $Stage -eq 'B2') {

    $label = if ($Stage -eq 'A2') { 'PENDING-REBOOT' } else { 'POST-REBOOT (control)' }
    Section "PR.C3 / PR.C4 -- the fallback's success claim, measured. State: $label"

    # PRECONDITION. In stage A2 the pending state must still hold; a reboot
    # between dispatches would silently turn this into a second post-reboot run.
    if ($Stage -eq 'A2') {
        $st = (Get-FeatureState -Name 'VirtualMachinePlatform').State
        $null = Require-Precondition -Id 'PR.PRE2' `
            -Name 'the box is STILL in the pending-reboot state at the time these calls are made' `
            -Met ($st -match 'Pending') `
            -Reason "DISM reports VirtualMachinePlatform State = '$st'. If the box rebooted between the installer dispatch and this one, these rows measure the post-reboot machine while claiming to measure the pending one."
    }

    $s = Invoke-Native -File 'wsl.exe' -CmdArgs '--status'
    W "wsl --status exit = $($s.Exit) | $($s.Joined)"

    $before = Invoke-Native -File 'wsl.exe' -CmdArgs '--list --quiet'
    $beforeList = @(($before.Out -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    W "distros BEFORE wsl --install: exit=$($before.Exit) [$($beforeList -join ', ')]"

    # setup.ps1:496 -- the exact fallback call, same arguments, same order.
    $inst = Invoke-Native -File 'wsl.exe' -CmdArgs '--install --no-launch -d Ubuntu'
    W "wsl --install --no-launch -d Ubuntu  exit = $($inst.Exit)"
    W "wsl --install --no-launch -d Ubuntu  out  = $($inst.Joined)"

    $after = Invoke-Native -File 'wsl.exe' -CmdArgs '--list --quiet'
    $afterList = @(($after.Out -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    W "distros AFTER  wsl --install: exit=$($after.Exit) [$($afterList -join ', ')]"

    $claimedSuccess = ($inst.Exit -eq 0)
    $distroExists   = ($afterList -contains 'Ubuntu')
    W ''
    W "  setup.ps1:502   if (rInst.ExitCode -eq 0)                  -> $claimedSuccess"
    W "  setup.ps1:503   Write-Log INFO 'WSL2 install succeeded.'   -> would be logged: $claimedSuccess"
    W "  a distro named Ubuntu actually exists                      -> $distroExists"
    W ''
    Record 'PR.C3' 'wsl --install returns 0 without producing a distro, and setup.ps1:503 logs success on that alone' `
        $(if ($claimedSuccess -and -not $distroExists) { 'FAIL' } else { 'PASS' }) `
        "installExit=$($inst.Exit); distroPresentAfter=$distroExists. FAIL means the fallback's success claim is FALSE and nothing between setup.ps1:503 and New-ClawUserAndSetDefault checks it."

    # setup.ps1:683 -- what Invoke-WslBash actually launches for the clawuser stub.
    $t = Invoke-Native -File 'wsl.exe' -CmdArgs '-d Ubuntu -u root --cd ~ -- true'
    W "wsl -d Ubuntu -u root -- true  exit = $($t.Exit)"
    W "wsl -d Ubuntu -u root -- true  out  = $($t.Joined)"
    Record 'PR.C4' 'the call New-ClawUserAndSetDefault makes returns the exit code that became "Failed to pre-create clawuser stub"' `
        $(if ($t.Exit -eq -1) { 'FAIL' } else { 'INFO' }) `
        "exit=$($t.Exit). The external log shows exit=-1 here. -1 is wsl.exe's own failure-to-launch code, not a code the bash payload chose; the same -1 appears on the wsl --import line two entries earlier in that same log."

    # Test-WslFunctional is the check that ALREADY EXISTS and is ALREADY CALLED,
    # one line too late (setup.ps1:930, after New-ClawUserAndSetDefault at 928).
    $tw = ($s.Exit -eq 0) -and $distroExists -and ($t.Exit -eq 0)
    Record 'PR.C5' 'Test-WslFunctional, evaluated here, would have refused this state BEFORE the clawuser step' `
        $(if ($tw) { 'INFO' } else { 'PASS' }) `
        "statusExit=$($s.Exit) distroInList=$distroExists trueExit=$($t.Exit) -> Test-WslFunctional would return $tw. PASS means the existing helper, moved from setup.ps1:930 to before line 928, converts this failure into the named 'WSL could not be configured on this machine' message at no new cost."

    Marker "pendingreboot-stage$Stage-done"
}

#=============================================================== STAGE B =====
if ($Stage -eq 'B') {

    Section 'CONTROL STAGE: the same box, after a reboot, with nothing else changed'
    $vmpState = $states['VirtualMachinePlatform']
    $nowEnabled = ($vmpState -match '^Enabled' -and $vmpState -notmatch 'Pending')
    $null = Register-Control -Id 'PR.CTL2' `
        -Name 'the reboot landed: VirtualMachinePlatform is now Enabled with nothing pending' `
        -Fired $nowEnabled `
        -Evidence "DISM reports State = '$vmpState'. Without this, the comparison between stage A and stage B is not a comparison of two states."

    $s = Invoke-Native -File 'wsl.exe' -CmdArgs '--status'
    W "POST-REBOOT  wsl --status  exit = $($s.Exit) | $($s.Joined)"
    Record 'PR.C1b' 'wsl --status exit code after the reboot' 'INFO' `
        "exit=$($s.Exit). Compare with PR.C1. If both are 0, the exit code does not discriminate between the two states at all, which is precisely why setup.ps1:921 cannot be built on it."

    Section 'Install log hygiene: C:\ProgramData\ClawFactory\install.log APPENDS'
    $logPath = 'C:\ProgramData\ClawFactory\install.log'
    if (Test-Path $logPath) {
        $banners = @(Select-String -LiteralPath $logPath -Pattern 'ClawFactory Secure Setup - starting' -SimpleMatch)
        W "install.log holds $($banners.Count) starting banner(s)"
        $null = Require-Precondition -Id 'PR.PRE3' `
            -Name 'the install.log this stage will read carries at most one run' `
            -Met ($banners.Count -le 1) `
            -Reason "found $($banners.Count) start banners. More than one means stage A's lines are still in the file and any conclusion drawn from it is drawn from two runs mixed together."
    } else {
        W 'install.log absent -- the box was cleaned between stages as intended.'
    }
    Marker 'pendingreboot-stageB-done'
}

Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix "PENDINGREBOOT_$Stage"
W 'PENDINGREBOOT_PROBE_COMPLETE'
