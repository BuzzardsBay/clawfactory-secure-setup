# Phase 2 — ClawFactory Studio Workbench

**Date:** 2026-07-13
**Authored against:** `PHASE1_GRANTS_2026-07-13.md` (commit `88331b9`) and `PHASE0_RECON_2026-07-13.md` (`d37be47`).
**Repos:** `ClawFactory-Studio` (now a git repo — Task 2.0) and `ClawFactory-Secure-Setup` (grants engine + this report).
**Evidence standard:** verbatim command/tool output; load-bearing claims labeled VERIFIED / INFERRED / GENERAL.
**Commits:** Studio `bdf6b60` (initial) → `d15e204` (Phase 2). Secure-Setup engine fixes + this report: see Git section.

---

## TASK 2.1 EVIDENCE FIRST — Studio opens NO WebSocket to `:8787` — DONE (VERIFIED)

The boot-eager gateway WebSocket, its device-identity pairing, and the dashboard-`Origin` spoofing are **deleted**, not disabled. `git rm` of `services/gateway-client.ts`, `ws/chat-bridge.ts`, `services/device-identity.ts`; the gateway host/port config removed from `config.ts`; `index.ts` no longer calls `getGatewayClient()`/`attachChatBridge()`.

**Boot log — clean (no gateway WS)** (VERIFIED). Compare Phase 0, where boot flooded with `gateway connecting { url: 'ws://127.0.0.1:8787/' }`:
```
[info]  wsl-keepalive starting
[info]  ClawFactory Studio backend listening { url: 'http://127.0.0.1:8099', nodeEnv: 'production' }
```
```
$ grep -iE "ws://|gateway connecting|:8787" boot.log
>>> NONE: no WebSocket/:8787/gateway-connect lines in boot log
```
**No node→:8787 connection at boot OR during a live chat turn** (VERIFIED). netstat of the Studio node PID during a streaming turn:
```
sample 1: '(node->:8787 = NONE)'
sample 2..5: '(node->:8787 = NONE)'
```
**Streaming works via SSE over plain HTTP** (POST `/api/chat/stream`), never a gateway WS (VERIFIED):
```
: stream-open
event: start
data: {"agent":"main"}
event: log
data: {"text":"EMBEDDED FALLBACK: Gateway agent failed; ... HTTP 401 authentication_error: invalid x-api-key"}
event: done
data: {"text":"","exit":1}
```
(The `401` is the no-valid-API-key artifact carried over from Phase 0/1 — the transport is proven; the model call is what fails.)

**Chosen CLI invocation (searched first).** `openclaw agent` has **no `--stream` flag** ([docs/cli/agent](https://docs.openclaw.ai/cli/agent)); `--json` buffers. So `agent-stream.ts` spawns `openclaw agent --agent <id> --message "$(echo <b64>|base64 -d)"` (plain text; message base64'd off the command line) and streams stdout as `delta` + stderr as `log` events, with a final `done`. The turn is gated by the Phase 1 `Test-TurnAllowed` before it starts. **INFERRED:** true token-level streaming isn't available from the CLI, so live feedback comes from stderr progress; a valid key would still stream progress + deliver the result at `done`.

**Studio smoke check confirms it** (Task 2.7): *"Studio opens NO WebSocket to :8787 (boot)" = PASS.*

---

## TASK 2.0 — Studio under git (private) — DONE

```
$ gh repo view BuzzardsBay/ClawFactory-Studio --json visibility,isPrivate,url
{"isPrivate":true,"url":"https://github.com/BuzzardsBay/ClawFactory-Studio","visibility":"PRIVATE"}
```
`git init` + `.gitignore` (node_modules, dist, `backend/public`, installer `work/`+`Output/` binaries, `.env`) + initial commit `bdf6b60` (102 files, **zero** node_modules/binaries/.env — verified). The Phase 1 ARCHITECTURE.md container-claim correction is in the initial commit. Private, per the "source code stays private" convention.

---

## TASK 2.2 — Workspace panel — DONE (VERIFIED)

`frontend/src/pages/workspace/WorkspacePage.tsx`, backed by `routes/grants.ts` → the Phase 1 engine (no mount/deny logic reimplemented). Rendered live in-browser:
```
Workspace   Refresh   Add a folder
Grants are the only parts of your PC the agent can see. Everything else stays hidden.
WORKSPACE FOLDERS   No folders granted yet. Use "Add a folder"...
SKILLS              No skill grants yet — coming in a later update.
DOMAINS             No domain grants yet — coming in a later update.
```
- All three grant types shown as always-visible sections (skill/domain empty until Phase 3). VERIFIED.
- Add-folder → native `FolderBrowserDialog` → confirmation screen (full path, rw/ro toggle default rw, "subfolders included", isolation statement) → `Grant-Workspace`.
- Deny-list rejections surface as a human message (422), not a trace (VERIFIED via curl):
```
POST /api/grants/workspace {"path":"C:\\"} -> HTTP 422
msg: Refusing to grant 'C:': that is a drive root or your user-profile root. Grant a specific project folder instead (e.g. C:\Users\bmcki\Documents\my-project).
```
- Revoke (confirm → `Revoke-Workspace`), broken-grant detection via `Test-Grants` (repair/revoke), "Open in Explorer" on each grant.

---

## TASK 2.3 — Files & Preview panel — DONE (VERIFIED)

`frontend/src/pages/files/FilesPage.tsx` + `routes/files.ts`. Browsing is rooted ONLY at active workspace grants (their Windows path) and the agent output dir (`\\wsl.localhost\Ubuntu\...\.openclaw\output`); every request path is resolved and bounds-checked against its root. Preview: markdown (react-markdown), code (mono `<pre>`), image, pdf (`<iframe>`), and **sandboxed offline HTML**. "Open in Explorer" / "Open with default app" on every file. Embedded editor/terminal/live-serving are explicitly out of scope (not built).

**Sandboxed HTML — the exact sandbox + CSP applied** (VERIFIED, as required):
- Client iframe: `sandbox=""` — an empty sandbox with **no** `allow-*` tokens, so the framed page is an opaque origin with scripts, same-origin, forms, popups, and top-navigation all disabled.
- Server response header on `/api/files/raw` for `html`:
```
Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; media-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'self'
X-Content-Type-Options: nosniff
```
Together: no network of any kind (no external img/css/fetch/script), no script execution, only inline styles and `data:` assets. A page the agent built cannot phone home from inside the preview.

Browse verified via curl against the granted demo workspace:
```
GET /api/files/list?root=<demo> -> meeting-notes.md, README.txt, roadmap.md, sales-q3.csv
GET /api/files/content?root=<demo>&path=README.txt -> {"kind":"code","text":"This is the ClawFactory Studio demo workspace..."}
```

---

## TASK 2.4 — Activity panel — DONE (VERIFIED)

`frontend/src/pages/activity/ActivityPage.tsx` + `routes/activity.ts`. Rendered live in-browser with real data:
```
Activity
Gateway online
Cost meter   TODAY $0.00   THIS MONTH $27.08   Caps: $5.00/day · $50.00/month · warn at 80%   Percent of cap 54%
Caps are enforced between turns — a turn already running can go over. There's no per-call guarantee.
Spend caps  [Daily cap] [Monthly cap] [Warn at %]  Save caps
Audit log   Refresh
  7/13/2026, 7:46:22 PM  workspace.revoked   id=clawfactory-demo-4ec4ed7c detail=UNMOUNTED RMDIR_OK
  7/13/2026, 7:46:22 PM  workspace.denied    path=C: reason=Refusing to grant 'C:'...
  7/13/2026, 7:46:20 PM  workspace.mounted   path=C:\Users\bmcki\ClawFactory Demo id=clawfactory-demo-...
```
- **Gateway health** pill (CLI probe, never a WS). **Cost meter** from `Get-SpendStatus`, polled. **`unknown` handled honestly** — the UI renders "Spend: unavailable / This is NOT $0" when the meter can't read (gateway down), never a fake `$0.00`. Warning at 80%, blocked state states cap+spend+how-to-raise. **Editable caps** (writes `governor.json`). **Audit-log viewer** shows the raw trail (not summarized). The between-turns disclaimer is in the copy.

---

## TASK 2.5 — Templates panel + 10 starters — DONE (VERIFIED)

`frontend/src/pages/templates/TemplatesPage.tsx` + `routes/templates.ts` + `services/templates.ts`. Templates are markdown with a JSON front-matter block (fields → a form) + a `{{field}}` body. Bundled defaults in `templates/` seed a user-writable dir on first use and are never overwritten if edited. Rendered live in-browser — 10 templates grouped by intent:
```
RESEARCH  🔎 Research a topic and write me a report   [Needs: web-search]  Use Edit Duplicate
          📚 Summarize the documents in my workspace
BUILD     🌐 Build me a simple website about X   📊 Turn this CSV into a chart
          ⚙️ Write a script that does X          🍽️ Make me a printable weekly meal plan...
ORGANIZE  📄 Extract data from these PDFs...      🗂️ Rename and organize the files...
WRITE     ✍️ Draft a document in my voice         📝 Turn these notes into documentation
```
- Gallery grouped by intent; **missing-skill warning** shown up front (the research template's `web-search` → "Needs a capability that isn't installed yet"). Run = compose `{{field}}` substitutions → stream via SSE. Duplicate / Edit (raw markdown) / New template all wired. VERIFIED (10 parsed via `/api/templates`; gallery rendered).

---

## TASK 2.6 — Demo workspace + first-run (time-to-wow) — PARTIAL (honestly reported)

`components/FirstRunBanner.tsx` + `routes/firstrun.ts` + `demo-workspace/`. On first open, a banner offers "Try the demo" → copies the bundled demo folder to `%USERPROFILE%\ClawFactory Demo`, grants it, and routes to Templates with the suggested template stashed.

**Time-to-wow, measured VERBATIM** (from a ready backend):
```
setup-demo (copy + grant + drvfs mount): 0.43s
TOTAL backend-ready -> visible previewable demo content: 0.87s
  (first previewable file: meeting-notes.md, rendered in the preview pane)
```
So from install-complete: launch Studio (backend boot, a few seconds) + **0.87s** to a granted workspace whose shipped sample content previews — **far under 5 minutes** for the demo-content path. VERIFIED.

**BUT the agent-GENERATED "wow" (a template run producing a NEW output file) could NOT be produced or timed on this machine** — agent turns return `HTTP 401 invalid x-api-key` (no valid provider key; the same artifact Phase 0/1 hit). The composed prompt streams correctly and the plumbing is proven; only the model call fails:
```
POST /api/templates/summarize-workspace/compose -> composed prompt streamed to /api/chat/stream
event: log  {"text":"... HTTP 401 authentication_error: invalid x-api-key"}
event: done
```
**Honest verdict:** the ≤5-minute gate is **met for the demo-content path (0.87s)** and **unmet-because-unmeasurable for the agent-output path** (blocked by the missing API key, not by Studio). With a valid key, the run streams and the agent writes output into the demo workspace, which previews immediately. This is a BLOCKED item, not a silent pass.

---

## TASK 2.7 — Installer refresh + smoke — PARTIAL

**Smoke — DONE (VERIFIED), `studio-smoke.ps1`, 4/4:**
```
  PASS  Studio backend boots and serves the SPA
  PASS  Studio opens NO WebSocket to :8787 (boot)
  PASS  Studio reads the grants ledger
  PASS  First-run demo produces a previewable file
Studio smoke: 4 pass, 0 fail
```
(Check #4 verifies the demo's shipped previewable content — the agent-generated file needs a key, see 2.6.)

**Installer `.exe` rebuild — DEFERRED (BLOCKED).** The backend (`backend/dist`) and SPA (`backend/public`) build clean and are ready to bundle, but repackaging `ClawFactory-Studio-Installer.exe` needs the Inno toolchain (ISCC) plus wiring the new `templates/` and `demo-workspace/` dirs and the `CLAWFACTORY_GRANTS_ENGINE` env into the Studio `.iss`/`setup-studio.ps1`. That packaging step is the remaining installer work (lower-risk, no product-logic change). See BLOCKED.

---

## SURPRISES

1. **SSE stalled on a Node ≥16 gotcha.** The stream initially delivered nothing: `req.on('close')` fires as soon as `express.json()` finishes reading the POST body (a readable emits `close` right after it ends in Node ≥16), so the handler tore itself down before the turn ran. Fixed by detecting client disconnect on **`res.on('close')`** instead. (Non-obvious; worth remembering for any SSE-over-POST in this codebase.)
2. **Grants engine re-grant-after-revoke collision (bug, FIXED in the engine).** The workspace slug is deterministic from the path, `Remove-Grant` is a soft-delete (keeps the id), and `Add-Grant` guards unique ids — so re-granting a previously-revoked folder threw `grant id already exists`. Surfaced by the first-run demo. Fixed: `Grant-Workspace` now **reactivates** a prior inactive record for the same slug instead of colliding. (Engine change in `clawfactory-grants.ps1`; Phase 1 smoke still 18/19.)
3. **Grants audit log had a UTF-8 BOM (bug, FIXED).** PS 5.1's `Set-Content -Encoding UTF8` prepended a BOM to `grants-audit.log` (and `grants.json`), breaking the first JSON line for the Node reader (the audit viewer showed it as "unparsed"). Fixed the engine writes to use `[IO.File]::WriteAllText` + `UTF8Encoding($false)` (no BOM) and added a defensive BOM-strip in the backend reader. (Matches the known PS-5.1-BOM lesson.)
4. **Agent turns 401 (no valid API key)** on this machine — blocks the agent-output "wow" (2.6) and any real agent result. Environment carryover (Phase 0/1), not a Studio defect.
5. **`@tailwindcss/typography` isn't a dependency**, so `prose`/`prose-invert` classes were inert; added a minimal `.prose` block to `index.css` so markdown preview renders readably without pulling a new dependency.

---

## BLOCKED

1. **Agent-generated time-to-wow (2.6)** — no valid provider API key on this box (`401`); the agent produces no output, so the agent-output ≤5-min result can't be produced or timed. Plumbing proven; needs a working key (or an Azure test VM with one).
2. **Studio installer `.exe` rebuild (2.7)** — needs ISCC + wiring `templates/`, `demo-workspace/`, and `CLAWFACTORY_GRANTS_ENGINE` into the Studio `.iss`. Code is built and ready; only packaging remains.
3. **ProgramData write-ACL for a non-admin user** (Phase 1 carryover) — Studio's backend called the engine as an admin-capable user in testing; whether a non-admin Studio process can write `ProgramData\ClawFactory\{grants,governor,grants-audit}` was not verified end-to-end. Relevant to the shipped service's run-as identity.

---

## PHASE 3 HANDOFF

**Where skill-catalog approval cards slot in (Activity panel):** the SSE stream already carries `log` events and can carry a `tool`/`approval` event type. Phase 3 adds:
- A `tool-approval` SSE event emitted when the agent hits a SOUL.md "GO"-gated action (the CLI surfaces the prompt on stdout/stderr; `agent-stream.ts` parses it into an event). The Activity panel renders an **approval card** (approve/deny) that writes the decision back (a new `POST /api/chat/approve` → the CLI's approval mechanism). The live transcript is already in the Chat panel; the approval card is the new surface.

**What the Templates panel needs from the catalog to wire "this template needs a skill":**
- `missing_skills` is already computed per template (`requires_skills` minus installed **skill grants**). Today skill grants are empty (Phase 1 defined the `skill`/`domain` grant types but they're unused).
- Phase 3 wires: when `missing_skills` is non-empty, the run view offers **"Install <skill>"** → creates a `skill` grant via the engine (a new `Grant-Skill` on the ledger) plus the `domain` grants it needs (via `depends_on`), and those **domain grants feed the egress-firewall allowlist** (the Phase 3 firewall change the Phase 0 report flagged as out-of-scope for Phase 1/2). Then the template runs. The Workspace panel's SKILLS/DOMAINS sections (already rendered empty) become populated.

---

## END-OF-SESSION GATE

### 1. Task accounting
| Task | Status |
|---|---|
| 2.0 Studio under git (private) | **DONE** — `bdf6b60`, private repo |
| 2.1 Remove boot-eager WS + SSE | **DONE** — proven no `:8787` WS |
| 2.2 Workspace panel | **DONE** — verified in-browser + curl |
| 2.3 Files & Preview panel | **DONE** — sandboxed HTML CSP verbatim |
| 2.4 Activity panel | **DONE** — live spend/health/audit, honest `unknown` |
| 2.5 Templates panel + 10 | **DONE** — 10 parsed, gallery rendered |
| 2.6 Demo + first-run | **PARTIAL** — demo-content path 0.87s; agent-output BLOCKED (401) |
| 2.7 Installer refresh + smoke | **PARTIAL** — smoke 4/4 DONE; `.exe` rebuild DEFERRED |

### 2. Resource ledger (created → proof cleaned)
- **Studio backend** booted repeatedly on :8099/:8091 for testing → all killed. Proof: *"no studio backend on 8091/8099 (clean)"*.
- **drvfs demo mount** (`/workspaces/clawfactory-demo-*`) created by first-run/demo tests → unmounted (studio-smoke revoke + final sweep). Proof: *"workspaces mounts: 0 / (none - clean)"*.
- **Real ProgramData ledger files** (`grants.json`, `governor.json`, `grants-audit.log`) created by Studio's engine calls during testing → removed. Proof: *"ProgramData: no grants/governor files (clean)"*.
- **`C:\Users\bmcki\ClawFactory Demo`** (demo copy) → removed. Proof: *"demo folder: gone (clean)"*.
- **`%LOCALAPPDATA%\ClawFactoryStudio`** (firstrun.json, seeded templates, studio.log) → removed.
- **Scratch scripts / logs** in the session scratchpad → to be removed in Git step.
- **Gateway left healthy:** `gateway_http=200`, `keepalive: 2` (WSL Host session held). No `wsl --shutdown` was run this session.
- **4 subagents** spawned (10 templates + demo content; 4 panels) — produced files only, no mounts/processes.

### 3. Delta security sweep
- **No WebSocket to `:8787` anywhere in shipped code:** `gateway-client.ts`/`chat-bridge.ts`/`device-identity.ts` deleted; `grep` for `ws://`/`8787`/`WebSocket` in `backend/src` returns only the removed-code references in git history, none in the tree. Studio-smoke check #2 = PASS.
- **No Origin spoofing anywhere in shipped code** — the only `Origin`-setting code was in the deleted `gateway-client.ts`.
- **No key material in any new file** — `grep -E 'tvly-|sk-|ANTHROPIC_API_KEY'` over the new backend/frontend/templates files is clean (Studio stores keys via the OS credential path, not in these files).
- **Firewall / SOUL pin / `/etc/wsl.conf` untouched** — no change to the egress firewall (domain grants are Phase 3), the SOUL hash pin, or `/etc/wsl.conf` (still `automount=true`, its pre-existing drifted state; read-only this session).

### 4. Delta bug review (found → fixed or listed)
- SSE `req`-vs-`res` close bug → **fixed** (2.1).
- Grants engine re-grant collision → **fixed** in `clawfactory-grants.ps1` (SURPRISES #2).
- Audit-log/ledger BOM → **fixed** in the engine + backend (SURPRISES #3).
- Agent 401 (no key) → **listed** (BLOCKED #1), environment not code.

### Git
Studio: `bdf6b60` (initial) → `d15e204` (Phase 2), pushed to `github.com/BuzzardsBay/ClawFactory-Studio` (private). Secure-Setup: engine fixes (`clawfactory-grants.ps1`) + this report — commit hash in the Git section of the session summary. All staging explicit by path; never `git add -A`.
