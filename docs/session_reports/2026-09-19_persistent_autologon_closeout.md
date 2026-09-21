# Persistent auto-logon for the validation runner — close-out

**Date:** 2026-09-19. **Repo root:** `C:\Users\bmcki\ClawFactory-Secure-Setup` (confirmed with
`git rev-parse --show-toplevel`). **Branch:** `main`. **Precedent this closes out:** card #259
(`2026-09-01_unattended_harness_closeout.md`). **Box:** `cfv-193`, `Standard_D2s_v4`, image
`clawfactory-win11-baseline-v2`, `clawfactory-validation`, `--nsg-rule NONE`, **no RDP rule at any
point.**

**No product code touched.** `setup.ps1`, `resources/`, the `.iss` and everything bundled are
unmodified. No tag, release, signing or ledger row.

## Headline

**Persistent auto-logon works and is proven to matter. OM-1 was NOT taken** — the build machine's
antivirus blocked the screenshot driver, and it was not worked around. `cfv-193` is **deallocated,
not deleted**, waiting on a decision (§5).

## 1. Task 0 — the tree check

- The 13 `validation/diag/cfv-192-harnessproof-*` files: `git ls-files --eol` shows **`i/lf w/lf`
  for all 13** (the two `-text` files are unrelated and unmodified). `git diff` and
  `git diff --cached` on the directory are **0 bytes**; all 33 tracked files are byte-identical to
  the index by `cmp`, with a control that `cmp` discriminates.
- **So the job prompt's premise was half wrong: it is NOT a CRLF artifact.** It is the stale stat
  cache already diagnosed in the 2026-09-01 close-out §9. No content diff of any kind, so per 0.1
  nothing stopped. Left alone, nothing committed. By the time of the final `git status` the 13 no
  longer appeared as modified — the cache had refreshed itself.
- `CC_CENSUS_OpenClaw2Delta_v1.md` remains untracked and unrelated (an OpenClaw 2.0 census prompt;
  no reference to this job). Untouched.
- Card #259's mechanisms both still hold, **read from the files, not the close-out**:
  `validation/cfv-arm-persistence.ps1` registers `CFV-Runner-System` (SYSTEM / ServiceAccount /
  AtStartup) and `CFV-Runner-User` (clawadmin / Interactive / AtLogOn); the password rule is in
  `docs/VALIDATION_PREAMBLE.md` ("the admin password is the session's").
- **One premise in the prompt did not match the tree:** it says to reuse "the session-generated
  password the provisioning command already creates". **No provisioning script existed** — `cfv-192`
  was created by an inline command and the value discarded. Reusing "the same password" therefore
  required *writing* the provisioning path (`validation/cfv-provision.ps1`), with generation and
  both consumers in one process. There is exactly one generation path; none was duplicated.

## 2. Task 1 — the implementation, and the security scoping (1.2, 1.3)

`cfv-provision.ps1` generates a 24-char alphanumeric password (regenerated until it has all three
classes), uses it for `az vm create --admin-password`, hands the same value to
`cfv-arm-autologon.ps1` as a run-command parameter, then discards it. Never printed, never written
to a file; a scan of all 37 evidence files for `Pw=` / `password=` found only a **count** line.

On the box (`AL_*`, from `arm-autologon.txt`):

```
AL_CRED_VALID_FOR_ACCOUNT=True        <- ValidateCredentials: the registry value IS the account's
AL_CTL_WRONG_VALUE_REJECTED=True      <- control: a wrong value is rejected
AL_AUTOADMINLOGON=1   AL_DEFAULTUSERNAME=clawadmin   AL_DEFAULTPASSWORD_LEN=24
AL_DEFAULTPASSWORD_EQUALS_INPUT=True  AL_AUTOLOGONCOUNT_ABSENT=True
AL_CTL_NEVER_WRITTEN_IS_ABSENT=True   <- control for the read-back
AL_EXT_SETTINGS_COPIES_OF_PASSWORD=0  (23 files scanned under C:\Packages\Plugins)
AL_RESULT=PASS
```

**What it means, plainly.** The password sits in `HKLM\...\Winlogon\DefaultPassword` in
plaintext-recoverable form **for as long as the VM exists** — readable by any local administrator
or SYSTEM process, and present in any snapshot or image taken from it. It is also on a `cmd.exe`
command line on the *build machine* for the seconds each `az` call runs (visible to other local
processes; same exposure class, on a machine that already holds the Azure login).

**Scope confirmation (1.2).** It cannot reach a customer machine:
1. The provisioning script is not shared with any customer-facing path — it is new, and
   `cfv-provision.ps1` **enforces** `-Rg clawfactory-validation` and `-Vm ^cfv-\d+$` by throwing
   before any credential exists. (A script-level guard, not a structural one: it protects against
   misuse, not against someone editing the file.)
2. `validation\` appears in no `[Files]` entry of the `.iss`; `setup.ps1`, `resources\` and the
   `.iss` name none of the new files — the same confinement checks card #259 recorded still hold
   (grep/`[Files]` review, not re-derived from prose).
3. Delivery route is `az vm run-command` against `clawfactory-validation` only.
4. **Never capture an image from a validation VM** — recorded in the script headers.

**Lifecycle (1.3).** No validation VM persists across cycles by design: teardown deletes VM, NIC,
public IP, NSG and disk. At session start the resource group held **zero VMs**. **One exception
exists right now and it is mine: `cfv-193` still exists (deallocated), holding the DefaultPassword
on its disk, because OM-1 is undecided (§5).** Exposure window: from 2026-09-19 22:56 UTC until
the box is deleted. It has no inbound path.

## 3. Task 2.1 — two-reboot proof (through the runner's own path)

Every WSL job below was **dropped as a file and executed by `CFV-Runner-User` in session 1**. No
`wsl.exe` was typed by this session, no RDP rule existed, no person logged in.

| | Boot (UTC) | Session at boot | WSL runner heartbeat | WSL job |
|---|---|---|---|---|
| Reboot 1 | 23:07:22 | `clawadmin console 1 Active`, logon 23:07 | 1s old, newer than boot | `w1`: `cfv-193\clawadmin`, session 1, `wsl --status` **exit 0**, no-such-distro control **exit -1** → PASS |
| *v1.4.5 installed through the same runner* | | | | digest matched, `INSTALLER_DONE=success`, 1002 s |
| Reboot 2 | 23:33:17 | `clawadmin console 1 Active`, logon 23:33 | 1s old, newer than boot | `w2`: same, plus real distro exec: `alive=True pid1=systemd`, exit-33 control **33** → PASS |

`AutoAdminLogon=1`, `DefaultPassword` length 24, `AutoLogonCount` absent, read back after each
reboot. The "newer than the boot" comparison is what excludes a leftover heartbeat file.

## 4. Task 2.2 — disable / re-enable (a fix that cannot be shown to matter is not proven)

| State | Reboot (UTC) | Session | `CFV-Runner-User` | WSL job | SYSTEM-queue control |
|---|---|---|---|---|---|
| **Auto-logon OFF** (`AutoAdminLogon=0`, password left in place) | 23:41:39 | **none** — `No User exists for *` | `Ready` (not running) | dropped as `wnoal`; **`RunnerDead`, heartbeat 370 s stale — reported by name, not skipped, not passed** | ran: `nt authority\system`, `JobDone` |
| **Re-enabled** (`AutoAdminLogon=1`) | 23:52:20 | `clawadmin console 1 Active` | `Running`, heartbeat 3 s | **`wnoal` — the same job that sat unserviced — ran** (`W_NOW` 23:57:42, boot 23:52:20) → PASS; fresh job `w3` → PASS | |

So: auto-logon is what makes the WSL queue serviceable; the SYSTEM runner keeps working
independently in the same state (neither masks the other). Re-enabling needed **no password** — the
session no longer holds it; `AutoAdminLogon` alone was toggled.

**Honest wrinkle:** the driver names the unserviced case **`RunnerDead`**, not `RunnerAbsent`,
because a heartbeat file from the previous boot exists and goes stale. Both are named,
non-verdict conditions and the reading is correct in substance, but "no session exists" is the
truer cause and the driver cannot say so. Candidate card C2.

## 5. Task 2.3 — OM-1: **BLOCKED, not taken**

- Preconditions in place: product installed (`INSTALLER_DONE=success`; distro up with systemd as PID 1). The gateway `/status` positive control was NOT taken — it is part of the blocked driver. The one-time suspension
  of hazard rule #5 **recorded and committed before the attempt** (`87d3512`,
  `2026-09-19_persistent_autologon_runplan.md`), last in run order, box due for teardown.
- The `.iss` `[Icons]` entry is unchanged (`cmd.exe /c start http://127.0.0.1:8787`); the
  *installed* `.lnk` shape check never ran.
- **The driver never ran.** Windows' antivirus (AMSI) blocked `validation/cfv-om1.ps1` on the build
  machine: *"This script contains malicious content and has been blocked by your antivirus
  software"* (`ScriptContainedMaliciousContent`). Its content is a screen-capture + base64 return
  path. **I did not reword, split, obfuscate or route it through the VM to get past that** — that is
  evading a security control I was not cleared to bypass, and a decision for the operator.
- **`cfv-om1.ps1` is left untracked and NOT committed or pushed** — a public repo should not
  receive a file the machine's own AV calls malicious without that being a deliberate choice.
- **OM-1 therefore stands OPEN** in `docs/VALIDATION_PREAMBLE.md`; this cycle has not closed it.
  There is no screenshot and nothing to report about what the dashboard shows.

**What I need from you (one decision):** how OM-1's capture should be authorised. Options, my
recommendation first: (a) add a Defender exclusion for `validation\cfv-om1.ps1` on the build
machine, then I resume on the existing box (saves ~1 h: the install is already done); (b) drop the
programmatic capture and take OM-1 by eye in the batched end-of-run card, which is where the
2026-09-01 close-out placed panel-reading; (c) abandon: I delete `cfv-193` now.

## 6. End-of-session gate

**Task accounting**

| Task | Status | Evidence |
|---|---|---|
| 0.1 tree check | DONE | §1; `--eol` output, `cmp` 33/33, 0-byte diffs |
| 0.2 census file | DONE | untracked, untouched |
| 0.3 #259 mechanisms | DONE | read from files; one premise corrected (no provisioning script existed) |
| 1.1 auto-logon, one password, no `AutoLogonCount` | DONE | `AL_*` block |
| 1.2 security statement + scoping | DONE | §2 |
| 1.3 lifecycle | DONE, with one live exception named | §2 |
| 2.1 two reboots + WSL job each | DONE | §3, evidence dir |
| 2.2 disable / re-enable | DONE | §4 |
| **2.3 OM-1** | **BLOCKED** — AV block on the driver; decision needed | §5; card below |
| 3.1 Dispatch card | DONE | **card #333**, created via `POST /api/agent/update`; references #259 as the precedent |
| 3.2 commit + push, no tag | DONE for everything committable | git log |
| 3.3 this document | DONE | |

**Resource ledger.** Start: RG held only `clawfactoryvalc467`, `bake-vmVNET`, and the two images
(no VMs). Now additionally: **`cfv-193` (VM, OS disk, NIC, public IP, NSG) — deallocated, not
deleted, deliberately.** Compute stopped; disk ~ cents/day. About 2.5 h of `Standard_D2s_v4`
≈ **$0.50**. No RDP rule, no licence slot. **Teardown of `cfv-193` is owed** — one command:
`cfv-autologon-proof.ps1 -Vm cfv-193 -Step teardown` (enumerates names, NIC first, prints the
unfiltered residual).

**Delta security sweep (this session's diff).**
- Password on a `cmd.exe` command line on the build machine for seconds (§2). Accepted, stated.
- Password on the VM's disk for the box's life; **deallocation does not remove it** (the reason
  the open box is flagged, not hidden).
- Reply scrubbed of the value before disk, and the scratch `azerr` files deleted in `finally`.
  `AL_EXT_SETTINGS_COPIES_OF_PASSWORD=0` measured. The scan covers `C:\Packages\Plugins` only; it
  does not prove no other on-VM copy exists (e.g. run-command's other staging locations).
- `cfv-provision.ps1`'s scope guard is script-level. No customer path reaches it.
- No secret appears in any committed file or evidence (scanned).
- The AV block itself is a **security control behaving correctly**, respected.

**Delta bug review — candidate cards only, none actioned**
- **C1** — `Restart-CfvBox` `hb-after` read the task `CFV-Runner`, which stopped existing in #259
  (fixed in passing to `CFV-Runner-System`; the reported state was cosmetic).
- **C2** — stale WSL heartbeat from a prior boot reads `RunnerDead`, not `RunnerAbsent`, when no
  session exists. `Get-CfvJobStatus` could compare heartbeat to `LastBootUpTime` / `query user`.
- **C3** — `query.exe user` with no session leaks a PowerShell ErrorRecord into `S_QUSER` (noise, not wrong).
- **C4** — `az vm restart` wall time was 10 and 26 minutes on two reboots; unexplained, and it
  dominates a cycle's clock. Worth a look before the next multi-reboot run.
- **C5** — the `.lnk` shape check is the only guard on "OM-1's shortcut changed shape"; it lives in
  the blocked driver. Whatever unblocks OM-1 should keep it.
- **C6** — `cfv-arm-persistence.ps1` without `-AutoLogonExpected` still FAILs a correctly armed
  box; intended (asserts the #259 state), but a header line saying so would prevent a wrong re-run.

**Not done / not claimed.** No panel screenshots (declined 2026-09-01, unchanged). OM-1 not taken.
Only one box was used, so "unattended across reboots" is proven on **one** fleet member over four
reboots, not across a full cycle.

---

## 7. ADDENDUM 2026-09-20 — OM-1 second attempt: STILL NOT TAKEN

**Operator decision:** option (a), "add a Defender exclusion for `validation\` on `cfv-193`, take
the OM-1 screenshot, note it was measured under exclusion consistent with OM-B1, then deallocate."

**Two corrections to the premise, both surfaced to the operator before acting.** The first block
was on the *build machine*, not on `cfv-193`, so a VM-side exclusion could not unblock the local
driver. The operator then chose to ship the capture code to the VM **as data** (read as a plain
file, never parsed by the build machine's AV).

**What was done**
- Local driver split: `cfv-om1.ps1` no longer contains any capture logic; the on-VM code sits in
  `validation/om1-payload/` and is read as data. The local block did **not** recur.
- **Exclusion added on `cfv-193`** (`Add-MpPreference -ExclusionPath 'C:\cfv'`), read back with a
  control: `EXC_AFTER` = `C:\cfv` + the three fleet exclusions OM-B1 already records
  (`C:\Program Files\ClawFactory`, `C:\ProgramData\ClawFactory`,
  `C:\Users\Public\Desktop\ClawFactory.lnk`); an unrelated path read `False`; real-time
  protection was **left on**. Any OM-1 reading would therefore have been **under exclusion,
  consistent with OM-B1** — it would not have observed Defender's behaviour on the product.
- **Third unattended proof, incidental:** after `az vm deallocate` + `az vm start` the box
  auto-logged-in by itself (`clawadmin console 1 Active`, logon 01:07) and the runner serviced jobs.
- **`shape` step PASSED** — the installed shortcut is unchanged from the `.iss`:
  `C:\Windows\System32\cmd.exe /c start http://127.0.0.1:8787`, working dir
  `C:\Program Files\ClawFactory`, comment "Open ClawFactory dashboard in browser (gateway must be
  running)". Card C5's "has the shortcut changed shape" question is answered: **no.**

**What blocked it.** The `pre` job's drop dispatch was rejected **on the VM**:
`This script contains malicious content and has been blocked by your antivirus software`
(`ScriptContainedMaliciousContent`, from the run-command extension's `script88.ps1`). **A path
exclusion does not cover AMSI's script-content scanning**, so the `C:\cfv` exclusion was
irrelevant to it. Two independent Defender instances (build machine, then VM) now reject the same
screen-capture payload. Going further means disabling real-time protection or AMSI on the VM, or
obfuscating the payload — **each is beyond the exclusion the operator authorised**, and disabling
Defender would also void the "consistent with OM-B1" framing. I stopped rather than escalate.

**My own defect, found and fixed in the driver:** `Invoke-WslJob` ignored the result of the job
drop, so a dropped-on-the-floor job was polled for a full 12 minutes and reported `Timeout`
instead of the real condition. The drop is now checked and reported by name (candidate card C7,
the same "unchecked call" class as the 4.4 success-line census).

**Not taken:** the pre/post `/status` controls, the click, the screenshot. **OM-1 remains OPEN.**
`cfv-193` is **deallocated again, not deleted** (it still holds the DefaultPassword on disk).

**Not committed, deliberately:** `validation/cfv-om1.ps1` and `validation/om1-payload/` — the
payload is the content two AV engines flag, and the driver is useless without it.

**Decision needed (one):** (1) take OM-1 by eye in the batched end-of-run card — my
recommendation now, since neither route to a programmatic capture survives AV without disabling
it; (2) authorise disabling Defender real-time/AMSI on `cfv-193` only, for this one capture,
recorded as a departure from OM-B1's framing; (3) delete `cfv-193` and leave OM-1 open.
