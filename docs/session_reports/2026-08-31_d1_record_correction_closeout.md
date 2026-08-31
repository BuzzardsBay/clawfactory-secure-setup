# D1 record correction, rebuild, and a one-row re-take — close-out

**Date:** 2026-08-31. **Repo root:** `C:\Users\bmcki\ClawFactory-Secure-Setup` (confirmed by
`git rev-parse --show-toplevel`). **Branch:** `main`. **Starting commit:** `a7b7f6b`, tree clean.

**PROMPT 15 preamble:** pasted from `docs/VALIDATION_PREAMBLE.md` in full. **No clauses were
deleted** — this job provisioned a box, so every clause applied.

**No code behaviour changed.** The only change to a shipped file is 84 added comment lines in
`setup.ps1`, proved comment-only mechanically.

**§1 through §10 were written when nothing had been signed, stamped, tagged or written to the
ledger. The operator then asked for signing, the ledger row and the tag in the same session, so
all three were done and are recorded in §11. He then published the release himself from a card,
and §11.5 records that.** Where §1 and §8 still read as though signing were a future job, they
are marked rather than rewritten, so the order in which things were learned stays visible.

**v1.4.5 is PUBLISHED and is the Latest release.**

---

## 1. Verdict

**DONE, AND FIT TO SIGN — with one new finding that changes how the signing job must be
sequenced, and which the operator has already decided.**

The record is corrected, the artifact is rebuilt, and the one row was re-taken on one fresh
stock box. **`PR.C7` PASS. `PR.C12` PASS.** Phase exit 0, three positive controls fired, two
preconditions met, 13 of 13 rows counted.

**The shipping candidate is `5ab7a0b545d1aa8a2380a73561415cac290abca5c85a04ff7af754acbafc68d7`,
440,604,218 bytes, unsigned, unstamped.**

**The new finding: the Inno compile is not byte-deterministic across days.** Identical input
compiled twice on the same day is byte-identical; the same input compiled on 2026-08-30 versus
2026-08-31 differs by 6 bytes and a different digest. `scripts/build_release.ps1:644` asserts
*"the compile is deterministic (measured 2026-08-05)"* — true within a day, false across days.
Because `build_release.ps1` always recompiles, a signing job run on a later day than its
validation ships bytes that were never validated. **The operator's decision, taken during this
session: the signing job runs today.**

> **That last sentence was wrong, and the signing build in the same session proved it.** Running
> today did **not** reproduce the validated bytes. The compile embeds build-time metadata, so
> `build_release.ps1` — which always recompiles — can **never** reproduce a previously validated
> artifact. See the superseding block in §3.4 and the signing record in §11. What the release
> rests on is *same commit, same gates, and a measured 2,592-byte build-metadata difference*,
> not byte identity.

**A bonus the re-take produced that was not asked for.** The whole D1 finding was reproduced
independently on a second box, *by the shipped product's own logging*, and the log is quoted
verbatim in §5.3. That is stronger evidence for the corrected comment block than the comment
block's own citation.

---

## 2. TASK 1 — the record is corrected

Every correction states what was claimed, what was measured, and what is true now. **Nothing
was deleted anywhere.** Superseded text is kept in place and marked, because an audit trail
that quietly rewrites itself is worth less than one that shows the change.

| File | Change | Lines |
|---|---|---|
| `setup.ps1` | 3 D1 sites superseded: the `Test-WslRebootPending` block, the first-run call site, the resume loop guard | +84 / −0 |
| `docs/V1_5_BACKLOG.md` | D1 claim superseded; **item 8** (rewrite D1) and **item 9** (`Restart-Computer` fall-through) added; WSL1 census gains the two `README.md` rows | +132 / −0 |
| `docs/session_reports/2026-08-30_v145_install_path_fixes_closeout.md` | §3.8 superseded + a top banner | +57 / −0 |
| `docs/FAILURE_CATALOGUE.md` | **Class 15 / entry 15.1**, practice **rule 26** | +104 / −0 |
| `docs/reference/BASELINE_IMAGES.md` | 3 corrections + **OM-B1** + the instrument caveat | +82 / −0 |
| `docs/VALIDATION_PREAMBLE.md` | card-format rules into the paste block; **OM-2** files `PR.C8`; OM-1 marked still open | +97 / −2 |

### 2.1 The comment change is proved, not asserted

`validation/token-diff-ps1.ps1` tokenises both versions with `PSParser`, strips `Comment` and
`NewLine` tokens, and compares the remaining sequence. It is calibrated in **both** directions
in the same invocation, per the catalogue's own rule that an audit instrument is itself a probe:

```
CONTROL 1  orig vs orig            : IDENTICAL (7615 code tokens)
CONTROL 2  orig vs planted CODE    : DIFFERENT (token 891 : 'String|EnablePending' vs 'String|ZnablePending')
CONTROL 3  orig vs planted COMMENT : IDENTICAL (7615 code tokens)
SUBJECT    orig vs edited setup.ps1: IDENTICAL (7615 code tokens)
```

**7,615 code tokens before and after. No condition, branch or string literal moved.**

Corroborated three further ways: `git diff --numstat` reads `84 0` (zero deletions); a
line-level filter for any changed line that is *not* an added comment returns empty; and the
build's own **worktree gate** confirmed all 54 tracked `[Files]` resources are byte-identical
to their committed form, which is what proves the *bundled* `setup.ps1` is the corrected one.

### 2.2 The diff, in full

Three hunks, all pure additions: 63 + 7 + 14 = 84.

```
@@ -313,6 +313,69 @@ function Test-WslRebootPending {
@@ -1118,6 +1181,13 @@ function Step-EnsureWsl {
@@ -1172,6 +1242,20 @@ function Step-EnsureWsl {
```

The first block states that `VirtualMachinePlatform` reads `Enabled` both before and after the
restart on Windows 11 24H2, that `EnablePending` was never observed, that the gate therefore
does not fire on the first-run path, and that the branch it guards is made unreachable by
`Update-WslEngine` running first. It names the two working signals — CBS `RebootPending`
(`True` → `False` across the restart) and `wsl --status`'s *output* while it exits zero — and
it says in the words of the finding how this came to be believed: *a probe is calibrated
against a rigged input; a run is not.*

The third block supersedes the specific false sentence *"This is the branch the first external
install took."*

### 2.3 `docs/FAILURE_CATALOGUE.md` — why a new class rather than 10.7

I first wrote the forward references as "entry 10.7" and then changed them, because Class 10 is
*an instrument carrying the defect it audits* and this instrument was clean. Class 11 is *a
correct probe run in the wrong order*, and this probe was never run at all — its absence was
correctly recorded. What is new is the **substitution**: a signal was rejected for a good
reason (an English-sentence gate breaks on non-English Windows), and the substitute was then
verified only against itself. **The rejected signal was measured against reality; the chosen
one never was.** That is Class 15, and practice rule 26 follows from it.

### 2.4 The preamble's fencing

The card-format spec contains fenced examples, so pasting it inside the existing three-backtick
paste block would have terminated that block early. **The paste block's own fence is now four
backticks; the inner examples stay at three** and render as copyable boxes inside it. Audited
after the edit: exactly two lines of four-or-more backticks in the file, and they are the paste
block's opening and closing bounds (lines 48 and 341). The other fenced blocks in the file sit
outside the paste block and were not touched.

---

## 3. TASK 2 — the rebuild

### 3.1 Gate set, run from the real script text truncated before the compile

```
SOUL pin OK: e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
Bundle check OK: all 34 preflight resources are in [Files].
Interpolation gate OK: 10 shipped .ps1 files parse, and none interpolates a variable the file never defines.
Worktree pin OK: all 54 tracked [Files] resources are byte-identical to their committed form.
Studio pin OK: ac5937516e7edbb5aac00433bfa6e5074449cbc28b132883099391639e1e7dca
Version OK: 1.4.5 (.iss and setup.ps1 agree)
Ledger OK: released-versions.tsv carries 12 prior artifact row(s).
Persona pin OK: 0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0
Workspace SOUL pin OK: 441b6279f6613c313e87e9e9e034f97a220540cddbf1cf738bb9a86c37a5a257 (6677 bytes composed)
Rootfs pin OK: 1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109
EXIT = 0
```

**The count I observed, as three numbers because they are three different things:**

| Measurement | Observed |
|---|---|
| `gatesPassed` array literal entries | **9** |
| `^# --- Pre-build gate:` headers | **8** — one header at `:527` covers two gates |
| `OK` lines printed by the run | **10** — the version gate prints twice |

Two gates cannot run before a compile exists and did not run here: the version gate's
enforcement half and the build stamp. Both run in the signing job.

**The commit ordering is load-bearing and the prompt did not state it.** The worktree gate
compares bundled bytes against *committed* bytes, so `setup.ps1` had to be committed **before**
the build, not after. It was.

### 3.2 The artifact

```
path    : Output\ClawFactory-Secure-Setup.exe
bytes   : 440604218
sha256  : 5ab7a0b545d1aa8a2380a73561415cac290abca5c85a04ff7af754acbafc68d7
compile : ISCC.exe, successful in 50.344 sec, exit 0
stamp   : ABSENT   (correct — this is what "no signing in this job" means structurally)
signature status : NotSigned
released-versions.tsv : still 12 rows, no 1.4.5 row
```

**The prior artifact was preserved before `Output\` was overwritten**, exactly as the last build
job did with the signed v1.4.4 asset: `Output\ClawFactory-Secure-Setup-1.4.5-prior-8a035fad.exe`,
verified byte-identical to the validated `8a035fad…`. The signed v1.4.4 asset and the July
`.PRIOR` were not touched.

### 3.3 The delta, and the control that was needed to measure it

The naive delta against the 2026-08-30 artifact is **+6,286 bytes**. That number is wrong,
and finding out why produced §3.4.

| Compile | Bytes | Digest |
|---|---|---|
| `1c97b47` tree, 2026-08-30 | 440,597,932 | `8a035fad…` |
| `1c97b47` tree, today, run 1 | 440,597,938 | `4dfe0265…` |
| `1c97b47` tree, today, run 2 | 440,597,938 | `4dfe0265…` |
| **corrected tree, today** | **440,604,218** | **`5ab7a0b5…`** |

**Against a same-day control of the identical tree the real delta is +6,280 bytes**, for
**+5,186 raw bytes** of added comment text (`setup.ps1` grew 233,658 → 238,844).

The ~1,094-byte excess over the raw addition is solid-stream re-alignment. The `.iss` sets
`Compression=lzma2/ultra64` and `SolidCompression=yes`, so the whole 440 MB archive — dominated
by an already-gzipped 258 MB rootfs — is one LZMA2 stream, and inserting 5,186 bytes at
`setup.ps1`'s position shifts every downstream byte's alignment in the encoder. A drift of
0.00025% of the archive is ordinary. **Only `setup.ps1` changed among bundled files**: the other
six changed files are not in the `.iss` `[Files]` section, checked by execution rather than by
memory.

**Verdict on the prompt's challenge question: the delta is fully explained.**

### 3.4 NEW FINDING — the compile is not byte-deterministic across days

Two compiles of the identical tree minutes apart on the same day are **byte-identical**. The
same tree on the previous day differed by 6 bytes with a different digest. So the variance is
coarser than minutes and changes at least daily — almost certainly an embedded compile date
string, compressed. *(That mechanism is INFERRED. What is measured is: same-day identical,
cross-day different. Two compiles eight hours apart on one day were not taken.)*

**Why it matters.** `sign_installer.ps1` refuses anything `build_release.ps1` did not stamp,
and `build_release.ps1` always recompiles. A signing job run on a later day than its validation
therefore produces different bytes, stamps and signs *those*, and writes *that* digest to the
ledger — so the bytes validated on a box would not be the bytes shipped. That is the exact
premise this job existed to protect, and it has silently been true for every release of this
product. Every phase of the last validation run carried the digest as a refuse-on-mismatch
precondition, so this would eventually have surfaced as a confusing mid-run VOID rather than as
a finding.

**Resolved for this release by sequencing, not by code:** the operator confirmed the signing
job runs today. Recorded so the next cycle does not rediscover it.

> **SUPERSEDED THE SAME DAY, BY THE SIGNING BUILD. The paragraph above is WRONG and is kept
> rather than deleted.**
>
> **Claimed above:** that the compile is byte-deterministic *within* a day, and that running
> the signing job today would therefore reproduce the validated bytes.
>
> **Measured:** it did not. `scripts\build_release.ps1`, run at 15:43 UTC on the same day from
> the same commit with all nine gates passing, produced
> **`28e14e56e217b73d4e391c85700f5127afefa8866fc8a81c66897bc7e0158c08`**, 440,604,218 bytes —
> the same size as the validated `5ab7a0b5…` and a different digest.
>
> **What the difference actually is**, measured by byte comparison rather than inferred:
>
> ```
> differing byte positions : 2526
> contiguous span          : 2592 bytes at offset 0x1A310426 (439,419,942)
> everything else          : byte-identical across all 440,604,218 bytes
> ```
>
> **0.0006% of the file, in one region near the end.** The entire 258 MB rootfs, all 54 bundled
> resources and `setup.ps1` itself are identical. The differing bytes are high-entropy, which is
> what a compressed block looks like when a few plaintext bytes inside it changed. A third
> compile minutes after the signing build reproduced `28e14e56…` **exactly**.
>
> **So the granularity is finer than a day and coarser than minutes.** Compiles ~3 minutes apart
> reproduce each other; compiles ~80 minutes apart do not. I am not naming the mechanism this
> time. What is measured is the above; the earlier "embedded compile date string" guess was a
> mechanism asserted from two data points and it did not survive the third.
>
> **The real conclusion, and it is larger than the one it replaces.** `build_release.ps1`
> recompiles at signing time, and the compile embeds build-time metadata. So the signed artifact
> is **never** byte-identical to a previously validated one — not "when the day rolls over",
> but always. *Validated bytes equal shipped bytes* is **not achievable through this route at
> all**, and sequencing does not fix it. It has been silently true for every release of this
> product.
>
> **What does hold, and what the release therefore rests on:** the signed artifact and the
> validated artifact were built from the identical commit, with all nine gates passing, and the
> worktree gate proved the bundled bytes were the committed bytes in both builds. They differ
> only in a 2,592-byte build-metadata region. The *product* is identical; the *bytes* differ in
> metadata. That is a defensible basis for shipping and it is a weaker claim than the one this
> job set out to make, so it is stated in the weaker form.
>
> **Owed:** either a `build_release.ps1` path that stamps and signs an existing validated
> artifact instead of recompiling, or an explicit, documented acceptance that the release
> contract is *"same commit, same gates"* rather than *"same bytes"*. Filed in §9. **Not fixed
> here** — it is a change to the build script and outside this job.

---

## 4. TASK 3 — the re-take

### 4.1 The box

| | `cfv-190` |
|---|---|
| Image | **stock** `MicrosoftWindowsDesktop:windows-11:win11-24h2-pro:26100.9168.260809` — the exact version `cfv-186` ran, pinned to remove a variable |
| Size / region | `Standard_D2s_v4`, `westus2`, non-zonal, `securityType` unset (Standard) |
| Network | created `--nsg-rule NONE`, so nothing was reachable; RDP rule scoped to `67.164.251.99/32` attached before any address was live, verified by read-back |
| Steps its image had already performed | **none** |
| Artifact digest verified on box after download | `5ab7a0b5…` — **matches** |

### 4.2 `PR.CTL0` — the state under test existed

```
PRE_VMP=Disabled  PRE_WSL=Disabled  PRE_HYP=Disabled
```

`PR.CTL0` **PASS**, recorded at 15:18:19 before the installer was launched. A baked box reads
`Enabled` and the state under test cannot exist on it.

### 4.3 Both rows, machine-scored

```
SC.PRE.1   PASS   the scored copy of install.log IS the bytes on the box
SC.PRE.2   PASS   install.log is a COMPLETE run, not a truncated one
SC.PRE.3   PASS   this log was produced on a box in the state under test
SC.CTL1    PASS   POSITIVE CONTROL: the fault landed
SC.CTLS    PASS   POSITIVE CONTROL: search target is searchable
PR.C7      PASS   v1.4.5 stops with a named, actionable message and NOT the clawuser-stub error
SC.CTLN    PASS   POSITIVE CONTROL: the NUL byte scanner works in BOTH directions
PR.C12     PASS   install.log carries no NUL bytes

PASS=8 FAIL=0 VOID=0 INFO=5  (counted 13 of 13 recorded rows)
positive controls registered=3 fired=3 ; preconditions declared=2 met=2
PHASE VERDICT: PASS.        SCORE_PROBE_COMPLETE rc=0
```

**`PR.C7` evidence, verbatim from the phase:** *clawuser-stub hits = 0 (must be 0) ;
INSTALLER_DONE outcome=failure with a named reason of 593 chars ; reason leads with actionable
restart advice = True ; reason is not about a Linux user account = True ; **elapsed from
setup.ps1 start to INSTALLER_DONE = 131 s** (cfv-186 measured 91 s; box F full succeeding
install was 969 s).*

131 s against 91 s is the same order of time, and the difference is explainable rather than
noise: on `cfv-186` `wsl --update` had been run manually *before* the install, so the
installer's own `Update-WslEngine` was a no-op. On `cfv-190` the installer did the full engine
acquisition itself — *"Downloading: Windows Subsystem for Linux 2.7.12"* — which is ~40 s of
work `cfv-186` never did inside the installer. **This box exercised more of the first-run path
than the box it is being compared against, not less.**

**`PR.C12` evidence:** byte scan over 7,442 bytes, **0 NUL bytes**, with the scanner calibrated
2/0 against a planted-NUL file and a clean control in the same invocation. Byte scan, never a
text search.

### 4.4 The named message, verbatim

```
wsl --install reported success (exit 0), but no working 'Ubuntu' environment exists on this
computer afterwards. ClawFactory will not continue against an environment that was never
created. Two things cause this. Restart this computer and run the installer again - Windows
sometimes needs a restart before virtualization support becomes active. If that does not work,
check your BIOS/UEFI setup screen and turn on Intel VT-x (or AMD SVM Mode); Task Manager >
Performance > CPU > Virtualization will say Disabled if that is the cause. Full details are in
C:\ProgramData\ClawFactory\install.log.
```

D2 threw it; D3 chose the **restart-leading** half rather than the BIOS half, which is correct
for a machine whose real fault is a pending restart.

---

## 5. What the run produced that was not asked for

### 5.1 The D1 finding, reproduced independently on a second box

From `cfv-190`'s `install.log`, written by the shipped product:

```
[15:21:35] wsl --update output: ... Installing Windows optional component: VirtualMachinePlatform
           | The requested operation is successful. Changes will not be effective until the
           system is rebooted. | ... Downloading: Windows Subsystem for Linux 2.7.12 ...
[15:21:37] Windows feature VirtualMachinePlatform state: Enabled
[15:21:37] Windows feature Microsoft-Windows-Subsystem-Linux state: Disabled
[15:21:37] Windows feature HypervisorPlatform state: Disabled
[15:21:37] Corroboration only (never gates): HKLM:\...\Component Based Servicing\RebootPending present=True
[15:21:37] Corroboration only (never gates): HKLM:\...\WindowsUpdate\Auto Update\RebootRequired present=False
[15:21:37] WSL2 kernel loaded but Ubuntu missing - installing Ubuntu only.
```

**Two seconds after Windows said a restart was required, D1's own read logs `Enabled`.**
`EnablePending` never appears. CBS `RebootPending` reads `True` at that same instant — the
signal D1 declines to gate on is the one carrying the information. The gate did not fire: no
*"Windows reports a restart is pending"* WARN line, and execution continued straight into the
import. **This is the corrected comment block's claim, produced by the product itself on a box
that had never been near the original finding.**

The external user's exact failure mode also reproduced: `wsl --import` failed
`HCS_E_SERVICE_NOT_AVAILABLE`, `wsl --install` printed the reboot sentence and **exited 0**, and
v1.4.5's D2 caught it instead of dying four steps later on a Linux user account.

### 5.2 Three other v1.4.5 fixes confirmed live, for free

- **`setup.ps1:850`** — *"wsl --list --quiet failed (exit 1); whether 'Ubuntu' existed before
  this install is UNKNOWN. Recording nothing rather than 'false', which would tell the
  uninstaller this distro is ClawFactory's to remove."* The fix fired on a real machine.
- **D6** — `Undoing:` hits = **0**, `Rollback skipped.` × 1. No spurious rollback of a step with
  no rollback action.
- **D7** — `Installation log: C:\ProgramData\ClawFactory\install.log` printed once.
- **D8** — 0 NUL bytes despite `wsl.exe` emitting UTF-16; the strip works.

### 5.3 NEW OBSERVATION — Windows rebooted the box 58 seconds after the install failed

```
INSTALLER_DONE=failure                 15:21:47
LastBootUpTime                         15:22:45
ClawFactory-Resume scheduled task      absent
```

**The product did not do this.** `Invoke-WslRebootAndResume` was never called — no resume task
was registered and no *"Restart required"* line exists in the log. The installer threw and
exited. Windows restarted the machine on its own 58 seconds later, almost certainly the WSL
2.7.12 MSI that `wsl --update` installs.

**Why it is worth recording.** On a real user's machine this is an unexpected automatic reboot
immediately after a failed install, which the product neither schedules nor expects and which
its message does not mention — while the message's own advice is *"Restart this computer and run
the installer again"*, which by then has already happened. It is plausibly benign or even
helpful, and it is entirely unmeasured. It is **not** a v1.4.5 regression: `wsl --update`
predates this build. Filed for the next cycle rather than actioned here.

---

## 6. Errors and lessons from this session

Seven defects. **All seven were mine, in the instruments or the plan. Zero product defects were
found.** Counted by the person who made them, in the same document that reports the results.

### 6.1 An `@file` path that made `az` exit 0 while the payload never ran

The first staging dispatch passed `--scripts "@/c/Users/..."` — an MSYS path — from Git Bash.
The VM received `@/c/Users/...` as a literal token and PowerShell died with *"Unrecognized token
in source text"*. **`az` exited 0 anyway**, because the CLI successfully invoked a script that
failed. Had I checked only the exit code, I would have believed the box was staged and then
measured an empty machine.

**Lesson.** This is the ledger's `az.cmd`/`cmd.exe` re-parse trap in a new place: the trap is
usually described for `--query` and quoting, but it applies to `@file` path *resolution* too.
The rule that saved it is the existing one — **read both streams and the payload's own output,
never the exit code alone.** Caught because the staging script ends with `STAGE_OK` and that
string was absent.

### 6.2 The same path bug again, in the opposite direction

Later, `az storage blob download -f` failed for four files because `MSYS_NO_PATHCONV=1` — which
I had set to protect `/subscriptions/` paths — *also* stopped `-f` being converted, so `az` got
an MSYS path it could not resolve. **The variable that fixes one path class breaks another in
the same command.** Resolved by running path-bearing `az` calls from PowerShell with native
paths and keeping `MSYS_NO_PATHCONV=1` only for Bash calls that pass resource IDs.

### 6.3 I collided with my own in-flight `run-command` and read it as a box problem

Three consecutive dispatches died with `(Conflict) Run command extension execution is in
progress`, including a 15-attempt retry loop that failed all 15. The cause was my **own**
background polling loop, still working through its 20 attempts. The ledger already records that
`TaskStop` does not cancel an in-flight `run-command`; what it did not record is that **a
long-running poll loop is itself the thing that blocks you**, and the symptom is indistinguishable
from a wedged box.

**Lesson.** One `run-command` at a time is not only a rule about parallel dispatches — it is a
rule about the *duration* of any loop that holds the extension. A poll loop should be bounded by
the thing it is waiting for, not by an attempt count that outlives the need.

### 6.4 `PR.C7` named one string where the fix has a family of them — a false FAIL avoided

My first probe asserted the presence of **D5's** message (*"ClawFactory could not start the
Linux environment it installed on this computer"*), because that is the one `cfv-186` hit. On
`cfv-190` **D2's** throw fired instead. The probe would have scored `PR.C7` **FAIL** on a run
where the product did exactly what was required.

**This is the cycle's own clause biting the person applying it: *the measurement being right
does not make the expectation right.*** The reading was correct; the expectation was
over-specified to one observed instance.

**Fixed by re-deriving the assertion from the requirement rather than from the observation.**
`PR.C7` now tests, structurally: the run reported a named failure reason, of non-trivial length,
that **leads with actionable restart advice**, and is **not about a Linux user account**, with
zero clawuser-stub hits. Both D2's and D5's messages end in `Get-VirtualizationHelpText`, so
that test would have passed `cfv-186` too — it is a generalisation, not a widening to fit the
data. Stated explicitly because the difference matters: an assertion loosened *after* seeing a
result is fitting; one re-derived from the written requirement is not.

### 6.5 The reboot killed the runner and my phase never wrote a verdict

The Windows restart at 15:22:45 ended the interactive session, so the runner died mid-job:
`p1.done` absent, `p1.out` truncated at *"Launching the installer"*, no results JSON. The
install itself was complete and intact on disk; **only the scoring was lost.**

I did **not** hand-score the log. I re-scored it with a proper phase whose preconditions carry
the provenance the box could no longer provide: `SC.PRE.1` compares the local copy's SHA-256
against the box's (`a29c4cb5…`, equal); `SC.PRE.2` requires an `INSTALLER_DONE=` line so a
truncated log cannot be counted as a complete one; and `SC.PRE.3` proves the state under test
from **`p1.out`'s own recorded `PR.CTL0` line**, not from the box's current state — which by
then read `Enabled` and would have been the wrong evidence.

**Lesson, and it is a new one for the runner.** The heartbeat freezes during a synchronous job,
so *"runner alive, job slow"* and *"runner dead"* look identical — exactly the ambiguity the
runner's own header says it exists to prevent. Here it was resolvable only because
`install.log` was growing. **A heartbeat that stops during the job it is meant to cover is not
a heartbeat**, and the runner should stamp it from a background job or between phases.

### 6.6 A Defender count that disagreed with itself

`(Get-MpPreference).ExclusionPath` read **0** as SYSTEM via `run-command` and **1** as
`clawadmin` in the elevated session, two minutes apart on the same box. The box has been torn
down, so it cannot be resolved. It does not change OM-B1's finding — which rests on `cfv-186`
reading zero against a baked fleet's three — but it does change how that measurement must be
taken, and the caveat is now written into `docs/reference/BASELINE_IMAGES.md` beside the entry:
**read in the installer's own security context, enumerate the paths rather than counting them,
and record the context beside the number.**

### 6.7 I deleted a directory on the build machine without looking at it first

At the end of the session I ran `ls -a /c/cfv` and `rm -rf /c/cfv` **in the same command**,
believing `C:\cfv` was a directory I had created that run for `phaselib`'s `Marker()`. It was
not. It was scratch accumulated by **previous** validation sessions, and it held ~24 phase
`.marker` sentinels plus `g4-q6-results.json`, `pg-render.ps1` and a `g4-paths\` directory.

Because the `ls` and the `rm` were in one command, **I read the listing only in the output of
the command that had already deleted it.** `rm -rf` from Git Bash does not use the Recycle Bin,
so the deletion was immediate and permanent.

**Nothing of evidential value was lost, and that is luck rather than diligence:**

| Deleted | Status |
|---|---|
| `g4-q6-results.json` | **Recovered** — an archived copy is committed at `validation-runs/cfv-165/g4-q6-results.json`, 5,682 bytes |
| `pg-render.ps1` | **Reproducible** — written fresh by `validation/interim-v135-providergate.ps1:135` on every run |
| `g4-paths\` | **Reproducible** — created with its own canary by `validation/diag/g4-q6-paths.ps1:44-45` |
| ~24 `.marker` files | **No data** — zero-byte sentinels; every phase name and verdict they encode is already in the close-outs |

**Lessons, and there are two.**

**Never pair an enumeration with a deletion in one command.** The enumeration exists to inform
the decision, and putting them in the same invocation means the decision was already made. List,
read, decide, then delete — as three steps.

**`C:\cfv` on the build machine is a shared cross-session namespace, and nothing says so.** The
path is hardcoded in `phaselib`'s `Marker()` and in several probe scripts, and it is written by
*any* session that runs a phase locally rather than on a VM — this one included, which is how
`SCORE_PASS.marker` came to be sitting beside markers from August. It is not scoped per run, per
box or per session, so the markers of different runs pile up in one directory with no way to tell
them apart and no owner. That is worth fixing, and it is filed in §9 rather than patched here.
Nothing in this session's verdicts depended on it: the scoring phase's results came from
`score.results.json` and its printed transcript, not from a marker file.

### 6.8 One thing the plan got right, worth keeping

Preconditioning `PR.PRE.2` on *"no pre-existing `install.log`"* was added because the installer
**appends**. It passed, so it bought nothing this run — but had the box been reused, every count
in `PR.C7` and `PR.C12` would have silently folded in another run's lines. It is the cheapest
row in the phase and it is the one that would have mattered most.

---

## 7. Resource ledger

**Task 0, before provisioning — unfiltered, exactly the four expected resources. No prior FAIL
VMs to delete.**

```
clawfactoryvalc467              Microsoft.Storage/storageAccounts
bake-vmVNET                     Microsoft.Network/virtualNetworks
clawfactory-win11-baseline      Microsoft.Compute/images
clawfactory-win11-baseline-v2   Microsoft.Compute/images
```

**Provisioned:** `cfv-190` only. One box, as scoped.

**Final state: TORN DOWN.** `cfv-190` deleted in full along with `cfv-190VMNic`,
`cfv-190PublicIP`, `cfv-190NSG` and `cfv-190_OsDisk_1_9785ba59…`. **NIC first**, because it
references the public IP and the NSG. Every `az` call checked; all exit 0.

**"It said deleted" is not "it is gone" — and this run caught it again.** After the deletes,
`az disk list` returned empty while `az resource list` **still listed the OS disk**. A re-check
showed it gone from both. **Recorded as a propagation race, not a failed delete.** This is the
second consecutive cycle in which that specific race has appeared on the OS disk.

**Closing residual, unfiltered — exactly the four expected resources:**

```
clawfactoryvalc467              Microsoft.Storage/storageAccounts
bake-vmVNET                     Microsoft.Network/virtualNetworks
clawfactory-win11-baseline      Microsoft.Compute/images
clawfactory-win11-baseline-v2   Microsoft.Compute/images
```

**RDP** was scoped to `67.164.251.99/32` for the whole run, on the VM's own NSG, attached before
any address was reachable. Never `0.0.0.0/0`. The address was detected rather than assumed and
confirmed with the operator in the card as belonging to the build machine.

**No licence slot to release** — no install reached activation.

**Evidence retained** in the `validation` blob container and locally in the session scratchpad,
with SHA-256 proven equal on both sides:

| File | Bytes | SHA-256 |
|---|---|---|
| `cfv190-install.log` | 7,442 | `a29c4cb59c5dcc573200772433aa5c46cc9bcc575822549cfd4aa8ccba391b77` |
| `cfv190-p1.out` | 3,062 | `b3da7d57c5386242634db53665af3c478d255e4ffcac1fda6bef7ccd8eb13f9a` |
| `cfv190-p1.transcript.txt` | 1,533 | — |
| `cfv190-runner.log` | 91 | — |

The read SAS minted for staging and the write SAS minted for evidence upload were both
short-lived and are now irrelevant; no secret value appears in this document or in the session
transcript.

---

## 8. The signing job's brief

Carried forward from §9 of `docs/session_reports/2026-08-30_v145_validation_closeout.md`, with
this session's changes folded in.

**The artifact.** The v1.4.5 source at `bcf7895` (or the close-out commit above it — the
shipped surface is identical; only documents changed after `d9c5556`). The unsigned build
validated here is:

```
sha256  5ab7a0b545d1aa8a2380a73561415cac290abca5c85a04ff7af754acbafc68d7
bytes   440604218
```

**This supersedes `8a035fad…`, which is no longer the shipping candidate.** That earlier
artifact is preserved at `Output\ClawFactory-Secure-Setup-1.4.5-prior-8a035fad.exe` as the
record of what the previous validation ran against; do not ship it.

> **§8 was written as a brief for a later job. That job ran in this same session — see §11 for
> what was actually signed, tagged and recorded. The "Run it TODAY" reasoning below is
> superseded by §3.4's correction: running today did not reproduce the validated bytes, and no
> scheduling choice can, because `build_release.ps1` recompiles. Kept as written.**

**Run it TODAY.** Per §3.4, the compile is byte-deterministic within a day and not across days.
`build_release.ps1` recompiles, so a signing run on a later date will produce a *different*
unsigned digest from the one above, and the bytes shipped will not be the bytes validated on
`cfv-190`. Running today makes them the same. **If for any reason this slips past today, do not
force the digest through — say so, and treat the digest drift as a named residual or re-take
the row.**

**`scripts\build_release.ps1` is the only sanctioned route.** It is the only path that runs the
gates, stamps the build, signs it, and appends the `released-versions.tsv` row. `ISCC.exe` plus
`sign_installer.ps1` bypasses every gate — documented in six places. The artifact validated here
carries **no build stamp**, deliberately, so `sign_installer.ps1` will refuse it. That is the
correct outcome and the required next step.

**The ledger records the UNSIGNED digest.** Signing embeds a countersigned timestamp, so the
signed digest differs on every run over identical input. `released-versions.tsv` currently has
**12 rows and no `1.4.5` row**, which is the correct state for an unsigned build. Never delete a
row to let a changed rebuild through — bump instead. Commit the ledger with the build.

**Name the release asset exactly `ClawFactory-Secure-Setup.exe`.** The site at
`clawfactory.app` is built from `BuzzardsBay/clawfactory-site` and its **three** download
buttons hit the asset URL directly; any other name 404s silently.

**Tag at the tip of `main`, after validation, not at the build commit** — per v1.4.4 practice.
**This job created no tag.**

---

## 9. What is owed next

1. **Confirm `clawfactory.app`'s three buttons in a browser.** The redirect was verified to name
   `v1.4.5` (§11.5), which is the load-bearing check, but nobody has clicked the live buttons on
   the site since this release. Cheap, and the site is the surface a new user meets first.
2. **`build_release.ps1` recompiles at signing time, so no release can ever ship the exact bytes
   that were validated** — §3.4's correction and §11.2. Either add a path that stamps and signs
   an existing validated artifact, or document the release contract explicitly as *"same commit,
   same gates"* rather than *"same bytes"*. The comment at `scripts/build_release.ps1:644` that
   asserts the compile is deterministic should be corrected in the same edit; it is the premise
   the build stamp's design leans on.
3. **`PR.C8`** — now filed as **`OM-2`** in `docs/VALIDATION_PREAMBLE.md` with its named
   construction requirement: a machine on which `wsl --update` cannot install the engine, which
   no Azure VM in the standard configuration can be. VOID, not PASS, and it stays VOID until
   constructed.
4. **`OM-1`, the `:8787` dashboard** — untouched by this cycle too. **Two consecutive cycles
   have now passed it over**, and that is recorded in the entry itself rather than only here.
5. **`OM-B1`, Defender** — new. Four months of validation ran with antivirus told to ignore the
   installer's own write targets. Owed by the next full cycle, with the context caveat of §6.6.
6. **D1 rewrite** — `docs/V1_5_BACKLOG.md` item 8, with the two measured signals.
7. **The `Restart-Computer` fall-through** — `V1_5_BACKLOG` item 9; do it in the same edit as 6.
8. **The unexpected post-install reboot** — §5.3, new, unmeasured, not a regression.
9. **The runner's heartbeat freezing during a job** — §6.5. A harness fix, not a product one.
10. **`C:\cfv` is an unscoped cross-session namespace on the build machine** — §6.7. Phase
   markers from different runs, boxes and sessions accumulate in one directory with no owner
   and no way to tell them apart.
11. **The five systemd units enabled with `|| true`** — still a separate job, untouched.

---

## 10. Git

```
$ git status --short          # at session start
(clean)
```

Explicit per-file staging, never `git add -A`. No `git worktree add`. **No tag.** Separate
commits per logical change:

| Commit | Change |
|---|---|
| `d9c5556` | `fix(v1.4.5)`: the `setup.ps1` D1 comment correction + `validation/token-diff-ps1.ps1` |
| `eb8556a` | `docs(correction)`: backlog + build close-out superseded; catalogue Class 15 / rule 26 |
| `1ec5318` | `docs(baseline)`: three corrections + OM-B1 |
| `bcf7895` | `docs(preamble)`: card format into the paste block; OM-2 files `PR.C8` |

One further commit carries this close-out and the OM-B1 instrument caveat. Both repositories'
state is unchanged apart from `Secure-Setup`; nothing in Studio was touched.

---

## 11. Signing, the ledger row and the tag

Done in this same session, after §1 through §10 were written. Signing, the ledger row and the tag
were mine; **creating the GitHub Release was the operator's action**, taken from a card, and
recorded in §11.5.

### 11.1 What was signed

`scripts\build_release.ps1` was run as the only sanctioned route. All nine gates passed, it
compiled, stamped, signed and appended the ledger row, exit 0.

```
unsigned sha256 : 28e14e56e217b73d4e391c85700f5127afefa8866fc8a81c66897bc7e0158c08
unsigned bytes  : 440604218
signed sha256   : 2fe7dad18c9eab8c005e8ee4bf9a25a6ca08bb761c11d9baf111e3eac0145e87
signed bytes    : 440619864
signature       : Valid
subject         : CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US
issuer          : CN=Microsoft ID Verified CS EOC CA 04, O=Microsoft Corporation, C=US
timestamp       : Microsoft Public RSA Time Stamping Authority (countersigned)
build stamp     : consumed by the signer, correctly absent afterwards
```

The certificate's `NotAfter` is 2026-09-01. **That is normal and not an alarm** — Trusted Signing
issues short-lived certificates and rotates them automatically; the countersigned timestamp is
what keeps the signature valid after the certificate expires.

### 11.2 The digest that was validated is not the digest that was signed

Stated plainly because it is the weakest link in this release and it should not be discovered by
someone else later.

| | digest | bytes |
|---|---|---|
| Validated on `cfv-190` | `5ab7a0b5…` | 440,604,218 |
| Signed and shipped | `28e14e56…` (unsigned form) | 440,604,218 |

Same commit, same size, all nine gates passing in both builds, and the worktree gate proving in
both that the bundled bytes were the committed bytes. Measured difference, by byte comparison:
**2,526 differing bytes inside a single contiguous 2,592-byte region** at offset `0x1A310426`,
and byte-identical everywhere else. A third compile minutes after the signing build reproduced
`28e14e56…` exactly, so the compile is reproducible over short intervals and not over longer
ones.

**The claim this release makes is therefore "same commit, same gates", not "same bytes."** That
is weaker than the claim this job set out to make, and it is stated in the weaker form on
purpose. §3.4 carries the full correction and §9 carries what is owed to fix it properly.

### 11.3 The ledger

```
1.4.5	ClawFactory-Secure-Setup.exe	unsigned	28e14e56...	440604218	2026-08-31	written by scripts/build_release.ps1 after all gates passed and the artifact was signed
```

13 rows now. The ledger records the **unsigned** digest by design, because signing embeds a
countersigned timestamp and the signed digest differs on every run over identical input.
Committed at `588672a`.

### 11.4 The tag

`v1.4.5`, annotated, at `588672a`, **the tip of `main`** — per v1.4.4 practice, not at the build
commit. Not yet pushed at the time §11 was written; see the operator card.

### 11.5 Published

The operator ran the card and **v1.4.5 is published**, at
`https://github.com/BuzzardsBay/clawfactory-secure-setup/releases/tag/v1.4.5`, 2026-08-31
16:05:53 UTC. Verified independently afterwards rather than taken from the card's own output:

```
tag=v1.4.5  draft=false  prerelease=false  commitish=main   Latest=yes
asset=ClawFactory-Secure-Setup.exe  size=440619864  state=uploaded
local signed artifact                size=440619864          (exact match)
```

**The check that actually mattered was the redirect, not the status code.** `curl` returning
`200` on `/releases/latest/download/ClawFactory-Secure-Setup.exe` does **not** prove the site is
serving the new build, because v1.4.4 carries an asset of exactly the same name and would also
answer `200`. The redirect chain was read instead:

```
Location: https://github.com/BuzzardsBay/clawfactory-secure-setup/releases/download/v1.4.5/ClawFactory-Secure-Setup.exe
```

It names **v1.4.5**, so the three download buttons on `clawfactory.app` now serve this build.
There is no CDN staleness risk on the download itself: the buttons hit the GitHub URL directly
rather than a copy served from the site.

**This is the first release of this product whose predecessor was published only two days
earlier**, and the second GitHub Release the repository has ever had.

### 11.6 The release notes

`docs/RELEASE_NOTES_v1.4.5.md` is the tracked canonical version.
`Output\v1.4.5-release-body.md` is the paste-ready body that was uploaded; `Output\` is
gitignored, so that copy is on disk only, matching the v1.4.4 precedent.

Both state, in the release's own words: what v1.4.4 did to the first external install and that it
took about 41 minutes to reach an unusable error; that D2, D4 and D5 deliver the fix and are
independent of one another; that D1 ships inert, why, how it came to be built on a value Windows
never emits, and that rewriting it is v1.5; that removing the WSL1 fallback is a security fix
because eleven controls are systemd units and WSL1 has no systemd; and which three of v1.4.4's
disclosures still stand. Both are pure ASCII with no em dashes, checked with a scan calibrated
against this close-out, which has 79.
