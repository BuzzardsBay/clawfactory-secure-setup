# Clean-install validation v1.0.39 — RELEASE GATE: RED — 2026-07-16

**Top line:** The release gate does **NOT** pass, and the headline isolation claim is
**still unproven** (the run halted at the install gate, before Task 4 could run). **But
the 38-version-old ownership bug this whole lineage was about is now PROVEN FIXED** — by
direct observation on a clean machine, not inference. The install is blocked by a
**smaller, self-inflicted regression in last session's v1.0.39 fix**: the Task 3
"fail-loud" change removed `|| true` from three `systemctl --user` calls that the original
design deliberately tolerated. This routes back to the design thread as a small, precise
fix — the hard problem is solved.

VM: `cfv-0716w`, provisioned 07:51, destroyed 08:26 PT. Plus `cfv-0716v` lost to the
provisioning lottery (§4). ~$0.55 total.

---

## 1. THE ONE THING THAT MATTERS: the ownership fix works (verbatim, observed)

The `cfv-0715p` probe could only *infer* the ownership from an `EACCES` error. This run
**observes it directly** — the exact evidence the fix was owed:

```
--- 2.2 gateway unit file exists ---
-rw-r--r-- 1 clawuser clawuser 923 Jul 16 14:25 /home/clawuser/.config/systemd/user/openclaw-gateway.service

--- 2.4 OWNERSHIP: the .config/systemd/user chain ---
clawuser:clawuser drwxr-xr-x  /home/clawuser/.config
clawuser:clawuser drwxr-xr-x  /home/clawuser/.config/systemd
clawuser:clawuser drwxr-xr-x  /home/clawuser/.config/systemd/user
clawuser:clawuser drwxr-xr-x  /home/clawuser/.config/systemd/user/openclaw-gateway.service.d

--- 2.5 install.log ---
[wsl:clawuser out] [gateway-install] ownership guard OK: .config/systemd/user chain is clawuser-owned
'ft: command not found' matches (must be 0): 0
```

**The unit file is created (923 B), the entire parent chain is `clawuser:clawuser`, and
the ownership guard passed.** The `EACCES` bug (root-owned `.config/systemd/user`) is
dead. The v1.0.39 Task 1 (chown) + Task 2 (guard) fixes are confirmed working on a clean
install.

---

## 2. WHY THE GATE IS RED: a Task-3 regression, precisely located

The honest marker (the v1.0.39 Task 4 fix, working as designed) reported the failure at
the point of failure:

```
INSTALLER_DONE=failure reason=openclaw gateway install failed (exit=1): the systemd user
unit ... was not created ... (exit 90 = ownership guard tripped; any other = install
did not write the unit).
```

**Read the exit code:** `exit=1`, **not** `exit=90`. So the ownership guard did **not**
trip (§1 confirms). And the message's "unit not created" is **wrong** — §1 shows the unit
*is* created. So the throw fired for a reason my static message doesn't cover.

**The mechanism, proven from the source (`setup.ps1`, `$gatewayInstall`):**

```
1964  UNIT="$UNIT_DIR/openclaw-gateway.service"
1965  if [ ! -f "$UNIT" ]; then ... exit ; fi          # PASSED -- unit exists (§1)
...   set -e ; set -o pipefail                          # active
1985  systemctl --user daemon-reload  2>&1 | tee -a "$LOG"   # <- no `|| true`
1988  systemctl --user enable  ...    2>&1 | tee -a "$LOG"   # <- no `|| true`
1991  systemctl --user restart ...    2>&1 | tee -a "$LOG"   # <- no `|| true`
```

The unit-existence check passed, so the block continued to the three `systemctl --user`
calls. **v1.0.38 had `|| true` on all three; v1.0.39 (my Task 3) removed it and added
`set -o pipefail`.** One of them returned non-zero → pipefail + `set -e` aborted → bash
exited 1 → `$rcGateway=1` → the PowerShell side threw. The install died here, **before**
the `/status` health poll.

**Why those systemctl calls legitimately fail during the install** — and why the original
design tolerated them: `systemctl --user` needs a user bus / `XDG_RUNTIME_DIR`, which the
`wsl -u clawuser` **non-login** install context does not reliably have (other call sites
in the tree set `XDG_RUNTIME_DIR=/run/user/1000` explicitly; this block does not). The
gateway is actually started by **`openclaw gateway install --force` itself** (it writes
*and* starts the unit); the three systemctl calls are belt-and-suspenders (per openclaw
#65184), and the **`/status` poll is the real health gate**. v1.0.37/cfv-137 passed
exactly this way: systemctl calls failed silently under `|| true`, the install-command's
own gateway start bound the port, the poll confirmed it. My fail-loud change turned that
tolerated failure into a fatal one.

**This is a regression in last session's fix, caught by validation doing its job** — not
the original ownership bug (fixed) and not a new product defect.

---

## 3. THE FIX (next job — NOT done here, per validation-not-fix discipline)

Narrow Task 3's fail-loud to the part that was right, restore the part that was wrong:

1. **Keep** the unit-existence hard gate (1964-1970) — that is the correct, precise gate
   and it works.
2. **Restore tolerance** on `daemon-reload/enable/restart`: either `|| true` them again as
   v1.0.38 had, **or** (better) give them a user bus — prefix with
   `XDG_RUNTIME_DIR=/run/user/$(id -u clawuser)` (the pattern the rest of the tree uses) so
   they actually succeed. Do **not** let them abort the install; the `/status` poll (left
   untouched, correctly) is the health authority.
3. **Fix the misleading throw message** — "unit not created" fired while the unit existed.
   Distinguish "guard tripped (90)" / "unit missing" / "post-unit systemctl failed".
4. Re-validate with this run's probe (probe bugs already fixed — §5).

One instrumented note for the fix: capture the exact `[wsl:clawuser err]` line from the
failing systemctl call (which of the three, and the precise error) — this run proved
*that* they abort but did not capture *which*, because the probe halted at the gate and
did not grep the systemctl lines. The `XDG_RUNTIME_DIR` hypothesis is strong (it explains
cfv-137's pass) but is an inference until that line is in hand.

---

## 4. Ledger

| # | Item | Result |
|---|---|---|
| Gate | Read v1.0.39 close-out + lore; fetch card comments | **DONE** — #125 done/0 comments |
| Preflight 0.1-0.3 | git clean · v1.0.39 blob (340587832 B) reused · RG 4 reusable · sweep list | **PASS** |
| Key readable | `ClawFactory/ScratchAzureKey` length 108, value never printed | **PASS** |
| Seed round-trip | CredWrite(UTF-16LE) → CredRead verified locally | **PASS** |
| 1.1 provision | `cfv-0716w`, D2s_v4, Standard, agent-Ready + provisioning-state gated | **PASS** (cfv-0716v infra-failed first, §4) |
| 1.2 seed + install | key seeded pre-install; v1.0.39 sha256-verified on box; `/SILENT …` | **DONE** |
| **2.1** | Honest verdict | **FAIL — INSTALLER_DONE=failure** (release gate RED) |
| **2.2** | Gateway unit file exists | **PASS — 923 B, clawuser-owned** (fix works) |
| 2.3 | `/status`=200 | **FAIL — 000** (install aborted before the health poll; §2) |
| **2.4** | `.config/systemd/user` chain clawuser-owned | **PASS (observed)** — probe verdict was a false-FAIL (regex matched wsl stderr noise); the DATA is all `clawuser:clawuser` (§5) |
| **2.5** | Guard passed + zero `ft:` | **PASS — "ownership guard OK", ft:=0** |
| GATE | Install-completion | **FAIL → Tasks 3-9 correctly skipped** (no point validating a broken install) |
| 3-9 | Full suite incl. **Task 4 headline** | **NOT RUN — gated** (headline still unproven) |
| 10 | Teardown by name + unfiltered proof + sweep cleared | **DONE** (§6) |

---

## 5. Probe bugs found + fixed (validation tooling, not the installer)

1. **WSL CWD-translation noise.** With `automount=false` (the isolation under test),
   `wsl.exe` cannot translate the Windows CWD (`C:\Windows\system32` under RunOnce) and
   spews `Failed to translate ...` to stderr. The commands *still ran* (the real output
   followed the noise — that is how §1's evidence was recovered), but the noise polluted
   verdict parsing. **Fixed:** all `wsl.exe` calls now pass `--cd /`.
2. **2.4 false-FAIL.** The ownership-verdict regex matched the wsl stderr noise lines, not
   the `stat` lines, so it reported FAIL while the actual data was all `clawuser:clawuser`.
   **Fixed:** 2.4 now considers only lines containing `/home/clawuser/.config` and asserts
   all four are present and clawuser-owned.

These are fixed in `scripts/probe-v1039-validation.ps1` so the re-validation (after the §3
setup.ps1 fix) runs clean. They did not affect the load-bearing finding — §1's evidence
was read directly from the raw bundle.

---

## 6. Resource ledger + teardown proof (UNFILTERED — L3)

```
=== VMs in subscription (UNFILTERED) ===
                                              <- empty: nothing billing
=== RG clawfactory-validation (UNFILTERED) ===
clawfactoryvalc467  (storage)   bake-vmVNET  (vnet)   clawfactory-win11-baseline{,-v2} (images)
=== sweep list ACTIVE_VMS.txt ===
(empty -- cfv-0716w de-registered after the listing proved it gone)
```

Harness verdict: `CLEAN -- no resource matching 'cfv-0716w' remains.` No VM, disk, NIC,
IP, or NSG remains. **Cost ~$0.55**: cfv-0716w ~35 min + cfv-0716v ~60 min (the
provisioning lottery, §4) of D2s_v4.

**Every harness fix earned its keep this run:** L6 continued a running VM despite
`OSProvisioningTimedOut`; the **new terminal-provisioning guard** (added mid-session after
cfv-0716v hung the stage 20 min on `ProvisioningState/failed`) will abort the next such VM
in milliseconds; teardown-by-name + unfiltered proof + L8 sweep de-registration all fired
correctly; the honest-marker (Task 4) surfaced the failure reason precisely; the
blob-retrieved bundle beat the 4 KB truncation.

---

## 7. §4 — the provisioning lottery (infra, not product/harness)

`cfv-0716v` (first attempt) reached terminal `OSProvisioningTimedOut` — it passed the
agent-Ready gate, then the stage `run-command` hung ~20 min and failed because Azure
refuses run-command against a VM in terminal-Failed provisioning. This is the
baseline-image lottery (`cfv-0715e/h/p` provisioned fine; `b/c/d/v` did not) — **not a
product or harness fault.** Mid-session I added a `ProvisioningState/failed` guard
(committed `a9c542b`) so a future doomed VM aborts instantly instead of burning 20 min;
`cfv-0716w` then provisioned cleanly and carried the run.

---

## 8. END-OF-SESSION GATE

**Task accounting:** §4. Preflight + provision + seed + install all executed; **the Task 2
gate FAILED (RED)**; Tasks 3-9 correctly skipped. The two deliverables: (1) ownership fix —
**PROVEN WORKING**; (2) headline isolation — **still unproven** (blocked by the gate).

**Resource ledger:** VM GONE, unfiltered proof §6, sweep list empty, ~$0.55.

**Delta security sweep.** No product/installer code changed this session (validation only;
the §3 fix is a separate job). Probe/harness edits only widen nothing: the `--cd /` and
regex fixes are validation-tooling; the terminal-provisioning guard is cost-safety. The
scratch key was seeded machine-to-machine (base64, CredWrite, never printed) into a VM that
is now destroyed. **No key/token/password/SAS in this report or any commit.** Bret's daily
driver untouched.

**Delta bug review.** Found: (1) the Task-3 systemctl-tolerance regression in v1.0.39 (§2,
routed to a fix job); (2) two probe bugs (§5, fixed). No new product defect beyond the
self-inflicted §2 regression. The ownership fix is confirmed, not weakened.

**OPERATOR ACTION — revoke the scratch key.** `ClawFactory/ScratchAzureKey` was seeded into
`cfv-0716w`'s Credential Manager (VM destroyed). Revoke/rotate it now.

**Card #126 → BLOCKED** (reason: release gate RED — v1.0.39 install fails at a Task-3
systemctl regression; ownership fix proven; headline still unproven). Next: the §3 fix
(small, precise), then re-run this exact validation.

---

## 9. Commits

```
d7194c5  feat(validate): full v1.0.39 validation probe + key-seed/pktmon/extra-file harness
a9c542b  fix(harness): abort on terminal ProvisioningState/failed, don't hang the stage
<this>   fix(validate): probe --cd / + 2.4 ownership-parse (WSL noise) ; close-out
```
