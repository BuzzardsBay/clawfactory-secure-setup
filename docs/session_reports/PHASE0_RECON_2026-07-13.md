# Phase 0 Recon — ClawFactory v1.1 "Workbench" gate

**Date:** 2026-07-13
**Scope:** Read-only reconnaissance. No product code, installer, `resources/`, `.iss`, Studio source, or installed WSL state was modified. Evidence is verbatim command output in fenced blocks. Every load-bearing statement is labeled **VERIFIED** / **INFERRED** / **GENERAL**.
**Target of live inspection:** the running install on this machine — WSL2 Ubuntu, `clawuser`, OpenClaw `2026.4.27`, ClawFactory gateway on `127.0.0.1:8787`. (No Azure VM was up; no isolated test machine exists — see BLOCKED.)

---

## DECISIONS-REQUIRED (the three branch calls, one line each)

1. **Studio branch → A (substantially working shell).** It boots headless, serves the built SPA + REST, talks to OpenClaw over the CLI/HTTP path today. Build the four v1.1 panels into it. **Caveat:** the *streaming-chat* WebSocket path to the gateway (`:8787`) is unverified and device-pairing-gated, but it is isolated to one feature and avoidable via the existing turn-based CLI path — so it does **not** demote this below A. (Fed by **0.1**.)
2. **Mount mechanism → drvfs (NOT Docker bind volumes).** Agents execute as `clawuser` node processes on the WSL ext4 filesystem; zero containers run, idle or active. (Fed by **0.2**, corroborated by **0.4** mount tests.)
3. **Governor → meter-and-alert (b). Hard enforce (a) is NOT native; a true pre-call hard cap needs a proxy (c).** OpenClaw natively meters tokens+cost (`gateway usage-cost`, per-call `usage` records) but has no budget/cap that can block a call. (Fed by **0.5**.)

---

## Comprehension gate (in my own words)

The build plan hangs on three branch decisions; this recon exists to make each answerable without a follow-up:

- **Decision 1 — What is Studio and can we build on it?** Determines the *release shape*: extend Studio (A), extend-but-add-time (B), or slip Studio to v1.2 and ship installer+grants+templates via ClawChat (C). **Fed by Task 0.1** (framework, launch, surfaces, gateway-connection mechanism, code health).
- **Decision 2 — How do we expose user folders to agents?** Determines whether the folder-access feature uses a **drvfs mount** into the WSL filesystem or **Docker bind volumes**. This depends entirely on *where agent work actually executes*. **Fed by Task 0.2** (process model), **corroborated by Task 0.4** (mount feasibility).
- **Decision 3 — Can the spend governor hard-stop, or only meter?** Determines whether v1.1 ships **hard caps** or a **live meter + alerts**, and whether a metering **proxy** is required. **Fed by Task 0.5** (OpenClaw cost/usage surface).

(Tasks 0.3 and 0.4 also feed Section 6 skill-catalog scope and the install-health/mount premises respectively.)

---

## Task 0.1 — Studio inventory → **Branch A** — DONE

### Framework & stack — VERIFIED
Browser web-app (React SPA + Node/Express backend), monorepo via npm workspaces. **No Electron, no Tauri** (Tauri is Phase-4-planned only).

`frontend/package.json` (verbatim):
```json
"dependencies": {
  "react": "^18.3.1", "react-dom": "^18.3.1", "react-markdown": "^10.1.0",
  "react-router-dom": "^6.27.0", "remark-gfm": "^4.0.1"
},
"devDependencies": {
  "@vitejs/plugin-react": "^4.3.0", "autoprefixer": "^10.4.20", "postcss": "^8.4.47",
  "tailwindcss": "^3.4.13", "typescript": "^5.6.0", "vite": "^5.4.8"
}
```
`backend/package.json` (verbatim):
```json
"dependencies": { "express": "^4.21.0", "cors": "^2.8.5", "ws": "^8.18.0", "zod": "^3.23.8" },
"devDependencies": { "tsx": "^4.19.0", "typescript": "^5.6.0", "@types/node": "^22.7.0", ... }
```
Root `package.json`: `"workspaces": ["backend","frontend"]`, build = `build:frontend && build:backend`; frontend SPA emitted to `backend/public/`, backend TS → `backend/dist/`.

### Does it launch? — VERIFIED (headless boot; browser GUI not driven — see BLOCKED)
The pre-built backend (`backend/dist/index.js` + `backend/public/` both present) was booted headless on port 8099 with the gateway client pointed at a **dead port (59999)** so it could not touch the real `:8787` gateway (hazard rule #5). It came up cleanly and served everything:
```
=== /api/health ===   {"status":"ok","uptime":7.7989654}
=== /api/version ===  {"studio":"0.1.0","openclaw":{"ok":true,"version":"OpenClaw 2026.4.27 (cbc2ba0)"},"gateway":{"reachable":true},"timestamp":"2026-07-13T23:18:03.118Z"}
=== / (SPA index) ===  <!doctype html> ... <title>ClawFactory Studio</title> <script type="module" ... src="/assets/index-CRTanV6N.js">
```
Boot log — the WS gateway client **only ever dialed the dead `:59999`, never `:8787`**, and REST kept working while it looped in backoff:
```
[info]  ClawFactory Studio backend listening { url: 'http://127.0.0.1:8099', nodeEnv: 'production' }
[info]  gateway connecting { url: 'ws://127.0.0.1:59999/' }
[warn]  gateway error { err: 'connect ECONNREFUSED 127.0.0.1:59999' }
[info]  gateway reconnect scheduled { delayMs: 1000, attempt: 1 }
... (exponential backoff, never targets :8787) ...
```
Process was killed afterward; port freed (resource ledger below). **INFERRED:** the SPA renders correctly in a browser (served `index.html` + assets are intact and the source is complete) — not visually verified due to the desktop/hazard constraints.

### Surfaces present (8 routed views) → v1.1 panel map — VERIFIED
`frontend/src/App.tsx` routes (verbatim):
```
/            → StatusPage
/get-started → GetStartedPage
/wizard      → WizardPage (Provider → Key → FirstAgent → Done)
/agents      → AgentsListPage
/agents/new  → AgentEditorPage
/agents/:name→ AgentEditorPage
/skills      → SkillsPage
/chat        → ChatPage
/settings    → SettingsPage
```
| Studio surface | v1.1 panel mapping |
|---|---|
| Status | **Activity** (health/status pills) — partial |
| Chat | **Workspace** (agent interaction) — partial |
| Agents list/editor | **Workspace** (agent management) — adjacent |
| Skills (ClawHub search/preview/install) | **Templates** (catalog) — closest existing analog |
| Wizard, Get-Started | onboarding — *unrelated to the 4 panels* |
| Settings | config/SOUL/key-rotation — *unrelated* |
| *(none)* | **Files & Preview** — **not built** |

**Takeaway:** the shell is real and extensible, but the *four v1.1 panels are net-new* — Studio is organized around agents/skills/chat/settings, and there is **no Files & Preview surface** at all.

### How does it talk to the gateway? (DISQUALIFYING) — VERIFIED
Studio uses **two** paths:

- **CLI/HTTP path (safe, used by most features):** `backend/src/services/openclaw-cli.ts` spawns `wsl.exe -d Ubuntu -u clawuser -- bash -lc 'openclaw ...'`. Version, agents CRUD, skills, settings, and turn-based chat all use this. `services/chat.ts` header (verbatim): *"For v1 of Studio, we use the simpler turn-based CLI: `openclaw agent --message ...`"*. No gateway socket involved.

- **Gateway WebSocket path (the risk):** `backend/src/services/gateway-client.ts` opens a **single persistent WS** and is **eager-started at boot** (`index.ts:81` — `getGatewayClient(); // eager-start the gateway connection`). Endpoint + Origin (verbatim):
```js
const url = `ws://${config.gatewayHost}:${config.openclawGatewayPort}/`;   // → ws://127.0.0.1:8787/
const ws = new WebSocket(url, {
  headers: { Origin: `http://${config.gatewayHost}:${config.openclawGatewayPort}` },  // spoofs dashboard origin
});
```
It connects to the **same `:8787` endpoint as the control-UI dashboard** and spoofs the dashboard Origin — BUT it deliberately does **not** use the dashboard client identity (verbatim comment + connect params):
```js
// We connect as 'cli' (not 'openclaw-control-ui') because the dashboard
// identity carries lifecycle semantics — when the gateway sees the dashboard
// disconnect, it treats the operator console as "gone" and starts shutting
// down. Studio is a long-lived backend service ...
const params = { client: { id: 'cli', ... mode: 'backend' }, role: 'operator', ... };
```
It also requires **device pairing** — on first connect it gets `NOT_PAIRED` and instructs the user to *"Open http://127.0.0.1:8787/ in a browser and approve 'ClawFactory Studio'"* — i.e., the pairing step is the very dashboard action ClawFactory forbids.

**Plain statement:** Studio does **not** naively impersonate the `openclaw-control-ui` client (it was explicitly engineered around the restart lifecycle), **but** it does keep a persistent, boot-eager WS to the hazardous `:8787` endpoint for *streaming chat*, and that dependency is (a) **unverified** against a live gateway — I did not connect it, since doing so is hazard rule #5 — and (b) **pairing-gated** through the forbidden dashboard. It is not "wrong" enough to disqualify, because every other feature uses the CLI path and streaming chat can fall back to the existing turn-based CLI path. **Effort note:** budget rework/verification for the streaming-chat WS bridge (or drop it to CLI turn-based) before relying on it.

### Line count & health — VERIFIED
```
backend/src TS:      4,668 lines in 29 files
frontend/src TSX+TS: 3,923 lines in 31 files
TOTAL (incl. CSS):   8,658 lines
TODO/FIXME/HACK/XXX in source: 0
```

### Branch recommendation — **A**
Substantial (8.6k LOC), clean (0 TODO), builds, boots, serves the SPA+REST, and reaches OpenClaw over a working CLI/HTTP path. Not hollow (rules out B); clearly usable (rules out C). Build the four panels in; treat the streaming-chat WS bridge as a scoped rework item.

---

## Task 0.2 — Where do agent workloads execute? → **clawuser processes, NOT containers** — DONE

**Answer: agents run as `clawuser`-owned OpenClaw (node) processes on the WSL ext4 filesystem. No containers are involved — idle or active.** The build plan's INFERRED assumption is confirmed; the mount mechanism is **drvfs**, not bind volumes.

Idle process tree — a single node gateway owned by `clawuser`:
```
clawuser  317  248  /usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 8787
```
`docker` is installed (rootless) but **no containers run at idle**:
```
$ docker --version → Docker version 29.5.2, build 79eb04c
$ docker ps        → (header only; zero containers)
```
During an actively-running agent turn (`openclaw agent --agent main ...`), 12 samples at ~1 s intervals — the worker is a `clawuser` `openclaw-agent` process, and **`docker_running=0` throughout**:
```
=== sample 4 @ 17:12:17 docker_running=0 ===
clawuser  2540 2538   \_ timeout 150 openclaw agent --agent main --json --message ...
clawuser  2541 2540       \_ openclaw
clawuser  2562 2541           \_ openclaw-agent
clawuser   317  248  \_ /usr/bin/node .../openclaw/dist/index.js gateway --port 8787
... (docker_running=0 on all 12 samples) ...
```
Owning UID and on-disk location — `clawuser` (uid 1000), work rooted on the WSL native ext4 disk:
```
$ id (clawuser) → uid=1000(clawuser) gid=1000(clawuser) groups=1000(clawuser)
$ df -T ~/.openclaw → /dev/sdd  ext4  ... 1% /
$ findmnt ~        → ext4  /dev/sdd
```
There is **no** `sandbox`/`container`/`docker`/`isolation` key anywhere in `openclaw.json` (grep returned nothing).

> **Contradiction flagged (see SURPRISES #2):** Studio's own `docs/ARCHITECTURE.md` claims the gateway *"spawns Docker containers per agent (sandbox=all, network=none)."* That is **false** on this live install.

---

## Task 0.3 — skill-scout / skill-builder / orchestrator / publisher + plugin system — DONE

### The four agents (verbatim) — VERIFIED
**`skill-scout`, `skill-builder`, `publisher` are placeholder stubs — their real prompts never shipped.** Representative (`~/.openclaw/agents/skill-scout/agent.md`, verbatim):
```
# skill-scout — placeholder

This agent's role-specific prompt has not shipped with this installer build.
The file `resources/skill-scout-prompt.md` was missing when bootstrap.ps1 ran;
this placeholder will be replaced atomically the next time the installer
runs against a build that does include the real prompt.

## What it can do today
Nothing useful, by design. Until a real prompt lands here, the orchestrator
will not route work to this agent — and a direct chat against it will get a
stub reply.
```
`skill-builder` and `publisher` are byte-identical in shape (only the one-line role differs: builder *"Builds and tests OpenClaw skills from scout opportunities; never publishes on its own."*; publisher *"After your explicit 'GO', pushes a finished skill to ClawHub + GitHub and verifies it is live."*).

**`orchestrator` has a real prompt** (`~/.openclaw/agents/orchestrator/agent.md`, verbatim excerpt):
```
# Orchestrator — First Activation Prompt
You are the **Orchestrator** of the ClawFactory Skills Factory ...
### Startup integrity check — run before every user interaction
2. Expected value (pinned at install time): `b8d8145b5a0bd800636519384484aa2940a204962cb97e18b5b0dc7fa13609bb`
3. If the computed hash does not match ... output exactly:
   `SOUL.md integrity check failed — refusing to act.`
## "GO" gating   (git push / openclaw publish / writes outside workspace / off-allowlist tools)
## Tool allowlist (enforced by gateway): `github`, `clawhub`, `fs.readLimited`, `fs.writeWorkspace`
## Tool denylist  (enforced by gateway): `shell`, `sudo`, `rm`, `system.run`, `browser`, `net.fetch`
```
(Agents present on disk: `main`, `orchestrator`, `publisher`, `skill-builder`, `skill-scout`.)

### Plugin config (redacted) — VERIFIED
There is **no Tavily plugin** (spec assumed one — see SURPRISES #4). Raw `openclaw.json` `.plugins` (secrets redacted at source; `jq` is absent so `python3`/CLI redaction used):
```json
{ "entries": { "bonjour": { "enabled": false }, "anthropic": { "enabled": true } } }
```
`openclaw config get plugins` (CLI adds the built-in `memory-core` default):
```json
{ "entries": { "bonjour": {"enabled": false}, "anthropic": {"enabled": true, "config": {}}, "memory-core": {"config": {}} } }
```
Grep for `tavily` anywhere in `openclaw.json` → **no matches**.

### OpenClaw plugin system (searched first, cited) — VERIFIED (docs)
From the official docs ([cli/plugins](https://docs.openclaw.ai/cli/plugins), [plugins/manifest](https://docs.openclaw.ai/plugins/manifest), [plugins/manage-plugins](https://docs.openclaw.ai/plugins/manage-plugins)):
- **CLI exists:** `openclaw plugins` with `install`, `list`, `uninstall`, `enable`/`disable`, `update`, `search`, `inspect/info`, `build`, `validate`, `init`, `doctor`, `registry`, `marketplace`.
- **Install:** `openclaw plugins install <path-or-spec>`; npm registry specs only (git/URL/file specs rejected); dependency installs run `--ignore-scripts`.
- **Version pinning:** `openclaw plugins install <npm-spec> --pin` saves the exact `name@version` in the managed index (npm only; git pins via ref).
- **Manifest:** every plugin ships `openclaw.plugin.json` with an inline JSON Schema (`configSchema`, even if empty); missing/invalid manifest fails config validation.
- **Permissions:** loader path-safety checks (ownership, world-writable) + `plugins.allow` / `plugins.entries.<id>` config; conversation hooks require `plugins.entries.<id>.hooks.allowConversationAccess=true`. The docs do **not** enumerate per-plugin *network/domain* allowlists in the manifest.

### Section-6 skill-catalog scope — one-page assessment
- **OpenClaw already provides:** the plugin *plumbing* (install/list/remove/pin, manifest+schema validation, marketplace/ClawHub search) and a coarse permission model. Studio already wraps a **Skills browser** (ClawHub search → preview `SKILL.md` → install with explicit `acknowledged: true`).
- **ClawFactory must supply itself:** the actual **agent behavior** for the catalog flow. `skill-scout`/`skill-builder`/`publisher` are empty shells — their prompts (`resources/*-prompt.md`) were never bundled, so the scout→build→publish pipeline the build plan's Section 6 assumes **does not exist yet** and the orchestrator explicitly won't route to them. This matches (and hardens) the plan's assumption that the agents are thin: they are not thin, they are **absent**. Also missing from OpenClaw natively: per-plugin *domain/egress* declarations (must be enforced by ClawFactory's egress firewall, not the manifest).

---

## Task 0.4 — Clean-install validation + mount feasibility — PARTIAL (clean-install BLOCKED)

### Clean install of v1.0.37 + 6-check smoke — **BLOCKED**
A clean install could not be performed: the only live install is on this working machine, and a clean install would **destroy Bret's actual WSL environment** — a state change forbidden by the read-only mandate and by the "validation stays off the local desktop" rule. No Azure VM was running, and the referenced `ClawFactory_Test_Machine_Protocol.md` **does not exist** (see BLOCKED/SURPRISES). *Substitute:* the smoke suite was run against the **existing** install (non-destructive — gateway already up, so the start-block early-exits).

**Smoke test vs the existing install (VERBATIM):** *(the current `smoke-test.ps1` has 11 checks, not "6")*
```
  FAIL  WSL automount disabled
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

Result: 10 pass, 1 fail, 0 skip
```
**The gateway check PASSES**, and the two flapping-fix checks (`.wslconfig vmIdleTimeout=-1`, `WSL Host scheduled task`) PASS → **the build plan is NOT preempted.** The lone FAIL is `WSL automount disabled` — because automount is **enabled** here (SURPRISES #3). VERIFIED.

### Gateway idle stability — VERIFIED (no flapping)
Stronger than a 10-minute idle window: the gateway process has **~8 hours of continuous uptime** and still returns 200. A process up for 28,642 s cannot have "flapped every 60–180 s."
```
gateway_ps_line:  317  28642  07:57:22  Mon Jul 13 09:27:11 2026  /usr/bin/node .../openclaw/dist/index.js gateway --port 8787
gateway_pid=317   uptime_seconds=28642   http_status_now=200   now=17:24:34
```
The same PID 317 was observed across the whole recon window (17:06 → 17:24) with no interaction and no dashboard opened. *(My scripted 10-min PID-diff probe had a `pgrep` bug and produced empty fields; the uptime measurement above supersedes it.)*

### Mount feasibility (drvfs, as root, uid/gid=1000, then unmounted) — VERIFIED
`clawuser` = uid 1000 (matches `uid=1000,gid=1000`). All tests unmounted and their scratch dirs removed (resource ledger).

| Path type | mount | clawuser read+write | Verdict |
|---|---|---|---|
| Normal local (`C:\Users\bmcki\Documents\...`) | ✅ `mount_exit=0` | ✅ read seed + WRITE_OK | **Supportable** |
| OneDrive-backed (`C:\Users\bmcki\OneDrive\...`) | ✅ `mount_exit=0` | ✅ read seed + WRITE_OK | **Supportable — hydrated files only** (on-demand/placeholder hydration untested → **UI warning**) |
| Spaces + non-ASCII (`...\Claw Recön Tëst`) | ✅ `mount_exit=0` | ✅ read seed + WRITE_OK | **Supportable** (cosmetic: `mount` output truncates the path at the space) |
| Mapped network drive | — | — | **Untestable here (none mapped)** → verify before enabling; default **warn/deny** |

Representative verbatim (normal local):
```
--- mount (root) --- mount_exit=0
C:/Users/bmcki/Documents/ClawReconMount on /mnt/recontest type 9p (rw,...;metadata;uid=1000;gid=1000;...)
--- clawuser read + write ---
-rwxrwxrwx 1 clawuser clawuser 18 ... seed.txt
--read seed-- seed-from-windows
--write-- WRITE_OK / claw-wrote-this
--- umount --- umount_exit=0
```
**Bonus finding (drives design):** because **automount=true**, `C:\` is **already** mounted and reachable by `clawuser`:
```
C:\ on /mnt/c type 9p (rw,...;path=C:\;uid=1000;gid=1000;...)
clawuser CAN list /mnt/c/Users/bmcki/Documents
```
So on this install the folder-access feature could use `/mnt/c/...` directly — but that exposes **all** of `C:`. Scoped, on-demand drvfs mounts (with automount=false) are the more secure design; that is a v1.1 UI/security decision, not a feasibility blocker.

**Recommendation:** allow-list normal local paths; warn on OneDrive (placeholder hydration) and spaces/non-ASCII (works, but tooling that parses `mount` output must handle the truncation); test-then-decide on mapped network drives.

---

## Task 0.5 — Spend governor enforcement point → **(b) meter-and-alert; (c) proxy for a hard cap** — DONE

### Searched first (cited) — VERIFIED (docs/community)
- [reference/token-use](https://docs.openclaw.ai/reference/token-use): per-call usage is exposed (`/usage tokens`, `/usage cost`, `/usage full`); transcript entries persist a normalized `usage` shape incl. `usage.cost` when the model has pricing (`models.providers.<p>.models[].cost`, USD/1M). **No config-level budget/spend cap that blocks a call is documented.**
- [cli/gateway](https://docs.openclaw.ai/cli/gateway): `openclaw gateway usage-cost` (`--days`, `--agent`, `--all-agents`, `--json`) reads usage-cost from session logs.
- Community guidance is explicit: *"budget limits are not natively in OpenClaw"* — hard stops require a **proxy** (e.g., LiteLLM virtual keys with budgets) or a custom skill that disables the gateway; `maxConcurrentRuns` is only a soft control.

### Live inspection — VERIFIED
`openclaw gateway usage-cost --json --days 30` returns real per-day tokens **and** cost:
```json
{ "date": "2026-06-14", "input": 90, "output": 240, "cacheRead": 0, "cacheWrite": 660300,
  "totalTokens": 660630, "totalCost": 2.4799950..., "cacheWriteCost": 2.476125... }
```
Per-**call** token counts are recorded in session trajectories (`~/.openclaw/agents/main/sessions/*.trajectory.jsonl`) on `model.completed` events (verbatim `usage` object):
```
PARENT TYPE KEY: model.completed
USAGE FIELD: {"input": 3, "output": 8, "cacheWrite": 16435, "total": 16446}
```
`~/.openclaw/logs/` does **NOT** record token counts — it holds only:
```
-rw------- config-audit.jsonl
-rw------- config-health.json
```
There is **no** budget/cap key in `openclaw.json` (agents config shows `maxConcurrent: 4`, no spend limit).

### Definitive call — VERIFIED
- **(a) Enforce — NO.** No pre-call hook/budget exists that can block a call before it hits the provider.
- **(b) Meter-and-alert — YES (achievable natively).** Poll `gateway usage-cost --json` (or tail trajectory `model.completed.usage`) → live spend meter + threshold alerts. This is what v1.1 should ship.
- **(c) Proxy — REQUIRED for a real hard cap.** To *block* an over-budget call, route provider traffic through a local metering proxy inside the sandbox that rejects once the cap is hit. **Sketch (do not build):** a loopback HTTPS proxy (e.g., LiteLLM-style) in WSL between OpenClaw and the provider; OpenClaw's provider base-URL points at it; it counts tokens per response and 402s/queues when the daily/monthly cap is exceeded. **Egress-firewall interaction:** the allowlist must then permit the provider host *only from the proxy* (or the proxy becomes the sole allowed egress to the provider), and the proxy's own upstream TLS to the provider must be on the allowlist — i.e., the cap and the firewall must agree on exactly one egress path.

**Ship recommendation:** v1.1 = **live meter + alerts (b)**; document hard caps (a via proxy c) as a follow-on.

---

## SURPRISES (contradictions with the build plan / April docs)

1. **Studio is far more built than "built, untested, no confirmed feature set (April 2026)."** It is ~8,658 LOC, Phase-2-complete per its README, boots headless, and serves a full SPA+REST. (Its README is *internally* inconsistent — the "Layout" section shows a Phase-1 `version.ts`-only skeleton while "Status" claims 5 completed slices; the **source** matches the richer claim.)
2. **Studio `docs/ARCHITECTURE.md` claims the gateway "spawns Docker containers per agent (sandbox=all, network=none)." This is false on the live install** — zero containers idle or active; agents run as `clawuser` processes on ext4 (Task 0.2). This is the single most decision-relevant contradiction (drvfs vs bind volumes).
3. **`automount` is `enabled=true` on the live install** — the spec, the build plan, and the smoke test all assume `false`. Consequence: `/mnt/c` already exposes *all* of `C:` to `clawuser`; the smoke "automount disabled" check FAILS. (I read `/etc/wsl.conf` before and after all mount work — both `true` — so I did not change it; this is pre-existing drift.)
4. **No Tavily plugin exists** anywhere in `openclaw.json` — the task assumed a "Tavily plugin configuration." Only `bonjour` (disabled) + `anthropic` (enabled) are configured.
5. **`skill-scout`, `skill-builder`, `publisher` are placeholder stubs**, not thin agents — their role prompts (`resources/*-prompt.md`) were missing at bootstrap and were never shipped. The scout→build→publish pipeline does not exist yet.
6. **Studio's gateway WS bridge spoofs the dashboard `Origin` and requires device pairing via `http://127.0.0.1:8787/`** — the exact dashboard action ClawFactory forbids. Streaming chat is therefore not usable without either pairing (hazardous) or a rework.
7. **`ClawFactory_Test_Machine_Protocol.md` (referenced by this job's spec) does not exist** anywhere on disk.
8. **The browser-dashboard hazard the spec attributes to `ClawFactory_Install_Lessons_Learned.md` is not in that file** (which contains only the Inno `[UninstallRun]` timing lesson). The gateway-flapping/dashboard-disconnect material lives in `CLAUDE_ClawFactory.md` instead. The hazard is real; the citation is misfiled.
9. **`smoke-test.ps1` has 11 checks, not "6".**

---

## BLOCKED (task/subtask, exact blocker)

- **0.4 clean-install of v1.0.37 + smoke on a clean box** — no isolated test machine exists (no Azure VM up; `ClawFactory_Test_Machine_Protocol.md` missing); a clean install on the sole live machine would destroy Bret's working environment (violates read-only + local-desktop rules). *Mitigation used:* smoke suite run against the existing install (10/11 pass; gateway healthy).
- **0.4 mapped-network-drive mount test** — no network drive is mapped on this machine (`Get-SmbMapping` empty); cannot exercise the path type.
- **0.4 OneDrive on-demand/placeholder hydration** — only hydrated (locally-materialized) files were tested; dehydrated placeholder behavior over drvfs remains unverified.
- **0.1 full visual click-through of the Studio UI** — the browser GUI was not driven (local-desktop rule + the boot-eager WS gateway hazard). Assessed via headless backend boot + complete source instead.
- **Dispatch card fetch/sync (`POST /api/agent/update`)** — no FleetView/card API endpoint, base URL, or credentials exist anywhere in the repo, `.env`, `.claude/`, or `CLAUDE_ClawFactory.md`. I did **not** POST to any invented endpoint. This close-out *is* the deliverable; sync it manually if the dispatch board is external to this machine.

---

## END-OF-SESSION GATE

### 1. Task accounting
| Task | Status |
|---|---|
| 0.1 Studio inventory + branch | **DONE** → Branch **A** |
| 0.2 Where workloads execute | **DONE** → clawuser processes / drvfs |
| 0.3 agents + plugin system | **DONE** → 3 stubs + real orchestrator; plugin CLI mapped |
| 0.4 clean-install + mounts | **PARTIAL** — mounts+smoke+idle DONE; **clean-install BLOCKED** |
| 0.5 spend governor | **DONE** → (b) meter native; (c) proxy for hard cap |
| Dispatch sync | **BLOCKED** (no endpoint) |

### 2. Resource ledger (started/created/mounted → proof removed; system left as found)
- **drvfs mounts** at `/mnt/recontest` (3×, uid/gid=1000) → all `umount`ed; `/mnt/recontest` `rmdir`ed. Proof: `mount | grep recontest` → *"none remain (clean)"*; `ls -ld /mnt/recontest` → *"none (clean)"*.
- **NTFS scratch dirs** `Documents\ClawReconMount`, `OneDrive\ClawReconMount`, `Documents\Claw Recön Tëst` (+ seed files) → `rm -rf`. Proof: `ls -d ...` → *"all NTFS test dirs removed (clean)"*.
- **WSL `/tmp` scratch** `recon_turn.out/err`, `recon_sample.log`, `recon_idle.log` → removed. Proof: `ls /tmp/recon*` → *"none (clean)"*.
- **Studio backend** (Windows `node` pid 39420 on :8099, gateway→dead :59999) → `taskkill /F`. Proof: no LISTENING socket on 8099, no `*ClawFactory-Studio*` node process.
- **Two trivial `openclaw agent` turns** (main agent) — both errored before writing anything (`Message required` / session-selector / 150 s timeout); `recon-probe.txt` was never created (verified absent). Consumed a small amount of Anthropic tokens; no files/config changed.
- **Idle-stability probe** (`sleep 600`) → `pkill`ed; verified no stray `sleep 600`.
- **Not touched:** the pre-existing `sleep infinity` (PID 903, ~7.9 h old = the `ClawFactory WSL Host` keepalive) and gateway PID 317 were left running (original state).

### 3. Delta security sweep
- **No key material in this report** — `grep -E 'tvly-|sk-|ANTHROPIC_API_KEY'` over this file returns nothing. (The `b8d81…` value is the SOUL.md SHA-256 pin, not a secret; usage-cost figures are Bret's own spend metrics, not credentials.)
- **`automount` unchanged** — `enabled=true` before and after all mount work (its pre-existing state; not modified by this recon).
- **Egress firewall unchanged** — smoke check *"Egress firewall clawfactory chain present in nft ruleset"* = PASS; *"Firewall inbound-deny rule on 8787"* = PASS. No firewall or config write occurred.

### 4. Delta bug review (live bugs → listed, not fixed)
- `automount=true` drift (SURPRISES #3) — a live deviation from the intended hardened state; **documented, not fixed**.
- `skill-scout/builder/publisher` placeholder prompts (SURPRISES #5) — missing `resources/*-prompt.md`; **documented, not fixed**.
- Studio `ARCHITECTURE.md` container claim (SURPRISES #2) and README Layout/Status inconsistency (#1) — **documented, not fixed**.

### Git
`git status --short` at start: clean. After recon: clean (no tracked file modified — verified `git diff --stat` empty). Only this new report is staged.
