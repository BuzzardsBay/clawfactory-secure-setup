# ClawFactory v1.0.31 — Azure validation report

**Date (UTC):** 2026-05-26 20:15 (install kicked off 20:01, failure recorded 20:02:10)
**VM:** cfv-131 — Standard_D2s_v5 — westus2
**Image:** `clawfactory-win11-baseline` (managed image)
**Installer:** `ClawFactory-Secure-Setup.exe` v1.0.31 (SHA-256 `0561E76D32996B7E21B0E2374DAC2745B246DD8333513AFCF8D7AD9F158EFFC0`)
**License key:** `CF-TEST-TEST-TEST-TEST` (preloaded in license DB, `max_machines=10`)
**Install flags:** `/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG /PROVIDER=claude /LICENSE=CF-TEST-TEST-TEST-TEST`

## Overall: FAIL

Headless install aborted at the **resume-after-reboot** step. Smoke test and downstream
checks were never reached.

## Results by phase

| Phase | Result | Notes |
|---|---|---|
| T0 Cleanup of stale RG resources | PASS | RG had no leftover VMs/disks/NICs/IPs from prior cycles. |
| T1 Upload installer to blob + 4h SAS | PASS | Uploaded as `ClawFactory-Secure-Setup-1.0.31.exe`. |
| T2 Provision cfv-131 | PASS | Standard_D2s_v5, Security `Standard`, from baseline image, ~3 min. Public IP `4.246.64.115`. |
| T3 Download + silent install | **FAIL** | Pre-reboot path completed; post-reboot Resume path aborted (see Failure analysis). |
| T4 Smoke test | NOT RUN | T3 failed; per spec, do not proceed past T4 on failure (and T3 itself never produced a usable install). |
| T5 License activation check | NOT RUN | |
| T6 Idle stability (5 min) | NOT RUN | |
| T7 chatCompletions check | NOT RUN | |
| T8 Report | PASS (this file) | |
| T9 VM cleanup | PASS | cfv-131 and OS disk deleted. |
| T10 Tag + GitHub release | **SKIPPED** | Spec: only on overall PASS. v1.0.31 is NOT tagged or released. |

## Failure analysis

### Symptom

After `wsl --install` returned exit 1 ("elevation required or reboot pending"), setup.ps1
took the documented reboot-and-resume path: registered the `ClawFactory-Resume` scheduled
task (AtStartup, SYSTEM), wrote `.wslconfig`, and rebooted. The Resume task fired ~56 s
after boot, launched the installer with `/resume`, and the resume entrypoint immediately
aborted with:

```
[ERROR] FATAL: -Resume passed but resume flag at C:\ProgramData\ClawFactory\resume-after-restart.flag
is missing or unreadable. Refusing to continue with a guessed provider (would silently install
Grok config on what may be a Claude install). To recover: delete C:\ProgramData\ClawFactory\
checkpoint.json and re-run the installer from scratch.
```

`install-result.txt` matches: `INSTALLER_DONE=failure reason=Resume flag not found...`

### Evidence

State of `C:\ProgramData\ClawFactory\` post-failure:

| File | Size | LastWriteTime | Present? |
|---|---|---|---|
| `checkpoint.json` | 142 B | 20:01:13 | yes (`completedSteps: [Preflight, EnsureWsl]`) |
| `resume-task.ps1` | 436 B | 20:01:10 | yes |
| `.wslconfig` | n/a | 20:01:13 | yes (at `C:\Windows\system32\config\systemprofile\.wslconfig`) |
| `install.log` | 2422 B | 20:02:10 | yes |
| `install-result.txt` | 150 B | 20:02:10 | yes |
| **`resume-after-restart.flag`** | — | — | **MISSING** |

Uninstall entry **was** written (`ClawFactory Secure Setup version 1.0.31 v1.0.31`), so Inno's
[Files]/[Registry] sections ran, but the post-install script aborted in setup.ps1 on the resume side.

### Scope

The bug is in setup.ps1's reboot-and-resume plumbing, **not** in any code path the v1.0.31
diff touched. v1.0.31 changes are scoped to:

- `Step-InstallOpenClaw` (Step 8) — replaced the `$OpenClawInstallSha256` hash-pin check
  with at-install-time hash logging + `installShHash` checkpoint write. Step 8 runs **after**
  Step 2 (WSL install). The Step 8 path was never reached on this run.
- `$InstallerVersion = '1.0.31'`, related top-of-file comments, and a stale comment fix on
  line 1435.
- `.iss`: AppVersion bump + Pascal comment-syntax fix (line 323 `{...}` → `(...)`).

The resume-flag write path was last meaningfully changed in **v1.0.28** (commit `b84ff56`,
"wsl --update preflight + resume-flag hardening") and last validated on Azure with a
manual-RDP fallback on cfv-130. v1.0.30 (license-wizard page) shipped without an Azure
validation cycle; v1.0.31 is the first headless Azure run since v1.0.28. The regression
may have been latent since v1.0.30 or is environmental.

### Suggested next steps (out of scope for this report)

1. Read the section of setup.ps1 that should write `resume-after-restart.flag` between the
   "Scheduled Task ... registered" log line and the "Created .wslconfig" log line — that's
   where the flag write is expected. Trace why it's not running (caught exception silently?
   wrong order? wrong path? recently refactored?).
2. Consider whether the v1.0.30 license-wizard work moved the flag-write block.
3. Re-validate v1.0.31 once the resume-flag write is restored.

## Diagnostic artifacts

Full install.log and result file captured to
`C:\Users\bmcki\AppData\Local\Temp\cfv131_diag.txt` (3402 bytes). Excerpts in the
"Symptom" section above.

## Cleanup

cfv-131 + OS disk + NIC + public IP deleted (`--os-disk-delete-option Delete`,
`--nic-delete-option Delete` set at create time). Blob `ClawFactory-Secure-Setup-1.0.31.exe`
in `clawfactoryvalc467/installers` retained — re-usable for the next attempt without
re-uploading.

## Release status

**v1.0.31 is NOT tagged and NOT released.** Per spec, T10 is gated on overall PASS.
