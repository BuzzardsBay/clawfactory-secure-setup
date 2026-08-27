# CLOSE-OUT: v1.4.4 wrapper fixes, the coverage gap behind them, then build and sign

**Status at the time of writing: IN PROGRESS, blocked on one operator login.**
Written incrementally so an interrupted session leaves an honest record rather
than nothing. Sections carry their own state. Anything not yet measured says so.

**No fitness-to-publish verdict appears in this document, by instruction. This
build will not have been validated.**

---

## 0. PROMPT 15 preamble

Pasted and followed, VM clauses included. **No clause was deleted.**

The job card's stop condition on this point did not fire. The copy at
`C:\Users\bmcki\OneDrive\Desktop\Claude Prompts\FrontierAI_CC_Prompt_Library.md`
is 925 lines and carries PROMPT 15 at line 645 with its notes at 878. It is
current, so the run proceeds.

Both required reports were read in full before any code was touched:
`2026-08-27_v143_validation_closeout.md` (1181 lines) and
`2026-08-27_v143_runner_closeout.md`.

---

## 1. State at the time of writing

| Task | State |
| --- | --- |
| Job card moved to `docs/cc_jobs/`, committed | **DONE**, `4c3ee45` |
| TASK 1, prove both fixes on cfv-178 | **STAGED AND BLOCKED.** Box running, patches and job staged and hash-verified on it. Needs one RDP login to start the runner |
| TASK 2.1 kill switch | **FIXED**, `6b48a41` |
| TASK 2.2 switch-provider | **FIXED**, `e26a562` |
| TASK 2.3 SECURITY_FINDINGS | **FIXED**, `c2cb37b`. Enumeration in section 5 |
| TASK 3.1 coverage enumeration | **DONE**, section 6 |
| TASK 3.2 extend coverage | **DONE**, `cec07a6` |
| TASK 3.3 AST sweep as a build gate | **DONE**, `e923480` + `1d56f2f`. Both canary readings in section 7 |
| TASK 4 version, build, sign, ledger | **NOT STARTED.** Gated on TASK 1 by the job card's own ordering |
| TASK 5.1 cards, commits, push | **DONE.** Cards `#289`–`#292`. `origin/main` at `1d56f2f` |
| TASK 5.2 `#284`–`#288` left in Review | **DONE** — untouched |
| TASK 5.3 close-out | this file |

`origin/main`, from `git ls-remote origin main`:

```
1d56f2f88e75826fba61f21dceb14f55b675a0ab	refs/heads/main
```

---

## 2. TASK 1: staged, calibrated, and waiting on a keyboard

`cfv-178` was started from its deallocated state.

```
az vm start -g clawfactory-validation -n cfv-178   ->  START_EXIT=0
az vm show  -d  ->  VM running   4.154.56.193
```

**Cost of the window.** Standard_D2s_v4 in westus2 is roughly **$0.10 per hour**
of compute while running; the OS disk bills whether or not it runs. The intended
window is one to two hours, so **about $0.10 to $0.20**. Money is not the
constraint here and never has been; operator availability is.

### 2.1 The box came back with no interactive session, as expected

Read through `az vm run-command`, which runs as SYSTEM:

```
APPDIR_EXISTS=True
RES|clawfactory-stop.ps1|2581          <- the shipped v1.4.3 bytes
RES|switch-provider.ps1|20141          <- the shipped v1.4.3 bytes
JOBS_EXISTS=True
HEARTBEAT=2026-08-27T17:23:32          <- stale, from before the deallocate
quser : No User exists for *
AutoAdminLogon=
WSL_LIST_RC=-1
Running WSL as local system is not supported.
Error code: Wsl/WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED
```

That last pair is the PROMPT 15 clause reproducing itself first-hand: every WSL
probe needs the interactive session, auto-logon is not armed, and no amount of
`run-command` gets round it. Hence the card at the end of this session.

### 2.2 What is staged, hash-verified at the far end

```
STAGED C:\cfv\patch\clawfactory-stop.ps1 sha256=F19E9C7769A02EEED1E32117F371424AF23AB86BF98AC9D3A020CEAAA22DE314 size=8647   MATCH=True
STAGED C:\cfv\patch\switch-provider.ps1  sha256=AF5C78E4FCF8461414CDD9965B64ECF7861760FB55E4E497A77AD93044A4932B size=21388  MATCH=True
STAGED C:\cfv\jobs\t1.job.ps1            sha256=3042FAFACB6EF6618E2EE34829323CD7D86CC676BDCFCC81958D889346A8A700 size=10682  MATCH=True
```

The job runs nine sections. Its shape is the point: **for each fix, the control
is the SHIPPED v1.4.3 script and it must FAIL in the same run.**

| § | What runs | Expected |
| --- | --- | --- |
| S0 | bring the gateway up | precondition, two readers must agree |
| S1 | **CONTROL** shipped `switch-provider.ps1 -Provider ollama` | must FAIL, `VariableIsUndefined` |
| S2 | **CONTROL** shipped `clawfactory-stop.ps1` | must FAIL: syntax error, exit 0, gateway STILL UP |
| S3 | apply the v1.4.4 candidates, box only, originals backed up | hashes reported |
| S4 | **SUBJECT** v1.4.4 `switch-provider.ps1` | completes, firewall applied, honest Ollama line |
| S5 | **POSITIVE CONTROL** for the fail-closed toolchain guard | must REFUSE |
| S6 | gateway back up | precondition |
| S7 | **SUBJECT** v1.4.4 `clawfactory-stop.ps1` | gateway DOWN by both readers |
| S8 | **FAULT INJECTION** same script, distro that does not exist | must refuse to claim success, exit non-zero |
| S9 | restore the box to shipped v1.4.3 | hashes reported |

Two readers, never one: HTTP where **only 2xx counts as up**, and a process count
taken inside the distro. Port 8787 is the root-owned gating proxy and answers 502
while the gateway behind it is dead, which is the reader defect that voided a
phase on 2026-08-27.

### 2.3 The quoting claim was calibrated locally first, on a synthetic target

PROMPT 15 requires a probe to produce a known-correct result on a rigged input
before it reports on a real one. `cmd /c echo <arg>` prints an argument exactly as
it survived PowerShell's native command-line construction:

```
--- OLD payload (v1.4.3) as it arrives at the child ---
"if pkill -u clawuser -f "[o]penclaw agent" 2>/dev/null; then echo "(killed running agent turn(s))"; else echo "(no running agent turns)"; fi"

--- NEW payload (v1.4.4) as it arrives at the child ---
"if pkill -u clawuser -f '[o]penclaw agent' 2>/dev/null; then echo CF_TURNS_KILLED; else echo CF_TURNS_NONE; fi"
```

The old argument is wrapped in double quotes with its own double quotes **not
escaped**, so it terminates at `-f "` and bash is handed a fragment — which is
exactly the reported `syntax error near unexpected token '('`. The new one is a
single intact argument. **The root cause is PowerShell's argument quoting, not
wsl.exe's re-quoting**, which is a small correction to the mechanism recorded in
the v1.4.3 close-out; the fix is the same either way.

All three payloads the fixed script builds were then enumerated from its AST:

```
PAYLOAD 1: has-double-quote=False  len=110
PAYLOAD 2: has-double-quote=False  len=51
PAYLOAD 3: has-double-quote=False  len=163
PAYLOAD_COUNT=3 (expected 3)
```

---

## 3. TASK 2.1: the kill switch, and the defect underneath it

Commit `6b48a41`. Two defects, not one.

**The quoting** is described above and is the smaller half. **The larger half is
that the script reported success for a step that failed.** It discarded both exit
codes and printed its banner unconditionally. That is the shape of `#286`, where
the uninstaller discarded its teardown's output and logged success regardless.

The fix is not "capture the exit code". Exit codes are captured, but the closing
summary is decided by a **verification taken after the stop**: a count of the
agent's processes inside the sandbox. Three states, and the output says which:

* verified and zero -> the success message, per claim;
* verified and non-zero -> named as still running, with `wsl --shutdown` as the fallback;
* unverified -> **no claim in either direction**, and exit 2.

`CF_VERIFY_OK` is printed only when `pgrep` actually exists, so an unverified
state cannot read as zero. The reader is a process count and not an HTTP probe
for the 8787 reason above.

`Invoke-StopWsl` **refuses** a payload containing a double quote rather than
escaping it. A silent escape would work and would let the next author reintroduce
the shape without noticing; a refusal is visible.

## 4. TASK 2.2: switch-provider, and the sentence the job card asked for

Commit `e26a562`. The four sites are escaped as `` `$baseHosts ``.

**Say so in the close-out, as instructed:** `3818bc0` fixed a real and serious
defect — the provider switch re-seeding seven toolchain hostnames into the set
nothing can revoke, silently defeating the user's toggle while the panel reported
it as off. **The fix's own explanatory comments broke the script**, for every
provider, and nothing noticed because nothing had ever executed it. **That is the
third time in this cycle that the artifact of a fix caused the next defect.** It
is why this session's response to it is a build gate rather than four backticks.

The minor at the old line 155 is fixed in the same commit: it printed
`[x] Ollama running with model llama3.1:8b` unconditionally, on cfv-178
immediately after the shell said `ollama: command not found`. It now asks the
sandbox whether the model is present and reports the answer, and the firewall
change still applies either way.

---

## 5. TASK 2.3: the structural table, enumerated

The job card is explicit that the enumeration is the deliverable and the one
corrected row is not. So: every row of the structural table, and whether it has
evidence behind it or is there by assumption.

### 5.1 What the row was, and what it should say now

The row read *"Kill switch, so you can stop everything immediately | Terminates
the real agent process | **Proven.**"* It terminated nothing, on every release.

**Decision: the row is REMOVED from the structural table** and given a residual
section of its own. Two reasons, and the first survives validation:

1. **A kill switch is an action you take, not a boundary that holds.** The table's
   own header says these guarantees "hold regardless of what the agent does" and
   "a hostile agent cannot route around these". A stopped process running as the
   agent's identity can be started again by that identity. What the kill switch
   can honestly guarantee is that when you run it, it tells you the truth about
   what it managed to stop — which is a different kind of claim.
2. **This build will not have been validated when the document ships.** The fix is
   proven by hand-patching an installed box with the shipped script as a failing
   control. That is real evidence and it is not a clean-install measurement, and a
   claim does not enter that table on the strength of a hand-patched box.

A row saying "not proven" inside a table whose header promises proven structural
guarantees would contradict the table rather than qualify it. Removal plus a named
residual is the honest shape.

### 5.2 The enumeration, which found the row was not the only problem

The paragraph above the table said: *"Every claim in the structural table below was
proven consumer-side: by asking the agent itself to cross the boundary and
recording its actual output."* **That sentence was false for three rows, not one.**

| # | Row | Evidence behind it | Verdict |
| --- | --- | --- | --- |
| 1 | **File isolation** | Consumer-side, the agent's own output: refused an ungranted file by direct path, by directory listing, through a symlink, through `../../..`, and via filesystem-wide search; `/etc/shadow` denied; positive control read a granted file in the same run | **Evidenced, consumer-side.** Strongest row in the table |
| 2 | **Egress allowlist** | Consumer-side and repeatedly: non-allowlisted hosts, raw IPs, non-standard ports and arbitrary resolvers blocked, across the `SP.*` and `TC.*` phases through v1.4.1 | **Evidenced, consumer-side**, with the scoping residual already stated |
| 3 | **Inbound deny** | **Producer-side only.** The gateway binds loopback, no listening surface is exposed, the Windows inbound block is present. `PHASE2_5_MOUNT_2026-07-14.md:156` flagged this in July in as many words: *"the rule exists" (producer). Not "a connection from another host is actually refused" (consumer).* No run has ever driven a connection from a second host | **Assumption-adjacent.** Real evidence, weaker class than the sentence claimed. **Status column now says so** |
| 4 | **No send path at the agent's identity** | Consumer-side and strong: `clawuser` to SMTP 465/587/25 gives ETIMEDOUT, with a control that CONNECTED (`220 smtp.gmail.com ESMTP`) proving the reader worked | **Evidenced, consumer-side** |
| 5 | **Approval binding** | Measured: a mutated payload is rejected, and a replayed approval returns `ESTATE request is already sent` | **Evidenced** |
| 6 | **Quarantine hold** | Measured at the identity level: `runuser -u clawuser -- rm -rf /var/lib/clawfactory/quarantine` gives Permission denied, and the directory cannot even be listed. The hold is the claim; the *routing* is already disclosed as advisory | **Evidenced** for the hold, as the row already says |
| 7 | **Credential protection** | **Ownership and file mode, not a refusal:** `mode=600 owner=root:root`, measured. Worth recording that `S.4` once printed `0600 root:root` as a hardcoded literal rather than a measurement — the same defect class as the kill switch, caught and fixed in the v1.4.0 completion run | **Assumption-adjacent by method**, and unavoidably so: the agent is provisioned its own key by design, so a consumer-side test would not be a refusal in any case. **Status column now says so** |
| 8 | **Safety-rules integrity** | Consumer-side: the agent cannot write, chmod, or delete-and-recreate the file | **Evidenced, consumer-side** |
| 9 | ~~**Kill switch**~~ | **None. Never executed on an installed machine by any current phase.** Present by assumption for the entire life of the product | **REMOVED** |

**The transferable finding is not row 9.** It is that a universal sentence
("every claim … was proven consumer-side") was carried over a table containing
rows that cannot be proven that way at all. Rows 3 and 7 were always weaker than
the sentence; nobody noticed because nobody read the sentence as a claim about
each row. The paragraph now states the exception and both Status columns carry
their own method, so the claim and the evidence sit in the same cell.

### 5.3 Where the table is mirrored, and what was done

| Location | Claim | Action |
| --- | --- | --- |
| `SECURITY_FINDINGS.md:44` | the structural row | **Removed**, residual section added |
| `SECURITY_FINDINGS.md` Door 2 residual | "and is still stopped by the kill switch" | **Removed** — untrue when written |
| `SECURITY.md:19` | kill switch listed among OS-enforced structural controls | **Corrected** |
| `README.md:32` | "stops the gateway and the agent processes" | **Corrected** |
| `SUPPORT_MATRIX.md:46` | "kills the agent **containers**" | **Corrected.** Also stale: Docker was removed in 2026-07 |
| `docs/RELEASE_NOTES_v1.4.3.md:73, :201` | the claim, twice | **Left.** The same document already contradicts itself deliberately at :332–:352, which states the defect plainly and says the notes are for the release that fixes it. Unpublished, and rewriting v1.4.3's notes is outside this job |
| `docs/index.html` and the **live site** | kill switch presented as a security control, in the meta description, the hero, the controls table and both feature lists | **NOT changed.** The live site serves from a separate repository and publishing is an irreversible public action. **This is an operator decision and it is listed in section 10** |

---

## 6. TASK 3.1: the coverage table, derived from the harness

Not from memory. A script reads the `.iss` `[Files]` section for the shipped set,
then searches two harness generations for each name and classifies every hit as
execution or as payload-rendering.

```
SHIPPED_PS1_COUNT=10
CURRENT_HARNESS_FILES=59  LEGACY_PROBE_FILES=5
```

| wrapper | payload sites | CURRENT suite | LEGACY probes | renders payload only |
| --- | --- | --- | --- | --- |
| `setup.ps1` | 50 | **EXECUTES** | -- | yes |
| `post-install.ps1` | 3 | -- | -- | -- |
| `bootstrap.ps1` | 7 | -- | -- | -- |
| `rename-agent.ps1` | 0 | -- | -- | -- |
| `launcher.ps1` | 3 | -- | -- | -- |
| `clawfactory-stop.ps1` | 1 | -- | **EXECUTES** | -- |
| `clawfactory-grants.ps1` | 4 | **EXECUTES** (dot-source) | EXECUTES | -- |
| `switch-provider.ps1` | 7 | -- | -- | **yes** |
| `uninstall.ps1` | 4 | -- | -- | -- |
| `smoke-test.ps1` | 10 | -- | **EXECUTES** | -- |

CURRENT = `validation\`, the phase-runner suite every run since v1.2.0 uses.
LEGACY = `scripts\probe-v10*.ps1` and `azure-probe.ps1`, the retired v1.0.x
one-shot probes.

**The instrument was canaried before it was trusted.** Planting a harness file
that executes `clawfactory-stop.ps1` flips its CURRENT column from `--` to
`EXECUTES`, so a `--` is a measurement and not a blind spot. The canary also
caught the instrument passing **vacuously**: the first run reported
`LEGACY_PROBE_FILES=0` because of a bad `Get-ChildItem -Include` glob, so every
`--` in that column meant "nothing was searched". The file count is now printed
and an empty set warns in the output.

### 6.1 The finding that is worse than "never executed"

`switch-provider.ps1` was never executed, and `validation/sp-prefix-fw.sh` states
its own nature in its first line: *"GENERATED, DO NOT EDIT. The firewall block of
resources/switch-provider.ps1 as it stood at commit 9710c5a, rendered."* That is
the gap the job card describes, and it is real.

But **the kill switch was executed** — by `scripts/probe-v1039-validation.ps1:237`
and `scripts/probe-v1047-validation.ps1:250`, on boxes, in July:

```powershell
if (Test-Path $ks) { W ((& powershell -NoProfile -ExecutionPolicy Bypass -File $ks 2>&1 | Select-Object -Last 8 | Out-String)) }
```

It ran, and nothing asserted on the result. It kept the **last eight lines**. The
script printed its two bash syntax errors early and its four-line false success
banner last, so — **INFERRED from the script's line ordering, not from a retained
transcript** — the tail those probes preserved was precisely the part that was
untrue, and the part that would have exposed it was discarded by the slice.

**So the lesson is not "execute the wrappers". It is "execute them and assert on
something that can fail."** Both the new build gate and the new phase are built to
that standard: every row asserts on a named string or a measured state.

---

## 7. TASK 3.3: the new build gate, and both canary readings

The v1.4.3 session's AST sweep was a scratchpad instrument and was deliberately
not committed, so it was **rebuilt from its description and re-canaried from
scratch** rather than lifted. It is now the ninth pre-build gate in
`scripts/build_release.ps1`, named `Interpolation gate` in the style of the
existing eight.

### 7.1 Canary reading 1 — it FAILS on a planted defect, naming file and line

One instance planted in a shipped script, in the real shape (a bare variable in a
here-string comment), then the real build script run:

```
SOUL pin OK: e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
Bundle check OK: all 34 preflight resources are in [Files].
Fail : build_release.ps1: UNDEFINED INTERPOLATION in shipped scripts. PowerShell expands these;
they are not prose. Escape each as `$name, or reword so no dollar sign appears --
resources\switch-provider.ps1:194 $plantedCanaryVar inside a DoubleQuotedHereString
(file sets StrictMode: this is FATAL at runtime)
BUILD_EXIT=1
```

File, line, variable, string kind, and the runtime consequence. Exit 1, before
ISCC is invoked. The planted line was then restored with `git checkout --`.

**It did not pass on the first attempt, and that is recorded rather than tidied
away.** Two defects in the instrument, both fixed in `1d56f2f`:

1. `$Matches` was read after a second `-match` had already overwritten it, so the
   `.ps1` filter yielded `$null` and the gate tried to parse the repository root
   as a file.
2. The remediation advice was built inside a double-quoted string, where the
   backtick escaped the dollar and the text printed as `Escape each as ,`.

Both are the class the gate exists to catch. "The canary passed" and "the canary
passed first time" are different claims, and only the first is true.

### 7.2 Canary reading 2 — it does NOT fire on a clean tree, or on things that look like the defect

Against the real pre-fix `switch-provider.ps1`, it reproduces the v1.4.3 reading
exactly:

```
File                       Line Var        Kind
switch-provider.PREFIX.ps1  182 $baseHosts DoubleQuotedHereString
switch-provider.PREFIX.ps1  185 $baseHosts DoubleQuotedHereString
switch-provider.PREFIX.ps1  194 $baseHosts DoubleQuotedHereString
switch-provider.PREFIX.ps1  235 $baseHosts DoubleQuotedHereString
TOTAL = 4
```

Against a synthetic file built to look like **what I was afraid of missing**
rather than what I had already found — six shapes and five negative controls:

```
canary-strict.ps1    9 $shapeOneUndefined   DoubleQuotedHereString   <- bare var in a here-string COMMENT
canary-strict.ps1   15 $shapeTwoUndefined   DoubleQuotedHereString   <- executable position
canary-strict.ps1   19 $shapeThreeUndefined           DoubleQuoted   <- single-line double-quoted string
canary-strict.ps1   23 $shapeFourUndefined  DoubleQuotedHereString   <- $() sub-expression
canary-strict.ps1   28 $shapeFiveUndefined  DoubleQuotedHereString   <- member access
canary-strict.ps1   33 $shapeSixUndefined   DoubleQuotedHereString   <- nested method call
TOTAL = 6
```

**6 of 6 planted shapes found. 0 of 5 negative controls fired** — an escaped
`` `$name ``, `$env:` drive qualification, a `param()` variable, a single-quoted
here-string, and automatic variables are all correctly silent.

And on the real fixed tree, all ten shipped scripts: **TOTAL = 0**.

### 7.3 What the gate cannot catch

Written into the gate's own comment block so its OK line is never read as more
than it is:

* A variable assigned **somewhere** in the file but not yet assigned at the point
  of use. "Defined anywhere" is the test, not "defined by now".
* A variable a dot-sourced library defines. That is the false-**positive**
  direction, not a miss; there are none today.
* A shell variable correctly escaped as `` `$x `` but semantically wrong. The gate
  checks that PowerShell will not eat it, not that bash wants it.
* Anything outside the `.iss` `[Files]` set — the validation harness and the build
  scripts are not swept.
* **The sibling defect it deliberately does not look for:** a bash payload
  carrying its own double quotes, which PowerShell fails to escape when building a
  native command line. That is what made the kill switch inert, it is a different
  shape, and `clawfactory-stop.ps1` refuses such a payload at runtime instead.

### 7.4 Two deliberate departures from the specification

Both stated in the gate's comment block, both measured before being taken.

1. **It runs BEFORE the worktree pin gate.** A source lint that only ever sees
   committed bytes cannot be canaried without committing the defect it exists to
   catch. Running it first means a planted instance in a dirty tree reaches it.
2. **It sweeps all ten shipped scripts, not only the seven that set StrictMode.**
   Without StrictMode the same shape is not fatal — it silently interpolates an
   **empty string** into a shell payload, which is how a probe once turned
   `grep -q "$ip"` into `grep -q ""` and matched everything. Measured both ways
   before widening: the tree reads TOTAL = 0 either way, so the wider scope costs
   nothing today and closes the blind spot for tomorrow. StrictMode status is
   reported per finding instead of used as a filter.

---

## 8. TASK 3.2: what was added to coverage

`validation/interim-v144-wrappers.ps1`, committed at `cec07a6`, under the phase
runner so the mechanical rules apply.

| Row | Wrapper | Assertion |
| --- | --- | --- |
| WR.1 | `smoke-test.ps1` | its own `N pass, N fail, N skip` summary line, with that line's presence as the control |
| WR.2 | `launcher.ps1` | `[STARTED]`, not `[ALREADY_RUNNING]`, against a genuinely down gateway |
| WR.3 | `clawfactory-stop.ps1` | gateway down by **two** readers, with a precondition that it was up by both |
| WR.4 | `clawfactory-stop.ps1`, fault-injected | must **refuse** to claim success; fault-landed control included |
| WR.5 | `switch-provider.ps1 -Provider ollama` | builds its payload and completes; firewall reader controlled |
| WR.5b | same | does not print an earned-looking Ollama line when Ollama is absent |
| WR.6 | the fail-closed toolchain guard | must **refuse** when a base host is made to look like a toolchain host |
| WR.7 | `post-install.ps1 -Provider later` | executes; the no-credential branch |
| WR.8 | `bootstrap.ps1` | executes; documented idempotent |
| WR.9 | `clawfactory-grants.ps1` | dot-sources and defines its functions, with a malformed-library control |

**The two that cannot be run, and their named substitutes** — recorded as INFO
rows carrying their reason, because a wrapper that was skipped and one that passed
must never look the same in a results file:

* **`rename-agent.ps1`** blocks on a modal `MessageBox` and never returns without a
  human click, so an unattended phase that ran it would **hang rather than fail**.
  It also builds no payload for another interpreter, so it is outside the defect
  class. **Substitute:** AST parse plus an assertion on the message text, and one
  by-hand click in the operator checklist.
* **`uninstall.ps1`**: running it is the destruction it performs, ending the
  install the phase is measuring. **Substitute:** it is already covered on its own
  box by `interim-v141-uninstall.ps1`, through the real dialog, against a held
  before-state.

WR.5 and WR.6 sit behind `-RunProviderSwitch`: switching to ollama replaces the
active provider and would confound any later phase on the same box. Ollama is the
only provider needing no credential, which is why it is the one used.

---

## 9. TASK 5.3 answer 5: the full validation scope for v1.4.4

**Stated plainly, because the job card asks for it plainly: this is the full
matrix plus sections 14.1 through 14.12 plus the new wrapper coverage. It is not a
re-run of what broke.**

The premise is the one this whole cycle was built on and it has not weakened: **a
rebuild changes the binary, and prior measurements do not transfer across a
rebuild.** Every v1.4.3 measurement was taken against `b2cd6408…`. v1.4.4 is
different bytes. Nothing carries over, including the rows that passed.

Three separate debts stack here, and it is worth being explicit that this is not
one release's worth of work:

1. **v1.4.4's own changes** — two shipped scripts, one new build gate, one new
   phase.
2. **v1.4.3's coverage, which was never completed.** Its run stopped on the second
   ship-blocker: matrix rows 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 were **not
   run**, and neither was TASK 2 or TASK 3.
3. **v1.4.2, still substantially unmeasured.** Its changes live almost entirely in
   the keep-Linux uninstall branch, and none of that branch has been measured on
   any release. Of its six change areas only the launcher change was ever tested.

### 9.1 Cost, in boxes

| Box | Install variant | Carries |
| --- | --- | --- |
| **A** | normal, `-Provider claude` | Matrix rows 1, 3, 5–14. Sections 14.8, 14.9, 14.10, 14.11, 14.6. **The new `interim-v144-wrappers.ps1` phase, with `-RunProviderSwitch` LAST** because it replaces the provider. Then the RemoveAll branch, 16 rows, last of all |
| **B** | `-Provider later` | Matrix row 4 |
| **C** | licence host blocked, prior artifact as control | Matrix row 2 |
| **D** | normal | TASK 2 in full: install, keep-Linux uninstall through the real dialog, read-back against a held before-state, reinstall, teardown log, the fault-injected negative half, next-boot check. The rendered dialog rides here |

**Four boxes. Roughly 11 to 15 hours of wall clock and about 12 operator touches**
— the same shape the v1.4.3 run costed, because it is the same matrix plus one
phase. **It does not fit in one unattended session**, and the constraint is
operator availability at an RDP keyboard, not money: four `Standard_D2s_v4` boxes
plus disks is a few dollars.

**One addition to that plan, from this session.** The new wrapper phase should run
on box A **before** the RemoveAll branch and **after** everything else, with
`-RunProviderSwitch`, because WR.5 leaves the box on ollama. Adding it does not
add a box.

**`SP.8` is expected to FAIL.** It is the documented address-scoping residual, not
a regression. Do not adjust, retire or invert it.

---

## 10. Waiting on the operator

1. **Whether to delete `cfv-178`.** The command is printed in section 11 rather
   than run. It costs money either way and the call is his.
2. **The live site.** `clawfactory.app` presents the kill switch as a security
   control in five places — meta description, hero, controls table, and both
   feature lists — and it serves from a separate repository. The repo-side claims
   are corrected; the published ones are not, and publishing is an irreversible
   public action.
3. **`docs/RELEASE_NOTES_v1.4.3.md`** still carries the claim at two lines while
   contradicting itself deliberately further down. Unpublished. Whether v1.4.4 gets
   its own notes is a separate decision.

