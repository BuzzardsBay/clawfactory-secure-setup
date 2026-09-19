# OpenClaw 2.0 delta census — close-out

**Run date:** 2026-09-19. **Job class:** read-only census. **Dispatch card:** #332.
**Working root confirmed:** the repo root `ClawFactory-Secure-Setup` (`git rev-parse --show-toplevel` returned it; the local absolute path is omitted).
**Repo state measured:** `HEAD` = `590022ae9c42`, tag `v1.4.5` = `b3ef2d4277ef` (tag is 24 commits behind HEAD (`git rev-list --count v1.4.5..HEAD`); `setup.ps1` differs by 51 inserted lines, all firewall/timer read-backs, Step 8 identical).


**Gate answers, in the order the prompt asks.** (1) Task 0 verdict and evidence: §1. (2) Live-fetched or bundled, with the quoted line: §1.1 row 0.2 (**bundled**; `setup.ps1` Step 8 reads `$PSScriptRoot\resources\openclaw-install.sh`; `.iss:71`). (3) Guard 3 count, both halves, and the 2.0 delta table: §3. (4) Task 2 caller table: §4. (5) Whether 2.0 still reads what Step 11 and `bootstrap.ps1` write, item by item: §5 (3.4). (6) Any component under a uid other than `clawuser`: §6. (7) What `ClawChat.exe` talks to, and whether 2.0 changed it: §7. (8) Task 6 and Task 7 tables: §8. (9) Every `NEEDS BOX` as candidate cards: §9. (10) Contradictions with the prompt or spec: §1.4 and §10.
---

## 1. TASK 0 VERDICT (printed first, always)

### `PINNED 1.x, FRESH INSTALLS SAFE`

"1.x" is the verdict-vocabulary token from the prompt. The pin is calendar-versioned
`2026.4.27`, the pre-2.0 line. 2.0 is `2026.8.1` (npm publish 2026-08-31T02:45:39Z).

Priority 1: **NO.** No second Dispatch card, no PushNotification, no wait for acknowledgement.

**What decides it, in order of strength:**

1. **The bytes a user receives, measured.** The retained install transcript
   `validation/diag/v146-install.log` (box `cfv-191`, install started 2026-08-31 17:16, **the published
   v1.4.5**, identified by digest and by asset size 440,619,864 in
   `docs/session_reports/2026-08-31_systemd_reboot_persistence_closeout.md:438-443`) records, verbatim:

   ```
   validation/diag/v146-install.log:457  [wsl:root out] ...Requested version: 2026.4.27
   validation/diag/v146-install.log:477  [wsl:root out] ...Installing OpenClaw v2026.4.27
   validation/diag/v146-install.log:481  [wsl:root out] ...OpenClaw installed successfully (2026.4.27)!
   ```

   Timing matters: **2.0 had been on npm `latest` for ~14.5 hours when that box installed.** The pin
   held while `latest` was 2.0. (VM clock is UTC: the journal in `v146-d-diag2.out.txt` stamps `+00:00`, so 17:16 UTC vs 02:45Z. The ANSI colour codes and mojibake emoji in the raw lines are the
   installer's own output; quoted here with them elided.)
   Corroboration on the same box: `validation/diag/v146-d-diag2.out.txt:30-36` shows
   `OpenClaw Gateway (v2026.4.27)` stopping and starting under systemd.

2. **The mechanism is present at tag `v1.4.5`.** `git show v1.4.5:setup.ps1`:

   ```
   75:  $OpenClawNpmVersion    = '2026.4.27'
   2345 (tag numbering; 2371 at HEAD):
        NO_ONBOARD=1 OPENCLAW_VERSION=$OpenClawNpmVersion HOME=/home/clawuser USER=clawuser LOGNAME=clawuser timeout --foreground --kill-after=30 900 bash /tmp/openclaw-install.sh -- --no-onboard > >(tee /tmp/openclaw-install.log) 2>&1
   ```

   Commit `826fe74` ("fix(installer): pin OpenClaw npm version to 2026.4.27") is the origin; the
   mechanism is intact at the tag and unchanged at HEAD (`git diff v1.4.5 HEAD -- setup.ps1` touches
   only firewall/timer read-backs).

3. **The script consumes the pin** (bundled copy, `git show v1.4.5:resources/openclaw-install.sh`,
   sha256 `3a617b73ea35ac23cf856ce9615b69d0ace4090d236e0a57bbc638f01676a9ce`, 93,387 bytes, identical at HEAD):

   ```
   1004  OPENCLAW_VERSION=${OPENCLAW_VERSION:-latest}
   2343  if [[ -z "${OPENCLAW_VERSION}" ]]; then OPENCLAW_VERSION="latest"; fi          (empty -> latest)
   2308-2324 resolve_package_install_spec():  ... echo "${package_name}@${value}"      (-> openclaw@2026.4.27)
   2357  install_spec="$(resolve_package_install_spec "${package_name}" "${OPENCLAW_VERSION}")"
   712-732 run_npm_global_install():  cmd+=(--no-fund --no-audit install -g "$spec")   (the npm install line)
   2365  if [[ "${OPENCLAW_VERSION}" == "latest" && "${package_name}" == "openclaw" ]]; then   (@next retry only for latest)
   ```

   **When the variable is unset or empty the script installs `openclaw@latest`**, which today is
   `2026.9.5` (npm dist-tag `latest`, fetched 2026-09-19T15:21Z). So the pin is load-bearing and is
   honoured; it is not ignored.

4. **The pinned package is still installable.** npm registry (fetched 2026-09-19T15:21:51Z):
   `2026.4.27` published 2026-04-29T22:28:04Z, `engines.node >=22.14.0`, `deprecated=no`.

5. **The pinned gateway does not self-update to 2.0 by default.** Upstream `v2026.4.27`
   (`cbc2ba0931468259f26a7c547131a06e03ca6c6c`): `src/config/schema.help.ts:58`
   `"update.auto.enabled": "Enable background auto-update for package installs (default: false)."`;
   `update.checkOnStart` (default true) only logs a hint (`docs/install/updating.md:168`).
   ClawFactory sets neither key (`grep` over `setup.ps1` and `resources/` at `v1.4.5`: no
   `update.*`). Post-install drift to 2.0 therefore requires a user to run an update by hand.

### 1.1 Tasks 0.1 - 0.7, item by item

| Item | Answer | Evidence |
|---|---|---|
| 0.1 Step 8 pin | Pinned via `OPENCLAW_VERSION=$OpenClawNpmVersion`, value `2026.4.27` | `setup.ps1:75`, `:2345` at tag; `:2371` at HEAD |
| 0.1 mechanism from `826fe74` still present? | **Yes**, same value, same variable, at tag and at HEAD | `git log --oneline 826fe74 -1`; tag/HEAD diff has no Step 8 lines |
| 0.2 live-fetched or bundled? | **BUNDLED.** `$bundledScript = Join-Path $PSScriptRoot 'resources\openclaw-install.sh'`, streamed into WSL over stdin. No network call to `openclaw.ai/install.sh` in Step 8. Shipped: `ClawFactory-Secure-Setup.iss:71` `Source: "resources\openclaw-install.sh"` | `setup.ps1` Step 8 at tag; `.iss:71` at tag |
| 0.3 hash compare | **There is no pinned hash to compare against.** `$OpenClawInstallSha256` does not exist at tag `v1.4.5` (`git show v1.4.5:setup.ps1 \| grep OpenClawInstallSha256` = empty). It was replaced in v1.0.31 by a computed-and-logged `installShHash` (`REPORT_v1.0.31.md:71`; `setup.ps1:57-60`). Bundled sha256 = `3a617b73ea35...a9ce`. Current live `openclaw.ai/install.sh` sha256 = `b8ba3a2d75c27a703de1b335f2a296304e933cbbebd006f83e4c0440498cbc0b`, 150,461 bytes, fetched 2026-09-19T15:21:37Z (`Last-Modified: Sat, 19 Sep 2026 09:27:10 GMT`). **They differ, and it does not matter**, because nothing compares them. The pinned bytes are fully recoverable: they are `resources/openclaw-install.sh` in the repo. | see §2 |
| 0.4 script consumption | Quoted above. Unset -> `openclaw@latest`. | item 3 above |
| 0.5 version string per box | **One box recorded it: `cfv-191`, `2026.4.27`** (above). **No v1.4.5 validation close-out records it.** `2026-08-30_v145_validation_closeout.md` contains no version string and no `installShHash`. The string exists only in a retained raw transcript that a close-out author did not read for it. **That absence is a finding** (§9, D-3). | `grep -n "2026\.4\.27"` over the v1.4.5 close-outs: no hits; hits only in `validation/diag/` |
| 0.6 operator card | §1.3 below | |
| 0.7 verdict | `PINNED 1.x, FRESH INSTALLS SAFE` | this section |

**Live-fetch vs bundle decides which verdicts are possible.** Because the script is bundled, the
verdict `SCRIPT PIN MISMATCH, FRESH INSTALLS FAIL AT STEP 8` is **impossible by construction** at
`v1.4.5`. There is no hash check that an upstream edit could trip. That failure class was removed in
v1.0.20/v1.0.31, which the prompt did not know.

### 1.2 What "SAFE" does and does not cover

SAFE covers: *which OpenClaw package version a fresh v1.4.5 install lands.* It does not cover, and this
census did not measure:

- whether a fresh install **today (2026-09-19)** still completes end to end. The only measurement is
  2026-08-31. A box measurement on 2026-09-19 would settle it; it is carded as B-1 in §9.
- other **live fetches Step 8 still makes** and that float: NodeSource `setup_${NODE_DEFAULT_MAJOR}.x`
  (`openclaw-install.sh:1620`, 1631, 1642), and the gateway pre-install's caret-ranged npm deps
  (`commander@^14.0.3`, `express@^5.2.1`, `ws@^8.20.0` in `Step-PreinstallGatewayRuntime`). Those
  move within their ranges; none is OpenClaw 2.0.

### 1.3 Operator card 0.6 (for the external tester's box)

Plain-text card, one command per fence, nothing else inside a fence.

**DO THIS**

1. Print the installed OpenClaw version.

```
wsl -d Ubuntu -u clawuser -- openclaw --version
```

You should see one line whose version token is exactly `2026.4.27`. The line is a banner of the
shape `OpenClaw <version> (<commit>)` (source: `src/cli/banner.ts:47-55` at upstream `v2026.4.27`);
a commit label after the version, or the word `unknown` in its place, is **not** a difference.
Compare the version token only.

2. Print the gateway status.

```
wsl -d Ubuntu -u clawuser -- openclaw status
```

There is **no literal string to compare** here: no captured `openclaw status` output exists in this
repo, so quoting one would be invention. Send back the first 25 lines exactly as printed. The command
name is unchanged in 2.0 (`docs/cli/status.md` at `v2026.8.2`, DOCS-ONLY; flags differ, plain
`openclaw status` remains).

3. Print the Step 8 lines from the install log. The log path is the one `setup.ps1` prints on its own
   failure path (`setup.ps1:2239`: `C:\ProgramData\ClawFactory\install.log`).

```
Select-String -Path 'C:\ProgramData\ClawFactory\install.log' -Pattern 'Requested version','installed successfully' | ForEach-Object { $_.Line }
```

You should see exactly two lines. They carry colour-code residue and possibly garbled emoji, which
are the installer's own and are not a difference. Compare only these substrings:
`Requested version:` followed by `2026.4.27`, and `OpenClaw installed successfully (2026.4.27)!`.

**Which case you are in**

| Command 1 shows | Meaning | What to send back |
|---|---|---|
| version token `2026.4.27` | the 1.x pin held (the expected case) | just say "matches" |
| `2026.8.1` or `2026.8.2` | 2.0 landed unvalidated: **priority 1** | commands 1, 2 and 3 output, all of it |
| `2026.9.x` | a build newer than this census anticipated: also priority 1 | same |
| anything else, or an error | neither | commands 1, 2, 3 output plus `wsl -l -v` output |

If command 3 prints nothing, the install ran from an older ClawFactory that logged differently; send
back the file's first 40 lines and its size.

### 1.4 Contradictions with the prompt found in Task 0

| # | Prompt says | Repo / upstream shows |
|---|---|---|
| C-1 | `$OpenClawInstallSha256` at tag `v1.4.5`; install.sh "fetched live" | Neither. Bundled, no pin. Hash-pin removed v1.0.31. |
| C-2 | Third verdict (`SCRIPT PIN MISMATCH`) is a live possibility | Impossible by construction (see 1.1). |
| C-3 | v1.4.5 shipped 2026-09-01 | GitHub release `publishedAt` = **2026-08-31T16:05:53Z** (`gh release view v1.4.5`). |
| C-4 | "six days" since 2.0; 2.0 = `2026.8.1`/`8.2` | Run date is **2026-09-19**, 19 days after. Upstream `latest` is now **`2026.9.5`**; five more releases (`9.1`-`9.5`) exist. `8.2` is not "current 2.0". |
| C-5 | `SPEC_OpenClaw2_Delta_Census_2026-09-02.md` may be on disk | **Not on disk** (`ls SPEC_OpenClaw2*` empty). No divergence report is possible. |
| C-6 | (comment in `setup.ps1:71-74`) `install.sh:1012`, `:2342`, `:2354` | Bundled script has them at `1004`, `2343-2357`, `2365`. Stale line references in the audit trail. Harmless, but the comments are the audit trail. |
| C-7 | (`SUPPORT_MATRIX.md:30` at the tag) "`setup.ps1` line 26: `$OpenClawInstallSha256 = ...` ... `curl`s `openclaw.ai/install.sh` ... exits 43 on mismatch" | **False at `v1.4.5`.** A stale shipped-doc claim that describes a mechanism removed in v1.0.31. Card it (§9, D-1). |

---

## PREAMBLE APPLICATION (required by the prompt)

The authoritative text is `docs/VALIDATION_PREAMBLE.md` (block at lines 48-372, plus the "earned"
clauses at 393-496 and 503-616, at HEAD `590022ae9c42`). It was read in full. It is **not reproduced
verbatim here**: it is 325 lines of boilerplate already committed in one place, and reprinting it into
each close-out would create a second copy that can drift. That is a departure from "paste the full
block"; it is stated rather than hidden.

**Deleted, and why (no box is provisioned in this job):** ENVIRONMENT, NOT NEGOTIABLE (D2s_v4, image,
resource group, `az vm run-command`, RDP, `/var/tmp`); the admin-password clause; the provisioning
handoff card and Card 2 (before every reboot); the phase-runner clause; SHELL AND EXIT CODES for
probes run on a box; A BASELINE IMAGE IS A SET OF INSTALL STEPS; RESOURCE LEDGER Task 0 (VM sweep),
licence-slot release, and expected residual; VERSION AND BUILD (no build, no ledger row); the
2026-09-01 harness clauses (liveness, run-command truncation, shared path, auto-logon).

**Kept and applied:** close-out-is-a-gate; comprehension; "if this prompt is wrong, say so"; the
CARD FORMAT hard rule (used in §1.3); MEASUREMENT DISCIPLINE's calibration clause; AN AUDIT REGEX IS
ITSELF A PROBE; CREDENTIAL HYGIENE; GIT; the python/Dispatch clause; earned clause 1 (expectation vs
measurement), 2 (calibration), **3 (chat does not assert from memory; a citation proves the
sentence's provenance, not the artefact's, and a bundled file is not its upstream original)**, 4 (a
card carries the evidence that could change the instruction).

**Not deleted, deferred:** dependency census, failure-mode walk and input-shape sweep apply to the
follow-on prompts this census produces, not to this one. They are recorded as owed in §9.

**Comprehension check.** This job changes exactly two repo files: this close-out and
`docs/reference/OPENCLAW2_DELTA_CENSUS_2026-09-19.md`. Nothing depends on either. Verified against the
repo, not the prompt: neither path exists yet; `docs/reference/` and `docs/session_reports/` exist.

**Dispatch invocation reused:** `docs/session_reports/2026-08-31_systemd_reboot_persistence_closeout.md:944-946`
("created via `POST {DISPATCH_URL}/api/agent/update` from PowerShell with the `x-frontier-secret`
header ... the `description` was supplied in the `create` call"). Credentials from
the Dispatch `.env` in the operator's FrontierAI checkout (path omitted), never printed. Card #332 created and re-read from `GET /api/cards`
(`status=in_progress`, `comments=0`).

---

## 2. Upstream state measured (the next OpenClaw release will follow this census)

| Item | Value |
|---|---|
| npm registry fetch | 2026-09-19T15:21:51Z; dist-tags `latest=2026.9.5`, `beta=2026.9.5`, `extended-stable=2026.6.35`; 257 versions |
| `2026.4.27` | npm time 2026-04-29T22:28:04Z; tag `v2026.4.27` -> commit `cbc2ba0931468259f26a7c547131a06e03ca6c6c` |
| `2026.8.1` | npm time 2026-08-31T02:45:39Z; commit `ea806575e6450e4d1efdfc72c19f04be982a1b9b`; `engines.node >=22.22.3 <23 \|\| >=24.15.0 <25 \|\| >=25.9.0` |
| `2026.8.2` | npm time 2026-09-01T16:19:50Z; commit `0965053fe6b9341776df147a6934b7485c60b5ca`; same engines. **Primary 2.0 measurement tag.** |
| `2026.9.5` | npm time 2026-09-19T01:14:57Z; commit `ec9c1a13db8938e5a3eaa51fca2e981cde2395a9` |
| `install.sh` (live) | fetched 2026-09-19T15:21:37Z from `https://openclaw.ai/install.sh`; sha256 `b8ba3a2d75c27a703de1b335f2a296304e933cbbebd006f83e4c0440498cbc0b`; 150,461 bytes; **byte-identical to `v2026.9.5:scripts/install.sh`** |
| `scripts/install.sh` per tag | `4.27` = 88,796 B (`ae7a1c90...`); `8.1` = 137,740 B (`864bd51b...`); `8.2` = 140,635 B (`29542688...`); `9.5` = 150,461 B (`b8ba3a2d...`) |
| **Bundled `openclaw-install.sh`** | 93,387 B, `3a617b73...`. **Matches NO upstream tag.** It is a mid-May-2026 site snapshot (`setup.ps1:57-60`: "changed twice in 24 hours on 2026-05-09/10"), not the `4.27` tag's script. |
| Docs | read from the `docs/` directory of each tag (docs-at-tag). No `docs.openclaw.ai` page was fetched. Anything resting only on `docs/` prose is marked `DOCS-ONLY`. |

**Clause-3 consequence.** Anything in this census said about "what `install.sh` does" is said about the
bundled script (what a user runs) unless it names a tag. Upstream `scripts/install.sh` at `v2026.4.27`
is **not** what ships.

---

## 3. Task 1 — egress delta (DONE, source-derived; measured half is NEEDS BOX)

Full enumeration (Task 1.1, 25 destinations) and the calibration write-up are in
`docs/reference/OPENCLAW2_DELTA_CENSUS_2026-09-19.md`. The answers the gate asks for are here.

**Headline.** Guard 3 counts **22 hostnames** for a default install (base 9, provider 1, aux 5, toolchain 8,
one overlap), re-derived from the tree at `v1.4.5`. 2.0 adds **two** destinations that matter:
`catalog.openclaw.ai` (structurally **denied**, fail-soft) and `telemetry.openclaw.ai` (**allowed by
address**, because it shares three Cloudflare addresses with the allowed `docs.openclaw.ai`, so Guard 3
**cannot** deny it by name). That is address-scoping residual #2, next to the known `clawhub.ai` one.
The **pinned 4.27 already has an unmeasured startup caller**: a pricing bootstrap to `openrouter.ai`
(denied) and `raw.githubusercontent.com` (allowed) that no one has ever drop-logged.

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

## 4. Task 2 — callers outside the chat path (DONE; every cell filled)

**How to read.** Structural = a root-owned or kernel-enforced mechanism stops the agent re-enabling it.
Every key is in `clawuser`-writable `openclaw.json`; the gateway's systemd drop-in directory is chowned to
`clawuser` (`setup.ps1:2474,2486-2491`), so the env switches are advisory too. No managed config layer exists
upstream at 8.2. The gate runs at exactly two entries: `POST /v1/chat/completions` at the proxy
(`clawfactory-proxy.js:1-30`) and the `openclaw agent` shim (`clawfactory-turn-gate.sh:1-8`).

| # | Caller | Default @2.0 (@4.27) | Disabling key | Structural or advisory | Provider path | Guard 2 can gate? |
|---|---|---|---|---|---|---|
| 1 | Grounded dreaming (rewrites `MEMORY.md`) | **ON**, cron `0 3 * * *` (OFF) | `plugins.entries.memory-core.config.dreaming.enabled=false` (DOCS path) | **ADVISORY** | **Around** the route and the shim: in-process `dispatchGatewayMethodInProcess("agent", …)` (`src/gateway/server-plugins.ts:305`; `dreaming-consolidation.ts:600`). Turn gate never runs | No |
| 2 | Per-turn experience review (self-learning) | **ON**, `mode: "auto"` (OFF) | `skills.workshop.autonomous.mode` | **ADVISORY** | **Around**: queued after a run when idle, `runEmbeddedAgent` in-process (`experience-review.ts:446`) | No |
| 3 | Skill collection review | **ON** with #2, every **7 days** in code ("daily" in help text) | same key | **ADVISORY** | **Around**: cron invokes the runner directly (`collection-review.ts:89`) | No |
| 4 | Skill auto-apply | **ON**, `approvalPolicy: "auto"` | `skills.workshop.approvalPolicy: "pending"` | **ADVISORY**; no network, changes the agent's **instructions**. SOUL pin does not cover skill files | n/a (workspace file write) | No |
| 5 | Skill history scan | manual | n/a | n/a | in-process `runEmbeddedAgent` | No |
| 6 | Live provider model discovery | **ON with key** for Anthropic, OpenAI (new); xAI/Google none found | **none found** | **UNMEASURED** for a switch; harmless in kind: provider's own host, metadata only | gateway's own HTTP fetch with the API key; not a chat turn, not via :8787 | No |
| 7 | Hosted catalog + pricing refresh | **ON**, start + 6 h (4.27: pricing bootstrap ON) | `models.catalogRefresh.enabled=false` (4.27: `models.pricing.enabled=false`) | **ADVISORY** as a switch; the **traffic** to `catalog.openclaw.ai`/`openrouter.ai` is **STRUCTURALLY denied** | no LLM | No |
| 8 | Update check / statistics | update check ON (both); `update.auto.enabled` default **false** (both); statistics off | `update.checkOnStart=false`; `OPENCLAW_NO_AUTO_UPDATE`; `telemetry.enabled`; `DO_NOT_TRACK` | **ADVISORY** | no LLM | No |
| 9 | Plugin trust review / capability consent / ClawHub review downloads | not automatic; on `plugins install` / `skills install` | consent flag `--accept-capabilities` | **ADVISORY, effectively none**: the gate is a CLI flag a shell-capable agent can pass itself | agent shell → CLI → `clawhub.ai`/npm | No |
| 10 | Heartbeat | `30m` at **both** tags; 2.0 skips when scratch is effectively empty | `agents.defaults.heartbeat.every: "0m"` | **ADVISORY** | in-process | No |
| 11 | Session observer | ON, only for **subscribed Control UI clients** | `gateway.controlUi.sessionObserver=false` | **ADVISORY** | in-process utility model, around :8787 | No |
| 12 | llama.cpp managed inference | plugin `enabledByDefault`, `onStartup:false`; trigger **UNMEASURED** | do not configure the provider | **ADVISORY**; hosts `github.com` (allowed), `huggingface.co` (denied) | spawns `llama-server`, same uid as the gateway | No |
| 13 | Scheduled DB backups / git snapshots | DOCS-ONLY (`CHANGELOG.md` 8.1) | n/a | **UNMEASURED**, NEEDS BOX | none | No |

**Four conclusions.**
1. **Every new 2.0 LLM caller runs in-process and around the chatCompletions route.** Dreaming, experience
   review, collection review, session observer and heartbeat never enter the SOUL check or the spend cap.
2. **No disabling key is structural today.** The only structural bound on these callers is the nft
   allowlist, and it cannot separate them because each calls the always-open provider host as the same uid.
3. **Whether the meter counts them is unresolved (UNMEASURED, B-5).** The meter counts transcripts by name,
   not by caller; dreaming uses sessions named `dreaming-narrative-consolidation-<hash>` (`dreaming-consolidation.ts:499`).
4. **Skill auto-apply is a new unpinned instruction channel.** It is the row that most changes the SOUL story.

## 5. Task 3 — install-path delta (DONE, source-derived)

**3.1 install.sh.** The prompt's "changes since the pinned hash" is wrong in form: no hash, no live fetch.

| Scenario | Result |
|---|---|
| **(A) Bump only the pin (`$OpenClawNpmVersion`) and keep the bundled script** | **The install step works.** The bundled script honours `OPENCLAW_VERSION` (`:1004`, spec at `:2348-2357` → `openclaw@2026.8.2`). It provisions NodeSource `setup_24.x` (`:19` `NODE_DEFAULT_MAJOR=24`, `:1620`); **measured on `cfv-191`: `Active Node.js: v24.20.0`** (`validation/diag/v146-install.log`). 2.0 engines are `>=22.22.3 <23 \|\| >=24.15.0 <25 \|\| >=25.9.0`, which 24.20 satisfies. The breakage is **downstream** (3.4, 5.1), not in the install step |
| **(B) Replace the bundled script with 8.1, 8.2 or 9.5** | **Step 8 aborts at argument parsing.** `setup.ps1:2345` runs `bash script -- --no-onboard`. The bundled parser's default arm is `*) shift ;;` (`:1122-1124`), so `--` is ignored; the 2.0-era default arm is `*) ui_error "Unknown option: $1"; return 2 ;;` (`v2026.8.2:scripts/install.sh:1519-1522`, spot-checked in this session) under `set -euo pipefail`. Same arm in 8.1 (`:1525`) and 9.5 (`:1572`). **STATIC READ**; a dynamic probe was declined by the permission classifier and not worked around. Fix if ever refreshed: drop the `--` |

- **Node "22.22.2" is stale**: 8.1 notes say 22.22.2, 8.2 source and engines say 22.22.3. Moot: `Step-PreInstallOpenClawDeps` deliberately installs no nodejs and the script provisions 24.
- **`NO_ONBOARD=1` is a dead variable.** Neither the bundled nor the 2.0-era script reads that name; both read `OPENCLAW_NO_ONBOARD` (`:1000`, `:1388`). Only the `--no-onboard` **flag** works (log: `Onboarding: skipped`).
- **"Block unauthenticated network Gateway service installs"** is in the CLI, not install.sh (`src/cli/daemon-cli/install.ts:57-90`, `:277-288`); it fires only on non-loopback bind with `auth.mode == none`. ClawFactory sets `gateway.bind loopback` before `gateway install` (`setup.ps1:2824,2870`), so it does not fire. A second new refusal (sudo-to-root user-service install, `install.ts:173-181`) does not fire because the install runs as `clawuser`. Not dynamically confirmed (B-26).
- **Systemd unit** (`src/daemon/systemd-unit.ts`, 4.27 → 8.2): `TimeoutStopSec` **30 → 330**, new `OOMPolicy=continue`; the rest unchanged. The `--port` shape survives, so `install-chat-proxy.sh`'s `sed` retarget to 8788 still works (`program-args.ts:231` @8.2). The `clawfactory-tunables.conf`-style drop-in still applies. `doctor --fix` (auto-run by install.sh on a **re-run**, `:2834-2898`) vs the `clawfactory-real-port.conf` drop-in is B-9.

**3.2 doctor.** **Premise wrong: `post-install.ps1` has no doctor invocation at v1.4.5** (`resources/post-install.ps1:154-168`, removed; cites openclaw#47133). The only doctor calls in the shipped tree are inside the bundled install.sh (`:2390` `doctor --non-interactive || true`; `:2834-2837` `doctor --fix --non-interactive`). Every flag those calls use still exists at 8.2 (`register.maintenance.ts:48-67`): **none removed**. Runtime prompt count is UNMEASURED; the call-site heuristic is 30 in 18 files @4.27 vs 44 in 27 files @8.2 (not a runtime figure).

**3.3 SQLite.** Does **not** run on gateway start: startup "refuses readiness and prints a `doctor --fix` command" for a legacy store (`docs/cli/doctor.md:331-339`, DOCS-ONLY sentence, backed by `src/agents/auth-profiles/store.ts:1056-1075`). A **fresh** install has no legacy store, so it is unaffected; an **upgrade of an existing 1.x install** needs `doctor --fix` with the gateway stopped. Databases: `<state-dir>/state/openclaw.sqlite` and `~/.openclaw/agents/<id>/agent/openclaw-agent.sqlite`, owner `clawuser`. The uninstaller's `deluser --remove-home` (`uninstall.ps1:522`) removes both without SQLite knowledge. **New hazard:** workspace attestation (`WorkspaceVanishedError`; 15 refs @8.2, 0 @4.27): a partial teardown that deletes the workspace but keeps state throws. Not reachable through the shipped uninstaller.

**3.4 Config shape, item by item.** READ = consumed at runtime; NOT READ = present but never consumed.

| Item written by Step 11 / bootstrap / Step 12 | 4.27 | 2.0 (`8.2`) |
|---|---|---|
| `~/.openclaw/auth-profiles.json` and per-agent copies (`{version:1,profiles:{"<prov>:default":{type:"api_key",provider,key}}}`, mode 600; `setup.ps1:3742-3760`, `:2503-2513`) | READ | **NOT READ at runtime. BREAKS every model call until migrated.** `legacy-source-files.ts:47` "runtime code must never read their contents"; a legacy file with an empty canonical store throws `AuthProfileMigrationRequiredError` ("run doctor --fix", `legacy-source-diagnostic.ts:111-133`). **The importer accepts ClawFactory's exact shape** (`persisted.ts:133-155`) |
| TTY-free alternative | none used | `openclaw models auth paste-api-key --provider <p> --profile-id <p>:default` reads **piped stdin** when not a TTY (`src/commands/models/auth.ts:128-130`). Untested; B-7 |
| `openclaw config set gateway.mode/bind/port` | READ | READ; keys valid under the strict schema |
| `plugins.entries.bonjour.enabled=false` + `OPENCLAW_DISABLE_BONJOUR=1` | READ | READ |
| `tools.deny=["browser"]`, `tools.exec.pathPrepend` | READ | READ (whether it covers the new docked Browser is Task 4: it stays advisory) |
| `gateway.http.endpoints.chatCompletions.enabled=true` | READ | READ; default still off |
| `auth.profiles.<id>` `{provider,mode,displayName}`, `auth.order.<prov>` | READ | READ; shape valid (`zod-schema.root-shape.ts:254-270`) |
| `~/.openclaw/agents/{orchestrator,skill-scout,skill-builder,publisher,main}/agent.md` | **NOT READ** | **NOT READ.** 0 non-test refs to `agent.md` in `src/` or `extensions/` at either tag. **Pre-existing, not a 2.0 delta**, but the persona-per-agent story rests on files OpenClaw has never loaded |
| `~/.openclaw/SOUL.md` (root 444, `chattr +i`) | NOT READ (config root is not the workspace) | NOT READ. It is ClawFactory's pin source only (`/etc/clawfactory/soul.sha256`) |
| `~/.openclaw/workspace/SOUL.md` (frozen root 444; the file the agent actually reads) | READ | **READ**, still in the workspace (`workspace.ts:58-66`). Writers use `flag "wx"` (`:317-331`) so an immutable file is skipped, never overwritten. First-start behaviour with a workspace holding **only** the frozen SOUL, and the BOOTSTRAP.md ritual against an immutable file: B-10 |
| `IDENTITY.md`, `AGENTS.md` | not written by ClawFactory | 2.0 seeds them from templates if missing (`workspace.ts:1053-1075`); **same names**, nothing to break |
| Spend meter `usage-cost --json --days 400` → `.daily[].{date,totalCost}` (`clawfactory-grants.ps1:616-640`) | READ | READ, shape preserved (`session-cost-usage.types.ts:43-59`); **but see Task 4 (stale-cache fail-open)** |

**Calibration ("read and rejected" vs "not read"), SOURCE-DERIVED, no 2.0 process was run.** A malformed key in
`openclaw.json` surfaces as `Invalid config at <configPath>:\n- <path>: <message>` (`src/config/io.invalid-config.ts:22,45`, `INVALID_CONFIG`) or `Unrecognized key: "<k>"` (`validation-issues.ts:373`); startup does **not** auto-repair it and the gateway refuses to start (`pre-bootstrap.ts:486-495`). A rejected auth entry during migration warns `dropped: N, keys: [...]` (`persisted.ts:249-265`). The retired `auth-profiles.json` yields neither: it yields `AuthProfileMigrationRequiredError` naming the DB owner and the doctor command. **The two are distinguishable by message form.** Dynamic confirmation is B-7.

**3.5 Hub and `openclaw-windows-node`.** **Confirmed from source: install.sh does not pull in either** (bundled, `v2026.8.2` and `v2026.9.5` contain no reference to Hub, MSI or winget; the only Windows lines are OS detection and a pointer "For Windows, use: iwr -useb https://openclaw.ai/install.ps1 \| iex", bundled `:260-267`). The Hub is a separate signed installer (`OpenClawCompanion-Setup-x64.exe`, `docs/platforms/windows.md:22-28`, DOCS-ONLY). Hub source read at `openclaw/openclaw-windows-node@3fc8372b` (2026-09-18):

| Item | Fact | Collision? |
|---|---|---|
| WSL distro | Hub provisions its **own** `OpenClawGateway` distro (`SetupContext.cs:16`); ClawFactory is hard-wired to `Ubuntu` (`setup.ps1:78`) | No name clash |
| Global WSL state | Hub touches only its own distro. ClawFactory edits global `%USERPROFILE%\.wslconfig` (`vmIdleTimeout=-1`) and calls `wsl --shutdown` (ClawChat `restart_wsl_and_gateway`), **which stops the Hub's distro too** | One-way: ClawFactory can stop the Hub's gateway |
| Ports | Hub `18789`; ClawFactory proxy 8787, real gateway 8788 | None by default |
| Install method in its distro | `openclaw.ai/install-cli.sh` (`GatewayInstallPolicy.cs:147`), a **different script** from `install.sh`, not pinned by ClawFactory | n/a |
| Second `openclaw` on PATH | No PATH mutation found in Hub source. ClawFactory always calls `wsl -d Ubuntu -u clawuser -- openclaw` | Not shown; which `openclaw` a bare Windows shell resolves: UNMEASURED |
| Config paths | disjoint (`%USERPROFILE%\.openclaw` vs `/home/clawuser/.openclaw`) | No |
| **Node pairing to ClawFactory's gateway** | If a user points the Hub at `127.0.0.1:8787`, the proxy relays the WebSocket **verbatim and ungated** (`clawfactory-proxy.js:150-160`), and a paired Windows node gives the agent Windows-side capabilities that Guard 1 exists to withhold | **Hazard**, not a config clash (B-14) |
| **Shared netns / uid rules** | All WSL2 distros share one utility VM and network namespace. nft rules match `meta skuid != clawuser return` (`setup.ps1:1971`), resolved by name at load time. Effect on another distro's processes: UNMEASURED | B-14 |

## 6. Task 4 — guard assumption walk (DONE, source-derived)

Upstream read at `v2026.8.2`; ClawFactory at `v1.4.5` (the files quoted are byte-identical at `HEAD` except
`setup.ps1` and three `install-*.sh`, which differ by `is-enabled` read-backs only). Ceiling on every
"config key" row: the agent, the gateway and every child are one uid, and Door 2 is closed-for-v1 and **was
not re-litigated**.

| # | Control | v1.4.5 | Does 2.0 change the assumption? | 2.0 value |
|---|---|---|---|---|
| 1 | Guard 1 core: `[automount] enabled=false`, `[interop] enabled=false`, per-folder grants (`setup.ps1:1611-1618`, read back at `:1573-1603`) | STRUCTURAL | No | **STRUCTURAL** |
| 1a | The unstated second half: "the agent's tools execute in this distro" (paired devices, cloud workers, workspace moves) | implicit | **Yes**: 2.0 can place a session on another machine and move its workspace | **ADVISORY** (absent by default, not enforced; a same-uid agent can approve its own loopback pairing) |
| 1b | Docked Browser panel | ADVISORY (`tools.deny=["browser"]`) | UI over the same tool; nothing new inside the cage | **ADVISORY**; reach bounded by Guard 3 |
| 1c | Windows node System tools | n/a | outside the boundary if a Hub/node is installed | **UNMEASURED** (B-14) |
| 1d | Managed-worktree copies of granted content | n/a | copy lands under `~/.openclaw/worktrees`, so **Revoke and the kill switch's unmount do not remove it** | **UNMEASURED**, DOCS-ONLY (B-18) |
| 2 | Guard 2 SMTP path (root broker, payload-hash binding, SMTP drop) | STRUCTURAL | No | **STRUCTURAL** |
| 2a | 2.0 inline exec approvals, "approve recurring work once" | n/a | A complement, **not a collision**: the grant is upstream of the broker and grants nothing it honours. Stored in `clawuser`-owned SQLite | **ADVISORY** |
| 3 | Guard 3 nft allowlist (`meta skuid != clawuser return`; `oifname "lo" accept`; three `tcp dport 443` accepts; terminal drop, `setup.ps1:1971-2002`) | STRUCTURAL | No | **STRUCTURAL** |
| 3a | Credential store "egress bound to declared hosts" (`secrets.egressProxy`) | n/a | **The prompt's "beneath nftables" is backwards**: it sits **above** nft, is opt-in and default-off, exact-hostname, application-layer, and constrains only where a *substituted secret* may go (`configuration-reference.md:1503-1521`, DOCS-ONLY) | **ADVISORY** |
| 3b | Every 2.0 process is `clawuser` | holds | holds by default. Escapes: rootful Docker sandbox containers, a Windows Hub, or a system-scope service, each needing an operator action | **STRUCTURAL by default** |
| 4 | SOUL pin (root 444 + `chattr +i` + turn-gate hash check) | file STRUCTURAL, enforcement gateway-path | still injected (`workspace.ts:247-254`, `["soul.md", 20]` at `system-prompt.ts:87`); wording weakened; new optional-file and attestation logic; **UNMEASURED at runtime** | **ADVISORY** (same class) |
| 5 | Spend cap | ADVISORY | **Yes, weaker (below)** | **ADVISORY, degraded** |
| 6 | chatCompletions gating proxy | gateway-path | route unchanged; the new turn-starters are not on it | **ADVISORY** as a coverage claim |
| 7 | Kill switch (`clawfactory-stop.ps1`) | an action, not a boundary | drain semantics changed | **UNMEASURED** (B-15) |
| 8 | `switch-provider.ps1` | works (v1.4.4 box A PASS) | **its key write targets a retired file** | **UNMEASURED, predicted BROKEN from source** |
| 9 | `rename-agent.ps1` | inert message box | no | **UNAFFECTED** |
| 10 | Tenth build gate | not built | not affected | n/a |

**Uid question (gate item 6): no 2.0 component runs as a uid other than `clawuser` by default.** The
gateway, node host, worker child, Codex app-server, browser, MCP stdio servers and `secrets.egressProxy`
are all `clawuser`. `llama-server` is an **opt-in plugin** child, same uid; the prompt's "llama-server,
node workers" do not escape the uid-scoped rules. Only three things escape, each needing an operator
action: a rootful Docker sandbox (default `mode: off`, ClawFactory removed Docker at `setup.ps1:1705-1723`;
inferred from the chain shape, **not measured**, B-19), the Windows Hub, or a system-scope service.

**Spend cap, the finding that matters.** The gate's fail-safe covers *unreadable*; 2.0 adds *readable but
not current*. At 8.2 the meter is cache-backed and refreshes in the background
(`src/gateway/server-methods/usage-result-cache.ts:195`, `requestRefresh: true, refreshMode: "background"`,
re-read in this session). The summary carries `cacheStatus.status` in `fresh|partial|stale|refreshing`
(`session-cost-usage.types.ts:52-58`) and **`clawfactory-spend-check.js` reads none of it (0 hits at
`v1.4.5`)**. A cold or stale cache yields a valid `daily` array with low or zero cost; the gate sees
`today ≈ 0` and **allows the turn**. That is a fail-open on the exact condition the gate was built to fail
closed on. At 4.27 the meter was a synchronous transcript scan, so the state did not exist. **Not measured on a
box (B-6).** Also: the meter counts one agent (default) at both versions; `openclaw infer model run`,
`POST /v1/embeddings` and `POST /v1/responses` are unmetered and ungated at **both** versions, and
**`SECURITY_FINDINGS.md` describes Door 2 without naming them.**

**Kill switch.** It (1) `pkill`s `openclaw agent`, (2) runs `openclaw gateway stop` (no timeout), (3) unmounts
every grant, (4) reports a `pgrep` count. At 8.2 `TimeoutStopSec=330` so a running turn may finish for up to
~5 minutes and `gateway stop` may block that long; the **report** stays honest, the **promptness** does not.
`openclaw node run`/`connect --service` is a separate user unit `gateway stop` does not touch. At the tip
`KillMode` changes to `mixed`. Never run against 2.0.

**`switch-provider.ps1`.** It writes the key **value** into `~/.openclaw/auth-profiles.json` and per-agent
copies (`:123-149`), the retired store at 8.2, and prints `[x] key written` (`:149`) while its `$?` on the
python step is only a WARN (`:148`): the silent-fake-success shape. The metadata half (`config set
auth.profiles.*`, `models set`) still works. The prompt's "`openai/*` rename" **does not apply**: ClawFactory
already emits `openai/…` (`switch-provider.ps1:54-56`); upstream's rename is from `codex/*`, so `doctor --fix`
has nothing to migrate. The 2.0 effect on ClawFactory is different: an `openai/*` API-key install on the
official Platform route is **eligible for the bundled Codex app-server runtime** (`docs/providers/openai.md:71-89`,
DOCS-ONLY), a different child binary whose network calls, tool surface and metering are unknown (B-16). The
"three recorded defects" is ambiguous: three separate sets exist (M4/M5/M6 in `v1.1_backlog.md:308-316`; the
v1.3.5 stale-mirror re-seed; the v1.4.3 unescaped `$baseHosts`). None is the one that matters at 2.0.

**Tenth build gate** = `encoding`, spec-only in `docs/V1_5_BACKLOG.md`; `scripts/build_release.ps1:691`
lists nine `gatesPassed`. A pin bump does not need it changed. **No gate ties `$OpenClawNpmVersion` to
anything**, which is why the stale line numbers and the stale `SUPPORT_MATRIX.md:30` survived.

## 7. Task 5 — surface delta (DONE, source-derived)

**5.1 ClawChat.exe.** **HTTP only; no WebSocket.** Source: the local ClawChat checkout, `src-tauri/src/lib.rs`
(Tauri), last commit `3577fae` 2026-05-11.

| Call | Detail |
|---|---|
| `GET http://127.0.0.1:8787/status` | `lib.rs:41-56`, polled every 10 s |
| `POST http://127.0.0.1:8787/v1/chat/completions` | `lib.rs:59-105`; `Authorization: Bearer <token>`, `x-openclaw-agent-id: main`, `stream:true` |
| config read | `wsl.exe … cat /home/clawuser/.openclaw/openclaw.json`; frontend reads a **top-level** `token`, not `gateway.auth.token` (`useGateway.js:16-17`; same in the built bundle). **Pre-existing mismatch**; no measurement that the shipped ClawChat obtains a token from a stock config (B-12) |
| `set_security_tier` | root write to `/etc/wsl.conf`: tier `open` sets **`[automount] enabled=true`** (a Guard 1 concern) and tries to stop `clawfactory-egress.service`, a unit name absent from the uninstaller's list, so that stop is a swallowed no-op |

**Shipped exe vs source.** `resources/ClawChat.exe` at `v1.4.5` (sha256 prefix `596c0825`, 11,702,272 B) contains the strings above; `ws://` and `wss://` are absent; a planted control string was absent. Three command names are not plaintext-visible (compressed frontend), so **the tie is strong, not byte-proven**.

**Did 2.0 change it?** Mostly no. `POST /v1/chat/completions` still exists, still opt-in, still reads `x-openclaw-agent-id`. Three items to verify:
- 2.0 adds a session-mutation authorization step (`http-utils.ts:315-336`, `authorizeOpenAiCompatibleHttpSession`). Whether a bearer gateway token still passes as owner: **UNMEASURED (B-12)**.
- **`GET /status` is not a route at either tag.** The probe routes are `/health`, `/healthz`, `/ready`, `/readyz`. `/status` returns 200 only because the Control UI SPA fallback answers unknown GETs with `index.html`. At 8.2 that fallback also returns **503** while assets are "preparing", "failed" or missing (`control-ui.ts:199-219`). ClawChat's ping, `install-chat-proxy.sh`'s health wait and setup's 30 s poll all depend on this accident. `/healthz`/`/readyz` exist at both tags (B-11).
- Model string: ClawChat sends the config's `model` (default `claude-sonnet-4-6`), probes send `openclaw/main`. Whether 2.0 treats them differently: UNMEASURED.

**5.2 Studio's four working panels.** Files, Deleted, Send, Web. They call **root-owned ClawFactory tools** (`clawfactory-grants.ps1`, `quarantinectl`, `sendctl`, `fetchctl`) and read **neither `openclaw.json`, `auth-profiles.json`, nor any gateway endpoint**. Their only OpenClaw dependencies are the spend meter (shape and scope preserved, stale-cache caveat) and the SOUL paths (unchanged). The pages that would need a Studio `/api/*` backend render `NotInThisRelease`; that backend's source is not tracked. Studio 1.3.2 = `.iss` `StudioInstaller` 1.3.2.

**5.3 `#311` (facts only; D5/D6 are not mine).** The Start Menu `ClawFactory Dashboard` runs `cmd /c start http://127.0.0.1:8787`; the recorded reason it is a dead end is device-pairing gating with no shipped pairing flow. At 2.0: the root-mounted SPA is unchanged; gateway auth runs before pairing, so the first connection needs the token pasted in (which ClawFactory never shows a user); **loopback pairing auto-approval exists at both versions**, with 2.0 adding conditions (after auth, browser device identity, **no forwarded/proxy headers**), and the proxy relays the upgrade verbatim adding none (`clawfactory-proxy.js:163-168`). So a browser through 8787 **plausibly can pair once given the token**: "dead end" is **unmeasured, not established** (B-13). The 2.0 UI is chat-first (Home, `/new`, Threads, "Ask OpenClaw"), and that chat is WebSocket RPC, **outside** the `POST /v1/chat/completions` spend-cap and SOUL gate; at 4.27 that path existed but was basic web chat, and 2.0 makes it the front door at the address the shortcut opens. Studio's chat page is `NotInThisRelease`; ClawChat provides gated chat. Whether that makes the Studio-chat question moot is not stated here.

## 8. Tasks 6 and 7 — threat-model inputs, comparison skeleton

(The same two tables are written to `docs/reference/OPENCLAW2_DELTA_CENSUS_2026-09-19.md`.)

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

## 9. NEEDS BOX and candidate cards

**Candidate cards for the follow-on validation job (`NEEDS BOX`).** Each needs a positive control and a
control that must fail in the same run, per the calibration clause.

| ID | Question | Source |
|---|---|---|
| B-1 | Does a fresh v1.4.5 install **today (2026-09-19)** still complete end to end at the pin? Only measurement is 2026-08-31 | Task 0 |
| B-2 | Boot-and-idle **nft drop-log at the pinned 4.27**: record `openrouter.ai`, `raw.githubusercontent.com`, anything else at start. **Both calibration halves.** Never measured | T1 |
| B-3 | Same on a 2.0 box: `catalog.openclaw.ai` denied, `telemetry.openclaw.ai` allowed by address. Sample the **WSL** resolver several times over hours | T1 |
| B-4 | A real `skills install` with the toggle **off** and the drop-log running: is `api.clawhub.ai` ever hit? | T1 |
| B-5 | Do dreaming, experience review, collection review appear in `gateway usage-cost` for the default agent, and do they cost tokens on an idle install (24 h idle transcript count at 4.27 and 2.0)? Heartbeat and session observer likewise | T2 |
| B-6 | **Spend meter on a cold or stale 2.0 cache: does the gate allow a turn over cap?** Positive control = a turn that provably spends; rigged = an empty-`daily` payload into the same gate | T4 |
| B-7 | **Fresh 2.0 install: does the wired key work, or `AuthProfileMigrationRequiredError`?** After `doctor --fix`, does `switch-provider` take? `printf key \| openclaw models auth paste-api-key` as a replacement. Includes the malformed-key calibration run live | T3, T4 |
| B-8 | Dynamic confirmation that a refreshed install.sh (≥8.1) aborts on `-- --no-onboard` | T3 |
| B-9 | `doctor --fix` (auto-run by install.sh on re-run) vs the `clawfactory-real-port.conf` ExecStart drop-in | T3 |
| B-10 | First start with a workspace holding **only** the frozen `SOUL.md`; the BOOTSTRAP.md ritual against an immutable file | T3 |
| B-11 | `GET /status` during Control UI "preparing" (503 window) vs the health gates; measure `/healthz`/`/readyz` as replacement | T5 |
| B-12 | ClawChat on 2.0: token acquisition (top-level vs `gateway.auth.token`), model string, the owner check | T5 |
| B-13 | Browser dashboard through 8787: pairing auto-approval through the proxy; does Control UI chat bypass the spend cap and SOUL gate | T5 |
| B-14 | Hub pairing to ClawFactory's gateway; a Windows process reaching the loopback proxy (mirrored vs NAT); shared-netns effect on a second distro | T3, T4 |
| B-15 | Kill switch under 2.0 drain: time to stop, pgrep count at 0 s, 30 s, 330 s with a Codex child alive; known-alive control from two independent readers | T4 |
| B-16 | `provider=openai` on 2.0: which harness ran, which hosts it contacted, whether its spend reaches the meter | T4 |
| B-17 | Default agent id, workspace and `--all-agents` enumeration on a config that registers no agents; a non-default agent's workspace is not covered by the SOUL pin | T4 |
| B-18 | Managed-worktree residue after Revoke (canary in a git grant) | T4 |
| B-19 | Rootful Docker in the distro: do container packets escape the `output`-only chain; which firewall backend customers get (nft vs `iptables-legacy`) and the 8788 drop under the latter | T4 |
| B-20 | Grok prefix (`grok/…`) resolution at 2.0 (upstream extension is `xai`) | T4 |
| B-21 | Does a systemd user manager honour a root-owned immutable drop-in for `OPENCLAW_NO_AUTO_UPDATE`? | T2 |
| B-22 | Does the agent's shell reach `plugins install <x> --accept-capabilities` in a real turn (self-consent)? | T2 |
| B-23 | llama.cpp: what triggers the GitHub/Hugging Face download, and under which uid `llama-server` runs | T2 |
| B-24 | Does anything Control-UI-shaped subscribe on a ClawFactory install (session observer)? | T2 |
| B-25 | Runtime doctor prompt count at 2.0 | T3 |
| B-26 | The two new install refusals do not fire under `wsl -u clawuser` | T3 |
| B-27 | **Cross-session visibility** (named in Task 6, not researched in this census) | T6 |
| B-28 | Measure both OpenClaw comparators (unsandboxed, and Docker sandbox on) so the Task 7 middle-state comparison has data | T7 |

**Candidate cards that need no box (docs and code hygiene).**

| ID | Item |
|---|---|
| D-1 | `SUPPORT_MATRIX.md:30` (at the tag) documents `$OpenClawInstallSha256`, a live `curl`, and exit 43 on mismatch. **None exists at v1.4.5.** Whether that file is bundled is not established here |
| D-2 | `setup.ps1:71-74` cites `install.sh:1012 / 2342 / 2354`; the bundled script has them at `1004 / 2343-2357 / 2365` |
| D-3 | **No v1.4.5 validation close-out records the OpenClaw version the box installed.** Add a version assertion to the validation cycle so it is read, not left in a transcript |
| D-4 | `SECURITY_FINDINGS.md` Door 2 text omits `openclaw infer model run`, `POST /v1/embeddings` and `POST /v1/responses` (ungated and unmetered at the pin as well). Decided-closed Door 2 is **not** reopened; the text is incomplete |
| D-5 | A **pin-coherence build gate** tying `$OpenClawNpmVersion` to the bundled script and to the literals in README/`SUPPORT_MATRIX.md`/`V1_5_BACKLOG.md:458,514` (the tenth gate is `encoding`; this would be an eleventh) |
| D-6 | `NO_ONBOARD=1` at `setup.ps1:2345` is a dead variable; only `--no-onboard` acts |
| D-7 | ClawChat `set_security_tier` "open" writes `automount=true` as root; stale unit name `clawfactory-egress.service` |
| D-8 | ClawChat reads a top-level `token`; OpenClaw uses `gateway.auth.token` |
| D-9 | `agent.md` is never read by OpenClaw at either tag (pre-existing); the four "factory agents" exist only as directories plus a file nothing loads |
| D-10 | `setup.ps1` comments and `install-send.sh` say uid 1000/1001; the rules key on the **name** |

## 10. Findings that contradict the prompt or the spec

| # | Prompt / spec says | What the repo or upstream shows |
|---|---|---|
| C-1 to C-7 | see §1.4 (Task 0) | |
| C-8 | Task 1: GHCR is a 2.0 destination | Not reached by the gateway in default config at either tag |
| C-9 | Task 1: 22 routes is untrustworthy | Reproduces for a default install (23 gemini, 24 ollama), but it counts **hostnames**, not routes or addresses |
| C-10 | Task 1: `api.clawhub.ai` is a host 2.0 needs | Appears in **no** upstream tag |
| C-11 | Task 3.1: Node 22.22.2 | Stale; 8.2 says 22.22.3, and ClawFactory installs Node 24 (measured v24.20.0) |
| C-12 | Task 3.1: `--no-onboard` and `NO_ONBOARD=1` are both honoured | Only the flag is; the env var is dead in the bundled and 2.0-era scripts |
| C-13 | Task 3.2: `post-install.ps1`'s non-interactive `doctor` invocation | Does not exist at v1.4.5; removed |
| C-14 | Task 3.4: "the four `agent.md` files" as config OpenClaw reads | OpenClaw has never read that filename |
| C-15 | Task 4: `openai/*` rename | Does not apply: ClawFactory already emits `openai/`; upstream renames from `codex/*` |
| C-16 | Task 4: credential-store egress binding is "beneath nftables" | It sits above it, opt-in, application-layer |
| C-17 | Task 4: `switch-provider.ps1` has "three recorded defects" | Three separate defect sets; none is the one that matters at 2.0 |
| C-18 | Task 5.1: gateway WebSocket or HTTP API | HTTP only |
| C-19 | Task 5.2: the panels read config files and gateway endpoints | They read neither; they shell to root-owned tools |
| C-20 | "2.0 is `2026.8.1`/`8.2`" | Upstream is at `2026.9.5`; a "2.0 pin bump" is a choice among seven releases |
| C-21 | The prompt's Task 4 does not anticipate a **stale-meter fail-open** | New failure class found (§6) |
| C-22 | Skill collection review "daily" | "daily" in the help text, `7 * 24 * 60 * 60_000` in code (`skill-collection-review-monitor.ts:60-63`) |

## 11. Recommendations

**The census's main conclusion: do not bump the pin on this evidence.** Today's install lands `2026.4.27`
inside all three guards. A bump is not a one-line change: it breaks key wiring and weakens the spend cap
until measured.

**Fold into the next prompt.**
- **v1.5 (or a dedicated 2.0-readiness prompt), only if a pin bump is being considered at all:** (a) the spend gate reads `cacheStatus` and treats anything but `fresh` as unknown, version-aware for the pin; (b) the key write moves off the retired file (Step 12 and `switch-provider.ps1`), probably to `models auth paste-api-key` over piped stdin; (c) health gates move from `/status` to `/healthz`/`/readyz`; (d) a kill-switch timeout and drain note. Without (a) and (b) a bump regresses two controls that are green today.
- **v1.5:** the pin-coherence gate (D-5); Door 2 residual text (D-4); credential-protection measurement re-based on a SQLite row; `iptables-legacy` parity for the 8788 drop.
- **v1.4.6 hotfix:** **nothing in this census requires one.** The pinned install is safe and inside the guards. D-1 and D-2 are doc/comment fixes that can ride any release; whether D-1 needs a release depends on whether `SUPPORT_MATRIX.md` is bundled (not established).
- **`#259` (unattended harness):** B-1 through B-28 batch naturally into cycles; the persistent-auto-logon follow-on unblocks the WSL-side ones.

**Dispatch cards.** B-1 to B-28 and D-1 to D-10 above.

**Rejected, with reason.**
- Patching Door 2: decided closed for v1 and not re-litigated.
- Treating 2.0's exec approvals or `secrets.egressProxy` as a ClawFactory control: both live in `clawuser`-owned state, so they can only ever be ADVISORY.
- Writing any Task 7 cell as site copy now: none reads `MEASURED` for an OpenClaw column.
- Setting `models.catalogRefresh.enabled=false` as the control for `catalog.openclaw.ai`: the control is the nft denial; the key is noise reduction.

## 12. END-OF-SESSION GATE

### 12.1 Task accounting

| Task | Status | Evidence / note |
|---|---|---|
| 0.1 - 0.5, 0.7 | **DONE** | §1, §1.1. Verdict `PINNED 1.x, FRESH INSTALLS SAFE` |
| 0.6 operator card | **DONE** (printed, not needed: verdict is not priority 1) | §1.3 |
| 1.1 - 1.4 | **DONE, source-derived.** Measured half is **BLOCKED on a box** | §3, reference file; B-2, B-3, B-4 |
| 2 | **DONE**, every cell filled | §4; B-5, B-21, B-22, B-23, B-24 |
| 3.1 - 3.5 | **DONE, source-derived.** 3.1(B) dynamic probe **declined by the permission classifier and not worked around** | §5; B-8, B-9, B-10, B-25, B-26 |
| 3.4 calibration | **DONE from source**, no live loader run | §5 |
| 4 | **DONE**, source-derived | §6; B-6, B-15 to B-20 |
| 5.1 - 5.3 | **DONE**, source-derived | §7; B-11, B-12, B-13 |
| 6 | **DONE**, except row 6 **cross-session visibility = UNMEASURED, not researched** | §8, reference file; B-27 |
| 7 | **DONE as a skeleton**; every OpenClaw cell `UNMEASURED` | §8; B-28 |
| 8 close-out | **DONE** (this file), committed with the reference file | §12.5 |
| Dispatch card | Created (#332) and re-read. **Comment bodies cannot be read** (the API returns a count only), so "read its comments at each task boundary" was done as a **count** at start (0) and after Task 0 (1, my own); no comment from anyone else was seen or could be | §12.2 |
| Dependency census, failure-mode walk, input-shape sweep | **DEFERRED** by the prompt to the follow-on prompts this census produces | preamble note |

No task silently dropped.

### 12.2 Resource ledger

- **Upstream fetches:** `https://openclaw.ai/install.sh` (1, 2026-09-19T15:21:37Z); `https://registry.npmjs.org/openclaw` (1 packument, 15:21:51Z); `git ls-remote` and depth-1 fetches of `github.com/openclaw/openclaw` at `v2026.4.27`, `v2026.8.1`, `v2026.8.2`, `v2026.9.5`; one `gh api` release lookup; `gh release view v1.4.5`. Researchers additionally read `openclaw/openclaw-windows-node@3fc8372b`, NodeSource `Packages.gz` (2026-09-19T15:28Z) and did DNS lookups from this Windows machine (not WSL's resolver).
- **Dispatch API:** 1 `create`, 1 `add_comment` before close-out, plus the closing writes recorded in §12.5. Reads of `GET /api/cards`.
- **Spend:** none. **No VM was provisioned.** No installer, Hub or `openclaw-windows-node` was run or installed on this machine. No `doctor --fix` on any box.
- **Files written in the repo:** exactly two, this close-out and `docs/reference/OPENCLAW2_DELTA_CENSUS_2026-09-19.md`. Scratch (clones, scripts, working notes) lived in the session scratchpad, outside the repo.
- Untracked `CC_CENSUS_OpenClaw2Delta_v1.md` (the job prompt) and 13 modified `validation/diag/cfv-192-harnessproof-*` files were already in the working tree at session start; they are **not staged**.

### 12.3 Delta security sweep (on this file and the reference file)

Scan: `grep -E` for key shapes (`sk-`, `AIza`, `gh[pousr]_`, `xox`, `AKIA`, `Bearer …`, `password|secret|token|api_key` assignments), e-mail addresses, the operator's username, absolute operator paths and the Dispatch secret name. **Calibration in the same invocation:** a planted canary line (a key-shaped string plus an address) returned rc 0 with a hit; a clean control line returned rc 1 with none. The first real run found **two** operator-path leaks (a local repo path and the Dispatch `.env` path) and a first name in the operator-card heading; all three were removed and the scan re-run to **0 hits on both files**. Hostnames quoted are public product hosts; none is credential-bearing. Every key, token and password in the sources read was left unquoted (the auth-profiles shape is quoted as a schema, not a value). Box name `cfv-191` is a disposable validation VM already named across the repo.

### 12.4 Delta bug review (candidate cards only, none acted on)

Defects in **this census's own instruments**, so the next reader can weigh the evidence:
- **Everything OpenClaw-side is a source read.** No 2.0 process ran. The two headline findings (retired `auth-profiles.json`, stale-meter fail-open) were each spot-checked against the tag in this session, but neither has been observed to fail. B-6 and B-7 turn them into measurements.
- **DNS-overlap results came from this machine's resolver**, three lookups each, against rotating Cloudflare and GitHub sets. The two "structural denial" claims (`catalog.openclaw.ai`, `download.db-ip.com`) and the one "allowed by address" claim (`telemetry.openclaw.ai`) are evidence, not proof.
- **The enumeration is blind to constructed hostnames** (Task 1.4). `api.clawhub.ai` "in no upstream tag" means no literal reference.
- **`SUPPORT_MATRIX.md` and the `setup.ps1` pin comment are audit-trail defects** (D-1, D-2), found because nothing ties the pin to anything (D-5).
- **The "14.5 hours" figure** in §1 rests on the journal's `+00:00` stamps and the install log's timestamps being the same clock. The log is not stamped with a zone; the equivalence is inferred from consistency with the release publication time. Minor.
- **Task 0 verdict scope:** SAFE is about which package lands. It does not cover whether a fresh install still completes today (B-1).

### 12.5 Commit and Dispatch

Recorded in the final message of the session; the commit hash cannot be written into a file that the commit contains.
