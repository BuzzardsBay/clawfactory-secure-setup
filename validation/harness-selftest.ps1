<#
  harness-selftest.ps1 -- proves the phase runner against DELIBERATELY BROKEN
  inputs.

  WHY THIS EXISTS, AND WHY A CLEAN RUN WOULD NOT DO
  -------------------------------------------------
  The four defects the runner now guards against all shipped while the harness
  was passing. Every one of them produced a clean-looking transcript. So a green
  run of the hardened harness is not evidence that the hardening works: it is
  evidence that the box was healthy, which is exactly the confusion that caused
  the defects in the first place.

  The only thing that demonstrates a guard is watching it fire. For each of the
  four defect classes this constructs an input where the thing being measured is
  ABSENT, runs the REAL interim-v120-phaselib.ps1 over it in a child process, and
  asserts on the exit code and the emitted results file.

  It uses the real library rather than a copy on purpose. A self-test against a
  reimplementation of the thing under test proves that the reimplementation
  works, which is the same category of error as everything above.

  Injected fault              Expected
  --------------------------  ------------------------------------------------
  1 precondition removed      VOID, named reason, no PASS and no FAIL
  2 positive control removed  VOID
  3 target is a compressed    VOID, absences NOT reported clean
    blob, so nothing is
    findable
  4 independent list edited   FAIL naming BOTH numbers
    to disagree

  Note on 4. It is the one case that is deliberately NOT void. A disagreement
  between the harness's copy and the product's report is a real finding about a
  real stale list, so voiding it would discard the very signal the comparison
  exists to raise. The work-package summary table calls all four "VOID"; the
  detailed table calls this one FAIL, and the detailed table is the one that is
  right. Recorded here rather than silently resolved.

  Runs anywhere PowerShell does. It touches no VM, no WSL and no product state,
  so it is cheap enough to run before every build as well as on the box.
#>
[CmdletBinding()]
param(
    [string]$WorkDir = (Join-Path $env:TEMP "cf-harness-selftest-$PID")
)

$ErrorActionPreference = 'Stop'
$RepoRoot   = Split-Path -Parent $PSScriptRoot
$PhaseLib   = Join-Path $RepoRoot 'validation\interim-v120-phaselib.ps1'
if (-not (Test-Path $PhaseLib)) { throw "harness-selftest: cannot find $PhaseLib" }

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
# The library writes markers to C:\cfv unconditionally; make sure that exists so
# a self-test on a dev box does not fail for a reason that has nothing to do with
# what it is testing.
New-Item -ItemType Directory -Path 'C:\cfv' -Force | Out-Null

$script:Findings = New-Object System.Collections.ArrayList
function Note($m) { Write-Host $m }
function Verdict($id, $name, $ok, $evidence) {
    [void]$script:Findings.Add([pscustomobject]@{ Id = $id; Name = $name; Ok = [bool]$ok; Evidence = $evidence })
    Write-Host ("  [{0}] {1} :: {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $id, $name) `
        -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    Write-Host "        $evidence" -ForegroundColor DarkGray
}

<# Run one synthetic phase body in a CHILD powershell, so an `exit` inside
   Complete-Phase terminates that child and not this script. Returns the exit
   code, the transcript and the parsed results file. #>
function Invoke-SyntheticPhase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Body
    )
    $tr  = Join-Path $WorkDir "$Name.transcript.txt"
    $rj  = Join-Path $WorkDir "$Name.results.json"
    $ps1 = Join-Path $WorkDir "$Name.ps1"
    Remove-Item $tr, $rj -Force -ErrorAction SilentlyContinue

    $full = @"
`$ErrorActionPreference = 'Continue'
. '$PhaseLib'
Start-Phase -Name '$Name' -Transcript '$tr' -Sentinel 'SELFTEST_COMPLETE'
$Body
Complete-Phase -ResultsJson '$rj' -MarkerPrefix 'SELFTEST'
"@
    [IO.File]::WriteAllText($ps1, $full, (New-Object Text.UTF8Encoding($false)))
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 *> (Join-Path $WorkDir "$Name.stdout.txt")
    $rc = $LASTEXITCODE
    $res = if (Test-Path $rj) { Get-Content $rj -Raw | ConvertFrom-Json } else { $null }
    $txt = if (Test-Path $tr) { Get-Content $tr -Raw } else { '' }
    return [pscustomobject]@{ Rc = $rc; Results = $res; Transcript = $txt }
}

Write-Host "`n===== HARNESS SELF-TEST: four injected faults =====`n" -ForegroundColor Cyan
Write-Host "Library under test: $PhaseLib"
Write-Host "Work dir          : $WorkDir`n"

# =====================================================================
# BASELINE. A healthy phase must still PASS. Without this, a runner that
# voided absolutely everything would score four out of four below, and a
# harness that never passes is as useless as one that never fails.
# =====================================================================
Write-Host "--- BASELINE (no fault injected): a healthy phase must still report PASS ---" -ForegroundColor Yellow
$base = Invoke-SyntheticPhase -Name 'baseline' -Body @'
$credentialConfigured = $true
if (Require-Precondition -Id 'B.PRE' -Name 'a credential is configured' -Met $credentialConfigured -Reason 'the synthetic fixture provides one') {
    Register-Control -Id 'B.CTL' -Name 'the probe can reach a known-good target' -Fired $true -Evidence 'synthetic reachable target responded' | Out-Null
    Record 'B.1' 'the subject is refused' 'PASS' 'synthetic refusal observed'
}
'@
Verdict 'SELF.0' 'BASELINE: a healthy phase still reports PASS (the runner is not simply voiding everything)' `
    (($base.Rc -eq 0) -and ($base.Results.PhaseVerdict -eq 'PASS')) `
    "rc=$($base.Rc) PhaseVerdict=$($base.Results.PhaseVerdict)"

# =====================================================================
# FAULT 1. Precondition removed: no SMTP credential.
# This is Phase 6's real failure, reduced. A fresh box has no credential, so
# Guard 2 correctly refuses to queue anything, the ids come back empty, and the
# control tool prints usage text instead of refusing anything. The run produced
# four FAILs and one PASS from a queue that was empty, and the PASS was the more
# dangerous of the two.
# =====================================================================
Write-Host "`n--- FAULT 1: precondition removed (no SMTP credential) ---" -ForegroundColor Yellow
$f1 = Invoke-SyntheticPhase -Name 'fault1-precondition' -Body @'
# The injected fault: the fixture reports NO configured credential.
$credentialConfigured = $false
if (Require-Precondition -Id 'F1.PRE' -Name 'an SMTP credential is configured' -Met $credentialConfigured `
        -Reason 'no SMTP credential on this box, so the send queue is empty and a refusal cannot be told apart from having nothing to refuse') {
    Register-Control -Id 'F1.CTL' -Name 'a queued send exists to act on' -Fired $true -Evidence 'unreachable in this run' | Out-Null
    Record 'F1.1' 'the broker refuses to approve without a credential' 'PASS' 'this is the bogus PASS the old harness emitted'
} else {
    # The phase correctly declines to measure. It records nothing further, which
    # is the behaviour under test: four FAILs and a PASS must NOT appear.
}
'@
$f1NoVerdicts = -not (@($f1.Results.Results | Where-Object { $_.Verdict -eq 'PASS' -or $_.Verdict -eq 'FAIL' }).Count)
$f1Named = "$($f1.Results.VoidReasons)" -match 'no SMTP credential'
Verdict 'SELF.1' 'FAULT 1: a missing precondition yields VOID with a NAMED reason, and no PASS and no FAIL' `
    (($f1.Rc -eq 4) -and ($f1.Results.PhaseVerdict -eq 'VOID') -and $f1NoVerdicts -and $f1Named) `
    "rc=$($f1.Rc) PhaseVerdict=$($f1.Results.PhaseVerdict) pass/fail rows=$(@($f1.Results.Results | Where-Object { $_.Verdict -eq 'PASS' -or $_.Verdict -eq 'FAIL' }).Count) reason=$($f1.Results.VoidReasons -join ' / ')"

# =====================================================================
# FAULT 2. Positive control removed from a phase that would otherwise pass.
# The phase measures a real refusal and reports it, but nothing in the run shows
# the probe could observe a SUCCESS. Blocks measured through an instrument that
# was never shown to work are not results.
# =====================================================================
Write-Host "`n--- FAULT 2: positive control removed from an otherwise-passing phase ---" -ForegroundColor Yellow
$f2 = Invoke-SyntheticPhase -Name 'fault2-nocontrol' -Body @'
# The injected fault: the Register-Control call is gone. Everything else is the
# same phase that passes in the baseline above.
Record 'F2.1' 'the subject is refused' 'PASS' 'synthetic refusal observed, but nothing proves the probe could see a success'
Record 'F2.2' 'a second subject is refused' 'PASS' 'same instrument, same unproven state'
'@
$f2Downgraded = @($f2.Results.Results | Where-Object { $_.OriginalVerdict -eq 'PASS' -and $_.Verdict -eq 'VOID' }).Count
Verdict 'SELF.2' 'FAULT 2: a phase with no positive control cannot report PASS, and its passes are downgraded' `
    (($f2.Rc -eq 4) -and ($f2.Results.PhaseVerdict -eq 'VOID') -and ($f2Downgraded -eq 2)) `
    "rc=$($f2.Rc) PhaseVerdict=$($f2.Results.PhaseVerdict) downgraded PASS->VOID=$f2Downgraded reason=$($f2.Results.VoidReasons -join ' / ')"

# Fault 2b: the control is PRESENT but did not fire. Same expected outcome, and
# it is a genuinely different code path: registered-but-false rather than absent.
Write-Host "`n--- FAULT 2b: positive control present but it did NOT fire ---" -ForegroundColor Yellow
$f2b = Invoke-SyntheticPhase -Name 'fault2b-controlmissed' -Body @'
# The injected fault: the known-good target was unreachable, so the instrument
# was never shown to work in THIS run.
Register-Control -Id 'F2b.CTL' -Name 'the probe can reach a known-good target' -Fired $false -Evidence 'the provider route did not respond' | Out-Null
Record 'F2b.1' 'the subject is refused' 'PASS' 'a refusal measured through an instrument that showed no success'
'@
Verdict 'SELF.2b' 'FAULT 2b: a registered control that did not FIRE voids the phase too' `
    (($f2b.Rc -eq 4) -and ($f2b.Results.PhaseVerdict -eq 'VOID') -and ("$($f2b.Results.VoidReasons)" -match 'did not fire')) `
    "rc=$($f2b.Rc) PhaseVerdict=$($f2b.Results.PhaseVerdict) reason=$($f2b.Results.VoidReasons -join ' / ')"

# =====================================================================
# FAULT 3. The search target is a compressed blob, so nothing is findable.
# The real case: twenty-six panel markers searched for inside a compiled NSIS
# installer. The payload is compressed. The search found nothing, and the
# absent-marker section printed a clean all-clear.
# =====================================================================
Write-Host "`n--- FAULT 3: search target replaced with a compressed blob ---" -ForegroundColor Yellow
$blob = Join-Path $WorkDir 'compressed-payload.bin'
$plain = Join-Path $WorkDir 'plain-payload.txt'
$sample = ("PRESENT_MARKER_ALPHA`nWorkspace`nsome other content`n" * 40)
[IO.File]::WriteAllText($plain, $sample, (New-Object Text.UTF8Encoding($false)))
# A real deflate stream, so the markers are genuinely unfindable rather than
# merely rearranged.
$msIn  = New-Object IO.MemoryStream
$gz    = New-Object IO.Compression.GZipStream($msIn, [IO.Compression.CompressionMode]::Compress)
$bytes = [Text.Encoding]::UTF8.GetBytes($sample)
$gz.Write($bytes, 0, $bytes.Length); $gz.Dispose()
[IO.File]::WriteAllBytes($blob, $msIn.ToArray())
Note "  built a compressed fixture: $((Get-Item $blob).Length) B from $($bytes.Length) B of text"

# Byte-preserving single-byte encoding. NOT [Text.Encoding]::Latin1, which does
# not exist on PS 5.1's .NET Framework: it evaluates to $null, ReadAllText throws
# "Value cannot be null", and the phase dies before it can be measured. Codepage
# 28591 is the same encoding by its portable name.
$latin1 = "[Text.Encoding]::GetEncoding(28591)"

$f3 = Invoke-SyntheticPhase -Name 'fault3-unsearchable' -Body @"
# The injected fault: the phase searches the COMPRESSED artifact instead of the
# extracted one. The stale markers it looks for are genuinely absent from it --
# and so is everything else, which is the whole problem.
`$hay = [IO.File]::ReadAllText('$($blob -replace "\\","\\")', $latin1)
`$positiveFound = `$hay -match 'PRESENT_MARKER_ALPHA'
Assert-Searchable -Id 'F3.SEARCH' -Name 'panel markers in the shipped payload' ``
    -PositiveMarkerFound `$positiveFound ``
    -MarkerDescription 'the positive marker PRESENT_MARKER_ALPHA' | Out-Null
`$staleFound = `$hay -match 'STALE_MARKER_v0_1_0'
Record 'F3.1' 'the stale marker is absent from the shipped payload' ``
    `$(if (-not `$staleFound) { 'PASS' } else { 'FAIL' }) ``
    'this is the clean all-clear the old harness printed over a payload it could not read at all'
"@
$f3AbsenceVoided = @($f3.Results.Results | Where-Object { $_.Id -eq 'F3.1' -and $_.Verdict -eq 'VOID' }).Count -eq 1
Verdict 'SELF.3' 'FAULT 3: an unsearchable target voids the phase, and the "absent" result is NOT reported clean' `
    (($f3.Rc -eq 4) -and ($f3.Results.PhaseVerdict -eq 'VOID') -and $f3AbsenceVoided) `
    "rc=$($f3.Rc) PhaseVerdict=$($f3.Results.PhaseVerdict) F3.1 verdict=$(@($f3.Results.Results | Where-Object Id -eq 'F3.1').Verdict) (was $(@($f3.Results.Results | Where-Object Id -eq 'F3.1').OriginalVerdict))"

# Fault 3 control: the SAME search over the UNCOMPRESSED fixture must pass, or
# the void above proves only that the assertion is unconditional.
Write-Host "`n--- FAULT 3 CONTROL: the same search over a readable payload must PASS ---" -ForegroundColor Yellow
$f3c = Invoke-SyntheticPhase -Name 'fault3-control-searchable' -Body @"
`$hay = [IO.File]::ReadAllText('$($plain -replace "\\","\\")', $latin1)
Assert-Searchable -Id 'F3c.SEARCH' -Name 'panel markers in the shipped payload' ``
    -PositiveMarkerFound (`$hay -match 'PRESENT_MARKER_ALPHA') ``
    -MarkerDescription 'the positive marker PRESENT_MARKER_ALPHA' | Out-Null
Record 'F3c.1' 'the stale marker is absent from the shipped payload' ``
    `$(if (-not (`$hay -match 'STALE_MARKER_v0_1_0')) { 'PASS' } else { 'FAIL' }) 'a real absence, in a payload the search can actually read'
"@
Verdict 'SELF.3c' 'FAULT 3 CONTROL: the identical search over a readable payload reports PASS (the assertion discriminates)' `
    (($f3c.Rc -eq 0) -and ($f3c.Results.PhaseVerdict -eq 'PASS')) `
    "rc=$($f3c.Rc) PhaseVerdict=$($f3c.Results.PhaseVerdict)"

# =====================================================================
# FAULT 4. The harness's independent copy of a list disagrees with what the
# product reports. Expected FAIL, not VOID: this is a real finding about a real
# stale list, and voiding it would discard the signal.
# =====================================================================
Write-Host "`n--- FAULT 4: independent list edited to disagree with the product ---" -ForegroundColor Yellow
$f4 = Invoke-SyntheticPhase -Name 'fault4-disagree' -Body @'
Register-Control -Id 'F4.CTL' -Name 'the product reported a count at all' -Fired $true -Evidence 'installer log line parsed' | Out-Null
# The injected fault: this harness holds 30 while the product ships 33.
$myCopy      = 30
$productSays = 33
Compare-Independent -Id 'F4.1' -Name 'installer resource count and this probe agree' `
    -Mine $myCopy -Reported $productSays `
    -MineLabel 'this probe enumerates' -ReportedLabel 'the installer claims' | Out-Null
'@
$f4Row  = @($f4.Results.Results | Where-Object Id -eq 'F4.1')
$f4Both = ("$($f4Row.Evidence)" -match '\b30\b') -and ("$($f4Row.Evidence)" -match '\b33\b')
Verdict 'SELF.4' 'FAULT 4: a disagreeing independent copy FAILS, and the evidence names BOTH numbers' `
    (($f4.Rc -eq 1) -and ($f4.Results.PhaseVerdict -eq 'FAIL') -and ($f4Row.Verdict -eq 'FAIL') -and $f4Both) `
    "rc=$($f4.Rc) PhaseVerdict=$($f4.Results.PhaseVerdict) F4.1=$($f4Row.Verdict) evidence=$($f4Row.Evidence)"

# Fault 4 control: agreeing copies must PASS, or the comparison is unconditional.
Write-Host "`n--- FAULT 4 CONTROL: agreeing copies must PASS ---" -ForegroundColor Yellow
$f4c = Invoke-SyntheticPhase -Name 'fault4-control-agree' -Body @'
Register-Control -Id 'F4c.CTL' -Name 'the product reported a count at all' -Fired $true -Evidence 'installer log line parsed' | Out-Null
Compare-Independent -Id 'F4c.1' -Name 'installer resource count and this probe agree' `
    -Mine 33 -Reported 33 -MineLabel 'this probe enumerates' -ReportedLabel 'the installer claims' | Out-Null
'@
Verdict 'SELF.4c' 'FAULT 4 CONTROL: agreeing copies report PASS (the comparison discriminates)' `
    (($f4c.Rc -eq 0) -and ($f4c.Results.PhaseVerdict -eq 'PASS')) `
    "rc=$($f4c.Rc) PhaseVerdict=$($f4c.Results.PhaseVerdict)"

# Fault 4b: the product reports NOTHING. An uncompared copy is the original
# defect, and it must not read as agreement.
Write-Host "`n--- FAULT 4b: the product reports nothing to compare against ---" -ForegroundColor Yellow
$f4b = Invoke-SyntheticPhase -Name 'fault4b-nothing-reported' -Body @'
Register-Control -Id 'F4b.CTL' -Name 'the phase ran' -Fired $true -Evidence 'synthetic' | Out-Null
Compare-Independent -Id 'F4b.1' -Name 'installer resource count and this probe agree' `
    -Mine 33 -Reported $null -MineLabel 'this probe enumerates' -ReportedLabel 'the installer claims' | Out-Null
'@
$f4bRow = @($f4b.Results.Results | Where-Object Id -eq 'F4b.1')
Verdict 'SELF.4b' 'FAULT 4b: nothing reported yields VOID, not a silent agreement, and the phase is not a clean pass' `
    (($f4b.Rc -eq 4) -and ($f4b.Results.PhaseVerdict -eq 'VOID') -and ($f4b.Results.VoidKind -eq 'row') -and ($f4bRow.Verdict -eq 'VOID')) `
    "rc=$($f4b.Rc) PhaseVerdict=$($f4b.Results.PhaseVerdict) VoidKind=$($f4b.Results.VoidKind) F4b.1=$($f4bRow.Verdict) evidence=$($f4bRow.Evidence)"

# Fault 4b control: a row-level void must NOT downgrade the phase's other rows.
# The instrument was sound; only one check was untakeable. Downgrading the rest
# would discard good evidence and push an author towards not recording the void.
Write-Host "`n--- FAULT 4b CONTROL: a row-level void leaves the other rows standing ---" -ForegroundColor Yellow
$f4d = Invoke-SyntheticPhase -Name 'fault4d-rowvoid-scope' -Body @'
Register-Control -Id 'F4d.CTL' -Name 'the probe can reach a known-good target' -Fired $true -Evidence 'synthetic reachable target responded' | Out-Null
Record 'F4d.1' 'a measurement that was genuinely taken' 'PASS' 'the instrument was sound for this one'
Compare-Independent -Id 'F4d.2' -Name 'a count the product did not report' `
    -Mine 33 -Reported $null -MineLabel 'this probe enumerates' -ReportedLabel 'the installer claims' | Out-Null
'@
$f4dKept = @($f4d.Results.Results | Where-Object { $_.Id -eq 'F4d.1' -and $_.Verdict -eq 'PASS' }).Count -eq 1
Verdict 'SELF.4d' 'FAULT 4b CONTROL: a row-level void withholds the phase pass but does NOT downgrade sound rows' `
    (($f4d.Rc -eq 4) -and ($f4d.Results.VoidKind -eq 'row') -and $f4dKept) `
    "rc=$($f4d.Rc) VoidKind=$($f4d.Results.VoidKind) F4d.1 survived as PASS=$f4dKept"

# =====================================================================
Write-Host "`n===== HARNESS SELF-TEST RESULT =====" -ForegroundColor Cyan
foreach ($f in $script:Findings) {
    Write-Host ("{0,-10} {1,-5} {2}" -f $f.Id, $(if ($f.Ok) { 'PASS' } else { 'FAIL' }), $f.Name)
}
$bad = @($script:Findings | Where-Object { -not $_.Ok })
$summary = Join-Path $WorkDir 'harness-selftest-results.json'
$script:Findings | ConvertTo-Json -Depth 5 | Out-File $summary -Encoding utf8
Write-Host "`nDetail written to $summary"
Write-Host "Per-fault transcripts and results files are beside it in $WorkDir"

if ($bad.Count -gt 0) {
    Write-Host "`nHARNESS SELF-TEST FAILED: $($bad.Count) of $($script:Findings.Count) checks did not hold." -ForegroundColor Red
    Write-Host 'The phase runner does NOT behave as documented. Do not trust a validation run made with it.' -ForegroundColor Red
    Write-Host 'HARNESS_SELFTEST_COMPLETE rc=1'
    exit 1
}
Write-Host "`nHARNESS SELF-TEST PASSED: $($script:Findings.Count)/$($script:Findings.Count)." -ForegroundColor Green
Write-Host 'Each of the four injected faults was caught, and each paired control shows the guard discriminates.'
Write-Host 'HARNESS_SELFTEST_COMPLETE rc=0'
exit 0
