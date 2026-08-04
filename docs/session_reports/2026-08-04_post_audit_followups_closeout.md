# Post-Audit Follow-Ups -- close-out

**Date:** 2026-08-04
**Track:** v1 fast-security-harness. Follow-up to the self-certifying integrity audit.
**Depends on:** `4bf720f`, `04a75bb`, card #208. Met.
**Dispatch card:** #209.
**Repos touched:** ClawFactory-Secure-Setup only. Studio not changed, nothing to push there.

---

## Task 1. How v1.0.45 was actually built

**DONE. Both statements were not true, and the error was mine.**

### The dates settle it

| Fact | Value |
| --- | --- |
| `v1.0.45` tagged | **2026-07-17** (`c1762a6`) |
| `ab180d4`, which introduced the broken regex | **2026-08-03 10:59:41 -0600** |
| Gap | 17 days, with the defect **after** the tag |
| `build_release.ps1` history | `e966409` 2026-07-06, `ab180d4` 2026-08-03, `4bf720f` 2026-08-04 |

v1.0.45 was built by `build_release.ps1` as it stood at `e966409`, which contained **no gates at
all**. It compiled, checked the output existed, and signed:

```
git show e966409:scripts/build_release.ps1 | grep -c "expectedSoulHash\|SOUL pin\|Bundle check"
0
```

So the tag predates the defect and **that part is benign**. Every release from v1.0.38 through
v1.1.0 was produced through the ungated version, which worked.

### The correction

The audit close-out said, in its next-session recommendations, that "`build_release.ps1` has never
completed a run", and the headline said the compile-and-sign path had never completed one. **That
was wrong as written.** The accurate claim is narrower: *`build_release.ps1` has never completed a
run in its gated form*, meaning since `ab180d4`. The compile-and-sign path itself has run many
times.

`2026-08-04_self_certifying_audit_closeout.md` has been corrected in place with a dated correction
block pointing here. The audit's other statements on this point were already correctly scoped
("failed the build unconditionally **from the day it was written**", "no release has been cut
through `build_release.ps1` **since `ab180d4`**"), so only the one unqualified sentence was wrong.

### The finding the audit missed: the gates are advisory, not structural

A bypass route exists, produces a release-grade signed binary, and is documented in six places:

```
ISCC.exe ClawFactory-Secure-Setup.iss
scripts\sign_installer.ps1 -InstallerPath Output\ClawFactory-Secure-Setup.exe
```

`sign_installer.ps1` declares `[Parameter(Mandatory = $true)] [string]$InstallerPath` and nothing
that constrains it. It contains **zero** references to `build_release`, `expectedSoulHash` or
`Preflight`. It signs whatever it is handed.

| Where the direct route is documented | Text |
| --- | --- |
| `README.md:106` | The "Building from source" section gives `ISCC.exe ClawFactory-Secure-Setup.iss` as the build command |
| `CONTRIBUTING.md:8` | "Every PR must compile cleanly with `ISCC.exe ClawFactory-Secure-Setup.iss`" |
| `CONTRIBUTING.md:29` | "3. Build: `ISCC.exe ClawFactory-Secure-Setup.iss`" |
| `ClawFactory-Secure-Setup.iss:3` | "Compile with: `ISCC.exe ClawFactory-Secure-Setup.iss`" |
| `ClawFactory_Session_Handoff_May26.md:147` | Build command row, direct ISCC |
| `build_release.ps1` header | "For a quick local dev build ... compile with `ISCC.exe` directly instead" |

There is no CI: `.github/workflows` does not exist. There is no other build or packaging script in
either repo (`scripts/` contains one build script, one signing script, and probes; `validation/`
contains validation harnesses only).

**Stated plainly: the four build gates are advisory, not structural.** A working, documented,
two-line route around them exists; it is the route the README teaches first; and it is the route
that gets taken under time pressure, which is exactly when the gates matter most. This is the same
class as the audit itself: a control that is real, that works when invoked, and that nothing
requires you to invoke.

### Can it be closed, and what closing costs

| Option | What it closes | Cost |
| --- | --- | --- |
| **(a)** Move the gates into the `.iss` itself via the Inno preprocessor (`#expr Exec(...)` plus `#error`) | Every ISCC invocation, including direct and third-party | Adds an ISPP compile-time dependency on PowerShell, makes the `.iss` non-portable and harder to audit by reading, and cannot be tested without compiling, which this session is forbidden from doing |
| **(b)** Have `sign_installer.ps1` refuse a binary not stamped by `build_release.ps1` | The **release** route only. Unsigned local dev compiles keep working, which is correct, and only signed binaries are released | Roughly 15 lines. Makes emergency re-signing harder. The stamp is itself state, so it does not stop someone determined, only someone in a hurry |
| **(c)** Document only: state in `README.md` and `CONTRIBUTING.md` that direct ISCC output must never be signed or released | Nothing mechanically | Free and honest |

**Recommendation: (b), plus the (c) wording, but NOT in this session, and it was not done here.**
The next session is the first build ever to run through the gates. Changing the signing path
immediately before that run gives any failure two candidate causes instead of one. (b) belongs in
the build session or immediately after it, where it can be exercised end to end. Making an untested
change to the build path is the behaviour this whole track exists to stop.

**Is the v1.0.45 route repeatable?** Yes, and that is the problem rather than the reassurance: it is
repeatable precisely because it does not depend on the gates.

---

## Task 2. `Step-FreezeInjectedSoul` now throws

**DONE.** `setup.ps1` line 2488. The `Write-Log WARN` is replaced by a `throw` naming what was not
delivered, why the install is refusing, and which two paths to check.

The reason it matters, restated in the code comment: `clawfactory-turn-gate.sh` enforces the
injected SOUL **only if its pin exists**. A freeze that failed left no pin, so every turn ran
unchecked while the installer, the post-install checklist and the smoke suite all reported green.

### How it was proven

A real clean-box install is not possible this session, because building an installer is out of
scope. Instead the **real** `Step-FreezeInjectedSoul` body was extracted from `setup.ps1` by AST
(`FunctionDefinitionAst`), written to a file in a scratch directory, and dot-sourced, so
`$PSScriptRoot` inside it resolves to that directory and it reads that directory's `resources\`.
Nothing was re-implemented. The four functions it depends on (`Write-Log`, `Invoke-WslBash`,
`Save-Checkpoint`, `Step-FreezeInjectedSoul`) all came from `setup.ps1` verbatim, and the step ran
against the live WSL distro through the real `Invoke-WslBash`.

The two runs differ **only** in whether the fault line is present in the harness-local copy of
`freeze-injected-soul.sh`. That is the paired control: one run must pass and one must fail.

**Direction 1, healthy script, must not abort:**

```
##### DIRECTION 1: healthy freeze script -- must NOT abort #####
Extracted verbatim from setup.ps1: Write-Log, Save-Checkpoint, Invoke-WslBash, Step-FreezeInjectedSoul
freeze script under test: sha256 c08151654a34ac61f5f2ed5b9953fc0449a0bc8c359c5d409aee09cc099dfe47
fault present in it: no
--- calling the real Step-FreezeInjectedSoul ---
[2026-08-04 13:42:09] [INFO] Step 15c [Defect 4]: Delivering + freezing the injected workspace SOUL.
RESULT: returned normally, no throw. INSTALL WOULD CONTINUE.
harness_exit=0

##### live-box state after direction 1 #####
WS=03f29043ca6e890cd52fe38190a85414804ce10a46ef79e18313c803a51957a2
PIN=03f29043ca6e890cd52fe38190a85414804ce10a46ef79e18313c803a51957a2
```

**Direction 2, same script with one line injected, must abort:**

```
##### DIRECTION 2: faulted freeze script -- must ABORT loudly #####
Extracted verbatim from setup.ps1: Write-Log, Save-Checkpoint, Invoke-WslBash, Step-FreezeInjectedSoul
freeze script under test: sha256 892b8189c035c1b102b527d34a256ddf6f6a6425beb60d48cce4cc84a586c5c9
fault present in it: YES
--- calling the real Step-FreezeInjectedSoul ---
[2026-08-04 13:42:28] [INFO] Step 15c [Defect 4]: Delivering + freezing the injected workspace SOUL.
RESULT: THREW. INSTALL WOULD ABORT.
MESSAGE: Step-FreezeInjectedSoul failed (exit 1): the factory safety rules were not delivered into
the agent's prompt, or could not be frozen and pinned. Refusing to finish the install, because the
launch gate enforces the injected safety rules only once their pin exists -- continuing would
produce an install that looks complete but runs the agent unchecked. Check
~/.openclaw/workspace/SOUL.md and /etc/clawfactory/workspace-soul.sha256, then re-run setup.ps1 -Resume.
harness_exit=7
```

The state the abort leaves behind is fail-safe, which is the defence in depth working:

```
WS=71876b2af72ef60ecafad034fa851083ba9cf56be6094ea129610c9c9bd5f2c7
PIN=03f29043ca6e890cd52fe38190a85414804ce10a46ef79e18313c803a51957a2

{"clawfactory_gate":"blocked","state":"soul_mismatch","message":"the safety rules injected into the
agent no longer match the value pinned at install time -- they may have been tampered with. No turn
will run until they are restored."}
gate_exit=3
```

Even if someone ignored the abort, every turn is blocked.

### What the abort does downstream, traced rather than assumed

`Step-FreezeInjectedSoul` runs inside the `Invoke-WithRollback { ... }` block (`setup.ps1:3084`, the
step at `:3129`). On throw: `Invoke-WithRollback` logs ERROR plus stack trace, then offers rollback
through `Confirm-Or-Default 'Installation failed. Run automatic rollback? (y/N)' 'n'`. **The default
is `n`**, so under `/SILENT` nothing destructive happens. It then rethrows to the top-level handler,
which writes `INSTALLER_DONE=failure` to `install.log` and `install-result.txt`. Because
`install-result.txt` then does not contain `success`, `InstallStudioComponent` in the `.iss` skips
the Studio install and says so. The abort is coherent from the step to the harness to the Studio
decision.

### What this session cannot claim

The proof above exercises the real step against a real WSL distro, but it is **not** a clean-box
install. The fresh-install ordering, where `~/.openclaw/workspace/SOUL.md` does not exist and
`PERSONA` falls back to `DEFAULT_PERSONA`, is still unexercised. That belongs in the build session.

---

## Task 3. The stale customer-facing claim

**DONE.** Both lines reworded, kept consistent, nothing deleted, no new claim added.

| File | Before | After |
| --- | --- | --- |
| `resources/post-install.ps1:241` | `[x] SOUL.md installed and hash-pinned in orchestrator prompt` | `[x] SOUL.md frozen root-owned + immutable; a changed hash refuses the turn` |
| `setup.ps1:38` `[R6]` | `SOUL.md hash pinned into orchestrator prompt.` | `SOUL.md frozen root-owned + immutable and hash-pinned; the turn gate refuses the turn (soul_mismatch) if the hash changes.` plus a note that the pin has not been in the orchestrator prompt since `8eaeb60` |

The new wording understates deliberately. It says a changed hash refuses the turn; it does not claim
the refusal is unbypassable, because the documented full-path `.mjs` residual still exists and is
recorded in `SECURITY_FINDINGS.md`. The `[R6]` comment carries the `8eaeb60` history so the next
reader does not re-add the orchestrator-prompt claim believing it was an oversight.

---

## Task 4. Ollama path carded, not fixed

**DONE. Card #210, high priority, status todo, tagged `founder-decision`.**

Names all three candidate resolutions and explicitly instructs that an implementer must not pick:

1. Pin an ollama version plus the sha256 of its `install.sh` and refuse on mismatch. Same shape now
   proven three times in `build_release.ps1`, but ollama publishes no stable digest, so this means a
   checked-in digest and re-validation on every ollama bump.
2. Vendor the script into `resources/` the way `openclaw-install.sh` already is, review it out of
   band, and drop the network call. Most consistent with how the product already treats OpenClaw;
   adds a review burden per upgrade.
3. Drop the Ollama provider from v1. Removes the surface at the cost of the only local,
   no-cloud-key option.

Nothing was chosen and nothing was implemented. The card also notes that whichever is chosen, the
word "integrity" has to come out of that comment, since it currently describes a two-byte shebang
check.

---

## Task 5. Version drift adjudicated and gated

**DONE.** `MyAppVersion` is correct; `$InstallerVersion` was stale and follows it.

**Evidence, not preference:**

- `MyAppVersion` tracks every release exactly: `1.0.43`, `1.0.44`, `1.0.45`, `1.0.46`, `1.0.47`,
  `1.0.48`, `1.1.0`, `1.1.1`, matching the tags.
- It feeds `AppVersion` in `[Setup]`, so it is what Windows shows in Apps & Features and on the
  uninstall entry. **It is the value the customer sees**, which makes it the authority.
- `$InstallerVersion` last changed around 2026-05-26 and is referenced in **no** `.ps1` and no
  `.iss`. `grep -rn InstallerVersion` returns only `setup.ps1:49` itself plus prose in `CHANGELOG.md`,
  `CLAUDE_ClawFactory.md` and three close-outs. It is a dead constant.
- Two earlier sessions already flagged it: `2026-07-21_ship_a_site_pass_closeout.md:89` and
  `2026-07-22_ship_b_v1_1_1_closeout.md:311` ("stale at `1.0.34`, unreferenced").

`$InstallerVersion` set to `1.1.1`, with a comment recording that `.iss` is the authority and that it
sat wrong through roughly fifteen releases because nothing compared the two. It is still
unreferenced; the assertion exists so that ceases to be a matter of luck.

New gate in `build_release.ps1`, same shape as the other three: fail on drift, never auto-correct.

**Both directions proven:**

```
##### POSITIVE: all four gates pass #####
SOUL pin OK: 8f5531a36e46af8143ffe59ae4112a83a28b3513c473562578ee81c408c07eb6
Bundle check OK: all 29 preflight resources are in [Files].
Studio pin OK: d5ff8370943194c2643674ddba98e917ca61865ce127ec424a1cb37c746d45a7
Version OK: 1.1.1 (.iss and setup.ps1 agree)
Compiling installer with Inno Setup...

##### NEGATIVE: drift the .iss version, must refuse #####
SOUL pin OK: 8f5531a36e46af8143ffe59ae4112a83a28b3513c473562578ee81c408c07eb6
Bundle check OK: all 29 preflight resources are in [Files].
Studio pin OK: d5ff8370943194c2643674ddba98e917ca61865ce127ec424a1cb37c746d45a7
CAUGHT: build_release.ps1: Version drift: .iss MyAppVersion is 1.1.2 but setup.ps1
$InstallerVersion is 1.1.1. The .iss value is the one the customer sees, so set $InstallerVersion
to 1.1.2 and rebuild.
restored .iss MyAppVersion: #define MyAppVersion   "1.1.1"
```

Both runs used a stand-in for `ISCC.exe` so they halt before compiling and signing, per the
out-of-scope rule. Note the negative run stops at the version gate **after** the first three pass,
which is the ordering working as intended.

---

## Task 6. End-of-session gate

### 6.1 Task accounting

| Task | Status |
| --- | --- |
| Dispatch card created at session start | DONE. Card **#209**, `in_progress`, moved to `done` at close-out |
| **Task 1** How was v1.0.45 actually built, reported before Task 2 | **DONE.** Tag predates the defect by 17 days. My audit sentence corrected in place |
| Task 1: `git log` dates, `ab180d4` against the tag | DONE |
| Task 1: every other build, packaging, release script in either repo | DONE. None exists. No CI |
| Task 1: manual compile procedure in session reports or lessons | DONE. Found in six documents |
| Task 1: how `ISCC.exe` is invoked and whether any path skips the gates | DONE. A documented bypass exists |
| Task 1: how the v1.0.45 signed binary was produced and whether repeatable | DONE. Ungated `e966409`; repeatable, which is the problem |
| Task 1: say plainly whether the route can be closed or only documented, and what closing costs | DONE. Three options costed; **not closed this session**, with the reason stated |
| **Task 2** `Step-FreezeInjectedSoul` throws | **DONE** |
| Task 2: clean-box install completes normally | **PARTIAL, and stated as such.** Proven against the live distro using the real extracted step, not a clean box, because building an installer is out of scope. Fresh-install ordering remains unexercised |
| Task 2: injected fault aborts loudly | DONE. Verbatim evidence above |
| Task 2: paired control per the file-based channel rule | DONE. The two runs differ only in the fault line; one passes, one fails |
| **Task 3** Reword both stale claims, keep consistent, understate, add nothing | **DONE** |
| **Task 4** Card the Ollama path, name three resolutions, choose none | **DONE.** Card #210 |
| **Task 5** Adjudicate version drift with evidence, make them agree, add a build gate | **DONE.** Both directions proven |
| **Task 6** Task accounting, ledger, security sweep, bug review, recommendations | DONE, this section |
| Cut a build | OUT OF SCOPE. Not done |
| Guard 3, Guard 4, Studio restyle | OUT OF SCOPE. Not touched |
| Customer-facing copy beyond Task 3 | OUT OF SCOPE. Not touched |
| Remaining presence-only items from the audit table | OUT OF SCOPE. Not touched |
| Close the build-gate bypass route | **DEFERRED** to the build session, with costs stated (Task 1) |
| Persona absorption after a failed freeze | **DEFERRED**, newly found this session. See 6.4 |

### 6.2 Resource ledger

**Live WSL box (`Ubuntu`), changed and restored:**
- The injected workspace SOUL was rewritten five times across the Task 2 runs. **Final state
  verified good:** `WS` and `PIN` both `03f29043ca6e890cd52fe38190a85414804ce10a46ef79e18313c803a51957a2`,
  factory SOUL and its pin both `cd0199d52b9e4787f9be6fe53fb5a71726978006bc09f973f09f352bb9452bde`,
  `root:root 444`, `lsattr` shows `i`, launch gate `gate_exit=0`.
- **The persona was corrupted mid-session and repaired.** The direction-2 fault left
  `MALICIOUS SAFETY RULES` at `$WS`; the next healthy run found no marker in it and preserved the
  whole thing as persona. Restored from `/root/cf-audit-backup/SOUL.md.bak` (kept from the audit
  session) and re-frozen. Persona verified back to the real text, ending
  `- [SOUL.md personality guide](/concepts/soul)`. This is recorded as a finding in 6.4, not just a
  cleanup note.
- `/root/cf-audit-backup/` still present, unchanged from the audit session, and it is what made the
  repair possible. Remove with `rm -rf /root/cf-audit-backup` when no longer wanted.

**Repo, tampered and restored:**
- `ClawFactory-Secure-Setup.iss` `MyAppVersion` set to `1.1.2` for the negative control, restored by
  writing back the captured original text. Verified: `#define MyAppVersion   "1.1.1"`.

**Scratchpad only, not in the repo:** `t2/proof.ps1`, `t2/extracted.ps1`, `t2/resources/`, `t2/log/`,
`t2-check.sh`, `t2-repair.sh`, `freeze-real.sh`. The faulted copy of `freeze-injected-soul.sh`
existed only under `t2/resources/` and was overwritten with the clean copy; it was never written to
`resources/`.

**Cards:** #209 (this session), #210 (Ollama).

**Azure:** none used. No VMs created, none live.

**Cost:** nothing compiled, nothing signed, nothing uploaded, no release cut.

### 6.3 Delta security sweep

**Claims this session made untrue:** none.

**Claims this session made TRUE that were previously false:** two. The `[R6]` header and the
post-install checklist line now describe the protection that actually exists. Both understate rather
than overstate.

**Security posture changes:**
- `Step-FreezeInjectedSoul` moves from fail-open to fail-closed. This is strictly stronger and is the
  point of the task. It raises install-abort risk, which is the correct trade: an aborted install is
  recoverable, an unenforced SOUL is not detectable by the customer.
- Traced and confirmed non-destructive: the throw does **not** trigger a silent rollback, because
  `Confirm-Or-Default` defaults to `n`. Checked rather than assumed, because a throw that wiped a
  customer's WSL distro would have been a far worse outcome than the bug being fixed.
- The version gate adds no runtime surface. It is build-time only.

**New finding, not a regression but newly relevant:** the build gates are advisory rather than
structural (Task 1). Recorded, costed, deferred with a reason.

**No secret, key, token or password** appears in any changed file, in the evidence blocks, or in this
close-out.

### 6.4 Delta bug review, from an end-to-end diff read

Read the complete working diff across all five files.

- **`$InstallerVersion` is under `Set-StrictMode -Version 3.0` and is unreferenced.** Confirmed that
  an unreferenced assignment is not a StrictMode violation, so setting it to `1.1.1` cannot break the
  install. Only reads of undefined variables throw.
- **The `throw` makes `Save-Checkpoint 'FreezeInjectedSoul'` unreachable on failure.** Intended: a
  checkpoint recorded for a step that failed would let `-Resume` skip it.
- **The new `throw` string is built with `+` concatenation inside parentheses**, matching the style
  of the other multi-line throws in the file, and contains no `$` that PowerShell would interpolate
  unintentionally. `$rc` is interpolated deliberately.
- **The version gate's `$psVer` regex uses a backtick-escaped `` `$ ``**, which is precisely the
  defect Fix 3 corrected in the audit. Checked deliberately rather than by habit; the positive run
  printing `Version OK: 1.1.1` proves it matches.
- **The `$issVer` regex uses a single-quoted string**, so its `#define\s+MyAppVersion\s+"([^"]+)"`
  needs no escaping. Two different quoting styles sit adjacent on purpose; both were executed.
- **Gate ordering:** the version gate runs after the Studio gate and before `ISCC.exe`. The negative
  run confirms the first three still print OK before it refuses, so a version drift does not mask an
  earlier failure.
- Git reports `CRLF will be replaced by LF` for `build_release.ps1`. Windows-only script, never
  enters WSL. `post-install.ps1` and `setup.ps1` likewise run on the Windows side.

**NEW FINDING: a failed freeze poisons the persona for the next successful freeze.**

Hit directly on the live box this session. When `freeze-injected-soul.sh` fails after replacing
`$WS`, the file left behind has no `CLAWFACTORY-SAFETY-END` marker. The next run takes the
`else` branch, `PERSONA=$(cat "$WS")`, and wraps **the entire leftover** as the user's persona. On
this box that meant the agent's persona became the literal string `MALICIOUS SAFETY RULES`, and the
freeze reported success while doing it.

The safety block above the marker is regenerated from the factory rules every run and was correct
throughout, so the hard boundaries were never weakened. What was corrupted is the persona, which is
user-owned content.

This is pre-existing, not introduced by the diff. **But Task 2 makes it materially more reachable**,
because the new throw tells the operator to "re-run `setup.ps1 -Resume`", and that re-run is exactly
the path that absorbs the remnant. Recommended fix: when no marker is found but
`/etc/clawfactory/workspace-soul.sha256` already exists, treat the file as a failed-freeze remnant
rather than as persona, and fall back to `DEFAULT_PERSONA` with a loud message. Cost: about six
lines plus a test. **Not done here**, because it is a behaviour change to persona handling that was
not in the task list and deserves its own decision.

### 6.5 Next-session recommendations

1. **Cut the build.** Unchanged as the top item, and now with four gates instead of three. It will be
   the first run to reach `ISCC.exe` through them.
2. **Fix the persona absorption (6.4) before or during that session.** It is cheap, it is now more
   reachable because of Task 2, and it corrupts user-owned content while reporting success.
3. **Close the build-gate bypass with option (b)** from Task 1, in or immediately after the build
   session, where it can be exercised end to end. Pair it with the (c) wording in `README.md` and
   `CONTRIBUTING.md`.
4. **Clean-box validation** of both the injected-SOUL fix and the new throw, covering the
   fresh-install ordering that no test has yet exercised.
5. **Founder decision on card #210** (Ollama unpinned remote code as root).
6. The remaining presence-only items from the audit table are unchanged and still deferred: the
   unpinned rootfs and `ClawChat.exe`, the vacuous smoke check, the dead `Get-SoulSha256`, and the
   explicit mode on `/etc/clawfactory/openclaw-real`.

---

## Git

`git status --short` run first. Explicit per-file staging, no `git add -A`, no `git worktree add`,
committed to `main` in the single working tree.

| File | Why |
| --- | --- |
| `setup.ps1` | Task 2 throw, Task 3 `[R6]` reword, Task 5 version |
| `resources/post-install.ps1` | Task 3 checklist line |
| `scripts/build_release.ps1` | Task 5 version gate |
| `docs/session_reports/2026-08-04_self_certifying_audit_closeout.md` | Task 1 correction |
| `docs/session_reports/2026-08-04_post_audit_followups_closeout.md` | This close-out |

Studio repo: not changed, nothing to push.
