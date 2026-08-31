# v1.4.5 validation — close-out

**Date:** 2026-08-31. **Repo root:** `C:\Users\bmcki\ClawFactory-Secure-Setup` (confirmed by
`git rev-parse --show-toplevel`). **Branch:** `main`. **Commit under test:** `1c97b47`
(session started at `ddc9919`, tree clean).

**Artifact under test:** `Output\ClawFactory-Secure-Setup.exe`, unsigned,
`sha256 8a035fadad64aa7c21868e2756d7140ad84c3e8443cbbc4f7faf6f7c1e7f696d`, 440,597,932 bytes.
Verified on the build machine before upload and again on **each box after download**; every
phase carries the digest as a declared precondition and refuses to proceed on mismatch.

**Nothing was signed, tagged, released, or written to `released-versions.tsv`. No shipped file
was modified.** The only repository change in this session is this document.

---

## 1. Verdict

**FIT TO SIGN, WITH TWO NAMED RESIDUALS.** Neither residual is a code blocker; one is a
documentation defect and is the more serious of the two.

**The build is materially better than v1.4.4 on the exact machine that broke.** On a stock
Windows 11 24H2 box in the reproduced external-failure state, v1.4.5 stops in **91 seconds**
with a named, actionable message that leads with the correct advice. v1.4.4 produced
`Failed to pre-create clawuser stub (exit=-1)` and the first external user spent
**41 minutes** reaching it. That improvement is measured, not inferred, and it survives
adversarial scoring: the phase carried two positive controls and five preconditions, all of
which fired or were met.

**Residual 1 — D1 is inert, and this is a documentation defect before it is a code one.**
`Test-WslRebootPending` does not fire in the state it was written for. `docs/V1_5_BACKLOG.md`
and `docs/session_reports/2026-08-30_v145_install_path_fixes_closeout.md` both describe D1 as
fixing the pending-reboot case. It does not. In a product whose own preamble says the comments
are the audit trail, shipping a documented fix that never executes is worse than the 1250 ms it
costs on every install. **Fix the documentation before signing; fix the code in v1.5.**

**Residual 2 — the installer logs a fatal error immediately before its own reboot.**
Pre-existing, not a v1.4.5 regression, and reached rarely (see §4.2). Low severity, named here
so it is not rediscovered as new.

**The whole of the user-visible fix is delivered by D2, D4 and D5, none of which depend on D1.**
That is the single most important sentence in this document for the signing decision.

---

## 2. Scoring — every assertion, verbatim evidence

`§8.2` of the build close-out lists **nine** assertions, not twelve. Twelve is reached by adding
the three controls `PR.CTL0/CTL1/CTL2`, which live in `validation/interim-v145-pendingreboot.ps1`
rather than in `§8.2`. Recorded here as nine assertions + three controls.

### 2.1 The nine assertions

| Row | Verdict | Evidence |
|---|---|---|
| **`PR.C6`** | **FAIL** | Post-`wsl --update`, pre-restart: `VirtualMachinePlatform='Enabled'`, `Microsoft-Windows-Subsystem-Linux='Disabled'`, `HypervisorPlatform='Disabled'`. Product gate returns **`False`**. `EnablePending` never appears. Corroboration keys at that moment: CBS `RebootPending=True`, `PendingFileRenameOperations=True` |
| **`PR.C7`** | **PASS** | `Failed to pre-create clawuser stub` hits = **0**. Named failure present ×3. Install stopped at 91 s |
| **`PR.C8`** | **VOID** | Reboot-and-resume path not reached on either box by any valid route. Named reason in §4.2 |
| **`PR.C6b`** | **INFO** | Box E **1250 ms** (cold, elevated, interactive). Box F **< 1 s** — all five gate log lines stamped `12:32:39` |
| **`PR.C9`** | **PASS** | `verified-import` hits = 1: `WSL2 import from bundle succeeded (verified: distro present and responding)`. Installer exit 0, 969 s, full install |
| **`PR.C10`** | **PASS** | `wsl-state.txt` = `'false'`; log carries `Recorded distroExistedPreInstall=False to wsl-state.txt` |
| **`PR.C11`** | **PASS** | `No rollback action is defined for 'Preflight' - nothing was undone for that step.` ×1; `Installation log: C:\ProgramData\ClawFactory\install.log` ×1; spurious `Undoing:` hits = **0** |
| **`PR.C12`** | **PASS** | Byte scan, both boxes, **0 NULs**. Planted-NUL canary control fired in the same run on both |
| **`PR.C13`** | **PASS** | `wsl --list --verbose` → no distro at all, version-1 present = `False`. **No `bcdedit` substitution needed** — see §3.3 |

### 2.2 The three controls, plus those added this run

| Control | Fired | Evidence |
|---|---|---|
| `PR.CTL0` | **YES** | `VirtualMachinePlatform = Disabled` on a stock box. First time on this fleet since 2026-05-06 |
| `PR.CTL1` | **YES** | `wsl --update` exit 0 moved VMP `Disabled → Enabled` and printed the external machine's exact sentence |
| `PR.CTL2` | **YES** | Restart landed: CBS `RebootPending` `True → False`, `LastBootUpTime = 12:51:19` |
| `PR.CTLF` / `PR.CTLE2` / `PR.CTLR` | **YES** | Search instruments proven against planted strings and absent-string negatives before any absence was asserted |
| `PR.CTLN` | **YES** | Byte scan proven against a file deliberately built to contain a NUL |

### 2.3 Bonus row

| Row | Verdict | Evidence |
|---|---|---|
| `PR.D6` | **PASS** | Shipped `setup.ps1:820` carries `Installation failed. Run automatic rollback? It can only remove the Windows firewall rule and unregister the Ubuntu distro. (y/N)`, with an absent-canary control reading 0. **Initially mis-scored FAIL — my instrument, see §5.4** |

---

## 3. The central finding, stated at full strength

### 3.1 D1 gates on a value that carries no information

The external-failure state was reproduced by the **product's own route** on a stock box that had
never had WSL. `wsl --update`, elevated and interactive, exit 0, printing verbatim:

```
Installing Windows optional component: VirtualMachinePlatform | The requested operation is
successful. Changes will not be effective until the system is rebooted.
```

Both controls fired, so the state is genuine. In it:

```
Get-WindowsOptionalFeature VirtualMachinePlatform  = Enabled      <- NOT EnablePending
Test-WslRebootPending                              = False        <- the gate does not fire
CBS RebootPending                                  = True         <- D1 reads this, refuses to gate on it
PendingFileRenameOperations                        = True         <- same
wsl --status                                       = exit 0       -> $kernelOk = True
```

And the control half, same box, nothing else changed:

| Reading | Before restart | After restart |
|---|---|---|
| `VirtualMachinePlatform` | `Enabled` | **`Enabled`** |
| CBS `RebootPending` | `True` | `False` |
| `PendingFileRenameOperations` | `True` | `False` |

**The typed feature state is identical either side of the restart. The keys D1 declines to gate
on are the only readings that change.** D1's chosen signal cannot distinguish a machine that
needs a restart from one that does not; the discarded signals can.

### 3.2 Why it can never fire on this path, as a mechanism

`Step-EnsureWsl` calls `Update-WslEngine` — `wsl --update` — **before** reaching the D1 gate
([setup.ps1:1110](../../setup.ps1)). After that call `wsl --status` exits 0. So by the time
`Test-WslRebootPending` is consulted, the installer's own preceding step has already made the
machine look healthy to the only other test on the path. Even if the typed state were correct,
the branch D1 guards is one that `Update-WslEngine` has made unreachable.

**How the fix came to be built on an unproduced value.** §4.2 of the build close-out records
that D1 was proven by injecting a synthetic `@{VirtualMachinePlatform='EnablePending'}` hashtable
through `Test-WslRebootPending`'s `$States` parameter. That proves the comparison works. It does
not prove Windows ever emits that value. This is the preamble's own clause —
*a probe is calibrated against a rigged input; a run is not* — applied to the fix's proof harness.
The implementer's reasoning for rejecting a prose match was sound (an English-sentence gate breaks
on every other Windows language); the substituted proxy was simply never measured against reality.

**A working signal exists and was measured in this run:** CBS `RebootPending`, which read `True`
before and `False` after. D1 rejected it as "routinely present on a healthy machine after any
Windows Update" — a real concern, but one that argues for combining it with a WSL-specific
condition, not for discarding it in favour of a value that is never set. `wsl --status`'s
*output* also says in plain text `WSL2 is unable to start since virtualization is not enabled on
this machine` while exiting 0 — the product reads the exit code and discards the output, which is
the same mistake D1 was written to correct, committed one call later. **Both are v1.5 work, not
this job's.**

### 3.3 D3's premise is stronger than the close-out claimed — the bit is inverted

Same CPU, same size, same region:

| | box E (stock, VMP `Disabled`, **cannot** run WSL2) | box F (baked, VMP `Enabled`, WSL 2.7.8, **can**) |
|---|---|---|
| `VirtualizationFirmwareEnabled` | **`True`** | **`False`** |
| `setup.ps1:1046` WARN would fire | No | **Yes** |

Once VMP is enabled the root partition no longer sees VT-x, so the bit reads `False` on a
healthy machine and `True` on a broken one. The close-out argued the bit *cannot distinguish*
disabled from unreported. On this fleet it is worse: **it points the wrong way.** D3's refusal to
gate on it is correct by a wider margin than was claimed, and D3 additionally chose the right half
of its message on box E — `VirtFirmwareSuspect` stayed false, so the text led with "restart"
rather than "check your BIOS", which is correct for a machine whose real fault is a pending restart.

### 3.4 `PR.C13` needed no substitution

TASK 0.4 predicted this row was not constructible on `Standard_D2s_v4` and proposed
`bcdedit /set hypervisorlaunchtype off` with a named caveat. **That was unnecessary.** Box E
reached genuine virtualization-unavailability by the product's own route — `wsl --status` reports
`WSL2 is unable to start since virtualization is not enabled on this machine` — which is the real
condition, not an approximation. Corroborated statically: zero `--set-version` / `--version 1`
call sites in any shipped file, and `Install-WslDistroWithFallback` returns only `'wsl2'` from two
sites. Scored PASS on the real fault.

---

## 4. What could not be measured, and what it would need

### 4.1 `PR.C8` — VOID, with a named reason

The reboot-and-resume subsystem was not exercised on either box by any valid route.

- **Box E:** the D1 gate does not fire, and `$kernelOk` is true after `Update-WslEngine`, so
  `Step-EnsureWsl` took the import path (`reboot branch taken = 0`, `bundled-import = 1`).
- **Box F:** the succeeding path completed; no reboot was needed.

**What it would need:** a machine on which `wsl --update` cannot install the WSL engine, so that
`wsl --status` still fails afterwards and `$kernelOk` is false. That is a real scenario — an
offline machine, a blocked Store/CDN route, a policy-restricted host — but it is not one an Azure
VM in this configuration can be put into. **Do not let this disappear into a pass.** It remains
open and is now a stronger claim than before: on a modern Windows 11 24H2 machine with a working
`wsl --update`, the reboot-and-resume path appears to be **unreachable by the normal first-run
flow entirely**.

### 4.2 The fall-through after `Restart-Computer -Force` — observed, characterised, not a blocker

Observed on the voided box F attempt (§5.2), which reached the reboot branch under SYSTEM:

```
[INFO]  Restart required: wsl --status still reports the kernel unavailable after wsl --install
[INFO]  Scheduled Task 'ClawFactory-Resume' registered
[INFO]  Resume flag written
[INFO]  Silent mode: skipping restart-required dialog; rebooting now.
[INFO]  Step 3: Writing initial /etc/wsl.conf ...
[ERROR] Install failed: Failed to write /etc/wsl.conf
[ERROR] Top-level handler caught: Failed to write /etc/wsl.conf
```

`Restart-Computer -Force` **initiates** a restart and returns; it does not halt the script.
`Step-EnsureWsl` ends with `Invoke-WslRebootAndResume` and the main body is a flat sequence
(`Step-EnsureWsl; Step-ConfigureWslConfig; Step-ConfigureWslConf; …`), so in the seconds before
Windows terminates the process the installer runs two further steps against a machine with no WSL
and writes a misleading fatal error immediately before what is meant to be a *pause*.

**Pre-existing, not a v1.4.5 regression** — the call predates this build. But **D1 adds a second
call site with the same shape** at `setup.ps1:1175`, and that one is mid-function, so a
fall-through there would also run the `$kernelOk` test and could register the resume task twice.
That second site is currently unreachable (§3.2), which is the only reason this is not worse.

**Severity: low, on the evidence.** The resume flag and scheduled task are both written *before*
the fall-through, so the restart-and-resume contract is not broken; the damage is a misleading log
entry on a path that §4.1 shows is rarely reached. **Recorded for v1.5, not a signing blocker.**

### 4.3 `OM-1` (the `:8787` dashboard) — NOT taken, entry stands

No suspension of hazard rule #5 was recorded in this run plan, so the measurement was not taken.
Per the preamble's own instruction, **the entry remains open** and the next cycle still owes it.

---

## 5. Instrument defects vs product defects — and the ratio

**Product findings: 2. Instrument defects: 4. Ratio 2:1 instrument-to-product.**

For five cycles this has run roughly **18:1**. It has changed, and I do not think that reflects
better instruments. It reflects a box that had never existed before: given somewhere new to fail,
the product failed there. Four of the six items below were found in the first ninety minutes on
the first stock image this project has ever validated against.

### 5.1 `?` is a legal PowerShell variable-name character — cost two dispatches, found twice

`"$n?$sas"` parses as `${n?}`, which is undefined and renders **empty**. The URL
`.../validation/e01.ps1?se=…` silently collapsed to `.../validation/se=…` — no filename, no query
string — producing an anonymous request and Azure's `PublicAccessNotPermitted` (HTTP 409).

I diagnosed the first occurrence wrongly as a freshly-minted-SAS validity window and re-minted the
token, which changed nothing. The real cause was found only by testing the interpolation locally.
I then **reintroduced the identical bug one line away from where I had fixed it**, in
`'/validation/$job?'`. Fix: brace it (`${n}`) or concatenate.

### 5.2 I drove installs through `az vm run-command`, which the runner's own header forbids

[interim-v120-runner.ps1](../../validation/interim-v120-runner.ps1) states: *"run-command is used
ONLY to drop job files and read status, never to touch WSL."* Under SYSTEM `wsl.exe` returns
`WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED`, so `wsl --status` exits −1, `$kernelOk` is false, and the
installer takes the **reboot branch on a box where WSL works perfectly well**. This voided one full
box F install (~16 minutes) and both its assertions. Corrected by adopting the documented
job-runner mechanism, which put every subsequent measurement in session 2 as `clawadmin`.

**This is the defect that would have produced a false verdict.** Had I scored that run at face
value, `PR.C9` and `PR.C10` would have been reported as v1.4.5 FAILs and the build refused.

### 5.3 A probe that scored FAIL where it should have declared a precondition

The first box F probe scored `PR.C9`/`PR.C10` FAIL when the install had never reached
`Install-WslDistroWithFallback`. A missing precondition is never a product verdict. Fixed by adding
`PR.PRE.F4` — *the install reached the succeeding path* — which gates both rows to VOID otherwise.

### 5.4 `PR.D6` searched the one place the string can never appear

`Confirm-Or-Default` writes the prompt to `install.log` **only** on the silent path
(`Write-Log INFO "Silent mode: auto-answering '$Prompt'…"`); interactively it calls
`Read-Host $Prompt`, which goes to the console. I forced the interactive path and then searched
`install.log`. Re-scored **PASS** against the shipped `setup.ps1:820` with an absent-canary control.

### 5.5 Two `az` traps re-confirmed from the ledger

`az vm get-instance-view --query "…[?starts_with(code,'PowerState')]…"` died with
`].code was unexpected at this time` — the `az.cmd`/`cmd.exe` re-parse trap. And
`az storage container generate-sas` takes `-n`, not `-c`; the wrong flag produced exit 2 and an
empty token, which the exit-code check and a local calibration caught **before** it reached a box.
Both are already in the ledger; both cost minutes rather than runs because the ledger existed.

---

## 6. Per-box ledger, per the baseline clause

| | **Box E — `cfv-186`** | **Box F — `cfv-187`** |
|---|---|---|
| Image | **stock** `MicrosoftWindowsDesktop:windows-11:win11-24h2-pro:26100.9168.260809` | `clawfactory-win11-baseline-v2` |
| Steps its image had already performed | **none** | VMP + WSL feature Enabled **and rebooted** (2026-05-06 bake); WSL engine 2.7.8 by MSI; AppX stripped |
| Rows it answered | `CTL0`, `CTL1`, `CTL2`, `C6`, `C6b`, `C7`, `C11`, `C12`, `C13`, `D6` | `C9`, `C10`, `C6b`, `C12` |
| Rows it **could not** answer | — | `C6`, `C7`, `C13`, all three controls — the state under test cannot exist on it |

### 6.1 Three open questions from `docs/reference/BASELINE_IMAGES.md` §3, now answered

That file records three things never read back from either image. All three were taken in one
dispatch before the installer was copied, exactly as it suggested.

1. **Defender exclusions survived sysprep.** All three present on `cfv-187`:
   `C:\Program Files\ClawFactory`, `C:\ProgramData\ClawFactory`,
   `C:\Users\Public\Desktop\ClawFactory.lnk`.
2. **`wuauserv` is `Running` / `Manual` on a provisioned box.** The bake disabled it;
   generalize/specialize **restored it**. §1 item 3's claim that the update service cannot set
   `RebootRequired` on these boxes is **false on a provisioned box** and should be corrected.
3. **VMP reads `Enabled` on a box provisioned from `-v2` today** — confirmed directly, not
   inferred from a June 2026 measurement.

**And one the file did not ask.** Box E has **no** Defender exclusions. The baked fleet has been
installing into three excluded paths for four months; a real user's machine has none. One more
thing four boxes could not see.

---

## 7. Resource ledger

**Starting state**, unfiltered, before anything was provisioned:

```
clawfactoryvalc467              Microsoft.Storage/storageAccounts
bake-vmVNET                     Microsoft.Network/virtualNetworks
clawfactory-win11-baseline      Microsoft.Compute/images
clawfactory-win11-baseline-v2   Microsoft.Compute/images
```

Already at expected residual — **no prior FAIL VMs to delete**. `az vm list`, `az disk list`,
`az network nic/public-ip/nsg list` all returned empty at exit 0.

**Provisioned and torn down mid-run:** `cfv-184`, `cfv-185` — both polluted by §5.2 and deleted
rather than reused, because *a second run over a box that has already been run is not the same
measurement as the first*. VM, NIC, public IP, NSG and OS disk swept explicitly, NIC first.
Residual re-checked with an unfiltered list and confirmed back to the four resources above.

**Current state: both live boxes DEALLOCATED**, verified `VM deallocated`.

```
cfv-186   VM deallocated      (box E, stock)
cfv-187   VM deallocated      (box F, baked)
```

Still allocated and awaiting your teardown decision: `cfv-186`, `cfv-187`, their OS disks,
`cfv-186-nic` / `cfv-187-nic`, `cfv-186-pip` / `cfv-187-pip` (static), `cfv-shared-nsg`.
Teardown command is in the handoff card. Evidence transcripts are in the validation blob container
and locally in the session scratchpad; nothing needed from the boxes remains.

**RDP** was scoped to `67.164.251.99/32` on a single shared NSG for the whole run. Never
`0.0.0.0/0`; both VMs were created with `--nsg-rule NONE` and the scoped rule attached before any
address was reachable.

**No licence slot to release** — no install reached activation.

---

## 8. Where this prompt and the build close-out were wrong

Reported per the preamble's *if this prompt is wrong, say so* clause. All were reported **before
provisioning** except §8.4.

**8.1 `PR.C7` tested the fix's intention, not its effect.** As written it asserts the install
*"stops inside `Step-EnsureWsl` with a named restart instruction"*. The code at that site does not
stop — it calls `Invoke-WslRebootAndResume`, which **reboots**. The named-stop `throw` is on the
`$Resume` branch only, reachable only *after* a restart. Re-derived and scored against what the
code does.

**8.2 `PR.C11` was unreachable as specified.** `Confirm-Or-Default` returns the default whenever
`Test-IsSilent`, and `Test-IsSilent` is true under any `az vm run-command` dispatch regardless of
flags. The rollback prompt's default is `'n'`, so no silent install and no run-command dispatch can
ever answer `Y`. Taken by invoking `setup.ps1` directly, non-silent, in the interactive session
with `y` piped to stdin.

**8.3 `PR.C13` was called not-constructible; it was constructible for free.** See §3.4.

**8.4 The count is nine assertions, not twelve.** §8.2 lists `C6, C7, C8, C6b, C9, C10, C11, C12,
C13`. Twelve is reached only by adding the three controls from the probe file.

**8.5 `validation/interim-v145-runner.ps1` is a v1.4.4 reproduction driver, not a v1.4.5 runner.**
Its `$SHIPPED_SHA` is the v1.4.4 digest, it uploads the artifact as `v144-shipped.exe`, its
`install` step runs the v1.4.4 installer, and it hardcodes `-Vm cfv-183`. The build close-out says
only *"point the digest gate at whichever you use"*, which understates it.

**8.6 `validation/interim-v145-pendingreboot.ps1` records FAIL when the defect is PRESENT.** Its
`PR.C1`/`PR.C3` are polarised for v1.4.4 diagnosis. Run against v1.4.5 and scored naively they
would read FAIL and look like v1.4.5 defects while measuring only OS behaviour. Fresh
v1.4.5-polarised probes were written instead, still driven through
`validation/interim-v120-phaselib.ps1` so the reporting discipline is enforced mechanically.

**8.7 The exemption premise-check passed.** All three conditions the operator conditioned the
box-D exemption on were verified against the tree: `'wsl1'` unproducible (zero `--set-version` /
`--version 1` sites; `Install-WslDistroWithFallback` returns only `'wsl2'`); `$variant` assigned at
3 sites, logged once each, read nowhere; checkpoint sequence **40 call sites, 31 distinct names**,
matching the build close-out's AST count exactly.

---

## 9. The signing job's brief

**Artifact.** The v1.4.5 source at `1c97b47`. The unsigned build validated here is
`8a035fadad64aa7c21868e2756d7140ad84c3e8443cbbc4f7faf6f7c1e7f696d`, 440,597,932 bytes.

**Do the documentation fix first.** §1 Residual 1. `docs/V1_5_BACKLOG.md` and
`docs/session_reports/2026-08-30_v145_install_path_fixes_closeout.md` both claim D1 fixes the
pending-reboot case. Correct them to state that D1 is inert on Windows 11 24H2 and that D2/D4/D5
carry the fix. **This changes shipped bytes** — `setup.ps1`'s D1 comment block also asserts the
gate works — so it must land *before* the build, and the resulting digest will differ from the one
above. That is expected and correct; do not force the old digest through.

**`scripts\build_release.ps1` is the only sanctioned route.** It is the only path that runs the
gates, stamps the build, signs it, and appends the `released-versions.tsv` row. `ISCC.exe` plus
`sign_installer.ps1` bypasses every gate — documented in six places. The artifact validated here
carries **no build stamp**, because this cycle's build deliberately truncated before the stamp, so
`sign_installer.ps1` will refuse it. That is the correct outcome and a required step for the next job.

**The ledger records the UNSIGNED digest.** Signing embeds a countersigned timestamp, so the signed
digest differs on every run over identical input. Never delete a row to let a changed rebuild
through — bump instead.

**Name the release asset exactly `ClawFactory-Secure-Setup.exe`.** The site at `clawfactory.app`
is built from `BuzzardsBay/clawfactory-site` and its three download buttons hit the asset URL
directly; any other name 404s silently.

**Tag after validation, not before.** Per v1.4.4 practice the tag goes at the tip of `main`, not
at the build commit.

---

## 10. What is owed next

1. **The D1 documentation correction** — §9, before signing. Doc + `setup.ps1` comment.
2. **Sign and release** — §9.
3. **`PR.C8`** — §4.1, still open, with a named construction requirement.
4. **`OM-1`, the `:8787` dashboard** — §4.3, still open, untouched by this cycle.
5. **D1 rewrite for v1.5** — §3.2 names two working signals that were measured in this run:
   CBS `RebootPending` combined with a WSL-specific condition, and `wsl --status`'s *output*
   rather than its exit code.
6. **The `Restart-Computer` fall-through** — §4.2, v1.5.
7. **`docs/reference/BASELINE_IMAGES.md` §1 item 3 is wrong on a provisioned box** — §6.1,
   a doc commit.
8. **`docs/V1_5_BACKLOG.md`'s WSL1 census** still lacks the two `README.md` rows the build job
   found — carried forward from that close-out's §10 item 4.
9. **The five systemd units enabled with `|| true`** — untouched, still a separate job.

---

## 11. Git

```
$ git status --short          # at session start
(clean)
$ git status --short          # before this commit
(clean)
```

Explicit per-file staging. No `git add -A`. No `git worktree add`. **No tags. Nothing pushed as an
artifact. No shipped file modified.** The single file added by this session is this close-out.
