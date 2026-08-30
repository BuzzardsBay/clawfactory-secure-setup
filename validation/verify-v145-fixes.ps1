<#
verify-v145-fixes.ps1 -- run each v1.4.5 fix against an input the OLD code accepts.

WHY THIS EXISTS. A fix that has only been seen to work on a healthy machine is
unmeasured. Every scenario below runs the SAME constructed input through the
setup.ps1 that shipped as v1.4.4 (read out of git at 25945d5, not retyped) and
through the setup.ps1 in the worktree, and prints both answers. A row PASSES only
when the old code accepts and the new code refuses -- an assertion that fails in
BOTH directions is the calibration, not decoration.

HOW IT LOADS THE CODE. Both versions are parsed with the PowerShell AST and their
top-level function definitions are re-declared inside a private scope, so the real
shipped text runs rather than a paraphrase of it. Process-launching helpers
(Invoke-WslExe, Start-Sleep, New-Item) are stubbed AFTER the extraction, so the
later definition shadows the extracted one. Nothing here touches wsl.exe.

WHAT IT CANNOT DO, said here rather than left to be discovered:
  - Get-WindowsOptionalFeature requires elevation, so the D1 READ is not exercised.
    Its DECISION is, through the -States injection point. The read is deferred to
    the validation job and the assertion is written out in the close-out.
  - The rootfs-import scenario needs resources/ubuntu-rootfs.tar.gz present and
    matching the pin; it is skipped, loudly, if the file is absent.

Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File validation\verify-v145-fixes.ps1
Exit:   0 all rows PASS, 1 any row FAIL, 4 any row VOID (skipped/unmeasurable).
#>

[CmdletBinding()]
param([string]$BaselineCommit = '25945d5')

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Scratch  = Join-Path $env:TEMP ("cf-v145-verify-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Scratch -Force | Out-Null

# Script-scope state the extracted functions reach for via $script:.
$script:VirtFirmwareSuspect = $false
$script:RebootPending       = $false

$script:Rows = @()
function Row {
    param([string]$Id, [string]$What, [string]$Old, [string]$New, [string]$Verdict, [string]$Note = '')
    $script:Rows += [pscustomobject]@{ Id = $Id; What = $What; Old = $Old; New = $New; Verdict = $Verdict; Note = $Note }
    $color = switch ($Verdict) { 'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'Yellow' } }
    Write-Host ("[{0}] {1,-6} {2}" -f $Id, $Verdict, $What) -ForegroundColor $color
    Write-Host ("         old: {0}" -f $Old)
    Write-Host ("         new: {0}" -f $New)
    if ($Note) { Write-Host ("         note: {0}" -f $Note) }
}

#--- load both versions -------------------------------------------------------
Push-Location $RepoRoot
$oldText = (& git show "${BaselineCommit}:setup.ps1") -join "`n"
Pop-Location
if (-not $oldText -or $oldText.Length -lt 10000) { throw "could not read setup.ps1 at $BaselineCommit" }
$newText = [IO.File]::ReadAllText((Join-Path $RepoRoot 'setup.ps1'))

function Get-FunctionText {
    # Top-level function definitions only. Returns one string of declarations.
    param([string]$Text)
    $errs = $null; $toks = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$toks, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) { throw "parse errors in source: $($errs[0].Message)" }
    $fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
    return (($fns | ForEach-Object { $_.Extent.Text }) -join "`n`n")
}
$oldFns = Get-FunctionText $oldText
$newFns = Get-FunctionText $newText

function Invoke-Sandbox {
    # Declare one version's functions in a private scope, apply variables and
    # stubs, then run the body there. Stubs are dot-sourced after the extraction
    # so they shadow the real helpers.
    param([string]$Fns, [hashtable]$Vars, [scriptblock]$Stubs, [scriptblock]$Body)
    & {
        param($Fns, $Vars, $Stubs, $Body)
        Set-StrictMode -Version 3.0
        Invoke-Expression $Fns
        foreach ($k in $Vars.Keys) { Set-Variable -Name $k -Value $Vars[$k] -Scope 0 }
        . $Stubs
        . $Body
    } $Fns $Vars $Stubs $Body
}

function Show-Result {
    # Render "returned <x>" or "threw: <first 110 chars>".
    param([scriptblock]$Action)
    try {
        $r = & $Action
        if ($null -eq $r) { return 'returned <null>' }
        return "returned '$r'"
    } catch {
        $m = $_.Exception.Message -replace "`r?`n", ' '
        if ($m.Length -gt 110) { $m = $m.Substring(0, 110) + '...' }
        return "threw: $m"
    }
}

#--- the wsl.exe stub factory -------------------------------------------------
# Returns a scriptblock defining Invoke-WslExe over a scripted response table,
# plus the no-op Start-Sleep / New-Item / Write-Log the paths under test need.
function New-WslStub {
    param(
        [int]$InstallExit, [string]$InstallOut,
        [int]$ImportExit = 0, [string]$ImportOut = '',
        [string[]]$ListDistros = @('Ubuntu'),
        [int]$ListExit = 0,
        [int]$TrueExit = 0,
        [int]$StatusExit = 0,
        [int]$FallbackExit = 0
    )
    $state = @{
        InstallExit = $InstallExit; InstallOut = $InstallOut
        ImportExit  = $ImportExit;  ImportOut  = $ImportOut
        ListDistros = $ListDistros; ListExit   = $ListExit
        TrueExit    = $TrueExit;    StatusExit = $StatusExit
        FallbackExit = $FallbackExit
    }
    $sb = {
        $S = $StubState
        function Write-Log { param([string]$Level, [string]$Message) }
        function Start-Sleep { param([int]$Seconds, [int]$Milliseconds) }
        function New-Item { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
        function Add-Content { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
        function Invoke-WslExe {
            param([Parameter(Mandatory)][string[]]$Arguments)
            $a = $Arguments -join ' '
            if ($a -like '--import*')                 { return @{ ExitCode = $S.ImportExit;  StdOut = $S.ImportOut;  StdErr = '' } }
            if ($a -like '--status*')                 { return @{ ExitCode = $S.StatusExit;  StdOut = '';            StdErr = '' } }
            if ($a -like '--list*')                   { return @{ ExitCode = $S.ListExit;    StdOut = (($S.ListDistros -join "`n") + "`n"); StdErr = '' } }
            if ($a -like '*-u root -- true*')         { return @{ ExitCode = $S.TrueExit;    StdOut = '';            StdErr = '' } }
            # The three WSL1-fallback calls. `--install -d Ubuntu --no-launch` is the
            # third; the PRIMARY install is `--install --no-launch -d Ubuntu`, a
            # different argument order, so the two are distinguishable and this arm
            # has to come first.
            if ($a -like '--install --no-distribution*' -or $a -like '--set-default-version*' -or $a -like '--install -d *') {
                                                        return @{ ExitCode = $S.FallbackExit; StdOut = '';           StdErr = '' } }
            if ($a -like '--install*')                { return @{ ExitCode = $S.InstallExit; StdOut = $S.InstallOut; StdErr = '' } }
            return @{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }
    }
    return @{ Stub = $sb; State = $state }
}

$logFile = Join-Path $Scratch 'install.log'
$logDir  = $Scratch

# ============================================================================
# CALIBRATION 0 -- the harness can produce BOTH answers on a healthy input.
# A rig that only ever returns "refused" would score every row below a PASS.
# ============================================================================
$h = New-WslStub -InstallExit 0 -InstallOut 'ok' -ListDistros @('Ubuntu') -TrueExit 0
$vars = @{ WslDistro = 'Ubuntu'; LogFile = $logFile; StubState = $h.State; WslCalls = @() }
$oldHealthy = Show-Result { Invoke-Sandbox -Fns $oldFns -Vars $vars -Stubs $h.Stub -Body { Install-WslDistroWithFallback -BundledRootfs '' } }
$newHealthy = Show-Result { Invoke-Sandbox -Fns $newFns -Vars $vars -Stubs $h.Stub -Body { Install-WslDistroWithFallback -BundledRootfs '' } }
Row 'CAL.0' 'healthy machine: exit 0 AND the distro answers -- BOTH versions must accept' `
    $oldHealthy $newHealthy `
    $(if ($oldHealthy -like "*'wsl2'*" -and $newHealthy -like "*'wsl2'*") { 'PASS' } else { 'FAIL' }) `
    'the positive control: proves the new check is not simply always refusing'

# ============================================================================
# D2 -- the exact shape of the first external install failure.
# `wsl --install` exits 0, prints the reboot sentence, and no distro exists.
# ============================================================================
$sentence = 'The requested operation is successful. Changes will not be effective until the system is rebooted.'
$b = New-WslStub -InstallExit 0 -InstallOut $sentence -ListDistros @('docker-desktop') -TrueExit -1
$vars = @{ WslDistro = 'Ubuntu'; LogFile = $logFile; StubState = $b.State; WslCalls = @() }
$oldD2 = Show-Result { Invoke-Sandbox -Fns $oldFns -Vars $vars -Stubs $b.Stub -Body { Install-WslDistroWithFallback -BundledRootfs '' } }
$newD2 = Show-Result { Invoke-Sandbox -Fns $newFns -Vars $vars -Stubs $b.Stub -Body { Install-WslDistroWithFallback -BundledRootfs '' } }
Row 'D2.1' 'wsl --install exits 0, prints the reboot sentence, creates NO distro' `
    $oldD2 $newD2 `
    $(if ($oldD2 -like "*'wsl2'*" -and $newD2 -like 'threw:*') { 'PASS' } else { 'FAIL' }) `
    'this is Jason install.log 11:11:18 -- the refutation was the line above the claim'

# D2, the import site. Needs the real bundled rootfs so the pin gate passes.
$rootfs = Join-Path $RepoRoot 'resources\ubuntu-rootfs.tar.gz'
if (Test-Path -LiteralPath $rootfs) {
    $i = New-WslStub -InstallExit 1 -InstallOut '' -ImportExit 0 -ImportOut 'ok' -ListDistros @('docker-desktop') -TrueExit -1
    $vars = @{ WslDistro = 'Ubuntu'; LogFile = $logFile; StubState = $i.State; WslCalls = @() }
    $oldD2i = Show-Result { Invoke-Sandbox -Fns $oldFns -Vars $vars -Stubs $i.Stub -Body { Install-WslDistroWithFallback -BundledRootfs $rootfs } }
    $newD2i = Show-Result { Invoke-Sandbox -Fns $newFns -Vars $vars -Stubs $i.Stub -Body { Install-WslDistroWithFallback -BundledRootfs $rootfs } }
    Row 'D2.2' 'wsl --import exits 0 and creates NO distro (the second success site)' `
        $oldD2i $newD2i `
        $(if ($oldD2i -like "*'wsl2'*" -and $newD2i -like 'threw:*') { 'PASS' } else { 'FAIL' })
} else {
    Row 'D2.2' 'wsl --import exits 0 and creates NO distro' 'not run' 'not run' 'VOID' `
        'resources\ubuntu-rootfs.tar.gz absent, so the rootfs pin cannot pass and the import branch is unreachable'
}

# ============================================================================
# v1.4.5-A -- the WSL1 downgrade. Old code accepts and returns 'wsl1'.
# ============================================================================
$w = New-WslStub -InstallExit 1 -InstallOut 'Error code: Wsl/InstallDistro/HCS_E_HYPERV_NOT_INSTALLED' `
                 -ListDistros @('Ubuntu') -TrueExit 0 -FallbackExit 0
$vars = @{ WslDistro = 'Ubuntu'; LogFile = $logFile; StubState = $w.State; WslCalls = @() }
$oldA = Show-Result { Invoke-Sandbox -Fns $oldFns -Vars $vars -Stubs $w.Stub -Body { Install-WslDistroWithFallback -BundledRootfs '' } }
$newA = Show-Result { Invoke-Sandbox -Fns $newFns -Vars $vars -Stubs $w.Stub -Body { Install-WslDistroWithFallback -BundledRootfs '' } }
Row 'A.1' 'HCS_E_HYPERV_NOT_INSTALLED: old downgrades to WSL1, new must refuse by name' `
    $oldA $newA `
    $(if ($oldA -like "*'wsl1'*" -and $newA -like 'threw:*Virtual Machine Platform*') { 'PASS' } else { 'FAIL' }) `
    'a WSL1 install cannot complete: it dies ~20 min later on a gateway health probe'

# ============================================================================
# D4 -- the virtualization signal is in the IMPORT output, not the install one.
# Old code tests only $output and so misses it; new tests both.
# ============================================================================
if (Test-Path -LiteralPath $rootfs) {
    $d = New-WslStub -InstallExit 1 -InstallOut 'Ubuntu is already installed.' `
                     -ImportExit 1 `
                     -ImportOut 'Error code: Wsl/Service/RegisterDistro/CreateVm/HCS/HCS_E_SERVICE_NOT_AVAILABLE' `
                     -ListDistros @('docker-desktop') -TrueExit -1
    $vars = @{ WslDistro = 'Ubuntu'; LogFile = $logFile; StubState = $d.State; WslCalls = @() }
    $oldD4 = Show-Result { Invoke-Sandbox -Fns $oldFns -Vars $vars -Stubs $d.Stub -Body { Install-WslDistroWithFallback -BundledRootfs $rootfs } }
    $newD4 = Show-Result { Invoke-Sandbox -Fns $newFns -Vars $vars -Stubs $d.Stub -Body { Install-WslDistroWithFallback -BundledRootfs $rootfs } }
    Row 'D4.1' 'the virtualization error is in the IMPORT stream only' `
        $oldD4 $newD4 `
        $(if ($oldD4 -like '*no fallback signal detected*' -and $newD4 -like '*Virtual Machine Platform*') { 'PASS' } else { 'FAIL' }) `
        'both throw; the old one names nothing actionable, the new one names the cause'
} else {
    Row 'D4.1' 'the virtualization error is in the IMPORT stream only' 'not run' 'not run' 'VOID' `
        'needs resources\ubuntu-rootfs.tar.gz'
}

# ============================================================================
# D1 -- the DECISION. The read itself needs elevation and is deferred.
# ============================================================================
$dlStub = {
    function Write-Log { param([string]$Level, [string]$Message) }
    function Test-Path { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) return $false }
}
$pendingStates = @{ 'VirtualMachinePlatform' = 'EnablePending'; 'Microsoft-Windows-Subsystem-Linux' = 'Enabled'; 'HypervisorPlatform' = 'Enabled' }
$cleanStates   = @{ 'VirtualMachinePlatform' = 'Enabled';       'Microsoft-Windows-Subsystem-Linux' = 'Enabled'; 'HypervisorPlatform' = 'Enabled' }
$unknownStates = @{ 'VirtualMachinePlatform' = 'Unknown';       'Microsoft-Windows-Subsystem-Linux' = 'Unknown'; 'HypervisorPlatform' = 'Unknown' }

$oldHas = Invoke-Sandbox -Fns $oldFns -Vars @{} -Stubs $dlStub -Body { [bool](Get-Command Test-WslRebootPending -ErrorAction SilentlyContinue) }
$newPend = Invoke-Sandbox -Fns $newFns -Vars @{ P = $pendingStates } -Stubs $dlStub -Body { Test-WslRebootPending -States $P }
$newClean = Invoke-Sandbox -Fns $newFns -Vars @{ P = $cleanStates } -Stubs $dlStub -Body { Test-WslRebootPending -States $P }
$newUnk = Invoke-Sandbox -Fns $newFns -Vars @{ P = $unknownStates } -Stubs $dlStub -Body { Test-WslRebootPending -States $P }
Row 'D1.1' 'VirtualMachinePlatform = EnablePending must be detected' `
    $(if ($oldHas) { 'function exists' } else { 'no such condition exists anywhere in v1.4.4' }) `
    "Test-WslRebootPending = $newPend" `
    $(if (-not $oldHas -and $newPend -eq $true) { 'PASS' } else { 'FAIL' })
Row 'D1.2' 'all three features Enabled must NOT trigger a restart' 'n/a' "Test-WslRebootPending = $newClean" `
    $(if ($newClean -eq $false) { 'PASS' } else { 'FAIL' }) `
    'the negative control: a gate that always fires would refuse to install on every machine'
Row 'D1.3' 'an unreadable feature state must fail OPEN, not restart the machine' 'n/a' "Test-WslRebootPending = $newUnk" `
    $(if ($newUnk -eq $false) { 'PASS' } else { 'FAIL' }) `
    'input-shape sweep: absent/unreadable is not a fault verdict here, by design'
# D1.4 asks whether the gate is built on prose. A grep would answer WRONGLY: the
# sentence appears in setup.ps1 as a COMMENT, which is where it belongs. So the
# instrument reads every STRING LITERAL out of the AST -- a condition would have to
# be one -- and it is calibrated against a planted source that does contain one.
function Test-SentenceInLiterals {
    param([string]$Text, [string]$Needle)
    $errs = $null; $toks = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$toks, [ref]$errs)
    $lits = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
    foreach ($l in $lits) { if ($l.Value -like "*$Needle*") { return $true } }
    return $false
}
$needle  = 'will not be effective until the system is rebooted'
$canary  = "function Bad { if (`$out -match '$needle') { Restart-Computer } }"
$canaryHit = Test-SentenceInLiterals -Text $canary -Needle $needle
$realHit   = Test-SentenceInLiterals -Text $newText -Needle $needle
$rawGrep   = $newText.Contains($needle)
Row 'D1.4' 'the gate must NOT be the English sentence Windows printed' `
    'no condition at all' `
    "planted canary found: $canaryHit; string literal in setup.ps1: $realHit (a raw text search says $rawGrep, and is wrong -- it is a comment)" `
    $(if ($canaryHit -and -not $realHit) { 'PASS' } else { 'FAIL' }) `
    'matching it would silently stop working on any non-English Windows'

# ============================================================================
# Census site 850 -- a failed `wsl --list` must not record the destructive answer.
# ============================================================================
$stateStub = {
    function Write-Log { param([string]$Level, [string]$Message) }
    function Update-WslEngine { }
    function Test-WslFunctional { return $true }
    function Test-WslRebootPending { param($States) return $false }
    function Save-Checkpoint { param([string]$Step) }
    function Invoke-WslExe { param([Parameter(Mandatory)][string[]]$Arguments) return @{ ExitCode = 1; StdOut = ''; StdErr = 'Error' } }
}
foreach ($pair in @(@{ Fns = $oldFns; Tag = 'old' }, @{ Fns = $newFns; Tag = 'new' })) {
    $d850 = Join-Path $Scratch ("state-" + $pair.Tag)
    New-Item -ItemType Directory -Path $d850 -Force | Out-Null
    Invoke-Sandbox -Fns $pair.Fns -Vars @{ WslDistro = 'Ubuntu'; LogDir = $d850; LogFile = (Join-Path $d850 'i.log'); Resume = $false; BundledRootfsDir = '' } `
        -Stubs $stateStub -Body { Step-EnsureWsl } | Out-Null
    $f = Join-Path $d850 'wsl-state.txt'
    Set-Variable -Name ("res850_" + $pair.Tag) -Value $(if (Test-Path $f) { "wrote '" + (Get-Content -Raw $f).Trim() + "'" } else { 'wrote nothing' })
}
Row '850.1' 'wsl --list --quiet FAILS: must not record the answer that permits deleting a user distro' `
    $res850_old $res850_new `
    $(if ($res850_old -like "*'false'*" -and $res850_new -eq 'wrote nothing') { 'PASS' } else { 'FAIL' }) `
    "'false' tells the uninstaller the distro is ClawFactory's to remove"

# ============================================================================
# D6 / D7 -- the failure path itself.
# ============================================================================
$rbStub = {
    $script:Lines = @()
    function Write-Log { param([string]$Level, [string]$Message) $script:Lines += "[$Level] $Message" }
    function Confirm-Or-Default { param([string]$Prompt, [string]$Default) return 'y' }
    function Get-CompletedSteps { return @('Preflight') }
    function Invoke-WslExe { param([Parameter(Mandatory)][string[]]$Arguments) return @{ ExitCode = 0; StdOut = ''; StdErr = '' } }
    function Remove-NetFirewallRule { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
}
foreach ($pair in @(@{ Fns = $oldFns; Tag = 'old' }, @{ Fns = $newFns; Tag = 'new' })) {
    $out = Invoke-Sandbox -Fns $pair.Fns -Vars @{ LogFile = 'C:\ProgramData\ClawFactory\install.log'; FirewallRuleName = 'x' } -Stubs $rbStub -Body {
        try { Invoke-WithRollback -Body { throw 'Failed to pre-create clawuser stub (exit=-1)' } } catch { }
        return , $script:Lines
    }
    Set-Variable -Name ("rb_" + $pair.Tag) -Value @($out)
}
$oldClaims = @($rb_old | Where-Object { $_ -like '*Undoing: Preflight*' }).Count
$newClaims = @($rb_new | Where-Object { $_ -like '*Undoing: Preflight*' }).Count
$newSays   = @($rb_new | Where-Object { $_ -like '*No rollback action is defined*' }).Count
Row 'D6.1' 'rollback of a step with no case must not claim it undid it' `
    "logged 'Undoing: Preflight' x$oldClaims and did nothing" `
    "logged 'Undoing: Preflight' x$newClaims, 'No rollback action is defined' x$newSays" `
    $(if ($oldClaims -eq 1 -and $newClaims -eq 0 -and $newSays -eq 1) { 'PASS' } else { 'FAIL' }) `
    'checkpoint.json from the external machine reads {"completedSteps":["Preflight"]}'
$oldLog = @($rb_old | Where-Object { $_ -like '*install.log*' }).Count
$newLog = @($rb_new | Where-Object { $_ -like '*install.log*' }).Count
Row 'D7.1' 'ACCEPTING the rollback must still print where the log is' `
    "log path printed $oldLog time(s)" "log path printed $newLog time(s)" `
    $(if ($oldLog -eq 0 -and $newLog -ge 1) { 'PASS' } else { 'FAIL' }) `
    'the user who accepted it was never told; measured cost of that omission: 41 minutes'

# ============================================================================
# D8 -- the consequence, measured rather than asserted: UTF-16 nulls make a
# search over install.log silently find nothing.
# ============================================================================
$nulLog   = Join-Path $Scratch 'with-nulls.log'
$cleanLog = Join-Path $Scratch 'no-nulls.log'
$line     = 'There is no distribution with the supplied name.'
$withNul  = ($line.ToCharArray() | ForEach-Object { "$_`0" }) -join ''
[IO.File]::WriteAllText($nulLog,   "[wsl:root out] $withNul`n")
[IO.File]::WriteAllText($cleanLog, "[wsl:root out] $($withNul -replace "`0", '')`n")
$hitNul   = @(Select-String -Path $nulLog   -Pattern 'no distribution' -SimpleMatch -ErrorAction SilentlyContinue).Count
$hitClean = @(Select-String -Path $cleanLog -Pattern 'no distribution' -SimpleMatch -ErrorAction SilentlyContinue).Count
$stripMarker = '$stdout = $stdout -replace'
$oldStrips   = $oldText.Contains($stripMarker)
$newStrips   = $newText.Contains($stripMarker)
Row 'D8.1' 'nulls in install.log defeat a plain search for the diagnostic line' `
    "old Invoke-WslBash strips nulls: $oldStrips -- searching the null-bearing file found $hitNul match(es)" `
    "new Invoke-WslBash strips nulls: $newStrips -- searching the stripped file found $hitClean match(es)" `
    $(if (-not $oldStrips -and $newStrips -and $hitNul -eq 0 -and $hitClean -eq 1) { 'PASS' } else { 'FAIL' }) `
    'the search over the null-bearing file is the calibration: it MUST find nothing'

#--- verdict ------------------------------------------------------------------
Write-Host ''
$fail = @($script:Rows | Where-Object { $_.Verdict -eq 'FAIL' }).Count
$void = @($script:Rows | Where-Object { $_.Verdict -eq 'VOID' }).Count
$pass = @($script:Rows | Where-Object { $_.Verdict -eq 'PASS' }).Count
Write-Host ("PASS $pass   FAIL $fail   VOID $void") -ForegroundColor $(if ($fail) { 'Red' } elseif ($void) { 'Yellow' } else { 'Green' })
Remove-Item -Recurse -Force $Scratch -ErrorAction SilentlyContinue
if ($fail -gt 0) { exit 1 }
if ($void -gt 0) { exit 4 }
exit 0
