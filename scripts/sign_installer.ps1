<#
Signs a ClawFactory installer .exe using Azure Artifact Signing (formerly "Trusted
Signing"). Must run as a discrete step AFTER Inno Setup compiles and BEFORE the
resulting .exe is uploaded to a GitHub Release.

Every invocation includes an RFC 3161 timestamp (/tr + /td SHA256). Azure Artifact
Signing leaf certificates are valid for only 3 days and rotate daily -- without a
timestamp, the signature reads as expired within days of shipping.

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

    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [string]$ToolsDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "signing\tools"),

    [string]$TimestampUrl = "http://timestamp.acs.microsoft.com"
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Error "sign_installer.ps1: $msg"
    exit 1
}

if (-not (Test-Path $InstallerPath)) {
    Fail "Installer not found: $InstallerPath"
}
$InstallerPath = (Resolve-Path $InstallerPath).Path

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

Write-Host "Signed successfully: $InstallerPath"
