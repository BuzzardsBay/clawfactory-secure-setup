# First Gated Build, close-out

**Date:** 2026-08-05
**Track:** v1 fast-security-harness, release engineering
**Dispatch card:** #213
**Base:** `000d4d9` (persona constant complete), card #212 done
**Commits this session:** `39aea30`, `8e637fd`, plus this close-out
**Outcome:** signed v1.2.0 installer produced, all five gates green, artifact verified. **Not tagged, not released, not published, not installed.**

---

## 0. Headline

`Output\ClawFactory-Secure-Setup.exe`

| Fact | Value |
| --- | --- |
| sha256 | `54f9a9e05e7f2f05571365dbb9bb30f3e2b724f260345587e9eba69855968d37` |
| bytes | 440,578,512 |
| ProductVersion reported by the binary | `1.2.0` |
| Authenticode | `Valid`, "Signature verified." |
| Built | 2026-08-05 10:56:51 |

**That digest is the artifact the next session validates.**

This is the first build in the product's history to reach `ISCC.exe` with the
integrity gates in force. Every prior release was produced by the ungated script at
`e966409` or by invoking `ISCC.exe` directly. All five gates passed, and two of them
were exercised in the failing direction as well, so "green" here means observed
rather than assumed.

The build did **not** fail on the `.iss` or the resource set. That was the expected
risk going in, and it did not materialise: the preflight-to-`[Files]` pairing gate had
already been fixed in the audit session, and it held. The failures this session
produced were elsewhere, and are recorded in full in section 6.

---

## 1. Task accounting

| Task | Status | Note |
| --- | --- | --- |
| Task 0. Digest sweep | **DONE** | Clean. No wrong literal. Gate satisfied, continued in-session |
| Task 0. Build-input inventory and reproducibility | **DONE** | Recorded, not fixed, per instruction. Section 3 |
| Task 1. Reconcile the Studio payload | **DONE** | Payload was stale. Rebuilt, contents proven, repinned. `39aea30` |
| Task 2. Version to 1.2.0 | **DONE** | Both gated literals. Drift gate proven in both directions. `8e637fd` |
| Task 3. Build | **DONE** | Succeeded first real run, exit 0, zero ISCC warnings |
| Task 4. Sign and verify independently | **DONE** | Not BLOCKED. Signing credentials were available and worked |
| Task 5. Prove the artifact | **DONE with one stated limit** | Embedded file list verified from the compiler's own embed record, not from an independent unpack. Section 5.1 |
| Close-out, git, dispatch card | **DONE** | This document |

Nothing was silently dropped. Two items were deliberately **not** done because they
are out of scope and are recorded as follow-ups instead: bumping Studio's own version
string (section 4.2) and resolving the Inno Setup commercial licensing question
(section 7.1).

---

## 2. Task 0. Digest sweep

### 2.1 Method

For every digest-bearing resource, three values were compared: the literal in source,
the SHA-256 of the **git-stored blob** (`git cat-file blob HEAD:<path>`), and the
SHA-256 of the **working-tree file**. The blob is the value any other clone would
check out; the working tree is the value this machine's build actually hashes. The
defect class from `ab180d4` is exactly the case where those two differ.

`core.autocrlf` is `true` in this repo, so any text file without an explicit
`.gitattributes` rule has a CRLF working tree and an LF blob.

### 2.2 Result: clean

| Literal | Covers | Source literal | Git blob | Working tree | Verdict |
| --- | --- | --- | --- | --- | --- |
| `$expectedSoulHash` (`setup.ps1:2395`) | `resources/safety-rules.md` | `e70212603f2f91e6...db7941` | same | same | **CLEAN** |
| `$expectedPersonaHash` (`setup.ps1:2494`) | `resources/persona.md` | `0557d07004d4d067...ff63a0` | same | same | **CLEAN** |
| `$expectedWorkspaceSoulHash` (`setup.ps1:2495`) | composed workspace SOUL | `441b6279f6613c31...a5a257` | recomputed independently: match, 6,677 bytes | **CLEAN** |
| `$studioPinned` (`build_release.ps1`) | embedded Studio installer | binary, gitignored | not in git by design | see Task 1 | **REPINNED** |

Both files covered by the workspace SOUL pin were confirmed to contain **zero CR
bytes** (safety-rules.md: 4,277 bytes, 0 CR, 31 LF; persona.md: 2,013 bytes, 0 CR,
43 LF), verified by a raw byte read with a positive control (`ClawFactory-Secure-Setup.iss`:
1,153 CR / 1,153 LF, as a file that must show CRs). Both carry `text eol=lf` rules.

A first probe using `grep -c $'\r'` reported 31 and 43 "CR lines" for those two files.
That was the empty-pattern trap: the pattern did not expand to a carriage return and
matched every line, so the counts were line counts. The `tr -dc '\r' | wc -c` and raw
byte-array readings agree on zero, and blob equals working tree, which is the
independent confirmation. Recording this because it is the same class of lying probe
already on file, and it nearly produced a false finding.

The composition in `scripts/build_release.ps1` and the one in
`resources/freeze-injected-soul.sh` were read side by side and are byte-identical
(same header lines, same `\n---\n` separator, same trailing comment and blank line).
The install-side delivery was also checked: `safety-rules.md` and `persona.md` are
transported as **base64 of raw bytes**, not through the CRLF-normalising `$lfB64`
helper used for the shell and node scripts, so the composed file in WSL is composed
from the same bytes the pin covers. That is correct as written.

### 2.3 Files with a hash-adjacent smell that turned out clean

- **`resources/orchestrator-prompt.md` is not digest-bearing.** Nothing hashes it.
  The `{{SOUL_SHA256}}` placeholder it once carried is gone from the file, and
  `bootstrap.ps1`'s substitution is dead code (audit rows 12 and 13). Its working tree
  is CRLF and its blob is LF with no `.gitattributes` rule, but with no digest over it
  that is a cosmetic inconsistency, not a finding of this class.

### 2.4 Two notes, neither a defect

- **`resources/clawfactory-proxy.js` and `resources/clawfactory-proxy.service` have no
  `eol=lf` rule** and are CRLF in the working tree while their blobs are LF. Both are
  transported into WSL through the `$lfB64` LF-normalising helper (`setup.ps1:2685-2686`),
  so nothing breaks. Every other resource of the same kind carries an explicit rule.
  Recommend adding the two lines for consistency, as belt-and-suspenders, not as a fix.
- **25 tracked `.ps1` files carry `eol=lf` in `.gitattributes` but are still CRLF in
  the working tree.** Git does not re-check-out files when `.gitattributes` changes, so
  the rule governs future commits and fresh clones but not this working copy. None of
  them is digest-bearing. `setup.ps1` is exempt by design (`-text diff`, byte-for-byte)
  and its blob equals its working tree.

---

## 3. Build inputs not in the repo, and reproducibility

### 3.1 Toolchain on this machine

| Component | Version |
| --- | --- |
| Inno Setup compiler engine | 6.7.1, at `C:\Program Files (x86)\Inno Setup 6\ISCC.exe` |
| PowerShell | 5.1.26100.8875, Desktop edition |
| Node | v24.13.1 |
| npm | 11.8.0 |
| git | 2.53.0.windows.1 |
| signtool | `signing\tools\Microsoft.Windows.SDK.BuildTools\bin\10.0.28000.0\x64\signtool.exe` |
| Azure Artifact Signing client | 1.0.128 |

`ISCC.exe` carries no version resource of its own (`FileVersion 0.0.0.0`); the 6.7.1
figure is the compiler engine version from its banner, corroborated by
`unins000.exe` at 6.7.1.

### 3.2 Inputs the repo does not contain

| Input | Size / digest | How a second machine would get it |
| --- | --- | --- |
| `resources/ubuntu-rootfs.tar.gz` | 341,130,963 B, sha256 `1483cc5c1dce1306...fb4109` | **No recorded source and no pin.** Audit row 6. This is the hard blocker |
| `resources/ClawFactory-Studio-Setup-1.1.0.exe` | 100,028,664 B, sha256 `b701bfb7...` | Rebuild from Studio `main` @`14b6422`, **but see 3.3** |
| `.env` | 6 `AZURE_SIGNING_*` keys | Secret. Not in the repo and must not be |
| `signing/tools/` | nuget-restored `Microsoft.ArtifactSigning.Client` + `Microsoft.Windows.SDK.BuildTools` | Restorable via the bundled `nuget.exe` |
| `signing/metadata.json` | 817 B, generated from `.env` | Generated |

`resources/ClawChat.exe` (11,702,272 B, sha256 `596c0825...`) **is** tracked in git, so
it is not on this list, though it still carries no build-time pin (audit row 7).

### 3.3 Is this build reproducible on a second machine? No.

Stated plainly, as instructed. Recorded, not fixed.

**What is reproducible:** the Inno compile step itself is **byte-for-byte
deterministic**. Two consecutive `ISCC.exe` runs over identical inputs produced
identical output, `82cf5023ba84f09bf1325d1a2ee6ad69ea1decb5feb65cc16f4dcdc3366e61b8`,
440,562,861 bytes, both times. So non-reproducibility is entirely a property of the
**inputs**, not of the compiler. That is the good news and it narrows the problem.

**What blocks reproduction:**

1. **`ubuntu-rootfs.tar.gz` has no recorded provenance.** 341 MB, gitignored, no source
   URL, no pin, no documented origin. A second machine cannot obtain a known-correct
   copy, and nothing would detect a wrong one. This is the single largest gap and it is
   also a supply-chain gap, not only a reproducibility one.
2. **The pinned Studio payload cannot be reproduced without the signing credentials.**
   The pin covers a **signed** artifact. Studio's `electron-builder` config is
   credential-gated: with no `.env` it produces an **unsigned** build, deliberately and
   by design. An unsigned Studio build has a different digest, so the Studio pin gate
   would fail on any machine without signing credentials. Reproducing the payload
   therefore requires the Azure signing secrets, not just the source.
3. **Signed artifacts are not bit-reproducible at all, even here.** Signing the exact
   same unsigned bytes twice produced two different files: the shipped artifact
   (440,578,512 B, `54f9a9e0...`) and a demonstration copy (440,578,504 B,
   `f908b0cc...`). Different sizes, different digests, because each RFC 3161 timestamp
   token differs. Any future reproducibility claim has to be made about the **unsigned**
   compile output, which is reproducible, and never about the signed artifact.
4. **The build box holds an Inno Setup instance reporting "Non-commercial use only".**
   See 7.1. A second machine would need whatever licence is correct.

**What it would take:** record and pin the rootfs (source, digest, and a build-time
gate in the shape already used three times in `build_release.ps1`); decide whether the
Studio pin should cover the unsigned or the signed artifact; and document the toolchain
versions above as requirements. Not attempted this session, per instruction.

---

## 4. Task 1. The Studio payload

### 4.1 It was stale, and worse than "stale"

The job posed two possibilities. The **first** is what was true.

The pinned payload `d5ff8370...` was built from Studio `@9d62ad0`. Studio `main` is at
`@14b6422`, three commits ahead, and the diff between them adds 1,285 lines across 12
files including three entire pages:

| Studio commit | Adds | Guard |
| --- | --- | --- |
| `6105c53` | `RecentlyDeletedPage.tsx`, `quarantine-engine.ts`, `quarantine-ipc.ts` | Guard 1 |
| `14b6422` | `ApprovalsPage.tsx`, `SmtpSetupPage.tsx`, `send-engine.ts`, `send-ipc.ts` | Guard 2 |

So shipping the old pin would have shipped an installer whose Studio has **no approval
card while the agent side has a send broker**, and additionally **no Recently-deleted
panel while the agent side has quarantine-delete**. Two guards with no front end, not
one. That is a broken product, exactly as the job framed it.

### 4.2 Resolution

Rebuilt from Studio `main` @`14b6422` with `npm run package`, signing gated on via
`CLAWFACTORY_SIGN_SCRIPT`. Typecheck clean. Four files signed by Azure Artifact
Signing (the app exe, `elevate.exe`, the uninstaller, and the installer), zero warnings,
zero errors.

| | Value |
| --- | --- |
| New Studio artifact | sha256 `b701bfb734d5a307a41cf4b3cca8d34eb4f9c89b2116c7bc084fb180afefb7eb` |
| bytes | 100,028,664 |
| Authenticode | `Valid`, `CN=Bret Mckinney`, timestamped |
| Studio commit | `14b6422` |

### 4.3 Confirmed by execution before pinning, not after

A pin to the wrong artifact is worse than no pin, so the contents were proven from the
**compiled binary**, not from the source tree.

Both installers were unpacked with 7-Zip (`electron-winstaller`'s bundled 7za 16.04;
no system 7-Zip is installed). `resources\app.asar` was extracted from each
`$PLUGINSDIR\app-64.7z` and searched for twelve markers drawn from the three new panels.

| Marker | New payload | Previously pinned payload |
| --- | --- | --- |
| `/approvals/smtp` | PRESENT | absent |
| `Email settings` | PRESENT | absent |
| `smtp.example.com` | PRESENT | absent |
| `Currently sending as` | PRESENT | absent |
| `send:approve` | PRESENT | absent |
| `send:credential` | PRESENT | absent |
| `send:deny` | PRESENT | absent |
| `send:list` | PRESENT | absent |
| `Recently deleted` | PRESENT | absent |
| `quarantine:list` | PRESENT | absent |
| `quarantine:restore` | PRESENT | absent |
| `clawfactory-sendctl` | PRESENT | absent |

Controls, because twelve hits with nothing to compare against would prove only that the
search runs:

- **Positive control**, must appear in both: `Workspace`, PRESENT in both. (A second
  intended positive, `ChatPage`, was absent from both; it is a component identifier that
  the minifier mangles, so it was the wrong choice of control, not a failure.)
- **Negative control**, must appear in neither: `ZZZ-NOT-IN-ANY-BUILD-4f9a`, absent in both.

app.asar sizes differ as expected: 546,035 bytes new against 510,683 bytes old.

Pin updated in `scripts/build_release.ps1` in the same shape as the other literals, with
the Studio commit hash recorded in commit `39aea30`.

### 4.4 One thing deliberately not changed

Studio stays at version `1.1.0`, so `ClawFactory-Studio-Setup-1.1.0.exe` is now a
**filename reused for different bytes**. The sha256 is the real anchor and it is
correct, but the name no longer carries provenance. Bumping Studio's version would have
touched the `.iss` `#define`, `$studioName`, and Studio's three `package.json` files,
which adds a second variable to the first gated build. Recorded as a follow-up.

---

## 5. Tasks 2 through 5, evidence

### 5.1 The five gates, verbatim

```
SOUL pin OK: e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
Bundle check OK: all 30 preflight resources are in [Files].
Studio pin OK: b701bfb734d5a307a41cf4b3cca8d34eb4f9c89b2116c7bc084fb180afefb7eb
Version OK: 1.2.0 (.iss and setup.ps1 agree)
Persona pin OK: 0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0
Workspace SOUL pin OK: 441b6279f6613c313e87e9e9e034f97a220540cddbf1cf738bb9a86c37a5a257 (6677 bytes composed)
```

Five gates, six OK lines: the persona gate emits two, one per literal it covers.

**The preflight pairing check.** The bundle gate reported all 30. Re-derived
independently of the gate, by parsing `$required` out of `setup.ps1` and pairing each
entry against both the `.iss` `[Files]` section and the compiler's own record of what it
embedded:

- 30 of 30 required resources present in `[Files]`.
- 30 of 30 required resources embedded by `ISCC.exe`.
- 0 missing on either side.
- Negative control `this-resource-does-not-exist.sh`: absent from both, so the pairing
  discriminates.
- `resources\ClawFactory-Studio-Setup-1.1.0.exe` present in the embedded set.
- 51 files embedded in total, against 30 required, the balance being the engine,
  launchers, icons, rootfs, ClawChat and docs.

The count is 30, not the 29 recorded in the audit table; `persona.md` joined the list
with the persona-as-a-constant work.

**Stated limit on Task 5.** "Extract or inspect the installer's embedded file list" was
satisfied by **inspection of the compiler's embed record**, not by an independent unpack
of the finished `.exe`. 7-Zip reads the artifact as a PE and exposes its sections,
resources, the `CERTIFICATE` block (15,648 bytes) and the payload blob `[0]`
(439,668,912 bytes), but it cannot decompress the Inno payload; no Inno extractor
(`innounp`, `innoextract`) is present on this machine, and obtaining one was out of
scope. What supports the claim instead: the compile transcript names every embedded file
by full path, and the compile is byte-for-byte deterministic, so the artifact is a
function of exactly those inputs. The next session installs the binary, which settles it
by execution.

### 5.2 The version gate, proven in both directions

This gate had never been observed doing anything. Both directions were run.

**Failing**, `.iss` at 1.2.0 and `setup.ps1` still at 1.1.1:

```
SOUL pin OK: e70212603f2f91e6...
Bundle check OK: all 30 preflight resources are in [Files].
Studio pin OK: b701bfb734d5a307...
Fail : build_release.ps1: Version drift: .iss MyAppVersion is 1.2.0 but setup.ps1
$InstallerVersion is 1.1.1. The .iss value is the one the customer sees, so set
$InstallerVersion to 1.2.0 and rebuild.
```

**Passing**, both at 1.2.0: `Version OK: 1.2.0 (.iss and setup.ps1 agree)`, and the run
proceeded to the compile step.

Both runs used a stand-in for `ISCC.exe` so they halted before a 60-second compile.

### 5.3 Every other place a version string lives

| Location | Value | Changed? | Why |
| --- | --- | --- | --- |
| `ClawFactory-Secure-Setup.iss:6` `MyAppVersion` | 1.1.1 to **1.2.0** | **yes** | The authority. Feeds `AppVersion` |
| `setup.ps1:56` `$InstallerVersion` | 1.1.1 to **1.2.0** | **yes** | Follows it, now gated |
| `.iss:13` `StudioInstaller` filename | 1.1.0 | no | Studio's own version. See 4.4 |
| `build_release.ps1` `$studioName` | 1.1.0 | no | Same |
| `README.md:3` release badge | v1.0.45 | no | Release-time copy, and already three releases stale before this session |
| `CHANGELOG.md` newest entry | 1.1.1 | no | Release-time. This session does not tag or release |
| `scripts/azure-validate.ps1` `$Blob`, `$ExpectSha256` | v1.0.48 | no | Harness defaults the validation session passes explicitly |
| Studio `package.json` x3 | 1.1.0 | no | Separate product |

1.2.0 rather than 1.1.2 because Guard 2 introduced a capability rather than fixing a
defect, per the job. No contrary instruction from Bret was on file.

The binary agrees: Windows reports `ProductVersion: 1.2.0` on the compiled `.exe`.
`FileVersion` is blank because the `.iss` sets no `VersionInfoVersion`. Cosmetic; noted
in section 7.

### 5.4 ISCC output

Successful compile in 60.734 seconds. **Zero warnings and zero errors**; the full
transcript was captured and contains no `Warning:` line. It parsed `[Setup]`,
`[Languages]`, `[Code]`, `[Icons]`, `[Run]` and 51 `[Files]` entries, compressed all 51,
and wrote `Output\ClawFactory-Secure-Setup.exe`.

One line from the banner is a finding rather than build noise, and is in 7.1.

### 5.5 Task 4. Signing, verified independently

Not BLOCKED. Credentials were present and the signing service responded.

`Get-AuthenticodeSignature` on the produced binary, rather than trusting the signer's
own "Signed successfully":

| Field | Value |
| --- | --- |
| Status | **Valid** |
| StatusMessage | Signature verified. |
| SignatureType | Authenticode |
| Signer subject | `CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US` |
| Signer issuer | `CN=Microsoft ID Verified CS EOC CA 04, O=Microsoft Corporation, C=US` |
| Signer serial | `330003DC6416A6072C5A29A09300000003DC64` |
| Signer validity | 2026-08-03 13:31:34 to **2026-08-06** 13:31:34 |
| Signer thumbprint | `515120D9C336C73A91CC54A5877B7B27C7B15EBE` |
| Timestamp authority | `CN=Microsoft Public RSA Time Stamping Authority`, issued by `CN=Microsoft Public RSA Timestamping CA 2020` |
| Timestamp cert validity | 2025-10-23 to 2026-10-22 |

The signing certificate is valid for **three days** and expires 2026-08-06. That is
normal for Azure Artifact Signing and is precisely why every invocation timestamps: the
RFC 3161 countersignature is what keeps the signature valid after the leaf expires. It
does mean the artifact's signature should be re-verified after 2026-08-06 to confirm the
timestamp is carrying it, and a `Valid` result then is the real proof.

**Signed digest differs from unsigned, demonstrated on the same bytes** rather than
inferred:

| | sha256 | bytes | Authenticode |
| --- | --- | --- | --- |
| Unsigned compile output | `82cf5023ba84f09bf1325d1a2ee6ad69ea1decb5feb65cc16f4dcdc3366e61b8` | 440,562,861 | `NotSigned` |
| That same file, after signing | `f908b0cccffbe984255c3a2dbd587cfd6ca3a86dc1fd589f025f80dc0f16a22b` | 440,578,504 | `Valid` |
| **Shipped artifact** | **`54f9a9e05e7f2f05571365dbb9bb30f3e2b724f260345587e9eba69855968d37`** | **440,578,512** | **`Valid`** |

The shipped artifact and the demonstration copy started from identical unsigned bytes
and ended up 8 bytes apart, which is the non-determinism of signing described in 3.3.

---

## 6. Every failure this session, including the ones now fixed

The pattern of what broke is the useful output, so all of it is here.

### 6.1 `build_release.ps1` could not be run at all under `powershell.exe -File`

**FIXED**, in `8e637fd`.

```
Split-Path : Cannot bind argument to parameter 'Path' because it is an empty string.
At ...\scripts\build_release.ps1:14 char:45
+     [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
```

The script died before the first gate. `$RepoRoot` defaulted to
`(Split-Path -Parent $PSScriptRoot)` inside the `param()` block.

Root cause, isolated to a **single variable** rather than guessed:

| Shape | Invocation | Result |
| --- | --- | --- |
| `[CmdletBinding()]` + param default | `-File`, no args | **FAILS** |
| `[CmdletBinding()]` + param default | `-File`, with args | **FAILS** |
| `[CmdletBinding()]` + param default | `&` from a session | works |
| `[CmdletBinding()]` + param default | `-File`, `-RepoRoot` passed | works |
| **no** `[CmdletBinding()]`, otherwise identical | `-File`, no args | **works** |

So: `[CmdletBinding()]` combined with `-File` leaves `$PSScriptRoot` empty during
parameter-default evaluation. `$PSScriptRoot` **is** populated by the time the body
runs, so the default moved into the body with an explicit failure if it still cannot
resolve.

My first hypothesis was that explicitly-supplied parameters triggered it. The control
matrix disproved that; it is `[CmdletBinding()]`.

Why it was invisible: the build has only ever been run one way, from an interactive
session with `&`, on one machine. It is a reproducibility defect of exactly the kind
Task 0 was chartered to surface, found by running the thing rather than reading it.

### 6.2 `sign_installer.ps1` carries the identical latent defect

**NOT FIXED, out of scope, reported.**

`scripts/sign_installer.ps1:18-28` has the same `[CmdletBinding()]` plus
`[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)` and `$ToolsDir` built the same
way. It will fail identically under `powershell.exe -File`.

It is **latent, not active**: `build_release.ps1` invokes it as
`& $signScript -InstallerPath $installerPath`, which works, and it signed correctly six
times this session. The job forbids changing `sign_installer.ps1` in this session so the
build has one candidate cause, so it is recorded and left alone. It should be fixed with
the same two lines when the stamp requirement lands.

### 6.3 Version drift

Deliberate negative control, not an accident. Section 5.2.

### 6.4 What did not fail

Worth stating, because it was the expected risk. The `.iss` compiled clean against the
current resource set on the first attempt: no missing files, no path errors, no stale
`[Files]` entries, zero ISCC warnings. The build was never re-run from the top because
no build-stage failure occurred.

---

## 7. Delta security sweep and bug review

Read end to end from `git diff 000d4d9..HEAD`: three files, 39 insertions, 8 deletions.

### 7.1 Finding: the compiler reports "Non-commercial use only"

**Reported, not acted on. Outside release engineering, and a decision for Bret.**

The `ISCC.exe` banner in the build transcript reads:

```
Compiler engine version: Inno Setup 6.7.1
Non-commercial use only
```

`license.txt` shipped in the same directory is the classic Inno licence and explicitly
permits commercial use. The two disagree, so the on-disk `license.txt` appears stale
relative to the running binary. Tracing the string: it is not in `ISCC.exe`; it is in
`Compil32.exe`, adjacent to `Single User`, `Team`, `Enterprise`, `License.Typ`,
`Update entitlement ended`. Inno Setup 6.7.1 therefore has a paid licence-tier model,
and this installation is running the non-commercial tier.

ClawFactory is a commercial product (`AppPublisher` is `Frontier Automation Systems LLC`,
and the site has a buy path pending). **Shipping a paid product built by a compiler
instance that self-reports "Non-commercial use only" is a licensing exposure that should
be resolved before any public release.** This does not affect the artifact's technical
correctness and is not a build failure. Verify the terms for 6.7.1 and buy the
appropriate licence if required.

### 7.2 Security review of the delta

| Change | Security assessment |
| --- | --- |
| `$studioPinned` `d5ff8370` to `b701bfb7` | **Strengthens.** The pin remains a literal in signed source, never derived from the artifact it certifies, so the L24 anchor property is preserved. The new value was verified against the artifact's contents before being trusted. Drift still fails the build and is never auto-corrected |
| `$RepoRoot` default moved from param block to body | **Neutral.** `$RepoRoot` was already a caller-settable parameter, so no new input reaches the build; the resolution point moved, not the trust boundary. One behaviour change worth naming: an explicitly-passed empty string now falls back to the script's parent instead of erroring, because `-not ''` is true. Benign for a locally-run build script |
| `MyAppVersion`, `$InstallerVersion` to 1.2.0 | **None.** Reporting only |

No new network calls, no new file writes, no new privilege use, no change to any
install-time or launch-time control, no weakening of any gate. Nothing in this delta
touches `setup.ps1` beyond one version literal.

### 7.3 Bug review of the delta

- `if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }` sits **before**
  `function Fail` is defined, which is why it uses `Write-Error` directly rather than
  `Fail`. Calling `Fail` there would have been a forward reference and would itself have
  been a bug. Correct as written.
- With `$ErrorActionPreference = "Stop"` already set above it, that `Write-Error` throws
  a terminating error, so the following `exit 1` is belt-and-suspenders. This matches the
  existing `Fail` function's shape, so it is consistent rather than novel.
- The comment block claims the failure occurs "whether or not arguments are passed."
  That claim is backed by the control matrix in 6.1, both rows observed.
- No other logic changed. The gate order, the gate semantics, and the compile and sign
  steps are untouched.

No bugs found in the delta.

---

## 8. Resource ledger

| Resource | Used |
| --- | --- |
| Azure VMs | **None.** No cloud validation this session, by design |
| Azure Artifact Signing calls | **6.** Four for the Studio rebuild (app exe, `elevate.exe`, uninstaller, installer), one for the shipped installer, one for the unsigned-vs-signed demonstration |
| `ISCC.exe` compiles | **3.** One real build, two for the determinism test |
| Studio `npm run package` | 1, plus 1 typecheck |
| Peak scratch disk | ~1.5 GB, cleaned to 1.02 MB. Retained: the build transcript, the ISCC stub, three probe scripts, two extracted `app.asar` files |
| Wall clock | roughly 1 hour |

**Left on disk, gitignored, for Bret to decide about:**

- `Output\ClawFactory-Secure-Setup.exe.PRIOR`, 440,525,520 B, sha256
  `67619df79179db11e76454e9734de244a51128b37c55f66071213c98f72719a9`. The previous
  v1.1.1-era installer from 2026-07-24, renamed rather than deleted so the new artifact
  is unambiguous. Safe to remove.
- `ClawFactory-Studio\desktop\release\ClawFactory-Studio-Setup-1.1.0.exe.PREV`,
  100,022,000 B, sha256 `d5ff8370...`. The previously pinned Studio build. Kept because
  it is the artifact the old pin referred to and it is the control that proved the new
  payload discriminates.

---

## 9. Next session: assembled-build validation

**Input:** `Output\ClawFactory-Secure-Setup.exe`, sha256
`54f9a9e05e7f2f05571365dbb9bb30f3e2b724f260345587e9eba69855968d37`, 440,578,512 bytes,
version 1.2.0, Authenticode Valid. Verify that digest before anything else; if it does
not match, do not proceed.

**What that session needs:**

1. **Re-verify the Authenticode signature first.** The leaf expires 2026-08-06. A
   `Valid` result after that date proves the RFC 3161 timestamp is carrying the
   signature, which has never actually been observed on this product. A failure there is
   a signing-policy finding, not an install finding, and it is cheap to check first.
2. **Settle the Task 5 limit by execution.** The embedded file list was verified from the
   compiler's record, not an independent unpack. Installing resolves it: confirm all 30
   preflight resources land on disk, and that `Step-Preflight` itself passes.
3. **Confirm the Studio payload actually reaches the customer profile and that the new
   panels are reachable in the running app.** This build is the first to carry them.
   Both the approvals card and the Recently-deleted panel should be exercised, not merely
   present. The de-elevated `ExecAsOriginalUser` landing at `ssPostInstall` is the part
   with history.

**Named tests carried forward, as instructed:**

| Test | Card | Note |
| --- | --- | --- |
| Guard 1 routing on a real agent turn | | Routing is advisory; the hold is structural. Never yet run on a clean box |
| External SMTP delivery | **#198** | Guard 2's send path end to end, against a real server |
| SOUL discoverability | **#199** | |
| Nested-channel audit | **#200** | |

**Also carried forward, from this session:**

| Item | Where | Priority |
| --- | --- | --- |
| Inno Setup commercial licensing | 7.1 | **Before any public release.** Business decision |
| `sign_installer.ps1` `-File` defect | 6.2 | With the stamp requirement that closes the advisory build-gate bypass |
| `ubuntu-rootfs.tar.gz` has no provenance or pin | 3.3 | High. Supply chain, not just reproducibility |
| Bump Studio's own version so the filename carries provenance | 4.4 | Medium |
| `eol=lf` rules for `clawfactory-proxy.js` and `.service` | 2.4 | Low, consistency |
| `VersionInfoVersion` unset, so `FileVersion` is blank | 5.3 | Low, cosmetic |

**Not done and still not done:** the build-gate bypass is still open. `ISCC.exe` invoked
directly, and `sign_installer.ps1` invoked directly, still skip all five gates. This
session used both of those paths deliberately, for the determinism test and the
signing demonstration, which is a live illustration that the bypass is real. Closing it
was explicitly deferred until after this build completed. It has now completed.

---

## 10. Git

`git status --short` was run first and the tree was clean at `000d4d9`. Explicit
per-file staging throughout; no `git add -A`, no `git worktree add`, single working tree
on `main`.

| Commit | Contents |
| --- | --- |
| `39aea30` | `scripts/build_release.ps1`: Studio pin to `b701bfb7`, Studio commit `14b6422` recorded in the message |
| `8e637fd` | `ClawFactory-Secure-Setup.iss`, `setup.ps1`, `scripts/build_release.ps1`: version 1.2.0 and the `-File` fix |
| this one | this close-out |

`39aea30` was amended once before it was pushed: the first attempt used PowerShell
here-string syntax in a bash context, which left a stray `@` as the subject line. The
body was intact; the amend restored the subject.

The Studio repo has **no source changes** this session, so nothing to commit or push
there. The rebuilt artifact is gitignored by design.

**Not tagged. No GitHub Release. Nothing published. The binary was not installed.**
