# v1.5 backlog

Written 2026-08-29, so that v1.5's certain contents stop living in chat memory and
handoff prose. Every number on this page was re-derived from the tree on the day it was
written; where a prior record is quoted, it is quoted as a prior record and the
re-derivation is shown beside it.

Nothing here is a decision about scope. The **Certain** section is certain only in the
sense that each item requires a rebuild anyway, so shipping v1.5 without it costs a
second rebuild. The **Undecided** section is explicitly undecided and carries no
recommendation.

---

## v1.4.5 — the install-fix release, which comes BEFORE everything below

**Added 2026-08-30**, after the first external install failure
(`docs/session_reports/2026-08-30_first_external_install_failure_closeout.md`, card `#315`)
and the exit-code census that followed it
(`docs/session_reports/2026-08-30_pre_v145_groundwork_closeout.md`).

v1.4.5 is not part of v1.5 and must not wait for it. Its scope is deliberately the
smallest surface that fixes the failure: `Step-Preflight`, `Step-EnsureWsl` and
`Install-WslDistroWithFallback`, all of which complete before `Step-ConfigureWslConfig`.
Everything else the census found is listed in item 7 below as **v1.5**, and the reason is
revalidation cost, not severity — widening the changed surface past `Step-EnsureWsl`
converts a two-box revalidation into a full four-box rerun.

**D1 no longer waits. Updated 2026-08-30, later the same day.** The external machine's
`install.log` arrived and settles the root cause with no inference left: the import failed
`Wsl/Service/RegisterDistro/CreateVm/HCS/HCS_E_SERVICE_NOT_AVAILABLE`, `wsl --install` printed
*"Changes will not be effective until the system is rebooted"* and returned **0**, and the next
step failed `WSL_E_DISTRO_NOT_FOUND`. Task Manager on that machine reads **Enabled**, so the
firmware reading is ruled out.

**`PR.C1` is answered from the field, so the reproduction is closed as redundant.** The log line
`WSL2 kernel loaded but Ubuntu missing` is inside the `if ($kernelOk)` branch at `setup.ps1:924`,
and `$kernelOk` comes from `wsl --status`'s exit code at `923` — so **`wsl --status` exits 0 while
`VirtualMachinePlatform` is `EnablePending`**, which is precisely the assumption D1's design
turned on. `cfv-183` was torn down. Full reading: the close-out's §9.

> **CORRECTION, 2026-08-31, by measurement. The two paragraphs above are superseded and
> are kept rather than deleted.**
>
> **Claimed** (above, and in `docs/session_reports/2026-08-30_v145_install_path_fixes_closeout.md`
> §3.8): that D1 fixes the pending-reboot case, and that on the external machine
> `wsl --status` exits 0 **while `VirtualMachinePlatform` is `EnablePending`**.
>
> **Measured**, on stock `MicrosoftWindowsDesktop:windows-11:win11-24h2-pro` (box `cfv-186`,
> 2026-08-30), in the external-failure state reproduced by the product's own route and
> corroborated by two controls that both fired:
>
> | Reading | Before restart | After restart |
> |---|---|---|
> | `VirtualMachinePlatform` | `Enabled` | `Enabled` |
> | `EnablePending` anywhere | never observed | never observed |
> | `Test-WslRebootPending` | `False` | `False` |
> | CBS `RebootPending` | `True` | `False` |
> | `PendingFileRenameOperations` | `True` | `False` |
>
> **True now.** The `EnablePending` sentence above was an **inference** from the external
> machine's `install.log`, not a reading of that machine's feature state, and the inference
> is wrong. `VirtualMachinePlatform` reads `Enabled` on both sides of the restart, so the
> typed state carries no information about a pending restart and `Test-WslRebootPending`
> returns `False` in exactly the state it was written for. **D1 does not fire, and does not
> fix the pending-reboot case.** Independently of that, the branch it guards is unreachable:
> `Update-WslEngine` runs before the gate and leaves `wsl --status` exiting 0.
>
> **v1.4.5 ships with D1 inert, deliberately.** The whole of the user-visible fix is
> delivered by **D2, D4 and D5**, none of which depends on D1: 91 seconds to a named message
> leading with the correct advice, against the 41 minutes the first external user spent
> reaching a message about a Linux user account. The rewrite is item 8 below.
>
> Full record: `docs/session_reports/2026-08-30_v145_validation_closeout.md` §1 Residual 1,
> §3.1 and §3.2.

### v1.4.5-A. Remove the WSL1 fallback. **Security fix, not an install fix.**

**Specification only. Nothing in this session edited `setup.ps1`.**

**What it is today.** `Install-WslDistroWithFallback:510-530`. When `wsl --install` fails
and the output matches `HCS_E_HYPERV_NOT_INSTALLED` or `0x80370102`, the function runs
`wsl --install --no-distribution`, `wsl --set-default-version 1`, and
`wsl --install -d Ubuntu --no-launch`, then logs

> `WSL1 fallback install succeeded. Some features (systemd, networking) behave differently on WSL1.`

and returns `'wsl1'`.

**Why it is a security item.** Eleven of the product's controls are systemd units. Read
from the tree, not from a prior close-out — the list is `uninstall.ps1:420`'s `CF_UNITS`,
and it is the same eleven:

| Unit | Control it carries | Defined at |
|---|---|---|
| `clawfactory-quarantine.service` | Guard 1, the delete broker | `resources/clawfactory-quarantine.service`, installed by `resources/install-quarantine.sh` |
| `clawfactory-quarantine-gc.service` / `.timer` | Guard 1 retention | same |
| `clawfactory-send.service` | Guard 2, the approval-gated send broker | `resources/clawfactory-send.service`, `resources/install-send.sh` |
| `clawfactory-send-gc.service` / `.timer` | Guard 2 retention | same |
| `clawfactory-proxy.service` | Blocker 1, the chatCompletions gating proxy | `resources/clawfactory-proxy.service`, `resources/install-chat-proxy.sh` |
| `clawfactory-fw.service` | egress-allowlist re-apply at boot | written inline, `setup.ps1:1817`, enabled `1830` |
| `clawfactory-allow-providers.service` / `.timer` | provider-address re-add | `setup.ps1:2233` / `2243` |
| `clawfactory-egress-refresh.service` | Guard 3 boot refresh | `resources/install-read-fetch.sh:~370` |

Plus `openclaw-gateway.service` as a **user** unit under `systemctl --user`, which needs
`loginctl enable-linger` and `dbus-user-session` (`setup.ps1:1349-1362`), and
`/etc/wsl.conf`'s `[boot] systemd=true` (`setup.ps1:1239`), which WSL1 does not read.

**Three controls do NOT depend on systemd, and saying so matters because the argument
should not be broader than the facts:**

- **The live nftables/iptables chain.** `Step-EgressFirewall` applies it directly with
  `nft -f`. Only its survival across a restart is `clawfactory-fw.service`.
- **`/etc/wsl.conf`'s `[automount] enabled=false` and `[interop] enabled=false`** — the P0
  file-isolation guard. A WSL-configuration control, verified by
  `Assert-WslAutomountDisabled` (`setup.ps1:1217`), no systemd involved.
- **The gated `openclaw` shim** at `/usr/bin/openclaw` — a filesystem substitution
  (`resources/install-turn-gate.sh`), no systemd involved.

**A correction to the reasoning in the prior close-out, and the reason to remove the branch
is stronger for it.** §4.3 of
`docs/session_reports/2026-08-30_first_external_install_failure_closeout.md` says *"A WSL1
install would produce a ClawFactory with none of its security controls."* Read against the
code, that is not what happens. A WSL1 install **cannot complete**. It dies, in this order:

1. `Step-PreinstallGatewayRuntime` (`setup.ps1:3743`) polls `http://127.0.0.1:8787/status`
   thirteen times and `throw`s *"Gateway did not respond after 120 seconds"*
   (`setup.ps1:~2625`). The gateway is started only through `systemctl --user`; **there is
   no `nohup`/`setsid` fallback anywhere in `setup.ps1` or `resources/gateway-wait.sh`** —
   `resources/launcher.ps1:205-206` claims *"Same logic as setup.ps1's
   Step-PreinstallGatewayRuntime"* and that comment is stale, the launcher has the fallback
   and the installer does not.
2. If it somehow got past that, `Step-FreezeInjectedSoul` (`3753`) runs
   `resources/freeze-injected-soul.sh`, whose `chattr +i "$WS"` at line 104 is unguarded
   under `set -e`.
3. And then `Step-InstallQuarantine` (`3754`): `install-quarantine.sh` has no start path for
   the broker other than the systemd unit, and its 30-second socket ping ends in
   `fatal "broker did not answer a ping from $AGENT_USER within 30s"`.

So the defect is not "ships insecure". It is **"spends roughly twenty minutes, then fails
with a message about a gateway health probe, or a broker socket, on a machine whose actual
problem is that it is running WSL1 because virtualization is unavailable."** The user is
never told the real thing. That is a worse diagnosis defect than the one that produced this
whole investigation, and it argues for removal at least as strongly.

**One premise is inherited rather than measured, and it is shared with the claim it
corrects:** that WSL1 has no systemd. It is not in dispute, but it has never been measured
on any box in this project, and neither the original claim nor this correction rests on
anything stronger.

**What to delete.** `setup.ps1:506-530` — the `$hyperVMissing` computation, the
`if (-not $hyperVMissing) { throw ... }`, and the three fallback calls (`$rFb1`, `$rFb2`,
`$rFb3`) with their logging loops and the `return 'wsl1'`.

**What replaces it.** An unconditional named stop at the point `wsl --install` fails, with
the virtualization diagnostic read from **the right variable** — D4's fix, which belongs in
the same edit. Today `setup.ps1:506` tests `$output`, built at `497` from `$rInst`, the
*install* call; the import call's streams are in `$rImp` and are only logged. The
replacement tests both.

**What the user sees.** Not a downgrade. A stop, naming the two things a person can act on:

> ClawFactory needs WSL 2, and Windows reported that the Virtual Machine Platform is not
> available on this computer. Two things cause this, and the log says which. **Restart this
> computer and run the installer again** — Windows sometimes needs a restart before
> virtualization support becomes active. **If that does not work, check your BIOS/UEFI
> setup screen** and turn on Intel VT-x (or AMD SVM Mode); Task Manager → Performance → CPU
> → Virtualization will say `Disabled` if this is the cause. Full details are in
> `C:\ProgramData\ClawFactory\install.log`.

Under D3 that message branches on `$script:VirtFirmwareSuspect` and leads with the firmware
half when the preflight found it.

**Regression risk: none any measurement would detect.** The branch has never executed on any
validation box. `docs/session_reports/` contains no run in which
`Install-WslDistroWithFallback` returned `'wsl1'`.

**Nothing dangles.** `$variant` is assigned at exactly three sites — `setup.ps1:882`, `926`,
`971` — and each is followed by one `Write-Log INFO "WSL variant installed: $variant"` and
nothing else. **It is never persisted, never branched on and never read again.** The
complete tree-wide census of every WSL1 reference:

| Site | What it is | Action |
|---|---|---|
| `setup.ps1:432, 436, 438` | comments describing the fallback | delete with it |
| `setup.ps1:506-530` | the branch itself | delete |
| `setup.ps1:831, 879` | comments naming "with WSL1 fallback" | reword |
| `setup.ps1:882/926/971` + `883/927/972` | `$variant` assign + log | keep; the string becomes always `'wsl2'`, so either keep the log or drop the return value |
| `resources/launcher.ps1:196` | comment explaining why the launcher probes HTTP instead of `systemctl is-active` — *"returned inactive on systemd-less WSL installs (WSL1 fallback or systemd-disabled)"* | **keep the code, keep the comment.** The HTTP probe is correct independently, and "systemd-disabled" remains reachable |
| `resources/uninstall.ps1:420` | comment *"uses iptables on WSL1"* on the `nft delete table` line | reword; the iptables-legacy backend remains reachable on a WSL2 kernel without nftables (`setup.ps1:1681`) |
| `validation/uninstall-teardown-extract.sh:4` | the same comment in the extracted copy | reword with it |
| `README.md:45` | the system-requirements bullet — *"WSL2 is required and there is no WSL1 fallback: if virtualization is unavailable the installer stops with a named message rather than installing something that cannot run ClawFactory's controls"* | **already correct as shipped in v1.4.5.** Listed so the census is complete, not because it needs an edit |
| `README.md:119` | the *"No WSL1 fallback (changed in v1.4.5)"* paragraph explaining the removal and what the installer does instead | **already correct as shipped in v1.4.5.** Same |

Nothing branches on the distro version anywhere. There is no `wsl --list --verbose` parse,
no `--set-version` read-back, and no `$variant` consumer.

> **CARRIED FORWARD 2026-08-31.** The two `README.md` rows above were missing from this
> table when it was written, and their absence was noted twice — in
> `docs/session_reports/2026-08-30_v145_install_path_fixes_closeout.md` §10 item 4 and again
> in `docs/session_reports/2026-08-30_v145_validation_closeout.md` §10 item 8 — without being
> added either time. They are added here. Both were re-derived from the tree on 2026-08-31,
> not copied from the close-outs that noticed them.
>
> **Nine sites, not seven.** The table's own claim to be *"the complete tree-wide census of
> every WSL1 reference"* was false at seven rows. Neither new row needs an edit: `README.md`
> was updated in the v1.4.5 build and both sentences describe the shipped behaviour
> correctly. The defect was in the census, not in the file — which is the point, because a
> census that claims completeness is read as one, and the next person to plan a WSL1 change
> from this table would have planned it against seven of nine sites.

### v1.4.5-B. The exit-code fixes on the changed surface

From the census (item 7): **D1** `setup.ps1:266`, **D2** `488` / `502` / `526`, **D1's
premise** `923` and `968`, **D5** the `Test-WslFunctional` ordering at `928-930`, `884-888`
and `973-975`, and one new site the census added:

**`setup.ps1:850` — `distroExistedPreInstall` defaults to the destructive answer.** *(Recorded
2026-08-30 as latent, not triggered: on the external machine the 60-second `wsl --list`
succeeded, so `wsl-state.txt` reads `false` truthfully. The risk is unchanged; it simply did
not bite this time.)*
`if ($rList.ExitCode -eq 0 -and $rList.StdOut)` gates the whole computation; on any failure
of `wsl --list --quiet`, `$distroExisted` stays `$false` and `wsl-state.txt` is written
`false`, which the uninstaller reads as *"this distro did not exist before we installed, so
it is ours to remove"*. **On the external machine that call took sixty seconds**, which is
the shape of a call that is about to fail. A `wsl --list` that errors should write **no**
verdict, or an explicit `unknown` that the uninstaller treats as "leave it alone", never
the answer that permits removing a user's pre-existing distro. Worth fixing in the same
edit because it is four lines away and in the same function.

### v1.4.5-C. The failure path itself. Three defects the log exposed, none of them in the diagnosis

**Added 2026-08-30 from the external machine's artefacts.** These are cheap, they are all on the
already-changed surface or in the shared failure path, and every one of them cost the first
external user something measurable.

**D6 — `Invoke-Rollback` announces work it has no mechanism to do.** `setup.ps1` has **31
distinct `Save-Checkpoint` names**; `Invoke-Rollback` has **2** cases, `FirewallRule` and
`EnsureWsl`. The other 29 fall to `default { }`. The external install completed only `Preflight`,
so answering `Y` to *"Installation failed. Run automatic rollback? (y/N)"* produced:

```
[11:52:37] [ERROR] Running rollback for completed steps...
[11:52:37] [INFO] Undoing: Preflight
```

and did nothing, because there is no `Preflight` case. **A prompt that offers an action, a log
line that claims it happened, and no mechanism behind either.** Fix: either the prompt states
what rollback can actually undo, or `default { }` logs *"no rollback action defined for
`<step>`"* rather than `Undoing: <step>`. The second is one line and is the honest minimum.
`C:\Program Files\ClawFactory` remaining populated is separately **correct** — Inno owns it —
but the prompt implies otherwise and the user concluded the rollback was broken.

**D7 — accepting the rollback is the one path that never prints the log location.**
`Invoke-WithRollback` writes `"Rollback skipped. Log: $LogFile"` only in the `else` branch. Accept,
and you are never told where the log is. Combined with `Failed to pre-create clawuser stub
(exit=-1)`, which names neither a cause nor a file, the failure path gave the user nothing
actionable. **The measurement that should govern how hard this is worth fixing: forty-one
minutes** — `11:11:19` failure to `11:52:37` rollback answer. That is how long a real person sat
in front of an error about a Linux user account before deciding what to do.

**D8 — `wsl.exe`'s UTF-16LE nulls are stripped on one path and not the other, and the unstripped
one carries the most valuable line in the file.**

```
[wsl:root out] T h e r e   i s   n o   d i s t r i b u t i o n   w i t h   t h e   s u p p l i e d   n a m e .
```

`Update-WslEngine` strips them at `setup.ps1:263`. `Invoke-WslBash`'s `[wsl:root out]` /
`[wsl:root err]` path (`setup.ps1:765-772`) does not. The nulls also make `grep` treat
`install.log` as a **binary file** and silently suppress matches — which it did to one of mine
while reading these artefacts. Same one-line strip as line 263.

---


**What it is.** Windows PowerShell 5.1 decodes a `.ps1` with no byte-order mark using
the system ANSI codepage, not UTF-8. A file saved as UTF-8 without a BOM therefore has
every multi-byte character rendered as its individual bytes reinterpreted as ANSI. An em
dash (`E2 80 94`) becomes three garbage characters.

**The shipped scripts that are UTF-8 without a BOM.** Re-derived 2026-08-29 by scanning
every `.ps1` named in a `Source:` line of the `.iss` `[Files]` section, testing the first
three bytes for `EF BB BF` and counting bytes outside the printable-ASCII range. Ten
`.ps1` files are shipped. **Five carry non-ASCII bytes with no BOM:**

| File | Non-ASCII lines | Customer-visible? |
|---|---|---|
| `resources/rename-agent.ps1` | 5 (lines 4, 10, 21, 25, 29) | **Yes.** Lines 21, 25 and 29 are the `MessageBox` body and title |
| `resources/bootstrap.ps1` | 6 (lines 8, 18, 114, 128, 199, 226) | **Yes.** Lines 128 and 226 |
| `resources/launcher.ps1` | 10 | No. All ten are comments |
| `resources/post-install.ps1` | 3 (lines 158, 187, 220) | No. All three are comments |
| `setup.ps1` | 1 (line 58) | No. Comment |

The other five shipped `.ps1` (`clawfactory-grants.ps1`, `clawfactory-stop.ps1`,
`switch-provider.ps1`, `uninstall.ps1`, `smoke-test.ps1`) carry no non-ASCII bytes at
all and are clean.

**Count of shipped files affected: 5.** This matches the count in the box D completion
close-out and was re-derived independently rather than copied from it.

**The customer-visible locations.** Counted by non-ASCII character, not by line, since a
single line can carry two em dashes:

| Where it lands | Source | Occurrences |
|---|---|---|
| The **"Rename Your Assistant" dialog body**, opened from the Start Menu shortcut of that name | `rename-agent.ps1:21` (2), `rename-agent.ps1:25` (2) | 4 |
| The **title bar of that same dialog** | `rename-agent.ps1:29` (1) | 1 |
| A written `agent.md` inside the sandbox, in the stub-agent explanation | `bootstrap.ps1:128` (1) | 1 |
| A `WARN` line reaching the console and `%ProgramData%\ClawFactory\install.log` | `bootstrap.ps1:226` (1) | 1 |

**Count of customer-visible occurrences: 7**, across 2 files and 4 distinct surfaces.
Each occurrence is a single em dash, `E2 80 94`, three bytes. This also matches the prior
record and was re-derived independently.

**Not affected.** Neither uninstall dialog, measured both ways across two independent
invocations in box D. The `.iss` itself carries zero non-ASCII bytes. The four bundled
`.md` files are read by markdown viewers, not by PowerShell, so their non-ASCII content
is not mojibake and is not in scope.

**Severity.** Cosmetic. Nothing about the sandbox, the firewall, the guards, the gateway
or containment is implicated. The meaning survives; it looks broken. It is worst in the
`rename-agent` dialog, whose only job is to explain a product decision to a customer.

### 2. `README.md` findings that could not be closed

`README.md` is bundled (`.iss:46`) and carries its own Start Menu shortcut (`.iss:186`).
The badge and gate-count corrections made on 2026-08-29 reach a customer only at the next
build. See `docs/POST_RELEASE_DOC_CORRECTIONS_v1.4.4.md`.

**Nothing in `README.md` was left uncorrected.** Every self-describing number in it was
re-derived and is either corrected or confirmed. The open item is not a finding but a
delivery: the corrected file has to be compiled into an artifact before it is true for
anyone who installed v1.4.4.

One related item is genuinely open and is **not** in `README.md`:

- **`resources/launcher.ps1` lines 14 to 20.** A known false claim now **deliberately
  retained in shipped bytes**. It is not one line. It is a seven-line header block
  carrying four separate false assertions. Quoted verbatim, exactly as it stands in the
  file, so this entry can be read without opening it:

  ```
  # launcher.ps1 — desktop shortcut entry point.
  #
  # Wired in by the [Icons] entry in ClawFactory-Secure-Setup.iss. Runs as the
  # end user (not admin) when they double-click the ClawFactory icon. The
  # shortcut starts PowerShell with -WindowStyle Hidden, so this script must
  # never spill console output. All user-facing errors come through a Windows
  # MessageBox dialog.
  ```

  **What is false, assertion by assertion, checked against `ClawFactory-Secure-Setup.iss`:**

  | Assertion | Reality |
  |---|---|
  | "desktop shortcut entry point" | The desktop shortcut's entry point is `{app}\ClawChat.exe` |
  | "Wired in by the `[Icons]` entry" | **No `[Icons]` entry invokes this script.** There is no such entry to be wired in by |
  | "when they double-click the ClawFactory icon" | Double-clicking that icon runs `ClawChat.exe`. This script is not reached |
  | "The shortcut starts PowerShell with `-WindowStyle Hidden`" | `grep -c "WindowStyle Hidden"` over the entire `.iss` returns **0**. No shortcut has ever passed that flag in the current script |

  The last one is the worst of the four, because it is a specific, checkable, operational
  detail that is simply not in the installer at all, and it is the premise for the
  following sentence's rule that the script must never write to the console.

  **It is a candidate for release-notes disclosure as well as for correction**, and that
  is a decision, not a foregone conclusion. The case for disclosing: it is a shipped file,
  it is auditable, "no telemetry, fully auditable PowerShell" is a claim this product makes
  in its own README, and a reader auditing `launcher.ps1` against the `.iss` will find the
  contradiction in about a minute. The case against: the script is unreachable, so the
  block misdescribes something no customer executes, and disclosing it invites a reader to
  weigh a comment on dead code as heavily as a live control. **Not decided here.**

  It was deliberately not corrected on 2026-08-29 because `launcher.ps1` is a shipped
  script and editing it changes shipped bytes. **v1.5 changes shipped bytes anyway, so
  correct it then**, and decide the disclosure question at the same time.

### 3. The tenth build gate

**Specification only. Do not implement in the session that wrote this page.**

**Name.** `encoding`. It becomes the tenth entry in the `gatesPassed` array written into
the build stamp at `scripts/build_release.ps1`, alongside `soul`, `bundle`,
`interpolation`, `worktree`, `studio`, `version`, `persona`, `workspace-soul` and
`rootfs`.

**What it asserts.** For every `.ps1` file named in a `Source:` line of the `.iss`
`[Files]` section: **either the file's first three bytes are `EF BB BF`, or the file
contains no byte outside the range `0x09, 0x0A, 0x0D, 0x20-0x7E`.** A file that satisfies
neither fails the build.

**Why that shape and not "must have a BOM".** Requiring a BOM on every shipped `.ps1`
would fail five files that are correct today and would churn bytes for no reason. The
defect is not the absence of a BOM; it is the combination of a BOM's absence with content
that needs one. The gate is written as that combination.

**Why not "must be ASCII".** That would be a stricter and simpler gate, but it forbids a
legitimate future in which a dialog carries a non-ASCII character deliberately and the
file is saved with a BOM to carry it. The gate should permit the correct thing, not only
the minimal thing.

**What a failing input looks like.** `resources/rename-agent.ps1` exactly as it stands on
2026-08-29: first three bytes are `23 20 72` (`# r`), not `EF BB BF`, and line 21 contains
the byte sequence `E2 80 94`. The gate must name the file, the line and the byte offset,
and it must say which of the two conditions failed, because "no BOM" and "has non-ASCII"
are separately actionable and the fix differs.

**What a passing input looks like.** Two shapes must both pass, and the gate is not
correct until both have been confirmed to:

1. `resources/uninstall.ps1` as it stands: no BOM, no non-ASCII byte. Passes on the
   second condition.
2. Any file whose first three bytes are `EF BB BF`, regardless of what follows. Passes on
   the first condition.

**Calibration, which is not optional.** This gate is a probe for a text-encoding defect,
and the file that holds the gate is itself a `.ps1`. `docs/FAILURE_CATALOGUE.md` entry
10.4 records that the first sweep written to measure this very defect contained the
defect: it held the character it was searching for, as a literal, in a file saved the
same way. **The gate must be written to match on byte values, never on a literal
non-ASCII character in its own source**, and it must be canaried by planting one em dash
in a copy of a clean shipped script and confirming the gate fails on it, before any clean
result from it is believed.

**Where it runs.** Before compilation, with the other pre-build gates. It is a lint on
source text and has no dependency on the worktree or bundle gates, so it can run early;
placing it immediately after the interpolation gate groups the two source-text lints
together.

### 4. A mechanical staleness gate

**Specification only. Do not implement in the session that wrote this page.**

**The problem it solves.** On 2026-08-29 four self-describing numbers in `README.md` were
checked by hand. One was wrong. It had been wrong through five releases, because nothing
re-derives it and a human reading the sentence has no reason to doubt it. Every number
corrected by hand on that day will drift again.

**What it is.** A script that reads the tree, derives each number below from its source,
compares it to the number written in the prose, and fails on a mismatch. **It re-derives;
it never rewrites.** Same discipline as every build gate: fail on drift, never
auto-correct, because a silent rewrite of a prose sentence is worse than a stale one.

**Whether it is a build gate.** Open. It should run in CI or as a `-Check` mode on
demand. Wiring it into `build_release.ps1` would block a release on a documentation
typo, which may or may not be wanted. Decide when implementing.

**The numbers it must derive, and the tree source of each:**

| Number in prose | Where the prose is | Tree source it must be derived from |
|---|---|---|
| Build-gate count ("nine pre-build gates") | `README.md` build section | Count of `^# --- Pre-build gate:` headers in `scripts/build_release.ps1`, cross-checked against the length of the `gatesPassed` array literal in the same file. **Both, and they must agree** |
| Version badge (`v1.4.4`) | `README.md` line 3, twice on the same line | `#define MyAppVersion` in `ClawFactory-Secure-Setup.iss`, cross-checked against the last row of `released-versions.tsv` |
| Smoke-check count ("19 checks") | `README.md` smoke-test section | Count of `Check '` invocations in `smoke-test.ps1` that are **not** inside the `if ($AgentChecks ...)` block. The opt-in count (7) is a second, separately derived number |
| Numbered smoke-check list (items 1 to 19) | `README.md` smoke-test section | The `Check '<name>'` strings in `smoke-test.ps1`, in source order. The gate must compare the **list**, not only its length, because a reordering is invisible to a count |
| **Unsigned** installer size | any doc asserting a build size | The size column of the last row of `released-versions.tsv`. **This is the pre-signing size.** For 1.4.4 it is `440594967` |
| **Signed** installer size | any doc asserting a download size, and the release body | The `size` field of the published GitHub release asset. For 1.4.4 it is `440610608` |
| OpenClaw version pin ("2026.4.27") | `README.md` components section | The pinned version literal in the installer scripts |
| Bundled-file count, wherever asserted | any doc | Count of `Source:` lines in the `.iss` `[Files]` section |
| Agent count ("four agents") | `README.md`, `CLAUDE_ClawFactory.md`, `rename-agent.ps1` dialog | The agent list written by `resources/bootstrap.ps1` |

**A note on where it must read from.** The bundled-file count must come from the `.iss`,
not from a doc that lists bundled files, and the version must come from the `.iss` define,
not from a badge that another doc copied. The whole value of the gate is that it does not
consult prose. A staleness gate that derives one prose number from another prose number
is `docs/FAILURE_CATALOGUE.md` Class 10.

**A note on the two installer sizes, which is why they are two rows and not one.** Two
byte counts for v1.4.4 are in circulation and both are correct, of different artifacts.
Verified by execution on 2026-08-29, not inferred:

| Artifact | Size | SHA-256 |
|---|---|---|
| Unsigned, as the ledger records it | `440594967` | `548562c72d5261bc62d590df03746ea2bb52134a413e10d137b590e589fdcdea` |
| Signed, as published and as it sits in `Output\` | `440610608` | `6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1` |

The published GitHub release asset and the local `Output\ClawFactory-Secure-Setup.exe` are
**byte-identical**: same size and same SHA-256. `Get-AuthenticodeSignature` on that file
returns `Status: Valid`, signer `CN=Bret Mckinney`, countersigned by
`CN=Microsoft Public RSA Time Stamping Authority`. The difference is **15641 bytes**, which
is the Authenticode signature block and its countersigned timestamp appended to the PE.
This confirms the expected explanation rather than assuming it.

**The gate must never compare one against the other**, and must fail loudly if a document
asserts a size without saying which artifact it means. The `~440 MB` in `README.md` happens
to be true of both, which is exactly the kind of coincidence that hides the ambiguity until
someone writes a precise number.

---

#### Sharpening, 2026-08-29: the complete number census, and what re-deriving it taught

**Still specification only. Nothing below was implemented.** The table above was written
from the numbers that were noticed. This section is the result of deriving **every**
self-describing number in the shipped and repository documents from the tree in one pass,
and it changes three of the derivations above.

**The complete census.** Ten numbers, each with the exact derivation the gate must use and
the value it produced on 2026-08-29.

| # | Number | Value on 2026-08-29 | Derivation, exactly |
|---|---|---|---|
| 1 | Build-gate count | **9** | The **length of the `gatesPassed` array literal** in `scripts/build_release.ps1`. See the warning below: the header count does **not** agree, and the previous spec said it must |
| 2 | Bundled-file count | **56** | `grep -c '^Source:'` over `ClawFactory-Secure-Setup.iss`, `[Files]` section only |
| 2b | Bundled **markdown** count | **4** | The `Source:` lines matching `.md"`. `README.md`, `resources/safety-rules.md`, `resources/persona.md`, `resources/orchestrator-prompt.md`. **`SECURITY_FINDINGS.md` is NOT bundled** and at least one close-out has said it is |
| 3 | Smoke-check count, default | **19** | `Check '` occurrences in `smoke-test.ps1` **before** the `if ($AgentChecks ...)` guard (line 317 today) |
| 3b | Smoke-check count, opt-in | **7** | `Check '` occurrences **at or after** that guard. Total in file: **26**. Three numbers, all correct, of different things |
| 4 | **Unsigned** installer size | **440594967** | Size column, last row of `released-versions.tsv` |
| 5 | **Signed** installer size | **440610608** | The `size` field of the published release asset, from the GitHub releases API. Confirmed equal to the length of `Output\ClawFactory-Secure-Setup.exe` |
| 6 | Version literal | **1.4.4** | `#define MyAppVersion` in the `.iss`, cross-checked against the last row of `released-versions.tsv` and against the `v1.4.4` badge on `README.md:3` (which carries it **twice on one line**) |
| 7 | Studio panel count, not-in-this-release | **7** of **11** | `docs/RELEASE_NOTES_v1.4.4.md:29`, `docs/RELEASE_v1.4.4_GITHUB_BODY.md:31`, `validation/MANUAL_CHECKS_studio.md` section 9. **Not derivable from this repository's tree** -- Studio is a separate repository. This row is a cross-document agreement check, not a derivation, and the gate must say so |
| 8 | Mojibake **file** count | **5** of 10 shipped `.ps1` | For each `.ps1` named in a `Source:` line: first three bytes are not `EF BB BF` **and** at least one byte falls outside `09 0A 0D 20-7E`. Hits: `setup.ps1`, `resources/post-install.ps1`, `resources/bootstrap.ps1`, `resources/rename-agent.ps1`, `resources/launcher.ps1` |
| 9 | Mojibake **customer-visible occurrence** count | **7** | Non-ASCII **characters** (not lines) on the four customer-reaching lines: `rename-agent.ps1:21` (2), `:25` (2), `:29` (1), `bootstrap.ps1:128` (1), `:226` (1) |
| 10 | OpenClaw version pin | **2026.4.27** | The pinned version literal in the installer scripts |

**Correction 1 to the spec above: the build-gate cross-check as written FAILS TODAY, and
the reason is not drift.** The previous spec says to count `^# --- Pre-build gate:` headers
and cross-check against the `gatesPassed` array, "**Both, and they must agree**". They do
not. The header count is **8**; the array has **9** entries. Nothing is stale: the header
at `scripts/build_release.ps1:527` reads *"the persona and the COMPOSED workspace SOUL"* --
**one header covering two gates**, `persona` and `workspace-soul`. A gate implemented from
the spec as written would fail the build on a correct tree, on its first run.

This is the second-order form of the defect the whole page is about. The rule *"derive it,
never trust the prose"* was applied, a derivation was written down, and **the derivation
itself was never run.** `docs/FAILURE_CATALOGUE.md` Class 10 is audit instruments carrying
the defect they audit; this is a *specification* carrying it. **The array is the authority;
the header count is advisory and must be reported as a warning, not a failure.**

**Correction 2: number 7 is not derivable and must not pretend to be.** Every other row
reads a file in this repository. The Studio panel count reads three documents that agree
with each other, describing a repository whose source is elsewhere. A gate that treats it
as a derivation is deriving one prose number from another prose number, which the note
above already names as Class 10. It stays in the census because the number has now been
asserted wrongly more than once -- see `docs/FAILURE_CATALOGUE.md` entry 12.2 -- but it is
an agreement check between three named files and must be labelled as one.

**Correction 3: the scanner for numbers 8 and 9 must not use `grep -P`, and must be
canaried before any clean result is believed.** Re-deriving the mojibake census on this
machine, the obvious pattern -- a `grep -cP` with a negated hex character class, run under
`LC_ALL=C` -- returned **0 for all ten shipped scripts**, i.e. a completely clean tree. It
was wrong. `grep -P` on this platform refuses under `LC_ALL=C` with *"grep: -P supports
only unibyte and UTF-8 locales"* and exits **2**, and the surrounding `|| echo 0` in the
loop turned that refusal into a reported zero. The clean result was a **failure to run,
presented as a pass**, on the exact defect class this gate exists to catch.

It was caught only because the preamble rule was applied: an em dash was planted in a copy
of a clean shipped script and the pattern was required to find it **before** the clean
result was believed. It did not. A byte-value scan (`od -An -v -tu1`, filter for values
above 126) found 3 bytes in the canary and 0 in the control, and then reproduced the
published census exactly: 10 shipped scripts, 5 affected, same files, same line numbers.

**Three requirements follow, and they are not optional:**

1. **The gate matches on byte values, never on a regex engine's character classes**, and
   never on a literal non-ASCII character in its own source (already required above, for a
   different reason -- entry 10.4).
2. **The gate carries a planted canary and a clean control, and runs both in the same
   invocation as the real scan.** A canary run separately is a second measurement of a
   different moment.
3. **A scanner that exits non-zero is VOID, never clean.** The `|| echo 0` that swallowed
   the failure is the whole defect. Any harness step that converts a non-zero exit into a
   count must be treated as absent.

#### 4b. The site download-link check. **A POST-RELEASE ASSERTION, not a derivation**

Recorded separately, deliberately. Every number in the census above is derived from bytes
in this repository. **This one is not derivable at all.** It is an HTTP reading against a
surface built from a different repository, and folding it into the staleness gate would put
a network call inside a lint and would let a transient 502 fail a documentation check.

**What it asserts.** After a release is published, and only then: a `HEAD` request to

```
https://github.com/BuzzardsBay/clawfactory-secure-setup/releases/latest/download/ClawFactory-Secure-Setup.exe
```

must return **200**, following redirects, with a `Content-Length` equal to the **signed**
size (census row 5) of the release just published.

**Why the size and not just the 200.** A 200 proves a file is served. Only the size proves
it is *this* release's file. `latest` moves; a stale CDN edge or a failed asset upload can
serve the previous release's binary under a 200 for some time. On 2026-07-21 this project
watched a CDN serve a stale page across 32 consecutive polls.

**Why it belongs to the release, not to the build.** It cannot pass before publication --
the asset does not exist -- so it can never be a pre-build gate. It is the last step of
cutting a release, after the asset is attached, and its failure mode is "the three download
buttons on `clawfactory.app` are 404ing right now", which is a release incident and not a
documentation defect.

**Failure means the obligation in item 6 was broken**, almost always by the asset having
been attached under a different filename. Fix the release, or fix the site -- in the same
window, not next week.

**This assertion has no positive control and cannot easily be given one**, because the
negative case is a real 404 against a public URL. State that limitation rather than
implying the reading is as strong as a gated measurement. The nearest available control is
to request a filename known not to exist and require **404**, in the same run, which proves
the reading distinguishes present from absent. **Do that.** A `HEAD` that returns 200 for
everything, including a name that cannot exist, is measuring a redirect, not an asset.

---

### 5. The `ClawFactory Dashboard` shortcut, card `#311`. **DELETE IT, do not fix it**

Added 2026-08-29 by the documentation-reconciliation job. Card `#311` was raised the same
day at priority 1, **product severity, not documentation severity**.

**What ships.** `ClawFactory-Secure-Setup.iss` `[Icons]`, verbatim:

```
Name: "{group}\ClawFactory Dashboard"; \
  Filename: "{sys}\cmd.exe"; \
  Parameters: "/c start http://127.0.0.1:8787"; \
  WorkingDir: "{app}"; \
  Comment: "Open ClawFactory dashboard in browser (gateway must be running)"
```

A Start Menu entry, shipped in v1.4.4, that opens the browser dashboard in one click, under
hover text that invites it and warns of nothing.

**Why it is a dead end, and this half is not in doubt.** The dashboard is device-pairing
gated — `SUPPORT_MATRIX.md:26`, grounded in the gateway's Ed25519 device-identity connect —
and **the installer ships no pairing flow and no explanation of one.** A first-run user who
clicks it reaches a surface they cannot get past, from a label promising a dashboard.

**Why deletion and not a fix.** Shipping a pairing flow is a feature, and a feature for a
surface nobody has asked for and nobody has measured. Removing five lines from `[Icons]`
costs nothing, removes a one-click dead end from the Start Menu, and leaves the dashboard
reachable by anyone who types the URL. Nothing else in the product references the shortcut.
The `Comment:` string is the only place the product advertises the dashboard at all.

**What deleting it does NOT do.** It does not close the measurement question below, and it
does not make the `:8787` surface safe or unsafe. It removes an invitation, nothing more.

**Scope note.** This changes `[Icons]`, which is shipped bytes, so it cannot be done outside
a build. v1.5 changes shipped bytes anyway.

**The open measurement question is NOT recorded here**, deliberately, because a v1.5
planning page is not what a validation cycle reads. It is in
`docs/VALIDATION_PREAMBLE.md`, under "Open measurements owed by the next validation cycle".

### 6. The site download links are coupled to the asset filename. **A RELEASE OBLIGATION**

Added 2026-08-29. This is not a v1.5 work item; it is a **standing obligation on every
future release**, recorded on the page a person cutting a release is most likely to open.

`clawfactory.app` carries **three** download buttons. Since the 2026-08-29 site change they
no longer point at the release page. All three point at the file:

```
https://github.com/BuzzardsBay/clawfactory-secure-setup/releases/latest/download/ClawFactory-Secure-Setup.exe
```

`/releases/latest/download/<name>` resolves **by filename**. If a release publishes its
asset under any other name, all three buttons return **404**. No gate catches it: the
filename lives in `BuzzardsBay/clawfactory-site`, a different repository, and nothing in
this repository's build reads it.

**The obligation, in one line:** *every release must attach its installer as exactly
`ClawFactory-Secure-Setup.exe`, or the site's three download buttons must be changed in the
same window.*

`OutputBaseFilename=ClawFactory-Secure-Setup` in the `.iss` produces that name today, so
the obligation is satisfied by not changing that line. It is written down because it is
satisfied by accident rather than by a check.

**Verified 2026-08-29**, and this is an HTTP reading, not a tree derivation: a `HEAD` on
the download URL returns `200` with `Content-Length: 440610608`, matching the published
signed asset. The corresponding **post-release assertion** is specified in item 4 below.

### 7. The exit-code census: 14 load-bearing sites in `setup.ps1`, plus 9 outside it

**Added 2026-08-30.** D2 was not a one-off. It is an instance of a pattern — *treating a
return code as proof that a state exists, rather than checking the state* — and this is the
enumeration of every other instance, taken by AST rather than by grep, calibrated against
planted canaries in shapes the file does not already contain, and adjudicated by reading
each site. Method, canary results and the full per-line table are in
`docs/session_reports/2026-08-30_pre_v145_groundwork_closeout.md` §3. The instrument is
committed at `validation/census-exitcode-proof.ps1` so the numbers can be re-derived rather
than believed.

**Counts.** `setup.ps1`: 65 raw AST hits → 16 false positives of the taint model, 1 in dead
code (`Enable-WindowsFeaturesForWsl`, never called) → **48 live sites: 26 verified, 8
unverified but harmless, 14 unverified and load-bearing.** Eight other shipped `.ps1` files:
68 raw hits, 5 load-bearing after adjudication. Thirteen shipped `.sh` files: 4 load-bearing
shapes. Twelve shipped `.js` files: **zero** — every exit code checked there is a
`setpriv`-as-the-agent permission probe, where the exit code *is* the state being asked
about, which is the pattern done right.

**The six that go in v1.4.5** are listed under v1.4.5-B above: `266`, `488`, `502`, `526`,
`923`/`968`, the `Test-WslFunctional` ordering, and `850`.

**The rest are v1.5.** Not because they are milder — two of them are security-shaped — but
because each one widens the changed surface past `Step-EnsureWsl` and converts a two-box
revalidation into a four-box rerun. Listed in descending severity:

1. **Five systemd units are enabled with the result thrown away.** `install-quarantine.sh:140-141`,
   `install-send.sh:190-191`, `install-chat-proxy.sh:87` all use
   `systemctl enable --now <unit> >/dev/null 2>&1 || true`. `enable --now` makes **two**
   claims — *running now* and *comes back after a reboot* — and each installer's live socket
   ping or health probe tests only the first. **Nothing in the product ever checks that
   Guard 1's broker, Guard 2's broker or the gating proxy are enabled at boot.**
   `install-read-fetch.sh:379-386` is the counter-example and says so in its own comment:
   *"`systemctl enable` is routinely written here with `|| true`, which means a unit that
   failed to install looks identical to one that did"*, and it reads back `is-enabled` and
   `fatal`s. Three files should do what the fourth already does. `setup.ps1:1830`
   (`systemctl enable clawfactory-fw.service 2>/dev/null || true`) is the same shape; that
   one has at least been measured to survive a reboot on a validation box, which is a
   measurement, not a check in the code.
2. **`nft flush set ... || true` in the exposure direction.** `clawfactory-read-fetch.sh:72`
   and `clawfactory-toolchain.sh:144`. Both sit directly under a comment reading
   *"Flush first. Every exit after this point is fail-closed."* The `|| true` breaks exactly
   that property: if the set exists (checked) but the flush fails (not checked), the
   previously-allowed addresses stay in the live set and the script goes on to add the new
   list and report the new count. A revoked host stays reachable while the panel says it was
   revoked. Low probability, wrong direction, and **the code disagrees with its own
   comment**, which in a security product is a defect in the audit trail.
3. **`setup.ps1:2922`, `Step-InstallTurnGate`.** `install-turn-gate.sh`'s own final check —
   *"Verify passthrough (a non-agent subcommand must still work)"* — downgrades to a WARN on
   failure, so the script exits 0 and `$rc -ne 0` never fires. A shim that replaced
   `/usr/bin/openclaw` and then does not work is indistinguishable from one that does. The
   product claims no caller can launch an ungated turn; that claim rests on this exit code.
4. **`resources/switch-provider.ps1:349`.** `if ($fwExit -ne 0) { Write-Warning ... }` and
   then, unconditionally, `Write-Host "  [x] egress allowlist updated (backend
   auto-detected)"`. **The success tick prints whether or not the firewall was updated.**
   After a provider switch that means the agent may have no route to the new provider, the
   old provider's addresses may still be allowed, and the user has been shown a green check
   for both. Same file, line `148`: the `auth-profiles.json` key write warns and continues,
   leaving the gateway on the old key.
5. **`resources/clawfactory-grants.ps1:588`, `Sync-GovernorMirror`.** `if ($r.ExitCode -eq 0)
   { $script:CF_LastMirroredCaps = $payload }`. The bash is `;`-chained with no `set -e` and
   its **last** command is `chmod 644`, so the exit code reports the chmod, not the
   `base64 -d > /etc/clawfactory/governor.json` that does the work. On a failed write the
   redirect has already truncated the file, `chmod` still succeeds, the module caches the
   caps as mirrored, and **never retries** — so a user who changes their spend cap in Studio
   gets a permanently blocked agent (`clawfactory-turn-gate.sh:53` emits
   `spend_config_bad`) with no self-heal. Fail-closed, which is the right direction, and
   still wrong.
6. **`setup.ps1:2717`** (auth-profile registration warns and continues; the key is then
   written for a profile that does not exist), **`setup.ps1:1309`** (the
   `-u clawuser -- true` boot test fails, the code falls back to root, WARNs, and nothing
   re-checks that the default user is `clawuser`), **`setup.ps1:2697`** (default model),
   **`resources/bootstrap.ps1:279`** (per-agent auth-profile fan-out).
7. **`setup.ps1:1852`, `Step-EgressFirewall`.** On failure it logs ERROR and `return`s
   without a checkpoint and **without throwing**, so the install continues. This one *is*
   caught: `install-send.sh:194` runs `clawfactory-fw-assert.sh || fatal` and
   `Step-InstallSend` throws. But that is twenty-one steps later, and the whole OpenClaw
   install, the gateway bring-up, the turn-gate and the SOUL freeze all run in between with
   no firewall. This is the preamble's *"WHEN is it needed"* question and it has an answer
   nobody wrote down.

**What the census cannot catch** is in the close-out §3.5, measured rather than asserted:
two canaries in shapes that cross a boundary the AST cannot follow — an exit code written to
a file and read back later, and an exit code passed across a parameter binding — were both
planted and both **missed**, with the total unchanged at 65.

**Do not fix any of these in the v1.4.5 build.** They are listed so that the v1.5 build has
a work list rather than a rediscovery.

### 8. Rewrite D1. It is inert as shipped in v1.4.5, and shipped saying so

**Added 2026-08-31 from the v1.4.5 validation run.** Not a regression and not a v1.4.5
blocker — the operator's decision was to ship v1.4.5 with D1 inert, because D2, D4 and D5
carry the whole user-visible fix without it. This entry exists so the rewrite starts from
evidence rather than from the design that produced the inert version.

**What is wrong.** `Test-WslRebootPending` gates on the typed `FeatureState` of
`VirtualMachinePlatform`, `Microsoft-Windows-Subsystem-Linux` and `HypervisorPlatform`,
firing only on `EnablePending` / `DisablePending`. On Windows 11 24H2 that value is never
emitted: `VirtualMachinePlatform` reads `Enabled` both before and after the restart. The
signal is identical on both sides of the thing it is supposed to detect.

**How it came to be built on an unproduced value.** The fix was proved by injecting a
synthetic `@{VirtualMachinePlatform='EnablePending'}` hashtable through the function's own
`$States` parameter (rows `D1.1`/`D1.2`/`D1.3` of `validation/verify-v145-fixes.ps1`). That
proves the comparison works. It does not prove Windows ever emits that value, and the run
that would have asked was never taken. *A probe is calibrated against a rigged input; a run
is not.* See `docs/FAILURE_CATALOGUE.md` entry 15.1.

**The two signals the run measured working.** Both were read on `cfv-186` in the reproduced
state, with the restart as the control:

1. **CBS `RebootPending`** — `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based
   Servicing\RebootPending` — read **`True` before** the restart and **`False` after**. D1
   reads it, logs it, and refuses to gate on it, on the ground that it is routinely present
   on a healthy machine after any Windows Update. That concern is real, and it argues for
   **combining** the key with a WSL-specific condition, not for discarding it in favour of a
   value that is never set.
2. **`wsl --status`'s OUTPUT.** It says in plain text `WSL2 is unable to start since
   virtualization is not enabled on this machine` **while the call exits zero**. The product
   reads the exit code and discards the output — the same mistake D1 was written to correct,
   committed one call later, at the `$kernelOk` assignment immediately below the gate.

**A second, independent problem the rewrite has to solve.** Even with a working signal, the
branch is unreachable on the first-run path as the file stands: `Step-EnsureWsl` calls
`Update-WslEngine` before consulting the gate, and after that call `wsl --status` exits 0.
Moving the gate, or gating on `Update-WslEngine`'s own captured output, is part of this item
and not a separate one.

**A non-English-prose constraint still applies.** The original reason for rejecting a match
on *"Changes will not be effective until the system is rebooted"* was sound: an
English-sentence gate silently stops working on every other Windows language. Signal 1 is
language-independent. Signal 2 is not, and if it is used it must be as corroboration behind
a language-independent condition, or via `wsl --status`'s exit code plus a structured read,
never as the sole gate.

**Scope note.** `setup.ps1:1175`'s call site and the resume-path loop guard at `setup.ps1:1121`
are both currently unreachable for the same reason, and the `Restart-Computer` fall-through in
item 9 below shares the code path. Do them in one edit.

### 9. The fall-through after `Restart-Computer -Force`

**Added 2026-08-31 from the v1.4.5 validation run.** Observed on a voided box-F attempt that
reached the reboot branch:

```
[INFO]  Restart required: wsl --status still reports the kernel unavailable after wsl --install
[INFO]  Scheduled Task 'ClawFactory-Resume' registered
[INFO]  Resume flag written
[INFO]  Silent mode: skipping restart-required dialog; rebooting now.
[INFO]  Step 3: Writing initial /etc/wsl.conf ...
[ERROR] Install failed: Failed to write /etc/wsl.conf
[ERROR] Top-level handler caught: Failed to write /etc/wsl.conf
```

`Restart-Computer -Force` **initiates** a restart and returns; it does not halt the script.
`Step-EnsureWsl` ends with `Invoke-WslRebootAndResume` and the main body is a flat sequence,
so in the seconds before Windows terminates the process the installer runs two further steps
against a machine with no WSL and logs a **fatal error immediately before what is meant to be
a pause**.

**Pre-existing, not a v1.4.5 regression.** Severity **low**: the resume flag and the scheduled
task are both written *before* the fall-through, so the restart-and-resume contract is not
broken; the damage is a misleading log entry on a path §4.1 of the validation close-out shows
is rarely reached. But **D1 adds a second call site with the same shape** at `setup.ps1:1176`,
and that one is mid-function, so a fall-through there would also run the `$kernelOk` test and
could register the resume task twice. That site is currently unreachable, which is the only
reason this is not worse — and it stops being true the moment item 8 is done. **Fix item 9 in
the same edit as item 8, or before it.**

---

## Carried, not scheduled

These are open conditions, not v1.5 work items. They are here so that v1.5 planning does
not rediscover them as new.

### `G2.6`, card `#305`

The post-approval payload-binding comparison, the end-to-end "the approved bytes are the
bytes that arrived" check, **has never been measured on any release of this product, on
any machine.** The surrounding mechanism is proven and enumerated by name: enqueue,
approval, single-use approval, payload hash binding at approval time, receipt, staging
purge, and refusal of a replayed approval.

The reason it was never measured is **a rig transport limitation, stated in those
terms**, and not a product finding: the broker correctly refuses cleartext against a plain
sink, and the bundled runtime will not trust a throwaway authority against an encrypted
one, so nothing ever arrived and there was nothing to compare. Closing it needs a rig that
can terminate a real encrypted transport with an authority the bundled runtime trusts.

### `#261`, intermittent GitHub-family fetches

With the toolchain toggle on, a GitHub-family fetch may intermittently fail and succeed on
retry. Measured across eight hosts: four at 12/12, `api.github.com` at 6/12. **The
mechanism is INFERRED and is labelled so in the sentence that makes the claim.** The split
is measured; the cause is not. It does not affect the provider route, which measured 12/12
with a control at 0/12 in the same run.

---

## Undecided

**These are held open pending the first external install and are not to be decided from
inside a build session.** No recommendation is attached to any of them, deliberately.
A build session sees the product from inside its own construction and is the worst
available vantage point for judging what a person who has never seen it needs.

- **The Studio chat panel.** UNDECIDED.
- **The remaining "not in this release" Studio panels. There are SEVEN of them, not six.**
  UNDECIDED. The count is re-derived from `docs/RELEASE_NOTES_v1.4.4.md:29` and
  `docs/RELEASE_v1.4.4_GITHUB_BODY.md:31`, both of which say seven of Studio's eleven
  panels are not in this release, and from `validation/MANUAL_CHECKS_studio.md` section 9.
  **This exact off-by-one has now occurred twice.** The v1.4.4 release-prep close-out
  section 1.2 is titled "The card names six not-in-this-release panels. There are seven",
  and the handoff document that produced this backlog reproduced the same six. The number
  is written here so the third occurrence has somewhere to be checked against.
- **The skills model.** UNDECIDED.
