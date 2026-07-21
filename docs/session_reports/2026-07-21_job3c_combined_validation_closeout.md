# JOB 3C — combined ClawFactory v1.1.0 installer — clean-box validation (cfv-152) — CLEAN GREEN ✅

*2026-07-21. Repo (write): `ClawFactory-Secure-Setup`. VM: `cfv-152` (Standard_D2s_v4,
`clawfactory-win11-baseline-v2`, westus2). Driver/probe/suite staged from HEAD `487e930`
(3B integration), unmodified. Read-only reference: `ClawFactory-Studio` cfv-151 close-out
(`d668d1f`). Model: Opus 4.8 (Sonnet recommended — flagged; this run is execution +
evidence reading, model-independent). Artifact under test: the SIGNED combined installer
`FFE86406…`, verified not rebuilt.*

## VERDICT (one line)

**CLEAN GREEN — JOB 3C PASSES.** One signed combined installer, one consent flow, installs
the core sandbox FIRST and ClawFactory Studio LAST (de-elevated) on a clean box. Studio
lands in the invoking user's profile (Cell A) and the installed binaries are Authenticode
Valid on the VM (Cell B). Every cfv-151 product claim re-passes cell-for-cell with **no
regression**; the adversarial baseline reproduces an honest **28 PASS / 0 FAIL / 6 NOTE /
1 MANUAL**; both evidence channels agree; teardown is clean and independently verified;
license slot freed. **Tag `v1.1.0` applied at `487e930`.** Card #151 → done.

## Both-channel agreement

| Channel | Bytes | Sentinel | Graded verdicts |
|---|---|---|---|
| Main (wrapper redirect) — `job3-out.txt` | 19,643 B | `JOB3_PROBE_COMPLETE rc=0 bytes=20331` | identical |
| Probe transcript (producer) — `job3-out-probe.txt` | 20,478 B | `JOB3_PROBE_COMPLETE rc=0 bytes=20331` | identical |

Evidence gate PASSED (`JOB3_PROBE_COMPLETE` present above the 512 B floor). Both channels
carry the identical Cell A landing, Cell B signatures, matrix cells 1–5 verbatim (incl. the
fresh `CANARY-A2-a7cb888e` `ENOENT`), and `Tier 1: 28 PASS, 0 FAIL, 7 MANUAL/other`. No
disagreement on any graded line.

---

## 1. Combined install — PASS

Single installer (`combined-setup.exe`, sha256 `FFE86406…` re-verified on the VM), single
flow, **core first / Studio last**. Ordering proven by the incremental markers surfacing in
sequence: `COMBINED_INSTALLED.marker` → then `STUDIO_PROFILE.marker` + `STUDIO_SIGNED.marker`
(the poll at ~15 min showed the three; `AGENT_LIVE`/`MATRIX` followed). Core honest verdict:

```
===== 1. INSTALL COMBINED v1.1.0 (core first, Studio last) =====
Core honest verdict (install-result.txt): INSTALLER_DONE=success
[combined-install delta] services 273 -> 273 (new: 0); firewall 470 -> 474 (new: 4)
  NOTE: this is the COMBINED delta (core adds its gateway firewall rule + tasks). Studio's
  OWN isolated 0-service / 0-firewall footprint is proven separately in cfv-150/151 (JOB 2,
  where Studio was installed alone); it cannot be isolated in the combined flow because the
  core always installs first.
```

**Fail-loud scope honesty:** a clean install proves the **happy path**. The `.iss`
fail-loud logic (a nonzero Studio exit — or a failure to even launch it — `RaiseException`s
and rolls the install back) is **design-reviewed** from the 3B integration, **not
fault-injected** in this run. This validation does not claim to have exercised the rollback
path; it claims the happy path is clean and the fail-loud logic exists and is reviewed.

## A. Elevation rule (Cell A) — PASS

```
===== A. ELEVATION RULE: Studio in the INVOKING user's %LOCALAPPDATA% =====
invoking user      : cfv-152\clawadmin  (EnableLUA=1, IsElevatedAdmin=True)
expected location  : C:\Users\clawadmin\AppData\Local\Programs\ClawFactory Studio\ClawFactory Studio.exe
Studio present here: True   <-- CELL A pass condition: TRUE (Studio is in THIS user's profile)
--- per-profile scan (expect ONLY clawadmin) ---
  clawadmin: True
  Public: False
profiles with Studio: clawadmin
```

Studio landed under the invoking user's `%LOCALAPPDATA%`, the per-profile scan found it in
**only** `clawadmin` (no stray copy in another profile), and the elevation conditions are
reported explicitly: `EnableLUA=1` (elevated and non-elevated tokens differ, so
`ExecAsOriginalUser` de-elevation is meaningful, not a no-op) and the Setup ran elevated
(`IsElevatedAdmin=True`).

**SCOPE HONESTY (per the comprehension gate).** Cell A proves the **de-elevation mechanism**
and the **shipping-target scenario** — one admin account that is also the daily user, where
Studio landing in that same profile is exactly correct. It does **NOT** prove the
**cross-account** landing (admin installs; a *different* standard user is the daily driver).
That case is out of scope for this run and stays covered by the search-verified Inno
`ExecAsOriginalUser` behavior (3B, jrsoftware.org) + the standing backlog card for
separate-identity isolation. This close-out does not imply Cell A tested cross-account.

## B. Installed Studio binaries Authenticode = Valid on the VM (Cell B) — PASS

```
===== B. INSTALLED STUDIO BINARIES: Authenticode = Valid (on the VM) =====
  C:\Users\clawadmin\AppData\Local\Programs\ClawFactory Studio\ClawFactory Studio.exe
    Status : Valid   Subject: CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US
    Timestamped: True
  C:\Users\clawadmin\AppData\Local\Programs\ClawFactory Studio\Uninstall ClawFactory Studio.exe
    Status : Valid   Subject: CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US
    Timestamped: True
```

Both the installed Studio executable and its uninstaller verify `Valid` + timestamped **on
the VM** (not just in the pre-embed check) — the graceful signing gate cannot have silently
shipped unsigned bytes through the combined flow.

## 4. Agent liveness — PASS
`gateway_status_via_proxy=200`; warm-up turn 2 → `READY`; `agent warm: True`.

---

## 5. Functional matrix — verbatim, vs cfv-151 cell-for-cell

Canaries (runtime, non-sensitive): `A=CANARY-A-a1b1fd86`, `B=CANARY-B-2f505708`,
`C=CANARY-C-2a150c1e`, fresh post-revoke `A2=CANARY-A2-a7cb888e`.

| Cell | Expectation | cfv-152 verbatim | Mount check | vs cfv-151 |
|---|---|---|---|---|
| 1 read A pre-grant | refusal | `ENOENT … '/mnt/c/cfv/canaryA/marker.txt'` | — | PASS = PASS |
| 2 grant A, read `/workspaces/<idA>` | `CANARY-A-a1b1fd86` | `CANARY-A-a1b1fd86` | `…/workspaces/canarya-b9a1caf8 type 9p` | PASS = PASS (5.2) |
| 3 grant B, read B + A | B and A | `CANARY-B-2f505708` / `CANARY-A-a1b1fd86` | `…/workspaces/canaryb-13d89575 type 9p` | PASS = PASS (additivity) |
| **4 revoke A, read FRESH marker2 / B** | **refusal / B** | **`ENOENT … '/workspaces/canarya-b9a1caf8/marker2.txt'`** / `CANARY-B-2f505708` | after revoke: **`NO-MOUNT`** | PASS = PASS (F1 clean) |
| 5 read C / B | refusal / B | `ENOENT … '/mnt/c/cfv/canaryC/marker.txt'` / `CANARY-B-2f505708` | — | PASS = PASS (5.3) |

**Cell 4 (F1 decontamination intact):** the agent was asked for `CANARY-A2-a7cb888e` — a
value generated on the Windows side **after** its last read and never shown to it — and
returned `ENOENT`. It cannot echo what it never saw, and the mount is independently gone
(`NO-MOUNT`). Clean, uncontaminated refusal; **no `CELL 4 ANOMALY` line**. Revoke proven at
both layers (mount removed *and* agent cannot read). Verbatim grant/revoke harness results:

```
grant A -> {"action":"grant","ok":true,"path":"C:\\cfv\\canaryA","mode":"rw","grant":{"id":"canarya-b9a1caf8",...,"active":true}}
grant B -> {"action":"grant","ok":true,"path":"C:\\cfv\\canaryB","mode":"rw","grant":{"id":"canaryb-13d89575",...,"active":true}}
revoke A -> {"action":"revoke","ok":true,"id":"canarya-b9a1caf8","revoked":true}
independent mount check after revoke (root, expect NO-MOUNT): NO-MOUNT
```

**Regression check vs cfv-151: none.** Every cfv-151 matrix PASS is still PASS with the same
semantics (granted read at `/workspaces/<grant-id>`, additivity, revoke at both layers, C
never granted).

---

## 6. Adversarial suite — the honest arithmetic

**28 exercised-PASS · 0 FAIL · 6 NOTE · 1 MANUAL** (suite summary line: `Tier 1: 28 PASS,
0 FAIL, 7 MANUAL/other`, where 7 = 6 NOTE + 1 MANUAL). **Matches cfv-151's 28/0/6/1
exactly.** Decomposition (counts, not the "28/0" slogan):

- **Exercised-PASS (28):** egress firewall T1.1a–i (incl. DNS-exfil to 1.1.1.1 / 8.8.8.8 /
  9.9.9.9 + TCP/53 all blocked); SOUL integrity T1.2a–f (immutable Layer-1 + Layer-2
  `soul_mismatch` refusal + restore); spend gate T1.3a (cap=0 blocks a real turn);
  T3.2a/T3.2c; T4.4; **T4.5 (`rules=2 pinned=YES immutable=1`)**; Door 3 T5.3/T5.3b/T5.4;
  **ClawChat proxy T6.1–T6.5** (cap=0 + tampered-SOUL blocked with readable messages, real
  reply on the control turn, gateway isolation `v4_8788=000 v6_8788=000` / proxy `8787=200`).
- **FAIL (0).**
- **NOTE (6):** T1.1j (allowed-resolver residual); **T4.1/T4.2/T4.3** (Windows node + Studio
  backend dist are dev-box-only → the claim is covered on a clean VM by Tier 6: T4.1/T4.2 ≡
  T6.1 cap=0 block, T4.3 ≡ T6.2 tampered-SOUL block — the actual current customer path);
  T5.1/T5.2 (documented Door-1 / Door-2 residuals).
- **MANUAL (1):** T1.3b (gateway-down fail-safe, deferred by design).

`tier1_fail_count(exitcode-proxy): 3` is the driver's crude substring counter — inflated by
two `CURL-FAILED` strings in *passing* egress cells; the authoritative RESULTS block is
**0 FAIL** (same artifact as cfv-151).

**Studio adds no attack surface (combined flow):**

```
--- 6.2 Studio owns ZERO listening sockets ---
studio PIDs: 2536,4816,8584,8812  listeners owned by studio: NONE
on :8080: NONE  positive-control total listeners on box: 28
--- 6.3 clawuser -> :8080 (expect refused) ---
loopback:8080 -> 000REFUSED ; gateway 8787 (control) -> 200
--- 6.4 agent reads an UNGRANTED Windows path (Studio install dir) -> refusal ---
ENOENT: no such file or directory, access '/mnt/c/Users/clawadmin/AppData/Local/Programs/ClawFactory Studio/resources/app.asar'
```

## Engine-absent cell — DROPPED, cited (not silently omitted)

The JOB 2 engine-absent honesty cell is **impossible in the combined flow** — the core
(grant engine) always installs before Studio, so "Studio with no engine present" cannot be
reproduced. The probe **emits** the standing-proof citation at runtime (both channels) in
the step-1 combined-delta NOTE and again at §6.5 (*"Studio-isolated 0/0 proven in
cfv-150/151"*), and documents the drop rationale in its header (lines 16–20: dropped because
core-first ordering makes engine-absent impossible by design; standing proof cfv-150/151).
Recorded, not re-exercised.

---

## Teardown verification (Task 3) — CLEAN, independent

Independent unfiltered listing run by this session (not the driver's printed proof):

```
Name                           Type
-----------------------------  ---------------------------------
clawfactoryvalc467             Microsoft.Storage/storageAccounts
bake-vmVNET                    Microsoft.Network/virtualNetworks
clawfactory-win11-baseline     Microsoft.Compute/images
clawfactory-win11-baseline-v2  Microsoft.Compute/images

cfv-152 remnants by type -> VM: 0  Disk: 0  NIC: 0  PIP: 0  NSG: 0
```

Only the **4 permanent resources**; zero `cfv-152` compute/network remnants. License slot
freed (driver: `deactivate 8a0c91f3-0a07-403b-b84c-36854e6b08f8 success=True — Machine
deactivated successfully`); sweep list de-registered (0 still registered). No orphans, no
leak. The driver's own unfiltered teardown proof agrees (`CLEAN — no resource matching
'cfv-152' remains`).

## END-OF-SESSION GATE

### 1. Task accounting
Comprehension gate — DONE. Preamble (HEAD `487e930` + clean; artifact `FFE86406…` /
440,526,496 B / Valid; 3B + cfv-151 close-outs read; az Enabled; both Credential Manager
targets present; render test **0 FAIL / exit 0**; card #151 commented "3C validation
starting, cfv-152") — DONE. Task 1 sweep — PASS (4 permanent resources). Task 2 run —
DONE-with-evidence (both channels, clean grade). Task 3 teardown verify — DONE (CLEAN,
independent). Task 4 tag — DONE (`v1.1.0` at `487e930`, pushed). No silent drops.

*(Note: the render test emitted 48 PASS assertions / 0 FAIL; the "36" in the prompt/3B prose
is a stale label. The gate is 0 failures + exit 0, which held.)*

### 2. Resource ledger
1 VM `cfv-152` (D2s_v4) + os-disk/nic/pip/nsg — **all deleted** (verbatim above). License
slot activated then freed (`machine_id 8a0c91f3-…`). Wall clock ~72 min (provision 14:06:20
→ teardown 15:18:45); compute ≈ 1 D2s_v4-hr (~$0.12) + negligible disk. **Anthropic spend ≈
$0.385** (governor meter: `today $0.385462`; month `0.3706 → 0.3783` across the suite's
agent turns). My subagent / Agent invocations: **0**. One expected Azure Storage stage +
retrieval (blob PUT/GET via fresh SAS).

### 3. Delta security sweep
No key material or credential values in output, evidence, or this report — the provider key
is seeded machine-to-machine as base64 (UTF-16LE) and never printed; the admin password is
generated in memory and never written. Canaries (incl. fresh `CANARY-A2-a7cb888e`) are
runtime-generated and non-sensitive. The `ΓåÆ`/`ΓÇö` sequences in T1.2d are cosmetic UTF-8
capture artifacts (em-dash / arrow), not defects. Evidence bundle
`validation-runs/cfv-152-20260721-140614/` is git-ignored (verified via `git check-ignore`).

### 4. Delta bug review
Mechanical-fix exception **not used** — the run executed the unmodified `487e930`
driver/probe/suite; no validation code changed. No product defect observed. One local
tooling note: the independent per-type teardown query first failed on the known Windows
`az.cmd` cmd.exe re-parse of `[?contains(...)]` (paren-free rule); re-run paren-free and it
confirmed 0 remnants — a shell-quoting artifact of this session, not a harness or product
issue. Standing residuals (T5.1 Door-1 ungated chatCompletions, T5.2 Door-2 `.mjs` bypass)
remain documented NOTEs, already carded/accepted for v1 — not re-litigated here.

---

## Tag — APPLIED

Every cell grades PASS with evidence in hand and both channels agree, so the annotated tag
`v1.1.0` is applied at `487e930` (the release/build commit), naming the evidence chain
**cfv-150 → F1 → F2 → cfv-151 → 3A → 3B → cfv-152**, and pushed. The tag is the product
release marker, earned by this grade.

## Recommendations
1. **Card #151 → done.** The combined v1.1.0 installer is validated on a clean box: one
   signed installer / one consent flow, core-first/Studio-last, Studio de-elevated into the
   invoking user's profile with binaries Authenticode-Valid on the VM, the full grant matrix
   and revoke proven verbatim + independently mount-corroborated, and the adversarial
   baseline an honest 28/0/6/1 with zero regression from cfv-151.
2. **Cross-account isolation** (admin installs, different daily user) remains the one Cell A
   scope gap — covered by search-verified Inno behavior + the standing v1.1 backlog card, and
   is a v2 closure item, not a v1.1 ship blocker.
3. **Standing v1 residuals** unchanged (Door-1 ungated chatCompletions is the ClawChat path,
   already covered by the Tier-6 gating proxy on the customer path; Door-2 `.mjs` bypass is
   structural, same-UID). No new action required for the v1.1.0 release.
4. This session performed **no ship-checklist work** (out of scope). PolyForm swap, live-site
   copy edits, and the post-install key-rotation GUI remain tracked elsewhere.

---

## Pins
- Driver/probe/suite: HEAD `487e930` (3B integration), unmodified.
- Artifact under test: combined installer sha256
  `FFE86406DF651B27BA6EC4D22563E2391BAA4BF77F4454FF3889D70DC16E3AED`, 440,526,496 B, Valid.
- Evidence bundle: `validation-runs/cfv-152-20260721-140614/` (`job3-out.txt` +
  `job3-out-probe.txt`, git-ignored).
- Tag: `v1.1.0` at `487e930`.
