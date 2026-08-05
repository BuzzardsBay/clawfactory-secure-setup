<#
Signs a ClawFactory installer .exe using Azure Artifact Signing (formerly "Trusted
Signing"). Must run as a discrete step AFTER Inno Setup compiles and BEFORE the
resulting .exe is uploaded to a GitHub Release.

Every invocation includes an RFC 3161 timestamp (/tr + /td SHA256). Azure Artifact
Signing leaf certificates are valid for only 3 days and rotate daily -- without a
timestamp, the signature reads as expired within days of shipping.

This script REFUSES to sign a binary that scripts\build_release.ps1 did not just
produce, so that the build gates cannot be skipped by compiling with ISCC.exe and
signing the result. Use -SignWithoutBuildStamp to override in an emergency; it
announces itself loudly in the output and in this file's own reasoning below.

Doc source used to build this script (fetched live, not from training-data
assumptions): https://learn.microsoft.com/en-us/azure/artifact-signing/how-to-signing-integrations
(ms.date 2026-05-14). Package/role names on that page reflect the Trusted Signing
-> Artifact Signing rename; older blog posts / cached docs still reference the old
"Microsoft.Trusted.Signing.Client" / "Trusted Signing Certificate Profile Signer"
names, which no longer match what `az role definition list` returns.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,

    # EMERGENCY ONLY. Signs a binary with no valid build stamp, meaning a binary
    # that may have passed none of build_release.ps1's gates. Named rather than
    # undocumented on purpose: an override that exists but is not written down
    # gets rediscovered as a trick, and a signing path with no override at all
    # gets worked around by editing this script, which is worse than both.
    [switch]$SignWithoutBuildStamp,

    # No defaults here on purpose; see the resolution below.
    [string]$RepoRoot,

    [string]$ToolsDir,

    [string]$TimestampUrl = "http://timestamp.acs.microsoft.com"
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Error "sign_installer.ps1: $msg"
    exit 1
}

# $RepoRoot and $ToolsDir used to default to expressions over $PSScriptRoot in the
# param block. That works when the script is invoked with & or dot-sourced from an
# existing session, which is how it has always been called, but it is broken under
# `powershell.exe -File`: with [CmdletBinding()] present, parameter defaults are
# evaluated while $PSScriptRoot is still EMPTY, so Split-Path throws "Cannot bind
# argument to parameter 'Path'" and the script dies before doing anything. Same
# defect, same diagnosis and same fix as build_release.ps1 on 2026-08-05, which
# left this one latent. $PSScriptRoot IS populated by the time the body runs.
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
if (-not $RepoRoot) { Fail "could not resolve the repo root; pass -RepoRoot explicitly." }
if (-not $ToolsDir) { $ToolsDir = Join-Path $RepoRoot "signing\tools" }

if (-not (Test-Path $InstallerPath)) {
    Fail "Installer not found: $InstallerPath"
}
$InstallerPath = (Resolve-Path $InstallerPath).Path

# ---------------------------------------------------------------------------
# 0. Build-gate enforcement. Refuse anything build_release.ps1 did not stamp.
# ---------------------------------------------------------------------------
# Until 2026-08-05 this script referenced no gate of any kind. It took an
# arbitrary -InstallerPath and signed it, so
#
#     ISCC.exe ClawFactory-Secure-Setup.iss
#     scripts\sign_installer.ps1 -InstallerPath Output\ClawFactory-Secure-Setup.exe
#
# produced a release-grade signed binary that had passed none of the seven build
# gates, and that route was documented in six places including the README.
#
# The stamp is state, and anyone who can run this script can forge one. That is
# accepted rather than solved: the threat here is a tired founder taking a
# documented shortcut under time pressure, not an adversary with local code
# execution. Against an attacker this is ADVISORY. Against process drift it is
# structural, because the shortcut now fails instead of quietly succeeding.
#
# Local dev compiles with ISCC.exe remain entirely legitimate. They simply do not
# produce signable output, which is the correct division: unsigned binaries never
# reach a customer, and the gates are only load-bearing for the ones that do.
$stampPath = "$InstallerPath.buildstamp"
if ($SignWithoutBuildStamp) {
    Write-Host ""
    Write-Host "***************************************************************************"
    Write-Host "*** -SignWithoutBuildStamp: BUILD GATES NOT ENFORCED FOR THIS SIGNATURE ***"
    Write-Host "***************************************************************************"
    Write-Host "This binary is being signed WITHOUT proof that scripts\build_release.ps1"
    Write-Host "produced it. It may not have passed the SOUL, bundle, Studio, version,"
    Write-Host "persona, workspace-SOUL or rootfs gate. Do not publish it as a release"
    Write-Host "unless you know exactly why you reached for this switch."
    Write-Host "  target: $InstallerPath"
    Write-Host ""
} else {
    if (-not (Test-Path -LiteralPath $stampPath)) {
        Fail ("no build stamp at $stampPath, so this binary was not produced by " +
              "scripts\build_release.ps1 and may have passed none of the build gates. Build " +
              "with `"scripts\build_release.ps1`" instead of calling ISCC.exe directly. If you " +
              "genuinely need to re-sign an existing binary, pass -SignWithoutBuildStamp.")
    }
    try {
        $stamp = Get-Content -Raw -LiteralPath $stampPath | ConvertFrom-Json
    } catch {
        Fail "build stamp at $stampPath is unreadable: $($_.Exception.Message)"
    }
    if (-not $stamp.unsignedSha256) {
        Fail "build stamp at $stampPath carries no unsignedSha256 field."
    }
    $actualHash = (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLower()
    if ($actualHash -ne ([string]$stamp.unsignedSha256).ToLower()) {
        Fail ("build stamp mismatch: the stamp covers $($stamp.unsignedSha256) but " +
              "$InstallerPath hashes to $actualHash. The binary changed after it was built, or " +
              "the stamp belongs to a different build. Re-run scripts\build_release.ps1.")
    }
    Write-Host "Build stamp OK: produced by $($stamp.producer) v$($stamp.version) at $($stamp.stampedUtc)"
    Write-Host "  gates passed: $($stamp.gatesPassed -join ', ')"
}

# ---------------------------------------------------------------------------
# 1. Load signing config from .env (repo-root, gitignored -- never committed)
# ---------------------------------------------------------------------------
$envFile = Join-Path $RepoRoot ".env"
if (-not (Test-Path $envFile)) {
    Fail ".env not found at $envFile -- run the signing setup step first (AZURE_SIGNING_* vars required)."
}

$envValues = @{}
foreach ($line in Get-Content $envFile) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
    $idx = $trimmed.IndexOf("=")
    if ($idx -lt 1) { continue }
    $key = $trimmed.Substring(0, $idx).Trim()
    $val = $trimmed.Substring($idx + 1).Trim()
    $envValues[$key] = $val
}

$required = @(
    "AZURE_SIGNING_TENANT_ID", "AZURE_SIGNING_CLIENT_ID", "AZURE_SIGNING_CLIENT_SECRET",
    "AZURE_SIGNING_ENDPOINT", "AZURE_SIGNING_ACCOUNT_NAME", "AZURE_SIGNING_CERT_PROFILE"
)
foreach ($key in $required) {
    if (-not $envValues.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($envValues[$key])) {
        Fail "Missing required $key in .env"
    }
}

# EnvironmentCredential (part of Azure.Identity's DefaultAzureCredential chain, which
# the Artifact Signing dlib uses under the hood) reads these exact standard names --
# NOT the AZURE_SIGNING_* names .env uses for our own bookkeeping. Map explicitly.
$env:AZURE_TENANT_ID     = $envValues["AZURE_SIGNING_TENANT_ID"]
$env:AZURE_CLIENT_ID     = $envValues["AZURE_SIGNING_CLIENT_ID"]
$env:AZURE_CLIENT_SECRET = $envValues["AZURE_SIGNING_CLIENT_SECRET"]

# ---------------------------------------------------------------------------
# 2. Generate real metadata.json from the committed template + .env values
# ---------------------------------------------------------------------------
$templatePath = Join-Path $RepoRoot "signing\metadata.json.template"
if (-not (Test-Path $templatePath)) {
    Fail "signing\metadata.json.template not found."
}
$metadata = Get-Content $templatePath -Raw | ConvertFrom-Json
$metadata.Endpoint                = $envValues["AZURE_SIGNING_ENDPOINT"]
$metadata.CodeSigningAccountName  = $envValues["AZURE_SIGNING_ACCOUNT_NAME"]
$metadata.CertificateProfileName  = $envValues["AZURE_SIGNING_CERT_PROFILE"]

$metadataPath = Join-Path $RepoRoot "signing\metadata.json"
$metadataJson = $metadata | ConvertTo-Json -Depth 5
# Set-Content -Encoding utf8 writes a BOM in Windows PowerShell 5.1, which the
# signing dlib's JSON parser rejects ("'0xEF' is an invalid start of a value").
# Write BOM-less UTF-8 explicitly instead.
[System.IO.File]::WriteAllText($metadataPath, $metadataJson, (New-Object System.Text.UTF8Encoding($false)))

# ---------------------------------------------------------------------------
# 3. Ensure signtool.exe (Windows SDK Build Tools) and the Artifact Signing
#    dlib are present locally. Fetched via NuGet into a gitignored tools dir
#    so paths are deterministic and the script is headless/CI-safe (no winget
#    dependency). Packages per Task 0 doc pull:
#      - Microsoft.Windows.SDK.BuildTools  (signtool.exe, >= 10.0.2261.755)
#      - Microsoft.ArtifactSigning.Client  (Azure.CodeSigning.Dlib.dll)
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

$nugetExe = Join-Path $ToolsDir "nuget.exe"
if (-not (Test-Path $nugetExe)) {
    Write-Host "Downloading nuget.exe..."
    Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $nugetExe
}

function Get-OrInstallNugetPackage($packageId) {
    $existing = Get-ChildItem -Path $ToolsDir -Directory -Filter "$packageId*" -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "Installing NuGet package $packageId..."
        & $nugetExe install $packageId -x -OutputDirectory $ToolsDir -NonInteractive | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Fail "nuget.exe install $packageId failed (exit $LASTEXITCODE)."
        }
    }
}

Get-OrInstallNugetPackage "Microsoft.Windows.SDK.BuildTools"
Get-OrInstallNugetPackage "Microsoft.ArtifactSigning.Client"

$signtoolPath = Get-ChildItem -Path $ToolsDir -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "\\x64\\" } |
    Sort-Object FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $signtoolPath) {
    Fail "Could not locate x64 signtool.exe under $ToolsDir after NuGet install."
}

$dlibPath = Get-ChildItem -Path $ToolsDir -Recurse -Filter "Azure.CodeSigning.Dlib.dll" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "x64" } |
    Sort-Object FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $dlibPath) {
    Fail "Could not locate x64 Azure.CodeSigning.Dlib.dll under $ToolsDir after NuGet install."
}

# ---------------------------------------------------------------------------
# 4. Sign, with mandatory RFC 3161 timestamp. Never allow this to succeed
#    without /tr + /td -- an unsigned-equivalent (untimestamped) installer
#    must never be treated as a successful build.
# ---------------------------------------------------------------------------
Write-Host "Signing $InstallerPath"
Write-Host "  signtool: $signtoolPath"
Write-Host "  dlib:     $dlibPath"
Write-Host "  metadata: $metadataPath"

& $signtoolPath sign /v /debug /fd SHA256 /tr $TimestampUrl /td SHA256 /dlib $dlibPath /dmdf $metadataPath $InstallerPath

if ($LASTEXITCODE -ne 0) {
    Fail "signtool sign failed (exit $LASTEXITCODE). Installer is UNSIGNED -- do not publish it."
}

# Consume the stamp. Signing appends to the file, so the digest the stamp covers
# is no longer the digest on disk and the stamp is now stale by construction.
# Leaving it would let a later direct compile land next to a stamp that no longer
# describes anything, which is the one way this check could quietly weaken.
if (Test-Path -LiteralPath $stampPath) {
    Remove-Item -LiteralPath $stampPath -Force
    Write-Host "Build stamp consumed: $stampPath"
}

Write-Host "Signed successfully: $InstallerPath"
