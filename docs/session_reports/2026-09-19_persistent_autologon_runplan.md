# Persistent auto-logon for the validation runner — run plan

**Recorded 2026-09-19, BEFORE `az vm create`, and committed before OM-1 is taken.** Job:
`CC_PersistentAutoLogon_ValidationRunner_v1.md`, follow-on to card #259.

## The box

One box, `cfv-193` (the next free number after `cfv-192`), `Standard_D2s_v4`, image
`clawfactory-win11-baseline-v2` (the baked image, chosen because it carries the WSL engine and
this job measures a transport, not an install step), resource group `clawfactory-validation`,
created `--nsg-rule NONE`. **No RDP rule at any point.** Estimated 2.5–3 h ≈ **$0.60**.

Provisioned by `validation/cfv-provision.ps1`, which generates the admin password once,
uses it for `az vm create --admin-password` and hands the same value to
`validation/cfv-arm-autologon.ps1` as a run-command parameter. It is never printed, never
written to a file, and only its length is ever reported.

## Sequence

| # | Step | Proves |
|---|---|---|
| 1 | provision + stage + arm auto-logon + arm the two runner tasks | the one-password path; `ValidateCredentials` says the registry value is the account's |
| 2 | **reboot 1**, wait for BOTH runners, no logon by a person | the WSL runner returns on its own |
| 3 | WSL job `w1` through the runner (context + `wsl --status` + must-fail control) | 2.1, first reboot |
| 4 | install the published v1.4.5 through the WSL runner (digest-gated) | the runner carries real WSL work; gives OM-1 a subject |
| 5 | **reboot 2**, then WSL job `w2` (adds a real distro exec) | 2.1, second reboot |
| 6 | **disable** auto-logon (`AutoAdminLogon=0`), **reboot 3**, drop a WSL job, expect it to visibly NOT run; a Windows-side job on the SYSTEM queue must still run | 2.2 — the fix matters, and the two mechanisms do not mask each other |
| 7 | **re-enable**, **reboot 4**; the SAME queued job must now run | 2.2 — restored |
| 8 | **OM-1, last** | 2.3 |
| 9 | teardown, NIC first, unfiltered residual | ledger |

## OM-1: ONE-TIME SUSPENSION OF HAZARD RULE #5, recorded here before it is taken

`docs/VALIDATION_PREAMBLE.md` OM-1 says the measurement needs *"an explicit one-time suspension
of hazard rule #5, recorded as such in the run plan before it is taken — not decided at the
keyboard."* **This is that record.**

- **Suspended:** hazard rule #5 (*"never open the dashboard at 127.0.0.1:8787"*), **for this one
  measurement, on `cfv-193` only.** It is reinstated the moment the measurement ends.
- **Authority:** the job card `CC_PersistentAutoLogon_ValidationRunner_v1.md` TASK 2.3 orders the
  measurement explicitly ("This is the first time this check has ever run").
- **Conditions from OM-1, all honoured:**
  1. taken **last**, on a box being torn down anyway, after every other row has its verdict;
  2. **positive control** — the gateway must answer `/status` 200 immediately BEFORE the click
     and again AFTER it, **from a path that is not the browser** (`curl` as `clawuser` inside
     the distro). Without the "after", a wedge and a clean result look identical;
  3. the screen is **captured**, not described;
  4. **not read as a verdict on whether the shortcut should ship** (V1_5_BACKLOG item 5 stands).
- **Added by this job:** a second, pre-click screenshot as a control that the capture path sees
  the desktop at all (a black frame after the click would otherwise be uninterpretable), and
  the shortcut is exercised by running **its own `[Icons]` command line**, not a URL typed by hand.

## What this job does NOT touch

`setup.ps1`, `resources/`, the `.iss`, anything bundled; no tag, no release, no signing, no
ledger row. No RDP, no `mstsc`, no computer-use on the operator's desktop.
