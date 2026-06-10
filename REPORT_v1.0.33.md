# ClawFactory v1.0.33 — Azure validation report (INSTALL + UNINSTALL VERIFICATION)

**Date (UTC):** 2026-06-10
**VM:** cfv-134 — Standard_D2s_v4 — westus2 — public IP `20.114.13.227`
**Image:** `clawfactory-win11-baseline-v2` (Gen V2, Generalized, WSL 2.7.8.0 baked in)
**Installer:** `ClawFactory-Secure-Setup.exe` v1.0.33, commit `381047b`
  - size `340541201` bytes — **verified, exact match**
  - sha256 `ADEB29688D8AB247F80EB675D1A59CF5240EBA83E7113582E9620820DECD9AEC` — **verified, exact match** (locally AND re-hashed on the VM after download)
**License key:** `CF-TEST-TEST-TEST-TEST`
**Install flags:** `/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG /PROVIDER=claude /LICENSE=CF-TEST-TEST-TEST-TEST`

## Overall: **FAIL**

The install aborts with a **fatal Inno Setup exception during the install process** and rolls
itself back completely (exit code 4). The failure is a **code defect in the brand-new v1.0.33
uninstaller wiring** (`.iss` `[UninstallRun]` + `GetUninstallFlags`), not an environmental
issue. setup.ps1 never runs, so no `install.log` / `INSTALLER_DONE` marker is ever produced.
Tasks 5–9 (smoke, idle, keep-alive, state files, uninstall) could not be reached because
nothing was installed.

This is a hard product bug: **the v1.0.33 installer cannot complete on any machine.** The
v1.0.33 uninstaller feature had never been through a *completed* install before this cycle
(every prior cycle since v1.0.26 failed upstream or installed via RDP), so the defect was
latent until the first true end-to-end install attempt — which is exactly what this run is.

## Root cause

`ClawFactory-Secure-Setup.iss` invokes the uninstaller via `[UninstallRun]`:

```
[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "... -File ""{app}\resources\uninstall.ps1""{code:GetUninstallFlags}"; ...
```

and `GetUninstallFlags` (`.iss` line ~238) does:

```pascal
function GetUninstallFlags(Param: string): string;
...
  if UninstallSilent then          <-- line 245
    Flags := ' -Silent';
  for i := 1 to ParamCount do ...  <-- scans for /REMOVEALL=1 etc.
```

**Inno expands `{code:...}` constants in `[UninstallRun]` `Parameters` at INSTALL time** (when
it records the uninstall-run data into the uninstall log, immediately after the last file —
`setup.ps1` — is copied). Evaluating `{code:GetUninstallFlags}` therefore calls
`GetUninstallFlags` *during Setup*, which calls `UninstallSilent` — a function Inno permits
**only during uninstall**. The result is a fatal runtime error:

```
2026-06-10 23:45:13.733   Starting the installation process.
2026-06-10 23:45:14.348   Dest filename: C:\Program Files\ClawFactory\setup.ps1
2026-06-10 23:45:28.931   Fatal exception during installation process (Exception):
                          Runtime error (at 18:46):
                          Internal error: Cannot call "UninstallSilent" function during Setup.
2026-06-10 23:45:28.935   Starting the uninstallation process.        <-- rollback
2026-06-10 23:45:30.589   Uninstallation process succeeded.
2026-06-10 23:45:32.189   Log closed.
```

(Inno Setup 6.7.1; install ran elevated as `cfv-134\clawadmin` in an interactive auto-logon
session — the correct context; the crash is purely the Pascal defect.)

### Deeper flaw (the fix must address this, not just the crash)

Because the `{code:GetUninstallFlags}` string is **baked at install time**, the function cannot
read uninstall-time state *at all*:
- `UninstallSilent` is invalid during Setup (→ the crash above).
- `ParamStr()` at install time returns the **installer's** command line, which never contains
  `/REMOVEALL=0|1` (those are uninstaller args). So even if the crash were suppressed, the
  baked flag string would always be empty — `/SILENT` and `/REMOVEALL=…` would silently fail
  to propagate to `uninstall.ps1`, breaking the documented silent-uninstall contract.

The flag-computation must happen at **uninstall** time, not install time.

### Recommended fix (v1.0.34)

Remove the `[UninstallRun]` entry and invoke `uninstall.ps1` from
`CurUninstallStepChanged(usUninstall)` in `[Code]`, where `UninstallSilent` and the
uninstaller's own `ParamStr()` (carrying `/REMOVEALL=…`) are valid:

```pascal
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Flags, AppDir: string;
  i, rc: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    Flags := '';
    if UninstallSilent then Flags := Flags + ' -Silent';
    for i := 1 to ParamCount do
    begin
      if CompareText(ParamStr(i), '/REMOVEALL=1') = 0 then Flags := Flags + ' -RemoveAll'
      else if CompareText(ParamStr(i), '/REMOVEALL=0') = 0 then Flags := Flags + ' -KeepLinuxEnvironment';
    end;
    AppDir := ExpandConstant('{app}');
    Exec('powershell.exe',
      '-NoProfile -ExecutionPolicy Bypass -File "' + AppDir + '\resources\uninstall.ps1"' + Flags,
      '', SW_HIDE, ewWaitUntilTerminated, rc);
  end;
end;
```

Delete `GetUninstallFlags` and the `[UninstallRun]` block. After the fix the **install** path
needs re-validation **and** the previously-unreachable **uninstall** path (Task 9) must be
validated for the first time. NB: the `uninstall.ps1` script itself was statically reviewed and
looks correct (see Preflight) — the defect is solely in how Inno wires/invokes it.

## Results by task

| Task | Result | Notes |
|---|---|---|
| 0 Cleanup + live state | PASS | Subscription **Enabled** (PayAsYouGo) verified live via `az rest`. Deleted one orphaned leftover NSG `cfv-133NSG` from the bake. RG otherwise clean. |
| 1 Preflight | PASS | Installer size + sha256 exact match. `.iss` flags + uninstaller wiring read and confirmed (`/PROVIDER=claude`→Anthropic, license→HKLM, `[UninstallRun]`→`uninstall.ps1`, `/REMOVEALL=1`→`-RemoveAll`). **Static read did not catch the install-time `{code:}` evaluation gotcha** — see "Pre-sim gap" below. |
| 2 Upload | PASS | Uploaded as `ClawFactory-Secure-Setup-1.0.33.exe` (340,541,201 B), 8h read SAS, HEAD-verified. |
| 3 Provision cfv-134 | PASS | `Standard_D2s_v4`, `--security-type Standard`, non-zonal, subnet `bake-vmSubnet`, `--nsg-rule NONE` + Standard PIP. From `clawfactory-win11-baseline-v2`. Agent ready, auto-logon configured, wrapper task registered. |
| 4 Install (user context) | **FAIL** | Auto-logon worked (`cfv-134\clawadmin` logged in), wrapper fired, installer downloaded (on-VM sha256 exact match) and launched **elevated in the interactive session** — then Inno aborted with the `UninstallSilent`-during-Setup fatal exception and rolled back. exit code 4. No `install.log`. |
| 5 Collect + smoke | NOT RUN | Nothing installed. |
| 6 Idle stability | NOT RUN | Nothing installed. |
| 7 Hidden keep-alive verify | NOT RUN | Nothing installed. |
| 8 State files | NOT RUN | Nothing installed. |
| 9 Silent uninstall + verify clean | NOT RUN | Nothing installed (and the uninstaller wiring is the bug). |
| 10 Report + cleanup | PASS (this file) | FAIL-path cleanup done; report written. |

## Install mechanism that DID work (for the record)

The headless user-context install harness behaved correctly — the failure is downstream of it:
- **Auto-logon** (`AutoAdminLogon=1`, `DefaultUserName=clawadmin`) brought up an interactive
  session after reboot — confirmed `interactive-user=[cfv-134\clawadmin]`.
- A **logon-triggered scheduled task** (`CFV-Install-Wrapper`, clawadmin / Interactive /
  HighestAvailable) ran the installer **in the interactive elevated session** (not SYSTEM), so
  the v1.0.26–v1.0.28 "Inno init / WSL-under-SYSTEM" blockers were avoided by design.
- The installer **downloaded fully and its on-VM SHA-256 matched the pinned hash exactly**
  (`ADEB29688…DECD9AEC`) — no transit corruption.
- Inno reached "Starting the installation process", extracted files to `C:\Program Files\
  ClawFactory\`, and crashed only at the uninstall-data-recording step. This proves the
  binary, the image, and the harness are all sound; only the `.iss` uninstall wiring is broken.

## Pre-sim gap (honest accounting)

The mandatory pre-simulation read `uninstall.ps1` and the `.iss` and confirmed every **flag
name, path, and wiring** was correct — and flagged the separate smoke check-#9 nft
false-positive risk. It did **not** catch that `{code:GetUninstallFlags}` in `[UninstallRun]`
`Parameters` is evaluated at *install* time, making the `UninstallSilent` call illegal. This is
a subtle Inno-specific evaluation-timing gotcha that only manifests at runtime. Lesson for next
time: any `{code:}` function referenced from an `[UninstallRun]`/`[Run]` `Parameters` constant
must be checked for calls that are only valid in the opposite phase (UninstallSilent, uninstall
ParamStr, etc.).

## The (separately-predicted) smoke check #9 issue — not reached

Per the pre-sim, smoke check #9 ("nft clawfactory chain present", run as `clawuser`) was
predicted to FAIL as a privilege false-positive, with the binding rule that a lone #9 FAIL is
excusable only if a root-context `nft list ruleset` independently shows the chain. This was
**not reached** (install failed first), so it neither helped nor hurt this verdict. It remains
a live issue for the next cycle and should be fixed alongside the uninstaller bug — see
recommendations.

## Cleanup (FAIL path)

- VM `cfv-134` deleted; NIC `cfv-134VMNic`, PIP `cfv-134PublicIP`, NSG `cfv-134NSG` deleted.
- **OS disk preserved (per FAIL spec): `cfv-134_disk1_79145c7e4cd648549d8292f39dea478b`**
  (Unattached, westus2). NB: the install rolled back completely, so this disk holds **no
  ClawFactory artifacts** — the only forensic artifact (the Inno Setup log) was captured off
  the VM before teardown. The disk can be safely deleted; it is preserved only to honor the
  FAIL-path instruction.
- RG `clawfactory-validation` now: 2 images (`clawfactory-win11-baseline`,
  `clawfactory-win11-baseline-v2`), `bake-vmVNET/bake-vmSubnet`, storage `clawfactoryvalc467`,
  and the one preserved disk. No VMs/NICs/PIPs/NSGs.
- Blob `ClawFactory-Secure-Setup-1.0.33.exe` retained in `clawfactoryvalc467/installers` (will
  need re-upload after a rebuild).
- Diagnostic artifacts kept locally (not in repo): Inno Setup log + wrapper marker under
  `C:\Users\bmcki\AppData\Local\Temp\cfv134\`.

## Release status

**v1.0.33 is NOT tagged and NOT released.** The installer cannot complete an install. No code
signing / ship decision applies until the `.iss` uninstaller-wiring bug is fixed and a full
install **and** uninstall cycle passes.

## Recommendations for v1.0.34

1. **Fix the uninstaller invocation** (the blocker): move `uninstall.ps1` invocation from
   `[UninstallRun]` to `CurUninstallStepChanged(usUninstall)` so `UninstallSilent` and the
   uninstaller's `/REMOVEALL=…` args are read at uninstall time (code above). Remove
   `GetUninstallFlags` + the `[UninstallRun]` block.
2. **Fix smoke check #9** (`setup.ps1` Step 17 / `run-smoke.ps1`): run the nft assertion as
   `root` (or via a sudo-permitted read) instead of `clawuser`, so the post-install smoke can
   reach a true `fail=0` and the check-#9 exception rule can be retired.
3. **Re-validate the full v1.0.33→.34 install AND uninstall cycle** — Task 9 (silent uninstall
   + verify-clean) has never run end-to-end and is the headline feature of this release.
4. Re-build with ISCC (present locally), re-verify the new size/sha256, re-upload, re-run on a
   fresh cfv-135 from `clawfactory-win11-baseline-v2` (D2s_v4; DSv5 quota still 0 in westus2).
