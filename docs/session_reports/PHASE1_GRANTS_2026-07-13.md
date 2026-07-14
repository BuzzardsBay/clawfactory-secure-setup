# Phase 1 — Grants substrate + spend governor (v1.1 "Workbench")

**Date:** 2026-07-13
**Authored against:** `docs/session_reports/PHASE0_RECON_2026-07-13.md` (commit `d37be47`). The three locked Phase 0 decisions (Studio branch A; mount = drvfs; governor = meter + turn-gate) are inputs here, not relitigated.
**Scope:** Task 1.0 automount STOP-gate, then the Grants substrate (ledger, workspace mount/revoke engine, launcher replay, Kill Switch, spend meter + turn-gate) and smoke coverage. No UI (Studio consumes this in Phase 2).
**Evidence standard:** verbatim command output in fenced blocks; load-bearing statements labeled VERIFIED / INFERRED / GENERAL.
**Target of live testing:** the running install on this machine (WSL2 Ubuntu, `clawuser`, OpenClaw 2026.4.27, gateway on 127.0.0.1:8787). The dashboard was never opened; gateway inspected only via curl/CLI.

---

## TASK 1.0 VERDICT — **(B) ENVIRONMENT DRIFT** — DONE

**The installer is correct. The live machine drifted after install.** `automount=false` is written correctly and no install step clobbers it; the observed `enabled=true` is a post-install change on Bret's daily driver, not an installer defect.

**Evidence 1 — the installer writes `enabled=false` correctly** (`setup.ps1`, `Step-ConfigureWslConf`, VERIFIED):
```
[automount]
enabled=false

[boot]
systemd=true

[network]
generateResolvConf=true
```
(heredoc at setup.ps1:1038-1047, base64-written to `/etc/wsl.conf`.)

**Evidence 2 — no step clobbers `[automount]` afterward** (VERIFIED). The only later writer, `Step-SetDefaultUser` (setup.ps1:1101-1102), *appends* `[user]` and never touches `[automount]`:
```
sed -i '/^\[user\]/,/^$/d' /etc/wsl.conf
printf '\n[user]\ndefault=clawuser\n' >> /etc/wsl.conf
```
`New-ClawUserAndSetDefault` (setup.ps1:505-508) does the same `[user]`-only append and runs *before* `Step-ConfigureWslConf` (which overwrites the whole file). Execution order (setup.ps1 runner): `Step-ConfigureWslConf` → `Step-RestartWsl` → `Step-CreateClawUser` → `Step-SetDefaultUser`. No `[automount]` rewrite exists after Step 3.

**Evidence 3 — the step completed on this machine** (`C:\ProgramData\ClawFactory\checkpoint.json`, VERIFIED):
```json
"completedSteps": [ "Preflight","EnsureWsl","ConfigureWslConfig","WslConf","WslRestart",
  "CreateClawUser","DefaultUser","Docker", ... "AgentBootstrap", ... ]
```
```
install.log:17: [2026-05-26 16:23:38] [INFO] Step 3: Writing initial /etc/wsl.conf (automount off, systemd on).
install.log:29: [2026-05-26 16:23:44] [INFO] Step 5b: Setting 'clawuser' as default WSL user + restarting.
```

**Evidence 4 — live state is `true`, 7 weeks later** (`/etc/wsl.conf` now, VERIFIED):
```
[automount]
enabled=true

[boot]
systemd=true

[network]
generateResolvConf=true
[user]
default=clawuser
```
Install ran 2026-05-26; this machine is Bret's daily driver; `enabled=true` on 2026-07-13 with the installer proven to write `false` ⇒ **post-install drift** (a manual edit, a WSL/Windows update, or another tool re-enabled it). The file's formatting (no blank line before `[user]`) also differs from what the installer's `printf` produces, consistent with an external rewrite.

### What was fixed (the real defect: no readback) — DONE
Even though the installer *wrote* the setting, it **never read it back** — so drift or a botched write would go undetected. That silent-success gap is the actual defect and is closed. Added `Assert-WslAutomountDisabled` (setup.ps1), which reads `/etc/wsl.conf` back and **fails loud (throws, non-zero exit, no checkpoint)** if automount is not verifiably disabled. Called (a) right after the write in `Step-ConfigureWslConf`, and (b) after the *final* WSL restart in `Step-SetDefaultUser`:
```powershell
$rc = Invoke-WslBash -Script $check -User 'root'
if ($rc -ne 0) {
    Write-Log ERROR "AUTOMOUNT VERIFICATION FAILED ($Context): ... P0 file-isolation failure. Refusing to continue; no checkpoint written."
    throw "wsl.conf automount verification failed ($Context): expected '[automount] enabled=false' ..."
}
```
Readback logic verified in isolation (temp files, never the live wsl.conf), VERIFIED:
```
enabled=false   -> rc=0  PASS (automount disabled)
enabled=true    -> rc=1  FAIL-LOUD (would throw)
automount absent-> rc=1  FAIL-LOUD (would throw)
```
setup.ps1 parses clean after the edit. The existing runtime smoke check is also wired and now surfaces the true state loudly (Task 1.5 #8).

### Recommendation on Bret's machine
**Do not auto-flip.** Per the Task 1.0 directive, the flip is Bret's call — losing `/mnt/c` may break his other WSL workflows. To restore the isolation guarantee he can, in an elevated shell: edit `/etc/wsl.conf` to `enabled=false`, `wsl --shutdown`, restart. Until then, **mount-isolation cannot be end-to-end verified on this box** (see BLOCKED) — the grant engine was built and tested on the drvfs mechanism itself, which is orthogonal to whether `/mnt/c` is also present.

**Gate outcome:** automount IS reliably enforceable (installer correct + readback now fails loud) ⇒ the grants model is not theater ⇒ proceeded to Tasks 1.1–1.5.

---

## TASK 1.1 — Grants ledger — DONE

`C:\ProgramData\ClawFactory\grants.json` (alongside `checkpoint.json`), one ledger for all three grant types. Read-append-write mirrors the checkpoint convention. **Schema** (documented in the file header):

| field | meaning |
|---|---|
| `id` | stable slug (unique) |
| `type` | `workspace` \| `skill` \| `domain` |
| `label` | human-readable |
| `created_at` | ISO-8601 |
| `mode` | workspace: `rw`\|`ro`; null for skill/domain |
| `target` | Windows path \| plugin id \| hostname |
| `depends_on` | array of grant ids (e.g. skill → its domain grants) |
| `active` | bool |

`skill`/`domain` are DEFINED now (so Phase 3 does not migrate the file) but UNUSED in v1.1. Helpers: `Add-Grant`, `Remove-Grant` (soft = mark inactive; preserves audit trail), `Get-Grants`, `Get-ActiveGrants [-Type]`. Last-write-wins (no locking, per spec).

**Audit log:** there was **no pre-existing runtime audit log** (`install.log` = install-time via `Write-Log`; `launcher.log` = launch-state only; OpenClaw's `~/.openclaw/logs/config-audit.jsonl` is WSL-side and OpenClaw-owned). Rather than write grant events into an unrelated log, I followed the established "one append-only log per subsystem in `ProgramData\ClawFactory`" convention with `grants-audit.log` (JSON-lines, atomic tmp+rename — same write pattern as `launcher.ps1`). This is flagged in SURPRISES.

**Evidence** (ledger tests, ledger redirected to a scratch dir so ProgramData stays clean, VERIFIED):
```
== Task 1.1 ledger ==
  PASS  Get-Grants returns 3
  PASS  Get-ActiveGrants -Type domain returns 1
  PASS  skill grant carries depends_on
  PASS  workspace grant has mode=rw
  PASS  skill grant mode is null
  PASS  Remove-Grant deactivates
  PASS  active count now 2
  PASS  removed grant still in ledger (soft)
  PASS  audit log has grant.add lines
```

---

## TASK 1.2 — Workspace grant / revoke engine (drvfs) — DONE

Mechanism (Phase 0 VERIFIED): `mount -t drvfs '<WinPath>' /workspaces/<slug> -o metadata,uid=1000,gid=1000[,ro]`, as root, clawuser=uid/gid 1000. Forward-slash Windows paths (backslashes are eaten crossing PowerShell→wsl→bash — Phase 0 lesson).

- **`Grant-Workspace -Path -Mode`**: resolves the path (junction/symlink aware via `.Target`), runs the deny list on the RESOLVED path, generates a deterministic slug (`leaf-<sha8>`), `mkdir -p` + mount, records the grant, audit-logs. **Idempotent**: an already-active grant for the same resolved path is a reported no-op, not a double mount.
- **`Revoke-Workspace -Id`**: unmount + `rmdir` mountpoint + mark inactive + audit-log. Never throws on a stale/already-gone mount.
- **Deny list** (validated on the RESOLVED path): drive roots and the user-profile root (exact); Windows / Program Files / Program Files (x86) / ProgramData / AppData (Roaming+Local) / the ClawFactory install dir (prefix). Rejections carry a clear message pointing at a project folder.
- **`Test-Grants`**: per active workspace grant → `{pathExists, mountLive, state}` (`ok`|`not-mounted`|`broken-path`) for Phase 2's broken-grant UI.
- **OneDrive / UNC / mapped drives** (Phase 0 open items): `Grant-Workspace` emits a `Write-Warning` when the resolved path is under a OneDrive root (on-demand placeholder files untested) or is UNC/mapped (untested). It does not silently allow them without a warning.

**Evidence** (full engine harness, one real transient mount, then cleaned; VERIFIED):
```
== Task 1.2 deny list ==
  PASS  deny C:\ (drive root)
  PASS  deny ProgramData (prefix)
  PASS  deny USERPROFILE root (exact)
  PASS  deny Windows (prefix)
  PASS  deny AppData subfolder (prefix)
== Task 1.2 workspace grant/revoke (real drvfs mount) ==
  PASS  grant returned with id
  PASS  Test-Grants shows 1 active ws
  PASS  grant state ok
  PASS  mount live
  PASS  clawuser reads seed through mount
  PASS  idempotent re-grant same id
  PASS  still exactly 1 active ws
  PASS  after revoke: 0 active ws
  PASS  mount gone after revoke
RESULT: 27 pass, 0 fail
```
(The mount as it appears in the WSL mount table during the test:)
```
C:/Users/bmcki/Documents/ClawGrantTest on /workspaces/clawgranttest-<hash> type 9p
  (rw,...;metadata;uid=1000;gid=1000;...)
```

---

## TASK 1.3 — Launcher replay + Kill Switch — DONE

- **Replay** wired into `resources/launcher.ps1` right after `Start-Gateway` (the layered gateway-start site). It dot-sources the grants lib and calls `Invoke-GrantReplay`, fully wrapped so a broken/absent lib or a vanished folder logs-and-skips and **never blocks gateway start**. A grant whose Windows path has vanished is marked broken (audit-logged) and skipped.
- **Kill Switch** (`resources/clawfactory-stop.ps1`) extended: after stopping containers + gateway it calls `Invoke-GrantKillUnmount` to unmount every active workspace mount. **Kill ≠ revoke** — grants stay active and replay on next start; the script now says so to the user.

**Evidence — including a REAL `wsl --shutdown`** (VERIFIED). Mount table captured at each step:
```
== grant + baseline ==
  [after grant] C:/Users/bmcki/Documents/ClawReplayTest on /workspaces/clawreplaytest-038418d3
  PASS  mount live after grant
== Kill Switch unmount (kill != revoke) ==
  [after kill]                              <-- mount gone
  PASS  kill unmounted 1
  PASS  mount gone after kill
  PASS  grant STILL active after kill (kill!=revoke)
== Replay (simulated loss = post-restart state) ==
  [after replay] C:/Users/bmcki/Documents/ClawReplayTest on /workspaces/clawreplaytest-038418d3
  PASS  replay remounted 1
== REAL wsl --shutdown + restart + replay ==
  [before shutdown] C:/Users/bmcki/Documents/ClawReplayTest on /workspaces/clawreplaytest-038418d3
  running: wsl --shutdown ...
  [after shutdown+boot (expect gone)]       <-- mount gone (shutdown drops drvfs mounts)
  PASS  mount GONE after real wsl --shutdown
  [after replay (expect back)] C:/Users/bmcki/Documents/ClawReplayTest on /workspaces/clawreplaytest-038418d3
  PASS  replay after real restart remounted 1
  PASS  clawuser reads seed through replayed mount
RESULT: 11 pass, 0 fail
```
**Operational note (SURPRISES):** the `wsl --shutdown` also killed the WSL-Host keepalive session (the v1.0.2 flap fix). The gateway briefly cycled until I re-triggered the `ClawFactory WSL Host` scheduled task; it was then confirmed stable and restored (see Resource ledger).

---

## TASK 1.4 — Spend governor: metering + turn-gate — DONE

- **Meter** (`Get-Spend` → `Get-SpendStatus`) sourced from OpenClaw's native `openclaw gateway usage-cost --json`, summing `totalCost` for today and the current calendar month. **On any failure (command missing / non-zero / schema change / unparseable) it returns `unknown` with NULL amounts — `$0.00` is never faked from a broken source.**
- **Caps**: `ProgramData\ClawFactory\governor.json`, defaults **$5/day, $50/month, warn 80%**, editable.
- **Turn-gate** (`Test-TurnAllowed`): before a turn, compares spend to caps. Blocks at/over a cap; if the meter is `unknown` it **fail-safe blocks** (cannot prove under-budget). Enforcement is at **turn granularity, not per-call** — an in-flight turn can overshoot; the user-facing copy says so and does not claim a hard per-call guarantee.
- **`Get-SpendStatus`** returns `{today, month, caps, pct_of_cap, state}`, `state ∈ ok|warning|blocked|unknown`.

**Interception point (stated VERBATIM, per spec):** Studio launches turns through the CLI path in
`ClawFactory-Studio/backend/src/services/chat.ts`, function `runOpenClawAgentTurn`, which spawns:
```js
const cmd = `${env} openclaw agent --json --message "$(cat)"`;
```
Phase 2 routes that spawn through **`Invoke-GatedAgentTurn -Agent -Message`** (or calls `Test-TurnAllowed` immediately before spawning and refuses if `-not allowed`). I did **not** modify Studio source — that is Phase 2, and this job is "no UI". The PowerShell wrap + the exact call site are the handoff.

**Evidence** (live meter + gate, VERIFIED):
```
== Task 1.4 governor ==
  PASS  spend today is numeric
  PASS  state not unknown (meter works)
    spend today=0 month=27.0788 state=ok pct=54.2
  PASS  cap=0 -> turn blocked
  PASS  high cap -> turn allowed
```
(month $27.08 / $50 cap = 54.2%, state `ok` < 80% warn.)

**Refinement of a Phase 0 finding (SURPRISES):** `usage-cost --json` is a **gateway WebSocket call**, not a pure log read — it fails when the gateway is down (`Error: gateway closed (1006 ...)`). So the meter is unavailable when the gateway is down; `Get-Spend` correctly returns `unknown` → the turn-gate fail-safe blocks. Verified during a transient gateway-down window (meter → `unknown`) and again once the gateway was healthy (meter → real numbers).

---

## TASK 1.5 — Smoke test extensions — DONE

Extended `smoke-test.ps1` from 11 → **19 checks**; the new ones are `-RequiresWsl` (SKIP under SYSTEM) and isolate their ledger/governor to a temp dir (real ProgramData untouched); the drvfs mount is real and cleaned up. Docs corrected (11→19 in README; 7→19 in CLAUDE_ClawFactory.md; "seven-check"→"smoke test" in CONTRIBUTING).

**Full run against the live install (VERIFIED):**
```
        /etc/wsl.conf automount -> 'enabled=true'  (required: enabled=false)
        WARNING: automount is NOT disabled -- the agent can reach all of C:\ via /mnt/c.
  FAIL  WSL automount disabled (file-isolation guarantee)
  PASS  Four agent.md files present
  PASS  AgentBootstrap checkpoint recorded
  PASS  Gateway responds 200 on loopback
  PASS  Firewall inbound-deny rule on 8787
  PASS  Orchestrator SOUL hash substituted
  PASS  auth-profiles.json present for all 5 agents
  PASS  .wslconfig has vmIdleTimeout=-1
  PASS  WSL Host scheduled task registered and enabled
  PASS  Egress firewall clawfactory chain present in nft ruleset
  PASS  OpenClaw build deps present (make g++ cmake python3)
  PASS  Grants library present
  PASS  Grant: workspace mount present after grant
  PASS  Grant: deny-list rejects drive root C:\
  PASS  Grant: Kill Switch unmounts but keeps grant active
  PASS  Grant: replay remounts after loss (post-restart path)
  PASS  Grant: mount gone after revoke
  PASS  Governor: meter returns numeric spend, state != unknown
  PASS  Governor: turn-gate blocks when cap = 0

Result: 18 pass, 1 fail, 0 skip
```
The single FAIL is check #8 (automount) — the known drift on Bret's box, now surfaced loudly instead of buried (Task 1.5 #8). Every new grants/governor check passes. Smoke check #4 uses **simulated** mount-loss (kill→replay), not a real `wsl --shutdown`, deliberately: baking a VM restart into a routine diagnostic would restart the user's gateway on every run. The real-shutdown replay is proven above (Task 1.3).

---

## SURPRISES

1. **`usage-cost --json` is a gateway WebSocket call, not a log read.** Phase 0 implied the meter reads session logs; in fact it connects to the gateway (`ws://127.0.0.1:8787`) and errors `gateway closed (1006)` when the gateway is down. Consequence: the meter is only available while the gateway is up; handled via `unknown` → fail-safe block, but Phase 2's live cost meter must tolerate `unknown` gracefully.
2. **`wsl --shutdown` drops the flap-fix keepalive.** The v1.0.2 stability fix (persistent WSL session held by the `ClawFactory WSL Host` scheduled task) does NOT auto-restore after a mid-session `wsl --shutdown` until that task next fires; the gateway cycles in the meantime. Re-triggering the task restores stability. Relevant to any tooling that shells `wsl --shutdown`.
3. **No pre-existing runtime audit log** existed. Created `grants-audit.log` (per-subsystem convention) rather than overload `install.log`. Documented, not a second logging *system*.
4. **`ClawFactory-Studio` is not a git repo** (Phase 0). The required `ARCHITECTURE.md` container-claim fix was applied to the file but **cannot be included in this repo's commit** — it is a working-tree edit in the sibling directory. See BLOCKED.
5. **Smoke-count docs were inconsistent** *before* this job: README said 11, `CLAUDE_ClawFactory.md` said 7, `CONTRIBUTING.md` said "seven-check". All three now unified to 19 (with count history noted).
6. **PowerShell single-object unwrap.** `Get-ActiveGrants`/`Test-Grants` return arrays, but PS unwraps a 1-element return to a scalar; callers must wrap count checks in `@(...)` under StrictMode. Noted in the Phase 2 handoff.

---

## BLOCKED

1. **End-to-end mount ISOLATION** (agent cannot see `/mnt/c`) cannot be verified on this box: automount is drifted to `true` and — per the Task 1.0 directive — I did not flip it on Bret's daily driver. The drvfs grant *mechanism* is fully tested; the *isolation* half needs a box with `automount=false`. Same box is needed for a clean-install run of the new fail-loud readback.
2. **Real `wsl --shutdown` in routine smoke** intentionally NOT added (would restart the user's gateway every diagnostic run). The real-shutdown replay is proven once here (Task 1.3); routine smoke uses the identical post-restart state via simulated loss.
3. **`ClawFactory-Studio/docs/ARCHITECTURE.md` fix not committable** — Studio is not a git repo, so it is not part of the `git commit` below. The edit is applied to the working file; committing it requires `git init` in that repo (Bret's call) or landing it when Studio is versioned in Phase 2.
4. **OneDrive on-demand/placeholder files and mapped network drives** remain untested (Phase 0 carryover — no dehydrated file / mapped drive available). The engine WARNS on both rather than silently allowing.
5. **ProgramData write-ACL for the non-admin user** (Studio runs as the user; `grants.json`/`governor.json` live under `ProgramData\ClawFactory`, created by the admin installer) was not verified end-to-end from a non-admin context. Flagged for Phase 2.

---

## PHASE 2 HANDOFF — exact signatures Studio will call

Load: dot-source `{app}\resources\clawfactory-grants.ps1`. **Wrap count checks in `@(...)`** (PS single-object unwrap). All functions are Windows PowerShell 5.1 compatible.

```
Get-Grants
  -> PSCustomObject[]  (every grant, all types)
     each: { id:string; type:'workspace'|'skill'|'domain'; label:string;
             created_at:string(ISO8601); mode:'rw'|'ro'|$null; target:string;
             depends_on:string[]; active:bool }

Get-ActiveGrants [-Type workspace|skill|domain]
  -> PSCustomObject[]  (active subset, optionally filtered)

Grant-Workspace -Path <string> [-Mode rw|ro (default rw)]
  -> the grant object (as above).  THROWS with a user-facing message on deny-list
     rejection or a non-existent path. Idempotent: an already-active grant for the
     same resolved path returns that grant (no double mount). Emits Write-Warning
     for OneDrive/UNC/mapped paths.

Revoke-Workspace -Id <string>
  -> $true (unmounted + mountpoint removed + grant marked inactive; audit-logged).
     Never throws on a stale/already-gone mount; returns $false only if no such id.

Test-Grants
  -> PSCustomObject[]  (per ACTIVE workspace grant)
     each: { id; label; target; mode; mountpoint:'/workspaces/<slug>';
             pathExists:bool; mountLive:bool; state:'ok'|'not-mounted'|'broken-path' }

Get-SpendStatus
  -> { today:double|$null; month:double|$null;
       caps:{ daily_cap_usd:double; monthly_cap_usd:double; warn_pct:int };
       pct_of_cap:double|$null;
       state:'ok'|'warning'|'blocked'|'unknown' }   # unknown = meter source broke (NOT $0.00)
```

Also available (used by launcher/kill-switch/turn-gate; Studio may call directly):
```
Test-TurnAllowed            -> @{ allowed:bool; state:string; message:string }   # fail-safe: unknown => blocked
Invoke-GatedAgentTurn -Agent <string> -Message <string>
                            -> { blocked:bool; state; message; output; exit }    # gates, then runs the turn
Invoke-GrantReplay          -> { replayed:int; broken:int; alreadyMounted:int }  # launcher calls this at gateway start
Invoke-GrantKillUnmount     -> int (count unmounted)                             # Kill Switch calls this
```

**Turn-gate wiring for Phase 2:** route `chat.ts`'s `runOpenClawAgentTurn` spawn
(`openclaw agent --json --message "$(cat)"`) through `Invoke-GatedAgentTurn`, or call
`Test-TurnAllowed` and refuse before spawning. State clearly in Studio's UI that the cap is
enforced per-turn (an in-flight turn can overshoot).

---

## END-OF-SESSION GATE

### 1. Task accounting
| Task | Status |
|---|---|
| 1.0 Automount truth (STOP gate) | **DONE** → verdict **(B) drift**; fail-loud readback added |
| 1.1 Grants ledger | **DONE** (9/9) |
| 1.2 Workspace grant/revoke engine | **DONE** (27/27 incl. deny list + real mount) |
| 1.3 Launcher replay + Kill Switch | **DONE** (11/11 incl. real `wsl --shutdown`) |
| 1.4 Spend governor meter + turn-gate | **DONE** (meter live; cap=0 blocks) |
| 1.5 Smoke test extensions | **DONE** (19 checks; 18 pass / 1 fail = known automount drift) |

### 2. Resource ledger (created/mounted/started → proof reverted)
- **drvfs mounts** at `/workspaces/<slug>` created across the 1.2/1.3/1.5 tests → every one `umount`ed + mountpoint removed. Final proof: `mount | grep workspaces` → *"no /workspaces mounts (clean)"*.
- **Real Windows test folders** `Documents\ClawGrantTest`, `Documents\ClawReplayTest`, `%USERPROFILE%\ClawSmokeGrantTest` → all `Remove-Item`d. Proof: *"test folder removed (clean)"* / *"no smoke test folder (clean)"*.
- **Real ProgramData ledger untouched:** all tests redirected `grants.json`/`governor.json`/`grants-audit.log` to scratch/temp. Proof: *"no real grants.json (smoke used temp - clean)"*.
- **`wsl --shutdown`** (Task 1.3 replay test) restarted the WSL VM. Restored: re-triggered `ClawFactory WSL Host` scheduled task (State=Running), restarted the gateway via the three-tier logic (NOT the launcher → no dashboard). Final verified state: `gateway_http=200`, `keepalive_sleep_procs=2`, Docker `OK`, gateway PID stable with growing uptime. (Unavoidable side effect: the gateway's uptime counter reset; it is healthy.)
- **Studio backend / dashboard:** not launched; dashboard never opened.
- **Scratch scripts** (`test_grants.ps1`, `test_replay.ps1`, `test_automount_readback.sh`, etc.) live only in the session scratchpad → removed (see git section).

### 3. Delta security sweep
- **Egress firewall unchanged:** smoke `Egress firewall clawfactory chain present` = PASS, `Firewall inbound-deny rule on 8787` = PASS. No firewall rule added/removed (domain grants are Phase 3).
- **SOUL hash pin untouched:** smoke `Orchestrator SOUL hash substituted` = PASS; no edit to any `agent.md` or the pin in setup.ps1.
- **`/etc/wsl.conf` on Bret's machine NOT modified by me:** read-only reads only; value is `enabled=true` before and after this session (its pre-existing drifted state). I did not flip it.
- **No key material in new files:** `grep -E 'tvly-|sk-|ANTHROPIC_API_KEY|DISPATCH_SECRET'` over the new/edited files is clean (the governor stores only USD amounts; no credentials).

### 4. Delta bug review (found, not silently left)
- automount drift (Task 1.0) → documented + fail-loud readback added; live flip is Bret's call.
- gateway-flap-after-`wsl --shutdown` (SURPRISES #2) → documented; environment restored.
- doc smoke-count inconsistency (SURPRISES #5) → corrected in three files.
- Studio ARCHITECTURE container claim → corrected in-file (not committable, BLOCKED #3).

### Git
`git status --short` at start: clean. Committed only the intended Secure-Setup files (setup.ps1, resources/clawfactory-grants.ps1, resources/launcher.ps1, resources/clawfactory-stop.ps1, smoke-test.ps1, ClawFactory-Secure-Setup.iss, README.md, CLAUDE_ClawFactory.md, CONTRIBUTING.md, this report) — explicitly, by path; never `git add -A`. Commit hash recorded at push. The Studio `ARCHITECTURE.md` edit is a working-tree change in a non-git sibling and is not part of this commit.
