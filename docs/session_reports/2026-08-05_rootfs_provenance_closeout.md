# Rootfs Provenance and Build-Gate Closure

**Date:** 2026-08-05
**Track:** v1 fast-security-harness, release engineering and supply chain
**Dispatch card:** #214
**Depends on:** first gated build complete (`6909d47`), `39aea30`, `8e637fd`, card #213 done
**Runs before:** assembled-build validation, which is the next job
**Final artifact for the validation session:** `6f378d3ad731739e09a086e68eb898dcd446c3e6337ec8e118134ea183624bf9`

---

## 0. Summary

Two items deferred out of the build session are closed. Neither changes product
behaviour; both are release engineering, and both would have invalidated a validation
run if done after it.

| Task | Outcome |
| --- | --- |
| 1. Identify the rootfs | **DONE.** Outcome 1, the best case: byte-identical to a published Canonical digest |
| 2. Pin what was adjudicated | **DONE.** Seventh build gate plus an install-time refusal, proven both directions |
| 3. Close the build-gate bypass | **DONE.** Signer refuses unstamped binaries; six doc locations corrected; `-File` defect fixed |
| 4. Rebuild | **DONE.** Inputs changed, so a rebuild was required. New signed artifact recorded below |

The headline of Task 1 is worth stating before the detail, because it changes how the
rest of this report should be read: **the rootfs turned out to be exactly what it should
have been.** It is a stock, unmodified Ubuntu 22.04.5 WSL image whose sha256 matches the
digest Canonical publishes for it. Nothing was substituted, nothing was added, nothing
had drifted. The gap was never that the bytes were wrong. The gap was that the product
had no way to tell.

---

## 1. Task 1. Identifying the rootfs

### 1.1 What was recorded before touching anything

| | |
| --- | --- |
| Path | `resources/ubuntu-rootfs.tar.gz` |
| Size | 341,130,963 bytes |
| sha256 | `1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109` |
| Created (local FS) | 2026-05-01T18:03:15Z |
| Last written (local FS) | 2026-05-01T20:41:24Z |

### 1.2 What it actually contains

Read out of the archive itself, not inferred:

| Source inside the tarball | Value |
| --- | --- |
| `/etc/os-release`, `/usr/lib/os-release` | `Ubuntu 22.04.5 LTS`, `VERSION_CODENAME=jammy`, `ID=ubuntu` |
| `/etc/lsb-release` | `DISTRIB_RELEASE=22.04`, `DISTRIB_CODENAME=jammy` |
| `/etc/debian_version` | `bookworm/sid`, which is correct for jammy's `base-files` and not an anomaly |
| `/var/lib/dpkg/status` | 562 packages, file dated 2025-03-18 |
| `/var/log/apt/history.log` | Three apt runs, all on **2025-03-18 between 21:37:13 and 21:38:34** |
| Archive member mtimes | Newest is 2025-03-18 15:38. **Zero** members dated later |
| `/etc/cloud/build.info` | Absent, so this is not a Canonical *cloud* image |
| `/etc/wsl.conf` | Present, `[boot] systemd=true` |

The apt manifest is the identifying detail. Its final packages are
`... snapd software-properties-common ubuntu-wsl wsl-setup`. `ubuntu-wsl` and
`wsl-setup` are the packages that distinguish Canonical's **WSL** image from its cloud
and container images, and they explain `/etc/wsl.conf` without anyone having edited it.

### 1.3 Does it correspond to a published upstream image? Yes, exactly

Canonical publishes dated WSL rootfs builds with digests. The 2025-03-18 build directory
exists, and its `SHA256SUMS` reads:

```
1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109 *ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz
```

That is the same 64 hex characters as the local file. Not a version match, not a
"consistent with" match: the same bytes.

| | |
| --- | --- |
| Source URL | <https://cloud-images.ubuntu.com/wsl/jammy/20250318/ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz> |
| Published digest | `1483cc5c...fb4109`, in `SHA256SUMS` in that same directory |
| Retrieved | 2026-08-05, over HTTPS |
| Published size | 325 MiB, which is 341,130,963 bytes |

Two notes on how to use that URL later. `.../wsl/jammy/current/` currently resolves to
this same 20250318 build, but `current/` moves; the **dated** path is the durable one and
is what got recorded. And the check performed was against the `SHA256SUMS` file itself
over HTTPS. The detached `SHA256SUMS.gpg` beside it was **not** verified, because doing
so means downloading the signature and the Ubuntu signing key. That is a real
strengthening and it is offered as a next-session item rather than claimed here.

### 1.4 What the repo knew about where it came from: nothing

| Where someone would look | What is there |
| --- | --- |
| `git log` for the file | Nothing. It is gitignored, so it has no history |
| `1e72358` (2026-05-01), the commit that gitignored it | "Source it separately (CDN / build-time download)". No URL, no digest |
| `a702b2d` (2026-05-01), the commit that bundled it | Wiring only. No provenance |
| `CONTRIBUTING.md:38` | "sourced separately at build time; **see internal docs for the source**" |
| The internal doc that line points at | Does not exist |
| Any session report | Only the two audit rows recording that the gap existed |

The `CONTRIBUTING.md` line is the most instructive artifact in the table. It reads like a
pointer to a record, which is why nobody chased it for fourteen weeks, and it pointed at
nothing.

### 1.5 What is installed beyond a base image: nothing

| Check | Result |
| --- | --- |
| `/home` | Empty. No `clawuser`, no user directories at all |
| `/root` | Stock `.bashrc` and `.profile` only |
| `/opt`, `/srv`, `/snap`, `/mnt`, `/media` | Empty directories |
| `/etc/passwd` | 28 entries, every one a stock Ubuntu system account |
| node, npm, nvm, openclaw, anything ClawFactory | Absent |
| Members with mtime after the 2025-03-18 build | **Zero** |

This matters for a reason beyond tidiness: it means a freshly fetched stock image **is**
a valid substitute. Nothing about this file is bespoke, so a future refetch from the
published URL reproduces it exactly, and the pin is a pin on upstream rather than on a
local artifact nobody else can obtain.

### 1.6 Adjudication

Outcome 1 of the three the job posed. Pinned, source URL recorded, done. Task 2 proceeded
without a founder decision because there was no ambiguity to escalate.

---

## 2. Task 2. The pin

Built in the shape the other gates already use: a literal in signed source, install
refusing on mismatch, and a build-time gate that keeps the literal honest and never
auto-corrects.

### 2.1 Install-time refusal

`setup.ps1`, inside `Install-WslDistroWithFallback`, before the `wsl --import`:

```powershell
$expectedRootfsHash = '1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109'
$rootfsHash = (Get-FileHash -LiteralPath $BundledRootfs -Algorithm SHA256).Hash.ToLower()
if ($rootfsHash -ne $expectedRootfsHash) { throw ... }
```

The provenance block above that literal carries the source URL, the release, the date it
was obtained, and the statement that the digest is upstream's published value rather than
one computed locally. Per the job: a pin with no recorded provenance is only half a
control.

One deliberate choice. A mismatch **throws**; it does not fall through to the network
install path a few lines below. Falling through would convert "someone substituted the
rootfs" into "installed from the network instead", which is a silent downgrade and
destroys exactly the signal the pin exists to raise.

### 2.2 Build-time gate

`scripts/build_release.ps1` gained a seventh gate, positioned after the workspace-SOUL
gate and before the compile. It checks three things: the file is present, the `.iss` still
bundles it, and the literal in `setup.ps1` matches the file on disk. The expected value is
**read out of `setup.ps1`** rather than duplicated in the build script, so the number the
install enforces is the number the build keeps honest. A second copy could only ever drift
from the first.

### 2.3 Proven in both directions

| Direction | Method | Result |
| --- | --- | --- |
| Build gate, positive | Full `build_release.ps1` run with a stub compiler | `Rootfs pin OK: 1483cc5c...fb4109`, all seven gates green, stopped at the stub |
| Build gate, negative | Flipped the literal's last character `9` to `a`, re-ran | `Rootfs drift: ... hashes to ...4109 but setup.ps1 pins ...410a`, exit 1, **`Compiling installer` never printed**. `setup.ps1` restored and re-hashed byte-identical afterwards |
| Install gate, positive | Gate block against the real rootfs | `ACCEPTED: 1483cc5c...fb4109` |
| Install gate, negative | Gate block against a 10-byte decoy gzip | `REFUSED: expected 1483cc5c...fb4109 but found 9d1011ce...35e3` |
| Install gate, wiring | PowerShell AST parse of `setup.ps1`; line-order check | 0 parse errors; pin at line 467, `wsl --import` at line 483, so the gate runs first |

The negative build test is the load-bearing one. It confirms the gate fails **closed and
early**, before 60 seconds of compile, and that it reports both digests so the operator
can tell substitution from an intentional rootfs change.

---

## 3. Task 3. Closing the build-gate bypass

### 3.1 What was open

`sign_installer.ps1` declared `[Parameter(Mandatory = $true)] [string]$InstallerPath` and
contained zero references to any gate. It signed whatever it was handed. So:

```
ISCC.exe ClawFactory-Secure-Setup.iss
scripts\sign_installer.ps1 -InstallerPath Output\ClawFactory-Secure-Setup.exe
```

produced a release-grade signed binary that had passed none of the gates, and that route
was documented in six places including the README, which taught it **first**.

### 3.2 The closure

`build_release.ps1` now writes a build stamp beside the compiled installer, before
signing, containing the sha256 of the unsigned bytes, the version, the gate list and a
UTC timestamp. `sign_installer.ps1` refuses to sign unless a stamp is present **and**
covers the exact bytes it is about to sign. On success the stamp is deleted, since signing
appends to the file and the stamp is stale by construction from that moment.

Binding to the digest rather than to mere presence is what makes a stale stamp useless. It
is worth being precise about why that holds rather than asserting it: an Inno compile over
identical inputs is byte-for-byte deterministic, measured on 2026-08-05. So a stale stamp
matches a fresh direct compile only when the inputs were identical to a build that already
passed the gates, which is precisely the case where the gates would have passed anyway.
Any input that would have failed a gate changes the compiled bytes and orphans the stamp.

### 3.3 What this control is worth, stated plainly

**The stamp is state, and anyone who can run the signer can forge one.** Writing a JSON
file with the right digest in it is not difficult, and nothing prevents it.

That is accepted rather than solved, because the threat being addressed is a tired founder
taking a documented shortcut under time pressure, not an adversary with local code
execution. Against an attacker this control is **advisory**. Against process drift it is
**structural**, because the shortcut now fails loudly instead of quietly succeeding. It
must never be described as more than that, and the same sentence appears in the comment
block in `sign_installer.ps1`, in `build_release.ps1`, and in the README, so a future
reader cannot pick up the stronger reading by accident.

The division of labour is the part worth keeping: local dev compiles with `ISCC.exe`
remain entirely legitimate and unchanged. They simply do not produce signable output.
Unsigned binaries never reach a customer, so the gates only need to be load-bearing on the
path that does.

### 3.4 The override

`-SignWithoutBuildStamp`. Emergency re-signing stays possible, which matters: a signing
path with **no** override gets worked around by editing the script, which is worse than
both an override and no control at all. It prints a banner naming itself and listing the
gates that were not enforced, so it cannot be used without leaving a trace in the output.

### 3.5 Proven by execution, with a paired control

| Test | Setup | Result |
| --- | --- | --- |
| A | No stamp at all | **REFUSED.** "no build stamp at ... so this binary was not produced by scripts\build_release.ps1" |
| B | Stamp present, covering different bytes | **REFUSED.** "build stamp mismatch: the stamp covers 0000... but ... hashes to d2234d6f..." |
| C **(paired control)** | Valid stamp over the real bytes | **PASSED the gate.** "Build stamp OK: produced by scripts/build_release.ps1 v1.2.0", then stopped at the next step (`.env not found`), proving the gate passed rather than the script merely failing somewhere |
| D | `-SignWithoutBuildStamp`, no stamp | **Announced itself**, printed the full banner, continued |
| E | Real end-to-end `build_release.ps1` | Stamp written, signer verified it, signed, stamp consumed. See section 4 |

Test C is deliberately pointed at an empty `-RepoRoot` so it halts at the `.env` check.
That keeps the control honest without spending a real signing operation on a junk file.

### 3.6 The latent `-File` defect

`sign_installer.ps1` carried the same `[CmdletBinding()]` plus `$PSScriptRoot` interaction
already fixed in `build_release.ps1` on 2026-08-05: `$RepoRoot` and `$ToolsDir` defaulted
to expressions over `$PSScriptRoot` **in the param block**, where `$PSScriptRoot` is still
empty under `powershell.exe -File`. Fixed the same way, by resolving in the body.

Demonstrated rather than assumed, with two minimal scripts differing only in that detail:

```
OLD shape under -File : Split-Path : Cannot bind argument to parameter 'Path' because it is an empty string.
NEW shape under -File : BODY REACHED. RepoRoot=... ToolsDir=...\signing\tools
```

Tests A through D above all ran under `-File` and reached the body, which is independent
confirmation the fix works in the real script.

### 3.7 The six documentation locations

All six from the 2026-08-04 enumeration, plus two adjacent copies of the same instruction
found while working:

| Location | Before | After |
| --- | --- | --- |
| `README.md` "Building from source" | Gave `ISCC.exe ...` as **the** build command | `.\scripts\build_release.ps1` is the build command, with the gates listed. Direct ISCC moved to a "Local dev compiles" subsection that states its output cannot be signed |
| `README.md` SmartScreen limitation | "compiled directly with ISCC.exe (skipping the signing step) is still unsigned" | "is unsigned and cannot be signed" |
| `README.md` signed-release section | "Use build_release.ps1 instead of calling ISCC.exe directly" | Describes the stamp, the override, and what the control is and is not worth |
| `CONTRIBUTING.md:8` | "Every PR must compile cleanly with `ISCC.exe ...`" | Compiling cleanly is still the PR bar; ISCC named as a local check |
| `CONTRIBUTING.md:29` | "3. Build: `ISCC.exe ...`" | Both routes, with which one is the real build command |
| `ClawFactory-Secure-Setup.iss:3` | "; Compile with: ISCC.exe ..." | "; Build with: .\scripts\build_release.ps1", plus why a bare compile cannot be signed |
| `ClawFactory_Session_Handoff_May26.md:147` | Build-command row, direct ISCC | Corrected in place, with a dated note saying what it used to say |
| `scripts/build_release.ps1` header | "For a quick local dev build ... compile with ISCC.exe directly instead" | "This is the build command, not merely the release one" |
| *(also)* `CLAUDE_ClawFactory.md:613` | Verbatim copy of the old `.iss` header | Updated to match |
| *(also)* `SUPPORT_MATRIX.md:20` | Pin-rotation answer said "recompile via `ISCC.exe`" | "rebuild via `.\scripts\build_release.ps1`" |

`CONTRIBUTING.md`'s build-prerequisites entry was also fixed. It had pointed at a
nonexistent internal doc for the rootfs source; it now carries the URL, the release, and
the digest inline, along with the instruction to use the dated URL. The same provenance
block went into `.gitignore` next to the ignore rule, which is the other place someone
looks when they wonder why a file is not in git.

---

## 4. Task 4. Rebuild

`setup.ps1` is bundled into the installer and it changed, so the artifact changed and a
rebuild was required. Run end to end through `scripts/build_release.ps1`, 66 seconds:

```
SOUL pin OK            e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
Bundle check OK        all 30 preflight resources are in [Files]
Studio pin OK          b701bfb734d5a307a41cf4b3cca8d34eb4f9c89b2116c7bc084fb180afefb7eb
Version OK             1.2.0 (.iss and setup.ps1 agree)
Persona pin OK         0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0
Workspace SOUL pin OK  441b6279f6613c313e87e9e9e034f97a220540cddbf1cf738bb9a86c37a5a257 (6677 bytes)
Rootfs pin OK          1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109
Successful compile (60.610 sec)
Build stamp written    unsigned sha256: a0ac0f008e901dc26503ff95f1697e55442d797bec1a404a918cfc7518f12d51
Build stamp OK         produced by scripts/build_release.ps1 v1.2.0 at 2026-08-05T17:51:29Z
Signing completed with status 'Succeeded' in 2.1130822s
Build stamp consumed
```

That transcript is itself the end-to-end proof of Task 3: the stamp was written by the
builder, independently verified by the signer, and consumed on success.

### 4.1 The artifact the validation session takes as input

| | |
| --- | --- |
| Path | `Output\ClawFactory-Secure-Setup.exe` |
| **sha256** | **`6f378d3ad731739e09a086e68eb898dcd446c3e6337ec8e118134ea183624bf9`** |
| Size | 440,575,752 bytes |
| Version | 1.2.0 |
| Built | 2026-08-05T17:51:33Z |

**This supersedes `54f9a9e05e7f2f05571365dbb9bb30f3e2b724f260345587e9eba69855968d37`.** That
artifact no longer exists on disk; the build overwrote it. Not tagged, per instruction.

### 4.2 Authenticode re-verification, and why it still proves nothing

| | |
| --- | --- |
| Status | **`Valid`**, "Signature verified." |
| Signer | `CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US` |
| Leaf validity | 2026-08-03T19:31:34Z to **2026-08-06T19:31:34Z** |
| Timestamp | Present. `CN=Microsoft Public RSA Time Stamping Authority` |
| Checked at | 2026-08-05T17:51:46Z |

The check ran roughly **26 hours before** the leaf expires, which is inside its own
validity window. A `Valid` result here is what an unexpired leaf produces with or without
a working timestamp, so **it does not yet demonstrate that RFC 3161 timestamping carries
this product's signature past leaf expiry.** That has still never been observed on this
product. Carried forward as the first item of the next session, which is the earliest it
can be answered.

Note the new artifact was signed by a fresh leaf (`NotBefore` 2026-08-03) that happens to
share the same 2026-08-06 expiry as the one that signed `54f9a9e0...`, so re-verifying
after that date tests the current artifact and not only the superseded one.

---

## 5. Resource ledger

| Resource | State |
| --- | --- |
| Azure VMs | **None provisioned.** No validation ran this session, by instruction |
| Azure signing operations | 1 (`OperationId 39abf287-c417-4115-9315-74cb9bef1c8a`) |
| Background tasks / monitors | None started, so none left running |
| Scratchpad | Rootfs unpack, listing, gate-test fixtures, stub compiler, `setup.ps1.pretest` backup. All under the session scratchpad, none in the repo |
| Repo working tree | Single tree on `main`. No worktrees created |
| Installed / purchased | Nothing. Inno Setup left alone, per instruction |
| `setup.ps1` tamper test | Restored and verified byte-identical (`9C6C4A57...89F8` before and after) |
| Old artifact | `54f9a9e0...` overwritten by the rebuild. `Output\...exe.PRIOR` from 2026-07-24 untouched |

---

## 6. Delta security sweep

Reviewing only what this session changed.

| Change | Assessment |
| --- | --- |
| Rootfs pin, install-time | **Improves posture.** Fails closed, throws rather than falling through. First check of any kind on this file |
| Rootfs pin, build-time | **Improves posture.** Reads the literal from `setup.ps1` rather than duplicating it, so the two cannot drift |
| Build stamp | **Improves posture against process drift only.** Forgeable by anyone who can run the signer; documented as advisory in three code comments and the README |
| `-SignWithoutBuildStamp` | **Neutral by design.** Makes an escape hatch explicit and loud instead of leaving script-editing as the undocumented one |
| Stamp consumed after signing | **Improves posture.** Prevents a later direct compile landing beside a stamp that no longer describes anything |
| `-File` fix in the signer | **Improves reliability, no security surface.** Removes a crash-before-body path |
| Stamp file contents | No secrets. Digest, version, gate names, timestamp. `Output/` is gitignored so it cannot be committed |
| Untrusted-input surface | `ConvertFrom-Json` over the stamp is the only new parse. PS 5.1 produces a `PSCustomObject`, no code execution, and the file sits in a directory the operator already controls |
| Documentation changes | No behaviour. The README now describes the stamp's limits explicitly, which is a small honesty improvement |

### 6.1 Residual, recorded not fixed

**Deleting the bundled rootfs still downgrades to a network install, silently.** The pin
lives inside `if ($BundledRootfs -and (Test-Path ...))`, so an absent tarball skips the
gate entirely and falls through to `wsl --install`. This is pre-existing and deliberate,
since the fallback is what makes the installer work where import fails.

It is worth being clear about the actual exposure, which is small. Evading the pin this
way requires **deletion**, not substitution, and the reward is a WSL install pulled from
Microsoft's and Canonical's own distribution rather than a filesystem of the attacker's
choosing. So it downgrades the guarantee from "a known image" to "an unpinned but
still-upstream image", rather than opening a path to attacker-controlled bytes. The new
`.iss` bundle check also fails the build if the rootfs stops being embedded. Not changed
this session because making absence fatal would remove a fallback that has been
load-bearing on real hardware, and that trade deserves its own decision rather than a
side effect of a pinning task.

---

## 7. Delta bug review

From an end-to-end read of the full diff.

| Finding | Severity | Disposition |
| --- | --- | --- |
| `gatesPassed` in the stamp is a hardcoded list, not derived from the gates that ran | Cosmetic | **Recorded.** It cannot be wrong today, since the stamp is only reached when every gate passed. It *can* go stale if an eighth gate is added and the list is not updated, making the stamp under-report. No security effect; the stamp's binding is the digest, not the list |
| `-SignWithoutBuildStamp` still deletes a stale stamp on success | Intentional | Correct behaviour. A stamp left beside a signed binary describes nothing |
| Stamp survives a failed signing run | Intentional | The next `build_release.ps1` overwrites it, and it is digest-bound so a stale one cannot validate different bytes |
| `$issVer` reused for the stamp's version field | None | Defined by the version gate above it, which fails the build if absent |
| `Fail` uses `Write-Error` under `$ErrorActionPreference = 'Stop'`, so `exit 1` is unreachable | Pre-existing | Behaviour is still fail-loud with a non-zero exit, confirmed in every test above. Not touched |
| Line-ending warnings on `scripts/*.ps1` (CRLF working copy, LF in git) | None | Neither script is digest-pinned, so the L-class line-ending hazard does not apply. Noted in section 8 |

No defects found requiring a fix before validation.

---

## 8. Next session: assembled-build validation

**Input artifact:** `6f378d3ad731739e09a086e68eb898dcd446c3e6337ec8e118134ea183624bf9`,
440,575,752 bytes, version 1.2.0, at `Output\ClawFactory-Secure-Setup.exe`.

### 8.1 Do this first

1. **Re-verify Authenticode, and this time it means something.** The leaf expired
   2026-08-06T19:31:34Z. Any check after that timestamp is the first real evidence that
   this product's RFC 3161 timestamping carries a signature past leaf expiry. A `Valid`
   result closes a question open since signing was wired in July. A failure is a
   signing-policy finding, not an install finding, and it is cheap to check before
   provisioning anything.
2. **Confirm the rootfs gate on a real install.** New this session and never exercised
   during an actual `wsl --import`. The install log should carry
   `Bundled rootfs SHA-256 = 1483cc5c... (matches the build-time pin)`. Its absence means
   the bundled path was skipped and the box installed from the network, which would make
   every downstream result a measurement of a different filesystem.
3. **Then the deferred Task 5 limit from the last build session:** confirm all 30 preflight
   resources land on disk and `Step-Preflight` passes, verified by unpack rather than from
   the compiler's own record.

### 8.2 Full carried-forward test list

| Test | Card | Origin | Note |
| --- | --- | --- | --- |
| **Authenticode valid past leaf expiry** | | this session | **Run first.** Only answerable after 2026-08-06T19:31:34Z |
| Rootfs pin observed on a real install | | this session | New gate, never seen on a live import |
| All 30 preflight resources land; `Step-Preflight` passes | | 2026-08-05 build | Was verified from the compiler's record, not an independent unpack |
| Studio payload reaches the customer profile; both new panels reachable | | 2026-08-05 build | First build carrying them. Exercise the approvals card and Recently-deleted, do not merely confirm presence |
| Guard 1 routing on a real agent turn | | earlier | Routing advisory, hold structural. Never run on a clean box |
| External SMTP delivery | **#198** | earlier | Guard 2 send path end to end, real server |
| SOUL discoverability | **#199** | earlier | |
| Nested-channel audit | **#200** | earlier | |

### 8.3 Also carried forward, not tests

| Item | Priority |
| --- | --- |
| Inno Setup commercial licence. Settled as a purchase Bret will make; gates nothing | Before public release. Business decision |
| Verify Canonical's `SHA256SUMS.gpg` signature on the rootfs digest | Low. Would close the last link in the provenance chain |
| Bump Studio's own version so the filename carries provenance | Medium |
| `ClawChat.exe` still carries no build-time pin (audit row 7, same class as L26) | Medium |
| `eol=lf` for `clawfactory-proxy.js` and the `.service` files; consider `*.ps1 text eol=lf` | Low, consistency |
| `VersionInfoVersion` unset, so `FileVersion` is blank | Low, cosmetic |
| Reproducibility on a second machine: the rootfs blocker is now **closed**, the signing-credential and signed-artifact blockers remain | Recorded, not scheduled |

Section 3.3 of the previous close-out listed four reasons this build was not reproducible
on a second machine. The rootfs, described there as "the single largest gap", is now
answered: a second machine can fetch a known-correct copy from a published URL and verify
it against a published digest. The remaining three are unchanged.

---

## 9. Lessons learned

`ClawFactory_Install_Lessons_Learned.md` gained **L26, "a large opaque dependency admitted
early is inherited by every control built on top of it"**, written for the shape rather
than for this file: large enough that git cannot hold it, opaque enough that nobody opens
it, admitted before the controls existed so it reads as background, working so it never
prompts a look, and foundational so it is the last thing suspected. Every one of those
properties makes a dependency more important to pin and less likely to get pinned.

The rule it lands on is that a dependency you cannot read gets its provenance recorded in
the same commit that admits it. Recovering it four months later took unpacking the
archive, dating it from `dpkg/status` and the apt history, recognising `ubuntu-wsl` and
`wsl-setup` as the WSL image's signature packages, and locating the matching dated
upstream build. That was a session of work to recover what was one URL at the time.

---

## 10. Task accounting

| Task | Status | Evidence |
| --- | --- | --- |
| 1. Identify the rootfs | **DONE** | Section 1. Outcome 1, exact published-digest match |
| 2. Pin what was adjudicated | **DONE** | Section 2. Seven-gate build plus install-time refusal, proven four ways |
| 3. Close the build-gate bypass | **DONE** | Section 3. Tests A to E; six doc locations plus two adjacent, corrected |
| 3b. `-File` defect in the signer | **DONE** | Section 3.6, demonstrated against the old shape |
| 4. Rebuild and re-verify | **DONE** | Section 4. New digest recorded; signature `Valid` but not yet probative |
| Lessons learned entry | **DONE** | Section 9, L26 |
| Verify `SHA256SUMS.gpg` | **DEFERRED** | Section 1.3. Needs a download; offered rather than claimed |
| Make rootfs absence fatal | **DEFERRED** | Section 6.1. Removes a load-bearing fallback; deserves its own decision |

Nothing dropped silently. Out of scope and not done, per instruction: no install, no
validation suite, no Studio version bump, no Guard 3 or 4, no Studio restyle, no
customer-facing copy, no Inno Setup licence purchase, no tag.

---

## 11. Git

`git status --short` run first; tree was clean at `6909d47`. Explicit per-file staging
throughout, no `git add -A`, no `git worktree add`, single working tree on `main`.

The Studio repo was checked and is **clean at `14b6422`** with no changes this session, so
only `ClawFactory-Secure-Setup` is pushed.
