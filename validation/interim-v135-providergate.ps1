<#
  v1.3.5 validation: THE INSTALL-TIME PROVIDER-ROUTE GATE (card #258, tests 2 and 3).

  WHAT IS BEING TESTED
  --------------------
  setup.ps1 Step-AssertProviderRoute runs LAST, as clawuser, inside WSL, after
  every firewall write, and opens a TCP connection to the provider host on 443.
  If it cannot, the install is refused. Before 1.3.5 there was no such check at
  all: the final gate is a loopback curl that never leaves the box, and the key
  wizard's request runs Windows-side, outside the clawuser chain, and is skipped
  under /SILENT.

  HOW THE CONTROL IS RIGGED, AND WHY THIS RIG RATHER THAN A FIREWALL EDIT
  -----------------------------------------------------------------------
  A gate proven only on a healthy box is a gate proven in one direction, which is
  the cfv-167 error. So the provider must be made genuinely unreachable and the
  gate must be seen to fail.

  The rig is an /etc/hosts entry pointing the provider host at 192.0.2.1, which is
  TEST-NET-1 and unroutable by definition. A firewall edit was rejected because
  Step-EgressFirewall rewrites the ruleset, so a rigged rule would be undone by
  the very re-run that is supposed to observe it, and the gate would pass for the
  wrong reason. /etc/hosts survives that, and getent is what the gate resolves
  with, so the rig lands where the measurement looks.

  TWO LEVELS OF CONTROL, BOTH REPORTED HONESTLY
  ----------------------------------------------
    LEVEL 1, always: the gate's own probe body, extracted from the INSTALLED
      setup.ps1, run as clawuser rigged and unrigged. This calibrates the
      MEASUREMENT in both directions and costs seconds.
    LEVEL 2, only with -RunFullInstallControl: the whole installer re-run with
      the rig in place, asserting it actually ABORTS. This is the loud-failure
      half and it costs a full install. When it is not run, that is recorded as
      an explicit INFO row rather than left to look like a pass.
#>
param(
    [string]$Transcript = 'C:\cfv\providergate-out-probe.txt',
    [string]$AppDir     = 'C:\Program Files\ClawFactory',
    [string]$ProviderHost = 'api.anthropic.com',
    # setup.ps1 writes here. NOT under a logs\ subdirectory: that path was assumed
    # when this phase was staged and it does not exist, so the phase would have
    # read nothing and reported a clean absence. Confirmed against cfv-169.
    [string]$InstallLog = 'C:\ProgramData\ClawFactory\install.log',
    [switch]$RunFullInstallControl,
    [switch]$DeferredProvider
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'ClawFactory v1.3.5 install-time provider-route gate' `
    -Transcript $Transcript -Sentinel 'PROVIDERGATE_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'PG.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) {
    W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'
    Complete-Phase -ResultsJson 'C:\cfv\providergate-results.json' -MarkerPrefix 'PROVIDERGATE'
}

# =========================================================================
Section '1. What the install itself recorded.'
$logText = if (Test-Path $InstallLog) { Get-Content $InstallLog -Raw } else { '' }
Require-Precondition -Id 'PG.1.PRE' -Name 'the install log is present and readable' -Met ([bool]$logText) `
    -Reason "the gate's own verdict is written here; without the log, 'the gate passed' and 'the gate never ran' are indistinguishable" | Out-Null

# Searchability first: a search for a phrase in a log that cannot be searched
# reports a clean absence and says nothing.
Assert-Searchable -Id 'PG.1.SRCH' -Name 'the install log' `
    -PositiveMarkerFound ($logText -match 'completed successfully|INSTALLER_DONE|Step 1:') `
    -MarkerDescription 'a known install-log phrase' | Out-Null

if ($DeferredProvider) {
    # TEST 3. The skip must be VISIBLE and must carry its reason. A gate that
    # silently does nothing when its subject is absent is indistinguishable from
    # a gate that is broken.
    Record 'PG.3a' 'TEST 3: with the provider deferred, the gate is SKIPPED and says so' `
        $(if ($logText -match 'Provider-route gate SKIPPED, reason: provider deferred') { 'PASS' } else { 'FAIL' }) `
        'the installer output must name the skip and its reason rather than passing silently'
    Record 'PG.3b' 'TEST 3: the deferred install still completed' `
        $(if ($logText -match 'completed successfully') { 'PASS' } else { 'FAIL' }) `
        'the skip must not turn into a refusal: there is simply no provider to reach yet'
    Complete-Phase -ResultsJson 'C:\cfv\providergate-results.json' -MarkerPrefix 'PROVIDERGATE'
}

# PRECONDITION, ADDED 2026-08-28. PG.2a and PG.2b read the INSTALL LOG for a
# verdict the gate writes. On a box installed with the provider DEFERRED the gate
# never runs, so it writes no verdict, and both rows would report FAIL against an
# installer that behaved exactly as designed.
#
# That is not hypothetical: box B installs with `-Provider later` and is the box
# that pays for the level-2 control below, so this phase gets run there a second
# time WITHOUT -DeferredProvider precisely to reach section 3. Without this
# precondition that second run manufactures two product FAILs out of a deliberate
# install variant.
#
# It is DISCOVERED, not assumed: the log is searched for either verdict the gate
# can write, so "the gate ran and passed", "the gate ran and failed" and "the gate
# never ran" are three distinguishable states rather than two.
$gateRan = $logText -match 'Provider-route gate (PASSED|FAILED)'
$gateSkipped = $logText -match 'Provider-route gate SKIPPED'
W "install log states: gateRan=$gateRan gateSkipped=$gateSkipped"
$gateSubject = Require-Precondition -Id 'PG.2.PRE' -Name 'this install actually RAN the provider-route gate' `
    -Met $gateRan `
    -Reason "PG.2a and PG.2b read a verdict the gate writes to the install log. gateRan=$gateRan gateSkipped=$gateSkipped. On an install with the provider deferred the gate is skipped by design and writes no verdict, so those two rows have no subject and record VOID rather than manufacturing a product FAIL out of a deliberate install variant"

Record 'PG.2a' 'TEST 2: the provider-route gate PASSED on this healthy box' `
    $(if (-not $gateSubject) { 'VOID' } elseif ($logText -match 'Provider-route gate PASSED') { 'PASS' } else { 'FAIL' }) `
    'the gate logs its own verdict; this reads the installer''s record rather than re-deriving it'
Record 'PG.2b' 'The gate ran as clawuser, after the last firewall write' `
    $(if (-not $gateSubject) { 'VOID' } elseif ($logText -match 'Provider-route gate - TCP connect to .*:443 as clawuser, after the last firewall write') { 'PASS' } else { 'FAIL' }) `
    'placement is the whole point: every pre-existing check either stayed on loopback or ran Windows-side'

# =========================================================================
Section '2. LEVEL 1 CONTROL: the gate''s own probe, run rigged and unrigged.'
# The probe body is extracted from the INSTALLED setup.ps1 so this calibrates the
# shipped measurement rather than a copy of it.
$renderPs = @"
`$ErrorActionPreference='Stop'
`$p = '$AppDir\setup.ps1'
if (-not (Test-Path `$p)) { 'RENDER_FAIL missing ' + `$p; exit }
`$lines = [IO.File]::ReadAllLines(`$p)
`$start = (`$lines | Select-String -SimpleMatch '`$probe = @"' | Select-Object -First 1).LineNumber
if (-not `$start) { 'RENDER_FAIL no probe here-string in the installed setup.ps1'; exit }
`$end = `$null; for (`$i = `$start; `$i -lt `$lines.Count; `$i++) { if (`$lines[`$i].TrimEnd() -eq '"@') { `$end = `$i + 1; break } }
if (-not `$end) { 'RENDER_FAIL no here-string terminator'; exit }
`$providerHost = '$ProviderHost'
`$body = (`$lines[`$start..(`$end-2)] -join "``n")
`$rendered = `$ExecutionContext.InvokeCommand.ExpandString(`$body)
[IO.File]::WriteAllText('C:\cfv\pg-probe.sh', `$rendered.Replace("``r``n","``n"), (New-Object Text.UTF8Encoding(`$false)))
"RENDER_OK bytes=`$(`$rendered.Length)"
"@
# Via a FILE, never -Command; see the matching note in interim-v135-switchprovider.ps1.
[IO.File]::WriteAllText('C:\cfv\pg-render.ps1', $renderPs, (New-Object Text.UTF8Encoding($false)))
$rr = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\cfv\pg-render.ps1' 2>&1) -join "`n"
W $rr
$renderOk = $rr -match 'RENDER_OK'
Register-Control -Id 'PG.2.CTL0' -Name 'the gate probe was extracted from the INSTALLED setup.ps1' `
    -Fired $renderOk -Evidence 'this control must calibrate the shipped measurement, not a re-implementation of it' | Out-Null

if ($renderOk) {
    $probeText = [IO.File]::ReadAllText('C:\cfv\pg-probe.sh')
    $lf = ($probeText -replace "`r`n", "`n") -replace "`r", "`n"
    $put = Invoke-WslFile -Tag 'pg-put' -User 'root' -Body "cat > /var/tmp/pg-probe.sh <<'CFSCRIPTEOF'`n$lf`nCFSCRIPTEOF`nchmod 755 /var/tmp/pg-probe.sh`necho `"WROTE=`$(wc -c < /var/tmp/pg-probe.sh | tr -d ' ')`""
    W $put.Out
    Register-Control -Id 'PG.2.CTL1' -Name 'the gate probe reached the distro intact' `
        -Fired ($put.Out -match 'WROTE=[1-9]') -Evidence 'a truncated probe would fail for the wrong reason and look like a blocked route' | Out-Null

    # UNRIGGED: must succeed. This is the positive half and it must fire in the
    # same run as the negative half, or neither means anything.
    $unrig = Invoke-WslFile -Tag 'pg-unrig' -User 'clawuser' -Body 'bash /var/tmp/pg-probe.sh; echo "PROBE_RC=$?"'
    W $unrig.Out
    $unrigOk = $unrig.Out -match 'PROBE_RC=0'

    # RIGGED: /etc/hosts points the provider at TEST-NET-1, which is unroutable.
    $rig = Invoke-WslFile -Tag 'pg-rig' -User 'root' -Body @"
cp /etc/hosts /var/tmp/hosts.bak
echo "192.0.2.1 $ProviderHost" >> /etc/hosts
echo "RIG_LANDED=`$(getent ahostsv4 $ProviderHost | awk '{print `$1}' | sort -u | tr '\n' ' ')"
"@
    W $rig.Out
    # THE FAULT MUST BE PROVEN TO HAVE LANDED. A rig that does not rig scores a
    # false pass and looks exactly like a working control.
    $rigLanded = $rig.Out -match 'RIG_LANDED=.*192\.0\.2\.1'
    Register-Control -Id 'PG.2.CTL2' -Name 'THE FAULT LANDED: the provider host now resolves to an unroutable address' `
        -Fired $rigLanded -Evidence "getent output after the rig: $(if ($rig.Out -match 'RIG_LANDED=(.*)') { $Matches[1] } else { 'not reported' })" | Out-Null

    $rigged = Invoke-WslFile -Tag 'pg-rigged' -User 'clawuser' -Body 'bash /var/tmp/pg-probe.sh; echo "PROBE_RC=$?"'
    W $rigged.Out
    $riggedFails = $rigged.Out -match 'PROBE_RC=1'

    $unrig2 = Invoke-WslFile -Tag 'pg-unrig2' -User 'root' -Body @"
cp /var/tmp/hosts.bak /etc/hosts
echo "RESTORED=`$(getent ahostsv4 $ProviderHost | awk '{print `$1}' | sort -u | tr '\n' ' ')"
"@
    W $unrig2.Out
    $restored = ($unrig2.Out -match 'RESTORED=') -and ($unrig2.Out -notmatch 'RESTORED=.*192\.0\.2\.1')

    Register-Control -Id 'PG.2.CTL3' -Name 'the gate probe SUCCEEDS on the healthy box in this same run' `
        -Fired $unrigOk -Evidence 'without this the failure below could mean the probe simply never works here' | Out-Null
    Record 'PG.2c' 'TEST 2 CONTROL: with the provider route deliberately broken, the gate''s probe FAILS' `
        $(if ($riggedFails) { 'PASS' } else { 'FAIL' }) `
        "unrigged rc=0: $unrigOk (must be true); rigged rc=1: $riggedFails (must be true). Both halves in one run"
    Record 'PG.2d' 'The rig was removed and the provider resolves normally again' `
        $(if ($restored) { 'PASS' } else { 'FAIL' }) `
        'a probe that leaves its fault behind poisons every phase after it, and this one would brick the agent'
}

# =========================================================================
Section '3. LEVEL 2 CONTROL: does the INSTALLER actually abort, loudly?'
if ($RunFullInstallControl) {
    W 'Re-running the installer with the provider route rigged. This is a full install and is slow.'
    $l2 = Invoke-WslFile -Tag 'pg-l2-rig' -User 'root' -Body @"
cp /etc/hosts /var/tmp/hosts.bak2
grep -q '192.0.2.1 $ProviderHost' /etc/hosts || echo "192.0.2.1 $ProviderHost" >> /etc/hosts
echo "L2_RIG=`$(getent ahostsv4 $ProviderHost | awk '{print `$1}' | sort -u | tr '\n' ' ')"
"@
    W $l2.Out
    Register-Control -Id 'PG.3.CTL' -Name 'THE FAULT LANDED for the level-2 control' `
        -Fired ($l2.Out -match 'L2_RIG=.*192\.0\.2\.1') -Evidence 'the installer is about to be re-run against this rig' | Out-Null

    $before = if (Test-Path $InstallLog) { (Get-Item $InstallLog).Length } else { 0 }
    $inst = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$AppDir\setup.ps1" `
                -AcknowledgedOpenClawUrl -Provider claude -Silent 2>&1
    W (($inst | Select-Object -Last 25) -join "`n")
    $after = if (Test-Path $InstallLog) { Get-Content $InstallLog -Raw } else { '' }
    $tail  = if ($after.Length -gt $before) { $after.Substring($before) } else { $after }

    # CLASSIFY, DO NOT TEST FOR ABSENCE. Four mutually exclusive states, and the
    # state is printed. The old shape asked only "does the tail contain the gate's
    # failure string", which cannot distinguish an install that aborted somewhere
    # ELSE under the same rig from one that aborted at the gate -- and the rig
    # points the provider host at an unroutable address for the WHOLE install, not
    # just for step 15h, so an earlier abort is a live possibility that has never
    # been measured. Naming it is the difference between a result and a guess.
    $st3 =
        if     ($tail -match 'Provider-route gate FAILED')                    { 'GATE_ABORT' }
        elseif ($tail -match 'INSTALLER_DONE=failure')                        { 'OTHER_ABORT' }
        elseif ($tail -match 'INSTALLER_DONE=success')                        { 'COMPLETED' }
        else                                                                  { 'NO_MARKER' }
    $reasonLine = (($tail -split "`r?`n") | Where-Object { $_ -match 'INSTALLER_DONE=' } | Select-Object -First 1)
    W "LEVEL2_STATE=$st3"
    W "LEVEL2_MARKER=$reasonLine"
    Record 'PG.3c' 'TEST 2 CONTROL, loud half: the installer REFUSED at the provider-route gate rather than completing' `
        $(if ($st3 -eq 'GATE_ABORT') { 'PASS' } elseif ($st3 -eq 'NO_MARKER') { 'VOID' } else { 'FAIL' }) `
        "state=$st3 (GATE_ABORT is the pass; OTHER_ABORT means the rig stopped the install somewhere earlier and the gate was never reached, which is a different result and not this control; COMPLETED means the rig did not stop it at all; NO_MARKER means the installer emitted no verdict, so nothing was measured). The refusal must NAME the gate, so an operator reading the log knows what to fix"
    Record 'PG.3d' 'The refusal reached the harness channel as a failure, not a timeout' `
        $(if ($st3 -eq 'GATE_ABORT' -or $st3 -eq 'OTHER_ABORT') { 'PASS' } elseif ($st3 -eq 'NO_MARKER') { 'FAIL' } else { 'FAIL' }) `
        "state=$st3, marker line: $reasonLine. A clean failure that emits nothing looks identical to a hang. The old form of this row matched bare 'INSTALLER_DONE', which INSTALLER_DONE=success also satisfies, so it could not fail"

    $l2r = Invoke-WslFile -Tag 'pg-l2-unrig' -User 'root' -Body @"
cp /var/tmp/hosts.bak2 /etc/hosts
echo "L2_RESTORED=`$(getent ahostsv4 $ProviderHost | awk '{print `$1}' | sort -u | tr '\n' ' ')"
"@
    W $l2r.Out
    Record 'PG.3e' 'The level-2 rig was removed' `
        $(if ($l2r.Out -notmatch 'L2_RESTORED=.*192\.0\.2\.1') { 'PASS' } else { 'FAIL' }) `
        'the box must be left usable for the phases after this one'
} else {
    Record 'PG.3f' 'LEVEL 2 CONTROL NOT RUN: the installer''s loud abort was not observed in this run' 'INFO' `
        'Level 1 above proves the gate MEASURES correctly in both directions on the shipped probe. It does NOT observe the installer aborting. Re-run this phase with -RunFullInstallControl to close that half; it costs a full install. Recorded as INFO rather than omitted, because a control that was skipped and a control that passed must never look the same in a results file'
}

Complete-Phase -ResultsJson 'C:\cfv\providergate-results.json' -MarkerPrefix 'PROVIDERGATE'
