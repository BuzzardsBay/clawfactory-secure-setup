## Quick navigation index (read this first when debugging)

| Symptom | First check | Then |
|---|---|---|
| Install fails mid-step | Section 15.2 (`install.log` tail) | Cross-ref Section 13.1 to identify which user context and which step |
| Gateway not responding on 8787 | Section 15.7 (service unit exists?) → Section 15.9 (journalctl) | Section 18.1 for healthy unit baseline |
| Smoke test fails 7th check (auth-profiles) | Section 15.5 (per-agent auth-profiles.json) | Section 14.3 (bootstrap.ps1 fan-out) |
| `openclaw config set` fails with "path not found" | Section 17.2/17.3 (schema for 2026.4.27) | Confirm path actually exists on pinned version |
| First-launch SIGTERM / restart loop | Section 15.9 (journalctl for SIGTERM) | Section 13.4 pattern hazard list |
| Step 8b `[gateway-install] FATAL` | Section 13.3 sub-block inventory | Section 15.2 for full context |
| Drop-in conf appears missing | Section 15.8 | Section 18.5 for healthy drop-in directory contents |
| Token absent / gateway refuses connections | Section 15.4 (openclaw.json) | Section 18.2 for healthy openclaw.json shape |

---

## 13. Install Execution Map

This section maps the 15-step install flow onto user contexts, log destinations, sub-blocks, and known pattern hazards. Use it when diagnosing a failed install: figure out which user owned the failing operation, which log captured its output, and whether the failure mode matches a known hazard pattern.

### 13.1 User context per step

The installer flow lives in `setup.ps1`'s `Invoke-MainFlow` (around line 1495). Most steps run as Windows admin (PowerShell native) and shell out to WSL via `Invoke-WslBash` for Linux-side work. The `-User` parameter to `Invoke-WslBash` selects between `root` (privileged installs) and `clawuser` (per-user state).

| # | Step | Top-level context | WSL inner user | Why |
|---|---|---|---|---|
| 1 | Step-Preflight | Windows admin | n/a | Validates Windows version, admin token, internet |
| 2 | Step-EnsureWsl | Windows admin | mixed (creates clawuser as root) | Installs WSL2 + Ubuntu, may schedule reboot |
| 3 | Step-ConfigureWslConf | Windows admin | root | Writes `/etc/wsl.conf` (automount off, systemd on) |
| 4 | Step-RestartWsl | Windows admin | n/a | `wsl --shutdown` so the new wsl.conf takes effect |
| 5 | Step-CreateClawUser | Windows admin | root | Creates `clawuser`, locks the account, writes `/etc/sudoers.d/...` |
| 5b | Step-SetDefaultUser | Windows admin | root | Sets `[user] default=clawuser` in `/etc/wsl.conf` |
| 6 | Step-InstallDocker | Windows admin | root → clawuser (rootless docker) | apt-installs docker + iptables/nftables, enables rootless for clawuser |
| 7 | Step-EgressFirewall | Windows admin | root | Writes nftables config + iptables-legacy fallback, systemd unit, IP allowlist |
| 7b | Step-InstallOllama | Windows admin | root, then clawuser | Only runs when Provider=ollama; pulls llama3.1:8b |
| 8 | Step-InstallOpenClaw | Windows admin | root (`OPENCLAW_VERSION=2026.4.27 install.sh`) | SHA-256-pinned fetch of openclaw.ai/install.sh, runs as root with `HOME=/home/clawuser` so artifacts land in clawuser's dirs |
| 8b | Step-PreinstallGatewayRuntime | Windows admin | root for `$script` (sub-blocks a-i), **clawuser** for `$gatewayInstall` | Splits across two `Invoke-WslBash` calls (see 13.3). **Context switch hazard zone** — see 13.4. |
| 9 | Step-ConfigureOpenClaw | Windows admin | clawuser | `openclaw config set` for gateway.bind/port/mode + per-provider auth profile |
| 10 | Step-CreateAgentDirectories | Windows admin | clawuser | Pre-creates 4 agent workspace dirs |
| 11 | Step-ApplySafetyRules | Windows admin | clawuser | Writes `~/.openclaw/SOUL.md` + sha256 sidecar (mode 444) |
| 12 | Step-WireProviderKey | Windows admin | clawuser | Writes `~/.openclaw/auth-profiles.json` (mode 600) with API key from DPAPI |
| 13 | Step-WindowsFirewallDeny | Windows admin | n/a | `Get/New-NetFirewallRule` — Windows-only |
| 14 | Step-PostInstall | Windows admin | clawuser | Runs `resources/post-install.ps1`: doctor health check + bonjour drop-in + restart |
| 15 | Step-ConfigureAgents | Windows admin | clawuser | Runs `resources/bootstrap.ps1`: writes 4 agent.md files + auth-profiles fan-out |

### 13.2 Logs and their owners

| Path | Owner / mode | Writer | When created | Purpose |
|---|---|---|---|---|
| `C:\ProgramData\ClawFactory\install.log` | Windows: SYSTEM (admin-readable) | `Write-Log` in setup.ps1; `Log` in post-install.ps1 / bootstrap.ps1 | Step 1 | Master install log. Captures all PowerShell `Log`/`Write-Log` calls AND all stdout/stderr from `Invoke-WslBash` (via `ForEach-Object { Log $_ }`). **Source of truth** for diagnosing Linux-side WSL output too. |
| `C:\ProgramData\ClawFactory\checkpoint.json` | Windows: SYSTEM | `Save-Checkpoint` | Step 1 | JSON `{"completedSteps": [...]}`. Each step appends its name on success. Used by `-Resume` to skip completed steps after WSL reboot. |
| `C:\ProgramData\ClawFactory\provider.json` | Windows: SYSTEM | setup.ps1 main flow | Step 1 | Records selected provider + timestamp. Read by switch-provider.ps1 / post-install.ps1. |
| `C:\ProgramData\ClawFactory\launcher.log` | Windows: user-writable | launcher.ps1 | First desktop-shortcut click | One-line-per-launch log: `STARTED` / `ALREADY_RUNNING` / `TIMEOUT`. |
| `C:\ProgramData\ClawFactory\resume-after-restart.flag` | Windows: SYSTEM | setup.ps1 if WSL install needed reboot | Pre-restart only | JSON `{"provider": "...", ...}`. Deleted on completion. Read by Inno Setup `[Code]` `ReadResumeProvider` if `/resume`. |
| `/tmp/openclaw-install.log` (Linux) | root:root, mode 644 (created by Step 8 install.sh as root) | install.sh | Step 8 | **Stale post-tee-fix.** Was used as install.sh tee target. Output now flows only through Windows install.log. May still receive failed tee writes from sub-block daemon-reload/enable/restart (with `\|\| true` masking the failures). |
| `/home/clawuser/.openclaw/logs/` (Linux) | clawuser:clawuser, mode 700 | openclaw runtime | Step 8b | Reserved for openclaw's own runtime logs. The canonical install command does not write here directly. |
| `journalctl --user -u openclaw-gateway` (Linux) | systemd-journald | systemd | Step 8b once unit installed | **Authoritative log** for gateway service lifecycle (start, restart, crash, exit codes). First place to look for runtime issues post-install. |

### 13.3 Step 8b sub-block inventory

Step 8b (`Step-PreinstallGatewayRuntime`) splits into two `Invoke-WslBash` calls:

| Sub-block | Purpose | User | Exit-code-critical? |
|---|---|---|---|
| `$script` (a) — Core runtime npm pre-install | `npm install` core deps in `~/.openclaw/plugin-runtime-deps/openclaw-*/` | root | No — failures logged, install continues |
| `$script` (b) — Bundled plugin npm pre-install | `npm install` per-plugin deps in `dist/extensions/<n>/.openclaw-install-stage/` | root | No — `tail -2 \|\| echo "(warn) ..."` swallows |
| `$script` (c) — `clawfactory-tunables.conf` drop-in | Writes `TimeoutStartSec=infinity` to `~/.config/systemd/user/openclaw-gateway.service.d/` | root | No — file write only |
| `$script` (d) — Per-agent auth-profiles seeding | Copies `~/.openclaw/auth-profiles.json` → `~/.openclaw/agents/<n>/agent/auth-profiles.json` (no-op since the source file isn't written until Step 12) | root | No — guarded by `[ -f ... ]` |
| `$script` (e) — `loginctl enable-linger clawuser` | Allows user-systemd to survive WSL session close | root | No — `\|\| true` |
| `$script` (f) — Auxiliary IPs into firewall allowlist | nft / iptables-legacy `add element` for provider auth/registry hosts | root | No — graceful per backend |
| `$script` (g) — Allow-providers refresh systemd timer | Writes `clawfactory-allow-providers.{service,timer}` + script | root | No — `\|\| true` on enable |
| `$script` (h) — Default `main` agent.md | Writes provider-aware `agent.md` for the main agent if dir exists and file missing | root | No — guarded |
| `$script` (i) — chown back to clawuser | Recursive chown of `~/.openclaw`, drop-in dir, extensions dir | root | No |
| `$gatewayInstall` (1) — `openclaw gateway install --force --port 8787` | Canonical install; auto-generates token, writes systemd unit | **clawuser** | **YES** — `rc=$?` captured, hard-fail on non-zero (PowerShell `throw`) |
| `$gatewayInstall` (2) — daemon-reload + enable + restart + sleep 5 + is-active poll | Per #65184 race-condition fix; gives unit ~17s to bind | clawuser | No — `\|\| true` masks each step; final exit 0 even if poll never sees `active` |

**Context-switch hazard**: anything `$script` (root) writes to a Linux path used by `$gatewayInstall` (clawuser) needs explicit chown. Sub-block (i) handles this for the directories listed; **`/tmp/*` files written as root in Step 8 do not get chowned** — that's the bug class fixed in the May 1 tee-removal commit.

### 13.4 Pattern hazard list

| Pattern | Where in current code | Status | Defense-in-depth |
|---|---|---|---|
| **tee-as-pipe-tail trap** (`cmd \| tee file` → `$?` is tee's exit, not cmd's; PIPESTATUS or process substitution required) | Fixed for the install command at setup.ps1:1180-1182. Three remaining instances at setup.ps1:1189/1192/1195 are wrapped in `\|\| true`, so exit code masking is intentional. | Fixed (load-bearing case) | Use `cmd 2>&1 > >(tee file) 2>&1` or `set -o pipefail` + `${PIPESTATUS[0]}` when exit code matters. |
| **Permission asymmetry on /tmp** (file created by root in Step N can't be appended-to by clawuser in Step N+1) | Source of the May 1 tee bug. Remaining `\|\| true`-wrapped tees at setup.ps1:1189/1192/1195 silently fail; their output is captured by Windows-side install.log instead. | Mitigated | Either `chown` /tmp files at end of root-context blocks, or write logs to clawuser-owned dirs (`~/.openclaw/logs/`), or rely entirely on the Windows-side capture. |
| **`--non-interactive` skip-on-prompt** (openclaw doctor `--non-interactive` skips operations needing confirmation, including systemd unit install — exits 1 in ~1s on fresh state) | Replaced in commit 5777d1c by `yes \| timeout … openclaw doctor --fix --yes` | Fixed | If a future doctor variant adds new prompts, the `yes` pipe still answers all of them. |
| **doctor-as-installer** (relying on `openclaw doctor` to install the systemd unit; doctor only repairs existing state, doesn't bootstrap) | Replaced in commit a10a4a6 by `openclaw gateway install --force --port 8787` as the canonical entry point | Fixed | Use the documented install command, treat doctor purely as a final health check. |
| **Step-name churn** (sub-blocks within a function evolve over time, but the function name and Step-NN comment header drift apart) | Step 8b currently has 9 sub-blocks (a-i + the two-phase gateway install) | Acceptable | Section 13.3 above is the source of truth. |
| **Stale comments after refactor** | Mostly cleaned in commit a10a4a6; minor stale strings (`config-set`, `fix bundle`) noted in v1.1 backlog | Acceptable | This document is the canonical reference; treat in-source comments as advisory. |

---

## 14. Code Interconnect Map

Each PowerShell script in the installer flow + post-install + ongoing-operations scripts. Read this when changing a script to understand who depends on its outputs (and on what state) and who changes the state it later reads.

### 14.1 setup.ps1

**Preconditions**: Windows 11 22H2+, admin token, internet, ≥8 GB free on `%SystemDrive%`. Run with `-AcknowledgedOpenClawUrl -Provider <name> -SourceExe <path> [-Resume]`. Inno Setup `[Run]` provides these; standalone invocation possible for re-runs.

**User context**: Windows admin throughout. Each step that touches Linux state shells out via `Invoke-WslBash -User <root|clawuser>`.

**Outputs / side effects**:
- WSL2 + Ubuntu installed and configured (steps 2-5b)
- `clawuser` Linux account, locked, default WSL user (steps 5-5b)
- Docker rootless for clawuser (step 6)
- nftables / iptables-legacy egress firewall (step 7)
- Optional Ollama (step 7b)
- OpenClaw npm package pinned to 2026.4.27 (step 8)
- OpenClaw gateway systemd user service + token + drop-ins (step 8b)
- `~/.openclaw/openclaw.json` populated with gateway.bind/port/mode + auth profile metadata (step 9)
- 4 empty agent workspace dirs (step 10)
- `~/.openclaw/SOUL.md` (mode 444) + sha256 (step 11)
- `~/.openclaw/auth-profiles.json` (mode 600) with API key from DPAPI (step 12)
- Windows Firewall inbound-deny rule on TCP/8787 (step 13)
- `%ProgramData%\ClawFactory\install.log`, `checkpoint.json`, `provider.json` (continuous)

**Downstream consumers**:
- `resources/post-install.ps1` (run by step 14)
- `resources/bootstrap.ps1` (run by step 15)
- `resources/launcher.ps1` (desktop shortcut, post-install)
- `resources/clawfactory-stop.ps1` (Start Menu, post-install)
- `resources/switch-provider.ps1` (Start Menu, post-install)

**State files**: writes/reads `checkpoint.json`, `provider.json`, `resume-after-restart.flag`; writes `install.log`; writes Linux `~/.openclaw/openclaw.json`, `~/.openclaw/auth-profiles.json`, `~/.openclaw/SOUL.md`, `~/.config/systemd/user/openclaw-gateway.service.d/clawfactory-tunables.conf`.

### 14.2 resources/post-install.ps1

**Preconditions**: All of setup.ps1 steps 1-13 completed. `~/.openclaw/auth-profiles.json` already exists for non-`ollama`/`later` providers (written by step 12). systemd-user available OR fallback path (3-tier) usable.

**User context**: Windows admin top-level. WSL operations as `clawuser`.

**Outputs / side effects**:
1. Reads provider key from Windows Credential Manager (DPAPI) to verify presence — does NOT re-wire it (step 12 already did).
2. `openclaw models set "<prefix>/<model>"` — writes default model id into `~/.openclaw/openclaw.json`.
3. **FIX 3 (doctor)**: `yes | timeout … openclaw doctor --fix --yes` — health check; non-zero exit logs WARN, install continues.
4. **FIX 1 (bonjour drop-in)**: writes `~/.config/systemd/user/openclaw-gateway.service.d/clawfactory-disable-bonjour.conf` with `Environment=OPENCLAW_DISABLE_BONJOUR=1`. Defense-in-depth.
5. avahi-daemon restart (no-op if avahi not installed).
6. **Restart and verify**: 3-tier gateway start (systemd → `openclaw gateway start` → `nohup setsid openclaw gateway run`), polls `127.0.0.1:8787/status` for ≤60s.

**Downstream consumers**: bootstrap.ps1 reads `~/.openclaw/auth-profiles.json` to fan out per-agent; smoke-test.ps1 verifies gateway responds.

**State files**: reads `Credential Manager`, `~/.openclaw/openclaw.json`; writes `~/.config/systemd/user/openclaw-gateway.service.d/clawfactory-disable-bonjour.conf`, restarts `openclaw-gateway.service`.

### 14.3 resources/bootstrap.ps1

**Preconditions**: setup.ps1 step 14 has completed; gateway is or recently was running; `~/.openclaw/agents/<id>/` directories exist (created by step 10); `~/.openclaw/SOUL.md.sha256` exists (step 11).

**User context**: Windows admin top-level. WSL operations as `clawuser` via its own `Invoke-WslBash`.

**Outputs / side effects**:
1. `Write-DefaultAgentName` — writes `%ProgramData%\ClawFactory\agent-name.txt` with default `Claw` (only if file absent).
2. `Get-SoulSha256` — reads `~/.openclaw/SOUL.md.sha256` to substitute into orchestrator prompt.
3. For each of `orchestrator`, `skill-scout`, `skill-builder`, `publisher`: writes `~/.openclaw/agents/<n>/agent.md` (mode 644) atomically (tmp + mv).
4. **FIX 4 — auth-profiles fan-out**: for each of `main`, `orchestrator`, `publisher`, `skill-builder`, `skill-scout`: copies `~/.openclaw/auth-profiles.json` → `~/.openclaw/agents/<id>/agent/auth-profiles.json` (mode 600). Graceful skip when source absent (Provider=later).
5. Appends `AgentBootstrap` to `checkpoint.json`.
6. Prints next-steps banner.

**Downstream consumers**: openclaw runtime reads per-agent auth-profiles.json; smoke-test.ps1's 7th check verifies all 5 fan-out targets exist with mode 600.

**State files**: reads `SOUL.md.sha256`, `auth-profiles.json`; writes 4× `agent.md`, 5× per-agent `auth-profiles.json`, `agent-name.txt`, `checkpoint.json`.

### 14.4 resources/launcher.ps1

**Preconditions**: install completed, gateway service unit exists. Run by desktop shortcut as Windows user (not admin).

**User context**: Windows user (no admin). WSL operations as `clawuser`.

**Outputs / side effects**:
1. HTTP-probes `127.0.0.1:8787/status`. If 200, opens chat in Windows Terminal (or PowerShell fallback) and exits.
2. If not responding, calls `Start-Gateway` (3-tier fallback: systemd → `openclaw gateway start` → `nohup setsid openclaw gateway run`).
3. Polls `/status` for `$TimeoutSec` seconds (default 15s). On 200, opens chat. On timeout, shows failure dialog.
4. Logs `STARTED` / `ALREADY_RUNNING` / `TIMEOUT` to `%ProgramData%\ClawFactory\launcher.log`.

**State files**: writes `launcher.log`. No state changes to openclaw config.

### 14.5 resources/switch-provider.ps1

**Preconditions**: install completed, run as admin (it modifies firewall rules). Provider name passed as parameter.

**User context**: Windows admin. WSL operations as `clawuser` and `root`.

**Outputs / side effects**:
1. Stores new API key in Credential Manager via `cmdkey`.
2. For Ollama: ensures Ollama is installed and pulls the default model.
3. Updates nftables allowlist (flush + re-resolve provider hosts).
4. Updates `~/skills-factory/openclaw.json` via python3 — **see known issues note in v1.1 backlog (M4-M6)**.

**State files**: writes Credential Manager, nftables ruleset, openclaw.json (currently to wrong path).

### 14.6 resources/clawfactory-stop.ps1

**Preconditions**: openclaw runtime exists in WSL. Optional admin (kill-only operations).

**User context**: Windows user. WSL operations as `clawuser`.

**Outputs / side effects**:
1. `docker kill` all containers labeled `clawfactory=1`.
2. `openclaw gateway stop` (graceful).

**State files**: none — stops processes only.

### 14.7 resources/rename-agent.ps1

**Preconditions**: install completed.

**User context**: Windows user. No WSL ops.

**Outputs / side effects**: shows an explanation MessageBox; performs no rename in factory variant. Full rename ships in the planned single-agent variant.

**State files**: none.

### 14.8 smoke-test.ps1

**Preconditions**: install completed on a clean VM.

**User context**: Windows admin. WSL operations as `clawuser`.

**Outputs / side effects**: 7 checks (WSL automount disabled, four agent.md files present, AgentBootstrap checkpoint, gateway 200, firewall inbound-deny, SOUL hash substituted, all-5-agents auth-profiles). Exits with `$fail` count.

**State files**: read-only verification; layered gateway-start helper may start the gateway as a side effect.

### 14.9 Pipeline summary

```
Inno Setup .iss
   └─ runs setup.ps1
       ├─ checkpoint.json (continuous)
       ├─ install.log (continuous)
       ├─ Linux state under /home/clawuser/.openclaw/
       └─ runs (step 14) post-install.ps1 → doctor health check + bonjour drop-in + restart
           └─ runs (step 15) bootstrap.ps1 → 4 agent.md + 5 auth-profiles fan-out + AgentBootstrap checkpoint
              ↓
           ────────────────────────────────────
           Post-install operational scripts:
              • launcher.ps1   (desktop shortcut)
              • clawfactory-stop.ps1   (kill switch)
              • switch-provider.ps1    (provider change)
              • rename-agent.ps1   (rename UX)
           ────────────────────────────────────
              ↓
           smoke-test.ps1 (verification on a clean VM)
```

---

## 15. Diagnostic Quick Reference

For each location: where it lives, who owns it, what it should look like when healthy, what failure looks like, and how to inspect it. Order: file paths first, then runtime introspection commands, then OpenClaw source navigation.

### 15.1 /tmp/openclaw-install.log

- **Path**: `/tmp/openclaw-install.log` (inside WSL Ubuntu)
- **Owner**: root:root, mode 644 (created by Step 8 install.sh as root). Post-tee-fix, may not be created at all on fresh installs that skip the install.sh tee.
- **Contains**: tee-output of install.sh (when populated by Step 8). May also receive failed tee writes from setup.ps1 Step 8b sub-blocks (silently swallowed via `|| true`).
- **Healthy state**: present after Step 8 with install.sh output; final lines say `[gateway-preinstall] complete`. Post-fix, install.sh tee is the only writer.
- **Unhealthy**: absent (Step 8 never ran), or contains permission errors from Step 8b's downstream tees (cosmetic; output is in Windows install.log).
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'tail -100 /tmp/openclaw-install.log'`
- **Common failure modes**:
  - File owned by root, clawuser appends fail with "Permission denied" (load-bearing case fixed May 1; remaining cases mitigated by `|| true`)
  - File doesn't exist (Step 8 skipped)
  - SHA-256 mismatch error visible from install.sh

### 15.2 C:\ProgramData\ClawFactory\install.log

- **Path**: `C:\ProgramData\ClawFactory\install.log`
- **Owner**: SYSTEM-writable, admin-readable (Windows ACLs)
- **Contains**: master log of the entire install. Every PowerShell `Log` / `Write-Log` call AND every line of stdout/stderr from `Invoke-WslBash` (via `ForEach-Object { Log $_ }`). Captures all WSL output even when Linux-side log files aren't accessible.
- **Healthy state**: ends with `[INFO] ==== ClawFactory Secure Setup - completed successfully ====`.
- **Unhealthy**: ends mid-step (script aborted), or shows `[ERROR]` lines, or has long gaps between timestamps.
- **Inspect**: `Get-Content "$env:ProgramData\ClawFactory\install.log" -Tail 100`
- **Common failure modes**:
  - Step 8 OpenClaw install timed out (check for "exit 124" or "exit 137")
  - Step 8b gateway install failed (check for FATAL openclaw gateway install)
  - WSL not ready post-resume (check Step 2 / Step 4 region)

### 15.3 C:\ProgramData\ClawFactory\checkpoint.json

- **Path**: `C:\ProgramData\ClawFactory\checkpoint.json`
- **Owner**: SYSTEM
- **Contains**: `{"completedSteps": ["Preflight", "EnsureWsl", ..., "AgentBootstrap"]}` — 16 entries on a clean full run.
- **Healthy state**: contains all of: `Preflight`, `EnsureWsl`, `WslConf`, `RestartWsl`, `ClawUser`, `DefaultUser`, `Docker`, `EgressFirewall`, `Ollama` (only if Provider=ollama), `OpenClaw`, `GatewayRuntime`, `OpenClawConfig`, `AgentDirs`, `SafetyRules`, `ProviderKey`, `WindowsFirewall`, `PostInstall`, `AgentBootstrap`.
- **Unhealthy**: missing `AgentBootstrap` (smoke-test will fail this check); missing `GatewayRuntime` (Step 8b never finished).
- **Inspect**: `Get-Content "$env:ProgramData\ClawFactory\checkpoint.json" | ConvertFrom-Json | Select-Object -ExpandProperty completedSteps`
- **Common failure modes**:
  - Stale from a partial install (`-Resume` will skip already-completed steps)
  - Missing checkpoint dir (step 1 didn't run)

### 15.4 ~/.openclaw/openclaw.json

- **Path**: `/home/clawuser/.openclaw/openclaw.json`
- **Owner**: clawuser:clawuser, mode 600
- **Contains**: gateway config (bind/port/mode/auth.token), auth profiles, default model, plugin entries.
- **Healthy state**: `gateway.bind = "loopback"`, `gateway.port = 8787`, `gateway.mode = "local"`, `gateway.auth.mode = "token"`, `gateway.auth.token` populated, `agents.defaults.model.primary` set to selected provider's default.
- **Unhealthy**: missing `gateway.auth.token` (gateway install didn't run); missing `agents.defaults.model.primary` (post-install didn't run); plugin `tavily.enabled = true` with placeholder API key (likely from a manual test — replace before shipping).
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'cat ~/.openclaw/openclaw.json | head -40'`
- **Common failure modes**:
  - Token absent → gateway never started
  - `config-set "path not found"` errors during install (FIX 2 removed addresses this — schema paths absent on 2026.4.27)

### 15.5 ~/.openclaw/auth-profiles.json (and per-agent variants)

- **Path**: `/home/clawuser/.openclaw/auth-profiles.json` (legacy/global), `/home/clawuser/.openclaw/agents/<n>/agent/auth-profiles.json` (per-agent canonical)
- **Owner**: clawuser:clawuser, mode 600
- **Contains**: provider auth metadata (provider name, mode=`api_key`, displayName, key reference).
- **Healthy state**: global file exists (written Step 12); 5 per-agent copies exist post-bootstrap.ps1 fan-out.
- **Unhealthy**: only global exists, not per-agent → openclaw runtime can't find keys (FIX 4 fan-out failed).
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'ls -la ~/.openclaw/auth-profiles.json ~/.openclaw/agents/*/agent/auth-profiles.json'`
- **Common failure modes**:
  - Mode 644 instead of 600 (smoke-test 7th check fails)
  - Source missing for Provider=later case (graceful skip in bootstrap.ps1)

### 15.6 ~/.openclaw/agents/<name>/agent.md

- **Path**: `/home/clawuser/.openclaw/agents/{orchestrator,skill-scout,skill-builder,publisher}/agent.md` (4 files)
- **Owner**: clawuser:clawuser, mode 644
- **Contains**: per-agent role prompt with `{{SOUL_SHA256}}` substituted (orchestrator only). Body is the role's responsibilities + safety boundaries.
- **Healthy state**: 4 files, ≥1 KB each. Orchestrator's SOUL hash substituted (literal `{{SOUL_SHA256}}` token absent).
- **Unhealthy**: any of the 4 missing or 0 bytes; orchestrator still contains `{{SOUL_SHA256}}` placeholder.
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'wc -c ~/.openclaw/agents/*/agent.md && grep -l "{{SOUL_SHA256}}" ~/.openclaw/agents/orchestrator/agent.md && echo BAD || echo OK'`
- **Common failure modes**:
  - Step 11 didn't write SOUL.md.sha256 → bootstrap can't substitute (intentional fail-loudly)
  - Resource file missing in installer build → bootstrap.ps1 writes a placeholder.

### 15.7 ~/.config/systemd/user/openclaw-gateway.service

- **Path**: `/home/clawuser/.config/systemd/user/openclaw-gateway.service`
- **Owner**: clawuser:clawuser, mode 644
- **Contains**: systemd user unit. `ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 8787`. Default `TimeoutStartSec=30`, `Restart=always`, env vars including `OPENCLAW_GATEWAY_PORT=8787`.
- **Healthy state**: file present, ≈900-1100 bytes, `systemctl --user is-enabled openclaw-gateway.service` returns `enabled`.
- **Unhealthy**: file absent → `openclaw gateway install --force` never ran or failed.
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'cat ~/.config/systemd/user/openclaw-gateway.service'`
- **Common failure modes**:
  - File absent (Step 8b failed)
  - Stale ExecStart pointing to an old openclaw version (re-run `openclaw gateway install --force`)

### 15.8 ~/.config/systemd/user/openclaw-gateway.service.d/clawfactory-tunables.conf

- **Path**: `/home/clawuser/.config/systemd/user/openclaw-gateway.service.d/clawfactory-tunables.conf`
- **Owner**: clawuser:clawuser, mode 644
- **Contains**: `[Service] / TimeoutStartSec=infinity` — drop-in override for the parent unit's 30s timeout.
- **Healthy state**: file present, drop-in dir contains both `clawfactory-tunables.conf` (TimeoutStartSec) and `clawfactory-disable-bonjour.conf` (Environment=OPENCLAW_DISABLE_BONJOUR=1).
- **Unhealthy**: drop-in dir absent or empty → first-boot may SIGTERM mid-init.
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'ls -la ~/.config/systemd/user/openclaw-gateway.service.d/ && cat ~/.config/systemd/user/openclaw-gateway.service.d/*.conf'`
- **Common failure modes**:
  - openclaw upgrade re-creates the unit; drop-ins still apply (systemd auto-merges).
  - Manual `openclaw gateway install --force` may write its own drop-in (e.g. `insecure-loopback.conf`); coexists with ours.

### 15.9 journalctl --user -u openclaw-gateway

- **Owner**: systemd-journald
- **Contains**: gateway service stdout, stderr, lifecycle events (start, stop, restart, exit codes).
- **Healthy state**: most recent entries show `Started ... gateway on port 8787` and no `Main process exited` records since.
- **Unhealthy**: repeated `Main process exited, code=killed, status=15/TERM` followed by restart cycles → bonjour SIGTERM bug fired (FIX 1's drop-in should prevent on 2026.4.27, but verify).
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'journalctl --user -u openclaw-gateway -n 100 --no-pager'`
- **Common failure modes**:
  - `failed to bind 0.0.0.0:8787` — another process on the port
  - `No API key found for provider 'openai'` — FIX 4 auth-profiles fan-out missed an agent

### 15.10 Windows Firewall rule "ClawFactory-Block-Inbound-8787"

- **Owner**: Windows Defender Firewall
- **Contains**: inbound-deny rule for TCP/8787, scope=any, action=Block.
- **Healthy state**: `(Get-NetFirewallRule -DisplayName 'ClawFactory-Block-Inbound-8787').Enabled = 'True'` and `.Action = 'Block'`.
- **Unhealthy**: rule missing → LAN can reach the gateway. Rule disabled → same.
- **Inspect**: `Get-NetFirewallRule -DisplayName 'ClawFactory-Block-Inbound-8787' | Format-List`
- **Common failure modes**:
  - Rule deleted by manual cleanup
  - Antivirus / endpoint-protection product overwriting Windows Firewall rules

### 15.11 OpenClaw source navigation

OpenClaw lives at `/usr/lib/node_modules/openclaw/` inside WSL (installed by `install.sh` as a global npm package). Key directories:

| Path | Contents |
|---|---|
| `/usr/lib/node_modules/openclaw/dist/index.js` | CLI entry point. `ExecStart` of the gateway unit. |
| `/usr/lib/node_modules/openclaw/dist/cli/` | Per-command implementations (`config.js`, `gateway.js`, `agents.js`, `doctor.js`, ...) |
| `/usr/lib/node_modules/openclaw/dist/extensions/<plugin>/` | Bundled plugins (anthropic, openai, browser, codex, ...). Each has `index.js` and `openclaw.plugin.json`. |
| `/usr/lib/node_modules/openclaw/dist/bonjour-discovery-*.js` | Bonjour mDNS code (the bug source — disabled via env var on 2026.4.27). |
| `/usr/lib/node_modules/openclaw/openclaw.mjs` | Symlinked from `/usr/bin/openclaw`. |
| `/usr/lib/node_modules/openclaw/package.json` | Pinned version: 2026.4.27. |

Grep recipes (run inside WSL as clawuser):

```bash
# Find which file implements a subcommand, e.g. `openclaw gateway install`:
grep -rl "gateway install" /usr/lib/node_modules/openclaw/dist/cli/

# Find a config schema path's implementation:
grep -rn "discovery.mdns" /usr/lib/node_modules/openclaw/dist/

# List all subcommands defined in dist/cli/:
ls /usr/lib/node_modules/openclaw/dist/cli/

# Find env-var consumers (e.g. who reads OPENCLAW_DISABLE_BONJOUR):
grep -rn "OPENCLAW_DISABLE_BONJOUR" /usr/lib/node_modules/openclaw/dist/
```

Re-read after every `OPENCLAW_VERSION` pin bump — paths and command names can shift between minor versions.

---

## 16. Inno Setup Script Reference

`ClawFactory-Secure-Setup.iss` is the Inno Setup 6 script that compiles the installer `.exe`. It bundles all source files into a single executable, defines the wizard pages (welcome, provider radio, API key prompt, security acknowledgement), shells out to `setup.ps1` to do the actual work, and registers Start Menu / desktop shortcuts. The `[Code]` section is Pascal-like Inno script that handles the `/resume` flag (post-WSL-reboot relaunch), the per-provider "Get your API key" button, API-key capture into Windows Credential Manager via `cmdkey`, and conditional page-skipping for non-key-requiring providers.

```ini
; ClawFactory Secure Setup - Inno Setup 6 script
; Builds a hardened OpenClaw Skills Factory on Windows 11.
; Compile with: "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ClawFactory-Secure-Setup.iss

#define MyAppName      "ClawFactory Secure Setup"
#define MyAppVersion   "1.0.0"
#define MyAppPublisher "Frontier Automation Systems LLC"
#define MyAppURL       "https://openclaw.ai"

[Setup]
; [R1] Fixed AppId for stable upgrade/uninstall identity. Do not regenerate.
AppId={{8D7C4B2A-4F1E-4B5C-9D3E-CF7A6B2E1A90}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
DefaultDirName={autopf}\ClawFactory
DefaultGroupName=ClawFactory
OutputBaseFilename=ClawFactory-Secure-Setup
OutputDir=Output
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
DisableReadyPage=no
UninstallDisplayIcon={app}\resources\lobster.ico
; [R1] Uncomment after configuring a SignTool via Tools > Configure Sign Tools in the IDE.
; SignTool=signtool

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "setup.ps1";                         DestDir: "{app}";            Flags: ignoreversion
Source: "README.md";                         DestDir: "{app}";            Flags: ignoreversion
Source: "LICENSE";                           DestDir: "{app}";            Flags: ignoreversion
Source: "resources\safety-rules.md";         DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\orchestrator-prompt.md";  DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\post-install.ps1";        DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\bootstrap.ps1";           DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\rename-agent.ps1";        DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\launcher.ps1";            DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\clawfactory-stop.ps1";    DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\switch-provider.ps1";     DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\logo.png";                DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\logo.README.txt";         DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\lobster.ico";             DestDir: "{app}\resources";  Flags: ignoreversion

[Run]
; [R5] No API key on the command line - setup.ps1 reads from Windows Credential Manager.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup.ps1"" -AcknowledgedOpenClawUrl -Provider {code:GetProviderLabel} -SourceExe ""{srcexe}""{code:GetResumeFlag}"; \
  WorkingDir: "{app}"; \
  StatusMsg: "{code:GetStatusMsg}"; \
  Flags: waituntilterminated

[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""if ((Read-Host 'Remove Ubuntu WSL distro, skills-factory workspace, and all provider credentials? [y/N]') -eq 'y') {{ wsl --unregister Ubuntu; cmdkey /delete:ClawFactory/GrokApiKey 2>$null; cmdkey /delete:ClawFactory/OpenAIApiKey 2>$null; cmdkey /delete:ClawFactory/AnthropicApiKey 2>$null; cmdkey /delete:ClawFactory/GeminiApiKey 2>$null; Remove-NetFirewallRule -DisplayName 'ClawFactory-Block-Inbound-8787' -ErrorAction SilentlyContinue }}"""; \
  RunOnceId: "ClawFactoryCleanup"; \
  Flags: runhidden

[Icons]
Name: "{commondesktop}\ClawFactory"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\resources\launcher.ps1"""; \
  WorkingDir: "{app}"; IconFilename: "{app}\resources\lobster.ico"; Comment: "Open ClawFactory"
Name: "{group}\ClawFactory Kill Switch"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\resources\clawfactory-stop.ps1"""; \
  WorkingDir: "{app}"; Comment: "Emergency stop: kills all ClawFactory agent containers"
Name: "{group}\ClawFactory Dashboard"; Filename: "{sys}\cmd.exe"; \
  Parameters: "/c start http://127.0.0.1:8787"; WorkingDir: "{app}"; \
  Comment: "Open ClawFactory dashboard in browser (gateway must be running)"
Name: "{group}\Rename Your Assistant"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\resources\rename-agent.ps1"""; \
  WorkingDir: "{app}"; Comment: "Rename your assistant (factory mode shows an explanation; full rename ships in the single-agent variant)"
Name: "{group}\Switch AI Provider"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -NoExit -File ""{app}\resources\switch-provider.ps1"""; \
  WorkingDir: "{app}"; Comment: "Change provider (Grok / OpenAI / Claude / Gemini / Ollama) after install"
Name: "{group}\ClawFactory README"; Filename: "{app}\README.md"
Name: "{group}\Uninstall ClawFactory"; Filename: "{uninstallexe}"

[Code]
var
  WelcomePage:    TOutputMsgWizardPage;
  ProviderPage:   TInputOptionWizardPage;
  ApiKeyPage:     TInputQueryWizardPage;
  ApiKeyLaterChk: TNewCheckBox;
  GetKeyButton:   TNewButton;
  AckPage:        TInputOptionWizardPage;
  IsResumeRun:    Boolean;
  ResumeProvider: string;

function ResumeFlagPath: string;
begin
  Result := ExpandConstant('{commonappdata}\ClawFactory\resume-after-restart.flag');
end;

function HasCmdLineSwitch(const SwitchName: string): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if CompareText(ParamStr(i), SwitchName) = 0 then begin Result := True; exit; end;
end;

{ Naive scan for "provider": "<value>" in the JSON resume flag (no JSON parser
  available in Inno's [Code] dialect; the flag has a known shape so a scan is safe). }
function ReadResumeProvider: string;
var Content: AnsiString; Tail: string; P, Q: Integer;
begin
  Result := 'grok';
  if not LoadStringFromFile(ResumeFlagPath, Content) then exit;
  Tail := string(Content);
  P := Pos('"provider"', Tail); if P = 0 then exit;
  Tail := Copy(Tail, P + Length('"provider"'), MaxInt);
  P := Pos(':', Tail); if P = 0 then exit;
  Tail := Copy(Tail, P + 1, MaxInt);
  P := Pos('"', Tail); if P = 0 then exit;
  Tail := Copy(Tail, P + 1, MaxInt);
  Q := Pos('"', Tail); if Q = 0 then exit;
  Result := Copy(Tail, 1, Q - 1);
end;

function GetProviderLabel(Param: string): string;
begin
  if IsResumeRun then begin Result := ResumeProvider; exit; end;
  case ProviderPage.SelectedValueIndex of
    0: Result := 'grok'; 1: Result := 'openai'; 2: Result := 'claude';
    3: Result := 'gemini'; 4: Result := 'ollama'; 5: Result := 'later';
  else Result := 'grok';
  end;
end;

function GetResumeFlag(Param: string): string;
begin if IsResumeRun then Result := ' -Resume' else Result := ''; end;

function GetStatusMsg(Param: string): string;
begin
  if IsResumeRun then Result := 'Resuming installation after restart...'
  else Result := 'Building your hardened OpenClaw Skills Factory (10-20 minutes)...';
end;

function ProviderNeedsApiKey: Boolean;
begin Result := (ProviderPage.SelectedValueIndex <= 3); end;

function ProviderCredentialTarget: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'ClawFactory/GrokApiKey'; 1: Result := 'ClawFactory/OpenAIApiKey';
    2: Result := 'ClawFactory/AnthropicApiKey'; 3: Result := 'ClawFactory/GeminiApiKey';
  else Result := 'ClawFactory/GrokApiKey';
  end;
end;

function ProviderApiKeyUrl: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'https://console.x.ai/';
    1: Result := 'https://platform.openai.com/api-keys';
    2: Result := 'https://console.anthropic.com/settings/keys';
    3: Result := 'https://aistudio.google.com/app/apikey';
  else Result := '';
  end;
end;

function ProviderShortName: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'Grok'; 1: Result := 'OpenAI';
    2: Result := 'Anthropic'; 3: Result := 'Gemini';
  else Result := '';
  end;
end;

procedure GetKeyButtonClick(Sender: TObject);
var URL: string; ResultCode: Integer;
begin
  URL := ProviderApiKeyUrl; if URL = '' then exit;
  ShellExec('open', URL, '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

procedure InitializeWizard;
begin
  IsResumeRun := HasCmdLineSwitch('/resume');
  if IsResumeRun then ResumeProvider := ReadResumeProvider;

  WelcomePage := CreateOutputMsgPage(wpWelcome,
    'Hardened OpenClaw Skills Factory',
    'This installer builds a sandboxed environment for AI agents.',
    'ClawFactory Secure Setup configures WSL2, Docker, and OpenClaw with strict' + #13#10 +
    'security guardrails:' + #13#10 + #13#10 +
    '  - Four agents run in Docker sandbox (network=none, sandbox=all).' + #13#10 +
    '  - OpenClaw gateway binds to 127.0.0.1 only.' + #13#10 +
    '  - Tool allowlist blocks shell/sudo/rm/system.run/browser.' + #13#10 +
    '  - WSL automount is disabled (no access to your Windows files).' + #13#10 +
    '  - All agents require explicit human "GO" for any risky action.' + #13#10 + #13#10 +
    'WARNING: AI agents will execute code inside these containers.' + #13#10 +
    'You must personally review every skill before publishing.' + #13#10 +
    'Install takes 10-20 minutes and needs admin rights + internet.');

  ProviderPage := CreateInputOptionPage(WelcomePage.ID,
    'Choose your AI provider', 'Which LLM should power your agents?',
    'You can switch providers later by re-running the installer or using the included' + #13#10 +
    'switch-provider.ps1 helper script. Ollama runs entirely on this machine - no' + #13#10 +
    'account, no API key, no cloud calls (needs ~8 GB RAM).',
    True, False);
  ProviderPage.Add('Grok (xAI) - default model: grok-4-1-fast');
  ProviderPage.Add('OpenAI (ChatGPT) - default model: gpt-5');
  ProviderPage.Add('Anthropic Claude - default model: claude-sonnet-4-6');
  ProviderPage.Add('Google Gemini - default model: gemini-2.5-pro');
  ProviderPage.Add('Ollama (local, free, offline-capable) - default model: llama3.1:8b');
  ProviderPage.Add('I''ll configure a provider later');
  ProviderPage.SelectedValueIndex := 0;

  ApiKeyPage := CreateInputQueryPage(ProviderPage.ID,
    'API Key', 'Paste the API key for your selected provider.',
    'The key is stored in Windows Credential Manager (DPAPI-protected, tied to your' + #13#10 +
    'Windows user). It is NEVER written to a file inside WSL.' + #13#10 + #13#10 +
    'Rotate later from a terminal with cmdkey (see README).');
  ApiKeyPage.Add('API key:', True);

  GetKeyButton := TNewButton.Create(ApiKeyPage);
  GetKeyButton.Parent := ApiKeyPage.Surface;
  GetKeyButton.Top    := ApiKeyPage.Edits[0].Top + ApiKeyPage.Edits[0].Height + ScaleY(12);
  GetKeyButton.Left   := ApiKeyPage.Edits[0].Left;
  GetKeyButton.Width  := ScaleX(220);
  GetKeyButton.Height := ScaleY(24);
  GetKeyButton.Caption := 'Get your API key →';
  GetKeyButton.OnClick := @GetKeyButtonClick;

  ApiKeyLaterChk := TNewCheckBox.Create(ApiKeyPage);
  ApiKeyLaterChk.Parent  := ApiKeyPage.Surface;
  ApiKeyLaterChk.Top     := GetKeyButton.Top + GetKeyButton.Height + ScaleY(12);
  ApiKeyLaterChk.Left    := ApiKeyPage.Edits[0].Left;
  ApiKeyLaterChk.Width   := ApiKeyPage.SurfaceWidth - ApiKeyLaterChk.Left;
  ApiKeyLaterChk.Height  := ScaleY(20);
  ApiKeyLaterChk.Caption := 'I''ll add my API key later (agents will not run until I do)';

  AckPage := CreateInputOptionPage(ApiKeyPage.ID,
    'Security Acknowledgement', 'Please confirm you understand what you are about to install.',
    'Tick the box below to continue. Installation is blocked until you do.',
    False, False);
  AckPage.Add('I understand agents execute code in isolated containers and I will ' +
              'personally review every skill before publishing.');
end;

procedure CurPageChanged(CurPageID: Integer);
var ShortName: string;
begin
  if CurPageID = ApiKeyPage.ID then
  begin
    ShortName := ProviderShortName;
    if ShortName = '' then GetKeyButton.Visible := False
    else begin
      GetKeyButton.Caption := 'Get your ' + ShortName + ' API key →';
      GetKeyButton.Visible := True;
    end;
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if IsResumeRun then
  begin
    if (PageID = WelcomePage.ID) or (PageID = ProviderPage.ID) or
       (PageID = ApiKeyPage.ID) or (PageID = AckPage.ID) then
    begin Result := True; exit; end;
  end;
  if PageID = ApiKeyPage.ID then Result := not ProviderNeedsApiKey;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var Key: string; ResultCode: Integer; CredTarget: string;
begin
  Result := True;
  if CurPageID = ApiKeyPage.ID then
  begin
    Key := Trim(ApiKeyPage.Values[0]);
    if (Key = '') and (not ApiKeyLaterChk.Checked) then
    begin
      MsgBox('Enter your API key, or tick "I''ll add my API key later".', mbError, MB_OK);
      Result := False; exit;
    end;
    if Key <> '' then
    begin
      CredTarget := ProviderCredentialTarget;
      Exec('cmdkey.exe', '/generic:' + CredTarget + ' /user:clawuser /pass:' + Key,
           '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      ApiKeyPage.Values[0] := '';
    end;
  end
  else if CurPageID = AckPage.ID then
  begin
    if not AckPage.Values[0] then
    begin
      MsgBox('You must acknowledge the security notice before installation can continue.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;
```

---

## 17. OpenClaw Config Schema (2026.4.27)

> Version-pinned to 2026.4.27. Re-capture on version bumps — paths, schema branches, and command syntax can shift between minor versions.

### 17.1 `openclaw config --help`

```
🦞 OpenClaw 2026.4.27 (cbc2ba0)

Usage: openclaw config [options] [command]

Non-interactive config helpers (get/set/unset/file/schema/validate). Run without
subcommand for guided setup.

Options:
  -h, --help           Display help for command
  --section <section>  Configuration sections for guided setup (repeatable). Use
                       with no subcommand. (default: [])

Commands:
  file                 Print the active config file path
  get                  Get a config value by dot path
  schema               Print the JSON schema for openclaw.json
  set                  Set config values by path (value mode, ref/provider
                       builder mode, or batch JSON mode).
                       Examples:
                       openclaw config set gateway.port 19001 --strict-json
                       openclaw config set channels.discord.token --ref-provider
                       default --ref-source env --ref-id DISCORD_BOT_TOKEN
                       openclaw config set secrets.providers.vault
                       --provider-source file --provider-path
                       /etc/openclaw/secrets.json --provider-mode json
                       openclaw config set --batch-file ./config-set.batch.json
                       --dry-run
  unset                Remove a config value by dot path
  validate             Validate the current config against the schema without
                       starting the gateway

Docs: https://docs.openclaw.ai/cli/config
```

Note: `openclaw config get` requires a `<path>` argument (e.g. `openclaw config get gateway.port`). Calling it without an argument errors with `error: missing required argument 'path'`.

### 17.2 `openclaw config schema` (top-level structure)

Run `openclaw config schema 2>&1 > openclaw-schema.json` for the full ~2000+ line output. Top-level structure:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "$schema": { "type": "string" },
    "meta": {
      "type": "object",
      "properties": {
        "lastTouchedVersion": { "type": "string" },
        "lastTouchedAt": { "anyOf": [ { "type": "string" }, {} ] }
      },
      "additionalProperties": false
    },
    "env": { "type": "object", "properties": { "shellEnv": {...}, "vars": {...} } },
    "wizard": { "type": "object", "properties": { "lastRunAt": {...}, "lastRunVersion": {...} } },
    "diagnostics": { "type": "object", "properties": { "enabled": {...}, "otel": {...} } }
    // gateway, agents, plugins, auth, channels, tools, update, secrets, discovery sub-schemas continue
  }
}
```

### 17.3 Notable observations

**Schema paths that exist on 2026.4.27** (confirmed via `cat ~/.openclaw/openclaw.json` from the live laptop):

- `gateway.bind`, `gateway.port`, `gateway.mode`, `gateway.auth.{mode,token}` ✓
- `meta.lastTouchedVersion`, `meta.lastTouchedAt` ✓
- `auth.profiles.<id>.{provider,mode,displayName}`, `auth.order.<provider>` ✓
- `agents.defaults.model.primary`, `agents.defaults.models.<id>`, `agents.list[]` ✓
- `wizard.lastRunAt` ✓
- `plugins.entries.<name>.{enabled,config}` ✓ — confirmed entries: `anthropic`, `openai`, `browser`, `acpx`, `tavily`
- `update.{checkOnStart,auto.enabled}` ✓
- `tools.web.search.provider` ✓
- `discovery.mdns` exists as a parent object but is empty (`{}`) on a healthy install.

**Schema paths the installer used to write but that no longer exist on 2026.4.27** (FIX 2 removed):

- `discovery.mdns.mode` — `openclaw config set discovery.mdns.mode off` returns `Config path not found`. The bonjour SIGTERM bug it was meant to suppress doesn't fire on this version (validated via clean journalctl over multiple installs). Forward-compatible protection comes from the env var drop-in (`OPENCLAW_DISABLE_BONJOUR=1`) instead.
- `skills.entries.coding-agent.enabled` — Same reason. The codex/coding-agent silent-default bug doesn't fire on 2026.4.27.

**Schema structure highlights**:

- Most leaf properties have human-readable `title` and `description` fields, useful for UI generation or `openclaw config validate`-style error messages.
- Many enum-like fields are encoded as `anyOf` with `const` branches rather than `enum` — supports forward-compatible string extension.
- `additionalProperties: false` is enforced on most well-defined parent objects (e.g. `meta`, `wizard`), so schema-set-then-validate is strict.
- Secrets / tokens (`gateway.auth.token`, `plugins.tavily.config.webSearch.apiKey`) are stored inline in `openclaw.json` (mode 600). For long-lived deployments, prefer the `--ref-provider` / `--ref-source env --ref-id ...` form documented in `openclaw config set --help` so secrets stay in env or external secret stores.

Re-run `openclaw config schema 2>&1 > openclaw-schema.json` after every `OPENCLAW_VERSION` pin bump and diff against this file's previous capture to spot schema drift.

---

## 18. Reference Healthy Install State (2026.4.27)

> Captured after manual `openclaw gateway install --force --port 8787` succeeded on laptop, May 1 2026. Use as baseline for diagnosing future installs that produce subtly different state. Re-capture after every `OPENCLAW_VERSION` pin bump.

### 18.1 systemd unit file

`~/.config/systemd/user/openclaw-gateway.service`:

```ini
[Unit]
Description=OpenClaw Gateway (v2026.4.27)
After=network-online.target
Wants=network-online.target
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 8787
Restart=always
RestartSec=5
RestartPreventExitStatus=78
TimeoutStopSec=30
TimeoutStartSec=30
SuccessExitStatus=0 143
KillMode=control-group
Environment=HOME=/home/clawuser
Environment=TMPDIR=/tmp
Environment=PATH=/usr/bin:/home/clawuser/.local/bin:/home/clawuser/.npm-global/bin:/home/clawuser/bin:/home/clawuser/.volta/bin:/home/clawuser/.asdf/shims:/home/clawuser/.bun/bin:/home/clawuser/.nvm/current/bin:/home/clawuser/.fnm/current/bin:/home/clawuser/.local/share/pnpm:/usr/local/bin:/bin
Environment=OPENCLAW_GATEWAY_PORT=8787
Environment=OPENCLAW_SYSTEMD_UNIT=openclaw-gateway.service
Environment="OPENCLAW_WINDOWS_TASK_NAME=OpenClaw Gateway"
Environment=OPENCLAW_SERVICE_MARKER=openclaw
Environment=OPENCLAW_SERVICE_KIND=gateway
Environment=OPENCLAW_SERVICE_VERSION=2026.4.27

[Install]
WantedBy=default.target
```

Confirms: gateway runs as a node process bound to port 8787, restarts on most failures, has `TimeoutStartSec=30` (overridden to `infinity` by drop-in — see 18.5).

### 18.2 ~/.openclaw/openclaw.json (token redacted)

```json
{
  "gateway": {
    "bind": "loopback",
    "port": 8787,
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "<REDACTED>"
    }
  },
  "meta": {
    "lastTouchedVersion": "2026.4.27",
    "lastTouchedAt": "2026-05-01T09:42:57.938Z"
  },
  "auth": {
    "profiles": {
      "anthropic:default": {
        "provider": "anthropic",
        "mode": "api_key",
        "displayName": "Anthropic (default)"
      }
    },
    "order": { "anthropic": [ "anthropic:default" ] }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "anthropic/claude-sonnet-4-6" },
      "models": {
        "openai/claude-sonnet-4-6": {},
        "anthropic/claude-sonnet-4-6": {}
      }
    },
    "list": [
      { "id": "main" },
      { "id": "orchestrator", "name": "orchestrator", "workspace": "/home/clawuser/.openclaw/agents/orchestrator", "agentDir": "/home/clawuser/.openclaw/agents/orchestrator/agent", "identity": { "name": "orchestrator" } },
      { "id": "skill-scout", "name": "skill-scout", "workspace": "/home/clawuser/.openclaw/agents/skill-scout", "identity": { "name": "skill-scout" }, "agentDir": "/home/clawuser/.openclaw/agents/skill-scout/agent" }
    ]
  },
  "wizard": { "lastRunAt": "2026-04-24T18:48:44-06:00" },
  "plugins": {
    "entries": {
      "anthropic": { "enabled": true },
      "openai":    { "enabled": true },
      "browser":   { "enabled": false },
      "acpx":      { "enabled": false },
      "tavily":    { "enabled": true, "config": { "webSearch": { "apiKey": "<REDACTED>" } } }
    }
  },
  "update": { "checkOnStart": false, "auto": { "enabled": false } },
  "tools":  { "web": { "search": { "provider": "tavily" } } },
  "discovery": { "mdns": {} }
}
```

Confirms: token-auth gateway bound loopback on 8787, default model is `anthropic/claude-sonnet-4-6`, 3 agents enumerated (main + orchestrator + skill-scout), 5 plugins configured, `discovery.mdns` exists as empty object (no schema path to set `mode` on this version).

### 18.3 ~/.openclaw/ directory listing

```
total 100
drwx------ 12 clawuser clawuser 4096 May  1 09:42 .
drwx------ 10 clawuser clawuser 4096 Apr 26 07:53 ..
-r--r--r--  1 clawuser clawuser  873 Apr 24 19:37 SOUL.md
-r--r--r--  1 clawuser clawuser   64 Apr 24 19:37 SOUL.md.sha256
drwxr-xr-x  7 clawuser clawuser 4096 Apr 26 07:54 agents
-rw-------  1 clawuser clawuser  205 Apr 24 18:47 auth-profiles.json
drwxr-xr-x  2 clawuser clawuser 4096 Apr 25 05:38 canvas
drwx------  2 clawuser clawuser 4096 Apr 26 09:26 cron
drwxrwxr-x  2 clawuser clawuser 4096 Apr 26 10:06 devices
-rw-------  1 clawuser clawuser  180 Apr 26 10:01 exec-approvals.json
-rw-------  1 clawuser clawuser  135 Apr 26 09:30 external-keys.json
drwxr-xr-x  9 clawuser clawuser 4096 Apr 26 07:53 factory
drwxr-xr-x  2 clawuser clawuser 4096 Apr 26 07:40 identity
drwx------  2 clawuser clawuser 4096 Apr 24 18:28 logs
-rw-------  1 clawuser clawuser 2131 May  1 09:42 openclaw.json
-rw-------  1 clawuser clawuser 2156 May  1 09:42 openclaw.json.bak
-rw-------  1 clawuser clawuser 2094 May  1 09:42 openclaw.json.bak.1
-rw-------  1 clawuser clawuser 2002 Apr 26 10:05 openclaw.json.bak.2
-rw-------  1 clawuser clawuser 1720 Apr 26 09:39 openclaw.json.bak.3
-rw-------  1 clawuser clawuser 1679 Apr 26 09:30 openclaw.json.bak.4
-rw-------  1 clawuser clawuser 2131 May  1 09:43 openclaw.json.last-good
drwxr-xr-x  3 clawuser clawuser 4096 Apr 24 17:37 plugin-runtime-deps
drwx------  2 clawuser clawuser 4096 Apr 25 05:38 tasks
-rw-------  1 clawuser clawuser   49 Apr 25 18:45 update-check.json
drwxr-xr-x  5 clawuser clawuser 4096 Apr 25 20:07 workspace
```

Confirms: `SOUL.md` is mode 444 (read-only — installed in Step 11 and `chattr +i`-equivalent via mode bits), 5 `openclaw.json.bak*` rolling backups (openclaw auto-rotates on every config write), `auth-profiles.json` is mode 600, `plugin-runtime-deps/` exists from Step 8b npm pre-install.

### 18.4 ~/.openclaw/agents/ directory listing

```
drwxr-xr-x  7 clawuser clawuser 4096 Apr 26 07:54 .
drwx------ 12 clawuser clawuser 4096 May  1 09:42 ..
drwx------  4 clawuser clawuser 4096 Apr 26 07:44 main
drwxr-xr-x  6 clawuser clawuser 4096 Apr 26 08:08 orchestrator
drwxr-xr-x  3 clawuser clawuser 4096 Apr 26 08:07 publisher
drwxr-xr-x  3 clawuser clawuser 4096 Apr 26 08:07 skill-builder
drwxr-xr-x  5 clawuser clawuser 4096 Apr 26 10:06 skill-scout
```

Confirms: 5 agent directories (main + 4 factory agents).

### 18.5 ~/.config/systemd/user/ directory listing

```
total 24
drwxrwxr-x 4 clawuser clawuser 4096 Apr 25 18:45 .
drwxrwxr-x 3 clawuser clawuser 4096 Apr 24 16:50 ..
drwxr-xr-x 2 clawuser clawuser 4096 Apr 25 05:32 default.target.wants
-rw-rw-r-- 1 clawuser clawuser  619 Apr 24 16:50 docker.service
-rw-r--r-- 1 clawuser clawuser 1065 Apr 25 05:32 openclaw-gateway.service
drwxr-xr-x 2 clawuser clawuser 4096 Apr 25 19:53 openclaw-gateway.service.d
```

Drop-in directory contents (`openclaw-gateway.service.d/`) on this snapshot:

```
total 12
drwxr-xr-x 2 clawuser clawuser 4096 Apr 25 19:53 .
drwxrwxr-x 4 clawuser clawuser 4096 Apr 25 18:45 ..
-rw-r--r-- 1 clawuser clawuser   84 Apr 25 20:04 insecure-loopback.conf
```

`insecure-loopback.conf` contents (auto-written by `openclaw gateway install --force` itself):

```ini
[Service]
Environment=OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
TimeoutStartSec=infinity
```

> **Note**: this snapshot is from a manual `openclaw gateway install --force` run, not a full setup.ps1 run. A full installer run also writes `clawfactory-tunables.conf` (TimeoutStartSec=infinity from sub-block c) and `clawfactory-disable-bonjour.conf` (Environment=OPENCLAW_DISABLE_BONJOUR=1 from post-install FIX 1). Both coexist with `insecure-loopback.conf` because systemd merges all `*.conf` drop-ins on `daemon-reload`.

### 18.6 systemctl unit-files inventory

```
openclaw-gateway.service                         enabled   enabled
```

Confirms: unit is enabled at user scope, will start on next user-systemd boot.

### 18.7 systemctl is-active

```
active
```

Confirms: gateway is running.

### 18.8 What this baseline confirms

- `openclaw gateway install --force --port 8787` (the canonical install used in setup.ps1 Step 8b after commit a10a4a6) does in fact:
  - auto-generate the gateway token,
  - write a 1065-byte systemd user unit at the documented path,
  - write its own `insecure-loopback.conf` drop-in setting `TimeoutStartSec=infinity` (which means our Step 8b sub-block c `clawfactory-tunables.conf` is now redundant on this version — both set the same thing),
  - leave the unit in `enabled` + `active` state immediately after install.
- Schema paths that 2026.4.27 actually has are exactly the ones listed in section 17.3.
- The 5-rolling-`.bak` backup pattern openclaw uses on `openclaw.json` writes is intentional — useful for rollback diagnosis.
- `discovery.mdns` exists as `{}`, not as `{"mode": "off"}`. Consistent with FIX 2's removal rationale.
