# OpenClaw 2.0 delta census — reference tables (2026-09-19)

Inputs for the v2 threat model and for the follow-on validation job. **The census does not write the
threat model.** Narrative, evidence trail and the Task 0 verdict live in
`docs/session_reports/2026-09-19_openclaw2_delta_census_closeout.md`; this file holds only the tables
that should survive as a reference.

**Nothing here was measured on a running box.** Every OpenClaw claim is a source read at the tag named,
or `DOCS-ONLY` where it rests on `docs/` prose. Values are `STRUCTURAL` (kernel- or root-enforced against
the agent's uid), `ADVISORY` (gateway-path, prompt-level, or writable by the agent's own uid) or
`UNMEASURED`.

## Upstream state read

| Item | Value |
|---|---|
| Pinned by v1.4.5 (`OPENCLAW_VERSION`) | `2026.4.27` = tag `v2026.4.27`, commit `cbc2ba0931468259f26a7c547131a06e03ca6c6c` (npm 2026-04-29T22:28:04Z) |
| 2.0 first | `2026.8.1` = `ea806575e6450e4d1efdfc72c19f04be982a1b9b` (npm 2026-08-31T02:45:39Z) |
| **Primary 2.0 measurement tag** | `2026.8.2` = `0965053fe6b9341776df147a6934b7485c60b5ca` (npm 2026-09-01T16:19:50Z) |
| Current npm `latest` | `2026.9.5` = `ec9c1a13db8938e5a3eaa51fca2e981cde2395a9` (npm 2026-09-19T01:14:57Z). Read for `install.sh`, `KillMode` and a few spot checks only |
| npm registry fetch | 2026-09-19T15:21:51Z |
| Live `https://openclaw.ai/install.sh` | fetched 2026-09-19T15:21:37Z, sha256 `b8ba3a2d75c27a703de1b335f2a296304e933cbbebd006f83e4c0440498cbc0b`, 150,461 bytes, **byte-identical to `v2026.9.5:scripts/install.sh`** |
| `scripts/install.sh` per tag | 4.27 = 88,796 B; 8.1 = 137,740 B; 8.2 = 140,635 B; 9.5 = 150,461 B |
| Bundled by ClawFactory v1.4.5 | `resources/openclaw-install.sh`, sha256 `3a617b73ea35ac23cf856ce9615b69d0ace4090d236e0a57bbc638f01676a9ce`, 93,387 B. **Matches no upstream tag.** |
| Docs | read from each tag's `docs/` directory on 2026-09-19, not from `docs.openclaw.ai` |
| ClawFactory side | tag `v1.4.5` = `b3ef2d4277efd1fe6000567775d2b51bcb64848e`; `HEAD` = `590022ae9c42468fd091c3bb8b3f15c3672f2d23` (24 commits later; `setup.ps1` +51 lines, firewall/timer read-backs only) |

**Re-read at the tag a pin bump actually targets.** Upstream is five releases past 2.0. Two load-bearing
findings already drifted at `v2026.9.5` (`KillMode` control-group → mixed; a "must never read" comment
was reworded).

### Task 1.2 — Guard 3 allowlist, re-derived from the tree at tag `v1.4.5`

The figure 22 was not carried. It was re-derived and, **for a default install, it reproduces**. It counts **hostnames**, not routes and not addresses (a route is an address set; `clawfactory-toolchain.sh:8-11` carries the 72-address measurement, a different figure). Matching is by resolved **address**, never hostname (`clawfactory-toolchain.sh:50-55`).

| Half | Where | Count | Members |
|---|---|---|---|
| Base | `setup.ps1:1776-1850` (`$baseHosts`) | **9** | `openclaw.ai`, `docs.openclaw.ai`, `nodejs.org`, `deb.nodesource.com`, `archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com`, `esm.ubuntu.com`, `ppa.launchpad.net` |
| Provider (toolchain-independent) | `setup.ps1:94-142` (`AllowlistHosts`) | 6 distinct; **1 per install** (2 for ollama, 0 for `later`) | grok `api.x.ai`; openai `api.openai.com`; claude `api.anthropic.com`; gemini `generativelanguage.googleapis.com`; ollama `ollama.com`, `registry.ollama.ai` |
| Aux (always-open providers) | `setup.ps1:2570` (install) and `:2668` (refresh timer), two identical copies (re-confirmed) | **5** | `api.anthropic.com`, `console.anthropic.com`, `api.openai.com`, `auth.openai.com`, `api.x.ai` |
| Toolchain (software-sources toggle) | `resources/clawfactory-toolchain.sh:94` (`TOOLCHAIN_HOSTS`, re-confirmed) | **8** | `clawhub.ai`, `api.clawhub.ai`, `api.github.com`, `github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`, `codeload.github.com`, `registry.npmjs.org` |
| Policy file | `resources/egress-policy.json` | `read_fetch.allow: []`, `toolchain.enabled: true`, `send_actions: []` | empty by default |

Distinct hostnames for a claude install: 9 + 5 + 8 + 1 provider − 1 overlap (`api.anthropic.com`) = **22**. openai/grok/`later`: 22. gemini: 23. ollama: 24. `HEAD` changes no host list (`git diff v1.4.5 HEAD` over `AUX_HOSTS|baseHosts|AllowlistHosts|toolchainHosts` = 0 hits).

### Task 1.1 — what the pinned `2026.4.27` (what v1.4.5 lands) and 2.0 (`2026.8.2`) can reach in a default config

`ON` = on with no operator action and no key; `KEY` = only once a key/OAuth is configured; `COND` = only on a user or agent action or non-default config; `NO` = not reached. Source column is upstream `<tag>:<path>:<line>`; `DOCS-ONLY` where it rests on `docs/` prose alone.

| Destination | Feature | 4.27 | 2.0 | Source |
|---|---|---|---|---|
| `api.anthropic.com` | chat; **live model discovery** `v1/models` | chat KEY; discovery absent | chat KEY; discovery **ON with key (new)** | `extensions/anthropic/register.runtime.ts:872` |
| `api.openai.com` | chat; live model discovery | chat KEY; discovery absent | discovery **ON with key (new)** | `extensions/openai/openai-provider.ts:92` |
| `api.x.ai`, `generativelanguage.googleapis.com` | chat | KEY | KEY; no live-discovery endpoint found (UNMEASURED beyond static) | `extensions/xai/provider-discovery.ts:9-13` |
| **`catalog.openclaw.ai`** | hosted model catalog + pricing refresh, at start then every 6 h | absent | **ON** (`!== false`) | `src/model-catalog/remote-config.ts:3,6`; `remote-refresh.ts:22` |
| **`openrouter.ai`** | model-pricing bootstrap at gateway start | **ON** (`models.pricing.enabled !== false`) | retired | `v2026.4.27:src/gateway/model-pricing-cache.ts:75,1109` |
| `raw.githubusercontent.com` | same bootstrap (LiteLLM price JSON) | **ON** | retired | `v2026.4.27:…model-pricing-cache.ts:77` |
| `registry.npmjs.org` | 4.27 update hint; plugin installs; install-time | update hint ON | not the update-check host | `v2026.4.27:src/infra/update-check.ts:313` |
| **`telemetry.openclaw.ai`** | daily update check; optional usage statistics | absent | **ON** (`update.checkOnStart` default true); statistics default off | `v2026.8.2:src/infra/telemetry.ts:19` |
| `clawhub.ai` | skill/plugin install, review, promos (CLI only) | COND | COND | `src/infra/clawhub-client.ts:15` |
| `api.clawhub.ai` | in ClawFactory's toolchain list | **in NO upstream tag** (4.27, 8.2, 9.5): 0 hits | same | `git grep -i "api\.clawhub"` on three tags is empty; ClawHub requests are `${baseUrl}/api/v1/…` on `clawhub.ai` (`clawhub-client.ts:173-187`) |
| `github.com`, `codeload.github.com`, `api.github.com` | git-source plugins, llama.cpp binary, gum | COND | COND | `extensions/llama-cpp/src/llama-server-install.ts:68` |
| **`download.db-ip.com`** | geolocation DB, plugin `enabledByDefault` | absent | plugin ON, download lazy, refresh 30 d, soft failure | `extensions/geolocation/src/config.ts:15` |
| **`huggingface.co`** | llama.cpp managed model download | absent | COND, trigger UNMEASURED | `extensions/llama-cpp/src/managed-server.ts:121-201` |
| `api.firecrawl.dev` | Firecrawl | KEY | KEY; keyless "Free" is an explicit choice (`CHANGELOG.md` 8.1, DOCS-ONLY) | `extensions/firecrawl/src/firecrawl-client.ts:53` |
| `www.gravatar.com` | shared-profile avatars | absent | COND (linked emails only) | `src/gateway/user-profiles-http.ts:23-40` |
| `ghcr.io` | named in the prompt | **NO** | **NO** | only QA harness, `scripts/`, k8s manifests; sandbox image is a local tag `openclaw-sandbox:bookworm-slim` (`src/agents/sandbox/constants.ts:15`) |
| telemetry / crash reporting (OTel, Prometheus, Langfuse) | — | NO | NO by default | `CHANGELOG.md` 8.1 (DOCS-ONLY) |
| `skills-sh` mirrors | "through ClawHub's mirrored, commit-pinned artifacts" | n/a | goes to `clawhub.ai`, no separate host | `CHANGELOG.md` 8.1 (DOCS-ONLY) |
| channel hosts (Telegram, Discord, Twitch, Meet, Zoom, Teams) | messaging plugins | NO | NO (unconfigured), but `google-meet`, `zoom-meetings`, `teams-meetings`, `linux-node`, `file-transfer`, `cua-computer`, `canvas`, `geolocation` are `enabledByDefault` | `openclaw.plugin.json` manifests |

Enumeration method: 248 distinct hostnames in non-test upstream source at 2.0 (445 host/unit pairs), classified by file and then by `activation`/`enabledByDefault`. Default-on plugin manifests grew from **67 (of 119)** at 4.27 to **82 (of 151)** at 8.2. **Install-time hosts:** the bundled script references 9 hosts; `v2026.8.2` adds only `docs.openclaw.ai/install/installer`, `openclaw.ai/install-cli.sh` and `*.nodesource.com/setup_${NODE_LINUX_DEFAULT_MAJOR}.x`; `v2026.9.5` adds none beyond 8.2. No new install-time host.

### Task 1.3 — diff: what 2.0 needs against what Guard 3 opens (claude install)

| Host | Feature that needs it | Allowed today? | If denied | Structural or advisory consequence | Recommended default |
|---|---|---|---|---|---|
| `api.anthropic.com` (and other provider) | chat, live discovery | yes (aux + provider) | product bricked | the route that must stay open | **allow** |
| **`catalog.openclaw.ai`** | hosted catalog + pricing (default ON) | **no**: 4 GitHub-Pages addresses (`185.199.108-111.153`), **0 overlap** | shipped catalog and pricing used (DOCS-ONLY) | **structural denial**, fail-soft | **deny** (leave). `models.catalogRefresh.enabled=false` as noise reduction only |
| **`telemetry.openclaw.ai`** | daily update check | **reachable by address**: 3 Cloudflare addresses **identical** to `docs.openclaw.ai` | update hint absent | **not structural**: open because `docs.openclaw.ai` is a base host; cannot be denied by name under address matching | **allow (unavoidable)**; document as address-scoping residual #2 beside the `clawhub.ai` one; set `update.checkOnStart=false` |
| `openrouter.ai` (4.27 pricing bootstrap) | pricing at start on **today's** installs | **no** | pricing left at shipped values | structural denial, silent | **deny**; disappears at 2.0 |
| `raw.githubusercontent.com` | same bootstrap | yes (toolchain) | same | revocable | behind the software-sources toggle |
| `registry.npmjs.org` | update hint; plugin installs | yes (toolchain) | `npm install` fails for the agent | revocable | behind the toggle (unchanged) |
| `clawhub.ai` | skills/plugins, review, promos | yes (toolchain) **and unrevocable**: `216.150.1.1` shared with `openclaw.ai` | installs still work | a structural claim here would be **false**; already documented | unchanged; the toggle does not close it |
| `api.clawhub.ai` | in ClawFactory's list; **no upstream code references it** | yes (toolchain) | UNMEASURED | resolves separately | NEEDS BOX (B-4): drop it from the list if nothing hits it |
| `github.com`, `codeload.github.com`, `api.github.com` | git plugin sources, llama.cpp binary | yes (toolchain) | those fail | revocable | behind toggle (unchanged) |
| `download.db-ip.com` | geolocation DB (lazy) | **no**, no overlap | lookups have no DB; soft | structural denial | **deny** |
| `huggingface.co` | llama.cpp model download | **no**, no overlap | managed local inference cannot fetch | structural denial | **deny**; if ever wanted, a **new** toggle |
| `api.firecrawl.dev` | Firecrawl | **no**, no overlap | unavailable | structural denial | **deny** |
| `www.gravatar.com` | avatars | **no** | no avatars | structural denial | **deny** |
| `ghcr.io` | not reached | n/a | n/a | n/a | **deny** (nothing needs it) |

**Which hosts the standing provider-route census would also have found.** As defined, that census observes the provider route, so on the current pin it finds only the provider host. A boot-and-idle drop-log at the pinned `2026.4.27` would additionally show **`openrouter.ai`** (denied) and **`raw.githubusercontent.com`** (allowed) from the pricing bootstrap, **which has never been measured**. At 2.0 it would add **`catalog.openclaw.ai`** (denied) and **`telemetry.openclaw.ai`** (allowed by address). Per the standing rule an nft drop-log needs **both calibration halves** before any of it is trusted. **This closes the obligation for the pinned version on paper only:** the enumeration is source-derived and the measured half needs a box (B-2, B-3).

DNS-overlap caveat: the resolver was this Windows machine's, not WSL's; Cloudflare and GitHub sets rotate; three lookups each. Controls: `example.com` overlapped 0 (must, did); `clawhub.ai` and `openclaw.ai` overlapped on `216.150.1.1` (must, did).

### Task 1.4 — calibration of the enumeration method

`t1_diff.sh` maps each candidate host to the count of non-test source files referencing it at `v2026.8.2` and to allowlist membership. **Planted host `zz-planted-unused.invalid`:** 0 refs, not allowed, flagged `<== needed by NOTHING in 2.0 source`; positive control `catalog.openclaw.ai` = 1 ref, not flagged; `github.com` = 182 refs. **Planted host removed:** the flag disappeared, every other row identical. **Result:** the method tells "no feature uses this" from "a feature uses this". One real hit fell out of the same run: `api.clawhub.ai` = 0 refs, cross-checked with `git grep -i "api\.clawhub"` on three tags. The method is blind to constructed hostnames, so that result is reported as **"no literal reference in three tags", not "unused"**.

### Task 6 — capabilities OpenClaw 2.0 turns on that the validated 1.x did not have

Measured state: upstream `v2026.8.2` (`0965053f…`) against `v2026.4.27` (`cbc2ba09…`), source-read. **No row here was measured on a running 2.0 box.**
"Structural" means the agent (uid `clawuser`, which is also the gateway's uid) cannot re-enable it because a root-owned or kernel-enforced mechanism prevents it. Every OpenClaw config key lives in the `clawuser`-writable `~/.openclaw/openclaw.json`; no managed or system config layer exists upstream at 8.2 (grep for `/etc/openclaw`, managed policy, read-only config found only TLS/OpenShell paths).

| # | Capability | Default in 2.0 (at 4.27) | Structural control inside the cage today | Advisory-only today | What it would take to make it structural |
|---|---|---|---|---|---|
| 1 | Grounded dreaming (nightly memory consolidation, rewrites `MEMORY.md`) | **ON**, cron `0 3 * * *` (**OFF**) | None for the behaviour. Its only network route is the always-open provider host | `plugins.entries.memory-core.config.dreaming.enabled=false` (key path from DOCS `docs/concepts/dreaming.md:15,251`; code default `true`, `src/memory-host-sdk/dreaming.ts:22,354`) | A root-owned config layer upstream (none at 8.2), or a turn-gate-adjacent hash of a pinned `openclaw.json` subset. That still cannot stop a background run, only chat turns after drift |
| 2 | Automatic self-learning, per-turn experience review | **ON**, `skills.workshop.autonomous.mode: "auto"` (`skill-workshop` not `enabledByDefault`, so **OFF**) | None | `skills.workshop.autonomous.mode = "off"`/`"propose"` | As row 1 |
| 3 | Skill collection review (system cron; rewrites or drops writable skills) | **ON** with row 2, every **7 days** in code (help text says "daily") | None | same key as row 2 | As row 1 |
| 4 | **Skill auto-apply** (scanner-approved skills written into the workspace and injected into the prompt) | **ON**, `approvalPolicy: "auto"` | **None. The SOUL pin covers `SOUL.md` only** (`clawfactory-turn-gate.sh:41-46`); skill files are a new unpinned instruction channel | `skills.workshop.approvalPolicy: "pending"` | Extend the freeze pattern (root 444 + `chattr +i` + pinned hash) to the skill directories. That also blocks legitimate skill installs, so it is a product decision, not a flag |
| 5 | Plugin install, trust review, ClawHub review downloads | Not automatic; runs on `plugins install` / `skills install` | Partial: the **address** route. `registry.npmjs.org` and the GitHub hosts revoke with the software-sources toggle; **`clawhub.ai` does not** (`216.150.1.1` is shared with `openclaw.ai`, measured 2026-09-19 and matching the `egress-policy.json` record) | Consent is a CLI flag `--accept-capabilities` (`src/cli/plugins-install-command.ts:98`, `src/plugins/capability-consent.ts:359`) that a shell-capable agent can pass itself. `tools.deny` is `["browser"]` only | A root broker for plugin installs in the shape of `clawfactory-send`. Whether the agent's shell reaches the CLI in a real turn is **UNMEASURED** |
| 6 | Cross-session visibility | **UNMEASURED**. Not read in this census | — | — | Needs its own source read; carded (B-27) |
| 7 | Paired-device and cloud-worker sessions (run work on another machine, move the workspace with it) | Absent by default: no node connected, empty `cloudWorkers.profiles`. **Absence, not enforcement** | Provisioning egress from the gateway is `clawuser` traffic that nft drops. Location-of-execution is not controlled | Pairing approval is `operator.pairing` + `operator.write`/`admin` in `clawuser`-owned SQLite; the proxy makes every client a loopback peer (`clawfactory-proxy.js:107-122`), and the gateway auto-approves direct-loopback pairing after auth (`docs/web/control-ui.md:92`, DOCS-ONLY) | There is no in-cage way to bind where a session executes. Would need the gateway to refuse the pairing/cloud scopes, which is an upstream capability. UNMEASURED |
| 8 | Docked Browser panel | Panel present; `browser.enabled` default `true` | Guard 3 bounds where a browser can go (a `clawuser` child under the same nft chain) | `tools.deny=["browser"]` (`setup.ps1:3069` at tag), gateway-path | Not installing a browser runtime, if none is bundled: UNMEASURED |
| 9 | Windows node System tools (`system.run`, `screen.snapshot`, `computer.act`) | Only if a user installs the Windows Hub/node and approves a pairing | `[interop] enabled=false` stops the **agent** launching a Windows executable. A node the **user** installs is outside every guard by construction | Pairing approval | No in-cage way. Detection/warning only |
| 10 | Live provider model discovery (Anthropic, OpenAI `v1/models`) | **ON with an API key** (new); xAI/Google: no live endpoint found | Destination is the provider's own host, always open, and carries metadata, not tokens | **No disabling key found** in source or schema help | None needed; the residual is that no off switch exists |
| 11 | Hosted model catalog + pricing refresh, start + every 6 h | **ON** (`catalog.openclaw.ai`); at 4.27 a pricing bootstrap to `openrouter.ai` + `raw.githubusercontent.com` **ON** | **Yes for the new host**: `catalog.openclaw.ai` resolves to 4 GitHub-Pages addresses with 0 overlap with any allowed address, so nft denies it; fail-soft | `models.catalogRefresh.enabled=false` (noise reduction only) | Already structural for the host. Drop-log has **never** been measured at either version |
| 12 | Update check / daily telemetry ping | **ON** (`update.checkOnStart` default true); statistics default off; `update.auto.enabled` default **false** at both tags | **No.** `telemetry.openclaw.ai` shares three Cloudflare addresses with the allowed `docs.openclaw.ai`, so nft cannot deny it by name | `update.checkOnStart=false`, `OPENCLAW_NO_AUTO_UPDATE=1`, `DO_NOT_TRACK`. The gateway drop-in directory is chowned to clawuser (`setup.ps1:2474,2486-2491`), so env switches are also advisory | Drop `docs.openclaw.ai` from the base hosts (breaks nothing measured, but not tested), or accept and document the residual. Root-owned immutable drop-in: UNMEASURED whether a user manager honours it |
| 13 | Geolocation DB (`download.db-ip.com`), plugin `enabledByDefault` | Plugin ON, download lazy on first lookup, soft failure | **Yes**: host denied, no overlap | `plugins.entries.geolocation.enabled` | Already structural |
| 14 | llama.cpp managed local inference | Plugin `enabledByDefault`, `onStartup:false`; opt-in provider | `huggingface.co` denied structurally; `github.com` allowed via toolchain toggle. Child runs as `clawuser`, so it is inside the uid rules | Do not configure the provider | Already structural for the hosts; trigger UNMEASURED |
| 15 | Managed worktrees (copies of a source repo under `~/.openclaw/worktrees`, runs a repo-supplied setup script) | UNMEASURED, DOCS-ONLY (`docs/concepts/managed-worktrees.md`) | None: a copy of granted content lands outside `/workspaces`, so **Revoke and the kill switch's unmount would not remove it** | — | Unknown; needs the B-18 measurement first |
| 16 | 2.0 exec approvals and standing "Always allow" grants | Default posture **no prompt** (`full`, `ask: off`, `exec-approvals.md:191,200`, DOCS-ONLY) | **Not applicable.** Stored in `clawuser`-owned `state/openclaw.sqlite`, so the agent can rewrite its own approvals. Cannot weaken Guard 2, which is upstream of it | Everything | STRUCTURAL is impossible for this store |
| 17 | Credential-store secret substitution (`secrets.egressProxy`, "egress bound to declared hosts") | Default **off** (`configuration-reference.md:1503-1521`, DOCS-ONLY) | None. Sits **above** nftables, not beneath it; constrains where a substituted secret may go, in application code | All of it | Only relevant if ClawFactory routes keys through the shared store, which it does not |
| 18 | Chat-first Control UI, background sessions, `sessions.dispatch`, automations, on the **WebSocket** control plane | **ON**, root-mounted at the address the Start Menu shortcut opens | Only the `clawuser` → 8788 drop (nft backend only; the `iptables-legacy` fallback has no 8788 drop, `setup.ps1:2062-2083`) | The proxy gates **only** `POST /v1/chat/completions`; its own header says the WS control plane is not gated (`clawfactory-proxy.js:150-160`) | Gate at the gateway, not the proxy: an upstream capability, or a WS-aware proxy. UNMEASURED that pairing works through it (B-13) |
| 19 | Implicit Codex app-server runtime for `openai/*` on an official Platform route | Eligible when runtime policy is unset/`auto` (`docs/providers/openai.md:71-89`, DOCS-ONLY) | It is a `clawuser` child, so the uid rules apply. Its network calls, tool surface and whether its spend reaches the meter are unknown | — | Pin the runtime policy: a `clawuser`-writable key, so advisory. UNMEASURED |
| 20 | Heartbeat (recurring agent turn) | `30m` at **both** tags; 2.0 skips when scratch is "effectively empty" | None | `agents.defaults.heartbeat.every: "0m"` | UNMEASURED at both tags whether an idle, channel-less install makes any model call |
| 21 | Session observer (utility-model digests) | ON, only for **subscribed Control UI clients** | None | `gateway.controlUi.sessionObserver=false` | UNMEASURED whether anything subscribes on a ClawFactory install |
| 22 | Cache-backed usage meter (a change to an existing control, not a new capability) | The meter returns a `cacheStatus` of `fresh`/`partial`/`stale`/`refreshing` and refreshes in the **background** (`usage-result-cache.ts:195`, `refreshMode: "background"`) | `clawfactory-spend-check.js` reads no `cacheStatus` (0 hits at `v1.4.5`), so a cold or stale cache reads as a valid low or zero number and the gate **allows** the turn | Whole spend cap is ADVISORY | Make the gate treat any non-`fresh` status as unknown and fail closed, version-aware for the pin. Not measured on a box (B-6) |

**Cross-cutting fact for this table.** Every 2.0 LLM caller in rows 1-3, 20 and 21 runs in-process inside the gateway and **around** the chatCompletions route and the `openclaw agent` shim. The turn gate (SOUL integrity + spend cap) is never entered for them. None is on the path Guard 2 can gate; Guard 2 covers `clawfactory-send` only.

### Task 7 — comparison skeleton

Every cell is `MEASURED <reference>` or `UNMEASURED`. **No cell becomes site copy until it reads `MEASURED`.** This census took **no box measurement**, so every OpenClaw cell is `UNMEASURED`. The rightmost column is a pointer to where source was read, and is **not** a measurement.

| Claim | ClawFactory v1.4.5 | OpenClaw 2.0 default (unsandboxed) | OpenClaw 2.0, Docker sandbox on | Source-read pointer (not a measurement) |
|---|---|---|---|---|
| Filesystem isolation | `MEASURED docs/session_reports/2026-08-31_systemd_reboot_persistence_closeout.md:514` (three guards and the gating proxy hold end to end, published v1.4.5, cfv-191, across a restart) | `UNMEASURED` | `UNMEASURED` | Sandbox `mode` default `off`, backend `docker`; unavailable backends fail closed (`docs/gateway/sandboxing.md:31-43`, DOCS-ONLY) |
| Egress control | `MEASURED 2026-08-31_systemd_reboot_persistence_closeout.md:514,630-635` (`[fw-assert] chain shape OK`, survives reboot). Address-scoped; two named residuals (`clawhub.ai`, `telemetry.openclaw.ai`) | `UNMEASURED` | `UNMEASURED` | Prompt states unsandboxed can reach any host and sandboxed defaults to no network; **neither was read or measured here** |
| Credential exposure to the agent | `UNMEASURED` as a claim about the agent (ownership and file mode were measured, `SECURITY_FINDINGS.md` "Credential protection"; agent and gateway share one uid) | `UNMEASURED` | `UNMEASURED` | 2.0 retires `auth-profiles.json` as a runtime store (`legacy-source-files.ts:47`); the measurement target moves to a SQLite row |
| Send gating | `MEASURED 2026-08-31_systemd_reboot_persistence_closeout.md:514` (email only; `docs/reference/EMAIL_APPROVAL.md` §1) | `UNMEASURED` | `UNMEASURED` | 2.0 exec approvals default to no prompt, stored in a `clawuser`-owned DB (`docs/tools/exec-approvals.md:92-99,191,200`, DOCS-ONLY) |
| Install without Docker Desktop | `MEASURED 2026-08-31_systemd_reboot_persistence_closeout.md:519` (install PASS, published v1.4.5, `/VERYSILENT`); Docker removed at `setup.ps1:1705-1723` | `UNMEASURED` | `UNMEASURED` (would need a Docker backend) | none |
| Windows Home support | `UNMEASURED` (no close-out read in this census records a Windows Home install) | `UNMEASURED` | `UNMEASURED` | none |
| Kill switch | `MEASURED` **as an action, not a boundary** (`SECURITY_FINDINGS.md` "The kill switch is a user action, not a standing boundary"); not re-measured here | `UNMEASURED` | `UNMEASURED` | 2.0 unit `TimeoutStopSec` 30 → 330; at `v2026.9.5` `KillMode` control-group → mixed (`systemd-unit.ts:80,85-88,117-118`) |

The allowlisted middle state, which is the ClawFactory claim, needs both comparators measured before any comparison sentence exists. Neither is measured. Carded as B-28.
