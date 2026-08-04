<#
Produces a release-ready, signed ClawFactory installer:
  1. Compiles ClawFactory-Secure-Setup.iss with Inno Setup (ISCC.exe)
  2. Signs the resulting Output\ClawFactory-Secure-Setup.exe via scripts\sign_installer.ps1

This is the only path that should feed a GitHub Release. For a quick local dev
build that doesn't need a valid signature, compile with ISCC.exe directly instead
(see README.md "Building from source").
#>

[CmdletBinding()]
param(
    [string]$IsccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Error "build_release.ps1: $msg"
    exit 1
}

if (-not (Test-Path $IsccPath)) {
    Fail "ISCC.exe not found at $IsccPath"
}

$issPath = Join-Path $RepoRoot "ClawFactory-Secure-Setup.iss"
if (-not (Test-Path $issPath)) {
    Fail "$issPath not found"
}

# --- Pre-build gate: the SOUL pin must be a build-time constant that MATCHES ---
# setup.ps1 carries the expected SHA-256 of resources/safety-rules.md as a
# literal, and refuses to install if the file on disk disagrees. That is what
# makes the pin an integrity control rather than theatre: a pin computed from
# the artefact it certifies certifies nothing.
#
# The literal therefore has to be kept honest at BUILD time, here, and drift has
# to fail the build loudly rather than be auto-corrected -- silently rewriting it
# would just move the self-certification one step earlier.
$soulFile = Join-Path $RepoRoot "resources\safety-rules.md"
if (-not (Test-Path $soulFile)) { Fail "resources/safety-rules.md not found" }
$soulActual = (Get-FileHash -LiteralPath $soulFile -Algorithm SHA256).Hash.ToLower()
$setupText  = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "setup.ps1")
# NOTE the backtick. In a double-quoted PowerShell string "$expectedSoulHash" is
# an EMPTY VARIABLE, not a literal, so the pattern collapsed to one that can never
# match and this gate failed the build unconditionally from the day it was added.
# It failed closed, so nothing shipped past it -- but it also never once compared
# the pin to the file. Verified by execution 2026-08-04; use '\$' or `$, not \$.
$m = [regex]::Match($setupText, "\`$expectedSoulHash\s*=\s*'([a-f0-9]{64})'")
if (-not $m.Success) {
    Fail "setup.ps1 does not carry an `$expectedSoulHash literal. The SOUL pin must be baked in at build time."
}
$soulPinned = $m.Groups[1].Value
if ($soulPinned -ne $soulActual) {
    Fail ("SOUL pin drift: setup.ps1 pins $soulPinned but resources/safety-rules.md hashes to $soulActual. " +
          "If the safety rules changed on purpose, update the `$expectedSoulHash literal in setup.ps1 to $soulActual and rebuild.")
}
Write-Host "SOUL pin OK: $soulPinned"

# --- Pre-build gate: every preflight-required resource must be BUNDLED --------
# The two halves of the bug that once shipped an installer with zero security
# controls: Step-Preflight's required list and the .iss [Files] section drifted
# apart, so the step existed and the file did not. Check the pairing here, where
# it is cheap, instead of on a customer's machine.
$reqMatch = [regex]::Match($setupText, "(?s)\`$required\s*=\s*@\((.*?)\)")   # backtick: see above
if (-not $reqMatch.Success) { Fail "could not read Step-Preflight's `$required list from setup.ps1" }
$required = [regex]::Matches($reqMatch.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
$issText  = Get-Content -Raw -LiteralPath $issPath
$notBundled = @($required | Where-Object { $issText -notmatch [regex]::Escape("resources\$_") })
if ($notBundled.Count -gt 0) {
    Fail ("These resources are required by Step-Preflight but are NOT in the .iss [Files] section: " +
          ($notBundled -join ', ') + ". A build with this gap installs with missing security controls.")
}
Write-Host ("Bundle check OK: all {0} preflight resources are in [Files]." -f $required.Count)

# --- Pre-build gate: the embedded Studio installer must be the VALIDATED one ---
# resources\ClawFactory-Studio-Setup-*.exe is gitignored and copied in from the
# Studio repo's release directory at build time, so git cannot tell you whether
# the right binary is sitting there. Both ClawFactory-Secure-Setup.iss and
# .gitignore said it was "verified by sha256 before compile"; that verification
# was real but MANUAL (performed in JOB 3B, recorded as MATCH in
# docs/session_reports/2026-07-21_job3b_combined_installer_closeout.md), and a
# check that lives only in a human's habit is not a check the build has.
#
# The digest below is NOT computed from the file in resources\. It is the value
# recorded in that close-out for the artefact built from Studio @9d62ad0 and
# validated on cfv-152. Drift fails the build; it is never auto-corrected, for
# the same reason the SOUL pin above is not.
$studioName   = 'ClawFactory-Studio-Setup-1.1.0.exe'
$studioPinned = 'd5ff8370943194c2643674ddba98e917ca61865ce127ec424a1cb37c746d45a7'
$studioFile   = Join-Path $RepoRoot "resources\$studioName"
if (-not (Test-Path $studioFile)) {
    Fail ("resources\$studioName not found. It is gitignored; copy it in from the Studio repo's " +
          "release directory before building.")
}
if ($issText -notmatch [regex]::Escape($studioName)) {
    Fail ("ClawFactory-Secure-Setup.iss no longer embeds $studioName. If Studio was rebuilt, update " +
          "BOTH the .iss #define and the `$studioPinned digest in this script.")
}
$studioActual = (Get-FileHash -LiteralPath $studioFile -Algorithm SHA256).Hash.ToLower()
if ($studioActual -ne $studioPinned) {
    Fail ("Studio installer drift: resources\$studioName hashes to $studioActual but this build pins " +
          "$studioPinned. Refusing to embed an unverified 100 MB payload. If Studio was rebuilt on " +
          "purpose, validate the new artefact, record its digest in a close-out, and update " +
          "`$studioPinned here to $studioActual.")
}
Write-Host "Studio pin OK: $studioPinned"

# --- Pre-build gate: the two version literals must agree ----------------------
# .iss MyAppVersion feeds AppVersion, so it is what the customer sees in Apps &
# Features and on the uninstall entry. That makes it the authority.
# setup.ps1's $InstallerVersion follows it. The two drifted for roughly fifteen
# releases (1.0.34 against 1.1.1) because nothing compared them. Same shape as
# the gates above: fail on drift, never auto-correct, because a silent rewrite
# would just hide which one someone forgot to bump.
$issVer = [regex]::Match($issText,   '#define\s+MyAppVersion\s+"([^"]+)"')
$psVer  = [regex]::Match($setupText, "\`$InstallerVersion\s*=\s*'([^']+)'")   # backtick, see above
if (-not $issVer.Success) { Fail "could not read MyAppVersion from ClawFactory-Secure-Setup.iss" }
if (-not $psVer.Success)  { Fail "could not read `$InstallerVersion from setup.ps1" }
if ($issVer.Groups[1].Value -ne $psVer.Groups[1].Value) {
    Fail ("Version drift: .iss MyAppVersion is $($issVer.Groups[1].Value) but setup.ps1 " +
          "`$InstallerVersion is $($psVer.Groups[1].Value). The .iss value is the one the customer " +
          "sees, so set `$InstallerVersion to $($issVer.Groups[1].Value) and rebuild.")
}
Write-Host "Version OK: $($issVer.Groups[1].Value) (.iss and setup.ps1 agree)"

Write-Host "Compiling installer with Inno Setup..."
& $IsccPath $issPath
if ($LASTEXITCODE -ne 0) {
    Fail "ISCC.exe compile failed (exit $LASTEXITCODE)."
}

$installerPath = Join-Path $RepoRoot "Output\ClawFactory-Secure-Setup.exe"
if (-not (Test-Path $installerPath)) {
    Fail "Expected compiled installer not found at $installerPath"
}

Write-Host "Signing compiled installer..."
$signScript = Join-Path $RepoRoot "scripts\sign_installer.ps1"
& $signScript -InstallerPath $installerPath
if ($LASTEXITCODE -ne 0) {
    Fail "Signing failed. $installerPath is UNSIGNED -- do not upload it to a GitHub Release."
}

Write-Host ""
Write-Host "Release-ready signed installer: $installerPath"
