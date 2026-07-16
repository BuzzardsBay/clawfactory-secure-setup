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

---

## L2 — `az vm run-command --scripts` mangles multi-line strings

**Discovered:** cfv-0715 clean-install validation (2026-07-15).

An inline multi-line PowerShell string passed to `--scripts` arrives on the VM
**corrupted**:

```
+ if (Test-Path C:\cfv\setup.exe) {
+                                 ~
Missing closing '}' in statement block or type definition.
```

Worse, a mangled script can run *partially* and return **empty stdout** — which
reads as "the script did nothing" rather than "the script was corrupted", sending
you diagnosing the wrong layer.

**Rule:** always pass `--scripts "@<localfile>"`. Write the script to a local file
first. This is the `harness via @file` pattern already recorded in the v1.0.37
report — it was rediscovered the hard way, so it is now a permanent rule.

## L3 — `--query "[?...]"` filters get mangled by the Windows shell and silently match nothing

**Discovered:** cfv-0715 teardown (2026-07-15). **This one is a billing leak.**

```
az network nic delete -g $RG -n $(az network nic list -g $RG --query "[?starts_with(name,'cfv-0715')].name" -o tsv)
  -> ].name was unexpected at this time.
  -> ERROR: unrecognized arguments: ...
  -> printed "nic deleted" anyway
```

The teardown loop reported `nic deleted / public-ip deleted / disk deleted` while
deleting **nothing**, leaving four orphans (NIC, public IP, NSG, OS disk) billing
after the VM was gone. A teardown that trusts a filtered query is a teardown that
reports success and leaks money.

**Rule:** delete by **explicit resource name**. Never rely on a `--query` filter in
a teardown path. Always finish with an **unfiltered** `az resource list -g <rg>`
and read it with your own eyes — that listing, not the delete commands' output, is
the proof.

## L4 — `2>&1` on `az` breaks `ConvertFrom-Json`

**Discovered:** cfv-0715 (2026-07-15).

`az ... -o json 2>&1 | ConvertFrom-Json` fails with
`Invalid JSON primitive: WARNING.` — PowerShell 5.1 wraps a native command's
stderr in ErrorRecords and merges Azure's warnings into the stream.

**Rule:** never `2>&1` an `az` call whose stdout you intend to parse.

## L5 — a PowerShell harness that redirects its own streams turns `az` WARNINGS into fatal errors

**Discovered:** cfv-0715b diagnostic cycle (2026-07-15). **This one destroys healthy runs.**

The harness was invoked as:

```powershell
.\scripts\azure-validate.ps1 ... *>&1 | Tee-Object -FilePath $log
```

`az vm create` **succeeded** — the VM provisioned and the installer was running (an
independent `run-command` probe returned `STILL_INSTALLING`). But az also printed a
deprecation warning (`WARNING: ... will be removed in a future release.`) to
**stderr**. The `*>&1` merged stderr into the output stream; PowerShell 5.1 wraps
redirected native-command stderr in `ErrorRecord`s (`NativeCommandError`); the
script runs `$ErrorActionPreference = 'Stop'`; so the *warning* became a
**terminating error**, `finally` fired, and the harness tore down a perfectly good
VM ~6 minutes in — then would have reported the run failed.

**Mechanism.** Native stderr becomes `ErrorRecord`s **only when redirected**. Left
alone it flows to the console harmlessly. So the redirect *creates* the fault; the
same script run without it is fine. This is L4's sibling: L4 breaks
`ConvertFrom-Json`, L5 breaks the whole run.

**Rule:** never `*>&1` or `2>&1` a PowerShell harness that calls `az` under
`EAP=Stop`. Let stderr flow; capture it at the outer layer (the agent harness
already captures it). `azure-validate.ps1` now refuses to start if it detects a
redirect on its own invocation line.

**Read-across:** any "az succeeded but my script threw" is this until proven
otherwise. Check for a redirect before believing the product is broken — and note
that a `finally`-based teardown makes this failure *expensive*: it deletes the
evidence.

## L6 — without a redirect, a failed `az` call does NOT stop the script (the exact inverse of L5)

**Discovered:** cfv-0715d diagnostic cycle (2026-07-15), immediately after fixing L5.

L5's fix (stop redirecting stderr) removed the false *fatal*. It also created a
false *success*:

```
ERROR: {"status":"Failed", ... "code":"OSProvisioningTimedOut" ...}
[17:31:39] Provisioned. (admin password generated in-memory; never printed or written)
[17:31:39] Staging ... onto the VM
```

`az vm create` failed and the harness printed **"Provisioned."** on the next line
and kept going — because `$ErrorActionPreference = 'Stop'` governs *PowerShell*
errors, **not a native command's exit code**. Without the redirect there is no
`ErrorRecord`, so nothing throws.

**The pair, stated once so it is never re-learned:**

| | stderr redirected (`*>&1`) | stderr not redirected |
|---|---|---|
| az **WARNING** | becomes a TERMINATING error (**L5**) | correctly ignored |
| az **ERROR** | terminates | **silently ignored (L6)** |

Neither mode is safe on its own. **The correct pattern is: no redirect + an
explicit `$LASTEXITCODE` check after every az call whose failure matters.**

**Second half of the rule — do not trust the exit code alone, either.** For this
custom image ARM reports `OSProvisioningTimedOut` while the guest **boots fine**
(the agent just reports late): cfv-0715d's VM was `PowerState/running` and serving
`run-command` while ARM called the deployment Failed. So on a non-zero exit,
**ask the VM** (`az vm get-instance-view` → `PowerState/running`) before deciding.
A hard abort on exit code alone would have thrown away a working VM;
a blind continue spends 40 minutes on a VM that may not exist. Check, then ask.

### L2 (sharpened) — the real rule is ONE LINE, and `@file` is not the fix

**Sharpened:** cfv-0715c/e (2026-07-15), after L2 cost three more VMs.

L2 said "use `@<localfile>`". That is **wrong** — or at least insufficient. What the
cfv-0715 lineage actually shows:

| `--scripts` shape | result |
|---|---|
| **single line** + `--query` | **WORKS** (this is what the `INSTALLER_DONE` poll uses, and it worked on cfv-0715) |
| **multi-line inline** | `--query` is silently **ignored** — az returns the whole JSON envelope — *and* the script yields `StdOut: ""`, `StdErr: ""` |
| **`@file`** | returned **empty** on cfv-0715c |

The multi-line failure is doubly deceptive: both `StdOut` and `StdErr` come back
empty with `"displayStatus": "Provisioning succeeded"`, so it reads as *"the box ran
my script and it printed nothing"* — you go debugging the VM, the image, the
network. The script never coherently ran. Meanwhile the wrapping `--query`
disappearing means `$r` is a JSON blob, so any `if ($r -match 'expected')` guard
fails for a second, unrelated-looking reason.

**Rule:** compose run-command scripts as a **single line** with `;` separators.
If you need multi-line content on the VM (a `.cmd`, a `.ps1`), carry it as
**base64** and `[IO.File]::WriteAllBytes` it in that one line, or download it from
blob storage via SAS — never paste it into `--scripts`.

**Corollary:** always assert on run-command output (`if ($r -notmatch '<marker>')
{ throw }`). Without a marker assertion, an empty `message` sails straight through
and the next step runs against a machine that is not in the state you think it is.

## L7 — `az` on Windows is `az.cmd`: cmd.exe re-parses every argument (this is the root of L2 AND L3)

**Discovered:** cfv-0715f (2026-07-15), after L2/L3 had each been "fixed" twice.

`az` on Windows is **`az.cmd`, a batch wrapper**. Invoking it from PowerShell hands
the argument string to **cmd.exe**, which re-parses it before Python ever sees it.
cmd treats `" ( ) & | < > ^` as metacharacters. The proof was unmistakable — the
harness's own output contained a **local cmd prompt echo**:

```
Output: C:\Users\bmcki\ClawFactory-Secure-Setup>  "C:\Program
.Length)"; "OK was unexpected at this time.
```

`was unexpected at this time` is cmd.exe. The script was never sent to Azure; cmd
tried to run it **locally**.

**This single fact explains the whole lineage, which was misdiagnosed three times:**
- **L3** — `--query "[?starts_with(name,'x')]"` "mangled by the Windows shell": the
  `(` `)` `'` are cmd metacharacters.
- **L2** — multi-line `--scripts` "mangled": embedded `"` break cmd's quoting.
- A SAS URL inline is unsafe: `&` is a cmd command separator.
- `$((Get-Item x).Length)` inline: parens.

**Rule:** never pass a script, a JMESPath filter with parens, or any string
containing `" ( ) & | < > ^` as an inline `az` argument on Windows. Pass scripts
via **`--scripts "@file"`** (the only argument is then a plain path). Keep
`--query` expressions paren-free (`value[].message` is fine; `[?foo(x)]` is not).

**And read BOTH streams.** `--query "value[0].message"` is **StdOut only**. A script
that throws leaves StdOut empty and its error in `value[1]` (StdErr) — which is how
cfv-0715c's `@file` run looked like "empty output, transport broken" when the
transport was fine and the script had simply thrown. Use `value[].message`.

`azure-validate.ps1` now funnels every run-command through one `Invoke-Rc` helper
that does both.
