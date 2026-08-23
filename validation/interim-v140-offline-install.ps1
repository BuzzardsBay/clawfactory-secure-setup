<#
  v1.4.0 release gate, box B. Two matrix rows that cannot be taken on box A
  because both are properties of the INSTALL ITSELF and box A is already
  installed.

    row 2  the install completes on a machine that cannot reach
           api.clawfactory.app. It must not fail closed the way it used to.
    row 4  the provider gate is SKIPPED, with a stated reason, under
           -Provider later.

  The two conditions are independent: one is a network block on a host nothing
  contacts any more, the other a wizard argument. They are combined onto one box
  deliberately and that combination is stated in the close-out rather than left
  for a reader to notice.

  WHY THERE IS A SECOND INSTALLER ON THIS BOX.
  A subject that completes under a block proves nothing on its own. It could
  complete because the block does not work. So this probe runs the LAST
  licence-carrying build we still hold, v1.1.1, under the SAME block first, and
  requires it to ABORT. That turns the block from an assumption into a measured
  fact and makes the behaviour change observable rather than argued:

    control B1  the block is real            (a connect to the subject fails
                                              while a control host succeeds)
    control B2  the block WOULD have stopped the old code
                                             (v1.1.1 /SILENT aborts at its
                                              licence gate and installs nothing)
    subject     v1.4.0 installs to completion under the identical block

  v1.1.1 aborts inside InitializeWizard, before any file is copied and before
  setup.ps1 is invoked, so it leaves the box clean for the subject. This probe
  asserts that cleanliness rather than trusting it, because a partial install
  under the subject would poison every row after it.
#>
param(
    [string]$CombinedExe = 'C:\cfv\combined-setup.exe',
    [string]$PriorExe    = 'C:\cfv\prior-setup.exe',
    [string]$Transcript  = 'C:\cfv\offline-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

function Finish($code) {
    W ''
    W "OFFLINE_PROBE_COMPLETE rc=$code"
    exit $code
}

$SUBJECT = 'api.clawfactory.app'
$CONTROL = 'openclaw.ai'

Start-Phase -Name 'ClawFactory v1.4.0 release gate, box B (offline licence host + deferred provider)' `
    -Transcript $Transcript -Sentinel 'OFFLINE_PROBE_COMPLETE'

# ---------------------------------------------------------------- 1. the block
Section '1. Make the licence host unreachable, and prove the block is real'

function ResolveA([string]$h) {
    try { @((Resolve-DnsName $h -Type A -ErrorAction Stop | Where-Object { $_.IPAddress }).IPAddress) }
    catch { @() }
}
$subjectIps = ResolveA $SUBJECT
$controlIps = ResolveA $CONTROL
W "subject $SUBJECT -> $(if ($subjectIps) { $subjectIps -join ',' } else { '(did not resolve)' })"
W "control $CONTROL -> $(if ($controlIps) { $controlIps -join ',' } else { '(did not resolve)' })"

$canBlock = Require-Precondition -Id 'B0' -Name "$SUBJECT resolves, so there is something to block" `
    -Met ($subjectIps.Count -gt 0) `
    -Reason "a host that does not resolve cannot be blocked, and an install that completes without it would prove nothing about a blocked one"
if (-not $canBlock) { Marker 'OFFLINE_FEASIBILITY_FAIL'; Complete-Phase -ResultsJson 'C:\cfv\offline-results.json' -MarkerPrefix 'OFFLINE'; Finish 4 }

Remove-NetFirewallRule -DisplayName 'cfv-block-licence-host' -ErrorAction SilentlyContinue
foreach ($ip in $subjectIps) {
    New-NetFirewallRule -DisplayName 'cfv-block-licence-host' -Direction Outbound -Action Block `
        -RemoteAddress $ip -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null
}
W "outbound block installed for $($subjectIps.Count) address(es)"

# The reachability probe is calibrated in BOTH directions in the same read. A
# block instrument proven only against the host it blocks passes whether the
# rule matched or the network was simply down.
function TryConnect([string]$h) {
    try {
        $r = Test-NetConnection -ComputerName $h -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
        return [bool]$r
    } catch { return $false }
}
$subjReach = TryConnect $SUBJECT
$ctlReach  = TryConnect $CONTROL
W "after the block: $SUBJECT reachable=$subjReach ; $CONTROL reachable=$ctlReach"

$blockProven = (-not $subjReach) -and $ctlReach
Register-Control -Id 'B1' -Name 'the block is real and specific' -Fired $blockProven `
    -Evidence "subject reachable=$subjReach (must be False), control $CONTROL reachable=$ctlReach (must be True). Both halves are required: a subject that is merely unreachable proves nothing if everything is unreachable." | Out-Null

# ------------------------------------------- 2. control B2, the old build dies
Section '2. CONTROL: the last licence-carrying build ABORTS under this same block'

$havePrior = Require-Precondition -Id 'B2.0' -Name 'v1.1.1 is staged on the box' `
    -Met (Test-Path $PriorExe) `
    -Reason "without the old build there is no measured evidence that the block would have stopped the licence call, only an argument from source"
if ($havePrior) {
    W "prior artifact sha256: $((Get-FileHash $PriorExe -Algorithm SHA256).Hash.ToLower())"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Start-Process -FilePath $PriorExe -ArgumentList `
        '/SILENT','/SUPPRESSMSGBOXES','/NORESTART','/LOG=C:\cfv\prior-install.log', `
        '/PROVIDER=claude','/LICENSE=CF-TEST-TEST-TEST-TEST' -Wait
    $sw.Stop()
    W "v1.1.1 returned after $([int]$sw.Elapsed.TotalSeconds)s"

    $priorLog = if (Test-Path 'C:\cfv\prior-install.log') { Get-Content 'C:\cfv\prior-install.log' -Raw } else { '' }
    $priorAborted = $priorLog -match 'License activation failed'
    $priorInstalled = (Test-Path 'C:\Program Files\ClawFactory\setup.ps1')
    foreach ($ln in @($priorLog -split "`r?`n" | Where-Object { $_ -match 'License|Abort' })) { W "   PRIOR> $ln" }
    W "v1.1.1 log says licence activation failed : $priorAborted"
    W "v1.1.1 left an install behind             : $priorInstalled"

    Register-Control -Id 'B2' -Name 'the block WOULD have stopped the old licence-carrying build' `
        -Fired ($priorAborted -and (-not $priorInstalled)) `
        -Evidence "v1.1.1 under the identical block: log carries 'License activation failed'=$priorAborted, and it installed nothing=$(-not $priorInstalled). This is what v1.4.0 is being compared against." | Out-Null

    Record 'B2.1' 'v1.1.1 left the box clean for the subject install' `
        $(if (-not $priorInstalled) { 'PASS' } else { 'FAIL' }) `
        "Program Files\ClawFactory\setup.ps1 present=$priorInstalled. A partial install here would poison every row after it."
}

# --------------------------------------------------- 3. the subject: v1.4.0
Section '3. SUBJECT: v1.4.0 installs to completion under the identical block, provider deferred'

if (-not (Test-Path $CombinedExe)) {
    Record 'B3.0' 'v1.4.0 present on the box' 'FAIL' "missing at $CombinedExe"
    Marker 'OFFLINE_FEASIBILITY_FAIL'
    Complete-Phase -ResultsJson 'C:\cfv\offline-results.json' -MarkerPrefix 'OFFLINE'
    Finish 2
}
W "subject artifact sha256: $((Get-FileHash $CombinedExe -Algorithm SHA256).Hash.ToLower())"

$sw2 = [Diagnostics.Stopwatch]::StartNew()
Start-Process -FilePath $CombinedExe -ArgumentList `
    '/SILENT','/SUPPRESSMSGBOXES','/NORESTART','/LOG=C:\cfv\install.log','/PROVIDER=later' -Wait
$sw2.Stop()
W "v1.4.0 returned after $([int]$sw2.Elapsed.TotalMinutes) min"
Marker 'OFFLINE_INSTALL_RETURNED'

# The Inno exit code is not the honest verdict. setup.ps1 writes the real one.
$resultFile = 'C:\ProgramData\ClawFactory\install-result.txt'
$verdict = if (Test-Path $resultFile) { (Get-Content $resultFile -Raw).Trim() } else { '(install-result.txt ABSENT)' }
W "install-result.txt: $verdict"

Record 'B3' "ROW 2: v1.4.0 installs to completion with $SUBJECT unreachable" `
    $(if ($verdict -match 'success') { 'PASS' } else { 'FAIL' }) `
    "install-result.txt='$verdict'. The old build under this identical block aborted before copying a file (control B2), so this is a behaviour change measured on one machine rather than argued from source."

# The licence host must still be unreachable AFTER the install. A block that
# lapsed part way through would make the row above meaningless.
$subjReachAfter = TryConnect $SUBJECT
Record 'B3.1' 'the block was still in force when the install finished' `
    $(if (-not $subjReachAfter) { 'PASS' } else { 'FAIL' }) `
    "subject reachable after install=$subjReachAfter (must be False). A lapsed block would silently turn row 2 into an ordinary install."

# ------------------------------------------ 4. row 4, the deferred provider
Section '4. ROW 4: the provider gate is SKIPPED, with a stated reason'

$setupLog = @(
    'C:\ProgramData\ClawFactory\install.log',
    'C:\ProgramData\ClawFactory\logs\setup.log'
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $setupLog) {
    Record 'B4' 'ROW 4: provider gate skipped with a stated reason' 'VOID' `
        'setup.ps1 install log not found, so the gate decision cannot be read. Not a product verdict.'
} else {
    $log = Get-Content $setupLog -Raw
    # Named reason, not merely absent output. "The gate did not run" and "the gate
    # ran and said nothing" are different products, and only one of them is
    # honest about a deferred provider.
    $gateLines = @([regex]::Matches($log, '(?im)^.*(provider gate|providergate|provider route|deferred|no provider|provider later).*$') |
                    ForEach-Object { $_.Value.Trim() })
    foreach ($ln in $gateLines) { W "   GATE> $ln" }
    $skippedWithReason = ($gateLines | Where-Object { $_ -match '(?i)skip|defer|later|not configured' }).Count -gt 0
    Record 'B4' 'ROW 4: provider gate skipped with a stated reason under -Provider later' `
        $(if ($skippedWithReason) { 'PASS' } else { 'FAIL' }) `
        "matched $($gateLines.Count) provider-gate line(s) in the install log; a skip with a named reason present=$skippedWithReason"

    # Positive control for the search itself. If the log cannot be searched at
    # all, an absent match reads exactly like a clean skip.
    Assert-Searchable -Id 'B4.SEARCH' -Name 'the install log is searchable' `
        -PositiveMarkerFound ($log -match '(?i)Step 1') `
        -MarkerDescription 'the string "Step 1" inside the setup.ps1 install log' | Out-Null
}

Complete-Phase -ResultsJson 'C:\cfv\offline-results.json' -MarkerPrefix 'OFFLINE'
Finish 0
