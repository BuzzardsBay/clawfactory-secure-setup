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
$m = [regex]::Match($setupText, "\$expectedSoulHash\s*=\s*'([a-f0-9]{64})'")
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
$reqMatch = [regex]::Match($setupText, "(?s)\$required\s*=\s*@\((.*?)\)")
if (-not $reqMatch.Success) { Fail "could not read Step-Preflight's `$required list from setup.ps1" }
$required = [regex]::Matches($reqMatch.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
$issText  = Get-Content -Raw -LiteralPath $issPath
$notBundled = @($required | Where-Object { $issText -notmatch [regex]::Escape("resources\$_") })
if ($notBundled.Count -gt 0) {
    Fail ("These resources are required by Step-Preflight but are NOT in the .iss [Files] section: " +
          ($notBundled -join ', ') + ". A build with this gap installs with missing security controls.")
}
Write-Host ("Bundle check OK: all {0} preflight resources are in [Files]." -f $required.Count)

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
