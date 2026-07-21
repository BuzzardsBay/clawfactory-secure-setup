<#
  Shared wrapper.cmd builder + evidence-gate predicate for JOB 3 (the COMBINED
  v1.1.0 installer). Derived from the proven JOB 2 lineage
  (ClawFactory-Studio/validation/wrapper-builder.ps1) -- COPIED into this repo, not
  shared, because JOB 3C runs from ClawFactory-Secure-Setup and must be
  self-contained (the Studio repo is a read-only reference, not a runtime
  dependency).

  Isolated into its own file for ONE reason: so validation/test-wrapper-render.ps1
  exercises the EXACT logic the driver arms and gates on -- not a copy that can
  drift. The JOB 2 origin of this pattern was cfv-149 (Studio close-out 8c0204d),
  which lost 100% of its evidence because the probe command was assembled as a
  multi-line string concatenation INSIDE an @(...) array literal:

      'powershell ... job-probe.ps1 ' +
        "-CombinedExe ... " +
        "-LicenseKey $LicenseKey ... > C:\cfv\job3-out.txt 2>&1",

  PowerShell parses each physical line there as a SEPARATE array element (6, not
  4) -- a silent, syntactically valid misparse. So wrapper.cmd ran the probe with
  no redirect (output lost to the session console) and ran "-LicenseKey ... >
  job3-out.txt 2>&1" as a standalone command whose "'-LicenseKey' is not
  recognized" error was the only thing captured. The lesson: build the command as
  ONE explicitly-joined string, then place it as a single array element.
#>

# Build the 4 lines of wrapper.cmd. The probe argument string is joined FIRST,
# then composed into a single command line WITH its redirect -- never a
# multi-line concat inside the array literal.
#
# JOB 3 delta vs JOB 2: the probe installs ONE combined installer, so it takes a
# single -CombinedExe (not separate -StudioExe / -SecureExe).
function Build-Job3CmdLines {
    param(
        [Parameter(Mandatory)][string]$SeedEnc,
        [string]$LicenseKey    = 'CF-TEST-TEST-TEST-TEST',
        [string]$SeedKeyTarget = 'ClawFactory/AnthropicApiKey',
        [string]$ProbeOut      = 'C:\cfv\job3-out.txt'
    )
    $probeArgs = @(
        '-NoProfile','-ExecutionPolicy','Bypass',
        '-File','C:\cfv\job3-probe.ps1',
        '-CombinedExe','C:\cfv\combined-setup.exe',
        '-LicenseKey',$LicenseKey,
        '-SeedKeyTarget',$SeedKeyTarget
    ) -join ' '
    # Command AND redirect on ONE physical line -- this is the whole fix.
    $probeLine = "powershell $probeArgs > $ProbeOut 2>&1"
    $lines = @(
        '@echo off',
        "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $SeedEnc",
        $probeLine,
        'echo JOB3_DONE > C:\cfv\JOB3_DONE.txt'
    )
    return ,$lines   # unary comma: hand back the array itself, do not unroll it
}

# Evidence-before-teardown predicate. TRUE iff at least one retrieved channel
# carries the producer sentinel JOB3_PROBE_COMPLETE AND is above a plausible size
# floor. Floor default 512 B: well above cfv-149's 102-byte dead bundle (~5x), and
# below any real probe run, which always emits header+identity+baseline+section
# output (>~1 KB even for the earliest FEASIBILITY_FAIL). The sentinel is the
# primary signal (the probe only writes it via its Finish path); the floor is a
# second guard against a truncated/corrupt sentinel-only fragment.
function Test-Job3Evidence {
    param([string[]]$Files, [int]$FloorBytes = 512)
    foreach ($f in $Files) {
        if ($f -and (Test-Path $f)) {
            if ((Get-Item $f).Length -ge $FloorBytes -and (Get-Content $f -Raw) -match 'JOB3_PROBE_COMPLETE') {
                return $true
            }
        }
    }
    return $false
}
