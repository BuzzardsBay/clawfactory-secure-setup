# Azure clean-install validation — STAGED, NOT RUN (2026-07-15)

**Job:** `CC_CLAWFACTORY_AZURE_CLEAN_VALIDATION_v1`.
**Status: the validation did NOT run. No VM was provisioned. Nothing billed.**
Two operator decisions reshaped the session (both recorded below), and the
staging step then found an install-breaking bug that would have made the entire
Azure run fail at step 15b.

---

## 1. THE HEADLINE — still unanswered, and that is the honest top line

> **Can the agent see ungranted files on a correct install? STILL UNKNOWN.**

No VM was provisioned, so `automount=false` was never exercised and the headline
claim remains **unproven on a correct install**, exactly as it was before this
session. Nothing here changes that. It is still the #1 thing this project owes
itself, and it is now fully staged to be answered in one push-button run.

**What DID change:** the validation would have failed on arrival. See §2.

---

## 2. THE FINDING — a fresh install was broken, and the installer shipped none of the security work

**Found by the staging preflight, before a VM existed, for $0.**

`setup.ps1` gained three steps across the security track —
`Step-InstallTurnGate`, `Step-FreezeInjectedSoul`, `Step-InstallChatProxy` —
each reading resource files from `{app}\resources`. **The matching `.iss [Files]`
entries were never added.** Verbatim diff of "what setup.ps1 loads" vs "what the
installer ships":

```
  ** MISSING ** clawfactory-proxy.js          ** MISSING ** install-chat-proxy.sh
  ** MISSING ** clawfactory-proxy.service     ** MISSING ** install-turn-gate.sh
  ** MISSING ** clawfactory-spend-check.js    ** MISSING ** openclaw-shim.sh
  ** MISSING ** clawfactory-turn-gate.sh      ** MISSING ** freeze-injected-soul.sh
  BUNDLED       safety-rules.md
```

**Consequence on a fresh machine:** `Step-InstallTurnGate` throws
`FileNotFoundException` inside `Invoke-WithRollback` → **the install aborts**, and
every control built in the last four jobs — the turn gate, the SOUL enforcement,
the chatCompletions proxy — is **absent**. The product would have installed
nothing that this entire security track produced.

**Why Bret's box never caught it:** every one of those steps was applied to the
live box *directly* (by me, via WSL), never *through the installer*. The installer
path had no coverage. That is the same producer-vs-consumer failure this project
keeps finding, one layer out: the code was right, the packaging was not, and only a
machine built by the installer would have noticed.

**Fixed:**
- 8 `[Files]` entries added; ISCC's compile log now shows each one being
  compressed in (verbatim in §4).
- **Guard so it cannot recur silently:** `Step-Preflight` now asserts every
  required resource is present and refuses to install otherwise, naming the
  missing files — fail fast and loud, before anything on the machine changes,
  instead of aborting mid-install with a bare exception and no controls.

---

## 3. Operator decisions that shaped the session

1. **Keyless validation.** No provider key goes on the VM. The headline is proven
   *model-independently*: with `automount=false`, `/mnt/c` is not mounted, so
   nothing in the VM can read it — the agent included. Asking a model to try is
   strictly weaker evidence than showing the mount does not exist. Only the
   agent's *narration* and the agent-result cold-start need a key; both are
   flagged NEEDS-KEY, never reported as PASS.
2. **Stage now, run the VM next session.** The realistic run is multi-hour
   (build → sign → upload 325 MB → provision → auto-logon install → suite →
   teardown) against a harness with a documented history of wedging. Starting it
   with limited runway risks the one failure this job explicitly forbids: a
   forgotten VM billing indefinitely. So the deterministic prerequisites were done
   now, with **zero** VM provisioned.

---

## 4. What is staged (all verified)

**Build — v1.0.38, from HEAD (`4ff70a3`).** There was no build to validate: the
only installer on disk was dated **Jul 6**, predating the entire security track,
and HEAD was 14 commits past the last tag (`v1.0.37-14-g7655c27`).

```
ISCC compile log (proof the bundling fix works):
   Compressing: resources\openclaw-shim.sh
   Compressing: resources\clawfactory-turn-gate.sh
   Compressing: resources\clawfactory-spend-check.js
   Compressing: resources\install-turn-gate.sh
   Compressing: resources\freeze-injected-soul.sh
   Compressing: resources\clawfactory-proxy.js
   Compressing: resources\clawfactory-proxy.service
   Compressing: resources\install-chat-proxy.sh
Successful compile (48.813 sec).

needed-vs-bundled diff: missing=0
every [Files] Source: entry resolves on disk: yes
signature: Status=Valid (Azure Artifact Signing, CN=Bret Mckinney)
sha256: bd76a4ada7a5ae0641e520df11b58f445ec5b4abe371506452c3b0a591b064f3
bytes:  340587592
tag:    v1.0.38
```

**Staged to Azure:** blob `installers/ClawFactory-Secure-Setup-v1.0.38.exe`,
`bytes: 340587592` — an exact byte-match with the local artifact. The harness
re-verifies the sha256 **on the VM** before installing.

**Harness — `scripts/azure-validate.ps1` + `scripts/azure-probe.ps1`** (new,
reusable, parses clean; preflight dry-run green). It encodes every trap the
lineage paid for:
- `az vm run-command` is **always** `NT AUTHORITY\SYSTEM`, and **WSL refuses to
  run as LocalSystem** — so *every* WSL-dependent check must run from a
  clawadmin auto-logon + RunOnce wrapper, never from run-command. The probe
  aborts loudly if it finds itself running as SYSTEM rather than emitting
  meaningless results.
- `--security-type Standard` (Trusted Launch breaks the baseline image).
- `Standard_D2s_v4` (DSv5 quota is 0 in westus2).
- Non-zonal, existing `bake-vmSubnet`, `--nsg-rule NONE` + Standard public IP.
- PowerShell, not Git Bash (MSYS mangles `az /subscriptions/...` paths).
- **Teardown runs in `finally`** — if anything throws, the VM still dies — and it
  writes a `teardown-proof.txt` containing the `az` listings, because a close-out
  that says "torn down" without the listing is not acceptable.

**Preflight dry-run (no provisioning):**
```
subscription state: Enabled        baseline image resolves: True
bake-vmSubnet resolves: True       cfv-138 already exists: False
```

---

## 5. Task accounting

| Task | Status |
|---|---|
| Search prior Azure work / reuse the harness patterns | **DONE** (patterns recovered from the v1.0.15/v1.0.37 lineage; encoded in a reusable script rather than left in prose) |
| Build with the security changes | **DONE** — v1.0.38, signed, hashed, tagged |
| Stage to storage | **DONE** — byte-match verified |
| Write the reusable harness | **DONE** — `azure-validate.ps1` + `azure-probe.ps1` |
| Task 1 — provision a clean VM | **NOT RUN** (deferred by decision; nothing billed) |
| Task 2 — install + install-path confirmation | **NOT RUN** — but the blocking bug that would have failed it is **FIXED** |
| Task 3 — the headline test | **NOT RUN — still the #1 owed item** |
| Task 4 — phone-home / meter-unknown / suite / cold-start | **NOT RUN** (probe written for all but the keyed parts) |
| Task 5 — teardown + proof | **N/A** — no VM created; "nothing billing" proven in §7 |

---

## 6. SURPRISES / BLOCKED

**SURPRISES**
1. **The installer shipped none of the security work** (§2). Four jobs of controls,
   none of them in the box a customer would install. Caught by packaging-vs-code
   diffing, not by any test — because no test had ever installed the product.
2. **There was nothing to validate.** The job says "get the current tagged build
   onto the VM"; no such build existed — the newest was 8 days stale and HEAD was
   untagged. The prerequisite was silently assumed.
3. **Signing just worked** (Status=Valid, 2.4s) — the one step expected to need
   babysitting didn't.

**BLOCKED**
- **The headline test** and every other clean-install check — need the VM run.
- **Agent-narrated checks + agent-result cold-start** — need a provider key
  (deliberately absent; keyless run decided).
- The harness is **written but unexercised**: it has never provisioned a VM. Expect
  first-run debugging, and treat a wedge as a harness fault, not a product verdict.

---

## 7. Release-readiness ledger

**Closed this session:** the installer actually contains the security track
(bundling fix + preflight guard). This was a hidden **ship-blocker**: everything
below was moot while the installer shipped none of it.

**OPEN — ranked:**
1. **The headline isolation claim is unproven on a correct install.** Everything is
   staged; one push-button run answers it. **Until it runs, ClawFactory's central
   promise is unverified.**
2. **Door 2 — the full-path bypass** (`node …/openclaw.mjs agent` runs ungated;
   agent and gateway share the `clawuser` UID). Needs a container or separate UID.
3. **"Four agents" is fiction** — only `main` is registered.
4. **GO-gating is model-dependent** — a prompt rule, not a control.
5. **DNS exfil reduced, not eliminated** — the permitted resolver still forwards.
6. **Spend is turn-granular** — an in-flight turn can overshoot.
7. **Fresh-install paths unvalidated** — the Docker-removal trap (does the nft
   firewall + gateway come up on a box where Docker never installed them?), the
   injected-SOUL/workspace ordering, the chat proxy, Tier 2, T1.3b. All converge on
   the one VM run.
8. **The broad dead-code/claims audit** — still owed.

**Teardown proof (§ required by the job):** none needed — **no VM was created**.
```
az vm list -d  ->  (empty)          # nothing exists, nothing billing
az resource list -g clawfactory-validation:
  clawfactoryvalc467              (storage, reusable)
  bake-vmVNET                     (vnet, reusable)
  clawfactory-win11-baseline      (image, reusable)
  clawfactory-win11-baseline-v2   (image, reusable)
```
Reusable infra intact; zero compute.

### Delta security sweep
- **Nothing was weakened to make anything pass** — nothing was tested. The one
  change to product behaviour is *stricter*: Preflight now refuses to install a
  build missing its security resources.
- **Bret's local machine and install: untouched.** This session only read the repo,
  built, signed, uploaded, and wrote scripts. No WSL/gateway/SOUL/firewall state on
  the daily driver was modified.
- **No key or token material in any output.** The storage account key was read into
  a variable and never printed; the generated VM admin password exists only in
  memory inside the harness and is never logged; no provider key is placed on the
  VM at all.

### Next session — one command
```powershell
.\scripts\azure-validate.ps1 -VmName cfv-138
```
Provisions, installs v1.0.38, runs the probe, prints the evidence, and tears the
VM down in `finally` with proof. Read §4's trap list first.
