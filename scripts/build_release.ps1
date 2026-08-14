<#
Produces a release-ready, signed ClawFactory installer:
  1. Runs seven pre-build gates (SOUL, bundle, Studio, version, persona,
     workspace SOUL, rootfs). Each fails the build on drift; none auto-correct.
  2. Compiles ClawFactory-Secure-Setup.iss with Inno Setup (ISCC.exe)
  3. Stamps the compiled bytes so sign_installer.ps1 will accept them
  4. Signs Output\ClawFactory-Secure-Setup.exe via scripts\sign_installer.ps1

This is the build command, not merely the release one. ISCC.exe on its own still
compiles a perfectly good local dev build; that output simply cannot be signed,
because sign_installer.ps1 refuses anything this script did not stamp. That is
the whole point of the stamp: unsigned dev compiles stay easy, and the route
that reaches a customer is the one that passed the gates.
#>

[CmdletBinding()]
param(
    [string]$IsccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    # No default here on purpose; see the resolution below.
    [string]$RepoRoot
)

$ErrorActionPreference = "Stop"

# $RepoRoot used to default to (Split-Path -Parent $PSScriptRoot) in the param
# block. That is fine when the script is invoked from an existing session with &
# or dot-sourcing, which is the only way it has ever been run here, but it is
# broken under `powershell.exe -File`: with [CmdletBinding()] present, parameter
# defaults are evaluated at a point where $PSScriptRoot is still EMPTY, so
# Split-Path threw "Cannot bind argument to parameter 'Path'" and the script died
# before the first gate. Isolated to that single variable on 2026-08-05: the same
# param block without [CmdletBinding()] resolves correctly under -File, and the
# same script with it fails under -File whether or not arguments are passed.
# $PSScriptRoot IS populated by the time the body runs, so resolve it here.
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
if (-not $RepoRoot) { Write-Error "build_release.ps1: could not resolve the repo root; pass -RepoRoot explicitly."; exit 1 }

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
# The digest below is NOT computed from the file in resources\. It is recorded
# here by hand from a build whose contents were checked, and drift fails the
# build; it is never auto-corrected, for the same reason the SOUL pin above is
# not.
#
# Repinned 2026-08-05 for v1.2.0. The previous pin, d5ff8370..., covered the
# artefact built from Studio @9d62ad0 and validated on cfv-152. That artefact had
# gone STALE rather than merely old: Studio @6105c53 and @14b6422 added the three
# panels the agent-side guards need a front end for, and none of them were in it.
# Shipping it would have paired a working send broker with a Studio that has no
# approval card, which is a broken product rather than an out-of-date asset.
#
# The value below is the artefact built from Studio @14b6422 (main), signed by
# the same Azure Trusted Signing cert. Before pinning it, its app.asar was
# extracted from the compiled NSIS payload and searched for twelve markers drawn
# from the three new panels (/approvals/smtp, Email settings, smtp.example.com,
# Currently sending as, send:approve, send:credential, send:deny, send:list,
# Recently deleted, quarantine:list, quarantine:restore, clawfactory-sendctl).
# All twelve are present in this artefact and absent from the d5ff8370 one, so
# the search discriminates rather than merely matching. See
# docs/session_reports/2026-08-05_first_gated_build_closeout.md.
#
# Repinned 2026-08-13 for the Studio panel smoke test, from Studio @14b6422 to
# the build carrying the SMTP-save parse fix. b701bfb7 could not save an SMTP
# credential at all: invokeEngineWithInput wrapped a two-statement expression in
# the PowerShell grouping operator ( ), which takes one pipeline, so the script
# died at PARSE time and surfaced as "the send service did not respond". The fix
# is the subexpression operator $( ).
#
# Verified before pinning, from the compiled signed installer rather than from
# source: all twelve panel markers above are still present (so the fix dropped
# nothing), and "-InputObject $(" is present in this artefact and ABSENT from
# b701bfb7, while "-InputObject (" is present in both because invokeEngine
# legitimately uses grouping and was not touched. So the search discriminates.
# Positive control 'Workspace' in both, negative sentinel in neither.
#
# RESOLVED 2026-08-14: the filename now carries the version again. It had been
# reused for three distinct payloads, because electron-builder interpolates
# ${version} from desktop/package.json and that had sat at 1.1.0 across two
# rebuilds. Bumping Studio to 1.2.0 fixes the name, the header the user sees and
# the package metadata in one move, since all three read the same field. The
# digest below remains the authority; the name is now merely honest as well.
#
# Repinned 2026-08-14 for Guard 3 and the five smoke-test polish items: the new
# Web access panel, expired approval requests, the full attachment hash, the real
# version in the header, and the PolyForm footer.
$studioName   = 'ClawFactory-Studio-Setup-1.2.0.exe'
$studioPinned = '540bb30b6f163ae2fb3b381d4491e5b6a25b2973add7d69615fb078a8b156fb9'
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

# --- Pre-build gate: the persona and the COMPOSED workspace SOUL -------------
# v1 makes the agent's injected SOUL a build-time constant: factory safety rules
# plus a fixed persona, in a fixed order. Two literals in setup.ps1 cover it, and
# both are checked here for the same reason the SOUL pin is. The composed digest
# is the one that matters, because that is the file the agent actually reads and
# the launch gate actually enforces.
#
# The composition below MUST stay byte-identical to the one in
# resources/freeze-injected-soul.sh. It is deliberately trivial (two constant
# strings around two file bodies) to keep that surface small, and a drift between
# the two fails the INSTALL loudly as well, because the script compares its own
# composed output against the digest passed to it.
$personaFile = Join-Path $RepoRoot "resources\persona.md"
if (-not (Test-Path $personaFile)) { Fail "resources/persona.md not found" }
$personaActual = (Get-FileHash -LiteralPath $personaFile -Algorithm SHA256).Hash.ToLower()
$pm = [regex]::Match($setupText, "\`$expectedPersonaHash\s*=\s*'([a-f0-9]{64})'")
if (-not $pm.Success) { Fail "setup.ps1 does not carry an `$expectedPersonaHash literal." }
if ($pm.Groups[1].Value -ne $personaActual) {
    Fail ("Persona pin drift: setup.ps1 pins $($pm.Groups[1].Value) but resources/persona.md hashes to " +
          "$personaActual. If the persona changed on purpose, update BOTH `$expectedPersonaHash and " +
          "`$expectedWorkspaceSoulHash in setup.ps1 and rebuild.")
}

Write-Host "Persona pin OK: $personaActual"

$hdr = "<!--`n" +
       "  CLAWFACTORY -- HARD SAFETY BOUNDARIES (the block below, before the persona).`n" +
       "  This file is root-owned and IMMUTABLE (chattr +i): the agent cannot modify,`n" +
       "  chmod, or delete it. A turn is REFUSED in code at launch if this file is`n" +
       "  tampered with. The boundaries below override everything that follows.`n" +
       "-->`n`n"
$sep = "`n---`n<!-- CLAWFACTORY: the text below is fixed at build time in v1. -->`n`n"
$enc = New-Object System.Text.UTF8Encoding($false)
$composed = New-Object System.Collections.Generic.List[byte]
$composed.AddRange($enc.GetBytes($hdr))
$composed.AddRange([IO.File]::ReadAllBytes($soulFile))
$composed.AddRange($enc.GetBytes($sep))
$composed.AddRange([IO.File]::ReadAllBytes($personaFile))
$sha = [System.Security.Cryptography.SHA256]::Create()
$composedHash = ([BitConverter]::ToString($sha.ComputeHash($composed.ToArray())) -replace '-','').ToLower()
$sha.Dispose()
$wm = [regex]::Match($setupText, "\`$expectedWorkspaceSoulHash\s*=\s*'([a-f0-9]{64})'")
if (-not $wm.Success) { Fail "setup.ps1 does not carry an `$expectedWorkspaceSoulHash literal." }
if ($wm.Groups[1].Value -ne $composedHash) {
    Fail ("Workspace SOUL pin drift: setup.ps1 pins $($wm.Groups[1].Value) but the composed file " +
          "(header + safety-rules.md + separator + persona.md) hashes to $composedHash. " +
          "Update `$expectedWorkspaceSoulHash to $composedHash and rebuild. If you did not change " +
          "either resource, check their line endings: .gitattributes pins both to eol=lf.")
}
Write-Host "Workspace SOUL pin OK: $composedHash ($($composed.Count) bytes composed)"

# --- Pre-build gate: the bundled Ubuntu rootfs must be the IDENTIFIED one -----
# resources\ubuntu-rootfs.tar.gz is 341 MB and gitignored, so like the Studio
# payload above, git cannot tell you whether the right bytes are sitting there.
# It is the higher risk of the two: every structural control the product sells
# runs INSIDE this filesystem, so a substitution here is underneath the nftables
# chain, both root brokers, the credential modes and the turn gate at once.
#
# Until 2026-08-05 it had no recorded source and no digest anywhere in the repo.
# It has now been identified as a stock, unmodified Canonical image and the
# digest below is UPSTREAM'S published value, not one computed from the file in
# resources\. See the setup.ps1 comment at the pin literal for the full
# provenance block (source URL, date, and what was checked).
#
#   Ubuntu 22.04.5 LTS (jammy) amd64, image built 2025-03-18
#   https://cloud-images.ubuntu.com/wsl/jammy/20250318/ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz
#   published in that directory's SHA256SUMS, retrieved 2026-08-05
#
# Fails on drift, never auto-corrects, same as every gate above.
$rootfsName   = 'ubuntu-rootfs.tar.gz'
$rootfsFile   = Join-Path $RepoRoot "resources\$rootfsName"
if (-not (Test-Path $rootfsFile)) {
    Fail ("resources\$rootfsName not found. It is gitignored; fetch it from " +
          "https://cloud-images.ubuntu.com/wsl/jammy/20250318/ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz " +
          "before building.")
}
if ($issText -notmatch [regex]::Escape("resources\$rootfsName")) {
    Fail ("ClawFactory-Secure-Setup.iss no longer bundles $rootfsName. Without it the installer " +
          "silently falls back to a network WSL install, which is not the filesystem this build was " +
          "verified against.")
}
# The expected value is read out of setup.ps1 rather than written here, so the
# literal that the INSTALL enforces is the one this gate keeps honest. A second
# copy here would only ever drift from it.
$rm = [regex]::Match($setupText, "\`$expectedRootfsHash\s*=\s*'([a-f0-9]{64})'")   # backtick, see above
if (-not $rm.Success) {
    Fail "setup.ps1 does not carry an `$expectedRootfsHash literal. The rootfs pin must be baked in at build time."
}
$rootfsPinned = $rm.Groups[1].Value
$rootfsActual = (Get-FileHash -LiteralPath $rootfsFile -Algorithm SHA256).Hash.ToLower()
if ($rootfsActual -ne $rootfsPinned) {
    Fail ("Rootfs drift: resources\$rootfsName hashes to $rootfsActual but setup.ps1 pins $rootfsPinned. " +
          "Refusing to embed an unidentified 341 MB filesystem. If the rootfs was replaced on purpose, " +
          "check the new file against the publisher's own SHA256SUMS, record the source URL and date in " +
          "the `$expectedRootfsHash comment in setup.ps1, and update the literal to $rootfsActual.")
}
Write-Host "Rootfs pin OK: $rootfsPinned"

Write-Host "Compiling installer with Inno Setup..."
& $IsccPath $issPath
if ($LASTEXITCODE -ne 0) {
    Fail "ISCC.exe compile failed (exit $LASTEXITCODE)."
}

$installerPath = Join-Path $RepoRoot "Output\ClawFactory-Secure-Setup.exe"
if (-not (Test-Path $installerPath)) {
    Fail "Expected compiled installer not found at $installerPath"
}

# --- Build stamp: the thing sign_installer.ps1 refuses to sign without --------
# Every gate above was advisory until this existed. `ISCC.exe` invoked directly
# followed by the signer produced a release-grade signed binary that had passed
# none of them, and that two-line route was the one the README taught first.
#
# The stamp is bound to the DIGEST of the unsigned bytes, not merely present, so
# a fresh direct compile cannot inherit an older stamp. It is worth being precise
# about why that holds: an Inno compile over identical inputs is byte-for-byte
# deterministic (measured 2026-08-05), so a stale stamp matches a direct compile
# only when the inputs were identical to a build that already passed the gates,
# which is the case where the gates would have passed anyway. Any input that
# would have failed a gate changes the compiled bytes and orphans the stamp.
#
# What this is NOT: a defence against anyone who can run the signer. The stamp is
# a file, and whoever can invoke sign_installer.ps1 can write one. That is
# accepted. The threat being addressed is a tired founder taking a documented
# shortcut at 2am, not an adversary with local execution. This control is
# ADVISORY against an attacker and STRUCTURAL against process drift, and it
# should never be described as more than that.
$unsignedHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLower()
$stampPath    = "$installerPath.buildstamp"
$stamp = [ordered]@{
    producer      = 'scripts/build_release.ps1'
    version       = $issVer.Groups[1].Value
    unsignedSha256 = $unsignedHash
    unsignedBytes = (Get-Item -LiteralPath $installerPath).Length
    gatesPassed   = @('soul', 'bundle', 'studio', 'version', 'persona', 'workspace-soul', 'rootfs')
    stampedUtc    = (Get-Date).ToUniversalTime().ToString('o')
}
# BOM-less UTF-8 on purpose; see the same note in sign_installer.ps1. PS 5.1's
# Set-Content -Encoding utf8 writes a BOM and non-PowerShell readers choke on it.
[System.IO.File]::WriteAllText($stampPath, ($stamp | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Build stamp written: $stampPath"
Write-Host "  unsigned sha256: $unsignedHash"

Write-Host "Signing compiled installer..."
$signScript = Join-Path $RepoRoot "scripts\sign_installer.ps1"
& $signScript -InstallerPath $installerPath
if ($LASTEXITCODE -ne 0) {
    Fail "Signing failed. $installerPath is UNSIGNED -- do not upload it to a GitHub Release."
}

Write-Host ""
Write-Host "Release-ready signed installer: $installerPath"
