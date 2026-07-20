# Egress persistence + Studio root cause — DIAGNOSTIC close-out (2026-07-19)

## Verdict lines (read these first)

```
EGRESS-AFTER-WSL-SHUTDOWN:    HOLDS
EGRESS-AFTER-WINDOWS-REBOOT:  HOLDS
IDLE-SHUTDOWN-REACHABLE:      NO
STUDIO-ROOTCAUSE:             UNPINNED-BUT-NARROWED -- setup-studio.ps1 exits 1 in ~1s writing ZERO log lines (fails at/before its first Write-Log, i.e. BEFORE Step-InstallNode/msiexec). The msiexec-1618 hypothesis is REFUTED.
STUDIO-RACE-OR-UNCONDITIONAL: UNCONDITIONAL (2nd attempt after a 30s delay failed identically)
```

**NOT a ship-blocker.** The published egress allowlist is a genuine structural control that
**survives both a `wsl --shutdown` and a full Windows reboot** on the shipped v1.0.47 build.
The Studio-session `T1.1a` FAIL (27/1 vs the 28/0 baseline) was **probe-induced**, not a
v1.0.47 regression (evidence below).

Run: `cfv-0719e2` (v1.0.47, byte-exact — sha256 verified on the box). `HARNESS_EXIT=0`. One
earlier attempt (`cfv-0719e`) was lost to a probe-orchestration bug (see *Delta bug review*),
not a product issue; both VMs torn down clean.

---

## Part A — egress persistence

### A2 — mechanism (the "why", from source + the box)

Egress is applied by an **enabled systemd oneshot**, `clawfactory-fw.service`
(`setup.ps1:1457-1470`), which re-runs `/usr/local/sbin/clawfactory-fw-apply.sh` on every
distro boot. Confirmed on the box — **it ran on boot** (a `oneshot` is `inactive (dead)` after a
*successful* apply, which is correct, not a failure):

```
is-enabled: enabled
Loaded: loaded (/etc/systemd/system/clawfactory-fw.service; enabled; vendor preset: enabled)
Active: inactive (dead) since Mon 2026-07-20 01:11:00 UTC; Main PID: 168 (code=exited, status=0/SUCCESS)
Jul 20 01:10:59 cfv-0719e2 systemd[1]: Starting ClawFactory egress firewall ...
Jul 20 01:11:00 cfv-0719e2 systemd[1]: Finished ClawFactory egress firewall ...
[Unit] After=network-online.target   [Service] Type=oneshot   [Install] WantedBy=multi-user.target
```

This is the re-apply-on-boot path the Task-0 search predicted was *required* for persistence.

### A1 — baseline (fresh install)
`nft list ruleset` shows the `clawfactory` table with a populated `allowed_ipv4` set (allowlisted
provider/OS IPs), verbatim:
```
table inet clawfactory {
    set allowed_ipv4 { type ipv4_addr; flags dynamic,timeout; timeout 6h;
        elements = { 74.125.142.84 ..., 91.189.91.46 ..., 104.16.0.34 ..., ... } }
    ...
```
Consumer-side verdict: `EGRESS-ENFORCED` (blocked host dropped, allowed host reachable). **See
the evidence-integrity note below** — the raw `curl`-as-`clawuser` strings were swallowed by a
probe bug; the *verdict* is reliable (self-validated by the allowed-host control) but the raw
per-host lines did not print.

### A3 — after `wsl --shutdown` (the core mechanism test)
```
gateway up after wsl --shutdown: True
nft clawfactory table present after restart: True
A3 EGRESS-AFTER-WSL-SHUTDOWN: HOLDS
```
The distro was shut down and restarted; the oneshot re-applied the table; the consumer-side
check (curl as `clawuser`) shows the blocked host dropped and the allowed host reachable →
**HOLDS**. This is the identical distro-boot re-apply path a Windows reboot triggers.

### A4 — after a FULL WINDOWS REBOOT (the realistic customer case)
Stage-2 ran after a real Windows reboot (auto-logon re-armed with a reset throwaway password).
```
clawfactory-fw.service after reboot: inactive   (oneshot ran-and-exited = normal)
A4 verdict: EGRESS-AFTER-WINDOWS-REBOOT: HOLDS
```
The `HOLDS` is self-validating: it requires the allowed host (`api.anthropic.com`) to be
**reachable** while `example.com` is **blocked** — so it cannot be a "network is simply dead"
false pass. **Side note (not an egress issue):** `gateway /status up after reboot: False` — the
OpenClaw gateway/agent did not come back within the 120 s post-reboot window; it takes longer
than that to restart after a cold Windows boot (keepalive → WSL → user-systemd → gateway). The
egress curl test does not depend on the gateway, so this does not affect the verdict, but it is
worth knowing that the agent is not instantly available post-reboot.

### A5 — idle-timeout
```
clawadmin .wslconfig: [wsl2] vmIdleTimeout=-1  (# Added by ClawFactory v1.0.1 ...)
IDLE-SHUTDOWN-REACHABLE: NO
```
Our config sets `vmIdleTimeout=-1`, which **disables** WSL idle shutdown — so the VM does not
tear down on its own from inactivity. **But the A3/A4 condition (a WSL VM restart) is still
reached without any agent-relevant user action** — a Windows reboot, a WSL servicing update, or
a manual `wsl --shutdown` all trigger it. The important point: egress **HOLDS** through that
restart, so the reachable-but-benign trigger is not a problem.

### A6 — recovery
N/A — A3 held (egress was enforced after the restart), so there was nothing to recover.

---

## Why the Studio-session `T1.1a` FAIL was probe-induced (Task 4: both HOLD)

This clean run isolates the variable. **Here** (default NAT, `wsl --shutdown`, waiting for the
gateway/firewall to settle before testing): egress **HOLDS**. **There** (the Studio session): the
`T1.1a` FAIL occurred only after the Studio probe's **mirrored-networking** manipulation
(`networkingMode=mirrored`) plus multiple `wsl --shutdown` cycles, with the adversarial suite
running at the very end. Two probe-side causes, either or both:
1. **Mirrored networking changes the network path** — `networkingMode=mirrored` shares the
   Windows network namespace, so the `clawuser`-UID-scoped `nft output` rules do not govern
   egress the same way; a check taken while mirrored (or immediately after switching back,
   before the firewall re-applied) sees open egress.
2. **Timing** — the adversarial suite ran right after the last restart, potentially **before**
   `clawfactory-fw.service` (`After=network-online.target`) had re-applied.

**Fix for the adversarial suite / any networking-manipulating probe** (so it stops emitting this
false signal): after any `wsl --shutdown` — and especially after toggling `networkingMode` —
**wait for `clawfactory-fw.service` to have re-applied** (e.g. poll `nft list table inet
clawfactory` or the gateway `/status`) and **fully restore default NAT** before running the
egress test. The clean A3 here already does this and passes.

---

## Part B — Studio root cause (capture)

The probe captured what the last probe missed. Result:
```
studio installer exit=0            (Inno masks it -- product bug #1, unchanged)
setup-studio.ps1 [studio] log lines in ProgramData\ClawFactory\install.log: ZERO
Inno studio-install.log: "Process exit code: 1"  (setup-studio.ps1 exited 1 in ~1s: 01:22:56.590 -> 01:22:57.563)
sc query ClawFactoryStudio: 1060 "service does not exist"
2nd attempt (after 30s): exit 0 / setup-studio.ps1 exit 1 / still no service  -> UNCONDITIONAL
```

**`STUDIO-ROOTCAUSE`: narrowed, not fully pinned.** `setup-studio.ps1` exits 1 in ~1 second while
writing **zero** `[studio]` lines to its own log — meaning it fails **at or before its first
`Write-Log`**, which is *before* `Step-InstallNode`/`msiexec`. So the standing **`msiexec 1618`
hypothesis is REFUTED** (the failure is earlier than the Node MSI), and it is **UNCONDITIONAL**
(the 2nd attempt failed identically, so it is not a race with the preceding Secure-Setup
install). The failure is early enough that the script produces no diagnostic — which means the
"make Studio start" job must **run `setup-studio.ps1` directly** (not via Inno) to capture the
raw PowerShell error / parse error, since the Inno `[Run]` swallows the child's stderr and the
script dies before logging. Candidate causes to check first: a parse/`Set-StrictMode 3.0`
failure, param binding, or an early exception before the `try` block.

**Product bug #2 confirmed (one-liner, as required):** the fix must set
`CLAWFACTORY_GRANTS_ENGINE=C:\Program Files\ClawFactory\resources\clawfactory-grants.ps1`
(verified present on the box); `setup-studio.ps1:163` sets only `NODE_ENV`+port, and
`config.ts:25-27` defaults to a hardcoded dev path.

---

## Task 0 — search + source (recorded in full)

**Search (named-product behavior):** runtime `nft` rules inside a WSL2 distro are **discarded on
`wsl --shutdown`** (the VM's netfilter state resets) **unless** re-applied on boot via a systemd
unit, `netfilter-persistent`, or `wsl.conf boot.command`. `wsl --shutdown` is triggered by a
Windows reboot, WSL servicing updates, the idle timeout, or a manual call. Sources:
[microsoft/WSL #6655](https://github.com/microsoft/WSL/issues/6655),
[MS Learn — wsl-config](https://learn.microsoft.com/en-us/windows/wsl/wsl-config),
[Red Hat — nftables on WSL](https://access.redhat.com/solutions/7129581),
[microsoft/WSL #13416 (systemd + shutdown)](https://github.com/microsoft/WSL/issues/13416).

**Source (our mechanism):** `Step-EgressFirewall` (`setup.ps1:1252-1500`) writes
`/etc/nftables.conf` + `/usr/local/sbin/clawfactory-fw-apply.sh`, installs and **enables**
`clawfactory-fw.service` (oneshot, `WantedBy=multi-user.target`, `After=network-online.target`,
`setup.ps1:1457-1470`). The wsl.conf it writes has `[boot] systemd=true` but **no
`boot.command`** — persistence rides entirely on the enabled systemd oneshot. A separate 5-hourly
timer (`setup.ps1:1824-1860`) refreshes provider IPs; it is not the boot re-apply. **Conclusion
before observing:** persistence *should* HOLD via the oneshot — which A2/A3/A4 confirmed.

---

## What was NOT cleanly tested (explicit)

- **Verbatim consumer-side `curl` strings** for A1/A3/A4 — a probe bug (below) swallowed the raw
  `clawuser -> example.com` / `api.anthropic.com` lines. The **verdicts are reliable** (the
  returned booleans drove HOLDS, and HOLDS is self-validating via the allowed-host control), and
  the mechanism is proven verbatim (oneshot journal + nft table present after restart) — but the
  per-host raw strings did not print. A re-run with the now-fixed probe would show them; given
  the outcome is a **non-blocker with strong mechanism corroboration**, I did not spend a third
  VM on evidence-display alone. Flagging for the record.
- **Agent narration** for the egress checks came back **empty** (cold-start/refusal on the first
  post-idle turn). The `curl`-as-`clawuser` result (the agent's exact UID) is the authoritative
  consumer-side network fact and drove the verdicts; the agent's *narration* was the nice-to-have
  that did not land.
- **The exact `setup-studio.ps1` throwing line** — it fails before logging (see Part B); pins on
  the next job by running the script directly.

---

## End-of-session gate

### 1. Task accounting
- Comprehension gate — DONE. Task 0 (search + source) — DONE-with-evidence. Task 1 provision —
  DONE (cfv-0719e2, v1.0.47 byte-exact, scratch key `ClawFactory/ScratchAzureKey` seeded m2m).
- Part A (A1/A2/A3/A4/A5/A6) — DONE-with-evidence; verdicts HOLDS/HOLDS/NO. A6 N/A (A3 held).
- Part B (Studio capture) — DONE-with-evidence; root cause narrowed + refuted the hypothesis,
  exact line DEFERRED to a direct-run capture.
- Task 4 branch — both HOLD → Studio-session FAIL explained as probe-induced, with the fix.

### 2. Resource ledger (unfiltered list-proof)
```
targets -> nic: cfv-0719e2VMNic | pip: cfv-0719e2-pip | nsg: cfv-0719e2-nsg | disk: cfv-0719e2-osdisk
license slot deactivate (7ff7ec1d-4728-47a1-b230-d14df1d97bc4): success=True msg=Machine deactivated successfully.
===== TEARDOWN PROOF (unfiltered) =====
clawfactoryvalc467 / bake-vmVNET / clawfactory-win11-baseline / clawfactory-win11-baseline-v2  (the 4 permanent only)
CLEAN -- no resource matching 'cfv-0719e2' remains.   HARNESS_EXIT=0
```
The earlier lost attempt `cfv-0719e` also tore down clean (slot `e201af42` freed `success=True`,
0 resources). Two disposable VMs this session, both gone; both slots freed.

### 3. Delta security sweep
**No product security posture was changed — diagnostic only.** No Secure-Setup or Studio source
was modified; only a validation probe (`scripts/egress-persistence-probe.ps1`) and this close-out
were written. The session's net effect on posture is **zero**; it *confirmed* an existing
structural control (egress) survives a restart.

### 4. Delta bug review
**Product bugs (reported, NOT fixed):**
- #1 (unchanged) Studio installer masks a failed `setup-studio.ps1` as success (`.iss:97-100`).
- #2 (confirmed) `CLAWFACTORY_GRANTS_ENGINE` not set by the installer; `config.ts` dev-path default.
- The `setup-studio.ps1` early unconditional failure itself (root cause pending a direct-run capture).

**Probe bugs (FIXED — tooling only, `scripts/egress-persistence-probe.ps1`):**
1. **Lost first run** — the A4 reboot stage let the harness's `wrapper.cmd` write `DIAG_DONE`
   *prematurely* (stage-1 exited before the reboot), and the retrieval raced stage-2's open
   `diag-out.txt` handle → the harness's anti-blind-teardown guard threw and the bundle was lost
   (VM torn down clean). Fixed: stage-1 now **blocks until the reboot kills it**, and `DIAG_DONE`
   is written by `ep-stage2.cmd` **after** the payload exits and releases the file.
2. **`EgressCheck` output swallow** — `$x = EgressCheck ...` captured the function's
   `Write-Output` detail into the variable, hiding the verbatim `curl` lines (verdicts survived).
   Fixed to report via a script-scoped var. (Same class as the Studio probe's `Run-Phase1-Sweep`
   and now caught a third time — see the memory note.)
