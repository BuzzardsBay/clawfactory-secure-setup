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
