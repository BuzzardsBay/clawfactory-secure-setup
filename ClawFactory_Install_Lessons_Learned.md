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

## L8 — `Where-Object | Set-Content` silently no-ops when the filter empties the pipeline

**Discovered:** cfv-0715p (2026-07-15), in the sweep-list guard added the same session.

The sweep list (`validation-runs/ACTIVE_VMS.txt`) exists because a **killed** process
never runs `finally` — that is how cfv-0715d ended up torn down by hand while billing.
Entries are removed once an unfiltered listing proves the VM gone:

```powershell
(Get-Content $f) | Where-Object { $_ -notmatch "^$VmName\s" } | Set-Content $f   # WRONG
```

When the filter removes the **only** line, `Where-Object` emits nothing, so
`Set-Content`'s process block **never runs** and the file is left **unchanged**. The
list therefore only ever cleared when 2+ VMs were registered — and a stale entry makes
the sweep cry wolf, which is how a real alarm gets ignored. (Same failure family as the
teardown assertion that reported an ORPHAN before ARM had settled.)

**Rule:** when rewriting a file by filtering it, **materialise the survivors and write
unconditionally** — never pipe a filter straight into `Set-Content`:

```powershell
$keep = @(Get-Content $f | Where-Object { $_.Trim() -and $_ -notmatch "^$VmName\s" })
[IO.File]::WriteAllText($f, (($keep -join "`r`n") + $(if ($keep.Count) { "`r`n" } else { "" })), (New-Object Text.ASCIIEncoding))
```

**Read-across:** any "my cleanup code ran but the file still says otherwise" in
PowerShell is this until proven otherwise. Verify a guard's *negative* path — the case
where it should erase the last row — because that is the path that only fires when it
matters.

## L9 — when you remove a component, assert the invariants its side effects were silently upholding

**Discovered:** the v1.0.38 gateway-unit EACCES bug (probe `cfv-0715p`, fixed v1.0.39).

The gateway install broke on clean machines because `openclaw gateway install` runs as
clawuser and could not write `~/.config/systemd/user/openclaw-gateway.service` — root
owned the parent chain (root's `mkdir -p` created it; the chown-back covered only the
leaf). But that ownership bug had existed **since the initial release**. It only became
reachable when Docker was removed, because `dockerd-rootless-setuptool.sh install` had
been creating `~/.config/systemd/user/` **as clawuser** first, so root's later `mkdir -p`
created nothing and ownership stayed correct.

The Docker-removal commit was careful — it documented **three** hidden dependencies it was
preserving (nftables, dbus-user-session, linger). It still shipped a broken installer,
because a **fourth** side effect (the `.config/systemd/user` ownership) was invisible:
nothing in the flow ever asserted it, so nothing could catch its loss.

**The general rule:** removing a component also removes every *incidental* side effect it
had. Enumerating the ones you know about is necessary but not sufficient — the dangerous
ones are the side effects nobody documented, that some later step silently relied on. You
cannot grep for an invisible dependency. What you *can* do is make the **invariant** each
critical step depends on **explicit and asserted at the point of use**, so that if any
future change (a removal, a reorder, an upstream update) breaks it, it fails loud, named,
and immediately — not 38 versions later, behind a misleading error, on a clean machine you
don't test often.

**How to apply:**
- When deleting a step, ask not "what did this install?" but "what state did everything
  *downstream* assume this left behind?" — and assert that state where it is consumed.
- Prefer an assertion at the consumer over a comment at the producer. The v1.0.39 fix adds
  both an explicit chown (producer) **and** a fail-loud ownership guard right before the
  gateway install (consumer). The guard is the durable half: it would have caught this bug
  the first time it shipped, and it will catch any future regression regardless of cause.
- A silent success signal is the same anti-pattern one layer up: setup.exe exited 0 on a
  failed install because Inno swallowed the `[Run]` child's exit code. Assert on the honest
  marker (`INSTALLER_DONE=success`), never on the lossy proxy.

## L10 -- an external activation call in the install path leaks state that teardown must reclaim

**Discovered:** v1.0.40 validation blocked (2026-07-16). The installer activates a license at
InitializeWizard via `POST /activate {key, machine_id, product}`; `machine_id` is the Windows
MachineGuid. Every validation VM consumed a license slot, and deleting the VM did NOT free it
-- so `CF-TEST-TEST-TEST-TEST` hit its 10-machine cap and blocked a whole run at the license
gate, with a misleading "missing or invalid /LICENSE=" abort (the arg was present; the slot
was full).

**Rule:** any install-path call to an EXTERNAL service that registers per-machine state
(license activation, device enrolment, a seat/slot) leaks that state on a throwaway VM. The
teardown that reclaims the VM must ALSO reclaim the external state -- here, `POST /deactivate`
with the SAME machine_id the install activated (read it from the VM while it is alive; a
mismatched id frees nothing). A failed reclaim is a logged warning, not a teardown failure,
but it MUST be visible or the leak is silent until the cap blocks the next run.

## L11 -- gate on the invariant, not on a shell block's exit code (a benign `tee` can fail it)

**Discovered:** v1.0.40 cfv-0716q (2026-07-16). The gateway-install block SUCCEEDS (unit
installed, service active) but exits 1 because `... | tee -a /tmp/openclaw-install.log` fails
"Permission denied" (the log is root-owned; the block runs as clawuser). The install then
throws "did not create the unit" -- which it plainly did (923 B, observed).

**Rule:** do not treat a multi-command shell block's raw exit code as a success/fail gate
when the block does belt-and-suspenders work (logging, best-effort restarts). Gate on the
ACTUAL invariant -- here, the unit file existing + the /status poll -- and let noisy,
non-load-bearing failures (a `tee` to an unwritable log, a systemctl call with no user bus)
be non-fatal. A redundant `tee` to a root-owned file is exactly the kind of benign failure
that should never fail an install; if the [wsl] capture already logs the output, drop the
tee. Related: fail-loud scope (L9) -- distinguish the authoritative check from the
belt-and-suspenders.

**v1.0.41 confirmed (cfv-0716r, 2026-07-16):** the fix (A2 `test -f` the unit, then WARN +
defer to the /status poll instead of throwing) worked on a clean box -- verbatim, the block
STILL exits 1 even after the tee was removed, so the tee was NOT the sole cause and the
`test -f`-then-defer is the load-bearing half. Do BOTH (drop the redundant tee AND gate on
the invariant); do not assume removing the noisy command makes the block exit 0.

## L12 -- fixing one false-failure exposes the NEXT step; the same too-short-timeout bug recurs

**Discovered:** v1.0.41 cfv-0716r (2026-07-16). With the gateway false-failure (L11) fixed,
the install reached -- for the first time on a clean box -- `Step-InstallChatProxy` /
`resources/install-chat-proxy.sh` (Blocker 1: proxy owns 8787, real gateway -> private 8788).
It moved the gateway to 8788 via a systemd `ExecStart=` drop-in, restarted via
`systemctl --user restart`, and health-checked the new port for only ~30s
(`seq 1 15; sleep 2`), the proxy /status for ~20s (`seq 1 10; sleep 2`), and
`Step-EnableChatCompletions` waited 12s. But the gateway cold-start on a 2-vCPU VM is ~67s
(the SAME number that forced the gateway `/status` poll from 60s -> 120s). All three windows
undershoot 67s -> the restarted gateway is still cold-starting when the proxy step gives up ->
FATAL rollback -> `INSTALLER_DONE=failure` ("ClawChat would be UNGATED - do not ship").

**Rules:**
1. **Every gateway restart+health-check in the install path must budget for the ~67s cold
   start**, not a hopeful 12-30s. When you widen one such timeout, grep for the others -- they
   are the same bug waiting for the step above them to stop RED-gating first.
2. **A fixed blocker uncovers the next domino.** A run that has *never* reached step N cannot
   have validated step N. Expect the first green-past-a-longstanding-gate run to expose a fresh
   failure downstream; budget a follow-up build for it rather than calling the fix "done."
3. **Prefer the mechanism that already works over the one that's fragile in-context.** The
   gateway *install* comes up reliably because `openclaw gateway install --force` direct-starts
   it; the proxy step's port-move leans on `systemctl --user restart`, which is fragile in the
   no-user-bus install context (see the deferred `enable-linger || true`). Route (v1.0.42):
   widen the health windows to >=120s to match the /status poll, AND harden the restart the way
   the install does. The fail-closed behavior itself is correct -- do not relax the gate; make
   the gateway actually come up in time.

## L13 -- a cold-start-sensitive timeout is never a single site; fix the CLASS, and don't stop at the window

**Discovered:** v1.0.42 (cfv-0716r -> cfv-0716s, 2026-07-16). L12 fixed the ONE window that fired;
this session audited EVERY gateway health window in the install path and swept the whole class to a
single 120s standard behind a shared helper (`resources/gateway-wait.sh`, `wait_for_gateway_healthy`
sourced by both `install-chat-proxy.sh` and `Step-EnableChatCompletions`, staged by
`Step-StageGatewayHelper`; PS-only sites -- the PostInstall-Smoke `/status` Check and `launcher.ps1`
-- widened in place to match). The inventory (10 sites; 5 were under the ~67s cold start) is the
deliverable, not the one fix.

**Rules:**
1. **Audit the class before editing.** A timeout that failed because of a cold start is a *symptom
   of a shared constant*, not a one-off. Grep the whole install path (`curl`/`/status`, `seq 1`,
   `sleep`, `for i in`, `is-active`, "did not respond within") and list every window with its
   effective seconds. Fixing three of four wastes the whole VM cycle.
2. **One source of truth.** Put the window in a single helper both callers source, so the numbers
   cannot drift apart again. Widen-in-place only where a shared source is genuinely too invasive
   (PS-vs-bash transport), and comment the link.
3. **Wall-clock, not accumulated sleep.** A cold gateway can cost `curl --max-time` per probe, so a
   loop that counts only its sleeps overshoots its own budget. Bound on `date +%s`.
4. **But the window may not be the bug.** v1.0.42 CONFIRMED 120s clears the ~67s cold start (the
   main `/status` poll caught `exit 7,7,7,7,28,28,28 -> 0`) -- yet the install STILL failed, because
   `Step-EnableChatCompletions` timed out at **120s** after its `systemctl --user restart`: the
   *restart* took the gateway down and it did not come back. When a widened timeout still fails, the
   failing operation (here the restart in the no-login WSL context), not the wait, is the real
   defect. The gateway *install* comes up reliably via `openclaw gateway install --force`; the
   *restart* steps lean on `systemctl --user restart`, which is the fragile link (L12 rule 3, still
   open -> v1.0.43). Instrument the failing step (the probe now captures the `[chat-proxy]` detail)
   before assuming the timeout was the whole story.
