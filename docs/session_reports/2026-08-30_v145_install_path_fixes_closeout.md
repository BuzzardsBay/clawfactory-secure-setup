# v1.4.5 install-path fixes — close-out

**Date:** 2026-08-30. **Repo root:** `C:\Users\bmcki\ClawFactory-Secure-Setup` (confirmed by
`git rev-parse --show-toplevel`). **Branch:** `main`. **Starting commit:** `1e16f6b`.

**What this job produced:** ten commits, an unsigned v1.4.5 installer, and a committed
regression harness. **Nothing was signed, tagged, released, pushed as an artifact, or written
to `released-versions.tsv`.** No VM was provisioned; no validation run was taken; no `.sh`
file was touched.

> **CORRECTED 2026-08-31: §3.8's claim about D1 is superseded by measurement.** This document
> describes D1 as fixing the pending-reboot case. It does not fix it, and it does not fire.
> The correction is in place at §3.8 and the finding is
> `docs/session_reports/2026-08-30_v145_validation_closeout.md` §1 Residual 1, §3.1 and §3.2.
> Nothing else in this document is affected; D2, D4, D5, D6, D7, D8 and 850 all stand as
> written, and they are what delivers the user-visible fix. The original text is kept
> throughout rather than rewritten.

---

## 0. PROMPT 15 preamble, as applied

The block below is `docs/VALIDATION_PREAMBLE.md`'s fenced paste block, with two clause groups
deleted and the deletions stated, per that file's own rule.

**Deleted, with the reason.**

- **`ENVIRONMENT, NOT NEGOTIABLE`** — every clause in it (VM size, baseline image, one
  `az vm run-command` at a time, SYSTEM context, `/var/tmp`, `/mnt/c`, RDP scoping,
  `-OutDir`, `az` exit codes, deallocate at handoff). **This job provisions no Azure VM and
  runs no install.** The clauses cannot be applied to a code-and-build job, and pretending to
  apply them would be a false record.
- **`HUMAN HANDOFF CARDS`** — the Card 1 / Card 2 content (VM name, public IP, `/32`, admin
  password, interactive-session command). Same reason: there is no VM to hand off. The
  *principle* — every point where the job needs a human, it stops and prints a self-contained
  card — is kept and discharged in §7.
- **`RESOURCE LEDGER`** — deletion of prior FAIL VMs, disk/NIC/pip/NSG sweeps, residual proof.
  Nothing was provisioned, so there is nothing to sweep. **Verified rather than assumed: this
  session issued no `az` command of any kind.**

**Kept in full and applied:** close-out-is-a-gate; the four pre-flight checks; "if this prompt
is wrong, say so before executing it"; measurement discipline; shell and exit codes; "an audit
regex is itself a probe"; "a baseline image is a set of install steps already completed";
credential hygiene; version and build; git; the `python`-is-blocked note.

**The four clauses the job brief names as governing this job directly, and where each is
discharged:**

| Clause | Where |
|---|---|
| Comprehension gate (pre-flight 1) | §1 |
| Dependency census (pre-flight 2), WHO and WHEN | §1.4 |
| Calibrate before measuring | §4 — the harness carries its controls, and §4.6 records an instrument that was wrong and how it was caught |
| A baseline image is a set of install steps already completed | §8, the validation brief: box E is a **stock** image |

---

## 1. TASK 0 — comprehension and premise check

### 1.1 What each defect is, in my own words

Read from the tree, not from the backlog. Every one survived; the three qualifications are in
§2.

**D1 — nothing in the installer knows what a pending reboot is.** `Update-WslEngine` runs
`wsl --update`, captures its combined output into `$out`, writes it to the log, and then the
only thing it does with the result is warn if the exit code was non-zero. The output is never
read by anything. So when Windows says "I enabled VirtualMachinePlatform, and it will not take
effect until you restart", the installer records that sentence and carries on as though the
feature were live. There is no condition anywhere in `setup.ps1` that asks whether a restart is
pending. It is a defect because the very next thing the file does is decide, from
`wsl --status`'s exit code, that the kernel is available — and that exit code is 0 in exactly
the state the sentence describes.

**D2 — a distro is declared to exist because a command returned zero.**
`Install-WslDistroWithFallback` had three `return` sites, and each one concluded from an exit
code that a bootable Linux environment now exists. It does not follow. `wsl --install` can exit
0 having enqueued work for after a restart. It is a defect because the caller immediately runs
a command *inside* that environment, so the first symptom is an error about something four
layers away from the cause.

**D3 — one firmware bit produces a warning that informs nothing, and cannot mean what a reader
takes it to mean.** `Win32_Processor.VirtualizationFirmwareEnabled` is OEM-populated and reads
`$null` on some hardware; `-not $null` is `$true`, so the WARN fires identically for "disabled"
and "not reported". Nothing consumes the finding. It is a defect of *waste* rather than of
danger: the installer knows something possibly relevant, says it to a log, and no later failure
can use it.

**D4 — the diagnostic is applied to the wrong variable.** The virtualization-signal test read
`$output`, which is built from the `wsl --install` call. The `wsl --import` call's streams live
in `$rImp` and were only ever logged. So an error reported by the import — which is the primary
path, the one that runs on every machine with the bundled rootfs — could not reach the test.

**D5 — the check that would have caught D2 already existed and already ran, two lines too
late.** All three sites called `New-ClawUserAndSetDefault` first and `Test-WslFunctional` after.
The first thing that touches the new environment was therefore a `useradd`, so the user's error
message was about a Linux user account.

**D6 — a prompt offers an action there is no mechanism behind.** `setup.ps1` saves 31 distinct
checkpoint names. `Invoke-Rollback` has 2 cases. The other 29 fell to an empty `default {}`, and
the loop logged `Undoing: <step>` before the switch, so the log asserted work that did not
happen.

**D7 — the one failure path that never says where the log is.** `Invoke-WithRollback` printed
`Rollback skipped. Log: $LogFile` only in the *declined* branch. Accept the rollback and you are
never told the path.

**D8 — the nulls are stripped on one logging path and not the other.** `Update-WslEngine`
strips `wsl.exe`'s UTF-16LE nulls; `Invoke-WslBash`'s `[wsl:<user> out]` / `[wsl:<user> err]`
path does not. The consequence is worse than ugly: nulls make a plain text search over
`install.log` find nothing at all.

**Census site 850 — the failure default is the destructive one.** A failed `wsl --list --quiet`
left `$distroExisted` at `$false` and wrote `false` to `wsl-state.txt`, which is the record
meaning "this distro was not here before us". **Qualified in §2.2.**

**v1.4.5-A — the WSL1 fallback.** Not "ships insecure". It cannot complete: the gateway is
started only through `systemctl --user` and there is no `nohup`/`setsid` path anywhere in
`setup.ps1` or `resources/gateway-wait.sh`, so `Step-PreinstallGatewayRuntime` throws after 120
seconds — about twenty minutes into an install, about a health probe, on a machine whose actual
problem is virtualization.

### 1.2 `setup.ps1` was pristine at start

```
$ git log -1 --format='%H %h %ad %s' -- setup.ps1
25945d523350eb1f7262586432ec11ea7e8fbfd2 25945d5 Thu Aug 27 13:18:10 2026 -0600 release: bump to v1.4.4
$ git hash-object setup.ps1      -> e09dd639c066d83b69f2eb4d8356ce635651c4ad
$ git rev-parse HEAD:setup.ps1   -> e09dd639c066d83b69f2eb4d8356ce635651c4ad
$ git status --short setup.ps1   -> (no output)
$ wc -l setup.ps1                -> 3869
```

Worktree hash equals the committed blob, and the last commit touching it is `25945d5`, as the
brief asserted. `git status --short` at session start was clean for the whole tree.

### 1.3 Where each fix lands, and the two overlaps

Line numbers are **as they stood at `25945d5`**, so they can be checked against the backlog.

| Item | File and line at 25945d5 | Function |
|---|---|---|
| D8 | `setup.ps1:761-772` | `Invoke-WslBash` |
| D6 | `setup.ps1:595-624` | `Invoke-Rollback` |
| D7 | `setup.ps1:636-645` | `Invoke-WithRollback` |
| 850 | `setup.ps1:846-863` | `Step-EnsureWsl` |
| D3 | `setup.ps1:814-821` | `Step-Preflight` |
| v1.4.5-A | `setup.ps1:432-438`, `506-530`, `831`, `879` | `Install-WslDistroWithFallback`, `Step-EnsureWsl` comments |
| D4 | `setup.ps1:483-492`, `506` | `Install-WslDistroWithFallback` |
| D2 | `setup.ps1:488`, `502`, (`526`) | `Install-WslDistroWithFallback` |
| D5 | `setup.ps1:884-893`, `928-932`, `973-977` | `Step-EnsureWsl` |
| D1 | new helpers + `setup.ps1:898-902`, `1043-1049`, refactor of `982-1019` | `Step-EnsureWsl` |
| A (shipped docs) | `README.md:45`, `README.md:119`, `resources/uninstall.ps1:420` | — |

**Two pairs touch the same lines, so order mattered and was chosen deliberately.**

1. **v1.4.5-A and D4 both rewrite `506`.** A deletes the branch that line guards; D4 changes
   what that line tests. They were applied as **one commit** (`17e0d56`), because applying them
   in either order separately would have produced an intermediate state that is wrong in a way
   no test would catch — a WSL1 downgrade newly reachable from an import-side virtualization
   error.
2. **D2 and D5 both sit on the boundary between `Install-WslDistroWithFallback` returning and
   `New-ClawUserAndSetDefault` running.** D2 also deletes site `526` — which A had already
   removed, so D2 landed on two sites, not three. Applied as one commit (`25a2f59`) with D2
   first, so the redundancy of D5 is the *stated* redundancy rather than an accident.

**D3 had to precede A, D2 and D5**, because those three consume `$script:VirtFirmwareSuspect`
through `Get-VirtualizationHelpText`. It is commit `a14b61f` and changes no control flow at all.

### 1.4 Dependency census (pre-flight 2), for the one thing removed

**WHO uses the WSL1 fallback?** Re-derived tree-wide rather than copied
(`grep -rni "wsl1\|set-default-version"`, all source extensions, excluding `docs/`):

| Site | Disposition |
|---|---|
| `setup.ps1:432,436,438` comments | rewritten with the branch |
| `setup.ps1:506-530` the branch | deleted |
| `setup.ps1:510,516,527,529,530` | deleted with it |
| `setup.ps1:831,879` comments | reworded |
| `resources/launcher.ps1:196` comment | **kept, code and comment.** The HTTP probe is correct independently and "systemd-disabled" stays reachable |
| `resources/uninstall.ps1:420` comment | reworded |
| `validation/uninstall-teardown-extract.sh:4` | reworded (separate commit, not shipped) |
| **`README.md:45`** | **rewritten — NOT in the backlog's census** |
| **`README.md:119`** | **rewritten — NOT in the backlog's census** |
| `Output/v1.4.4-release-body.md:138` | left. A historical record of what v1.4.4 said |

**WHEN is it needed?** Never. `$variant` is assigned at three sites, logged once at each, and
read nowhere; nothing in the tree branches on the distro version; there is no
`wsl --list --verbose` parse and no `--set-version` read-back. The branch has never executed on
any validation box — `docs/session_reports/` contains no run in which the function returned
`'wsl1'`.

### 1.5 Which fixes change shipped bytes

**Shipped** (`setup.ps1`, `resources/uninstall.ps1` and `README.md` are all `Source:` entries in
the `.iss` `[Files]` section, and `README.md` also carries its own Start Menu shortcut):
D1, D2, D3, D4, D5, D6, D7, D8, 850, v1.4.5-A, and the version bump. All eleven require the
build.

**Not shipped**, and therefore in its own commit (`f3cb7f6`), per Task 0.4:
`validation/uninstall-teardown-extract.sh`. The harness `validation/verify-v145-fixes.ps1`
(`7910c83`) is likewise not shipped and is its own commit.

---

## 2. Where the brief and the backlog are wrong, or one step ahead of the code

Reported before executing, per the preamble. Nothing here blocked the work; all of it changed
what was written.

### 2.1 The backlog's WSL1 census claims completeness and is not complete

`docs/V1_5_BACKLOG.md` § v1.4.5-A introduces its table as *"The complete tree-wide census of
every WSL1 reference"*. It omits **`README.md:45`** ("falls back to WSL1 automatically if
unavailable") and **`README.md:119`** (an entire bullet titled "WSL1 fallback on hardware
without nested virtualization", including the claim that the egress firewall uses
iptables-legacy). `README.md` is bundled at `.iss:46` and has a Start Menu entry, so shipping
v1.4.5 against that census would have shipped a document promising a behaviour the code no
longer has. Both are rewritten in `17e0d56`.

### 2.2 Site 850's stated consequence is one step ahead of the code

The backlog says a `false` verdict is what *"the uninstaller reads as 'this distro did not exist
before we installed, so it is ours to remove'"*. Read against the tree, `resources/uninstall.ps1`
does this and only this:

```powershell
$DistroPreExisted = ((Get-Content -LiteralPath $sf -Raw).Trim() -eq 'true')
Write-Log INFO "Cached distroExistedPreInstall = $DistroPreExisted"
```

`$DistroPreExisted` is **never referenced again**. `grep -n "PreExisted" resources/uninstall.ps1`
returns exactly those two lines plus the declaration. The `RemoveAll` decision comes from
`-KeepLinuxEnvironment`, `-RemoveAll`, `-Silent` or the dialog. `setup.ps1`'s own comment at 843
already says *"The checkbox in the uninstall UI remains the authority"*.

**So the defect is real and its consequence is not.** It writes a false record; nothing acts on
the record today. The fix is unchanged — it costs four lines and the record should be true — but
the severity is "a false record a future consumer would misread", not data loss. Recorded in the
commit message as well as here.

### 2.3 Three deliberate deviations from the fix design in the close-outs

**(a) The registry keys are corroboration, never the condition.** The D1 design
(`2026-08-30_first_external_install_failure_closeout.md` §4.1) proposes
`…\Component Based Servicing\RebootPending` and `…\WindowsUpdate\Auto Update\RebootRequired` as
a "secondary, belt-and-braces" part of the check. Implemented as specified, that is a false
gate: **either key is routinely present on a perfectly healthy machine after any Windows
Update**, and the branch behind it *restarts the user's computer*. They are read and logged;
they cannot fire the gate. This is the same argument that keeps D3 from becoming a gate, applied
consistently.

**(b) The gate is evaluated after `Test-WslFunctional`, not before the `$Resume` branch.** The
design says "immediately after the `Update-WslEngine` call at line 870, before the `$Resume`
branch at 872". At that point the code does not yet know whether WSL already works. A machine
with a pending feature state *and* a working WSL2 would have been restarted for nothing. The
check now sits after each point where `Test-WslFunctional` has already returned false — which is
still before the `$kernelOk` test at the old line 923, the branch the external machine took.

**(c) No `rebootCount`.** The design adds a counter to the resume flag as a loop guard. It is
not needed: the `$Resume` branch **stops** with a named manual-restart instruction rather than
rebooting again, and that branch is reachable only from a restart this installer scheduled. The
flag *is* the count. Fewer moving parts, and the guard is structural rather than arithmetic.

**(d) `Wait-WslFunctional` retries; the design specified a single call.** D2's design says
"three `wsl.exe` process launches per success path". A one-shot probe against a distro
registered a second earlier is a coin flip, and this project already paid for that lesson once
(`project_v141_built_unvalidated`: one-shot reachability probes). Three attempts, three seconds
apart. On a healthy machine the first attempt passes and the cost is the design's three
launches; the worst case is stated in §5.1 as a trade.

### 2.4 The prompt's own constraint made `build_release.ps1` unrunnable end to end

`scripts/build_release.ps1` has **no `-SkipSign` switch**: gates → compile → stamp → **sign** →
append a ledger row, in one straight line. The brief forbids signing and forbids a ledger row.
So the gates and the compile were run as two separate acts (§6), which is the route the script's
own header calls the unsigned dev build. This is stated rather than worked around silently,
because it means **the artifact in `Output\` carries no build stamp and `sign_installer.ps1`
will refuse it** — which is the correct outcome for this job and a required step for the next.

---

## 3. TASK 1 — the fixes, one commit each

Ten commits, `1e16f6b..HEAD`, explicit per-file staging, no `git add -A`, `git status --short`
before each. No tags.

```
a8467cc fix(v1.4.5-C D8): strip wsl.exe's UTF-16 nulls on Invoke-WslBash's log path too
0086407 fix(v1.4.5-C D6+D7): stop claiming rollback undid a step it has no case for, and always print the log path
a6a76a3 fix(v1.4.5-B, census site 850): never record a distro-pre-existence verdict we do not have
a14b61f fix(v1.4.5 D3): record the virtualization readings, do not gate on them
17e0d56 fix(v1.4.5-A + D4): remove the WSL1 fallback; stop with a named message and read BOTH wsl outputs
f3cb7f6 chore(v1.4.5-A): reword the WSL1 comment in the extracted teardown copy
25a2f59 fix(v1.4.5-B D2+D5): verify a distro exists and answers before treating an exit code as proof
c2c30cb fix(v1.4.5-B D1): stop on a pending reboot, read from the typed feature state
7910c83 validation: verify-v145-fixes.ps1 -- every fix run against an input the OLD code accepts
1c97b47 release: bump to v1.4.5
```

### 3.1 D8 — the nulls

**Before** (`Invoke-WslBash`, 761-772): `foreach ($line in ($stdout -split "`r?`n"))` with no
strip on either stream.
**After:** two lines added ahead of both loops, `$stdout = $stdout -replace "`0", ''` and the
same for `$stderr`, with a comment citing the strip `Update-WslEngine` already performs.

**Evidence tie.** `install.log`, the `[wsl:root out]` line:
`T h e r e   i s   n o   d i s t r i b u t i o n   w i t h   t h e   s u p p l i e d   n a m e .`
— the most direct statement of the fault in the whole file, and the nulls additionally made
`grep` classify the file as binary and suppress matches, which it did to a reader of those
artefacts (groundwork close-out §9.2 D).

### 3.2 D6 — the rollback that undid nothing

**Before:** `Write-Log INFO "Undoing: $s"` *above* the `switch`, and `default { }`.
**After:** `Undoing:` moved inside the two real cases; `default { Write-Log INFO "No rollback
action is defined for '$s' - nothing was undone for that step." }`; one closing line saying that
`C:\Program Files\ClawFactory` is the uninstaller's to remove; and the prompt itself now reads
*"It can only remove the Windows firewall rule and unregister the Ubuntu distro."*

**Evidence tie.** `install.log` 11:52:37 —
`[ERROR] Running rollback for completed steps...` / `[INFO] Undoing: Preflight` — with
`checkpoint.json` reading `{ "completedSteps": [ "Preflight" ] }` and no `Preflight` case in the
switch.

### 3.3 D7 — the log path

**Before:** `else { Write-Log INFO "Rollback skipped. Log: $LogFile" }` — the *declined* branch
only.
**After:** `else { Write-Log INFO 'Rollback skipped.' }` and, outside the `if` entirely,
`Write-Log ERROR "Installation log: $LogFile"` on every failure path.

**Evidence tie.** The external user accepted the rollback, so no line naming the log was ever
printed; combined with `Failed to pre-create clawuser stub (exit=-1)`, which names neither cause
nor file. Measured cost: 41 minutes 18 seconds, 11:11:19 → 11:52:37.

### 3.4 Site 850 — the verdict not taken

**Before:** `if ($rList.ExitCode -eq 0 -and $rList.StdOut) { … }` gating the computation, then
an unconditional `Set-Content … wsl-state.txt` of `$distroExisted`, which is `$false` on any
failure.
**After:** the write moved inside `if ($rList.ExitCode -eq 0)`; the failure arm logs a WARN
naming the exit code and stating that nothing was recorded. Any existing file is left untouched,
deliberately, so a previously recorded `true` cannot be downgraded to absent by a later timeout.

**Evidence tie.** Census §3.2 row `850`, plus `install.log` 11:09:53 → 11:10:53: this call took
**sixty seconds** and succeeded, so `wsl-state.txt` read `false` truthfully this time. The shape
that produces the false record is one timeout away.

### 3.5 D3 — the readings

**Before:**

```powershell
$cpu = Get-CimInstance Win32_Processor
if (-not $cpu.VirtualizationFirmwareEnabled) {
    Write-Log WARN 'Virtualization may be disabled in BIOS. WSL2 may fail to start.'
}
```

**After:** four readings logged through `Format-Reading`, which renders raw value **and** type
so `False` is distinguishable from `<null:not-reported>`; `$script:VirtFirmwareSuspect` set; the
WARN rewritten to say it is a warning and not a check that failed; and
`Get-VirtualizationHelpText` added, which every WSL failure message now ends with.

**Evidence tie, and it is a measurement rather than an argument.** The WARN fired at 11:09:53 on
a machine whose Task Manager reads **Enabled**. A hard gate on that bit would have refused to
install on a working computer. **The BIOS preflight therefore does not become a hard gate**, as
the brief requires and as the evidence independently settles.

### 3.6 v1.4.5-A + D4 — the fallback, and the variable it read

**Before** (506-530): `$hyperVMissing = ($output -match 'HCS_E_HYPERV_NOT_INSTALLED' -or
$output -match '0x80370102')`; throw if not; otherwise three fallback `wsl` calls, a WARN
reading *"Some features (systemd, networking) behave differently on WSL1"*, and `return 'wsl1'`.

**After:** no fallback. `$importOutput` is captured next to `$output` and initialised at the top
of the function (StrictMode 3.0 makes an unassigned read terminating on the no-bundle path);
`$allOutput` is both; the signal set gains `HCS_E_SERVICE_NOT_AVAILABLE` and `0x80370114`; and
one of two named throws fires — the virtualization one via `Get-VirtualizationHelpText`, or a
generic one that names the two log prefixes to look at.

**Evidence tie.** `install.log`:
`[wsl --import v2] Error code: Wsl/Service/RegisterDistro/CreateVm/HCS/HCS_E_SERVICE_NOT_AVAILABLE`
— on the **import** stream, which the old test could not see. And, for the removal itself, the
absence of evidence stated as such: no close-out in this repository records
`Install-WslDistroWithFallback` returning `'wsl1'` on any box.

### 3.7 D2 + D5 — the load-bearing fix

**Before:**

```powershell
if ($rInst.ExitCode -eq 0) {
    Write-Log INFO 'WSL2 install succeeded.'
    return 'wsl2'
}
```

**After:**

```powershell
if ($rInst.ExitCode -eq 0) {
    if (-not (Wait-WslFunctional)) {
        throw (Get-WslNotCreatedMessage -Command 'wsl --install')
    }
    Write-Log INFO 'WSL2 install succeeded (verified: distro present and responding).'
    return 'wsl2'
}
```

Same shape at the import site. `Wait-WslFunctional` is `Test-WslFunctional` — `wsl --status`
exit 0, `wsl --list --quiet` contains `Ubuntu`, and `wsl -d Ubuntu -u root -- true` exit 0 —
retried three times, three seconds apart. **The third call is the one that proves a Linux
userspace exists, which is the claim being made.**

D5: `New-ClawUserAndSetDefault` now runs *after* the readiness check at all three
`Step-EnsureWsl` sites, and the message those sites throw is no longer
`'WSL could not be configured on this machine. Please contact support at hello@avitalresearch.com'`.

**Evidence tie, and this is the fix the evidence caught in the act.** Two adjacent lines of
`install.log`:

```
[wsl install out] The requested operation is successful. Changes will not be effective until the system is rebooted.
[2026-08-30 11:11:18] [INFO] WSL2 install succeeded.
```

The sentence that refutes the claim is the line immediately above the claim. It was written to
disk by the very code that made the claim, and read by nothing.

### 3.8 D1 — the pending-reboot gate

**Before:** no such condition exists anywhere in `setup.ps1`.
**After:** `Get-WslFeatureStates` reads the typed `FeatureState` for `VirtualMachinePlatform`,
`Microsoft-Windows-Subsystem-Linux` and `HypervisorPlatform`; `Test-WslRebootPending` decides on
`EnablePending`/`DisablePending` only, logs the two registry keys as corroboration, and takes
`-States` for injection. Non-`$Resume` and pending → `Invoke-WslRebootAndResume`, which is the
existing reboot path lifted out of `Step-EnsureWsl` unchanged. `$Resume` and still pending →
stop with a named manual-restart instruction.

**The gate is not the English sentence**, per Task 1.1. The sentence stays in the log and in a
comment as corroboration; a check on it would silently stop working on any non-English Windows,
which is the same defect class in a new place. Proved rather than asserted — see row `D1.4`.

**Evidence tie.** `wsl --update`'s captured output, verbatim: *"Installing Windows optional
component: VirtualMachinePlatform | The requested operation is successful. Changes will not be
effective until the system is rebooted."* — captured at 256, normalised at 263, logged at 264,
referenced nowhere. And `PR.C1`, answered from the field rather than from a rig: the log line
`WSL2 kernel loaded but Ubuntu missing` sits inside `if ($kernelOk)`, so **`wsl --status` exits
0 while `VirtualMachinePlatform` is `EnablePending`**.

> **CORRECTION, 2026-08-31, by measurement. Everything above in §3.8 is superseded and is
> kept rather than deleted.**
>
> **Claimed above:** that `Test-WslRebootPending` gates the pending-reboot case, and — in the
> Evidence tie — that on the external machine `wsl --status` exits 0 **while
> `VirtualMachinePlatform` is `EnablePending`**.
>
> **Measured** on stock `MicrosoftWindowsDesktop:windows-11:win11-24h2-pro` (box `cfv-186`,
> 2026-08-30), in the external-failure state reproduced by the product's own route —
> `wsl --update`, elevated and interactive, exit 0, printing the sentence quoted above — with
> `PR.CTL0` (`VirtualMachinePlatform = Disabled` at start), `PR.CTL1` (the enable happened) and
> `PR.CTL2` (the restart landed) all firing in the same run:
>
> | Reading | Before restart | After restart |
> |---|---|---|
> | `VirtualMachinePlatform` | `Enabled` | `Enabled` |
> | `EnablePending`, on any of the three features | never observed | never observed |
> | `Test-WslRebootPending` | `False` | `False` |
> | CBS `RebootPending` | `True` | `False` |
> | `PendingFileRenameOperations` | `True` | `False` |
>
> **True now.** The Evidence tie's `EnablePending` sentence was an **inference** from the
> external machine's `install.log` — the log proves `wsl --status` exited 0 in a state needing
> a restart, and the rest was supplied by the design. The feature state was never read on that
> machine. On a box put into the same state deliberately, the typed state reads `Enabled` on
> both sides of the restart. So `Test-WslRebootPending` returns `False` in exactly the state it
> was written to catch: **the gate does not fire, and D1 does not fix the pending-reboot case.**
>
> Independently of the signal, the branch is unreachable on the first-run path: `Step-EnsureWsl`
> calls `Update-WslEngine` before the gate, and after that call `wsl --status` exits 0, so the
> installer's own preceding step has already made the machine look healthy to the only other
> test on the path.
>
> **What §4.2 below got right, and what it did not.** §4.2 correctly records that the *read* was
> not measured and defers it to `PR.C6`. `PR.C6` was then taken, and it **FAILED**. The gap was
> not that the assertion was undeferred; it was that the rows above it (`D1.1`/`D1.2`/`D1.3`)
> proved the *comparison* against a synthetic `EnablePending` injected through the function's own
> `$States` parameter, and a passing comparison against a rigged input reads exactly like a
> working gate. *A probe is calibrated against a rigged input; a run is not.* Recorded as
> `docs/FAILURE_CATALOGUE.md` entry 15.1.
>
> **The remainder of §3.8 stands.** The refusal to gate on the English sentence is still correct
> for the reason given, and `D1.4` still proves the gate is not that sentence. What is wrong is
> only the claim that the substituted signal works.
>
> **v1.4.5 ships with D1 inert, by the operator's decision**, because D2/D4/D5 deliver the whole
> user-visible fix without it. The rewrite is `docs/V1_5_BACKLOG.md` item 8, which carries the
> two signals this run measured working: CBS `RebootPending`, and `wsl --status`'s *output*.

---

## 4. TASK 2 — every fix against an input the old code accepts

`validation/verify-v145-fixes.ps1`, committed at `7910c83`. It reads the v1.4.4 `setup.ps1` out
of git at `25945d5` and the worktree copy, re-declares each version's top-level functions from
its own AST so the shipped text runs rather than a paraphrase, stubs `wsl.exe`, and feeds both
the same constructed input.

```
powershell -NoProfile -ExecutionPolicy Bypass -File validation\verify-v145-fixes.ps1
PASS 13   FAIL 0   VOID 0     (exit 0)
```

| Row | Input | Old code | New code |
|---|---|---|---|
| `CAL.0` | healthy: exit 0 **and** the distro answers | returned `'wsl2'` | returned `'wsl2'` |
| `D2.1` | `wsl --install` exit 0, prints the reboot sentence, no distro | returned `'wsl2'` | **threw** "wsl --install reported success (exit 0), but no working 'Ubuntu' environment exists…" |
| `D2.2` | `wsl --import` exit 0, no distro | returned `'wsl2'` | **threw** the same, naming `wsl --import` |
| `A.1` | `HCS_E_HYPERV_NOT_INSTALLED`, fallback calls all succeed | returned `'wsl1'` | **threw** "ClawFactory needs WSL 2, and Windows reported that the Virtual Machine Platform is not available…" |
| `D4.1` | virtualization error on the **import** stream only | threw "…no fallback signal detected" | **threw** the named virtualization stop |
| `D1.1` | `VirtualMachinePlatform = EnablePending` | no such condition exists in v1.4.4 | `Test-WslRebootPending = True` |
| `D1.2` | all three features `Enabled` | n/a | `False` |
| `D1.3` | all three `Unknown` (unreadable) | n/a | `False` — fails **open** |
| `D1.4` | is the gate the English sentence? | no condition at all | planted canary found `True`; string literal in `setup.ps1` `False` |
| `850.1` | `wsl --list --quiet` exits 1 | wrote `'false'` | wrote nothing |
| `D6.1` | rollback with `completedSteps = ['Preflight']` | `Undoing: Preflight` ×1, undid nothing | `Undoing:` ×0, `No rollback action is defined` ×1 |
| `D7.1` | failure, rollback **accepted** | log path printed 0 times | log path printed 1 time |
| `D8.1` | a log line carrying UTF-16 nulls | strips nulls: `False`; search found **0** matches | strips nulls: `True`; search found **1** match |

### 4.1 Task 2.2 specifically — exit zero, no distro

Row `D2.1` is that exact shape and nothing else: the stub returns exit 0 from `wsl --install`
with the reboot sentence on stdout, `wsl --status` exit 0, `wsl --list --quiet` exit 0 listing
`docker-desktop` and not `Ubuntu`, and `wsl -d Ubuntu -u root -- true` exit `-1` — the value
from the real log. The old code returns `'wsl2'`; the new code throws. Row `D2.2` repeats it at
the import site, using the real `resources/ubuntu-rootfs.tar.gz` so the rootfs pin genuinely
passes rather than being stubbed past.

### 4.2 Task 2.3 specifically — the pending-reboot read

**Split, and the split is the honest answer.** The *decision* is measured here: `D1.1`/`D1.2`/
`D1.3` drive `Test-WslRebootPending` with constructed states and get `True`/`False`/`False`.
**The *read* is not.** `Get-WindowsOptionalFeature -Online` requires elevation and this session's
shell is not elevated:

```
Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
  -> ERR: The requested operation requires elevation.       (126 ms to fail)
  IsAdmin = False
```

So the assertion that the read returns `EnablePending` in a constructed pending state is
**deferred to the validation job**, and written out in §8.2 as `PR.C6`.

### 4.3 Calibration

Per "calibrate before measuring", each direction is anchored:

- `CAL.0` is the positive control. A new check that simply always refused would fail it, so no
  row below it can score a pass by refusing everything.
- `D1.2` and `D1.3` are the negative controls for the reboot gate — a gate that always fired
  would restart every machine.
- `D8.1`'s search over the **null-bearing** file must find **nothing**. That is the
  measurement, not an assertion about it; the stripped file finding exactly one match is its
  pair.
- `D1.4` does **not** grep, and says why in the file: the sentence is present in `setup.ps1`
  as a comment, where it belongs, so a raw text search answers `True` and is wrong. The
  instrument reads string literals out of the AST and is calibrated against a planted source
  that contains one — canary found `True`, real file `False`.

### 4.4 What could NOT be tested here, and what each needs

| # | Not tested | Why | What it needs |
|---|---|---|---|
| U1 | `Get-WindowsOptionalFeature -Online` returning `EnablePending` | needs elevation; measured failing at 126 ms in this shell | the validation box, elevated. `PR.C6` in §8.2 |
| U2 | The install actually **stopping** on a pending reboot, restarting, and resuming | needs a machine in that state, which no baked image can be in | box E, stock image. `PR.C7`/`PR.C8` |
| U3 | The whole reboot-and-resume subsystem end to end | **it has never run to completion in any recorded validation of this product.** The one recorded execution, 2026-05-21, aborted | box E |
| U4 | The elapsed cost of `Get-WindowsOptionalFeature` ×3 under elevation | same as U1 | box E; §5.1 records the gap |
| U5 | `Wait-WslFunctional`'s worst case on a genuinely broken machine | the 60-second `wsl --list` is one field observation, not a distribution | box E, if it fails there |
| U6 | That WSL1 has no systemd | inherited premise, never measured on any box in this project, and shared with the claim it corrects | now moot for the code — the branch is gone — but the *argument* still rests on it, and this is the second close-out to say so |
| U7 | The two rewritten `README.md` bullets as a customer sees them | Start Menu shortcut on the installed machine | any box, one look |

---

## 5. TASK 3 — regression surface

### 5.1 What each fix costs on a healthy install

Measured on this build machine, Windows 11 26200, with a running `Ubuntu` distro. Read-only
`wsl.exe` calls only; nothing was started that was not already running (`wsl --list --running`
confirmed `Ubuntu` was up before any timing was taken).

| Fix | Extra process launches | Extra in-process calls | Measured |
|---|---|---|---|
| D2 (`Wait-WslFunctional`, first attempt passes) | **+3 `wsl.exe`** | — | 1002 ms first run, then 116 / 112 ms. **Mean 410 ms, warm ~114 ms** |
| D1 (`Test-WslRebootPending`) | **0** | 3 × `Get-WindowsOptionalFeature`, 2 × `Test-Path` on HKLM | **NOT MEASURED** — needs elevation (U1/U4). Bound it in the validation run |
| D3 | 0 | +1 `Get-CimInstance Win32_ComputerSystem` | below timer resolution alongside the `Win32_Processor` query already there |
| D5 | 0 | 0 — a reordering | 0 |
| D6, D7, D8, 850 | 0 | 0 | 0 |

Individual read-only calls, for the record: `wsl --status` 33 ms, `wsl --list --quiet` 27 ms.

**The one number that is not free and is not measured is D1's**, and it is on the path *every*
install takes. `Get-WindowsOptionalFeature -Online` is a DISM-backed query and is not
instantaneous. It runs at most once per install. **Recorded as an open cost, not as zero.**

### 5.2 Checkpoint sequence and `$variant`

Enumerated by **AST**, not by regex — see §5.4 for why that distinction earned itself.

```
AST Save-Checkpoint CALL SITES   old = 40   new = 40
IDENTICAL (order + names)        True
DISTINCT NAMES                   old = 31   new = 31   identical = True
$variant assignment sites        old = 3    new = 3
```

**The checkpoint sequence is unchanged: 40 call sites, same names, same order, 31 distinct.**

**`$variant` needs a precise answer rather than a yes or no, and here it is in the terms the
brief asks for.**

- **Its value is unchanged.** On every path any validation box has ever taken, it is `'wsl2'`.
- **Its domain is not.** The return literals go from `{'wsl2', 'wsl2', 'wsl1'}` to
  `{'wsl2', 'wsl2'}`. **`'wsl1'` is no longer producible.**

**So: strictly read, one of the two things the prior exemption was conditioned on has changed —
the set of values `$variant` can take is smaller by one.** Stated in bold as the brief requires,
rather than smoothed over.

**My reading, offered as a recommendation and not as a decision taken:** the exemption from
re-running box D's structural table survives, because the removed value was never produced on
any box, `$variant` is never persisted or branched on, and the checkpoint sequence — the other
half of the condition — is byte-for-byte identical. **The call belongs to whoever authors the
validation job, and §8 assumes the exemption is NOT taken for the one row that could see it.**

### 5.3 The build-gate set

Run against the tree at `1c97b47`, by taking `scripts/build_release.ps1` and truncating it
immediately before the `Compiling installer with Inno Setup...` line — so every gate runs from
the real script text, and nothing after the compile (the stamp, the signature, the ledger
append) can run. The repo copy was not modified.

```
SOUL pin OK: e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
Bundle check OK: all 34 preflight resources are in [Files].
Interpolation gate OK: 10 shipped .ps1 files parse, and none interpolates a variable the file never defines.
  Worktree pin: resources/ubuntu-rootfs.tar.gz is not tracked by git ... its own pin gate covers it.
  Worktree pin: resources/ClawFactory-Studio-Setup-1.3.2.exe is not tracked by git ... its own pin gate covers it.
Worktree pin OK: all 54 tracked [Files] resources are byte-identical to their committed form.
Studio pin OK: ac5937516e7edbb5aac00433bfa6e5074449cbc28b132883099391639e1e7dca
Version OK: 1.4.5 (.iss and setup.ps1 agree)
Ledger OK: released-versions.tsv carries 12 prior artifact row(s).
Persona pin OK: 0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0
Workspace SOUL pin OK: 441b6279f6613c313e87e9e9e034f97a220540cddbf1cf738bb9a86c37a5a257 (6677 bytes composed)
Rootfs pin OK: 1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109
EXIT = 0
```

**The count I actually observed, reported as three different numbers because they are three
different things:**

| Measurement | Observed | Agrees with the staleness spec? |
|---|---|---|
| Named gates in the `gatesPassed` array literal | **9** | Yes — census row 1, value 9 |
| `^# --- Pre-build gate:` headers | **8** | Yes, **and only with Correction 1**: one header at `:527` covers two gates (`persona` and `workspace-soul`) |
| `OK` lines printed by a full gate run | **10** | The version gate prints twice — the literals-agree half and the ledger half |

The original spec's rule — count headers, cross-check against `gatesPassed`, *"Both, and they
must agree"* — **still fails today, for the reason its own Correction 1 gives.** Re-derived here
independently rather than believed: `grep -c '^# --- Pre-build gate:'` returns 8 and the array
has 9 entries.

**Two gates did not run**, because they cannot run before a compile exists and this job stops
before signing: the version gate's **enforcement half** (`build_release.ps1:658`, the compiled
digest against a prior row for the same version) and the **build stamp**
(`:636`, not a gate but the thing `sign_installer.ps1` demands). Both run in the signing job.
`README.md`'s "nine pre-build gates" is correct and needs no change.

### 5.4 An instrument that was wrong, caught in the same session

The first checkpoint census used a regex over the file text and reported **40 old / 41 new**,
i.e. a changed sequence. It was wrong: a comment I had written inside `Invoke-WslRebootAndResume`
contains the literal text `Save-Checkpoint 'EnsureWsl'`, and the regex counted it. Re-run by AST
over `CommandAst` nodes: 40 and 40, identical.

Recorded because it is the preamble's own rule biting in real time — *"where the question is
enumeration rather than detection, parse the AST instead of matching text"* — and because a
regex census that had reported 40/40 by luck would have been believed.

---

## 6. TASK 4 — the build

### 6.1 Version literals bumped

| Site | Before | After |
|---|---|---|
| `ClawFactory-Secure-Setup.iss:9` `#define MyAppVersion` | `"1.4.4"` | `"1.4.5"` |
| `setup.ps1:56` `$InstallerVersion` | `'1.4.4'` | `'1.4.5'` |
| `README.md:3` release badge (**twice on the one line**) | `v1.4.4` | `v1.4.5` |

`released-versions.tsv` **deliberately not touched** — its row is written by
`build_release.ps1` *after* signing, and an unsigned build must leave no row or it poisons the
gate for the real attempt.

Not bumped, each correct as it stands: `README.md:32` "Fixed in v1.4.4",
`resources/clawfactory-stop.ps1:15`, `scripts/build_release.ps1:136,690`, `SECURITY.md:22` and
the `SECURITY_FINDINGS.md` body — all historical statements about when something changed.
**One left open on purpose:** `SECURITY_FINDINGS.md:3` *"Applies to … v1.4.4"* is a currency
claim, not a history one. It is **not bundled**, so correcting it costs a commit and not a
build; it belongs to whoever re-derives that document against v1.4.5.

### 6.2 The artifact

```
path    : C:\Users\bmcki\ClawFactory-Secure-Setup\Output\ClawFactory-Secure-Setup.exe
bytes   : 440597932
sha256  : 8a035fadad64aa7c21868e2756d7140ad84c3e8443cbbc4f7faf6f7c1e7f696d
written : 2026-08-30 14:49:55
compile : ISCC.exe, successful in 62.640 sec, exit 0
stamp   : ABSENT  (Output\ClawFactory-Secure-Setup.exe.buildstamp does not exist)
signature status : NotSigned
```

For scale: the unsigned v1.4.4 was `440594967` bytes, so this is **+2965 bytes**.

**The previous contents of `Output\` were inspected before being overwritten**, and the signed
v1.4.4 asset — `6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1`, 440610608
bytes, byte-identical to the published GitHub release asset — was copied to
`Output\ClawFactory-Secure-Setup-1.4.4-signed.exe` first. It is intact.
`Output\ClawFactory-Secure-Setup.exe.PRIOR` (2026-07-24) was not touched.

**The absent build stamp is the correct state, not an omission.** `sign_installer.ps1` refuses
anything `build_release.ps1` did not stamp, so these bytes cannot be signed by the sanctioned
route — which is what "no signing in this job" has to mean structurally rather than by
intention. The signing job re-runs `build_release.ps1`, which re-runs every gate, recompiles,
stamps, signs and appends the ledger row.

---

## 7. Operator card — nothing to do yet, and here is what exists

**STOP. Not signed. Not tagged. Not released. No ledger row. Nothing pushed.**

**What exists on disk right now**

| Thing | Where |
|---|---|
| Unsigned v1.4.5 installer | `Output\ClawFactory-Secure-Setup.exe` — 440597932 bytes, sha256 `8a035fad…f696d` |
| The signed v1.4.4 you published, preserved | `Output\ClawFactory-Secure-Setup-1.4.4-signed.exe` — sha256 `6e655603…b4d1` |
| Ten commits on `main`, unpushed | `1e16f6b..1c97b47` |
| The proof harness | `validation\verify-v145-fixes.ps1` — 13 rows, PASS 13 |

**The next two jobs, in order. Do not reorder them.**

1. **VALIDATION.** Brief in §8. It needs a **stock** Windows 11 image, not
   `clawfactory-win11-baseline-v2` — the baked image cannot be in the state under test. It
   needs the unsigned installer above, or a signed one; the digest gate in
   `validation\interim-v145-runner.ps1` must be pointed at whichever you use.
2. **SIGNING AND RELEASE**, only after validation returns. Run
   `scripts\build_release.ps1` — not `ISCC.exe` — because that is the only route that stamps,
   signs and writes the `released-versions.tsv` row. **Expect a different digest from the one
   above only if an input changed; if nothing changed, Inno is deterministic and it will
   match.** Then: tag, release, and attach the asset as **exactly**
   `ClawFactory-Secure-Setup.exe` or the site's three download buttons 404.

**Nothing is needed from you to close this job.**

---

## 8. TASK 5.3 — the validation job's brief

### 8.1 Which boxes, which images

**Two boxes. Not four.** The changed surface is `Step-Preflight`, `Step-EnsureWsl` and
`Install-WslDistroWithFallback`, all of which complete before `Step-ConfigureWslConfig`.

| Box | Image | Why this image |
|---|---|---|
| **E — the one that has never existed** | **stock `MicrosoftWindowsDesktop:windows-11:win11-24h2-pro`** | **The baseline clause.** `clawfactory-win11-baseline-v2` was baked with the WSL engine already installed by MSI, and the bake for `clawfactory-win11-baseline` enabled `VirtualMachinePlatform` and rebooted before capture. **Neither image can ever be in the state under test.** For four months no box could be, and four boxes agreed with each other |
| **F — the no-regression box** | `clawfactory-win11-baseline-v2` | Proves the added verification does not break the path all four v1.4.4 boxes took. D2 inserts three `wsl.exe` calls into a *succeeding* install; that is the whole regression risk |

`PR.CTL0` from `validation/interim-v145-pendingreboot.ps1` applies to box E and is
load-bearing: **`VirtualMachinePlatform` must read `Disabled` at start.** If it does not, the
run is measuring a baked image again and every row on box E is VOID.

**Rows the baked box cannot answer:** every `PR.*` row below except `PR.C9` and `PR.C10`. Box E
answers them. Say so in the run plan, per the baseline clause.

### 8.2 The assertions

Deferred from Task 2.3 — these are the ones this job could not take, written out so the
validation job does not have to reconstruct them:

- **`PR.C6` (from U1).** On box E, elevated, before the install:
  `(Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State` must read
  **`EnablePending`** after `wsl --update` has enabled it and before any restart. Control: the
  same read must be **`Enabled`** after the restart with nothing else changed. *A fault
  injection that does not inject scores a false pass.*
- **`PR.C7` (from U2).** The install must **stop inside `Step-EnsureWsl` with a named restart
  instruction**, and the string `Failed to pre-create clawuser stub` must appear **nowhere** in
  `install.log`. This is the PASS criterion the regression test was written for, before the fix
  existed.
- **`PR.C8` (from U2/U3).** After the restart and no other change, the install must proceed
  **past** `Step-EnsureWsl`. **This exercises the reboot-and-resume subsystem, which has never
  run to completion in any recorded validation of this product**, so a failure here is a finding
  about that subsystem and not necessarily about D1.
- **`PR.C6b` (from U4).** Record the wall-clock of `Test-WslRebootPending` on both boxes. It is
  on the path every install takes and this job could not measure it.
- **`PR.C9`.** On box F: the install completes, and `install.log` contains
  `WSL2 import from bundle succeeded (verified: distro present and responding)`. The word
  **verified** is the assertion; its absence means the old code path ran.
- **`PR.C10`.** On box F: `Get-Content C:\ProgramData\ClawFactory\wsl-state.txt` still reads
  `false`, i.e. site 850's fix did not stop the *succeeding* path from recording.
- **`PR.C11`.** Box E or F, deliberate: make the install fail after `Preflight`, answer **`Y`**
  to the rollback prompt, and assert `install.log` contains **`No rollback action is defined`**
  and a line naming `install.log` itself. Both were absent from the external failure.
- **`PR.C12`.** Any box: `install.log` must contain **no NUL bytes**. Measure it as a byte scan
  (`Format-Hex`, or `Select-String` over the raw bytes), **not** by grepping for text — a grep
  over a null-bearing file is exactly the instrument that fails silently here.
- **`PR.C13`.** Box E, the whole point: with virtualization genuinely unavailable, the installer
  must **stop with the Virtual Machine Platform message and must not produce a WSL1 distro.**
  `wsl --list --verbose` must show no version-1 distro. If this cannot be constructed on an
  Azure VM, say so and mark it VOID with a named reason rather than passing it by inspection.

### 8.3 Rules the brief must carry

- **Deallocate at every handoff.** Box E reboots, and auto-logon is a one-shot: after the
  restart a human logs in over RDP and starts the on-VM runner by hand. **Plan it in**; the
  reboot is the subject of the test, not an incident.
- **Do not generate, print or ask for an admin password.** The operator sets it once, at
  provisioning.
- `Standard_D2s_v4`. One `az vm run-command invoke` at a time. Check the exit code of every
  `az` call.
- Point the runner's digest gate at whichever artifact is used, and **refuse to proceed on a
  mismatch** — reproducing against the wrong bytes answers every question fluently and wrongly.

---

## 9. Git

```
$ git status --short          # at session start
(clean)
$ git status --short          # at close
(clean)
```

Explicit per-file staging throughout, no `git add -A`, no `git worktree add`, **no tags**,
nothing pushed. Ten commits, `1e16f6b..1c97b47`.

| File | Change |
|---|---|
| `setup.ps1` | D1, D2, D3, D4, D5, D6, D7, D8, 850, WSL1 removal, version bump |
| `README.md` | two WSL1 claims rewritten; the v1.4.5 badge |
| `ClawFactory-Secure-Setup.iss` | `MyAppVersion` 1.4.5 |
| `resources/uninstall.ps1` | one comment reworded |
| `validation/uninstall-teardown-extract.sh` | the same comment, separate commit, not shipped |
| `validation/verify-v145-fixes.ps1` | new — the proof harness |
| `docs/session_reports/2026-08-30_v145_install_path_fixes_closeout.md` | this file |

**Line endings held.** `setup.ps1` carries `attr/-text`, so git performs no conversion and the
bytes written are the bytes committed; `git ls-files --eol` reads `i/lf w/lf` and a CR count
over the file returns **0**. The worktree gate confirms it from the other direction: all 54
tracked `[Files]` resources are byte-identical to their committed form.

---

## 10. What is owed next

1. **The validation run**, §8. Two boxes, one of them stock.
2. **Signing and release**, only after it returns. `scripts\build_release.ps1`, then tag, then
   attach the asset as exactly `ClawFactory-Secure-Setup.exe`.
3. **`SECURITY_FINDINGS.md:3`'s version currency claim** — a doc commit, not a build.
4. **`docs/V1_5_BACKLOG.md`'s WSL1 census** should gain the two `README.md` rows it was missing,
   so the next reader of that table is not misled by its claim of completeness.
5. **`OM-1` in `docs/VALIDATION_PREAMBLE.md` remains open.** This session provisioned no box and
   did not take the `:8787` measurement. The entry stands.
6. **The five systemd units enabled with `|| true`** are untouched here and remain a separate
   job with a separate test, exactly as the brief scoped them.
