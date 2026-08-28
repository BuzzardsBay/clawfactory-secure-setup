<#
  Section 14.11, the half box A did not take: a PER-FILE CARRIAGE-RETURN COUNT on
  the shipped Windows-side PowerShell scripts, ON THE BOX.

  WHAT WAS ALREADY COVERED, AND WHAT WAS NOT
  ------------------------------------------
  Box A proved these scripts EXECUTE from their installed form (WR.1/2/3/4/7/8/9)
  and proved, in section 14.8, that the bundled bytes are the committed bytes for
  the set it sampled. Neither of those is a CR count. A file can execute perfectly
  on Windows with CRLF throughout and still break the moment one of its
  here-strings is carried into WSL and run by bash -- which is the L20/L21 class
  this repo pins `*.ps1 text eol=lf` in .gitattributes to prevent, and which
  `git ls-files --eol` showed was silently untrue for ten bundled files as
  recently as v1.4.3. So the count is taken directly.

  CLAUSE 1 -- DISCOVER, DO NOT ASSUME.
  This probe does NOT assert against a list of filenames it was born knowing. It
  ENUMERATES what is actually on the box under the install directory and PRINTS
  the enumeration first. It then compares that discovered set against a held copy
  supplied by the driver from the repo, and reports the two directions of
  difference separately (on the box but not expected / expected but not on the
  box), because those are different defects.

  ONE NAME MOVES BETWEEN SOURCE AND DESTINATION, and it is named here rather than
  guessed at. ClawFactory-Secure-Setup.iss:61 reads

      Source: "smoke-test.ps1";   DestDir: "{app}\resources";   Flags: ignoreversion

  so the file that sits at the REPO ROOT is delivered under {app}\resources, not
  under {app}. Every other shipped .ps1 keeps its relative path. The held copy the
  driver passes uses DESTINATION paths for exactly this reason.

  CLAUSE 2 -- CLASSIFY, DO NOT TEST FOR ABSENCE.
  "CR count is zero" is a positive measurement, not an absence test, but the
  INSTRUMENT that produces it can still be blind -- a reader that fails to open a
  file, or a match that never sees a CR, returns zero for a file full of them.
  So the counter is calibrated in BOTH directions, in this same run, against
  synthetic files built from real shipped bytes:

      planted   the counter reports n+1 on a copy with ONE CR inserted
      stripped  the counter reports 0 on the same copy with CRs removed

  A counter that cannot produce a known-correct answer on a rigged input is not
  permitted to report an answer on a real one.
#>
param(
    [string]$Transcript  = 'C:\cfv\crcensus-out.txt',
    [string]$ResultsJson = 'C:\cfv\crcensus-results.json',
    [string]$AppDir     = 'C:\Program Files\ClawFactory',
    [string]$WorkDir    = 'C:\cfv\crwork',
    # HELD COPY, supplied by the driver, measured on the build machine at the
    # commit under test. Format: one entry per shipped script,
    #     <destination-relative-path>=<crCount>:<bytes>
    # comma separated. An uncompared held copy is a second stale list, so this is
    # compared rather than printed.
    [string]$ExpectCsv  = '',
    # Where the phase runner lives. A parameter, not a constant, so this probe can be
    # DRY-RUN on the build machine against a rigged target before it is ever pointed
    # at a real box. Every probe box A wrote after hour four was defective and none
    # of them could be dry-run; that is not a coincidence.
    [string]$LibDir     = 'C:\cfv'
)

$ErrorActionPreference = 'Continue'
. (Join-Path $LibDir 'interim-v120-phaselib.ps1')

Start-Phase -Name 'Section 14.11: CR census on the shipped Windows-side PowerShell scripts' `
    -Transcript $Transcript -Sentinel 'CRCENSUS_PROBE_COMPLETE'

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# The counter, defined once and used for the calibration AND the census, so the
# thing calibrated is the thing that measures.
function Count-CR([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return -1 }
    # Latin-1 is byte-preserving: every byte maps to exactly one char, so a CR
    # byte cannot be swallowed by a decoder the way it can under a UTF-8 fallback.
    $txt = [IO.File]::ReadAllText($Path, [Text.Encoding]::GetEncoding(28591))
    $n = 0
    foreach ($m in [regex]::Matches($txt, "`r")) { $n++ }
    return $n
}

# =========================================================================
Section '0. DISCOVER: what PowerShell actually shipped to this box'
$found = @()
foreach ($root in @($AppDir, (Join-Path $AppDir 'resources'))) {
    if (Test-Path -LiteralPath $root) {
        foreach ($f in (Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -ErrorAction SilentlyContinue)) {
            $rel = $f.FullName.Substring($AppDir.Length).TrimStart('\')
            $found += [pscustomobject]@{ Rel = $rel; Full = $f.FullName; Bytes = $f.Length }
        }
    } else {
        W "  (absent) $root"
    }
}
foreach ($f in ($found | Sort-Object Rel)) { W ("  FOUND {0,-34} {1} bytes" -f $f.Rel, $f.Bytes) }
W "DISCOVERED_COUNT=$($found.Count)"

# A census over an empty set reports a clean sweep. The vacuity guard is a
# precondition, not a comment.
$haveFiles = Require-Precondition -Id 'CR.PRE' -Name 'at least one shipped .ps1 was found under the install directory' `
    -Met ($found.Count -gt 0) `
    -Reason "AppDir=$AppDir. A CR census over zero files reports zero CRs and means nothing; that is the same shape as the LEGACY_PROBE_FILES=0 sweep that once certified an unsearched tree"
if (-not $haveFiles) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'CRCENSUS' }

# =========================================================================
Section '1. CALIBRATE the counter, in both directions, on real shipped bytes'
# The LARGEST discovered file, not the smallest, and the reason is a defect this
# probe's own dry-run found in it. With `Sort-Object Bytes` ascending, an 18-byte
# file planted in the rigged tree became the calibration subject: the calibration
# still passed, but it was then calibrating the counter against 18 bytes rather
# than against a real script, and any actor who can drop a file into the install
# directory could choose what the instrument calibrates on. Largest-first cannot
# be displaced downwards by adding a file.
$sample = ($found | Sort-Object Bytes -Descending | Select-Object -First 1)
$srcTxt = [IO.File]::ReadAllText($sample.Full, [Text.Encoding]::GetEncoding(28591))
$baseCr = Count-CR $sample.Full
W "calibration sample: $($sample.Rel) ($($sample.Bytes) bytes, CR=$baseCr as shipped)"

$plantPath = Join-Path $WorkDir 'calib-planted.ps1'
$stripPath = Join-Path $WorkDir 'calib-stripped.ps1'
# ONE CR inserted, at a position that exists in every file of any size.
[IO.File]::WriteAllText($plantPath, ($srcTxt.Insert(1, "`r")), [Text.Encoding]::GetEncoding(28591))
[IO.File]::WriteAllText($stripPath, ($srcTxt -replace "`r", ''), [Text.Encoding]::GetEncoding(28591))
$plantCr = Count-CR $plantPath
$stripCr = Count-CR $stripPath
W "PLANTED  expected=$($baseCr + 1)  measured=$plantCr"
W "STRIPPED expected=0               measured=$stripCr"

$calOk = ($plantCr -eq ($baseCr + 1)) -and ($stripCr -eq 0)
Register-Control -Id 'CR.CTL' -Name 'the CR counter reports a NON-ZERO count on a planted CR and zero on stripped bytes' `
    -Fired $calOk `
    -Evidence "planted: expected $($baseCr + 1), measured $plantCr (must be equal); stripped: expected 0, measured $stripCr (must be equal). Both halves are required -- a counter that always returns 0 passes the second alone, and a counter that always returns a positive number passes the first alone" | Out-Null

# =========================================================================
Section '2. THE CENSUS: per-file CR count on the box'
$expect = @{}
foreach ($e in ($ExpectCsv -split ',' | Where-Object { $_ -match '\S' })) {
    if ($e -match '^\s*(.+?)\s*=\s*(\d+)\s*:\s*(\d+)\s*$') {
        $expect[$Matches[1].Trim()] = @{ Cr = [int]$Matches[2]; Bytes = [long]$Matches[3] }
    }
}
W "HELD_COPY_ENTRIES=$($expect.Count)"

$nonZero = @()
foreach ($f in ($found | Sort-Object Rel)) {
    $cr = Count-CR $f.Full
    if ($cr -ne 0) { $nonZero += "$($f.Rel)=$cr" }
    W ("  CR {0,-34} cr={1,-6} bytes={2}" -f $f.Rel, $cr, $f.Bytes)
    Record "CR.$($f.Rel)" "shipped script $($f.Rel) carries no carriage return" `
        $(if (-not $calOk) { 'VOID' } elseif ($cr -eq 0) { 'PASS' } else { 'FAIL' }) `
        "measured cr=$cr, bytes=$($f.Bytes) on the box. The repo pins *.ps1 to eol=lf, so any CR here is a divergence between the shipped bytes and the committed bytes, which is the v1.4.3 class"
}
W "NONZERO_FILES=$(if ($nonZero.Count) { $nonZero -join ' ' } else { '(none)' })"

# =========================================================================
Section '3. COMPARE against the held copy, both directions reported separately'
if ($expect.Count -eq 0) {
    Record 'CR.HELD' 'comparison against a held copy from the repo' 'VOID' `
        'no -ExpectCsv was supplied, so the census above stands on its own and nothing was compared. A held copy that is never compared is a second stale list'
} else {
    $onBoxNotExpected = @($found.Rel | Where-Object { -not $expect.ContainsKey($_) })
    $expectedNotOnBox = @($expect.Keys   | Where-Object { $found.Rel -notcontains $_ })
    $crMismatch = @()
    $byteMismatch = @()
    foreach ($f in $found) {
        if ($expect.ContainsKey($f.Rel)) {
            $cr = Count-CR $f.Full
            if ($cr -ne $expect[$f.Rel].Cr)         { $crMismatch   += "$($f.Rel) box=$cr repo=$($expect[$f.Rel].Cr)" }
            if ($f.Bytes -ne $expect[$f.Rel].Bytes) { $byteMismatch += "$($f.Rel) box=$($f.Bytes) repo=$($expect[$f.Rel].Bytes)" }
        }
    }
    W "ON_BOX_NOT_EXPECTED = $(if ($onBoxNotExpected.Count) { $onBoxNotExpected -join ' ' } else { '(none)' })"
    W "EXPECTED_NOT_ON_BOX = $(if ($expectedNotOnBox.Count) { $expectedNotOnBox -join ' ' } else { '(none)' })"
    W "CR_MISMATCH         = $(if ($crMismatch.Count) { $crMismatch -join ' ; ' } else { '(none)' })"
    W "BYTE_MISMATCH       = $(if ($byteMismatch.Count) { $byteMismatch -join ' ; ' } else { '(none)' })"

    Record 'CR.SET' 'the set of shipped .ps1 on the box is the set the repo bundles' `
        $(if (($onBoxNotExpected.Count -eq 0) -and ($expectedNotOnBox.Count -eq 0)) { 'PASS' } else { 'FAIL' }) `
        "onBoxNotExpected=$($onBoxNotExpected.Count) [$($onBoxNotExpected -join ' ')] ; expectedNotOnBox=$($expectedNotOnBox.Count) [$($expectedNotOnBox -join ' ')]. Reported as two counts, not one, because an extra file and a missing file are different defects"
    Record 'CR.HELD' 'every shipped script matches the repo CR count measured at this commit' `
        $(if (-not $calOk) { 'VOID' } elseif ($crMismatch.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
        "mismatches: $(if ($crMismatch.Count) { $crMismatch -join ' ; ' } else { '(none)' })"
    Record 'CR.BYTES' 'every shipped script matches the repo BYTE COUNT measured at this commit' `
        $(if ($byteMismatch.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
        "mismatches: $(if ($byteMismatch.Count) { $byteMismatch -join ' ; ' } else { '(none)' }). This corroborates section 14.8 per file rather than over a sampled set; a byte difference with an equal CR count would mean the divergence is something other than line endings"
}

Remove-Item -LiteralPath $plantPath, $stripPath -Force -ErrorAction SilentlyContinue
Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'CRCENSUS'
