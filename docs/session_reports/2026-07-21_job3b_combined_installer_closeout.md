# JOB 3B — the combined ClawFactory v1.1.0 installer — close-out

*2026-07-21. Authoring/build session, NO cloud VMs. Repo (write):
`ClawFactory-Secure-Setup`. Read-only reference: `ClawFactory-Studio` @ `9d62ad0`.
Model: Sonnet recommended; run on Opus 4.8 (flagged — build+harness verified by ISCC
compile, `Get-AuthenticodeSignature`, AST parse, and an in-session render test, all
model-independent). Produced ONE signed combined installer that installs the sandbox,
the agent, AND Studio in a single download / single consent flow, plus the adapted
JOB 3C validation driver. **The tag is PREPARED but NOT applied; NO VM was
provisioned; 3C is a separate fresh session.** Dispatch card #151 commented
"3B integration starting".*

---

## Artifact verification (hash + Valid, both the embedded INPUT and the OUTPUT)

**Embedded INPUT — signed Studio installer (verified, never trusted from the pin alone):**

```
name:   ClawFactory-Studio-Setup-1.1.0.exe   (from ClawFactory-Studio\desktop\release, @9d62ad0)
size:   100,022,000 bytes                     MATCH
sha256: D5FF8370943194C2643674DDBA98E917CA61865CE127EC424A1CB37C746D45A7   MATCH
sig:    Valid   CN=Bret Mckinney   RFC3161-timestamped (Microsoft Public RSA Time Stamping Authority)
```

Both hash AND `Get-AuthenticodeSignature = Valid` were checked before embedding, and
**re-verified after copying** into `resources\` (the copy is never trusted). Why both:
the hash proves *which bytes*; the signature proves those bytes are *signed and
trusted* — independent facts, and the Studio signing gate is graceful (an unsigned
rebuild is silent), so verification is the only way to know we hold signed bytes. The
Studio leaf cert `NotAfter` is 2026-07-22, but the RFC3161 timestamp pins the signing
time inside the validity window, so it stays Valid past expiry (by design).

**OUTPUT — the combined v1.1.0 installer (the 3C pin):**

```
name:   ClawFactory-Secure-Setup.exe  (Output\; staged to 3C as ClawFactory-Secure-Setup-v1.1.0.exe)
size:   440,526,496 bytes             (was 340,595,512 at v1.0.48; +~100 MB embedded Studio)
sha256: FFE86406DF651B27BA6EC4D22563E2391BAA4BF77F4454FF3889D70DC16E3AED
sig:    Valid
subject:CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US
issuer: CN=Microsoft ID Verified CS AOC CA 04, O=Microsoft Corporation, C=US
valid:  NotBefore 2026-07-20 12:14:42Z  NotAfter 2026-07-23 12:14:42Z  (3-day Azure leaf, rotates)
tsauth: True  (Microsoft Public RSA Time Stamping Authority)   thumbprint D3E2E431D1AB94A48360BEA45A6535876C17AE1F
```

Compiled with ISCC (Inno Setup 6, "Successful compile (59.094 sec)"), signed via the
established `scripts\sign_installer.ps1` (Azure Artifact Signing: signtool + dlib,
`Signing completed with status 'Succeeded'`, 0 errors). Signing was a single expected
call to the Azure signing service.

---

## The elevation implementation (Task 2) — search-first

**Search-verified facts** (current Inno docs, not training assumptions):
- `[Run]` entries are processed **BEFORE** `CurStepChanged(ssPostInstall)` fires
  ([willjusticeprevil.blogspot.com](http://willjusticeprevil.blogspot.com/2014/08/inno-setup-is-run-section-processed.html),
  [jrsoftware.org event functions](https://jrsoftware.org/ishelp/topic_scriptevents.htm)).
  So at `ssPostInstall` the core `setup.ps1` (a `[Run]` entry) has already finished —
  **core first, Studio last**, with no change to `setup.ps1` or its reboot/resume
  `[Run]` entry.
- `ExecAsOriginalUser(File, Params, Dir, Show, Wait, var ResultCode)` runs a program
  as the (normally non-elevated) user who started Setup, and returns a ResultCode
  ([jrsoftware.org ExecAsOriginalUser](https://jrsoftware.org/ishelp/topic_isxfunc_execasoriginaluser.htm)).
- electron-builder NSIS: `oneClick:false`, `perMachine:false`, `allowElevation:false`
  → per-user install to `%LOCALAPPDATA%\Programs\ClawFactory Studio`, silent via `/S`,
  **no UAC** ([electron.build NSIS](https://www.electron.build/docs/nsis/)).

**Implementation** (`ClawFactory-Secure-Setup.iss`): a new `[Files]` entry embeds the
signed Studio installer, extracted to `{app}\stage` (Program Files, world
Read+Execute — NOT `{tmp}`, which under an elevated Setup is the elevating admin's
temp and unreadable to a *different* original user: the kitchen-table bug). A new
`CurStepChanged(ssPostInstall)` → `InstallStudioComponent` gates on the core's
`install-result.txt = 'success'` (skips a pre-reboot pass; lets the core's own
failure reporting stand if the core failed), then runs
`ExecAsOriginalUser(<staged exe>, '/S', ...)` so Studio lands in the **customer's**
profile, not the admin's. It is **NOT** `deleteafterinstall` (whose timing vs
`ssPostInstall` is undocumented) — the procedure consumes then `DeleteFile`s the
staged exe itself. Version metadata bumped 1.0.48 → **1.1.0**.

**Failure honesty:** a nonzero Studio exit — or a failure to even launch it —
`RaiseException`s, which shows the message and rolls the install back. No
partial-success, no "finished with warnings."

**Compile gotcha caught + fixed in-session:** the first compile aborted (Pascal
syntax error) because a `{ }` brace comment contained the token `{app}` — Inno
brace-comments don't nest and end at the first `}`, closing the comment early (the
same reason `CurUninstallStepChanged` already uses `//` lines). All new comments were
converted to `//`; recompile succeeded.

## The uninstall implementation (Task 3) — search-first, structural path exists

**Search-verified:** `ExecAsOriginalUser` is **NOT supported at uninstall time /
`[UninstallRun]`**
([documentation.help ExecAsOriginalUser](https://documentation.help/Inno-Setup/topic_isxfunc_execasoriginaluser.htm)) —
confirming the prompt. So the elevated uninstaller cannot de-elevate the same way.

**Decision (A): a clean structural path exists for the shipping scenario, so proceed
(no STOP).** `resources\uninstall.ps1` gains an isolated, tolerant, honest Step 4.5
that locates the per-user Studio uninstaller and runs it silently. In the shipping
target — Windows Home, one admin who is also the installing user — an elevated process
of that same account shares the account's HKCU and `%LOCALAPPDATA%`, so it removes
Studio fully. It gathers candidates from (1) the installing user's HKCU Uninstall
entry (authoritative — uses whatever flags electron-builder registered), (2) the
current user's install dir, and (3) a best-effort scan of every user profile. It
verifies against the install dir and **logs honestly** — if Studio is not found it
*says so* rather than claiming a clean removal.

**Residual (documented, not hidden — the tradeoff):** if a *different* admin account
uninstalls while the customer's Studio lives in another profile's HKCU, the
registry lookup won't find it (the profile scan still catches the files). This is
symmetric with the install-side elevation model (same-account assumed). A
scheduled-task-as-interactive-user approach would close the cross-account gap but adds
failure modes (no-interactive-user, multi-user) out of proportion to v1.1.0 — carded
for a future harness iteration rather than shipped half-built.

## Harness delta (Task 5) — derived from the JOB 2 lineage

**Choice: COPY, not share.** JOB 3C runs from `ClawFactory-Secure-Setup` and must be
self-contained; the Studio repo is a read-only reference, never a runtime dependency.
So the proven JOB 2 machinery was copied into `validation\` and adapted. New files:

- `validation\job3-validate.ps1` — driver. Stages **only** the combined installer
  (+ probe + adversarial suite); preflight verifies the combined **hash AND
  Authenticode = Valid** (an unsigned graceful-gate build is a silent ship-blocker).
  All JOB 2 evidence machinery carries over unchanged: producer transcript + sentinel
  (`JOB3_PROBE_COMPLETE`), evidence-before-teardown gate (512-byte floor), both
  channels, resumable state, standalone teardown, L2–L21 rules.
- `validation\job3-probe.ps1` — VM-side. Installs the **single** combined installer
  (core first, Studio last); runs the functional matrix (cells 1–5, semantics
  unchanged, incl. the F1 fresh-marker revoke decontamination) + the adversarial
  suite. **Two NEW cells:** (A) Studio landed in the invoking user's `%LOCALAPPDATA%`
  (reports identity, `EnableLUA`, elevation, resolved path, and a per-profile scan so
  a stray copy in another profile is caught); (B) the installed Studio exe + its
  uninstaller verify `Get-AuthenticodeSignature = Valid` on the VM. The `Wsl` helper
  carries the F2 CR-strip (L21).
- `validation\wrapper-builder.ps1` — `Build-Job3CmdLines` (single `-CombinedExe`; the
  one-joined-line + 4-line Count guard that killed the cfv-149 evidence-loss defect) +
  `Test-Job3Evidence`.
- `validation\job3-teardown.ps1` — VM-name-generic L3/L10 teardown.
- `validation\test-wrapper-render.ps1` — extended render test.

**Dropped cell — cited, not silently omitted:** the JOB 2 **engine-absent** cell
(Studio with no grant engine present) is impossible in the combined flow — the core
(grant engine) always installs before Studio. Its standing proof is **cfv-150 /
cfv-151** (JOB 2), cited in the probe header and in the combined-delta note. The
Studio-*isolated* 0-service/0-firewall footprint is likewise cited from cfv-150/151
(it can't be isolated when core+Studio install together); the probe still reports the
combined delta and runs the live no-listener / :8080-refused / ungranted-read checks.

### Render test — verbatim PASS (in-session, no VM)

```
--- 1. wrapper cmdLines structure (combined installer) ---
PASS  cmdLines has exactly 4 elements (cfv-149 produced 6)
PASS  probe line contains the probe script path
PASS  probe line passes the SINGLE combined installer (-CombinedExe)
PASS  probe line has NO separate -StudioExe (combined flow)
PASS  probe line has NO separate -SecureExe (combined flow)
PASS  probe line contains -LicenseKey on the SAME line
PASS  probe line contains the redirect on the SAME line
PASS  on that line, -LicenseKey precedes the redirect (one command)
PASS  NO array element is a bare '-LicenseKey...' fragment (the cfv-149 signature)
PASS  line 0 is @echo off
PASS  line 3 writes JOB3_DONE
--- 2. evidence-before-teardown gate (JOB3 sentinel) ---
PASS  gate REJECTS the ~102-byte cfv-149 dead bundle
PASS  gate ACCEPTS a plausible bundle WITH the JOB3 sentinel
PASS  gate REJECTS a big bundle with NO sentinel
PASS  gate REJECTS a JOB2 sentinel (must be JOB3_PROBE_COMPLETE)
PASS  gate REJECTS a sentinel-only file below the 512-byte floor
PASS  gate ACCEPTS when EITHER channel is valid (redundancy)
PASS  gate REJECTS when both channels are missing
--- 3. probe: COMBINED single-installer flow ---
PASS  probe installs the SINGLE combined installer ($CombinedExe)
PASS  probe has the '1. INSTALL COMBINED' step
PASS  probe does NOT run a separate Secure-Setup install (-SecureExe)
PASS  probe does NOT run a separate Studio install (-StudioExe)
PASS  probe emits the JOB3_PROBE_COMPLETE sentinel via Finish
PASS  probe Wsl helper strips CR before base64 (F2 / L21)
--- 4. probe: NEW CELL A (elevation rule -- Studio in invoking user profile) ---
PASS  extracted CELL A block
PASS  CELL A resolves Studio under the invoking user's %LOCALAPPDATA%
PASS  CELL A asserts Studio present in THIS user's profile
PASS  CELL A does a per-profile scan (no stray copy in another profile)
PASS  CELL A reports EnableLUA + elevation (conditions explicit)
PASS  CELL A flags a wrong landing as a CONCERN
PASS  CELL A writes its progress marker
--- 5. probe: NEW CELL B (installed Studio binaries Authenticode Valid) ---
PASS  extracted CELL B block
PASS  CELL B calls Get-AuthenticodeSignature on the installed binaries
PASS  CELL B checks Status -ne 'Valid' and flags a CONCERN
PASS  CELL B also verifies the uninstaller binary
PASS  CELL B writes its progress marker
--- 6. probe: engine-absent cell DROPPED (cited, not silently omitted) ---
PASS  probe does NOT run the JOB2 engine-absent read (rEngineAbsent)
PASS  probe has NO live ENGINE_ABSENT marker
PASS  probe CITES cfv-150/151 as the engine-absent standing proof
PASS  probe explains WHY engine-absent is impossible in the combined flow
--- 7. probe: functional matrix + F1 revoke decontamination carried over ---
PASS  extracted the CELL 4 block from the probe
PASS  probe generates a FRESH post-revoke marker (CANARY-A2)
PASS  cell 4 A-revoked read targets marker2.txt (fresh, unseen)
PASS  cell 4 does NOT re-read A's original marker.txt (cfv-150 contamination)
PASS  cell 4 keeps the independent NO-MOUNT check
PASS  cell 4 keeps the B-control read (idB/marker.txt)
PASS  cell 4 flags a fresh-marker readback as an ANOMALY
PASS  matrix keeps the granted read at /workspaces/<grant-id> (L19)

ALL RENDER TESTS PASSED
```

All six new/modified `.ps1` files also AST-parse clean (`[Parser]::ParseFile` → 0 errors).

## .gitattributes hardening (Task 6)

Added `*.ps1 text eol=lf` for defense-in-depth (no future multi-line bash in a `.ps1`
regresses on CRLF), with the runtime CR-strip kept as belt-and-suspenders. `setup.ps1`
contains a lone NUL byte (inside a comment about NUL bytes) so git auto-detects it as
binary and ships it that way — it is UNTOUCHABLE product logic, so it is explicitly
kept `binary`. Verified: after `git add --renormalize .`, `setup.ps1`'s index blob is
**byte-identical** (`fb789816…` unchanged, not staged); all other tracked `.ps1` are
`i/lf` and the working tree agrees (no phantom diff). The same change is carded for the
Studio repo (read-only here).

---

## END-OF-SESSION GATE

### 1. Task accounting
Comprehension gate — DONE. Preamble (both repos clean @ `9741b74` / `9d62ad0`, artifact
hash+Valid, close-outs read, card commented) — DONE. Task 2 (.iss elevation + fail-loud)
— DONE. Task 3 (uninstaller, decision A) — DONE. Task 4 (build + sign + verify) — DONE.
Task 5 (harness) — DONE, render test green. Task 6 (.gitattributes) — DONE. Task 7
(commit/push + this close-out) — DONE. **DEFERRED by design:** the git tag (applied only
after cfv-152 grades clean) and the 3C validation run. **CARDED:** the Studio-repo
`.gitattributes` change; the cross-account uninstall closure. No silent drops.

### 2. Resource ledger
**ZERO cloud VMs.** One expected Azure Artifact Signing call (signed the combined
installer, Succeeded). Local artifacts: `Output\ClawFactory-Secure-Setup.exe` (440.5 MB,
signed — the 3C pin, gitignored); `resources\ClawFactory-Studio-Setup-1.1.0.exe`
(staged, gitignored); scratch build logs under the session scratchpad.

### 3. Delta security sweep
No credential VALUES in any diff, commit, or this report — the API key is seeded
machine-to-machine as base64 and never printed (harness), and signing creds are read
by name only. **Nothing widens product permissions:** the .iss addition runs the Studio
sub-install *de-elevated* (lower privilege, not higher) and fails loud; the uninstaller
step only removes files/registry it can already reach. **Product logic untouched:**
`setup.ps1` byte-identical (index hash unchanged); the write surfaces are the `.iss`
packaging layer, `uninstall.ps1`'s isolated Step 4.5, and the new `validation\` tooling.

### 4. Delta bug review
Diff re-read. The render test is the load-bearing local evidence (36/36 PASS) and the
ISCC compile + `Get-AuthenticodeSignature` prove the installer builds and is signed. The
`{app}`-in-brace-comment compile abort was caught and fixed in-session. The
`deleteafterinstall` timing ambiguity was avoided by manual deletion. The `setup.ps1`
NUL-byte binary status was diagnosed before the renormalize and explicitly excluded.
Out-of-scope items (cross-account uninstall, Studio-repo `.gitattributes`) carded, not
patched.

---

## READY for JOB 3C

**READY.** Pin the SIGNED combined installer:

```
ClawFactory-Secure-Setup.exe   (upload as blob ClawFactory-Secure-Setup-v1.1.0.exe)
sha256: FFE86406DF651B27BA6EC4D22563E2391BAA4BF77F4454FF3889D70DC16E3AED
size:   440,526,496 bytes      signature: Valid (CN=Bret Mckinney, timestamped)
```

Run 3C in a fresh session (provisions cfv-152, one clean box):

```
cd C:\Users\bmcki\ClawFactory-Secure-Setup ; .\validation\job3-validate.ps1 -VmName cfv-152
```

The driver's preflight re-verifies the pinned hash **and** the signature against the
local `Output\ClawFactory-Secure-Setup.exe` (a rebuild would change the bytes → the
pin catches it). The tag is prepared but applied only after cfv-152 grades clean. Do
NOT provision, tag, or start 3C from this session.
