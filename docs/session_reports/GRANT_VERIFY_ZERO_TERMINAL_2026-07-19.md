# Grant Mechanism Verification + Terminal Drop-Out Inventory

**Date:** 2026-07-19
**Session type:** Verification and inventory only. No UI designed, no product code changed, no VM provisioned.
**Applies to:** ClawFactory Secure Setup v1.0.45 (source as committed at `3105bd1`); ClawFactory Studio (private repo, unbundled, unvalidated).
**Dispatch card:** #139 `CC_CLAWFACTORY_GRANT_VERIFY_ZERO_TERMINAL`.

---

## Task 1 verdict (the security question) — stated first

**NO. On a correct install, a process running as `clawuser` (the agent itself) cannot invoke the grant mechanism and cannot cause a new Windows folder to be mounted into the sandbox.** The published file-isolation guarantee holds against the agent for *causing* a grant, not only for *reading* an existing one.

**The privilege boundary, in one sentence:** every path that creates a mount is **Windows-side code that calls `wsl.exe -u root`** (`resources/clawfactory-grants.ps1:389`, invoked as root at `:392`; the launcher that replays grants runs as the **Windows end-user, not the agent** — `resources/launcher.ps1:17`), and the agent — a non-sudo uid-1000 process inside WSL with `[automount] enabled=false` (`setup.ps1:1089-1090`) — has **no reachable Windows binary to execute and no writable input that the mechanism trusts**, so it cannot reach any of that code.

This is a genuinely different question from the prior validation (agent cannot *read* ungranted paths), and it is answered independently here: the agent cannot *cause a path to become granted* either.

**However, that "NO" rests on two settings that are not independently defended, and one of them (WSL networking) becomes load-bearing the moment Studio goes on the zero-terminal critical path.** These are defense-in-depth findings, not a break of the current shipped product — detail in Findings A/B/C below. They must be treated as hard constraints on the UI work, which is exactly what this session existed to determine.

---

### 1.1 The full grant path (what runs, what privilege, where the mount lands, which identity)

| Step | Where | Identity | Evidence |
|---|---|---|---|
| User (or Studio) calls `Grant-Workspace -Path <win> -Mode rw` | Windows PowerShell 5.1 | The invoking **Windows** user | `clawfactory-grants.ps1:342` |
| Path canonicalized (reparse points/junctions resolved) + deny-listed | Windows | Windows user | `:353-359`, `ConvertTo-CanonicalPath :210`, `Test-WorkspaceDenied :249` |
| Deterministic slug computed (`<leaf>-<8 hex>`) | Windows | Windows user | `New-WorkspaceSlug :300` |
| Mount created: `nsenter -t <gateway-pid> -m -- mount -t drvfs '<win>' /workspaces/<slug> -o metadata,uid=1000,gid=1000[,ro]` | **WSL, as root**, targeting the **gateway's mount namespace** | `wsl.exe -u root` launched **from Windows** | `:382-392` (`Invoke-ClawWslBash -User 'root'`), gateway-namespace preamble `:323-326` |
| Grant recorded in ledger | Windows filesystem | Windows user | `Add-Grant :159` → `Save-GrantsRaw :134` → `C:\ProgramData\ClawFactory\grants.json` (`:29`) |
| On WSL/gateway restart, active grants re-mounted | Windows launcher fires it | **Windows end-user** double-click | `launcher.ps1:198-208` → `Invoke-GrantReplay :487` |

The mount is a **drvfs mount inside the gateway process's mount namespace** (Phase 2.5 fix — an ordinary `wsl` mount lands in a different namespace and is invisible to the agent). Creating it requires (a) running `wsl.exe -u root`, which is a Windows-side capability, and (b) `nsenter` into another process's namespace, which requires root/CAP_SYS_ADMIN.

### 1.2 Can `clawuser` trigger it? Every vector considered

| Vector | Reachable by `clawuser`? | Why / Evidence |
|---|---|---|
| **Direct call of `Grant-Workspace`** | **No** | It is a Windows PowerShell function. The agent lives in WSL and has no PowerShell/Windows process of its own. |
| **`mount` / `nsenter` directly in WSL** | **No** | `clawuser` is uid 1000, non-sudo — the temporary NOPASSWD sudoers line and sudo-group membership are stripped post-create (`setup.ps1:1136`, `:1139`). `mount` needs CAP_SYS_ADMIN; `nsenter -m` into the gateway needs root. |
| **WSL interop → run `wsl.exe -u root` / `powershell.exe` from inside the distro** | **No, on a correct install** — but *not because interop is disabled* | Interop is **enabled** (no `[interop]` section in the wsl.conf the installer writes — `setup.ps1:1088-1097`, so `enabled` and `appendWindowsPath` are at their default `true`). What stops it is **`[automount] enabled=false`**: with `/mnt/c` unmounted, there is **no Windows PE binary anywhere the agent can `exec`**, so the (enabled) interop handler is never fed a Windows binary. `appendWindowsPath` adds `/mnt/c/...` PATH entries that resolve to nothing for the same reason. **See Finding A — this makes the boundary transitive on one setting.** |
| **Gateway / proxy / API surface exposing grants** (the `127.0.0.1:8787` path the agent uses) | **No** | Grants are implemented **only** in the Windows PowerShell library. The OpenClaw gateway and the root-owned chatCompletions proxy have no grant/mount RPC. The agent's WebSocket path to `:8787` cannot express "mount a folder." |
| **Studio's HTTP grant API** (`POST /api/grants/workspace`, no auth — `Studio backend/src/routes/grants.ts:64`) | **No, on the shipped config** — **conditional, see Finding B** | Studio binds `127.0.0.1:8080` (`config.ts:11`, `index.ts:76`) and the installer's `.wslconfig` sets only `vmIdleTimeout=-1`, **no `networkingMode=mirrored`** (`setup.ps1:884-1042`). Under default WSL2 **NAT** networking, a Windows service on `127.0.0.1` is **not** reachable from inside WSL. Also: Studio is not bundled in the v1.0.45 installer and has never been validated. |
| **A file the agent can write that the mechanism later reads** (config/queue/watched dir) | **No, on a correct install** — **see Finding C** | The trusted inputs are `grants.json` (Windows `ProgramData` — unreachable from WSL with automount off; `Invoke-GrantReplay` re-mounts it **without re-checking the deny-list**, `:504-533`) and `/etc/clawfactory/governor.json` + SOUL pins (root-owned `644`/`444` — `clawuser` can read, cannot write). None is agent-writable today. |
| **Scheduled task / service acting on agent input** | **No** | The only ClawFactory tasks are `ClawFactory WSL Host` (runs `sleep infinity`, a keepalive) and the install-time resume/smoke tasks (`uninstall.ps1:128-132`). None reads an agent-writable file to perform a grant. Replay is triggered by the **user's desktop double-click**, not by any WSL-side input. |

### 1.3 Verdict with evidence

**NO** — the agent cannot grant itself access on a correct install. What prevents it, precisely: the grant-creating code is Windows-side and privileged (`clawfactory-grants.ps1:389-392` runs `wsl.exe -u root`); the agent is a non-sudo WSL process (`setup.ps1:1136-1139`); with `[automount] enabled=false` (`setup.ps1:1089-1090`, fail-loud–verified by `Assert-WslAutomountDisabled :1053`) the agent has **no Windows binary to exec via interop and no `/mnt/c` route to the trusted ledger**; and the one network surface that does expose grants (Studio, unauthenticated) is unreachable under the shipped NAT-loopback configuration. This is the sentence that supports the published file-isolation claim — with the caveat that it is **transitive on `automount=false` (plus NAT networking, once Studio is in play)**, not independently belt-and-suspendered.

### 1.4 Findings that gate the UI work (report-only; nothing changed)

- **Finding A — interop is not explicitly disabled (defense-in-depth gap).** The wsl.conf written at `setup.ps1:1088-1097` has no `[interop]` section, so `interop.enabled` and `interop.appendWindowsPath` default to `true`. The agent's inability to use interop depends **entirely** on `automount=false`. A single drift of `automount` to `true` therefore does two things at once: exposes all of `C:\` via `/mnt/c` **and** hands the agent a reachable `wsl.exe`/`powershell.exe` — i.e. a path to root and to self-granting. Bret's own daily-driver box has already drifted to `automount=true` once (card #116 comment #143). Recommend (v1.1, not this session) adding `[interop]\nenabled=false\nappendWindowsPath=false` so the two failures are decoupled and neither alone is sufficient.
- **Finding B — Studio's grant API is an unauthenticated grant surface; its safety is a networking assumption.** `POST /api/grants/workspace` (no auth, `routes/grants.ts:64-83`) shells straight into `Grant-Workspace`. Studio's stated threat model is *"the only attacker who can hit localhost already has code execution on the box"* (`Studio docs/ARCHITECTURE.md:102`) — but the agent **is** exactly that attacker. Two invariants must hold and be **tested** before Studio can carry the zero-terminal grant UX: (1) WSL networking stays **NAT** (never `networkingMode=mirrored`, which shares loopback bidirectionally), and (2) Studio stays bound to **`127.0.0.1`** (never `0.0.0.0`). If either flips, `clawuser` reaching `:8080` grants itself any non-deny-listed folder — a structural break of the headline. The deny-list still applies via Studio (422, `:77-79`), so `C:\` and system dirs remain blocked, but any ordinary project folder would be grantable.
- **Finding C — `grants.json` is a trusted input; replay does not re-validate it.** `Invoke-GrantReplay` re-mounts every active ledger entry without re-running `Test-WorkspaceDenied` (`:504-533`). Safe today only because the ledger lives in Windows `ProgramData` (unreachable from WSL with automount off) and is ACL-restricted. This couples replay's integrity to the same `automount=false` + NTFS-ACL assumptions; worth a deny-list re-check on replay as hardening.

---

## Task 2 — Grant mechanism behavior (design constraints)

| # | Question | Answer (from code) | Evidence |
|---|---|---|---|
| 2.1 | Additive or replacing? | **Additive.** Each grant is appended to the ledger and mounted at its own `/workspaces/<slug>`. Granting a second folder never disturbs the first. | `Add-Grant` appends `@($grants) + $obj` (`:186`); each mount is per-slug (`:385-390`). |
| 2.2 | Identifier / mapping model; deterministic? stable? | **Slug = `<sanitized-leaf>-<first 4 bytes of SHA256(lowercased resolved path)>`** (e.g. `granted-ba622b4f`). **Deterministic** (pure function of the resolved path) and **stable across reboots** (ledger persists in ProgramData). Across **uninstall→reinstall the slug value regenerates identically, but the ledger itself is deleted** (`uninstall.ps1:341-346` removes all of `ProgramData\ClawFactory`), so grants must be re-created after reinstall. | `New-WorkspaceSlug :300-313`; uninstall wipe `:342-346`. |
| 2.3 | Revoke path; single-grant granularity? | **Yes.** `Revoke-Workspace -Id` unmounts + removes the mountpoint + marks only the matching id inactive; other grants untouched. Idempotent — reports, never throws, if the mount is already gone. Note: **revoke ≠ kill.** The Kill Switch unmounts everything but leaves grants *active* for replay (`Invoke-GrantKillUnmount :537`). | `Revoke-Workspace :426-449`; `Remove-Grant :191` (soft, single id). |
| 2.4 | Enumerable list for a UI? | **Yes, three views.** `Get-Grants` (all), `Get-ActiveGrants [-Type workspace]` (active), and `Test-Grants` (per-grant health: `ok` / `broken-path` / `not-mounted`, with `pathExists` + live mount check in the gateway namespace). A UI should render state from `Test-Grants`, **not** the raw ledger, because a mount can be live/dead independent of the ledger. | `:146-157`, `Test-Grants :451-474`. |
| 2.5 | Limits / footguns a UI must respect | See list below. | — |

**Task 2.5 footguns (a UI must handle all of these):**
- **Deny-list rejections are normal, not errors.** Drive roots, the user-profile root, and the trees `WINDIR / ProgramData / ProgramFiles / ProgramFiles(x86) / APPDATA / LOCALAPPDATA / <install dir>` are rejected with a human-readable reason (`Test-WorkspaceDenied :249-278`). Studio surfaces this as HTTP 422. The picker UI should pre-empt or gracefully explain these.
- **Symlinks/junctions are resolved before the deny-check** (`ConvertTo-CanonicalPath :210`) — a link pointing at `C:\` is caught. Good; no UI action needed, but don't second-guess it.
- **Path must already exist** or `Grant-Workspace` throws (`:350`).
- **OneDrive-backed folders** → non-fatal warning; on-demand/placeholder files may hang for the agent until hydrated (`Get-WorkspaceWarnings :285`). UI should surface the warning.
- **UNC / mapped network drives** → non-fatal warning; untested in Phase 0 (`:288-296`). UI should discourage.
- **Gateway not running** → grant is *recorded but not mounted*; it becomes visible only on next gateway start via replay (`NO_GATEWAY` path `:398-403`). UI must show a "pending / applies on next start" state, not "mounted."
- **Mounts are namespace-bound and lost on gateway restart**, then replayed by the launcher. "Mounted" in the UI must come from `Test-WslMountLive` (gateway namespace), not the ledger.
- **No max-mount cap in code** — mounts are unbounded drvfs mounts; a UI should impose a sane soft limit.
- **Apostrophes in a Windows path are a latent break.** The Windows path is interpolated into a single-quoted bash string (`'$winFwd'`, `:389`); a path containing `'` would break the quoting. Windows filenames *can* contain apostrophes. Spaces/unicode are fine (spaces are inside the quotes; the slug sanitizer strips non-`[a-z0-9]` and falls back to `ws-<hash>`). UI should reject or escape paths containing `'`.

---

## Task 3 — Terminal drop-out inventory (the UX gate)

Legend: **GUI** = achievable with no console/typing of commands; **Semi** = GUI-launched but presents a console / requires elevation / prompts; **Terminal** = requires PowerShell or manual file editing. "Studio" answers assume Studio were installed — it is **not shipped or validated** today.

| Lifecycle step | Shipped path today | Class | Studio covers it? | Evidence |
|---|---|---|---|---|
| Obtain + enter API key (initial) | Installer wizard: provider radio + API-key page with "Get your API key" browser button + "add later" checkbox; key → Credential Manager | **GUI** | Studio has a first-run wizard too | `.iss` `ProviderPage :462`, `ApiKeyPage :509-536`, cred target `:249-257` |
| First launch (start the agent/gateway) | Desktop/Start-Menu **ClawChat** icon; `launcher.ps1` auto-starts the gateway | **GUI** | Yes (Studio launcher) | `.iss [Icons] :100-108`; `launcher.ps1:22-31` |
| **Grant a folder** | **None.** `clawfactory-grants.ps1` is bundled but **no shortcut invokes `Grant-Workspace`**; user must `. clawfactory-grants.ps1; Grant-Workspace -Path …` in PowerShell | **Terminal** | **Yes** — native folder picker `POST /api/grants/pick` + `/workspace` | `.iss [Icons]` has no grants entry; `client.ts:145-146` |
| **Revoke a grant** | None (terminal `Revoke-Workspace -Id`) | **Terminal** | Yes — `DELETE /api/grants/:id` | `client.ts:147` |
| **List current grants** | None (terminal `Get-Grants` / `Test-Grants`) | **Terminal** | Yes — `GET /api/grants` + `/test` | `client.ts:143-144` |
| Stop the agent (kill switch) | Start-Menu **Kill Switch** shortcut → `clawfactory-stop.ps1` | **Semi** (GUI-launched, shows a console) | Not the primary surface | `.iss [Icons] :111` |
| Check whether it's running | ClawChat connection state / browser dashboard at `:8787` | **GUI** (indirect) | Yes — Studio health/activity panel | `launcher.ps1:23-30` |
| View spend / the cap | None (terminal `Get-SpendStatus`) | **Terminal** | Yes — Studio cost meter (`$27.08/mo` proven in Phase 2) | `grants.ps1 Get-SpendStatus :639`; card #117 |
| **Change the cap** | None — **hand-edit `C:\ProgramData\ClawFactory\governor.json`** | **Terminal** (manual file edit) | Not built (read-only meter today) | `Get-GovernorConfig :591-608` |
| Switch providers | Start-Menu **Switch AI Provider** → `switch-provider.ps1` (`-NoExit`): **requires admin**, prompts to paste key via `Read-Host`; **known-buggy (M4/M5/M6)** | **Semi + broken** | Partial (Studio settings) | `.iss [Icons] :124-128`; `switch-provider.ps1:30,115`; CLAUDE known-issues M4-M6 |
| View / restore safety rules | None — reinstall, or restore `SOUL.md` from `resources/` and re-pin | **Terminal** | No | `SECURITY_FINDINGS.md` safety-rules row; `Test-SoulIntegrity :695` |
| Update | Re-run the installer `.exe` | **GUI** | Studio installer | `.iss` |
| Uninstall | Windows Add/Remove Programs → runs `uninstall.ps1` | **GUI** | Studio uninstaller | `.iss [Code] :671-699` |
| Recover: gateway down | ClawChat/launcher auto-restarts + polls up to 120s | **GUI** | Yes | `launcher.ps1:5-11,25-31` |
| Recover: key invalid/expired | Re-run Switch Provider (semi/broken) or reinstall | **Semi/Terminal** | Partial | `switch-provider.ps1` |
| Recover: cap reached | Turn blocked with readable message; **raising the cap = hand-edit `governor.json`** | **Terminal** to fix | Not built | `Test-TurnAllowed :678-693` |
| Recover: spend meter cold | Auto-handled since v1.0.45 (prime+retry); no user action | **GUI** (transparent) | n/a | memory / CLAUDE v1.0.45 |

> **ClawChat scope note (unverified this session):** stale docs (CLAUDE header, v1.0.21) claim ClawChat v1.1 gained a settings tab with provider switching + a security-tier selector, while the v1.0.20 known-issues (C2) says it has *no* settings tab. There is **no code in either in-scope repo** that wires ClawChat to grants, spend, or safety rules. Treat ClawChat as the **chat surface only** for this inventory; any settings-tab capability needs a separate verification pass against the ClawChat repo before it can be counted.

---

## Task 4 — Assessment

### 4.1 Gap list (must gain a GUI surface for "zero terminal"), ordered by how often a normal user hits it

1. **Grant a folder** — the single most common action; today it is terminal-only. Highest priority.
2. **List / see current grants (with health)** — needed every time the user wonders "what can the agent see?"
3. **Revoke a grant** — the safety-relevant counterpart to granting.
4. **View spend + cap** — users check this often once they understand it costs money.
5. **Change the cap** — currently a raw JSON edit; a footgun and a support driver.
6. **Switch providers / re-enter a key post-install** — semi-terminal and known-broken (M4/M5/M6); overlaps card #138.
7. **View / restore safety rules** — rare, but the recovery story is "reinstall," which is poor.

(API-key initial entry, first launch, update, uninstall, and gateway-down recovery are **already GUI** and are not gaps.)

### 4.2 Where each gap most naturally belongs

| Gap | Natural home | Rationale |
|---|---|---|
| Grant a folder | **Studio** (folder picker already built) or a **small dedicated tray/utility** | Needs a native OS folder picker + live mount state; belongs in a persistent management surface, not the installer. |
| List grants (health) | **Studio** | `Test-Grants` is already surfaced as `/api/grants/test`. |
| Revoke a grant | **Studio** | Pairs with the list. |
| View spend + cap | **Studio** (cost meter already built) | Already proven in Phase 2. |
| Change the cap | **Studio** (extend meter to editable) | Keep it beside the meter. |
| Switch provider / re-key | **Installer wizard** for first key (done) + **Studio settings** for rotation | Aligns with card #138; retire the admin/`Read-Host` script path. |
| View/restore safety rules | **Studio** (read-only view) + installer "repair" | Restore is inherently privileged; a one-click "repair" in the installer is the honest fit. |

### 4.3 Recommendation (stated directly)

**Studio is the right home for the management gaps (grants, spend/cap, provider settings, safety-rules view) — but it cannot go on the critical path until it is (a) validated on a clean VM and (b) hardened against the exact actor this product assumes is hostile.** Do not stand up a second management UI in the main product; that duplicates the folder picker, cost meter, and grant panels Studio already has, and splits the security review surface. The main product's own zero-terminal scope should stay narrow: the **installer wizard** owns first-run (provider + API key — already GUI) and a one-click "repair," and Studio owns everything post-install.

The two conditions are non-negotiable, because putting Studio on the critical path is precisely what converts Finding B from theoretical to live:
1. **Validate Studio** (it has never had a clean-VM pass) — the same install-gate discipline used for v1.0.45.
2. **Close the unauthenticated-loopback exposure** before shipping: keep WSL networking at **NAT** and Studio bound to **`127.0.0.1`** as *tested invariants*, and add real request authentication to Studio's grant routes rather than relying on the "localhost implies trusted" assumption — because the agent is a localhost-adjacent actor by design. Pair this with Finding A (`[interop] enabled=false`) so file isolation and self-grant don't share a single point of failure.

If Studio validation slips, the **interim** zero-terminal grant surface should be a **tiny signed tray utility** that calls the same `Grant-Workspace`/`Revoke-Workspace`/`Test-Grants` library directly on the Windows side (no network surface at all) — strictly better than Studio on the security axis, and far less work than a full second UI.

### 4.4 Rough effort per gap

| Gap | Effort | Note |
|---|---|---|
| Grant a folder (Studio) | **S** | Picker + `/api/grants/workspace` exist; wire the panel. |
| List grants + health (Studio) | **S** | `/api/grants/test` exists. |
| Revoke (Studio) | **S** | `DELETE` exists. |
| View spend + cap (Studio) | **S** | Cost meter built. |
| Change the cap (Studio) | **M** | New write endpoint over `governor.json` + validation. |
| Switch provider / re-key | **M** | Overlaps card #138; also fix M4/M5/M6 in `switch-provider.ps1`. |
| View/restore safety rules | **M** | Read view is S; privileged restore/repair is M. |
| **Studio validation pass** | **L** | Clean-VM install-gate discipline; never done. Prerequisite for all Studio items. |
| **Studio auth + networking hardening (Finding B)** | **M** | Auth on grant routes + tested NAT/127.0.0.1 invariants. Ship-blocker if Studio is on the path. |
| `[interop] enabled=false` hardening (Finding A) | **S** | One wsl.conf block + a smoke check. |

---

## End-of-session gate

### Task accounting
- **Task 1 (security question):** DONE. Verdict **NO** on a correct install, with file:line evidence and every vector enumerated. Three defense-in-depth findings (A/B/C) surfaced and reported, not patched.
- **Task 2 (grant behavior):** DONE (table). Additive; deterministic stable slug; single-grant revoke; three enumeration views; footguns catalogued.
- **Task 3 (drop-out inventory):** DONE (table). Grants/revoke/list/spend/cap/safety-rules are the terminal-only gaps; API key + first launch + update + uninstall are already GUI.
- **Task 4 (assessment):** DONE. Direct recommendation: Studio for management gaps, conditional on validation + auth/networking hardening; narrow installer scope for the main product; tray-utility fallback.

### Resource ledger
**No Azure resources created, started, or touched.** No VM provisioned (out of scope by instruction). No cloud spend. This was a read-only source inspection plus Dispatch card sync.

### Delta security sweep
**No product code changed** — verification session. Zero new attack surface introduced. Three *pre-existing* residuals were documented (Findings A/B/C); none is a new regression and none was modified. The most consequential, Finding B, is a **design constraint** that becomes a ship-blocker only if/when Studio is placed on the zero-terminal critical path.

### Delta bug review (incl. anything Task 1 surfaced)
- **Finding A** — interop not explicitly disabled in `setup.ps1` wsl.conf; isolation is transitive on `automount=false`. *Not a live break; hardening recommended for v1.1.*
- **Finding B** — Studio grant API is unauthenticated on loopback; safe only under NAT + 127.0.0.1 bind. *Ship-blocker for the Studio-on-critical-path plan; not a defect in the shipped product.*
- **Finding C** — `Invoke-GrantReplay` re-mounts `grants.json` without re-validating the deny-list; safe only because the ledger is unreachable from WSL today. *Hardening recommended.*
- Latent footgun: apostrophe in a Windows path breaks the single-quoted bash mount string (`clawfactory-grants.ps1:389`). *Low severity; UI should reject `'`.*
- No new bugs introduced this session.

### Git expectation
`git status --short` should show **only this close-out** (`docs/session_reports/GRANT_VERIFY_ZERO_TERMINAL_2026-07-19.md`). If any product source file appears in the diff, stop — nothing in this session edited product code.
