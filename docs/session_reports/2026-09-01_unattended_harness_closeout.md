# Card #259 — the unattended validation harness. Close-out

**Date:** 2026-09-01. **Repo root:** `C:\Users\bmcki\ClawFactory-Secure-Setup` (confirmed by
`git rev-parse --show-toplevel`). **Branch:** `main`. **Session start commit:** `53a54db`, tree
clean.

**No product code was touched.** `setup.ps1`, `resources/`, the `.iss` and every bundled file are
unmodified. **Nothing was signed, tagged, released, or written to `released-versions.tsv`.** No
v1.5 work.

**Box:** `cfv-192`, `Standard_D2s_v4`, image `clawfactory-win11-baseline-v2`, resource group
`clawfactory-validation`. Created `--nsg-rule NONE` with **no RDP rule at any point**. Torn down
in full.

---

## 1. The number, which is the deliverable (TASK 6.4)

> **REVISED 2026-09-01, after the operator's decision in §6.1.** The number below was
> originally **5 per four-box cycle**, carrying one provisioning touch per box. The operator
> took the recommendation and removed that touch. The revised number stands.

**The next validation cycle needs ONE operator interruption for the whole cycle, regardless of
how many boxes it uses** — a single batched end-of-run card — plus the release, if the cycle
ends in one.

For a four-box cycle shaped like v1.4.4 that is **1–2 interruptions, against the 13–15 that
cycle actually cost.**

| | Irreducible? | Why |
|---|---|---|
| ~~Set the admin password at `az vm create`~~ | **REMOVED** — §6.1 | The session generates it inside the command; the value is never seen, printed or stored |
| **One end-of-run batch** carrying M-1…M-6, M-9 | **Cannot be removed today**, but see §6.4 | Rendered dialogs and panels read by eye. I cannot RDP to a validation VM without driving `mstsc` on the operator's own desktop, which a standing rule forbids |
| **Enter the real SMTP credential** (M-3) | **Irreducible** | A live secret with reach beyond the box. Folds into the batch |
| **Create the GitHub Release** (M-11) | **Irreducible** | A public action. Belongs to the release job, not the validation run |

**Two different kinds of removal, and the distinction matters.** The runner start and every
restart were *transport* — no measurement got cheaper, it simply stopped needing a person. The
provisioning password was removed by a **decision**, not an engineering change; it was never a
measurement at all.

**What remains is only ever what a person must see or authorise.**

---

## 2. TASK 0 — the census

### 2.1 What each cycle actually cost

| Cycle | Touches | Detail |
|---|---|---|
| **v1.4.3** (`cfv-178`; 4 planned, 1 provisioned) | 1 spent, ~12 planned | Run stopped on its second ship-blocker before rows 10 and 11 were reached |
| **v1.4.4** (A, B, C, D + completion, 4 sessions) | **13–15** | Box A: 5. Boxes B+C: 2–3. Box D: 4. D-completion: the rest |
| **v1.4.5** (E, F, `cfv-191`, publish) | **7+** | `cfv-191` alone needed 3: create, start runner, **restart runner after the reboot** |

**The measured cost of the removable one.** On `cfv-191`, Windows came back at **`18:55:19`** and
nothing ran until the operator logged in at **`19:49:24`**
(`2026-08-31_systemd_reboot_persistence_closeout.md`). **54 minutes of dead wall clock, on one
box, on one reboot.**

### 2.2 Classification

11 checks enumerated in `validation/MANUAL_CHECKS_REGISTER.md`.

- **Removable by this job:** the runner start and every restart. ~8–10 of v1.4.4's touches.
- **Irreducibly human:** 3 — two credentials, one public action.
- **Human but batchable:** 7 — Studio panels, three dialogs, the rename modal, the logon-flash
  observation, `OM-1`.

**Most of the cost is one thing, and the card's other two items are worth much less.** Reported in
§6.

---

## 3. TASK 1 — the premise was half wrong, and the mechanism is not the one specified

### 3.1 The correction

The card said auto-logon is one-shot so a rebooted box comes back with no session. True of
Windows; **false of this fleet, which armed no auto-logon at all.**

> `2026-08-27_v143_validation_closeout.md:320` — *"`AutoAdminLogon=` is empty and was **asserted
> rather than set**. The driver arms no auto-logon."*

All four implementations in the tree (`interim-v120-validate.ps1:436`, `job3-validate.ps1:275`,
`scripts/azure-validate.ps1:449`, `scripts/egress-persistence-probe.ps1:211`) obtain the password
by **resetting the account with `az vm user update`** and writing it in cleartext to
`HKLM\...\Winlogon\DefaultPassword`. PROMPT 15 forbids both halves.

**So the question was never "make a one-shot survive". It was "get a non-SYSTEM context without a
credential".** The preamble's `Not scriptable around` was an inference from the credential rule
stated as a fact about Windows, and it governed three cycles. Corrected in
`docs/VALIDATION_PREAMBLE.md`.

### 3.2 S4U was tried first and is DENIED — measured, with controls

An S4U scheduled-task principal gives a token for a local account with **no password**. It does
not work here:

| Attempt | Result |
|---|---|
| `Register-ScheduledTask -LogonType S4U -RunLevel Highest` | **Access is denied.** |
| `Register-ScheduledTask -LogonType S4U -RunLevel Limited` | **Access is denied.** |
| `schtasks /Create /XML` with `<LogonType>S4U</LogonType>` | **Access is denied.** (exit 1) |
| the same S4U call from **Task Scheduler's own SYSTEM task** | **Access is denied.** |
| `-LogonType ServiceAccount` / SYSTEM | **succeeds** ← control |
| `-LogonType Interactive` / clawadmin | **succeeds** ← control |

Two controls succeeded in the same run, so the context can register tasks and the denial is
specific to S4U. The obvious cause was ruled out by measurement:
`SeBatchLogonRight = *S-1-5-32-544` (BUILTIN\Administrators), and `clawadmin` is SID `…-500`, a
member — **the target account holds the right it needs.** Caller held `SeTcbPrivilege` and
`SeImpersonatePrivilege`.

**Recorded as a measured negative, not an inference.**

### 3.3 What ships instead, and the honest split

Two tasks, because the two things a runner does have different requirements and only one is free:

- **`CFV-Runner-System`** — SYSTEM / ServiceAccount / **AtStartup**. Comes back at every boot with
  no logon and no credential. Services `jobs\`: every Windows-side measurement.
- **`CFV-Runner-User`** — clawadmin / Interactive / AtLogOn. Services `wsljobs\`: anything touching
  `wsl.exe`, which refuses SYSTEM by name. **Cannot come back on its own after a reboot.**

**Windows-side work is now unattended across reboots. WSL work is not, and cannot be without a
credential.** A WSL job dropped with no session reports **`RunnerAbsent`** — a named precondition,
never a product verdict. Measured on `cfv-192`:

```
WSL-queue poll condition: RunnerAbsent
  no runner has ever beaten on this queue and its task state is 'Ready'. For the WSL queue this
  means there is no interactive session, which is an unmet PRECONDITION and never a product verdict.
```

### 3.4 TASK 1.2 — the security implication, and confinement

**No credential is created, stored, printed or requested.** Asserted on the box at the end of
arming: `ARM_WINLOGON_AUTOADMINLOGON=` (empty), `ARM_WINLOGON_DEFAULTPASSWORD_PRESENT=False`.

This is **strictly less exposure than what it replaces.** The forbidden drivers leave a cleartext
administrator password in the registry, which survives into any snapshot. This leaves nothing.
What remains is a SYSTEM autostart on a throwaway VM with no inbound path, deleted with its disk.

**Confinement, verified by execution, not asserted:**

1. `ClawFactory-Secure-Setup.iss` `[Files]` names only `LICENSE`, `NOTICE`, `README.md` and
   `resources\*`. **Zero `validation\` sources.**
2. `grep` over `setup.ps1`, `resources/` and the `.iss` for any new filename or either task name:
   **0 hits.**
3. `resources/uninstall.ps1` removes tasks by an **explicit three-name list**, not a pattern.
4. Only delivery route is `az vm run-command` against `clawfactory-validation`.

### 3.5 TASK 1.3 — the runner restarts itself. Measured, twice, then a third time

```
REBOOT PROVED: 2026-09-01T19:35:47Z -> 2026-09-01T20:13:52Z
RUNNER RESTARTED ITSELF: heartbeat 4s old after the reboot, with no interactive login.

REBOOT PROVED: 2026-09-01T20:13:52Z -> 2026-09-01T20:20:52Z
RUNNER RESTARTED ITSELF: heartbeat 4s old after the reboot, with no interactive login.
```

And a third time incidentally, through the deallocate/start cycle in the break tests
(boot `20:52:45`). A job ran to completion on the far side of each — **a process existing and a
runner that can still execute work are different claims:**

```
p2: JOB_BOOT=2026-09-01T20:13:52Z  RUNNER_EXITCODE=0
p3: JOB_BOOT=2026-09-01T20:20:52Z  RUNNER_EXITCODE=0
```

`query session` at the end of the run showed **no user logged on at any point**. Every job ran as
`nt authority\system`, session 0.

**Why this survives where the product's resume path does not:** `ClawFactory-Resume` is registered
by the installer mid-install and unregisters itself on completion; and the product's
`ClawFactory WSL Host` task uses `<LogonType>InteractiveToken</LogonType>`, so its `BootTrigger`
cannot produce a token with no session. That is exactly the 54-minute gap on `cfv-191`. This task
is a standing `ServiceAccount` principal, which needs no session at all.

---

## 4. TASK 4 — the four defects, and the five more the box found

### 4.1–4.4, as specified

| | Status |
|---|---|
| **4.1** heartbeat froze during a synchronous job | **Closed.** `Start-Process` child + heartbeat stamped from the wait loop, naming its state. Measured: `JobRunning ... elapsed=85` *during* a 3-minute job |
| **4.2** `run-command` returns empty above ~16 KB at exit 0 | **Closed, and the premise was wrong twice over** — see §4.5 |
| **4.3** `C:\cfv` unscoped | **Closed.** `C:\cfv\runs\<RunId>\` + `_owner.json`. `C:\cfv` kept as root because **80 files** reference it |
| **4.4** unconditional success line | **Closed. 12 found, 7 fixed, 5 adjudicated, 0 unadjudicated** |
| **4.5** clauses | 5 added to `docs/VALIDATION_PREAMBLE.md` |

**The 4.4 census.** `validation/cfv-successline-census.ps1`, AST-based, and it re-parses the
*content* of every string literal that parses as PowerShell — because the two known live instances
are inside a here-string and a file-level AST walk is structurally blind to them.

It caught two defects in itself before scanning anything real. The second matters: it **passed
calibration and then reported both known live instances clean**, because `Test-Path` was in its
guard pattern and `if (Test-Path $source) { upload; report }` is the wrapper around both. The
canary lacked that wrapper. *A canary only certifies the pattern against the shape of the canary.*

Fixed: `interim-v145-runner.ps1:171,195`; `diag/g4-probe.ps1:560,621` (which compounded 4.4 with
4.2 — "transcript saved" after an unbounded `Get-Content` through run-command);
`harness-selftest.ps1:460`; plus two unchecked `generate-sas` calls found in passing.

Not fixed, adjudicated in the instrument's own table: four instances in **drivers forbidden by
PROMPT 15** (repairing an instrument nobody may run would make it look blessed — the same argument
the v1.4.4 close-out made about its stale digest), and one false positive.

### 4.5 THE FINDING THAT OUTRANKS THE REST — a false pass in my own fix

**TASK 5.4 says a failure mode producing a false PASS outranks everything. This job produced one,
in the instrument built to prevent it.**

The inherited belief was that `az vm run-command` *"returns empty above roughly 16 KB"*. Measured
on `cfv-192`, **both halves are wrong**:

- The limit is **4096 bytes**, not ~16 KB. Bracketed: **3584 came back whole, 4096 did not.**
- It does **not** return empty. It returns **the last 4096 bytes** and silently discards
  everything before them.

A payload emitting 900 numbered lines came back as **78**, beginning mid-word:

```
[INE00822-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx]
 LINE00823-...
 ...
 LINE00900-...
```

**So a tail sentinel survives every truncation by construction.** The library's first version
carried only a tail sentinel and reported `Ok` on a reply that had lost 91% of its content.

**Closed:** a **head** sentinel and a tail sentinel, naming different faults — head gone means the
channel truncated, tail gone means the payload died early. Re-measured with the fix in place:

```
3584 bytes requested -> Ok               3774 returned, sentinel=True
4096 bytes requested -> OutputTruncated  4097 returned, sentinel=False
65536 bytes requested -> OutputTruncated 4097 returned, sentinel=False
```

Two consequences worth stating separately. `Receive-CfvJobOutput`'s chunk size was **6000 bytes,
itself above the ceiling**, so every chunk of a large `.out` was being head-truncated; only the
reassembled-byte-count assertion caught it. Now 2048, derived from the measurement. And **I read
past a live instance of this earlier in the session** — the `restart-runner` output began
mid-sentence at `t be greater than or equal to zero` and I did not flag it.

### 4.6 The other four the box found, all mine

1. **The heartbeat never stamped, and a silent catch hid it.** `'{0} … {5}' -f (Get-Date)…​ + 'Z', …`
   — `-f` binds **tighter** than `+`, so the format string got one argument and threw; an empty
   `catch { }` swallowed it. The runner ran perfectly while never stamping; the driver correctly
   read a zero-byte heartbeat and reported `RunnerDead` against a live runner. The runner log
   showed `RUNNER_LOOP_ERROR` **every five seconds**. *A silent catch inside the one function whose
   purpose is to prevent silence* — this job's own subject, committed in the fix for it.
2. **`RUNNER_EXITCODE=` came back empty.** `Start-Process -PassThru` with redirected streams
   returns a **null** `ExitCode` after exit. A job that failed and a job that passed were identical
   to the driver. Fixed by touching `.Handle` before waiting; emits `UNREADABLE` rather than an
   empty string.
3. **`wsl.exe` writes its own messages in UTF-16LE.** Read through an 8-bit console encoding they
   arrive with a NUL after every character, so a plain `-match` **fails against the exact string it
   is looking for**. The SYSTEM control fired on the box and the driver reported it had not. This
   one failed **safe**; the same defect on an assertion seeking a *success* string fails unsafe.
   `Test-CfvWslTextMatch`, calibrated 6/6 both ways against the real bytes.
4. **`BoxUnreachable` did not match Azure's actual message.** A deallocated box returns
   `(OperationNotAllowed) The operation requires the VM to be running (or set to run).` — none of
   the patterns I guessed in advance matched it, so it reported `DispatchFailed`. Found only by
   actually deallocating a box. Fixed, calibrated 3/3, **and re-tested on the real box.**

### 4.7 Two instrument defects I made and caught in passing

- **`grep -c $'\r'` reported CRLF in files that had none.** Caught by an `od`/`tr` byte count with
  both canary halves. The files were LF throughout.
- **`az --query "[?starts_with(code,'PowerState')]"`** hit the known `az.cmd` bracket re-parse trap
  in my own polling loop, failed 30 times, and **my loop did not check the exit code** — a direct
  violation of *check the exit code of every `az` call*. The box happened to be up.

**Ratio for this job: 9 instrument defects, 0 product defects.** Consistent with the last three
cycles, and the point of the exercise.

---

## 5. TASK 5 — the harness against a broken run

### 5.1 The unattended cycle

Fifteen steps, one box, **no RDP rule created at any point**. Every point at which the old harness
would have stopped for a human, and whether it did:

| Point | Old harness | This run |
|---|---|---|
| Start the runner after provisioning | RDP login | **No stop.** Registered by `run-command` as SYSTEM |
| Restart the runner after reboot 1 | RDP login | **No stop.** 4s heartbeat, no login |
| Restart the runner after reboot 2 | RDP login | **No stop.** 4s heartbeat, no login |
| Restart the runner after deallocate/start | RDP login | **No stop.** |
| Diagnose a stalled poll | Read by hand | **No stop.** Named condition |

**It stopped for a human exactly once: to create the box.**

### 5.2 / 5.3 The deliberate breaks, each with a control

| Break | Reported | Control |
|---|---|---|
| A job that **fails** | `JobDone`, `RUNNER_EXITCODE=1`, stderr captured under its own header, both markers present | `bok`: identical shape, `RUNNER_EXITCODE=0` |
| Output **over the limit** | `OutputTruncated`, `bof=False eof=True`, with the correct diagnosis | 3584-byte reply → `Ok` |
| A **colliding** dispatch | `DispatchConflict` detected 6×, waited out, then `Ok` after 32s | A collision that never clears → `DispatchConflict` by name |
| A **box that does not come back** | `BoxUnreachable` (after the §4.6.4 fix) | A `Conflict` and a generic error both → not `BoxUnreachable` |

**Calibrated in both directions.** `cfv-driverlib-selftest.ps1` runs 15 cases with 4 explicit
controls — a harness reporting everything as broken would fail them. **15/15.**

**And the self-test was itself proved able to fail.** I injected a false pass into a scratch copy
(`$cond = "Ok"` for a sentinel-less reply): `SELF.D1` and `SELF.D1b` FAILED, the run **stopped at
the critical gate** and exited **4**, and the control `SELF.D1ctl` still passed. When the sentinel
contract later changed to head+tail, **the self-test caught the stale rigs on its own** and gated
at exit 4 before I noticed.

### 5.4 A false PASS was found, and it is reported

Yes — §4.5. It was in my own defect-4.2 fix, it was found by measurement rather than reasoning,
and it is closed and re-verified. **This is the single most valuable thing the run produced**, and
it is precisely the outcome a green run could never have delivered.

---

## 6. Challenging the scope — three things (TASK 2, and the card's own question)

### 6.1 The admin password — DECIDED. It is the session's, not the operator's

**I recommended against my own TASK 2 conclusion, and the operator took the recommendation on
2026-09-01:**

> *"I don't see a reason for me to enter the passwords and get into the VMs if you can do it
> yourself."*

**The decision.** The session generates the validation VM's admin password inside the
provisioning command, so the value is never seen, never printed, never stored, and never enters a
transcript:

```
$pw = -join ((1..24) | % { [char](Get-Random -Input (48..57 + 65..90 + 97..122)) })
```

**Why the old clause bought nothing on these boxes.** A validation VM is created `--nsg-rule NONE`
with no inbound path, holds nothing, and is deleted within hours. A leaked password for it is
worthless — while the clause cost one human interruption per box per cycle. **A password nobody
knows is the correct design for a box nobody logs into.**

**What did NOT change, and for a separate reason.** `az vm user update` after provisioning stays
forbidden: an unchecked one hung the VMAccess extension and cost an hour on `cfv-162`, and it is
the route by which the forbidden drivers reset a live account. The two prohibitions were always
about different failures and only one of them has been lifted.

**Scope.** Validation VMs in `clawfactory-validation` only — boxes created to be measured and
deleted. This is not a licence to generate credentials anywhere else, and the preamble says so.

**Governing text updated in the same commit:** `docs/VALIDATION_PREAMBLE.md` — the
`Do not generate an admin password` clause is replaced by
`THE ADMIN PASSWORD IS THE SESSION'S, NOT THE OPERATOR'S`; Card 1 is no longer required at
provisioning; the `PUT-PASSWORD-HERE` placeholder is **retired**, and with it the only
placeholder the card format ever permitted; the worked card example is replaced with one for a
check only a person can make, because provisioning is no longer such a card.

### 6.4 What the decision unlocks, which is bigger than the touch it removed

Flagged as a consequence, not done here. **The session owning the password also makes persistent
auto-logon available without asking anyone for anything** — write `AutoAdminLogon` and
`DefaultPassword` with **no** `AutoLogonCount`, which is what makes it survive rather than fire
once. That would give a standing interactive session, and therefore:

1. **The WSL runner becomes unattended too.** §3.3's honest split — *"WSL work is not, and cannot
   be, without a credential"* — was true only while the credential was the operator's. It no
   longer is. This is the single largest remaining gap and the decision closes the route to it.
2. ~~**Screenshots become possible.**~~ **PROPOSED AND DECLINED, 2026-09-01.** A user-context
   runner could capture the Studio panels and drive the clicks with UI Automation, turning M-1
   from *"sit at the keyboard"* into *"approve these ten images"*. The operator declined, and
   the reasoning is worth keeping because it is better than the proposal:

   - **A human is the better instrument for reading UI copy.** Pixel-scraping an Electron panel
     to verify wording is the exact class of measurement this project keeps being burned by —
     see §4.7's tally. A misread panel is a wrong verdict about the thing under test.
   - *"It's not that big a hassle and I'll still need my PC available."*

   **So item 1 above is the whole of what §6.4 unlocks, and it is still worth building.** The
   WSL runner becoming unattended is a transport win with no measurement quality attached to it.
   Panel-reading is not, and should stay human.

**The cost, stated plainly:** a cleartext password in `HKLM\...\Winlogon\DefaultPassword` on a
throwaway box with no inbound path, deleted within hours. It cannot reach a customer machine —
`validation/` is bundled by nothing (§3.4). That is a real exposure and a small one, and it should
be taken deliberately in the job that builds it rather than assumed here.

**2. The manual/automated split removes zero interruptions.** It converts ~7 scattered ones into 1
batch, which is worth doing and is done (`MANUAL_CHECKS_REGISTER.md`), but it should not be
described as reducing the count.

**3. This job's own first step was an operator interruption.** A job to remove operator touches
began with one. That is the honest shape and it is not a failure of the design.

**The card listed three items. One of them carried essentially all the value.**

---

## 7. Resource ledger

**Starting state, unfiltered, before anything was provisioned** — already at expected residual, no
prior FAIL VMs or orphaned disks to sweep:

```
clawfactoryvalc467              Microsoft.Storage/storageAccounts
bake-vmVNET                     Microsoft.Network/virtualNetworks
clawfactory-win11-baseline      Microsoft.Compute/images
clawfactory-win11-baseline-v2   Microsoft.Compute/images
```

**Provisioned:** `cfv-192` only. Roughly 1h40m of `Standard_D2s_v4` including two deallocations,
so **well under $0.50**.

**Teardown**, NIC first because it references the public IP and the NSG, every exit code checked:

```
vm delete exit=0
nic cfv-192VMNic delete exit=0
pip cfv-192PublicIP delete exit=0
nsg cfv-192NSG delete exit=0
disk cfv-192_disk1_2daa412d8e0d46609360774795249573 delete exit=0
```

The teardown **enumerates rather than guessing names**, and that change was necessary: `az vm
create` named these `cfv-192PublicIP` / `cfv-192VMNic` / `cfv-192NSG`, none of which matched the
`$Vm-pip` / `$Vm-nsg` forms the driver originally hardcoded. **A delete aimed at a name that does
not exist reports success against nothing.**

**Closing residual, unfiltered — exactly the four expected resources, on both checks:**

```
clawfactoryvalc467              Microsoft.Storage/storageAccounts
bake-vmVNET                     Microsoft.Network/virtualNetworks
clawfactory-win11-baseline      Microsoft.Compute/images
clawfactory-win11-baseline-v2   Microsoft.Compute/images
```

`"It said deleted" is not "it is gone"` — re-checked after 25 seconds. **No propagation race this
time**, unlike the two prior cycles; recorded as the distinction the preamble requires.

**No RDP rule was ever created.** **No licence slot to release** — no install reached activation.
**No credential** was generated, printed, requested or stored.

---

## 8. What is owed next

1. **`OM-1`, the `:8787` dashboard** — still not taken. Three cycles now. `M-8` in the register.
2. **`M-7`, the logon-flash observation** — deferred three cycles. It is now *harder*, because the
   runs no longer produce an interactive logon by accident; it must be deliberately scheduled.
3. **`PR.C8`, reboot-and-resume on a first-run machine** — untouched by this job.
4. ~~The password decision~~ — **TAKEN 2026-09-01**, §6.1. The governing text is updated in the
   same commit. **What it opens is now the item:** persistent auto-logon, which makes the WSL
   runner unattended and Studio-panel screenshots possible (§6.4). That is the largest remaining
   reduction available and it is a separate job.
5. **The `fetch` step of `cfv-harness-proof.ps1` asks for more than 4096 bytes** and correctly
   reports `OutputTruncated`. It should be split into bounded pieces. Recorded rather than fixed,
   because it failed loudly and that is the designed behaviour.
6. **`Publish-CfvFile` and `Measure-CfvOutputLimit` are only self-tested**, not exercised against
   the real storage account this run — no blob upload was needed once the payload was base64'd
   into the dispatch. Owed on the next cycle that uploads anything.

---

## 9. Git

```
$ git status --short          # at session start
(clean)
```

Explicit per-file staging throughout. No `git add -A`. No `git worktree add`. **No tags.** Ten
commits, one per logical change. Both the working tree and the index are LF, verified by a byte
count with both canary halves rather than by `git status`.

**`git status` lied, in the direction nobody guards against.** After normalising the evidence
files it reported 13 as modified while `git diff` and `git diff --cached` were both **zero
bytes**. Byte-for-byte comparison of the committed blob against the worktree file said
**IDENTICAL** (208 bytes each), with a control proving `cmp` discriminates. It was a stale stat
cache, cleared by `git update-index --really-refresh`. The recorded lesson in this project is that
`git status` is blind to CRLF divergence; this is the same instrument failing the other way, and
the fix is the same — **compare bytes, not status.**
