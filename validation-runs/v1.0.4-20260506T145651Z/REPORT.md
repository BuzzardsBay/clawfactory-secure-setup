# ClawFactory v1.0.4 Validation Report

- Timestamp (UTC): 2026-05-06T14:57:09Z (run start) — 2026-05-06T15:14:xx (idle done)
- Run dir: validation-runs/v1.0.4-20260506T145651Z/
- Commit tested: 7a59e99
- VM: ClawTest, reverted from snapshot Clean-Win11

## Verdict

**FAIL**

The installer process exited (non-TIMEOUT) but produced no install
artifacts and no log files. Smoke test could not run; idle gateway
probes both failed.

## Install

- Duration: 124s wall clock
- Exit code: 34 (Inno Setup does not document this code; treated as
  internal failure)
- First failure point: cannot be determined from logs — Inno Setup's
  log file at `C:\install-stdout.log` was never created, and
  `C:\ProgramData\ClawFactory\install.log` was also never created.
  No `Setup Log*.txt` files exist in any guest TEMP directory.
  guestcontrol stdout and stderr from the installer process were both
  empty (consistent with `/SILENT /SUPPRESSMSGBOXES`).

  Filesystem state on guest after the installer exited:
  - `C:\Program Files\ClawFactory`            : MISSING
  - `C:\ProgramData\ClawFactory`              : MISSING
  - `C:\install-stdout.log`                   : MISSING
  - `C:\Users\clawtest\AppData\Local\Temp\Setup Log*.txt` : NONE
  - `is-*.tmp` directories from this run      : NONE
    (one stale `is-TPHCM9BGAX-uninstall.tmp` from a prior pre-snapshot
    run was found, dated 2026-05-06 07:47:46 — predates this run)

  No 30-line install.log excerpt is available because no install.log
  was written (see Notes for the most likely root cause).

## Smoke test

Did not execute — `smoke-test.ps1` not found at any of the three
expected paths:

- `C:\Program Files\ClawFactory\resources\smoke-test.ps1` : MISSING
- `C:\Program Files\ClawFactory\smoke-test.ps1`           : MISSING
- `C:\ProgramData\ClawFactory\smoke-test.ps1`             : MISSING

X/N: 0/0 checks passed (smoke harness never reached).

## Idle test

- PROBE1: FAIL - Unable to connect to the remote server
- PROBE2: FAIL - Unable to connect to the remote server (after 300s sleep)
- Gateway alive after 5 min: **no**

(Failure expected and consistent with the install never completing —
gateway components were not installed on the guest.)

## Notes

- **Most likely root cause: silent UAC elevation denial.** The Inno
  Setup binary requires admin elevation. When launched via
  `VBoxManage guestcontrol run` under `clawtest` (a split-token admin
  with no interactive desktop session), the UAC consent prompt cannot
  be displayed and is auto-denied. This matches the observed pattern:
  no log file ever created, no temp dir ever created, process exited
  in 124s with a non-zero code, zero stdout/stderr captured. Inno
  Setup's own initialization (which writes the log file) never ran in
  the elevated child because elevation never happened. This is
  consistent with the warning in the spec about UAC behavior under
  guestcontrol; per the spec this is reported, not worked around.
- Exit code 34 is not a documented Inno Setup return value. It may be
  produced by the parent (unelevated) shim that Inno emits when its
  elevated child fails to start.

- **Anomaly: GA readiness check.** The spec's Task 2 readiness check
  (`VBoxManage guestproperty get ClawTest /VirtualBox/GuestAdd/Version`
  returning a version string) returned `No value set!` for the full
  180-second poll window. Independent diagnostic via
  `VBoxManage showvminfo ClawTest --machinereadable` confirmed
  `GuestAdditionsRunLevel=3` and
  `GuestAdditionsVersion="7.2.8 r173730"` at the same moment, and the
  guestproperty enumeration listed all GA component properties. GA
  was in fact fully ready; the specific `/VirtualBox/GuestAdd/Version`
  property is simply not populated on this VBox 7.2.8 build.
  The run was allowed to proceed on this basis (subsequent
  guestcontrol calls all succeeded — copyto, stat, run — confirming
  GA was operational). Recommend updating the spec's readiness check
  to use `showvminfo ... GuestAdditionsRunLevel` or
  `/VirtualBox/GuestAdd/Components/VBoxControl.exe`.

- Pre-existing run logs (cleanup-20260506-083948.log,
  snapshot-20260506-085530.log) were not touched.
- Cleanup, snapshot artifacts, repo files: untouched.

## Files in this run dir

- host-driver.log         (host-side VBoxManage call log)
- install-start.txt       (epoch start of install)
- install-rc.txt          (= 34)
- install-duration.txt    (= 124)
- install-run-stdout.txt  (empty)
- install-run-stderr.txt  (empty)
- install.log             (consolidated install summary; no Inno log
                           was available)
- smoke-test.log          (smoke-test.ps1 not found)
- idle-test.log           (PROBE1 + PROBE2 results)
- diag-hunt.ps1, diag-hunt.out  (post-install filesystem &
                                  event-log diagnostic)
- smoke-probe.ps1, idle-probe.ps1  (probe scripts)
