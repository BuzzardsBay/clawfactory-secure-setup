# Studio wiring scope, and #199a documentation

**Session date:** 2026-08-13
**Track:** v1 fast-security-harness
**Depends on:** interim validation complete (`2fbf12e`), card #215 closed
**Dispatch card:** #242
**Repos read:** `ClawFactory-Secure-Setup`, `ClawFactory-Studio` (both clean at start)
**Code written:** one user-facing document. No wiring, no backend, no rebuild, no VM.

---

## 0. The headline, before anything else

**The three panels are already wired. All of them. End to end.**

The job was scoped on the premise that Approvals, Recently deleted and Email settings are
unwired scaffolding and that wiring them is unscoped plumbing with a security-relevant
approve channel. That premise is wrong, and it is wrong in the direction that makes this
cheaper rather than more expensive.

Every link in the chain exists, in source and in the shipped payload:

| Link | Approvals / Email settings | Recently deleted |
|---|---|---|
| Page calls | `api.send.*` | `api.quarantine.*` |
| Client routes to bridge, not HTTP | `client.ts:274-305` | `client.ts:256-269` |
| Preload exposes the channels | `preload.ts:37-50` | `preload.ts:29-32` |
| Main process registers the handlers | `main.ts:194` | `main.ts:193` |
| IPC layer with per-channel validation | `send-ipc.ts` (5 channels) | `quarantine-ipc.ts` (2 channels) |
| Typed engine over PowerShell | `send-engine.ts` | `quarantine-engine.ts` |
| PowerShell functions exist in the shipped engine | `clawfactory-grants.ps1:889-1016` | `:812-848` |
| Root-side ctl exists and is bundled | `clawfactory-sendctl.js` | `clawfactory-quarantinectl.js` |
| Reply shapes match what Studio parses | `sendd.js:334-338` returns `{ok, pending[]}` | `quarantinectl.js:74-85` returns `{ok, retentionDays, store, items}` |

No link is missing. Not routing, not a backend process, not build config.

**So the scope question changes.** It is not "what does wiring cost". It is "this has never
been run once, and one defect is already visible by inspection". The work ahead is a defect
fix measured in characters plus a validation pass, not a build.

### What D4 actually observed

The interim close-out (D4, lines 120-144) quotes this banner and attributes it to the three
panels:

> "Studio backend unreachable. This panel is not wired in the desktop shell scaffold yet.
> Studio is being rebuilt as a native app; the Workspace (grants) panel is fully functional."

That string is a composite of two separate pieces of product text, and it is rendered by
exactly one screen: `frontend/src/pages/Status.tsx:37-41`, the **home route** (`/`), which is
the first thing Studio shows on launch. `StatusPage` calls `api.version()`, which is one of
the panels that genuinely is unwired, so it throws `SHELL_UNAVAILABLE` (`client.ts:53-55`),
and the page renders a failure pill whose label is `"Studio backend unreachable"` and whose
detail is that thrown message.

Search both repos: no code path in `ApprovalsPage`, `SmtpSetupPage` or `RecentlyDeletedPage`
can produce that string. Their error states read `"Couldn't load pending messages: ..."` and
`"Couldn't load recently deleted files: ..."`, with the engine's own message appended.

The supporting evidence cited in D4 points the same way. "Confirmed structurally: no Studio
backend is listening at all" is true and is **not** a finding: the current Studio has no
listener by design. `main.ts:2-7` says so, and says why. The previous Studio bound
`127.0.0.1:8080` with an unauthenticated grant route reachable from inside WSL under
mirrored networking, and that listener was removed as a ship-blocker. A port scan finding
nothing is the fix working. The Workspace panel that D4 correctly reports as functional also
has no listening port.

**The two supporting facts D4 offers are both consistent with a fully working Studio.** The
banner was read on the home screen, and the port scan measured the wrong thing.

I am deliberately not claiming the panels work. Nobody has clicked them on an installed
machine, and section 3 records one defect that says at least one of them does not. I am
claiming the diagnosis in the record is wrong about the cause, which changes what to do next.

### The v0.1.0 that is not a stale payload

D4 says "the installed Studio v0.1.0". `desktop/package.json` says `1.1.0`. Both are correct
observations of different things: `frontend/src/App.tsx:37` renders the version as a
**hardcoded string literal** in the header, never read from `package.json`, and it was never
updated when Studio was bumped `0.1.0` to `1.1.0` at `b4e773c`.

So "v0.1.0" is a cosmetic staleness in one string, not evidence that an old payload shipped.
It is worth fixing precisely because it caused a wrong inference once already.

---

## 1. Task 1. What actually exists

### 1.1 The three panels

All three are **complete**, not stubs and not partial. No `TODO`, no "coming soon", no
placeholder returns. Each calls only the preload bridge and nothing over HTTP.

| Panel | File | Lines | Calls | Target exists |
|---|---|---|---|---|
| Approvals | `frontend/src/pages/send/ApprovalsPage.tsx` | 280 | `api.send.list`, `api.send.credential`, `api.send.approve`, `api.send.deny` | yes |
| Email settings | `frontend/src/pages/send/SmtpSetupPage.tsx` | 226 | `api.send.credential`, `api.send.setCredential` | yes |
| Recently deleted | `frontend/src/pages/deleted/RecentlyDeletedPage.tsx` | 217 | `api.quarantine.list`, `api.quarantine.restore` | yes |

They are also more finished than "renders data". `ApprovalsPage` carries a live countdown
that re-renders each second (`:87-90`), disables Approve on an expired item (`:195`), sends
the payload hash with every approval (`:107`), shows the body itself rather than a summary,
and lists every recipient including Bcc. There is no approve-all and no bulk action.

### 1.2 The grants trace, which is the template

Renderer to root, for the one path proven to work, since the other two follow it exactly:

1. **Renderer.** `WorkspacePage.tsx:66` calls `api.grants.all()`.
2. **Client.** `client.ts:223-227` calls `bridge().grants.list()`. `bridge()`
   (`client.ts:151-159`) reads `window.studio` and throws a readable error if absent. The
   reply is a discriminated envelope: `{ok:true, ...}` or `{ok:false, error, deny?}`.
3. **Preload.** `preload.ts:18` maps `list()` to `ipcRenderer.invoke('grants:list')`. This is
   the security boundary. There is no generic `invoke(channel)`, no `ipcRenderer`
   passthrough, no Node built-ins. The renderer cannot name a channel.
4. **IPC, main process.** `grants-ipc.ts:29-35` handles `grants:list`, catches everything, and
   returns an envelope rather than throwing across the process boundary. Every channel is
   hardcoded and separately validated.
5. **Engine.** `grants-engine.ts:194` calls `invokeEngine('Get-Grants', true)`.
   `invokeEngine` (`:37-91`) builds a PowerShell script that dot-sources the installed engine
   and pipes the result through `ConvertTo-Json`, base64-encodes it as UTF-16LE, and spawns
   `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand`. It
   has a 60 second timeout and converts an `__engine_error` marker back into a typed
   `EngineError`.
6. **Path resolution.** `config.ts:36-47` resolves
   `C:\Program Files\ClawFactory\resources\clawfactory-grants.ps1`, lazily per call, with a
   readable error naming the exact missing file. Confirmed bundled at
   `ClawFactory-Secure-Setup.iss:56`.
7. **PowerShell to root.** `clawfactory-grants.ps1` runs `wsl.exe -u root`.
8. **Back.** JSON on stdout, parsed in the main process, envelope to the renderer.

The load-bearing property: **the privileged path runs on Windows, in the Electron main
process, as the logged-in user.** `clawuser` (the agent) is not on this path at any point.
It reaches the renderer only through the enumerated IPC channels, and the renderer runs with
`contextIsolation: true`, `nodeIntegration: false`, `sandbox: true`, a strict CSP with
`connect-src 'none'`, navigation blocked and window-open denied (`main.ts:24-33, 52-67`).

Quarantine and send replicate this trace with no deviation in shape. Same envelope, same
hardcoded channels, same engine invocation, same PowerShell to `wsl -u root`.

### 1.3 The four committed modules, and whether the packaged shell reaches them

| Module | Lines | Reachable from the packaged shell |
|---|---|---|
| `desktop/src/quarantine-engine.ts` | 76 | yes |
| `desktop/src/quarantine-ipc.ts` | 43 | yes, registered at `main.ts:193` |
| `desktop/src/send-engine.ts` | 110 | yes |
| `desktop/src/send-ipc.ts` | 110 | yes, registered at `main.ts:194` |

Verified against build output, not just source:

- `desktop/dist/preload.js` (compiled, 2026-08-05 10:48) contains all three channel groups
  including `quarantine:list`, `quarantine:restore` and the five `send:*` channels.
- `desktop/dist/` contains `quarantine-engine.js`, `quarantine-ipc.js`, `send-engine.js`,
  `send-ipc.js`, all stamped 10:48.
- The built renderer bundle `desktop/renderer/assets/index-C26n1Rj-.js` (same timestamp)
  contains the bridge call sites: `.send.list()`, `.quarantine.list()`, `.send.credential()`,
  `.send.approve`, `.send.setCredential`, `.quarantine.restore`, plus panel-specific strings
  such as `retentionDays`, `restoredTo` and `payloadHash`.
- `electron-builder.config.cjs` packages `['dist/**/*', 'renderer/**/*', 'package.json']`, so
  all of the above go into `app.asar`.

Nothing is missing. Not routing, not a backend process, not build config.

### 1.4 What the banner means in code

`Status.tsx:35-42`. The check is `api.version()`, which is `get('/api/version')`, which is one
of the deliberately-unwired HTTP stubs (`client.ts:57-60`). It tests **nothing about the
guard panels**. What has to become true for that banner to clear is that Studio grows a
`version` source, which is unrelated work on a page whose text ("Running on
http://127.0.0.1:8080", `Status.tsx:48`) describes an architecture that was removed.

The genuinely unwired panels are Status, Agents, Skills, Chat, Settings, Themes, Activity,
Files, Templates, Get started and the Wizard. That list is real and is not this job's scope,
but it is what `SHELL_UNAVAILABLE` was written for.

### 1.5 Why packaged v0.1.0 appeared to differ from source

It did not. Three separate things produced one wrong conclusion:

1. **A hardcoded version string.** `App.tsx:37` renders `v0.1.0` as a literal. The payload was
   1.1.0.
2. **A banner read on the wrong screen.** Home route, not the panels.
3. **A port scan of an architecture with no ports.** By design since the inbound listener was
   removed.

One thing genuinely does obscure this and is worth recording separately: **the built renderer
is not in version control.** `desktop/.gitignore:5` ignores `renderer/`, and
`backend/public/` is ignored too. So what shipped inside `app.asar` is whatever was on the
build box at build time. In this case it was current (10:48, minutes before the 11:07 build
close-out), and the build session verified marker strings inside the new asar. But nothing
structural prevents a stale renderer from being packaged, and there would be no diff to see
it in. That is the same class of gap as the rootfs provenance finding.

---

## 2. Task 2. The scope

### 2.1 What is missing, per panel

| Panel | Missing |
|---|---|
| Recently deleted | Nothing found by inspection. Chain complete, shapes match. Never executed. |
| Approvals | Nothing found by inspection. Chain complete, shapes match. Never executed. |
| Email settings | **One defect, confirmed.** See below. Chain otherwise complete. |

**The defect: saving SMTP settings from Studio cannot work.**

`send-engine.ts:104-108` builds a two-statement PowerShell expression:

```
$j = [Console]::In.ReadToEnd() | ConvertFrom-Json; Set-SendCredential -SmtpHost $j.host ...
```

`grants-engine.ts:113` interpolates it into `ConvertTo-Json -Depth 8 -Compress -InputObject
(${expression})`. PowerShell's grouping operator `( ... )` accepts one pipeline, not a
statement list. Parsed with `[Parser]::ParseInput` against the exact string the code builds:

```
PARSE ERRORS: 2
  Missing closing ')' in expression.
  Unexpected token ')' in expression or statement.
```

The subexpression form `$( ... )` parses clean (0 errors) with the same body.

So a user filling in Email settings and clicking save gets a PowerShell parse error, not a
stored credential. It fails closed, which is the right direction, and the error surfaces in
the UI rather than being swallowed. But the panel does not do its job.

This is also **exactly the path the interim validation wanted and could not use.** D4 item 3
records that Bret was to enter the SMTP app password through Studio and a root-channel helper
was substituted. Had that path been attempted, this would have been found in August rather
than by inspection now.

Fix is one of two small edits, and the choice matters slightly:

- `send-engine.ts:104`, restructure the expression into a single pipeline. Narrow, affects
  only this call site. **Recommended.**
- `grants-engine.ts:113`, change `(${expression})` to `$(${expression})`. General, but
  changes semantics for every caller: a subexpression emitting more than one object yields an
  array. Today the assignment emits nothing so the result is identical, but it is a wider
  blast radius for no extra benefit.

Not fixed in this session. The job scopes and does not wire, and this sits in the send path.

### 2.2 One backend or three?

**Neither. Keep the current shape: zero backends, per-feature engine and IPC module pairs in
the Electron main process.** That is already what exists, and it is already three, following
the grants pattern exactly.

Reasoning:

- **A shared backend is the thing that was removed as a ship-blocker.** The previous Studio
  bound `127.0.0.1:8080` with an unauthenticated grant route, reachable from inside WSL under
  mirrored networking. Re-introducing any listener re-opens that, and it would now be a
  listener that can approve email.
- **The per-feature split is the security argument, not just tidiness.** `send-ipc.ts:12-17`
  states the rule: adding a channel here is the one way to undo Guard 2, so every addition
  answers "can the agent influence this" first. Five channels in a 110-line file that a
  reviewer reads in one sitting. A shared router with a channel registry loses that.
- **There is no shared state to justify unification.** The three features share
  `invokeEngine`, and that is the entire useful overlap. They already share it.

The work is not "build a backend". There is nothing to build.

### 2.3 Where it runs, as what user, and whether the property survives

**It runs in the Electron main process, on Windows, as the logged-in interactive user.** It
reaches root through `powershell.exe -EncodedCommand`, which calls `wsl.exe -u root`, which
speaks to `/run/clawfactory/send-admin.sock` (0600 root:root) via a 0750 root:root ctl.

**The recommended approach preserves Guard 2's core property, because it changes nothing
about the shape.** The invariant is that no send path may ever run as uid 1000. Nothing
proposed here introduces a uid 1000 path, a listener, a socket the agent can open, or an IPC
channel the agent can influence. The defect fix in 2.1 is a PowerShell syntax correction on
a path that already exists.

Two things that would break it, recorded so they are refused rather than rediscovered:

1. **Any inbound listener in Studio**, on any interface, for any reason. Under mirrored
   networking the agent reaches Windows loopback.
2. **Any approve channel that does not require the payload hash.** `send-ipc.ts:62-64`
   enforces a 64 hex character hash. Approving by id alone would approve whatever that id
   holds now instead of what the user read.

### 2.4 What has to be re-validated

Test 8 (`interim-v120-phase3.ps1:268-303`) tests five channels, all from `clawuser` inside
WSL: approve on the request socket, direct connect to the admin socket, executing the ctl
`.js`, the ctl wrapper, and `node <ctl>`. **None of them involve Studio.** So test 8 does not
need re-running against a wired Studio so much as **extending**: a wired Studio adds a sixth
channel that the suite has never covered, the Electron IPC bridge. The question to answer is
whether anything the agent can influence can drive it. It should not (no bridge into WSL,
interop disabled, renderer sandboxed, no listener), but "should not" is what validation is
for.

Every Guard 2 and Guard 1 test whose result depends on Studio's shape:

| Test | Suite | Why it depends |
|---|---|---|
| **8, agent cannot approve** | Phase 3 | Needs a sixth channel: the IPC bridge. Existing five stay as-is |
| **0, credential configured, one destination authorized** | Phase 3b | Studio's Email settings is the intake. Blocked today by 2.1 |
| **2, card carries the full payload** | Phase 3b | "Card" now means the rendered panel, not ctl JSON |
| **3, approve executes a real send** | Phase 3b | Via the Approve button |
| 3b, staging purged after send | Phase 3b | Indirect, triggered by the approve above |
| 3c, receipt has a reference not the body | Phase 3b | Indirect, same |
| **4, deny sends nothing** | Phase 3b | Via the Deny button |
| **5, replay of a consumed approval refused** | Phase 3b | Studio must not offer re-approve on a consumed card |
| **5b, wrong payload hash voids the approval** | Phase 3b | Studio must send the hash it displayed, not a re-fetched one |
| 6, attachment rewritten after approval | Phase 3b | Indirect, via the approve path |
| **7, expired approval refused** | Phase 3b | Studio's countdown and disabled button are now part of the behaviour |
| **13, credential absent from every surface** | Phase 3b | **New surfaces**: Electron main process argv, renderer memory, Studio logs. The stdin discipline exists for this and has never been exercised through Studio |
| **Guard 1 restore** | Phase 2 | Entirely a Studio path. Restore is deliberately unreachable from the agent |
| **Guard 1 no-purge surface** | carried forward | Currently REVIEW, heuristic scan only. Becomes directly testable: there is no purge channel in `preload.ts` or `quarantine-ipc.ts` |

Nine tests change materially, four are indirect, one carried-forward REVIEW becomes provable.

**The harness gap that makes this real work.** Studio is a packaged GUI. The existing proof
harness (`main.ts:141-178`, `STUDIO_SELFTEST_ACTIONS`) drives the write path by calling the
same exported functions the IPC handlers call, which is legitimate, but its action grammar
supports only `grant=`, `revoke=` and `list`. Extending it to quarantine and send actions is
the actual build work in this validation, and it needs care: driving the engine functions
proves the engine, and does **not** prove the button, the countdown, the disabled state or
that the displayed hash is the submitted hash. Some of test 5b and 7 need the UI itself.

### 2.5 What breaks the pin

Rebuilding Studio changes `app.asar`, so the NSIS installer's bytes change, so:

- `scripts/build_release.ps1:128` `$studioPinned` (`b701bfb7...`) moves. The gate fails the
  build until it is updated by hand, which is correct behaviour and is the fifth gate.
- **The version-in-filename problem recurs and gets worse.** Per the build close-out §4.4,
  `ClawFactory-Studio-Setup-1.1.0.exe` is already a filename reused for different bytes. A
  third distinct payload under the same name compounds it.

**Recommendation: bump Studio's version in this pass.** The close-out deferred it to avoid a
second variable in the first gated build. That reason has expired: the gated build shipped.
Bumping touches `ClawFactory-Secure-Setup.iss:16` (`#define StudioInstaller`),
`build_release.ps1:127` (`$studioName`) and `:128` (`$studioPinned`), plus Studio's
`package.json` files. Do it in the same pass as `App.tsx:37`, so the header string, the
filename and `package.json` finally agree.

Also worth doing while the build is open: **stop gitignoring the built renderer**, or record
its digest. Today the payload's UI is not reproducible and not diffable.

### 2.6 Estimate

In sessions, assuming no VM is provisioned until the validation session.

| Phase | Sessions | Contents |
|---|---|---|
| Wiring | **0.5** | The `Set-SendCredential` parse fix, `App.tsx:37` version, Studio version bump across four files, rebuild, repin, `.iss` define |
| Validation | **1.5 to 2** | Extend the selftest harness to quarantine and send actions, extend test 8 with the IPC channel, re-run the nine dependent tests on a clean box, GUI-driven checks for 5b and 7 |
| Rework buffer | **1** | |
| **Total** | **3 to 3.5** | |

**What would make it larger:**

- **Runtime failures not visible in source.** The chain is verified structurally and has never
  been executed. `ConvertTo-Json -Depth 8` on a large body, the 60 second PowerShell timeout
  against a cold WSL distro, or a shape mismatch under a single-element array are all
  plausible and none are provable by reading. Add a session if two or more surface.
- **GUI driving.** If the selftest harness cannot cover the UI-dependent assertions (5b, 7,
  and the payload-hash binding), a real GUI automation approach is needed on a headless VM.
  That is the single largest risk. Add one to two sessions.
- **Test 13 through new surfaces.** If the credential turns out to be visible in an Electron
  main process argument, a crash dump or a renderer devtools surface, that is a real fix, not
  a test change.
- **The unwired panels drawing scope.** Status, Settings, Activity, Files and the rest are
  genuinely unwired and a founder looking at a working Approvals panel next to a broken
  Status page will reasonably ask. Hold that line or it doubles.

### 2.7 Sequence: confirmed, with a sharper reason and one change

**Confirmed: Studio ahead of Guards 3 and 4.** The stated reason (Guard 3 adds config
surfaces wanting the same backend) holds and is strengthened by Task 1: there is no backend
to want, there is a **pattern**, and Guard 3 should follow it rather than invent a fourth
shape. Validating the pattern under two guards before a third is built is the cheap ordering.

Two stronger reasons the original framing did not have:

1. **It is now mostly validation, not building.** A validation pass slots in before Guard 3 at
   a fraction of the assumed cost.
2. **The record is wrong right now.** D4 says these panels do not function and the honest
   claim sentences carry "may not yet be paired with a claim about Studio". That constraint
   is currently based on a misreading. Every week it stands, copy decisions are made against
   a false constraint, and the temptation to rewrite honest copy grows.

**The change I recommend: put a smoke check first, before the fix and before the rebuild.**

Half a session, one clean box, the **existing** signed v1.2.0 artifact with no rebuild and no
pin movement. Install, launch Studio, open all three panels, screenshot each. That answers
the one question inspection cannot: does this chain execute at all. Two possible outcomes and
both are worth the half session:

- **They load.** Then D4 is corrected on evidence, the scope in 2.6 is confirmed, and Email
  settings is the only known defect.
- **They error.** Then the real error message is in hand, which is the diagnostic the record
  has never had, and 2.6 gets re-estimated against a fact.

Doing the version bump and the repin before knowing this spends a build and a pin movement on
an assumption.

**Recommended order:** smoke, then fix, then rebuild and repin with the version bump, then the
validation pass, then Guard 3.

---

## 3. Task 3. Every surface that names a Studio panel

Listed, not changed, per instruction. If Studio is confirmed working these all become true as
written and the churn was correctly avoided.

### Agent-facing wording, the highest-stakes group

| Location | Text |
|---|---|
| `resources/clawfactory-quarantine-rm.js:232` | `rm: '<arg>' moved to ClawFactory quarantine (restorable from Studio > Recently deleted)` |
| `resources/quarantine-lib.js:224` | `Nothing was deleted. Open Studio > Recently deleted and restore or clear ...` |
| `resources/quarantine-lib.js:248` | `... Studio > Recently deleted and clear items, then try again.` |
| `resources/clawfactory-send.js:54` | usage text: `Nothing is sent until you approve it in ClawFactory Studio.` |
| `resources/clawfactory-send.js:228` | success output: `Queued for approval in ClawFactory Studio. Nothing has been sent.` |

The first three are what D4 called out: the agent tells the user, in its own words, to restore
from a panel. Note this is the CLI's own literal text, not model-authored, which makes it both
more predictable and more binding.

### SOUL and safety rules

| Location | Text |
|---|---|
| `resources/safety-rules.md:19` | `... only when the user approves that exact message in Studio, and an approval covers one message once.` |
| `resources/safety-rules.md:21` | `... the file is kept for 30 days and the user can restore it from Studio.` |

**Covered by the workspace SOUL pin.** Editing either moves a build-time digest.

### Orchestrator prompt

| Location | Text |
|---|---|
| `resources/orchestrator-prompt.md:50` | `... approves that exact message in Studio, and the approval is single use and bound to the exact ...` |

### Persona

No Studio panel references. `resources/persona.md` is clean. (Persona is a build-time
constant with its own pin, so this being clean is convenient.)

### Installer and post-install

| Location | Text |
|---|---|
| `resources/install-send.sh:235` | `[send] no destination is authorized until SMTP is configured in Studio (fail-closed)` |
| `resources/egress-policy.json:13` | `permitted until the user configures SMTP in Studio, which is the act that authorizes` |
| `ClawFactory-Secure-Setup.iss:1093` | wizard status: `Installing ClawFactory Studio (your visual workbench)...` |

`resources/post-install.ps1` names no panel.

### Repo documentation

| Location | Text |
|---|---|
| `SECURITY.md:114` | `The Permissions page in Studio exists so users can opt into broader access.` |

**Note:** the Permissions page is one of the genuinely unwired panels. This line is
independently inaccurate today and is **not** fixed by wiring the three guard panels. It is
the one item on this list that needs attention regardless of the Studio decision. Recorded,
not changed, per instruction.

`README.md` names Studio only as a build input (the payload pin), no panels.

### Site copy

`C:\Users\bmcki\clawfactory-site\index.html`, lines 748, 839, 855, 925, 1003, 1016. All
describe Studio as "a visual workbench for managing setup and granting the agent access to
specific project folders", which is the **grants** panel, the one already proven to work.

**No live site copy names Approvals, Recently deleted or Email settings.** Nothing to change
there in either direction.

### Studio's own strings

`frontend/src/App.tsx:46-51` (nav labels), `RecentlyDeletedPage.tsx:166`,
`ApprovalsPage.tsx:214, 216-217, 233`, `SmtpSetupPage.tsx:89-91`.

### New this session

`docs/reference/EMAIL_APPROVAL.md` sections 4 and 5 reference Approvals and Email settings.
Carries an explicit status note, see section 4.

---

## 4. Task 4. `clawfactory-send` documentation

**Delivered:** `docs/reference/EMAIL_APPROVAL.md`.

Written for the user, not the agent. Per the founder decision on #199a, nothing in the
agent's context changed: no persona text, no SOUL text, no orchestrator prompt. Those are
covered by the workspace SOUL pin and this is a documentation change.

The document explains what `clawfactory-send` is, why the agent will not offer it (framed as
the security property it is, including the approval-fatigue reasoning), how a person invokes
it deliberately by naming the command, what the approval card shows, what approve and deny
do, the ten minute window, how to configure the email account, the limits, and what the agent
structurally cannot do.

The claim sentence is used verbatim with its boundary attached, both quoted as blocks:

> Your agent can write an email. It cannot send one. Every message waits for you, and
> approving it sends exactly that message, once.

> This covers email. It is not a claim that no data can leave your machine: your agent talks
> to a hosted AI model, and anything it can read it can send there.

No new claim language was written.

**The Studio note, as instructed, and adjusted for what Task 1 found.** The instruction was to
note that the flow references panels that do not function. Task 1 shows the more accurate
statement is that the panels are built and wired but have never been exercised, with one
confirmed defect in Email settings. So the document carries a status section saying the
mechanism is validated end to end including real external delivery, that the Studio side is
built and wired but never exercised on an installed machine, and that sections 4 and 5
describe the implemented flow rather than an observed one. That note comes out when the
panels have been driven on a clean install.

Overstating ("does not work") would have been as wrong as understating, and this project's
worst finding to date was a false assurance in the other direction.

---

## 5. End-of-session gate

### 5.1 Task accounting

| Task | Status | Note |
|---|---|---|
| Dispatch card at session start | **DONE** | #242 created, moved to done at close-out |
| 1. Establish what exists (5 sub-items) | **DONE** | All five answered. Headline: premise was wrong |
| 2. Scope the work | **DONE** | Section 2. Five questions answered, sequence confirmed with one change |
| 3. Enumerate surfaces naming a panel | **DONE** | 18 locations across 6 groups. None changed |
| 4. Document `clawfactory-send` | **DONE** | `docs/reference/EMAIL_APPROVAL.md` |
| 5. End-of-session gate | **DONE** | This section |

Nothing dropped, nothing deferred silently. Explicitly **not** done, per scope: no wiring, no
backend code, no IPC handlers, no routing, no Studio rebuild, no pin movement, no VM, no
Guard 3 or 4, no restyle, no marketing copy, no tag, no Inno licence.

**One in-scope thing I did not do and am naming:** I did not fix the `Set-SendCredential`
parse defect. It is one line, and the instruction was to report rather than fix. It does not
meet the "must be fixed immediately, report and stop" bar: it fails closed, it is on a path
no customer has reached, and it is in the send path this job was told not to touch.

### 5.2 Resource ledger

| Resource | State |
|---|---|
| Azure VMs | **None provisioned.** No `az` invoked this session |
| Azure spend this session | **$0** |
| Live VMs from prior sessions | **0**, unchanged. Nothing to deallocate |
| Background processes / monitors | **None started.** Nothing left running |
| Local artifacts written | 2 files, both in `ClawFactory-Secure-Setup`, both committed |
| Scratchpad | Unused |
| `ClawFactory-Studio` | **Read only. No writes, no commits.** Clean at start and at close |

### 5.3 Delta security sweep

Scope: this session's changes, which are two markdown files and no code.

| Check | Result |
|---|---|
| Secrets in new files | **None.** No keys, tokens, passwords, hashes of secrets. `EMAIL_APPROVAL.md` describes credential handling and contains no credential |
| New attack surface | **None.** No code, no config, no build input, no bundled resource. Neither file is referenced by `setup.ps1`, the `.iss`, or any gate |
| Pinned digests touched | **None.** SOUL, persona, workspace SOUL, Studio and rootfs pins all untouched. No build-time literal moved |
| Agent-reachable content changed | **None.** No persona, SOUL, safety-rules or orchestrator-prompt edit. Nothing this session enters the agent's context |
| Overclaim in new copy | **Checked deliberately.** `EMAIL_APPROVAL.md` carries the boundary sentence with the claim, and a status section separating what is validated (the mechanism, including real external delivery) from what is not (the Studio surface) |
| Underclaim / false alarm | **Checked.** The close-out does not assert the panels work. It asserts the chain is structurally complete and unexecuted, and names one confirmed defect |
| Guard 2 invariant | **Preserved.** Nothing proposed introduces a uid 1000 send path, a listener, or an unhashed approve channel. 2.3 records the two changes that would break it |

### 5.4 Delta bug review

Two defects found by inspection. Neither introduced this session. Neither fixed, per scope.

**B1. Saving SMTP settings from Studio cannot work. Confirmed, not fixed.**
`send-engine.ts:104-108` with `grants-engine.ts:113`. A two-statement PowerShell expression
inside the `( ... )` grouping operator. Parse-tested: 2 errors; the `$( ... )` form parses
clean. Severity: **the customer-facing credential intake path is broken**, and it is the same
path the interim validation had to route around. Fails closed with a visible error. Fix is one
line, preferably at the `send-engine.ts` end (see 2.1).

**B2. Studio's displayed version is a hardcoded literal.** `App.tsx:37` renders `v0.1.0`,
never read from `package.json`, not updated at the `b4e773c` bump to 1.1.0. Severity: low as a
defect, **non-trivial as a diagnostic hazard**, since it is one of the three things that
produced a wrong conclusion in D4.

**Two observations that are not defects but belong in the record:**

- **The built renderer is not in version control** (`desktop/.gitignore:5`). What ships in
  `app.asar` is whatever was on the build box. Same class as the rootfs provenance gap.
- **`SECURITY.md:114` names the Permissions page**, which is genuinely unwired. Not fixed by
  wiring the three guard panels. Needs attention regardless of the Studio decision.

### 5.5 Next-session recommendations

1. **Smoke Studio's three panels on one clean box. Half a session.** The single highest-value
   action available. Uses the existing signed v1.2.0 artifact, no rebuild, no pin movement.
   Install, launch, open Approvals, Recently deleted and Email settings, screenshot each.
   Answers the one question inspection cannot, and either corrects D4 on evidence or hands
   over a real error message.
2. **Fix B1 and B2, bump Studio's version, rebuild, repin.** Half a session, after the smoke.
   Four files for the version bump plus the two fixes. Consider un-ignoring the built renderer
   in the same pass.
3. **The Studio validation pass. 1.5 to 2 sessions.** Extend the selftest action grammar to
   quarantine and send, extend test 8 with the IPC channel, re-run the nine dependent tests.
   Budget for GUI driving on 5b and 7.
4. **Correct D4 in the record.** Once the smoke lands, whichever way it goes. The honest claim
   sentences currently carry a constraint about Studio built on a misreading, and copy
   decisions are being made against it.
5. **Then Guard 3**, following the engine-plus-IPC pattern rather than inventing a fourth
   shape.

**Cheapest thing that would change the plan:** recommendation 1. Everything after it is
estimated against an assumption that thirty minutes on a VM would replace with a fact.

---

*Card #242. Close-out committed with the session's files. No tag.*
