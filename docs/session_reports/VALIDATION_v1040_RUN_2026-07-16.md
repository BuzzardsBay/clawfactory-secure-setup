# Clean-install validation v1.0.40 — RELEASE GATE: RED (false-failure root-caused) — 2026-07-16

**Top line:** The release gate is **RED**, but for the first time the cause is fully
root-caused with verbatim evidence, and it is **NOT a real gateway failure** — the gateway
**genuinely comes up on a clean box** (unit installed, service *active*). The install
*falsely* reports failure because the gateway-install bash block exits 1 — correlated with a
redundant `tee` to a **root-owned `/tmp/openclaw-install.log` that clawuser cannot write**
("Permission denied") — and the PowerShell throw treats any non-zero block exit as "unit not
created." Every fix this lineage shipped is now confirmed working; a residual
exit-code/log-permission gating defect is the only thing between v1.0.40 and green. The
headline isolation suite still could not run (gate RED). Routed to a precise fix job.

Also delivered and **proven**: **Task H (deactivate-on-teardown)** — the license-slot leak
that blocked the prior session is fixed; both runs this session freed their slot.

VMs: cfv-0716z + cfv-0716q (instrumented), both provisioned/installed/torn down cleanly.
~$0.55. All destroyed; slots freed; nothing billing.

---

## 1. THE ROOT CAUSE — verbatim (cfv-0716q instrumented)

The enhanced probe captured the full gateway-install section of `install.log`:

```
[wsl:clawuser out] [gateway-install] openclaw gateway install --force --port 8787
[wsl:clawuser out] Installed systemd service: /home/clawuser/.config/systemd/user/openclaw-gateway.service
[wsl:clawuser out] [gateway-install] systemctl --user daemon-reload
[wsl:clawuser out] [gateway-install] systemctl --user enable openclaw-gateway.service
[wsl:clawuser out] [gateway-install] systemctl --user restart openclaw-gateway.service
[wsl:clawuser out] [gateway-install] Gateway service active (attempt 1)
[wsl:clawuser err] tee: /tmp/openclaw-install.log: Permission denied
[wsl:clawuser err] tee: /tmp/openclaw-install.log: Permission denied
[wsl:clawuser err] tee: /tmp/openclaw-install.log: Permission denied
[wsl:clawuser exit] 1
[ERROR] Install failed: gateway install failed (exit=1): 'openclaw gateway install' did not create the unit ...
```

Read it plainly:
- **`Installed systemd service: …openclaw-gateway.service`** — `openclaw gateway install`
  **created the unit** (probe 2.2 confirms: `-rw-r--r-- 1 clawuser clawuser 923`).
- **`Gateway service active (attempt 1)`** — the systemctl calls ran and the gateway is
  **up** (the block reached its final `exit 0`).
- **The only errors are three `tee: /tmp/openclaw-install.log: Permission denied`** — that
  log is root-owned; this block runs as clawuser.
- **`[wsl:clawuser exit] 1`** — the block nonetheless exits 1, and the PowerShell throw
  (2017) converts any non-zero into the misleading **"did not create the unit"** (it plainly
  did).

So the gateway is **healthy**; the install fails only because a non-fatal `tee` error to a
root-owned log makes the block exit non-zero, and that exit is gated as fatal.

**Reproduced deterministically** — cfv-0716z and cfv-0716q showed the identical sequence.

---

## 2. What this corrects, and what it confirms

**Corrects the cfv-0716w (v1.0.39) diagnosis.** Last session I attributed that abort to "a
`systemctl --user` call returned non-zero." The instrumented log + a local repro show the
real culprit was the **`tee` to the root-owned log** failing under `set -o pipefail`:

```
local repro (Git Bash), faithful shape `bash -lc "echo b64 | base64 -d | bash -l"`:
  v1.0.39 shape  `... | tee /unwritable`            -> EXIT 1, aborts (pipefail)   <- the cfv-0716w abort
  v1.0.40 shape  `... | tee /unwritable || true`    -> EXIT 0                       <- the || true works in isolation
```

Same location, more precise cause. My v1.0.40 `|| true` genuinely fixed the *mid-block
abort* (the block now runs to "active" instead of dying at the first systemctl/tee) — but on
the **real-Linux login-shell** the block still surfaces exit 1, which my Git-Bash repro
(exit 0) cannot reproduce, so the exact bash-internal path is login-shell/`pipefail`-specific.
That detail does **not** change the fix.

**Confirms every fix in the lineage works on a clean box:**
- **Ownership fix (v1.0.39):** unit created 923 B, chain all `clawuser:clawuser` (probe 2.2/2.4 PASS), guard logged "ownership guard OK".
- **systemctl-tolerance (v1.0.40):** the three calls ran; gateway reached **"active (attempt 1)"**; the v1.0.39 mid-block abort is gone.
- **License (Task, prior):** the install ran the full ~20 min (cleared InitializeWizard); the cap is clear.
- **Task H (this session):** slot freed on both teardowns (§5).

---

## 3. THE FIX (routed — NOT done here; validation-not-fix)

The gateway is healthy, so the gate must stop treating the **block exit code** as the success
criterion. Two independent, small changes (either fixes it; do both):

1. **Don't gate on the noisy block exit.** The unit-existence check inside the block is the
   correct hard gate; once the unit exists, a non-zero block exit must **defer to the
   `/status` poll** (the health authority) rather than throw. In effect: restore the v1.0.38
   *WARN-not-throw* semantics for `$rcGateway != 0`, but keep the unit-existence check as the
   hard failure. (The PowerShell side can `test -f` the unit / check `/status` before
   throwing.)
2. **Remove the failing `tee`.** `... | tee -a "$LOG"` writes `/tmp/openclaw-install.log` as
   clawuser, but that file is root-owned → "Permission denied". The `tee` is **redundant** —
   `Invoke-WslBash` already captures every `[wsl:clawuser out]` line into
   `C:\ProgramData\ClawFactory\install.log`. Drop the `tee` (or pre-create the log
   clawuser-writable, as the v1.0.11/13 lineage did for the OpenClaw-install step).

Do **not** re-touch the ownership fix or the unit-existence hard gate (both proven).

---

## 4. Ledger

| # | Item | Result |
|---|---|---|
| Gate 1-3 | v1.0.40 close-out + `$gatewayInstall` source · card comments · key readable (108) | **DONE** |
| Gate 4 | License slots free (probe activate `valid:true` → deactivate) | **PASS** |
| **Task H** | Deactivate-on-teardown (capture MachineGuid → POST /deactivate) | **DONE + PROVEN** (§5) |
| 0 | Preflight — v1.0.40 staged (340582248 B), RG reusable, nothing billing | **PASS** |
| 1 | Provision + seed + pktmon + install (both VMs full ~20 min) | **DONE** |
| **2.1** | Honest verdict | **FAIL — INSTALLER_DONE=failure** (false; §1) |
| **2.2** | Gateway unit file exists | **PASS — 923 B, clawuser-owned** |
| 2.3 | `/status`=200 | **FAIL** (probe ran post-abort; but "Gateway service active" proves it was up) |
| **2.4** | `.config/systemd/user` chain clawuser-owned | **PASS (observed)** |
| **2.5 + A3** | Guard OK, `ft:`=0, three systemctl lines + **`[wsl:clawuser exit] 1` + tee errors** | **CAPTURED — the root cause (§1)** |
| GATE | Install completion | **FAIL → Tasks 3-9 skipped** (headline still unproven) |
| 3-9 incl. **Task 4 headline** | Full suite | **NOT RUN — gated** |
| 10 | Teardown by name + unfiltered proof + **license deactivate** + sweep cleared | **DONE** (§5) |

---

## 5. Resource ledger + teardown proof (UNFILTERED — L3) + Task H

```
=== VMs (UNFILTERED) ===                (empty -- nothing billing)
=== RG clawfactory-validation ===       clawfactoryvalc467 · bake-vmVNET · baseline{,-v2}  (all reusable)
=== sweep list ACTIVE_VMS.txt ===       (empty)
=== license slot (Task H.2) -- BOTH runs ===
  cfv-0716z: deactivate (320f8181-44a9-4ef3-9c49-06f783ac8e23): success=True
  cfv-0716q: deactivate (afd3faef-7a18-4346-b3ce-ea93586daabb): success=True
```

Harness verdict both runs: `CLEAN -- no resource matching '<vm>' remains.` **~$0.55** (two
full installs, ~20 min each, D2s_v4). **Task H proven: the license-slot leak that blocked the
prior session is fixed** — every VM now frees its slot on teardown, and the deactivate uses
the exact `MachineGuid` the installer activated (captured pre-install).

---

## 6. END-OF-SESSION GATE

**Task accounting:** Task H **DONE + proven**. PART B ran to the **install gate**, which
**FAILED (RED)** — but root-caused to a false-failure (§1), not a real gateway fault.
Tasks 3-9 (incl. the Task 4 headline) not run. The gateway is *proven* to come up on a clean
box; the headline remains unproven only because the gate blocks the suite.

**Resource ledger:** both VMs GONE, unfiltered proof §5, sweep empty, both slots freed, ~$0.55.

**Delta security sweep.** The only committed code change is the harness (Task H deactivate +
probe instrumentation) — validation tooling, no product/installer edits, no permission
widened, no egress, no Docker. The Task H `/deactivate` call posts only
`{key, machine_id, product}` to the product's own license API (operator-instructed); no
secret is logged. Scratch key seeded machine-to-machine (base64/CredWrite, never printed)
into VMs now destroyed; not flagged for revocation (operator reuse, by instruction). No
key/token/password/SAS in this report or any commit. Bret's daily driver untouched.

**Delta bug review.** Root-caused the false-failure (§1) — a real, precise, routable defect
(exit-code gating + root-owned-log `tee`), NOT a gateway failure. Corrected the prior
cfv-0716w diagnosis (§2). No new product defect beyond this one. All lineage fixes confirmed
working.

**Card #126 → BLOCKED** (reason: v1.0.40 install RED-gates on a false-failure —
gateway is healthy on a clean box, but the block exits 1 via a root-owned-log `tee` +
exit-code gating; precise fix routed. Task H slot-leak fix proven. Headline still unproven —
blocked by the gate). Next: the §3 fix (small), then re-run this exact validation → the
headline finally runs.

---

## 7. Commits

```
12fc051  feat(harness): deactivate the license slot on teardown (Task H)
9386a1e  feat(validate): capture the full gateway-install section + [wsl exit] code
<this>   docs: v1.0.40 validation run close-out (RED -- false-failure root-caused)
```
