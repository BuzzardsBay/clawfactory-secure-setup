# Azure Artifact Signing wired into ClawFactory release build

**Date:** 2026-07-06
**Repo:** `C:\Users\bmcki\ClawFactory-Secure-Setup`
**Result:** PASS -- signing wired, real installer signed, both verification methods report Valid.

## Doc version used

Fetched live (not from training-data assumptions), since package/flag names have
changed across versions:

- **URL:** https://learn.microsoft.com/en-us/azure/artifact-signing/how-to-signing-integrations
- **ms.date:** 2026-05-14 (fetched 2026-07-06)

The product has been renamed **Trusted Signing -> Artifact Signing**. This mattered
in practice: the original task brief said to assign the "Trusted Signing Certificate
Profile Signer" role -- that name no longer exists. `az role definition list`
confirmed the live role name is **`Artifact Signing Certificate Profile Signer`**,
which is what was actually assigned (see Task 1 below).

Key facts confirmed from the live doc, not memory:

| Item | Value |
|---|---|
| SignTool source | `Microsoft.Windows.SDK.BuildTools` NuGet package (signtool.exe >= 10.0.2261.755) |
| Dlib source | `Microsoft.ArtifactSigning.Client` NuGet package -> `Azure.CodeSigning.Dlib.dll` |
| Runtime dependency | .NET 8.0 Runtime (confirmed present: 8.0.23) |
| Timestamp authority | `http://timestamp.acs.microsoft.com` |
| Metadata (`/dmdf`) schema | `Endpoint`, `CodeSigningAccountName`, `CertificateProfileName`, `CorrelationId` (optional), `ExcludeCredentials` (optional) |
| Auth mechanism | `DefaultAzureCredential` chain; service-principal auth goes through `EnvironmentCredential`, which reads the **standard** `AZURE_TENANT_ID` / `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` env vars -- not arbitrary names |

## Task 0 -- Comprehension gate

- `az account show` confirmed authenticated; cross-checked with a direct
  `az rest` call to `management.azure.com` per standing lesson (cached CLI
  profile state can lie) -- live state: subscription `43010359-...`, state
  `Enabled`, quota `PayAsYouGo_2014-09-01`.
- Read `ClawFactory-Secure-Setup.iss` and `README.md`. There is **no existing
  automated build/release script** in this repo -- the documented build process
  (README "Building from source") is a single manual `ISCC.exe` invocation, and
  GitHub Releases (per `CLAUDE_ClawFactory.md` section 20.5) are cut manually.
  The `.iss` file has an unused, commented-out Inno-native `SignTool=signtool`
  directive (line 31) intended for IDE-configured signing -- left untouched, since
  the brief explicitly asked for a discrete post-compile script step instead of
  Inno's built-in signing hook.
- **Endpoint verification (Task 0.5):** queried the live resource directly --
  `az rest ... codeSigningAccounts/clawfactory-signing` returned
  `"accountUri": "https://eus.codesigning.azure.net/"` -- an exact match for the
  value given in the brief. No mismatch, proceeded without stopping.

## Task 1 -- Service principal + role assignment

Commands run (secrets redacted):

```
az ad app create --display-name "clawfactory-signing-sp"
  -> appId b9bb9008-2d68-47df-8665-9aae0fe2dce2

az ad sp create --id b9bb9008-2d68-47df-8665-9aae0fe2dce2
  -> SP object id e9b0c44f-c47b-4592-b1c4-72b89d9c213a

az role assignment create \
  --assignee-object-id e9b0c44f-c47b-4592-b1c4-72b89d9c213a \
  --assignee-principal-type ServicePrincipal \
  --role "Artifact Signing Certificate Profile Signer" \
  --scope /subscriptions/43010359-5b4c-4d16-af11-10f6544b2978/resourceGroups/clawfactory-signing/providers/Microsoft.CodeSigning/codeSigningAccounts/clawfactory-signing
  -> role assignment 53d4d3a1-86e4-4fd9-ae8a-38cd162628bd, succeeded

az ad app credential reset --id b9bb9008-2d68-47df-8665-9aae0fe2dce2 --append --query password -o tsv
  -> secret generated, piped directly into .env, never printed to any terminal output or log
```

**Environment quirk hit and fixed:** the first two `az role assignment create`
attempts failed with a generic `(MissingSubscription)` error. `--debug` showed
the real cause: Git Bash's MSYS path-conversion layer was rewriting
`/subscriptions/...` into `C:/Program Files/Git/subscriptions/...` before the
argument reached `az`. Not a permissions or scope problem. Fix: set
`MSYS_NO_PATHCONV=1` before any `az` command that takes a `/subscriptions/...`
scope argument in this shell. Saved to memory as a recurring-relevant lesson for
any future Azure CLI work in this environment.

Secret was piped straight from `az ad app credential reset` into an appended
`.env` block inside a single shell command -- it was never assigned to a
separately-echoed variable and never appears in this report or any terminal
output shown to the user.

## Task 2 -- Local credential + config storage

- `.env` (repo root, pre-existing gitignore pattern, confirmed via
  `git check-ignore -v .env`) now holds: `AZURE_SIGNING_TENANT_ID`,
  `AZURE_SIGNING_CLIENT_ID`, `AZURE_SIGNING_CLIENT_SECRET`,
  `AZURE_SIGNING_ENDPOINT=https://eus.codesigning.azure.net/`,
  `AZURE_SIGNING_ACCOUNT_NAME=clawfactory-signing`,
  `AZURE_SIGNING_CERT_PROFILE=clawfactory-cert`.
- New `signing/metadata.json.template` committed with placeholder-safe values
  (account/profile names are not secret, so the template ships the real
  account/profile/endpoint but no credential). The real per-build
  `signing/metadata.json` is generated at build time by `sign_installer.ps1`
  and is gitignored (`.gitignore` updated: added `signing/metadata.json` and
  `signing/tools/`, the latter holding the NuGet-fetched signtool/dlib binaries).

## Task 3 -- `scripts/sign_installer.ps1`

New file. Fetches `Microsoft.Windows.SDK.BuildTools` and
`Microsoft.ArtifactSigning.Client` via `nuget.exe` into a gitignored
`signing/tools/` (deterministic, headless-safe -- no dependency on winget's
unpredictable install path), locates `signtool.exe` (x64) and
`Azure.CodeSigning.Dlib.dll` (x64) by search rather than a hardcoded internal
package path, generates real `metadata.json` from `.env` + the template, maps
`.env`'s `AZURE_SIGNING_*` names onto the standard `AZURE_TENANT_ID` /
`AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` env vars that `EnvironmentCredential`
actually reads, then signs with:

```
signtool.exe sign /v /debug /fd SHA256 /tr http://timestamp.acs.microsoft.com /td SHA256 /dlib <dlib> /dmdf <metadata.json> <installer>
```

`/tr` + `/td SHA256` (the RFC 3161 timestamp) are present, unconditional, in the
one and only sign invocation in the script -- verified present in the source
and confirmed present in the actual verify output below. Non-zero exit anywhere
in the chain (`Fail` helper) aborts with a clear message; the script never
reports success while leaving an unsigned/untimestamped file behind.

**Bug hit and fixed during Task 5:** the first real run failed with a generic
signtool error (`SignTool Error: An unexpected internal error has occurred`,
`SignerSign() failed`). `/debug` output showed the actual cause: a
`System.Text.Json.JsonException: '0xEF' is an invalid start of a value`.
Windows PowerShell 5.1's `Set-Content -Encoding utf8` writes a UTF-8 BOM, and
the signing dlib's JSON parser rejects the leading BOM byte. Fixed by writing
`metadata.json` via `[System.IO.File]::WriteAllText(..., New-Object
System.Text.UTF8Encoding($false))` instead. This is exactly the kind of
misleadingly-generic failure the brief warned about for a region mismatch --
in this case the generic error was actually a BOM/encoding bug, not Azure-side
at all.

## Task 4 -- Wired into build process

No automated build/release script existed before this task (see Task 0). Two
files created/edited to insert signing as a discrete post-compile,
pre-release step:

- **Created** `scripts/build_release.ps1`: runs `ISCC.exe` against
  `ClawFactory-Secure-Setup.iss`, then calls `scripts/sign_installer.ps1` on
  the resulting `Output\ClawFactory-Secure-Setup.exe`. This is the new
  canonical path to a release-ready installer.
- **Edited** `README.md` "Building from source" section: added a "Producing a
  signed release build" subsection pointing at `build_release.ps1`, and
  updated the stale "Known limitations" bullet (previously said signing was
  "in progress" under the old "Azure Trusted Signing" name) to reflect that
  signing is now wired and working.

Install-step ordering and hardened-install logic (`setup.ps1`,
`ClawFactory-Secure-Setup.iss` `[Files]`/`[Run]` sections) were not touched.

## Task 5 -- Verification (full output)

Ran `scripts\build_release.ps1` for real: compiled v1.0.37 with `ISCC.exe`,
signed the output.

**`signtool verify /pa /v`:**

```
Verifying: ...\Output\ClawFactory-Secure-Setup.exe
Signature Index: 0 (Primary Signature)
Hash of file (sha256): 6560B201E938751D9079A44D99C0E377FC3CA172420A4C41006B0117F09FC190

Signing Certificate Chain:
    Issued to: Microsoft Identity Verification Root Certificate Authority 2020
    ...
        Issued to: Microsoft ID Verified Code Signing PCA 2021
        ...
            Issued to: Microsoft ID Verified CS EOC CA 04
            ...
                Issued to: Bret Mckinney
                Issued by: Microsoft ID Verified CS EOC CA 04
                Expires:   Thu Jul 09 11:33:03 2026
                SHA1 hash: CFE69933BABDDCF0B1DFA2680A60C1049F557F53

The signature is timestamped: Mon Jul 06 12:10:45 2026

Timestamp Verified by:
    Issued to: Microsoft Identity Verification Root Certificate Authority 2020
    ...
        Issued to: Microsoft Public RSA Timestamping CA 2020
        ...
            Issued to: Microsoft Public RSA Time Stamping Authority
            Expires:   Thu Oct 22 14:46:51 2026

Successfully verified: ...\Output\ClawFactory-Secure-Setup.exe
Number of files successfully Verified: 1
Number of warnings: 0
Number of errors: 0
```

Note the leaf cert's 3-day validity window (Jul 6 -> Jul 9 2026) -- exactly the
rotation cadence the brief warned about, which is why the timestamp above is
what keeps this signature valid indefinitely rather than expiring Jul 9.

**`Get-AuthenticodeSignature`:**

```
Status                 : Valid
StatusMessage          : Signature verified.
SignerCertificate      : [Subject] CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US
                          [Issuer]  CN=Microsoft ID Verified CS EOC CA 04, O=Microsoft Corporation, C=US
                          [Not Before] 06-Jul-26 11:33:03 AM
                          [Not After]  09-Jul-26 11:33:03 AM
                          [Thumbprint] CFE69933BABDDCF0B1DFA2680A60C1049F557F53
TimeStamperCertificate : [Subject] CN=Microsoft Public RSA Time Stamping Authority, ...
                          [Issuer]  CN=Microsoft Public RSA Timestamping CA 2020, O=Microsoft Corporation, C=US
                          [Not Before] 23-Oct-25 2:46:51 PM
                          [Not After]  22-Oct-26 2:46:51 PM
                          [Thumbprint] FF73F729152A9059805E5E0832449D996EF60411
```

`TimeStamperCertificate` is populated (not null) -- timestamp confirmed present
and validated by both tools.

**Explorer Properties -> Digital Signatures tab:** not captured -- validation
was kept fully headless/scripted per standing guidance to avoid computer-use
or remote-desktop interaction with the local machine. The `signtool verify /pa
/v` output above (chain to root, "Successfully verified", 0 errors) and the
`Get-AuthenticodeSignature` output (`Status: Valid`, signer "Bret Mckinney")
are the full substitute the brief allows for when a screenshot isn't taken.

## Guardrail recap

- RFC 3161 timestamp flag (`/tr` + `/td SHA256`) present in the one sign
  invocation in the codebase, unconditionally -- confirmed present in both
  source and the actual verify output above.
- No secrets committed. No secret ever printed to a log, this report, or
  visible terminal output -- generated via `az ad app credential reset
  --query password -o tsv` piped directly into `.env` inside one shell
  command.
- `.env`, `signing/metadata.json` (real), and `signing/tools/` (downloaded
  binaries) all confirmed gitignored before staging anything.
- Install-step ordering / hardened-install logic untouched.
- No orchestrator/loop repo touched (this is ClawFactory only).
