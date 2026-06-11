# ClawFactory Installer — Lessons Learned

Permanent, cross-version gotchas for the Inno Setup installer (`ClawFactory-Secure-Setup.iss`)
and `setup.ps1`. Add an entry whenever a defect teaches a rule that should never be re-learned.

---

## L1 — Inno expands `[UninstallRun]` / `[Run]` `Parameters` constants at INSTALL time

**Discovered:** v1.0.33 Azure validation (cfv-134, 2026-06-10). The brand-new uninstaller
wiring made the installer crash during Setup with:

```
Runtime error (at 18:46):
Internal error: Cannot call "UninstallSilent" function during Setup.
```

→ fatal exception → full rollback → exit code 4. `setup.ps1` never ran (no `install.log`).

**Mechanism.** Inno Setup records `[UninstallRun]` entries into the uninstall log **during
installation**, immediately after the last file is copied. When it does, it **expands the
`{code:...}` constants in their `Parameters`/`Filename` fields right then — at INSTALL time.**
The `.iss` had:

```
[UninstallRun]
Filename: "powershell.exe"; Parameters: "... uninstall.ps1""{code:GetUninstallFlags}"; ...
```

and `GetUninstallFlags` called `UninstallSilent`, which Inno permits **only during uninstall**.
So a function meant to run at uninstall time was invoked during Setup and threw.

**Two-part rule:**

1. **Phase validity.** Any `{code:}` function referenced from a `[Run]` or `[UninstallRun]`
   `Parameters`/`Filename`/`WorkingDir` constant runs at **INSTALL** time. It must not call
   functions that are only valid in the other phase:
   - Uninstall-only (illegal during Setup): `UninstallSilent`, `UninstallProgressForm`, and
     reading the *uninstaller's* `ParamStr()` (the install-time `ParamStr()` is the
     *installer's* command line — it will NOT contain `/REMOVEALL=…` or other uninstall args).
   - Install-only analog that IS valid in `[Run]`: `WizardSilent()`.
2. **Even without the crash, the data is wrong.** Because the string is baked at install time,
   it can never reflect uninstall-time inputs. The old `GetUninstallFlags` would have baked an
   empty flag string anyway, so `/SILENT` and `/REMOVEALL=…` would have silently failed to
   reach `uninstall.ps1`.

**Correct pattern (shipped in v1.0.34).** Invoke the uninstaller helper from
`CurUninstallStepChanged(usUninstall)` in `[Code]`, where `UninstallSilent` and the
uninstaller's `ParamStr()` are valid, and which fires **before** Inno removes files (so
`{app}\resources\uninstall.ps1` still exists):

```pascal
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var Flags, AppDir: string; i, rc: Integer;
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

**Pre-build checklist (do this before every ISCC compile):** audit EVERY `{code:}` reference in
`[Run]`, `[UninstallRun]`, `[Files]`, and `[Icons]` for phase-validity. A function reachable
from a `[Run]`/`[UninstallRun]` parameter constant must only call code valid in the **install**
phase. If you need uninstall-time logic, it belongs in `CurUninstallStepChanged`, not in a
`{code:}` constant.

**Why pre-sim missed it:** static review confirmed every flag name, path, and wiring was
*correct for uninstall* — but the bug was an evaluation-**timing** violation that only manifests
at runtime. Flag/path correctness is necessary but not sufficient; phase-timing is a separate
axis that must be checked explicitly.
