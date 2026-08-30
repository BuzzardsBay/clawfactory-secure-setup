# First external install failure — diagnosis and fix design

**Date:** 2026-08-30
**Repo:** `C:\Users\bmcki\ClawFactory-Secure-Setup`, branch `main`, clean at start (`d10ebfe`)
**Subject:** v1.4.4, `provider=openai`, first install by anyone who did not build the product.
Failed 88 seconds in.
**Job state at close:** Tasks 0, 1, 3 and 4 **COMPLETE**. Task 2 (reproduction) **STAGED AND
BLOCKED** on one operator action, described in the handoff card at the end. Nothing in this
document depends on the reproduction having run; every claim is labelled with what it rests on.

---

## 0. Preamble clauses deleted, and why

The PROMPT 15 block from `docs/VALIDATION_PREAMBLE.md` was pasted into this job in full.
**Nothing was deleted.** The Azure and VM clauses are load-bearing here: the job provisions a
box, and the resource-ledger, one-dispatch-at-a-time, handoff-card and calibration clauses all
governed work actually done below.

Two clauses fired and changed what this session did:

- **"CALIBRATE BEFORE MEASURING."** Every body in the new probe was run against a known-answer
  input before the probe was allowed near a real box. §6.2 records the results, including a
  negative control.
- **"A citation proves the provenance of a sentence, not the provenance of the artefact."**
  The tag `v1.4.4` points at `9111e9b`, a documentation commit, while the artefact was built
  from `25945d5`. Reading `setup.ps1` at the tag would have been reading a file at a commit
  that did not produce the installer. §1.1 resolves this by comparison rather than by assuming
  they agree.

---

## 1. TASK 0 — reading the code that shipped, not the code that is current

### 1.1 The revision question, settled before anything was read

The job brief said to check out the tag rather than read `HEAD`. That is right in spirit and
insufficient in fact: the annotated tag `v1.4.4` resolves to `9111e9b`, a commit that touched
only `docs/RELEASE_NOTES_v1.4.4.md` and `docs/RELEASE_v1.4.4_GITHUB_BODY.md`, and the tag
message itself says the artefact was **built from `25945d5`**. Tag and build commit are
deliberately different (`project_v144_published`).

So both were extracted and compared rather than one being trusted:

```
$ git show v1.4.4:setup.ps1  > setup_tag.ps1
$ git show 25945d5:setup.ps1 > setup_build.ps1
$ diff setup_tag.ps1 setup_build.ps1 && echo IDENTICAL
IDENTICAL
```

Both are 214,311 bytes, 3,869 lines. **`setup.ps1` is byte-identical at the tag and at the
build commit**, so the distinction does not bite here — but it was checked rather than assumed,
and a future job on a file that *did* change between those two commits would have been misled.

### 1.2 The stack-trace line numbers, verified

The external stack trace names four sites. Every one of them lands where it should in
`setup_build.ps1`:

| Trace line | What the file actually holds there |
|---|---|
| `New-ClawUserAndSetDefault`, line **556** | `    if ($rc -ne 0) { throw "Failed to pre-create clawuser stub (exit=$rc)" }` |
| `Step-EnsureWsl`, line **928** | `        New-ClawUserAndSetDefault` |
| `Invoke-WithRollback`, line **628** | `    try { & $Body }` |
| dispatch, line **3708** | `Invoke-WithRollback {` |
| dispatch, line **3710** | `    Step-EnsureWsl` |

Line 556 is inside `New-ClawUserAndSetDefault` (which begins at 533 and ends at 557) and is the
`throw` that produced the exact message in the console. **This is the right revision.** Every
line number cited anywhere below refers to `setup.ps1` at `25945d5`, which is the file installed
to `C:\Program Files\ClawFactory\setup.ps1` on the external machine.

### 1.3 The four functions, verbatim

**`New-ClawUserAndSetDefault`, 533–557:**

```
 533| function New-ClawUserAndSetDefault {
 534|     # Pre-creates clawuser as a TEMPORARY sudoer (NOPASSWD) so Ubuntu's
 535|     # first-launch locale-setup script and other OOBE hooks don't block
 536|     # waiting for an interactive default user, and sets it as the WSL
 537|     # default in /etc/wsl.conf. Step-CreateClawUser strips both the sudoers
 538|     # line and the sudo group membership later, restoring the non-privileged
 539|     # security model (DEVIATION A2: clawuser is non-sudo at runtime).
 540|     Write-Log INFO 'Pre-creating clawuser stub (temp sudoer) and setting WSL default user.'
 541|     $script = @'
 542| set -e
 543| if ! id clawuser >/dev/null 2>&1; then
 544|     useradd -m -s /bin/bash clawuser
 545| fi
 546| usermod -aG sudo clawuser
 547| grep -qx 'clawuser ALL=(ALL) NOPASSWD:ALL' /etc/sudoers || \
 548|     echo 'clawuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
 549| touch /etc/wsl.conf
 550| sed -i '/^\[user\]/,/^$/d' /etc/wsl.conf
 551| printf '\n[user]\ndefault=clawuser\n' >> /etc/wsl.conf
 552| chmod 644 /etc/wsl.conf
 553| echo "clawuser-stub ready: uid=$(id -u clawuser)"
 554| '@
 555|     $rc = Invoke-WslBash -Script $script -User 'root'
 556|     if ($rc -ne 0) { throw "Failed to pre-create clawuser stub (exit=$rc)" }
 557| }
```

**`Step-EnsureWsl`, the branch that was taken, 904–935:**

```
 904|     # Kernel-loaded check. If `wsl --status` returns 0 the feature is active
 905|     # and we can install Ubuntu without rebooting. Otherwise enable features
 906|     # via DISM and reboot - the resume branch above completes the install.
 907|     # Uses Process.Start (not 2>&1) - same reason as Invoke-WslBash: PS 5.1
 908|     # converts each stderr line to an ErrorRecord and $ErrorActionPreference =
 909|     # 'Stop' turns those into terminating errors before we can check ExitCode.
 910|     $psiStatus = New-Object System.Diagnostics.ProcessStartInfo
 911|     $psiStatus.FileName               = 'wsl.exe'
 912|     $psiStatus.Arguments              = '--status'
 913|     $psiStatus.RedirectStandardOutput = $true
 914|     $psiStatus.RedirectStandardError  = $true
 915|     $psiStatus.UseShellExecute        = $false
 916|     $psiStatus.CreateNoWindow         = $true
 917|     $procStatus = [System.Diagnostics.Process]::Start($psiStatus)
 918|     $null = $procStatus.StandardOutput.ReadToEnd()
 919|     $null = $procStatus.StandardError.ReadToEnd()
 920|     $procStatus.WaitForExit()
 921|     $kernelOk = ($procStatus.ExitCode -eq 0)
 922|
 923|     if ($kernelOk) {
 924|         Write-Log INFO 'WSL2 kernel loaded but Ubuntu missing - installing Ubuntu only.'
 925|         $bundledTarball = if ($BundledRootfsDir) { Join-Path $BundledRootfsDir 'ubuntu-rootfs.tar.gz' } else { '' }
 926|         $variant = Install-WslDistroWithFallback -BundledRootfs $bundledTarball
 927|         Write-Log INFO "WSL variant installed: $variant"
 928|         New-ClawUserAndSetDefault
 929|         Start-Sleep -Seconds 5
 930|         if (-not (Test-WslFunctional)) {
 931|             throw 'WSL could not be configured on this machine. Please contact support at hello@avitalresearch.com'
 932|         }
 933|         Save-Checkpoint 'EnsureWsl'
 934|         return
 935|     }
```

**`Invoke-WithRollback`, 626–647:**

```
 626| function Invoke-WithRollback {
 627|     param([scriptblock]$Body)
 628|     try { & $Body }
 629|     catch {
 630|         Write-Log ERROR "Install failed: $($_.Exception.Message)"
 631|         Write-Log ERROR $_.ScriptStackTrace
 632|         # v1.0.14: @() forces array context. PS 5.1 unrolls single-element
 633|         # array returns to a bare scalar; under StrictMode 3 a string has no
 634|         # .Count property, which threw "property 'Count' cannot be found"
 635|         # in v1.0.13 when only the Preflight checkpoint had been saved.
 636|         $done = @(Get-CompletedSteps)
 637|         if ($done.Count -gt 0) {
 638|             $ans = Confirm-Or-Default 'Installation failed. Run automatic rollback? (y/N)' 'n'
 639|             if ($ans -match '^[Yy]') {
 640|                 Invoke-Rollback -CompletedSteps $done
 641|             } else {
 642|                 Write-Log INFO "Rollback skipped. Log: $LogFile"
 643|             }
 644|         }
 645|         throw
 646|     }
 647| }
```

**The dispatch, 3708–3713:**

```
3708| Invoke-WithRollback {
3709|     Step-Preflight
3710|     Step-EnsureWsl
3711|     Step-ConfigureWslConfig      # v1.0.1: Windows-side .wslconfig (vmIdleTimeout=-1)
3712|     Step-ConfigureWslConf
3713|     Step-RestartWsl
```

### 1.4 One transcription artefact in the pasted log, corrected

The log block in the job brief carries

```
Bundled rootfs SHA-256 = 1483ccc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109
```

which is **65 hex characters**. A SHA-256 is 64. The pin at `setup.ps1:467` and every one of the
eleven other places this digest is recorded in the repo all read `1483cc5c1dce…` (64 characters,
one `c` fewer). The pasted string has a duplicated `c` — a transcription artefact of reading the
value off a screenshot.

This matters only to rule something out. `setup.ps1:469-473` throws on mismatch and does **not**
fall through; the external log shows line 474's "matches the build-time pin" message, so the
comparison passed at install time. **The bundled rootfs is not implicated in this failure.**

---

## 2. TASK 1 — the actual path through the code

### 2.1 `wsl --update`: nothing looks at its output

There is exactly one invocation, in `Update-WslEngine` (`setup.ps1:230-269`), called from one
place, `Step-EnsureWsl:870`, unconditionally and before all three branches.

```
 247|     Write-Log INFO 'Running wsl --update before distro install (v1.0.28 preflight).'
 ...
 255|     $proc = [System.Diagnostics.Process]::Start($psi)
 256|     $out  = $proc.StandardOutput.ReadToEnd() + $proc.StandardError.ReadToEnd()
 257|     $proc.WaitForExit()
 258|     $rc = $proc.ExitCode
 259|     Write-Log INFO "wsl --update exit code: $rc"
 260|     if ($out) {
 261|         # wsl.exe emits UTF-16 LE; strip the null bytes that show as
 262|         # gibberish in the log if we don't.
 263|         $clean = ($out -replace "`0", '' -replace "`r?`n+", ' | ').Trim(' |')
 264|         if ($clean) { Write-Log INFO "wsl --update output: $clean" }
 265|     }
 266|     if ($rc -ne 0) {
 267|         Write-Log WARN "wsl --update returned $rc (continuing anyway - install may still succeed if the engine was already current)."
 268|     }
 269| }
```

**Does any code inspect that output for a reboot-required signal? No.** `$out` is captured at
256, whitespace-normalised at 263, written to the log at 264, and never referenced again. The
function returns nothing. `$rc` is compared against zero at 266 and, on the external machine,
`$rc` was 0, so even the WARN did not fire.

The sentence Windows emitted —
`Changes will not be effective until the system is rebooted` — was pasted into an INFO line
in the middle of a message reading `The operation completed successfully`. **VERIFIED from the
code: the installer logged the reboot requirement and had no code capable of acting on it.**

Further, `Enable-WindowsFeaturesForWsl` (`setup.ps1:405-426`) is the only function in the file
that knows DISM exit **3010** means *success, restart required*. An AST census of the shipped
file (53 function definitions, 554 command nodes, with `Step-EnsureWsl` as a positive control
returning 1) reports:

```
  DEAD  line  405  Enable-WindowsFeaturesForWsl
  DEAD  line  559  Invoke-WslInstallWithRestart
  CANARY  Step-EnsureWsl call count = 1
```

**Both are defined and never invoked anywhere in the file.** The installer never runs DISM at
all; `VirtualMachinePlatform` is enabled only as a side effect of `wsl --update`, whose reboot
signal nothing reads. So the two pieces of code that understand "reboot required" are one that
is never called and one whose output is only logged.

### 2.2 The import, the fallback, and what makes it claim success

`Install-WslDistroWithFallback`, `setup.ps1:483-509`:

```
 483|         $rImp = Invoke-WslExe -Arguments @('--import', $WslDistro, $WslInstallDir, $BundledRootfs, '--version', '2')
 484|         foreach ($line in (($rImp.StdOut + "`n" + $rImp.StdErr) -split "`r?`n")) {
 485|             $t = $line.Trim()
 486|             if ($t) { Add-Content -LiteralPath $LogFile -Value "[wsl --import v2] $t" -Encoding UTF8 }
 487|         }
 488|         if ($rImp.ExitCode -eq 0) {
 489|             Write-Log INFO 'WSL2 import from bundle succeeded.'
 490|             return 'wsl2'
 491|         }
 492|         Write-Log WARN "wsl --import failed (exit $($rImp.ExitCode)), falling through to wsl --install."
 493|     }
 494|
 495|     Write-Log INFO 'Installing Ubuntu (attempting WSL2 first).'
 496|     $rInst = Invoke-WslExe -Arguments @('--install', '--no-launch', '-d', $WslDistro)
 497|     $output = $rInst.StdOut + "`n" + $rInst.StdErr
 498|     foreach ($line in ($output -split "`r?`n")) {
 499|         $t = $line.TrimEnd()
 500|         if ($t) { Add-Content -LiteralPath $LogFile -Value "[wsl install out] $t" -Encoding UTF8 }
 501|     }
 502|     if ($rInst.ExitCode -eq 0) {
 503|         Write-Log INFO 'WSL2 install succeeded.'
 504|         return 'wsl2'
 505|     }
 506|     $hyperVMissing = ($output -match 'HCS_E_HYPERV_NOT_INSTALLED' -or $output -match '0x80370102')
 507|     if (-not $hyperVMissing) {
 508|         throw "wsl --install failed (exit $($rInst.ExitCode)) and no fallback signal detected. See $LogFile."
 509|     }
```

**What condition causes `WSL2 install succeeded` to be logged: `$rInst.ExitCode -eq 0`, and
nothing else.** One integer from one process.

**What verifies a distro exists between that log line and the next step: nothing.** Line 503
logs, line 504 returns `'wsl2'`, control returns to `Step-EnsureWsl:926`, line 927 logs the
variant, and line 928 calls `New-ClawUserAndSetDefault`. There is no `wsl --list`, no
`Test-WslFunctional`, no file check, no anything between them. Stated plainly rather than
quoted, because there is no code to quote.

The timestamps make the emptiness of that claim concrete. `wsl --import` failed and
`wsl --install --no-launch -d Ubuntu` reported success **in the same second, 11:11:18**. A
network install of Ubuntu transfers several hundred megabytes. Whatever exit 0 meant there, it
did not mean a distro had been fetched and registered.

**A separate defect in the same block, not in the working hypothesis.** Line 506 tests for the
virtualization diagnostic — `HCS_E_HYPERV_NOT_INSTALLED` / `0x80370102` — against `$output`,
which is built at 497 from `$rInst`, the **install** call. The **import** call's streams live in
`$rImp` and are used at 484-486 for logging only. So the one place in this file that recognises
a virtualization fault reads the wrong command's output, and on the external machine it never
ran at all, because `$rInst.ExitCode` was 0 and line 502 returned first. The real diagnostic —
whatever `wsl --import` actually said — was written to
`C:\ProgramData\ClawFactory\install.log` under the prefix `[wsl --import v2]` and examined by
nothing. **That text is still on the external machine and is the single most valuable piece of
untaken evidence in this investigation.** It is ask (a) in the handoff card.

### 2.3 The BIOS-virtualization preflight at 11:09:53

`Step-Preflight`, `setup.ps1:814-821`:

```
 814|     try {
 815|         $cpu = Get-CimInstance Win32_Processor
 816|         if (-not $cpu.VirtualizationFirmwareEnabled) {
 817|             Write-Log WARN 'Virtualization may be disabled in BIOS. WSL2 may fail to start.'
 818|         }
 819|     } catch {
 820|         Write-Log WARN 'Could not query CPU virtualization state.'
 821|     }
```

- **What it tests:** one WMI property, `Win32_Processor.VirtualizationFirmwareEnabled`, an
  OEM-populated firmware bit.
- **What it does with a negative result:** writes a WARN line. Nothing else. No variable is
  set, no state is recorded, nothing downstream reads it.
- **Is it a warning or a gate:** **a warning.** There is no `throw`, no `exit`, no branch. The
  next statement is the unrelated `wsl.exe` PATH check at 822.

The wording is also weaker than the code deserves: "may be disabled" is what a
`$null` reads like, and `-not $null` is `True`, so the WARN fires identically whether the
property says *disabled* or says *nothing at all*. Under `Set-StrictMode -Version 3.0` with a
multi-socket machine the property access member-enumerates to an array and `-not @()` is also
`True`, so an empty result fires it too.

**Calibrated on a known machine** (this build machine, 2026-08-30):

```
Win32_Processor.VirtualizationFirmwareEnabled = [True]  type=Boolean  (AMD Ryzen 7 9800X3D)
Win32_ComputerSystem.HypervisorPresent        = True
setup.ps1:816 WARN branch would fire        = False
```

This is worth stating because the common folklore — *the property always reads False once a
hypervisor is running* — is **not true here**: virtualization is live, Hyper-V is present, and
the property still reads `True`. So the WARN on the external machine is **not** explained away
by "Hyper-V had already claimed the firmware bit", and the possibility that the reading is
genuine is correspondingly stronger. It remains one unreliable bit on one machine and settles
nothing on its own, which is why the Task Manager reading matters.

### 2.4 What produces exit `-1` in `New-ClawUserAndSetDefault`

`$rc` at line 555 is whatever `Invoke-WslBash` returns, and `Invoke-WslBash`
(`setup.ps1:654-774`) returns `$proc.ExitCode` at line 756/773 — the exit code of **`wsl.exe`
itself**, launched at 683 as:

```
 683|     $psi.Arguments              = "-d $WslDistro -u $User --cd ~ -- bash -l -s"
```

**`-1` is not a distinct condition and the bash payload did not choose it.** The payload's own
failure codes would be 1 (`set -e` on a failed `useradd`), 2, 126, 127 and so on. `-1` is
`wsl.exe` failing to launch the distro at all — the same value `wsl --import` returned two log
lines earlier, from the same executable, for the same underlying reason. The message
`Failed to pre-create clawuser stub (exit=-1)` names a Linux user account and a sudoers file
that were never reached.

The stderr `wsl.exe` printed alongside that `-1` **was captured** — `Invoke-WslBash:765-771`
writes it to the log file as `[wsl:root err] …`, and line 772 writes `[wsl:root exit] -1`. Like
the import diagnostic, it went to the file and never to the console. Same ask, same file.

### 2.5 One more signal in the timestamps

`Step-EnsureWsl` logs "Step 2" at **11:09:53** and `distroExistedPreInstall=False` at
**11:10:53**. Between those two lines the only work is the `wsl --list --quiet` at
`setup.ps1:848`. **That call took sixty seconds**, against roughly one second for the same call
at 11:11:18 after `wsl --update` had run. A minute-long `wsl --list` on a machine with no
distros is itself an indication that the WSL layer was not healthy before the installer touched
it. Recorded as corroboration; it does not discriminate between the candidate causes.

### 2.6 The causal chain, with every link labelled

At 11:09:53 the preflight read one firmware bit, wrote `Virtualization may be disabled in BIOS`,
and continued, because that branch is a warning and not a gate **[VERIFIED, setup.ps1:814-821]**.
At 11:10:53 a `wsl --list` that took a full minute returned no distros **[VERIFIED from the
timestamps]**. At 11:11:17 `wsl --update` installed WSL 2.7.12, enabled the
`VirtualMachinePlatform` optional component, and stated that the change would not take effect
until reboot; `Update-WslEngine` wrote that sentence into an INFO line and has no code that reads
it **[VERIFIED, setup.ps1:230-269]**. One second later `wsl --status` exited 0, so
`$kernelOk` was true and the installer took the import branch at line 923 instead of the
reboot-and-resume branch at line 937 **[INFERRED — the branch taken is verified from the log's
next line, but that `wsl --status` exits 0 in a pending-reboot state is the assumption this whole
diagnosis turns on and is Task 2's PR.C1]**. `wsl --import` of the digest-verified bundled rootfs
then failed with `-1`, which is the first real failure **[VERIFIED from the log]**; its
diagnostic text went to `install.log` and was read by nothing, because line 506's virtualization
check is applied to the *install* call's output and not the *import* call's **[VERIFIED,
setup.ps1:497 vs 506]**. The fallback ran `wsl --install --no-launch -d Ubuntu`, which returned 0
in the same second, and line 502 accepted that integer as proof, logged `WSL2 install succeeded`
and returned `'wsl2'` with nothing between it and the next step checking that a distro existed
**[VERIFIED, setup.ps1:496-504]**. Line 928 then called `New-ClawUserAndSetDefault`, whose
`wsl.exe` invocation could not launch a distro that was never created and returned `-1`, and line
556 turned that into a message about a Linux user account **[VERIFIED]**. The verification that
would have caught it — `Test-WslFunctional` — exists, is already called, and sits at line 930,
**two lines too late** **[VERIFIED]**. Whether the underlying cause was the pending reboot or
virtualization genuinely disabled in the machine's firmware is **[UNKNOWN]**, and §3 explains
why the console log cannot distinguish them.

### 2.7 Challenging the prompt: where the hypothesis is right, wrong, and incomplete

The brief asked to confirm or refute rather than assume. Point by point:

- **"`wsl --update` enabled `VirtualMachinePlatform` and the installer logged the reboot
  sentence inside a success message and continued."** **CONFIRMED**, and stronger than stated:
  there is no code anywhere in the file capable of acting on a pending-reboot condition, because
  the only function that understands DISM's 3010 is dead code.

- **"`wsl --import` failed with `-1`, the first real failure and the one that mattered."**
  **CONFIRMED as the first real failure.** Partly refuted as "the one that mattered": its
  *diagnostic* mattered more than its exit code, and that diagnostic was captured to disk and
  then ignored by a check pointed at the wrong variable.

- **"The fallback reported success without producing a usable distro and the installer believed
  it."** **CONFIRMED from the code.** This is the most serious of the three and it is the only
  one that is **cause-independent**: whether the machine needed a reboot or needs a BIOS change,
  line 502 accepts an integer as proof of a filesystem, and the user is told about a sudoers
  file either way.

- **"Two separate defects, and the second is the more serious."** **Agreed on the ordering.**
  But there are **five**, not two, and the numbering below reflects that.

- **"There is a third candidate cause stacked underneath: BIOS."** **This is not a red herring
  and it is not resolved.** §3 is about it.

The one place the brief bends the evidence, gently: it treats the pending reboot as the cause and
BIOS as a stacked-underneath alternative. On the evidence available they are **symmetric**. Both
produce a `wsl --update` that succeeds, a `wsl --status` that exits 0, an import that fails `-1`,
and a `wsl.exe` that cannot launch a distro. **Every line of the console log is identical under
both stories.** That is not a reason to prefer one; it is a reason to say the console log cannot
answer it, and to name the two artefacts that can.

---

## 3. Which cause it actually was — and why the console cannot say

Two readings are alive:

**(i) Pending reboot.** `VirtualMachinePlatform` was enabled by `wsl --update` and needs a
restart. A reboot fixes it. The preflight WARN was a false alarm from an unreliable bit.

**(ii) Firmware.** Intel VT-x / AMD-V (SVM Mode) is off in the machine's BIOS/UEFI. No reboot
fixes it. The preflight found the real blocker 85 seconds before the failure and let the install
proceed anyway.

They are not exclusive; both can be true at once, in which case a reboot alone still fails.

**Two artefacts discriminate, and only two.**

1. **Task Manager → Performance → CPU → Virtualization**, on the external machine. Already in
   flight per the brief. `Enabled` kills reading (ii) outright. `Disabled` confirms it.

2. **`C:\ProgramData\ClawFactory\install.log` on the external machine.** This file is written by
   `Write-Log` at `setup.ps1:154` and holds three things that never reached the console:
   - `[wsl --import v2] …` — `wsl.exe`'s own error text for the import failure. WSL emits
     *materially different* text for "the Virtual Machine Platform is not enabled / restart
     required" than for "virtualization is not enabled in the firmware". This one line most
     likely settles it on its own.
   - `[wsl install out] …` — what `wsl --install --no-launch -d Ubuntu` printed while returning 0,
     which is the direct evidence for defect 2.
   - `[wsl:root err] …` and `[wsl:root exit] -1` — the stderr behind the clawuser message.

The reproduction in §5 is designed to answer (i) on a box we control. **It cannot answer (ii)**,
because an Azure VM's virtualization state is not the external machine's firmware. Only artefact
1 answers that. Both asks are in the handoff card, and the log is listed first because it is free
and does not need the machine's owner to navigate anything.

---

## 4. TASK 3 — the fix design. Nothing implemented; `setup.ps1` is untouched in this job.

### 4.0 The five defects

| # | Defect | Status | Severity |
|---|---|---|---|
| **D1** | No pending-reboot condition anywhere; `wsl --update`'s reboot sentence is logged and unread; the only function that understands DISM 3010 is dead code | VERIFIED from code | high |
| **D2** | `Install-WslDistroWithFallback` accepts an exit code as proof a distro exists. Silent fake-success | VERIFIED from code | **highest** |
| **D3** | The BIOS-virtualization preflight is a warning, not a gate, and sets no state that later failures can consult | VERIFIED from code | high |
| **D4** | The virtualization diagnostic at `setup.ps1:506` is applied to the `wsl --install` output, never to the `wsl --import` output where the real error was | VERIFIED from code | medium |
| **D5** | `Test-WslFunctional` — the exact check D2 needs — already exists and is already called, two lines after the step that fails first | VERIFIED from code | medium (it makes D2's fix nearly free) |

### 4.1 D1 — stop on a pending reboot, at the point it is knowable

**Where.** A new `Test-PendingReboot` helper next to `Update-WslEngine`, and one new branch in
`Step-EnsureWsl` immediately after the `Update-WslEngine` call at line 870, **before** the
`$Resume` branch at 872.

**What it checks — and explicitly not the sentence.** Matching the English string
`will not be effective until the system is rebooted` would silently stop working on a Windows
installed in any other language, which is a defect of exactly the class this catalogue is about.
The check is:

- `(Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State` — a typed
  enum, `EnablePending` / `DisablePending` / `Enabled` / `Disabled`, language-independent.
  Same for `Microsoft-Windows-Subsystem-Linux` and `HypervisorPlatform`.
- Secondary, belt-and-braces:
  `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending`
  and `…\WindowsUpdate\Auto Update\RebootRequired`.

The `wsl --update` output is still logged, and its reboot sentence is recorded as *corroboration*
in the log, never as the condition.

**What it does on failure.** Takes the reboot-and-resume path that already exists at
`setup.ps1:982-1019` — `Register-ResumeScheduledTask`, `Save-ResumeFlag`, restart dialog,
`Restart-Computer` — rather than falling through to the `$kernelOk` test at 921. No new
subsystem; the existing one is simply reachable from a second condition.

**Loop guard, which the current code has no need for and the fixed code does.** The resume flag
gains a `rebootCount`. On the `$Resume` path, if the feature is *still* `EnablePending`, stop —
do not reboot a second time. Message: *"Windows still reports that a restart is pending after
restarting. Please restart this computer manually and run the ClawFactory installer again. If
this repeats, see C:\ProgramData\ClawFactory\install.log."*

**What the user sees.** The existing `Restart Required` dialog with accurate text: *"Windows
needs to restart to finish turning on virtualization support. ClawFactory will continue
automatically after the restart."* Under `/SILENT` it logs and reboots, exactly as line
1005-1019 does today.

### 4.2 D2 — verify the fallback's claim before the next step runs

**Where.** `Install-WslDistroWithFallback`, at all three success sites: 488 (import), 502 (WSL2
install), 526 (WSL1 install).

**What the check is.** `Test-WslFunctional` (`setup.ps1:271-292`), unchanged, called before each
`return`. It runs three `wsl.exe` invocations: `--status` must exit 0, `--list --quiet` must
contain `$WslDistro`, and `-d $WslDistro -u root -- true` must exit 0. That third call is the
one that actually proves a Linux userspace exists, which is the claim being made.

```
    if ($rInst.ExitCode -eq 0) {
        if (-not (Test-WslFunctional)) {
            throw ("wsl --install reported success (exit 0) but no working '$WslDistro' distro " +
                   "exists afterwards. Refusing to continue against a distro that was never created. " +
                   "See $LogFile for what wsl.exe actually printed.")
        }
        Write-Log INFO 'WSL2 install succeeded (verified: distro present and responding).'
        return 'wsl2'
    }
```

**What it costs.** Three `wsl.exe` process launches per success path. On a healthy machine that
is well under a second — measurable on boxes A–D, where the same three calls already run at line
930 five seconds later. On a broken machine the cost is bounded by `wsl.exe`'s own behaviour, and
this investigation has one measurement of that: **`wsl --list --quiet` took 60 seconds** on the
external machine at 11:09:53. So the honest worst case is *tens of seconds added to an install
that is going to fail anyway*, in exchange for failing at the step that is actually wrong. That
is a good trade and it should be stated as a trade rather than as free.

**What the user sees.** Not this message. The `throw` propagates to `Invoke-WithRollback` and the
console shows the text above, which names the real thing that went wrong. Under D3's change the
message additionally branches on the firmware reading (§4.3).

**D5, the one-line net underneath.** Independently of the above, swap the order at
`setup.ps1:928-930`, `884-888` and `973-975` so `Test-WslFunctional` runs **before**
`New-ClawUserAndSetDefault`. On the external machine this alone would have replaced
`Failed to pre-create clawuser stub (exit=-1)` with
`WSL could not be configured on this machine`. It is strictly redundant once D2 lands, and it
should still be done: a second net under the first one, for one line.

That message should itself be rewritten. `Please contact support at hello@avitalresearch.com` is
the wrong instruction for a product that is free, public and unsupported (`v1.4.4` release notes;
`docs/` issue templates). It should name the two things a user can actually do — restart; check
BIOS virtualization — and point at `C:\ProgramData\ClawFactory\install.log`.

### 4.3 D3 — the BIOS preflight: **not** a hard gate, and here is why

**Recommendation: do not turn `Win32_Processor.VirtualizationFirmwareEnabled` into a hard gate.**

The reasoning, stated so it can be argued with. The property is one OEM-populated firmware bit.
It reads `$null` on some hardware, and `-not $null` is `True`, so the current WARN already cannot
distinguish *disabled* from *not reported*. Gating an installer on it would refuse to install on
machines where WSL2 works perfectly. A false gate on a signal this weak is a worse defect than
the warning it replaces, and it is the same mistake as trusting `wsl --status`: **building a
branch on a value that does not mean what the branch needs it to mean.** That is the sentence
this whole failure is about, and applying it in one direction while ignoring it in the other
would not be consistent.

**What it becomes instead — a deferred gate.** Three changes:

1. **Read more, at preflight.** Log `VirtualizationFirmwareEnabled`,
   `Win32_ComputerSystem.HypervisorPresent`, `SecondLevelAddressTranslationExtensions` and
   `VMMonitorModeExtensions`, each with its raw value and type. The log then carries the full
   picture instead of one bit, and the next person diagnosing this reads facts rather than a
   verdict. Cheap; no behaviour change.
2. **Record the finding.** Set `$script:VirtFirmwareSuspect` rather than only writing a WARN.
   Today the warning informs nobody and nothing.
3. **Let it explain, when a real failure proves it right.** D1's and D2's `throw` messages branch
   on `$script:VirtFirmwareSuspect`. When it is set, the user is told:

   > *ClawFactory could not start the Linux environment, and your computer reports that hardware
   > virtualization may be turned off in its firmware. Open Task Manager, go to Performance →
   > CPU, and look at "Virtualization". If it says Disabled, restart your computer, enter the
   > BIOS/UEFI setup screen, and turn on Intel VT-x (or AMD SVM Mode), then run this installer
   > again. Full details are in C:\ProgramData\ClawFactory\install.log.*

   When it is not set, the user gets the reboot message instead.

**One thing that should become a hard gate,** and this is the real safety change in D3. The WSL1
fallback at `setup.ps1:510-530` is reachable and returns `'wsl1'`. WSL1 has no systemd. Every
structural control this product ships — `clawfactory-quarantine.service`,
`clawfactory-send.service`, `clawfactory-proxy.service`, the nftables chain installed by
`Step-EgressFirewall` — is a systemd unit or depends on one. **A WSL1 install would produce a
ClawFactory with none of its security controls**, and line 529's warning, *"Some features
(systemd, networking) behave differently on WSL1"*, materially understates that. The fallback
should either refuse outright with a named message, or be removed. It has never executed on any
validation box (§4.5), so removing it carries no regression risk that any measurement would
detect. **This is out of scope for this job and is filed rather than fixed** — it is a security
claim question, not an install-failure question, and it deserves its own decision.

### 4.4 What each fix costs, and whether this is a v1.4.5

**Shipped bytes.** All of D1–D5 change `setup.ps1`, which is `[Files]` line 45 of
`ClawFactory-Secure-Setup.iss` and installs to `C:\Program Files\ClawFactory\setup.ps1`. **Yes:
rebuild, re-sign, a new `released-versions.tsv` row, and revalidation.** Nothing here can ship as
a documentation commit.

**Does it warrant a v1.4.5 ahead of v1.5? Yes.**

The product is published, free and public. `clawfactory.app` links straight at the v1.4.4 asset
(`project_ship_a_site_pass`). The first person outside this project to run it could not install
it, and the message he got named a Linux user account. Whatever the root cause turns out to be,
**the modal first-time user is on a machine that has never had WSL** — which is precisely the
path with the least measurement behind it. The open v1.5 items (persona authorability, the
mojibake sweep, the README gate-count and badge) are unrelated to this and larger. Shipping the
install fix behind them leaves the product failing on first install for however long v1.5 takes.

**With one condition, stated as a condition and not a hedge: do not build v1.4.5 until Task 2
returns.** D2, D3, D4 and D5 are verified from the code and are correct under either reading of
§3. **D1's gate is not.** If PR.C1 refutes the pending-reboot story, a pending-reboot gate would
be a new branch built on a premise that was never measured — which is the defect being fixed,
committed a second time. D1 is the only one that waits.

**Revalidation scope.** Not a full four-box rerun; the changed surface is `Step-Preflight`,
`Step-EnsureWsl` and `Install-WslDistroWithFallback`, all of which complete before
`Step-ConfigureWslConfig`. What is needed:

- **Box E, the new one.** Stock Windows 11, never had WSL, pending-reboot state constructed
  deliberately. This is the case that has never existed. §4.5.
- **One baseline-v2 box.** To prove the added verification does not regress the path all four
  v1.4.4 boxes took. D2 inserts three `wsl.exe` calls into a *succeeding* install; that is the
  regression risk and it is the only one.
- **Box D's structural table does not need rerunning.** Nothing below `Step-EnsureWsl` changes.
  **Stated with the risk named:** if any of D1–D5 turns out to alter the `$variant` value or the
  checkpoint sequence, that assumption is wrong and the structural rerun becomes mandatory. The
  build that lands should confirm `$variant` and the `completedSteps` array are unchanged before
  this exemption is taken.

### 4.5 TASK 3.5 — the regression test, written before the fix

**It exists, is committed in this session, and is calibrated:
`validation/interim-v145-pendingreboot.ps1`**, with its build-machine driver
`validation/interim-v145-runner.ps1`. Written now, deliberately, so it cannot be shaped by
whatever the fix turns out to be.

**The validation case.**

- **Image: stock `MicrosoftWindowsDesktop:windows-11:win11-24h2-pro`. NOT
  `clawfactory-win11-baseline-v2`.** This is the load-bearing choice in the whole design.
  baseline-v2 was baked with the WSL engine already installed via MSI
  (`project_baseline_v2_and_dsv5_quota`), which means it cannot ever be in the state under test.
- `PR.CTL0` asserts `VirtualMachinePlatform` reads `Disabled` at start. If it does not, the run
  is measuring baseline-v2 again and every row is void.
- The pending state is constructed by running `wsl --update` — the product's own route — not by
  DISM, so the state under test is the state the product produces. `PR.1b` records it if the
  DISM fallback was needed instead.
- `PR.CTL1` proves the fault landed: DISM must report `Enable Pending`. *A fault injection that
  does not inject scores a false pass and looks exactly like a working control.*
- `PR.C1` is the decisive row: does `wsl --status` exit 0 in that state.
- The shipped installer then runs `/VERYSILENT` and the log is captured verbatim.
- `PR.C3` / `PR.C4` / `PR.C5` measure the fallback's success claim, the `-1`, and what
  `Test-WslFunctional` would have returned — deliberately **after** the installer run, because
  they claim the distro name `Ubuntu` and would otherwise hand the installer a distro it did not
  create.
- Every row is then re-measured **after a reboot with nothing else changed** (`-Stage B` /
  `-Stage B2`), which is the control for the `az vm run-command`-runs-as-SYSTEM confound. If a
  call fails pre-reboot and succeeds post-reboot under the same SYSTEM context, SYSTEM is not the
  explanation. If it fails in both, the rows are VOID and say so.

**PASS criterion for the fixed build** (the thing this test exists to assert, once D1 lands):
the install **stops inside `Step-EnsureWsl` with a named restart instruction**, and the string
`Failed to pre-create clawuser stub` appears **nowhere** in `install.log`. Then, after a reboot
and no other change, the install proceeds past `Step-EnsureWsl`.

**What else the gap implies was never tested.** This is the part that generalises, and it is
larger than one branch.

All four v1.4.4 boxes — `cfv-179` (A), `cfv-180`/`cfv-181` (B/C), `cfv-182` (D) — ran
`clawfactory-win11-baseline-v2`, cited in each box's close-out. Every one of them entered
`Step-EnsureWsl` with WSL live, so every one of them took the `Test-WslFunctional`-is-true path
at line 898 or the `$kernelOk` path at 923. **Nothing in the v1.4.x cycle has ever executed:**

- `Step-EnsureWsl:937-1019` — the entire "WSL not installed" branch:
  `wsl --install --no-distribution`, `Register-ResumeScheduledTask`, `Save-ResumeFlag`, the
  restart dialog, `Restart-Computer -Force`.
- `Step-EnsureWsl:872-895` — the whole `$Resume` branch, including its 12 × 5s ready loop.
- `Register-ResumeScheduledTask` / `Unregister-ResumeScheduledTask` (330-384).
- `Show-RestartDialog` (385-403).
- The Inno `/resume` re-entry: `GetResumeFlag`, `ReadResumeProvider`, `IsResumeRun`.
- `Install-WslDistroWithFallback:510-530`, the WSL1 fallback.
- `Enable-WindowsFeaturesForWsl` and `Invoke-WslInstallWithRestart` — dead, therefore
  **unexecutable**, which is a stronger statement than untested.

**How far back this goes, measured rather than asserted.** A tree-wide search for
`ClawFactory-Resume`, `resume-after-restart` and `Reboot required` finds **zero hits in
`docs/session_reports/`** — no close-out in this repository records the reboot-and-resume path
running. The only recorded execution is in `validation/REPORT_bisect_v1026_v1027.md`, dated
**2026-05-21**, where the scheduled task fired correctly under SYSTEM and the install then
**aborted anyway** in the resume branch with
`wsl --install failed (exit 1) and no fallback signal detected`.

So: **the reboot-and-resume subsystem has never run to completion in any recorded validation of
this product.** The one time it ran at all, it failed.

And the sequence closes on itself. That 2026-05-21 failure is why `Update-WslEngine` was added in
v1.0.28 — its own comment at `setup.ps1:236-239` cites the cfv-128 cycle. Shortly after,
`baseline-v2` was baked with WSL pre-installed so validation would stop tripping over the engine
version. From that point the reboot path was skipped on every box, and `wsl --update` — the fix —
was never again exercised on a machine where it would enable `VirtualMachinePlatform` and require
a reboot. **The fix for the old bug created the new one, on the one path nothing measured after
that.**

---

## 5. TASK 2 — reproduction: staged, calibrated, and blocked on one thing

### 5.1 Starting state of `clawfactory-validation` (Task 0 of the resource ledger)

Unfiltered list, not a grep for a VM name:

```
$ az resource list -g clawfactory-validation --query "[].[name,type]" -o tsv
clawfactoryvalc467             Microsoft.Storage/storageAccounts
bake-vmVNET                    Microsoft.Network/virtualNetworks
clawfactory-win11-baseline     Microsoft.Compute/images
clawfactory-win11-baseline-v2  Microsoft.Compute/images

$ az vm list / disk list / nic list / public-ip list / nsg list  -g clawfactory-validation
(all empty, all exit 0)
```

**Exactly the expected residual: the storage account, the VNET and the two baseline images.
Nothing else.** There were no prior FAIL VMs or OS disks to delete, so Task 0 required no
deletions. **No VM has been provisioned by this session** and nothing is currently billing
compute.

### 5.2 The artefact, identified by digest and not by filename

`combined-cfv-179.exe` through `combined-cfv-182.exe` in the `validation` container are **all
440,610,608 bytes**. Size does not identify which is the shipped build. The local
`Output\ClawFactory-Secure-Setup.exe` does:

```
local Output\ClawFactory-Secure-Setup.exe  sha256 = 6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1
tag v1.4.4 message claims                        = 6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1
MATCH = True
```

That file is what the runner uploads, and the `prep` step **refuses to proceed** if the hash does
not match — on the build machine before upload, and again on the box after download. Reproducing
against the wrong bytes would answer every question fluently and wrongly.

### 5.3 Calibration, before any box exists

Every body in the probe was run against a target whose answer was already known:

```
CALIBRATION of the probe's exit-code channel:
  expect 0   got 0    PASS=True
  expect 7   got 7    PASS=True
  expect -1  got -1   PASS=True      <- the exact value under investigation
  stdout captured: 'HELLO_CONTROL'   PASS=True
  stderr captured: 'ERR_CONTROL'     PASS=True
CALIBRATION of the DISM State regex:
  parsed State from a synthetic block = 'Enable Pending'   PASS=True
  'Enable Pending' -match 'Pending'   = True   (must be True)
  'Enabled'        -match 'Pending'   = False  (must be False)
  'Disabled'       -match '^Disabled' = True   (must be True)
  NEGATIVE CONTROL: regex against text with no State line matched = False  (must be False)
```

Both new files parse with zero errors under the PowerShell AST parser.

### 5.4 Two hazards designed around, named so a later reader does not re-learn them

- **Ordering.** The micro-probes claim the distro name `Ubuntu`. If they ran before the installer,
  the installer would find a distro this probe created and skip the branch under test. The
  runner's step order puts `install` before `A2` and says why in its header.
- **Appending.** `C:\ProgramData\ClawFactory\install.log` appends (`setup.ps1:154`). Stage B must
  not read a file carrying stage A's lines. The runner's `fetchA` step moves it aside; the probe
  additionally counts `starting` banners and records VOID if it finds more than one.

### 5.5 What is blocked, and what unblocks it

`az vm create` requires an admin password. The preamble is explicit: *"Do not generate an admin
password, do not print one, do not ask for one, and do not call `az vm user update` after
provisioning. The operator sets it once, at provisioning."* **That is the only thing standing
between this session and the measurement.** Everything else — probe, runner, calibration, digest
gate, resource census — is done.

**RDP is deliberately not opened.** Every stage of this reproduction runs under
`az vm run-command invoke`, and the SYSTEM-context confound is handled by the stage-B control
rather than by an interactive session. If a stage turns out to need a real logon, that becomes a
Card 2 at that point, not a rule bent quietly.

**Reproduction result: NOT YET TAKEN.** No claim is made in this document about whether the
failure reproduces. §2.6 labels every link accordingly and §3 states plainly what the
reproduction can and cannot settle.

---

## 6. Git

```
$ git status --short          # at session start
(clean)
```

Explicit per-file staging, no `git add -A`, no tags. **`setup.ps1` was not modified in this
job** — it was read, at a commit, out of the object database, into a scratch directory.

| File | Change |
|---|---|
| `validation/interim-v145-pendingreboot.ps1` | new — the regression probe, written before the fix |
| `validation/interim-v145-runner.ps1` | new — the build-machine driver |
| `docs/session_reports/2026-08-30_first_external_install_failure_closeout.md` | new — this file |
| `docs/FAILURE_CATALOGUE.md` | new Class 13 entry, and one corrected sentence in the header |

---

## 7. What is owed next

1. **The two artefacts from the external machine** (handoff card, asks a and b). The install log
   is free and probably decisive on its own.
2. **The reproduction**, once the box exists (handoff card, ask c).
3. **v1.4.5 scope decision.** D2, D3, D4, D5 are ready to specify into a build now. D1 waits on
   PR.C1.
4. **Filed, not fixed here:** the WSL1 fallback produces a ClawFactory with no systemd and
   therefore none of its structural controls (§4.3). Needs its own decision.
5. **`OM-1` in `docs/VALIDATION_PREAMBLE.md` remains open.** This session did not take the
   `:8787` measurement and the entry stands.
