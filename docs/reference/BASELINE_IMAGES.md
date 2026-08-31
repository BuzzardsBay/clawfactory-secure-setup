# Validation baseline images: what each one has already done

**Purpose.** A baseline image is a set of install steps already completed. Every step an
image has performed is a step the boxes built on it cannot measure — not a step that
passed, a step that was never asked. This file is the written record the
`docs/VALIDATION_PREAMBLE.md` clause *A BASELINE IMAGE IS A SET OF INSTALL STEPS ALREADY
COMPLETED* requires. Read it before choosing an image, not after a result is in dispute.

**Status: two managed images exist. Both are read from the tree and from Azure metadata;
nothing below is asserted from memory.** Written 2026-08-30. Update at every rebake, in the
same commit as the rebake.

---

## Why this file exists

On 2026-08-30 the first person outside this project to run the v1.4.4 installer could not
install it, on a Windows machine that had never had WSL. All four v1.4.4 validation boxes
had passed. They were four copies of one sample: every one entered `Step-EnsureWsl` with
virtualization already enabled and already rebooted, because the bake had done that and then
generalized the machine.

The belief recorded in `docs/FAILURE_CATALOGUE.md` 13.1 was that `clawfactory-win11-baseline-v2`
created this gap. **It did not.** The gap was created by the *original* bake, four weeks
earlier, and `-v2` only removed what was left. That correction is in §4.

---

## 1. `clawfactory-win11-baseline` — baked 2026-05-06

**Azure metadata** (`az image show`, read 2026-08-30): managed image, `hyperVGeneration = V2`,
`osState = Generalized`, `osType = Windows`, captured from a VM named `bake-vm` (no longer
present in the resource group), **no tags**.

**Source marketplace image:** `MicrosoftWindowsDesktop:Windows-11:win11-24h2-pro:latest`,
`SecurityType=Standard`, non-zonal. Recorded in
`validation-runs/phase1-bake-20260506-144034/log.md`.

**Steps performed before capture.** Verbatim from
`validation-runs/phase1-bake-20260506-144034/configure-vm.ps1`:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
wsl --install --no-distribution --web-download
Add-MpPreference -ExclusionPath "C:\Program Files\ClawFactory"
Add-MpPreference -ExclusionPath "C:\ProgramData\ClawFactory"
Add-MpPreference -ExclusionPath "C:\Users\Public\Desktop\ClawFactory.lnk"
winget install Microsoft.PowerShell --silent ...
winget install Microsoft.VCRedist.2015+.x64 --silent ...
```

then, from `pre-sysprep-cleanup.ps1`:

```powershell
Remove-Item "C:\Windows\Panther" -Recurse -Force
Stop-Service wuauserv -Force
Set-Service wuauserv -StartupType Disabled
Get-AppxPackage -AllUsers | ? { -not $_.NonRemovable } | Remove-AppxPackage -AllUsers
```

then `sysprep.exe /generalize /shutdown /oobe /quiet /mode:vm`, deallocate, generalize,
capture.

**What the bake log actually confirms**, as opposed to what the script attempts
(`validation-runs/phase1-bake-20260506-144034/log.md`):

| Step | Confirmed by the log? |
|---|---|
| `Microsoft-Windows-Subsystem-Linux` = Enabled | **YES** — `PASS: WSL=Enabled VMP=Enabled` |
| `VirtualMachinePlatform` = Enabled | **YES** — same line |
| **A reboot after enabling both features** | **YES** — `## Task 5 — Reboot / PASS: VM running confirmed within 15s of restart` |
| `wuauserv` stopped and disabled | **YES** — `PRE_SYSPREP_CLEANUP_DONE (Panther cleaned, wuauserv disabled, AppX removed)` |
| AppX packages removed | **YES** — same line |
| Three Defender exclusions | **NO** — attempted; the log records no result, and no later run has read them back |
| PowerShell 7 / VCRedist via winget | **NO — and they were NOT installed.** `Note: winget not available in RunCommand context (non-fatal; WSL/VMP are the gate)` |
| A working WSL engine | **NO — and it was NOT present.** See §2's "Before" block, measured on a VM built from this image: `wsl --version` returned *"Windows Subsystem for Linux must be updated"*, and no WSL MSI product or appx was installed |

**Therefore a box built on `clawfactory-win11-baseline` cannot measure:**

1. **`Enable-WindowsFeaturesForWsl` / any feature-enablement path.** Both features are
   already `Enabled`, so nothing in the installer has to enable them.
2. **Any pending-reboot state arising from feature enablement.** The bake enabled them
   *and then rebooted* (Task 5) before capture. `VirtualMachinePlatform` on this image
   reads `Enabled`, never `EnablePending`. **This is the exact state the first external
   install failed in, and it has been unreachable on this fleet since 2026-05-06.**
3. **A pending reboot arising from Windows Update.** `wuauserv` is stopped and disabled.
   `HKLM:\...\WindowsUpdate\Auto Update\RebootRequired` cannot be set by the update
   service on these boxes, which matters because that key is one of the two secondary
   signals the D1 fix design proposes to read.
4. **Any interaction between Windows Defender and the install**, if the three
   `Add-MpPreference` exclusions took effect and survived sysprep. `C:\Program Files\ClawFactory`,
   `C:\ProgramData\ClawFactory` and the public desktop `.lnk` are the installer's three
   principal write targets, and a real user's machine has none of them excluded. **Whether
   they survived is unknown**: never read back, on any box, in any run.

   > **CORRECTED 2026-08-31 by measurement on `cfv-187`, a box provisioned from
   > `clawfactory-win11-baseline-v2`. Item 3 above is FALSE on a provisioned box.**
   > `wuauserv` reads **`Running` / `Manual`**. The bake disabled it; the
   > generalize/specialize cycle **restored it**. So the claim that
   > `HKLM:\...\WindowsUpdate\Auto Update\RebootRequired` cannot be set by the update
   > service on these boxes does not hold, and any reasoning that rested on it — including
   > the reading of which of D1's two secondary signals were reachable on this fleet — is
   > unsupported. The item is kept above rather than deleted. **What the boxes still cannot
   > measure is item 2's pending-reboot state, and that is unaffected by this correction.**

   > **CORRECTED 2026-08-31 by measurement on `cfv-187`. Item 4's "whether they survived is
   > unknown" is now answered: THEY SURVIVED.** All three `Add-MpPreference` exclusions are
   > present on a box provisioned from `-v2` today — `C:\Program Files\ClawFactory`,
   > `C:\ProgramData\ClawFactory`, and `C:\Users\Public\Desktop\ClawFactory.lnk`. The
   > consequence is larger than the correction and is recorded as an open measurement in §3.
5. **Anything that depends on the Store appx surface**, which the pre-sysprep cleanup
   strips wholesale.

---

## 2. `clawfactory-win11-baseline-v2` — baked 2026-06-10

**Azure metadata** (`az image show`, read 2026-08-30): managed image, `hyperVGeneration = V2`,
`osState = Generalized`, captured from a VM named **`cfv-133`**, **no tags**.

**Record:** `REPORT.md` at the repository root, and commit `962a189`
(*"ops: baseline-v2 rebake PASS — WSL 2.7.8 baked into clawfactory-win11-baseline-v2"*,
2026-06-10).

**Base:** `cfv-133` was provisioned **from `clawfactory-win11-baseline`**, not from a
marketplace image. So `-v2` inherits everything in §1 and adds to it.

**State measured on `cfv-133` before the rebake step** (`REPORT.md`, "Before"):

- `wsl --version` → *"Windows Subsystem for Linux must be updated to the latest version to proceed."* (inbox System32 stub only)
- `wsl --status` → *"The Windows Subsystem for Linux is not installed."*
- No `Microsoft.WSL` / WSL MSI product; no WSL or Linux appx present.
- **Optional features `Microsoft-Windows-Subsystem-Linux` and `VirtualMachinePlatform` = `Enabled`.**

That last line is the load-bearing one. It is the direct measurement that §1's claims 1 and 2
rest on, taken on a real box from the v1 image.

**The one step `-v2` adds:**

```
msiexec /i wsl.2.7.8.0.x64.msi /quiet /norestart   →  exit 0, no reboot required
```

MSI downloaded from `https://github.com/microsoft/WSL/releases/download/2.7.8/wsl.2.7.8.0.x64.msi`
(258,678,784 bytes). Verified after install: `wsl --version` = 2.7.8.0, kernel 6.18.33.1-1,
Windows 10.0.26100.8246, and `wsl --update` → *"The most recent version … is already
installed."* Then the same `pre-sysprep-cleanup.ps1` + `sysprep.ps1` recipe, verbatim.

**Therefore a box built on `clawfactory-win11-baseline-v2` cannot measure, in addition to
everything in §1:**

6. **`Update-WslEngine` doing any work.** `wsl --update` on these boxes reports "already
   installed" and exits 0 without touching the engine or any optional feature. On a real
   first-run machine it is the call that installs the engine, enables
   `VirtualMachinePlatform` as a side effect, and prints the reboot sentence — the whole
   sequence that produced the external failure.
7. **Any engine-version acquisition path at all**, including the failure modes of the
   Store/elevation route that made the MSI fallback necessary in the first place.
8. **No distro is present** on either image, so `wsl --import` of the bundled rootfs *is*
   exercised. This is one of the few first-run steps the fleet does cover, and it should be
   said, because it is the step that failed first on the external machine.

---

## 3. What neither image can be, and what that costs

Neither image can ever be a Windows machine that has never had WSL. Both have both optional
features `Enabled` and both have taken the reboot that follows. `-v2` additionally has the
engine.

> **CONFIRMED 2026-08-31 by direct measurement, not inference.** `VirtualMachinePlatform`
> reads **`Enabled`** on a box provisioned from `clawfactory-win11-baseline-v2` **today**
> (`cfv-187`, 2026-08-30). The claim above no longer rests only on the June 2026 reading of
> `cfv-133` and the May bake script's own `RESULT:` line. And the matching negative was taken
> in the same run: `VirtualMachinePlatform` reads **`Disabled`** on a stock
> `MicrosoftWindowsDesktop:windows-11:win11-24h2-pro` box (`cfv-186`) — `PR.CTL0`, the first
> time that control has fired on this fleet since 2026-05-06.

The regression rig written on 2026-08-30 —
`validation/interim-v145-pendingreboot.ps1` — is built on this fact and refuses to run
against a baked image: its `PR.CTL0` row asserts `VirtualMachinePlatform` reads `Disabled`
at start, and voids the run if it does not. It specifies
`MicrosoftWindowsDesktop:windows-11:win11-24h2-pro` for exactly that reason.

**Unmeasured and owed.** Nothing in this repository has ever read back, from either image:

- whether the three Defender exclusions survived sysprep;
- whether `wuauserv` is still disabled on a provisioned box (it is disabled at capture; a
  generalize/specialize cycle may or may not restore it);
- whether `VirtualMachinePlatform` reads `Enabled` on a box provisioned from either image
  **today**. The claim rests on one measurement on `cfv-133` in June 2026 and on the bake
  script's own `RESULT:` line in May. Both are strong; neither is current.

**Two of the three above were settled on 2026-08-30 and one was strengthened; the list is
kept so the method is visible.** Read back on `cfv-187` before the installer was copied,
exactly as the paragraph below suggests: the three Defender exclusions **survived**;
`wuauserv` is **`Running` / `Manual`**, not disabled; and `VirtualMachinePlatform` reads
**`Enabled`** on a box provisioned today. See the corrections in §1 and §2.

**And one open measurement the file did not ask for, found by the same dispatch. It is the
same class as the WSL drift above and is recorded here for that reason.**

**OM-B1. Nothing has ever measured what Windows Defender does to a real ClawFactory install.**

The baked fleet carries three Defender exclusions, added by the 2026-05-06 bake and confirmed
on 2026-08-30 to have survived sysprep:

```
C:\Program Files\ClawFactory
C:\ProgramData\ClawFactory
C:\Users\Public\Desktop\ClawFactory.lnk
```

Those are the installer's three principal write targets: its program directory, its data and
log directory, and the desktop shortcut it creates. **A stock box has none.** Measured
directly on `cfv-186` in the same run: zero exclusions.

So **every validation this project has run since 2026-05-06 — four months, and every box on
both images — has installed with antivirus told in advance to ignore exactly the paths the
installer writes to.** No run has ever observed Defender's real-time scanning, its
reputation checks, or its behavioural blocking act on this product, and no run could have.
A real user's machine has all of them.

This is not a claim that Defender breaks the install. It is the statement that **nobody
knows**, that nothing in the transcripts of four months distinguishes "Defender is fine with
this" from "Defender was never asked", and that the boxes went on passing while the question
was gone. That is entry 14.1's mechanism, on a different subject, found the same day.

**What it would need.** A stock box, no exclusions, Defender left exactly as Windows ships
it, and a full install run to completion — with, at minimum, `Get-MpComputerStatus` and the
`Microsoft-Windows-Windows Defender/Operational` event log read after the install, and the
elapsed install time compared against the excluded fleet's. It is one box, and it is the
only measurement here that cannot be taken on a baked image at all. **Take it before the
next release that changes what the installer writes**, and note that the bundled rootfs
tarball is ~258 MB of compressed archive being unpacked into a write target, which is the
shape of a workload real-time scanning is most likely to slow.

**Not a v1.4.5 blocker**, and recorded rather than actioned here: v1.4.5 changes no write
target and no installed path. It is owed by the next full validation cycle.


The first box of the next cycle can settle all three in one `az vm run-command` before the
installer is copied, and should.

---

## 4. Correction to `docs/FAILURE_CATALOGUE.md` 13.1

Entry 13.1, written 2026-08-30, says the four v1.4.4 boxes ran
`clawfactory-win11-baseline-v2`, *"which was deliberately baked with the WSL engine already
installed and virtualization already live, precisely so that validation runs would stop
tripping over the WSL engine version"*, and the close-out of the same day concludes that
*"the fix for the old bug created the new one, on the one path nothing measured after that."*

**The fleet claim is right. The attribution is wrong, and it is wrong in the direction that
makes the finding larger.**

`clawfactory-win11-baseline` — the *original*, 2026-05-06, four and a half weeks before
`-v2` existed — already enabled `VirtualMachinePlatform`, already rebooted, and already
disabled Windows Update. The June rebake added the WSL **engine** and nothing else relevant.
So:

- The pending-reboot state has been unreachable since **2026-05-06**, not since 2026-06-10.
- It is unreachable on **both** images. Falling back to `-v1` would not have caught it.
- `-v2` did not create the blind spot. It removed the last remaining first-run WSL step from
  a fleet that had already lost the feature-enablement step, which is why the run of
  2026-05-21 could still stumble into the reboot-and-resume branch (via `wsl --install`
  exiting non-zero) and no run after 2026-06-10 could.

The general lesson survives intact and gets sharper: **the blindness arrived with the first
bake, not with the rebake that removed the friction.** Any image built by running install
steps and then generalizing has this property from its first version. It is not a thing that
creeps in later.
