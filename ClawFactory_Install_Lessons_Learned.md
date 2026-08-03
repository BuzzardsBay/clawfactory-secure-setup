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

## L14 -- restart via the mechanism the install PROVES works; and audit the CONTEXT of every health probe

**Discovered:** v1.0.43 (cfv-0717a/b, 2026-07-17). L13 confirmed 120s clears the cold start but the
install still failed -- the *restart* was the bug, and there were TWO of them:
1. **Restart mechanism.** Every restart step (`Step-EnableChatCompletions`, `install-chat-proxy.sh`)
   used a bare `systemctl --user restart`, fragile in the no-login WSL install context. The gateway
   *install* comes up reliably via `openclaw gateway install --force` (its own start). Fix = a shared
   `restart_gateway_reliably <port>`: `openclaw gateway restart` (openclaw's OWN, token-preserving),
   fallback `openclaw gateway install --force` (proven start, honors the ExecStart drop-in), with XDG
   + `assert_user_manager_ready`. Never a bare unit restart. This made the install GREEN.
2. **Health-probe CONTEXT (the latent one).** `install-chat-proxy.sh` health-checked the moved
   gateway on 8788 **as clawuser** -- but the nft firewall DROPS `clawuser->8788` (that is the whole
   point of the private port). So the probe got 000 even when the gateway was healthy -> fail-closed
   rollback. Latent since the feature shipped; never exercised until the step first ran on a
   firewall-active clean box. **Rule: a health probe must run from a context the firewall ALLOWS for
   that port.** Probe the private port as root (exempt); probe the public/proxy port as the client
   (clawuser). Audit the uid of every `curl`/health check against the egress rules, not just its
   timeout.

## L15 -- a green install gate exposes the RUNTIME; the agent's first real run is its own gate

**Discovered:** v1.0.43 cfv-0717b (2026-07-17). The install finally passed, so the agent ran on a
clean box for the FIRST time (every prior run died at the install gate) -- and it couldn't start:
`EACCES: permission denied, open '/home/clawuser/.openclaw/workspace/AGENTS.md'`. Root cause:
`freeze-injected-soul.sh` runs as root and `mkdir -p …/workspace` BEFORE OpenClaw creates it lazily,
leaving the workspace **directory** root-owned; it chowns only `SOUL.md`, so clawuser can't write
`AGENTS.md`. The B4 positive control failed -> the whole headline test is INVALID (by its own rule).

**Rules:**
1. **Fixing the gate reveals the next domino (L12 again, now at the runtime layer).** A step that
   creates a path AS ROOT on behalf of a clawuser service must `chown` it back, or the service can't
   write there. `mkdir -p` as root is a silent ownership trap -- grep every root `mkdir`/`install -d`
   under a user's `$HOME` for a matching chown.
2. **Only freeze the file, not its directory.** Immutability belongs on `SOUL.md` (root:root 444 +i);
   the workspace *directory* must stay writable by the agent uid.
3. **The consumer view has its own control.** The isolation SUBSTRATE was validated by observation
   this run (private-port firewall: `clawuser->8788=000`, `proxy_8787=200`; SOUL immutable; spend
   gate; docker gone), but the headline's agent's-own-output proof needs a working agent -- which is
   itself gated by (1). Separate "the substrate holds" from "the agent, driven, cannot reach it"; the
   second needs the agent to actually run.

## L16 -- the fix is proven when the CONSUMER runs; and a working-agent suite outlasts a 1h SAS

**Discovered:** v1.0.44 (cfv-0717c/d, 2026-07-17). The L15 one-line `chown clawuser:clawuser
/home/clawuser/.openclaw/workspace` (mirror of the gateway `.config` ownership fix -- root creates a
path under the agent's $HOME, must chown it back) WORKED: the agent created its whole workspace
(`AGENTS.md HEARTBEAT.md IDENTITY.md SOUL.md TOOLS.md USER.md`), and **the headline isolation is
PROVEN from the agent's own output** -- it refuses the ungranted canary via `/mnt/c` and by listing,
refuses symlink/`../../..` escapes, `/etc/shadow` denied, canary never appears (4.3/4.4). SOUL.md
stayed root:root 444 +i and every tamper still blocked (T1.2a-c/T4.4) -- directory ownership and
per-file immutability are orthogonal, exactly as intended.

**Rules:**
1. **Prove a runtime fix by driving the consumer, not by re-reading the config.** "AGENTS.md exists
   in the workspace listing" + "the agent produced a real refusal in its own words" is the proof; a
   mount table or an ownership `stat` is not.
2. **A full suite with a WORKING agent easily exceeds 1h -- don't pin a SAS at staging time.** Every
   prior run halted at the install gate in minutes, so nobody noticed the diag-retrieval SAS reused
   the staging `$exp` (start+1h). The first run that actually ran the agent (cfv-0717c) took ~65 min
   and the bundle-upload SAS was already expired -> AuthenticationFailed -> the evidence was lost and
   the VM was torn down. Compute the retrieval SAS FRESH at retrieval time, and verify the blob
   actually landed (`az storage blob exists`) -- the VM's `UPLOADED=<localsize>` marker prints even
   when the PUT failed, silently masking it.

## L17 -- the first agent turn after an idle is cold; warm before any load-bearing turn

**Discovered:** v1.0.44 cfv-0717d (2026-07-17). The probe runs a 5-min idle (3.3) immediately before
the Task 4 headline, so the 4.2 positive control was the FIRST agent turn after the idle -- and it
came back blank: the gateway/spend-meter was cold, so the turn-gate fail-safed (`spend_meter_unknown
=> block`, which is the CORRECT fail-safe) or the turn timed out. The very next turns warmed up and
produced full, articulate responses. A cold first turn is not an agent failure; it is warmup.

**Rules:**
1. **Warm the agent with a throwaway turn before any make-or-break turn** (a positive control, a
   demo, a first customer turn after boot/idle). Retry once on an empty/blocked result before
   declaring failure.
2. **`spend_meter_unknown => block` is a feature, not the bug.** The gate fail-safing on a cold meter
   is correct; the fix is to warm the meter, not to weaken the gate.
3. **Corroborate a blocked control against other turns.** 4.2 blanked, but T1.2f (turn runs after
   SOUL restore), T6.3 (normal proxy turn, real reply), and T1.1a/b (real fetches) all ran in the
   same session -- so the agent demonstrably works and the 4.3/4.4 refusals are discriminating, not a
   broken-everything artifact.

## L18 -- one root behind many blanks: the turn-gate's cold-meter query blocks the first turns

**Discovered:** v1.0.44 confirmation cfv-0717e (2026-07-17). The L17 "warm the agent" fix was NOT
enough on the agent-CLI path: the warm-up turn AND both retries got `spend_meter_unknown`, yet a
direct `openclaw gateway usage-cost` returned `$0.08 · 22k tokens` at the same moment and the proxy
turn-gate read spend fine. Root cause (source): `clawfactory-turn-gate.sh:54` reads the meter via
`openclaw gateway usage-cost --json --days 400`; when the gateway is cold that 400-day WS query
returns EMPTY -> the gate fail-safes. This single cold-meter issue is the common root of the 4.2
cold-blank (cfv-0717d), the T6.1/T6.2 chatCompletions blanks (cfv-0717d), AND this run's 4.2 block.
Proof it is timing, not a real gap: once WARM (a control turn first), the chatCompletions cap=0 and
tampered-SOUL cases both return readable, chat-completion-shaped block messages and neither runs the
model (security intact).

**Rules:**
1. **A cold-start artifact can outlast a single warm-up turn -- and it points at a PRODUCT issue, not
   a test one.** A fresh install's first customer turns are fail-safe-blocked until the meter WS
   warms. Papering it over with a bigger probe warm-up hides a real UX defect; report it.
2. **Prime the exact query the gate uses, at the end of install.** The gate uses `usage-cost --json
   --days 400`; prime THAT (not a plain `usage-cost`, which warms differently and misled the
   diagnosis). Or make the gate retry / shrink `--days` to the governor window / add a generous
   timeout. Keep the fail-safe.
3. **Separate "the message is blank" (UX) from "the turn ran" (security).** Check token usage / a
   sentinel reply: cap=0 and tampered-SOUL both returned 0 tokens and no model output -> blocked. A
   blank-but-blocked response is a UX bug; a real reply would be the security bug. They need different
   urgency.

## L19 -- fix the meter at the source, and make sure the probe reads the granted mount

**Discovered:** v1.0.45 cfv-0717f -> cfv-0717g (2026-07-17). The L18 diagnosis was acted on two ways
in v1.0.45: (a) `clawfactory-turn-gate.sh` now wraps the `usage-cost --days 400` read in a bounded
retry (10x/~10s, fail-closed preserved), and (b) `setup.ps1` PRIMES that exact query as `clawuser`
after the health gate so the meter is warm before the first customer turn. That fixed the product
side -- but cfv-0717f's 4.2 positive control STILL failed with "project-note.txt does not exist."
The cause was the PROBE, not the meter: it read the home workspace (`/home/clawuser/.openclaw/
workspace/`), where nothing was granted, instead of the grant's mount. Fixed the probe (`b14f7bc`)
to read `/workspaces/<grant-id>/project-note.txt` and warm with a throwaway-turn loop first;
cfv-0717g then PASSED -- the agent read and quoted `GRANTED-FILE-<rand>` on warm-up attempt 2.

**Rules:**
1. **Prime the meter, don't just retry the gate.** Doing both (retry in the gate + prime at end of
   install) is belt-and-suspenders and cheap; the prime is what makes the FIRST turn work, the retry
   is what makes it robust on a slow box. Keep the fail-safe on both.
2. **A positive control must exercise the exact path the claim is about.** The headline is "the agent
   can read a GRANTED path" -- so the probe must open the *grant's mount* (`/workspaces/<grant-id>/`),
   not the home workspace. A green meter with the probe pointed at the wrong directory reads as a
   product FAIL when the product is fine. Verify the path the test opens before blaming the meter.
3. **Warm-up loop, not a single warm-up turn.** cfv-0717g went hot on warm-up attempt 2, not 1 -- a
   loop that retries the throwaway turn until non-empty is more reliable than one-and-done (see L17).

## L20 -- a multi-line string concat inside a PowerShell array literal parses as separate elements (silent evidence loss)

**Discovered:** Studio JOB 2 cfv-149 (2026-07-20; ClawFactory-Studio close-out `8c0204d`, fix `e3155b4`).
The JOB 2 driver built the RunOnce `wrapper.cmd` with the probe command written as a multi-line string
concatenation inside an `@(...)` array literal (`'powershell ... ' + "-A ..." + "-B ... > out.txt 2>&1",`).
PowerShell parsed each physical line as a SEPARATE array element (6, not 4) -- a silent, syntactically
valid misparse that `[Parser]::ParseFile` cannot catch. So the wrapper ran the probe with NO redirect
(output lost to the session console) and ran `-LicenseKey ... > out.txt 2>&1` as a standalone command whose
`'-LicenseKey' is not recognized` error was the only thing captured (102 bytes). The driver then reported
exit 0 and tore down -- silent fake-success inside our own harness; 100% of the run's evidence was lost.

**Rules:**
1. **Build a command line as ONE explicitly-joined string, then place it as a single array element.** Never
   rely on trailing-`+` continuation inside `@(...)` -- it reads as element separators. Guard with a
   `Count -ne N` assertion that throws before the artifact is used.
2. **Evidence capture must be producer-owned AND redundant.** The thing under test writes its own transcript
   with a completion sentinel (`JOB2_PROBE_COMPLETE rc=<n>`), independent of any single wrapper redirect.
   One redirect must never be able to lose a whole run.
3. **Gate teardown on evidence-in-hand.** Refuse to delete a VM unless a retrieved channel carries the
   sentinel above a plausible size floor; otherwise deallocate + preserve + exit nonzero. Never tear down on
   a fake-success bundle.
4. **Simulate before execute.** A committed render test that BUILDS the artifact and asserts its structure
   (element count, command+redirect on one line) catches semantic misparses a parser cannot; it runs for
   free, forever (`validation/test-wrapper-render.ps1` in the Studio repo).

## L21 -- a .ps1 that carries multi-line bash into WSL must reach bash as LF, or strip CR at the boundary

**Discovered:** Studio JOB 2 F2 / cfv-150 (2026-07-20). `adversarial-suite.ps1` T4.5 passes a multi-line
bash here-string into WSL via the `Wsl` helper (base64 -> `bash`). It FAILED on the clean VM with
`bash: line 9: syntax error: unexpected end of file`. Root cause: `*.ps1` is NOT covered by this repo's
`.gitattributes` eol=lf rules, so on Windows (core.autocrlf=true) the working copy is CRLF
(`git ls-files --eol` = `w/crlf`), and the JOB 2 driver stages that CRLF working copy. A multi-line bash
script with CRLF breaks (`if...fi` + quotes, each line ending `\r`); a SINGLE-line command tolerates a lone
trailing CR -- which is why only the one multi-line cell failed and it hid behind a green "28/0" summary.
Confirmed with `bash -n`: LF ok, CRLF errors. Fixed by stripping carriage returns in the `Wsl` helper
(a `-replace` of CR before the base64 encode), so bash always receives LF regardless of the checkout.

**Rules:**
1. **Any .ps1 that transports bash/node into WSL must reach bash as LF.** The existing `.gitattributes`
   already forces `*.sh`/`*.mjs` to LF for exactly this reason; a `.ps1` that EMBEDS bash is the same hazard
   and is not covered. Either add `*.ps1 text eol=lf` (renormalizes all .ps1) or strip CR in code at the WSL
   boundary (self-contained, robust regardless of checkout). This repo did the latter.
2. **`unexpected end of file` on a here-string that looks balanced is almost always CRLF.** Reproduce with
   `bash -n` on an LF copy vs a CRLF copy before rewriting the script's logic.
3. **A latent bug in a rarely-reached multi-line cell hides behind a green aggregate.** Single-line commands
   survived CRLF, so the suite's "28/0" never exposed T4.5 until a run finally executed it. Trust a per-cell
   result you actually ran over a comfortable baseline count.

## L22 -- the verifier channel can lie; an inline `wsl.exe -- bash -c` probe fabricates PASSES

**Discovered:** Guard 2 Task 0 (2026-08-01/02). While confirming that uid 1000 has no route to SMTP, a
probe run as `wsl.exe -u root -- bash -lc '<multi-line script>'` reported that clawuser had CONNECTED to
`smtp.gmail.com` on both 465 and 587. That would have been a ship-blocking hole in the Guard 2 claim. It
was false. The channel itself was corrupting the script and its results:

- Whole `echo` lines silently vanished, and one header arrived truncated mid-word (`is bash? ---`).
- `$?` returned `0` for a command that had just printed `Connection refused` on the line above.
- Shell-function positional parameters expanded to empty, so `probe host port` ran `exec 3<>/dev/tcp//`
  and printed `  : blocked`.
- A `for ip in ...; do nft list ... | grep -q "$ip"; done` loop had `$ip` empty, making every iteration
  `grep -q ""`, which matches any line. That produced three confident, entirely fabricated "PRESENT"
  readings about firewall allowlist contents.

MSYS path conversion was tested and **refuted** as the cause (`MSYS_NO_PATHCONV=1` changed nothing; the
string arrives intact). The corruption is in the nested quoting and stream layer between the Bash tool,
`wsl.exe`, and the inner shell. Same family as L20 and L21: the transport mangles the payload, and the
result still looks like a clean measurement.

The false SMTP result was caught only because the probe carried a **control that had to fail**: a
non-allowlisted destination on 443 also reported success, which is impossible. Re-run through a
file-based channel, the true result was unambiguous: allowlisted 443 connects, non-allowlisted 443
times out, all three SMTP ports time out for clawuser, and root gets a real `220 smtp.gmail.com ESMTP`
banner.

**Rules:**
1. **Never report a security result measured by an inline nested `wsl.exe -- bash -c`.** Write the probe
   to a file, copy it in, strip CR, run it redirecting to a file, copy that file out, and read it. The
   file-based channel is the only one that has held up.
2. **Every block assertion carries a paired control that MUST fail in the same run.** A test whose
   control does not fail is a void result, not a pass. Absent that control, this session would have
   filed a false hole against a firewall that was working correctly.
3. **A verifier that reports `0` is not evidence that the subject succeeded.** Prefer a positive artifact
   that only a real success can produce: a protocol banner, a counter delta, a file that only the true
   path writes. `rc=0` alone proved nothing here.
4. **When a result contradicts a previously executed finding, suspect the harness before the system.**
   Addendum A had recorded these ports as blocked by execution. The contradiction was the signal.
