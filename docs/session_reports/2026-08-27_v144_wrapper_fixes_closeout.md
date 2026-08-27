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

*Sections 5 to 9 — the structural-table enumeration, the coverage table, the two
canary readings, the build, and the v1.4.4 validation scope — are written as they
complete. See the task table in section 1 for what is done and what is not.*
