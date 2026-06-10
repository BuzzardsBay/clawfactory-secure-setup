# ClawFactory v1.0.32 — Azure validation report

**Date (UTC):** 2026-05-26 20:43 (install kicked off 20:43:02, failure recorded 20:45:11)
**VM:** cfv-132 — Standard_D2s_v5 — westus2 — public IP `20.109.188.211`
**Image:** `clawfactory-win11-baseline` (managed image)
**Installer:** `ClawFactory-Secure-Setup.exe` v1.0.32 (SHA-256 `8E52E3335EA88E1D49F916AB6EF5DAFEA36A3E5AB37343439183CB6EB5DEBF08`)
**License key:** `CF-TEST-TEST-TEST-TEST` (preloaded in license DB, `max_machines=10`)
**Install flags:** `/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG /PROVIDER=claude /LICENSE=CF-TEST-TEST-TEST-TEST`

## Overall: FAIL — and the v1.0.32 fix verified working en route

Install progressed further than the v1.0.31 run (the resume-flag regression is fixed) but
failed at a new, unrelated point: WSL platform-level install failure on the baseline image.

## Results by phase

| Phase | Result | Notes |
|---|---|---|
| T0 RG cleanup | PASS | RG already clean post v1.0.31 teardown. |
| T1 Upload installer + 6h SAS | PASS | Uploaded as `ClawFactory-Secure-Setup-1.0.32.exe`. |
| T2 Provision cfv-132 | PASS | Standard_D2s_v5, Security `Standard`, from baseline image, ~2 min. |
| T3 Download + install (with reboot cycle) | **FAIL** | Pre-reboot OK, **resume flag now written and read correctly**, post-reboot WSL install failed. |
| T4–T7 Smoke / activation / idle / chat | NOT RUN | T3 failed. |
| T8 Report | PASS (this file) | |
| T9 VM cleanup | PASS | cfv-132 + OS disk + NIC + PIP + NSG deleted. |
| T10 Tag + GitHub release | **SKIPPED** | Gated on overall PASS. v1.0.32 NOT tagged/released. |

## v1.0.32 fix verification (the intended change)

The Step-EnsureWsl reboot path (Site B) now correctly persists the resume flag. Direct
evidence from the cfv-132 install log:

**Pre-reboot (20:43:06):**
```
[INFO] Reboot required. ClawFactory-Resume scheduled task is registered.
[INFO] Resume flag written: C:\ProgramData\ClawFactory\resume-after-restart.flag
[INFO] Silent mode: skipping restart-required dialog; rebooting now.
```

**Post-reboot (20:44:09) — resume entrypoint successfully reads the flag:**
```
[INFO] ==== ClawFactory Secure Setup - resuming after restart (provider=claude) ====
[INFO] Step 1: Preflight checks. Selected provider: Anthropic Claude.
```

The `provider=claude` field is read from the JSON written by `Save-ResumeFlag`. If the flag
were missing (v1.0.31 bug) the resume would have aborted with "resume flag is missing or
unreadable". If the flag were present but malformed (the spec-pattern `'1'` scenario the
spec deviation note called out) it would have aborted with "missing 'provider' field". Neither
fired — the v1.0.32 fix is end-to-end correct.

## New failure (T3): WSL engine on baseline image

After resume succeeded, Step-EnsureWsl re-entered the WSL install path:

```
[2026-05-26 20:44:11] [INFO] wsl --update exit code: 1
[2026-05-26 20:44:11] [INFO] wsl --update output: The requested operation requires elevation.
 | The handle is invalid.
[2026-05-26 20:44:11] [WARN] wsl --update returned 1 (continuing anyway - install may still succeed if the engine was already current).
[2026-05-26 20:44:11] [INFO] Resuming after restart - completing WSL install if needed.
[2026-05-26 20:44:11] [INFO] Installing Ubuntu from bundled rootfs (offline).
[wsl --import v2] Operation aborted
[wsl --import v2] Windows Subsystem for Linux must be updated to the latest version to proceed. You can update by running 'wsl.exe --update'.
[wsl --import v2] For more information please visit https://aka.ms/wslinstall
[2026-05-26 20:45:11] [WARN] wsl --import failed (exit 1), falling through to wsl --install.
[2026-05-26 20:45:11] [INFO] Installing Ubuntu (attempting WSL2 first).
[wsl install out] The requested operation requires elevation.
[wsl install out] The handle is invalid.
[2026-05-26 20:45:11] [ERROR] Install failed: wsl --install failed (exit 1) and no fallback signal detected.
```

### Root cause (best read)

1. **WSL engine on `clawfactory-win11-baseline` is too old.** `wsl --import v2` says
   verbatim: "Windows Subsystem for Linux must be updated to the latest version to proceed."
2. **`wsl --update` cannot elevate properly under `az vm run-command invoke` SYSTEM
   context.** Returns `The requested operation requires elevation. | The handle is invalid.`
   The "handle is invalid" message is characteristic of wsl.exe being invoked without a
   console handle — which is exactly what happens under headless SYSTEM execution.
3. v1.0.28 added the `wsl --update` preflight specifically to refresh the engine before
   install, but its non-fatal WARN ("continuing anyway") means the install proceeds even
   when the engine update silently failed. Both `wsl --import` and `wsl --install` then
   hit the same elevation/handle wall.

### Scope

**Not a v1.0.32 regression. Not caused by my source diff.** This is an environmental issue
with the baseline image's WSL stack + the headless SYSTEM execution context. v1.0.31 ran
on the same baseline image and the same failure mode would have occurred there *if* the
resume-flag bug hadn't pre-empted it. With v1.0.32's fix landed, the latent platform
issue is now exposed.

## Suggested follow-ups (separate tasks)

1. **Refresh the baseline image's WSL engine.** Bake a current `wsl.exe` /
   `Microsoft.WSL` Store package into `clawfactory-win11-baseline`. Could do this by
   running `wsl --update` interactively once via RDP (one-time, per spec this is an
   exception to "never RDP" — it's a baseline build action, not a validation step) and
   then re-Sysprep + capture.
2. **Or:** investigate whether `wsl --update` can be coaxed to work under SYSTEM. The
   "handle is invalid" hint suggests redirecting standard handles (already done via
   `Invoke-WslExe` / Process.Start with `CreateNoWindow=$true`) may not be enough.
   `wsl --update --web-download` sometimes routes around the Store-update path that
   needs interactive console.
3. **Lower-priority:** consider whether the v1.0.28 `wsl --update` WARN-and-continue
   policy should be tightened — if it's the gate to a successful install on a clean
   image, treating its failure as fatal would surface this earlier.

## Diagnostic artifacts (kept locally, not in repo)

- Full install.log: `C:\Users\bmcki\AppData\Local\Temp\cfv132_install_log.txt` (4096 bytes)
- Poller log: `C:\Users\bmcki\AppData\Local\Temp\cfv132_wait_poll.log`
- install-result.txt content (from VM):
  `INSTALLER_DONE=failure reason=wsl --install failed (exit 1) and no fallback signal detected.`

## Cleanup

cfv-132 + OS disk + NIC + public IP + NSG deleted. Blob `ClawFactory-Secure-Setup-1.0.32.exe`
and `cfv132_install.ps1` retained in `clawfactoryvalc467/installers`.

## Release status

**v1.0.32 is NOT tagged and NOT released.** Code change in v1.0.32 (resume-flag fix at
Site B) is verified working in this run, but the headless install cannot complete
end-to-end on the current baseline image. The next iteration's blocker is the baseline
image's WSL engine, not setup.ps1.
