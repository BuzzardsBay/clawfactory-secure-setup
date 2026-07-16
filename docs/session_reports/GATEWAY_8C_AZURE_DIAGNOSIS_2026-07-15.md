# Step 8c gateway failure — Azure diagnostic cycle — 2026-07-15

**ROOT CAUSE CAPTURED.** Card #124 → **done** (for this diagnostic; the fix is the next job).

> **The gateway's systemd `--user` unit file is never created — `openclaw gateway
> install --force --port 8787` (`setup.ps1:1918`) does not produce
> `/home/clawuser/.config/systemd/user/openclaw-gateway.service`, and its non-zero
> exit is swallowed by a `WARN` (1921–1923), so the installer proceeds to
> `daemon-reload` / `enable` / `restart` a unit that does not exist and then blames
> the gateway with "Gateway did not respond after 120 seconds".**

Every layer this cycle was sent to investigate — the user session, linger,
`user@1000`, `/run/user/1000`, logind, the user bus — is **provably healthy**. The
hypothesis in the job spec is **falsified**, and last session's refusal to report
`219/CGROUP` as the cause is now vindicated: it was a local scratch artifact.

VM: `cfv-0715h`, 20.230.146.104, provisioned 18:51:48, destroyed 19:31 PT. **~$0.55
total** across the cycle (all VMs, see §7).

---

## 1. THE LOAD-BEARING EVIDENCE (Task 3.5) — verbatim

```
########## 3.5 THE GATEWAY ITSELF ##########
--- unit file present? ---
ls: cannot access '/home/clawuser/.config/systemd/user/openclaw-gateway.service': No such file or directory
--- systemctl --user -M clawuser@ status openclaw-gateway (needs a live user bus) ---
Failed to get properties: Transport endpoint is not connected
--- ss -ltnp : is ANYTHING listening on 8787/8788? ---
  (nothing listening on 8787/8788)
--- any openclaw/node processes alive? ---
  (no openclaw/node processes)
```

**There is no unit. There never was.** `systemctl --user enable/restart
openclaw-gateway.service` had nothing to act on.

### The mechanism, in `setup.ps1`'s own words

```
1918  openclaw gateway install --force --port 8787 2>&1
1919  rc=$?
1921  if [ "$rc" -ne 0 ]; then
1922      echo "[gateway-install] WARN: openclaw gateway install --force returned $rc - continuing
1923            to daemon-reload/restart; PowerShell-side /status poll is the source of truth..." >&2
1926  systemctl --user daemon-reload            2>&1 | tee -a "$LOG" || true
1929  systemctl --user enable  openclaw-gateway.service  2>&1 | tee -a "$LOG" || true
1932  systemctl --user restart openclaw-gateway.service  2>&1 | tee -a "$LOG" || true
```

The **one command that creates the unit** has its failure demoted to a warning, and
the three that depend on it are each `|| true`. So the install cannot fail at the
point of failure; it fails 120 s later, pointing at the wrong component. The
comment above it (line 1900) shows this is familiar ground: *"a workaround for the
missing unit (the prior code tried to start a unit nothing in our flow had ever
created)."*

### The timeline lines up exactly

```
01:14:58  user@1000 started, "Startup finished in 386ms."
01:22:45  provider.json written
01:28:25  systemd[318]: Reloading.        <- setup.ps1:1926 daemon-reload. It REACHED the step.
01:30:49  Process exit code: 1            <- 120s later: "Gateway did not respond"
```

---

## 2. The hypothesis is FALSIFIED — every layer beneath is healthy

```
--- systemctl status user@1000.service ---
     Active: active (running) since Thu 2026-07-16 01:14:58 UTC; 15min ago
     Status: "Startup finished in 386ms."
   Main PID: 318 (systemd)
--- systemctl show user@1000 ---
Result=success   ExecMainCode=0   ExecMainStatus=0   ActiveState=active   SubState=running

--- loginctl show-user clawuser ---
State=active     Linger=yes     Sessions=1     RuntimePath=/run/user/1000

--- ls -ld /run/user/1000 ---
drwx------ 5 clawuser clawuser 180 Jul 16 01:14 /run/user/1000

--- exactly what setup.ps1 does at 1932 (systemctl --user as clawuser) ---
running        <- systemctl --user is-system-running
inactive       <- is-active openclaw-gateway.service (no such unit)

--- logind ---
Jul 16 01:14:56 systemd-logind[188]: New seat seat0.
Jul 16 01:14:57 systemd-logind[188]: New session 1 of user clawuser.
     Active: active (running)   Status: "Processing requests..."
ii  dbus-user-session 1.12.20-2ubuntu4.1   /etc/pam.d/common-session:29: session optional pam_systemd.so
```

The job's stated hypothesis — *"on a clean boot nothing ever creates clawuser's
login session, so `user@1000` has no trigger to start"* — is **wrong on every
clause**: the session IS created, `user@1000` IS running, the runtime dir DOES
exist, the bus IS reachable.

**`219/CGROUP` is confirmed a local artifact.** Last session's contaminated scratch
distro showed `user@1000: failed / 219/CGROUP`; the clean single-distro VM shows
`active (running)`. Refusing to report it as root cause was correct.

**Single-distro proof (3.1):**
```
  NAME      STATE     VERSION          PRETTY_NAME="Ubuntu 22.04.5 LTS"
* Ubuntu    Running   2                pid1: /lib/systemd/systemd --system
  boot_id: 0d13efb0-1f69-4dfb-8419-0ccd41aece9f      systemd: running
```
`pid1 cgroup ns: cgroup:[4026531835]` is the host root ns here **too** — but with
only ONE distro there is no second systemd to contend for `/user.slice`, so nothing
fails. That is precisely why the local repro was invalid and this VM is not.

---

## 3. Ruled out, with evidence

| Candidate | Verdict | Evidence |
|---|---|---|
| linger / no login session | **DEAD** | `Linger=yes`, `State=active`, `New session 1 of user clawuser` |
| `user@1000` fails (219/CGROUP) | **DEAD** | `active (running)`, `Result=success`, `ExecMainStatus=0` |
| `/run/user/1000` missing → "Failed to connect to bus" | **DEAD** | dir exists; `is-system-running` → `running` |
| Docker removal took the login shell with it | **DEAD** | user session exists without it |
| logind unhealthy | **DEAD** | `active (running)`, "Processing requests..." |
| **Type=simple race** | **MOOT** | unit does not exist, so nothing can be "active early". `curl 8787 → http=000` |
| **v1.0.2 session-exit shutdown** | **NOT the cause at 8c** | see below |

**The v1.0.2 lore check fired — and is still not the cause.** The shutdown signature
IS present, three times:
```
01:14:17 unknown: Operation canceled @p9io.cpp:258 (AcceptAsync)
01:14:17 systemd-logind[209]: System is powering down.
01:14:42 systemd-logind[185]: System is powering down.
```
But the boot table shows those cycles are **early**, and boot 0 spans the whole
gateway step unbroken:
```
-3  01:14:01 — 01:14:18      -1  01:14:36 — 01:14:46
-2  01:14:24 — 01:14:27       0  01:14:54 — 01:30:51   <- gateway step at 01:28-01:30 lives entirely here
```
So the distro was stable for the 16 minutes covering the failure. Real mechanism,
wrong crime scene. Worth noting the keepalive that suppresses it is registered at
`setup.ps1:2771`, i.e. **after** the gateway step at 2720 — a latent ordering
oddity, not today's bug.

---

## 4. What is NOT yet known — and the ONE probe that settles it

**Proven:** the unit is absent, and the command meant to create it has its failure
swallowed.
**Not proven:** *why* `openclaw gateway install --force --port 8787` fails or no-ops.

I am not going to guess. The one probe that settles it, which this bundle missed:

```bash
# 1. the log that step writes and that nothing ever reads back (setup.ps1:1913)
cat /tmp/openclaw-install.log
# 2. run the exact command as clawuser and capture rc + BOTH streams
su clawuser -s /bin/bash -c 'openclaw gateway install --force --port 8787; echo rc=$?' 2>&1
# 3. setup.ps1's OWN log (this bundle read the wrong path -- see §6)
Get-Content 'C:\Program Files\ClawFactory\install.log' -Tail 120
```

**Leading suspect, explicitly NOT claimed as cause:** `Step-EgressFirewall` (step
10) runs **before** `Step-PreinstallGatewayRuntime` (step 13) and Job 4 added
UID-scoped nft rules; if `openclaw gateway install` needs egress as `clawuser`, the
firewall would break it — and v1.0.37 (cfv-137) passed *before* those rules existed.
That is a hypothesis with a motive, not a finding. Probe 2 above distinguishes it in
one run.

---

## 5. Ledger

| # | Item | Result |
|---|---|---|
| Gate 1–2 | `CLAUDE_ClawFactory.md` (Type=simple window, user-session lore) · `38d5481` + cfv-0715 close-outs | **DONE** |
| Gate 3 | Fetch #124 comments | **DONE** — Blocked, **0 comments**, nothing to escalate |
| **Gate/Task 0** | `Step-WireProviderKey` AFTER the gateway step → no key needed | **CONFIRMED** — source order `2720` → `2724`, and the checkpoint ends at `OpenClawConfigured` |
| 0.1 | `git status --short` | **DONE** — clean at `38d5481` |
| 0.2 | Staged installer reused, not rebuilt | **DONE** — blob `ClawFactory-Secure-Setup-v1.0.38.exe`, **340587592 B**, sha256 re-verified **on the VM** |
| 0.3 | RG holds only reusable infra, nothing billing | **DONE** — verbatim §7 |
| **1.1/1.2** | **Harden teardown (L3) + commit** | **DONE** — `0a05c72`, and it **earned itself twice** (§6) |
| 2.1 | Provision `cfv-0715h` | **DONE** — D2s_v4, Standard, 18:51:48 |
| 2.2 | Auto-logon + RunOnce wrapper, proven flags | **DONE** — `/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG /PROVIDER=claude /LICENSE=CF-TEST-…` |
| 2.3 | Poll INSTALLER_DONE, expect gateway failure | **DONE (failed as predicted)** — `Process exit code: 1`; checkpoint ends at `OpenClawConfigured` |
| **3.1** | Single-distro proof | **CAPTURED** — one distro; scratch artifact ruled out |
| **3.2** | **`user@1000` state + why** | **CAPTURED** — `active (running)`, `Result=success` → **hypothesis falsified** |
| 3.3 | Linger + sessions | **CAPTURED** — `Linger=yes`, `Sessions=1` |
| 3.4 | Runtime dir | **CAPTURED** — `/run/user/1000` exists |
| **3.5** | **The gateway itself** | **CAPTURED — THIS IS THE ANSWER** — unit file absent |
| 3.6 | Type=simple race | **CAPTURED → MOOT** — no unit to race |
| 3.7 | logind health | **CAPTURED** — healthy; session created |
| 4.1/4.2 | Teardown by explicit name + unfiltered proof + cost | **DONE** — §7 |

**Not done, deliberately:** no fix, no suite (`-SkipSuite`), no rebuild, `|| true`
linger gap untouched — all out of scope per the job.

---

## 6. SURPRISES — the harness ate this session

Six VMs died to harness defects before one produced evidence. Each is now a
permanent lesson and a loud guard; none was a product fault.

1. **L5 — a stream redirect turned `az` WARNINGS into fatal errors.** I invoked the
   harness as `... *>&1 | Tee-Object`. `az vm create` **succeeded** — an independent
   probe returned `STILL_INSTALLING` — but az printed
   `WARNING: The default value of '--size' will be changed...`; PS 5.1 wraps
   *redirected* native stderr in ErrorRecords; `EAP=Stop` made it terminating;
   `finally` **tore down a healthy, installing VM**. A `finally` teardown makes this
   expensive: it deletes the evidence.
2. **L6 — the inverse.** Removing the redirect removed the false fatal and created a
   false success: `ERROR: OSProvisioningTimedOut` followed on the next line by
   `[17:31:39] Provisioned.` `EAP=Stop` does not govern native exit codes. Neither
   mode is safe; the rule is **no redirect + explicit `$LASTEXITCODE`** — *and* don't
   trust the code alone, because ARM reports `OSProvisioningTimedOut` for this image
   while the guest boots fine (cfv-0715d was `PowerState/running`).
3. **L7 — `az` on Windows is `az.cmd`, a batch wrapper: cmd.exe re-parses every
   argument.** This is the root of **L2 AND L3**, each previously misdiagnosed twice.
   The proof was the harness printing a **local cmd prompt**:
   `Output: C:\Users\bmcki\ClawFactory-Secure-Setup>` … `was unexpected at this time.`
   The script was never sent to Azure — cmd tried to run it *here*. Explains L3's
   `[?starts_with(...)]` (parens), multi-line `--scripts` (quotes), SAS `&`, and
   `$((Get-Item x).Length)` (parens).
4. **`--query "value[0].message"` is StdOut ONLY.** A script that throws leaves
   StdOut empty and its error unread in `value[1]`. That is why cfv-0715c looked
   like "empty output, transport broken" when the transport was fine and the script
   had simply thrown. I spent two VMs blaming the wrong layer.
5. **run-command's `message` truncates at ~4 KB — keeping the TAIL.** cfv-0715g's
   bundle came back as its last 4116 bytes: sections 3.1–3.4 and the head of 3.5
   **silently vanished**, no error, no marker. The answer was in the missing part.
   The bundle is now pulled via blob (14869 bytes) with a byte-count assertion.
6. **`function H` never ran.** PowerShell ships `h` as an alias for `Get-History`
   and **aliases outrank functions**, so every header call was really
   `Get-History "0. WINDOWS SIDE..."`. Renamed to `Section`.
7. **cfv-0715d wedged `run-command` for 20+ minutes** (agent `Not Ready` after
   `OSProvisioningTimedOut`) — frozen output that reads exactly like a slow install.
   `run-command invoke` has no client-side timeout. Now gated on agent Ready.
8. **The L3 teardown fix earned itself twice in one session:** (a) cfv-0715b's
   create failed half-way, so `az vm show` returned nothing and only the *pinned*
   names could delete the orphans — the exact case the old `starts_with` filter
   silently missed; (b) its assertion caught `cfv-0715b-osdisk` — though that was a
   **false alarm** from reading the listing before ARM settled, which I fixed
   (10×15 s settle), because a false alarm every run is how a real alarm gets ignored.
9. **`INSTALLER_EXIT=0` is a lie.** setup.exe exits 0 while `install.log` records
   `Process exit code: 1` for setup.ps1 — Inno's `[Run]` failure doesn't propagate
   under `/SILENT`. The harness's success signal is unreliable; **not fixed**, logged
   below.
10. **My own probe was nearly defeated by the product's own isolation:** the bundle
    originally staged itself via `wslpath` → `/mnt/c/...`, but ClawFactory sets
    `[automount] enabled=false` (and `Assert-WslAutomountDisabled` *throws* if it
    can't verify it), so `/mnt/c` does not exist. Caught before the run; now passed
    as base64.

---

## 7. Resource ledger + teardown proof (UNFILTERED — L3)

```
=== VMs in subscription (UNFILTERED) ===
                                              <- empty: nothing billing

=== ALL resources in clawfactory-validation (UNFILTERED) ===
Name                           Type
-----------------------------  ---------------------------------
clawfactoryvalc467             Microsoft.Storage/storageAccounts   (reusable)
bake-vmVNET                    Microsoft.Network/virtualNetworks   (reusable)
clawfactory-win11-baseline     Microsoft.Compute/images            (reusable)
clawfactory-win11-baseline-v2  Microsoft.Compute/images            (reusable)
```
No `cfv-*` VM, disk, NIC, public IP, or NSG remains. Harness verdict:
`CLEAN -- no resource matching 'cfv-0715h' remains.`

**Cost.** 7 VMs, ~166 min of `Standard_D2s_v4` @ ~$0.192/h ≈ **$0.53**; ~$0.02
storage/IP. **≈ $0.55 total.** cfv-0715d alone was 61 min (the wedge). All destroyed:
`b, c, e, f, g, h` by the harness `finally`; `d` by hand after I killed the wedged run
(a killed process cannot run `finally` — noted for the next session).

**Local:** 3 orphaned monitor tails (flagged by Bret) stopped; they were local
`tail -f` processes, **zero cost**, no Azure exposure. Temp files holding the VM
admin password / SAS tokens are written outside the repo and shredded in `finally`;
`validation-runs/` is gitignored. No key, token, password, or SAS appears in this
report. **No provider key was ever placed on any VM** (Task 0 proved none is needed).

---

## 8. END-OF-SESSION GATE

**Task accounting:** §5. Every numbered item CAPTURED/DONE except the deliberately
out-of-scope ones. The **deliverable — root cause with evidence — is achieved.**

**Delta security sweep.** Product code: **unchanged** — this was a diagnostic; the
only commits are harness/diagnostic scripts and lessons. Nothing was weakened to make
anything pass; no control was disabled to get evidence. The diagnostic **observes
only** (no start/restart/repair — a probe that fixes the box destroys the evidence).
`automount=false` was left intact and worked *against* my own probe (§6.10), which is
the control behaving correctly. New secret-handling is **stricter**: run-command
scripts now go through temp files outside the repo, shredded in `finally`.
Bret's daily driver: **untouched** — nothing this session ran against it.

**Delta bug review — found, not fixed, carded:**
1. **`openclaw gateway install`'s failure is swallowed** (`setup.ps1:1921-1923` WARN)
   and the three dependent calls are `|| true`. This is *the* defect: it converts a
   precise failure into a misleading one 120 s later. **This is the fix job.**
2. **`INSTALLER_EXIT=0` on a failed install** (§6.9) — the harness's success signal is
   unreliable; it should assert on setup.ps1's exit code / `INSTALLER_DONE=failure`.
3. **Both `enable-linger` calls are `|| true`** — pre-existing, still open, still out
   of scope (and now known to be irrelevant to this bug).
4. **Keepalive registered at 2771, after the gateway step at 2720** — latent ordering
   oddity; the session-exit shutdown does fire during install (§3), just not at 8c.
5. **`diag-8c.ps1` reads the wrong setup.ps1 log path** (`C:\Program Files\ClawFactory
   Secure Setup\` vs the real `C:\Program Files\ClawFactory\`) — which is why §4's
   probe 3 is still owed. Fix with the next run.

**Card #124:** → **done** for this diagnostic (root cause captured with evidence).
The fix is a new, separate job, gated on §4's one probe.

**Next session, in order:** (1) run §4's three probes — one VM, ~$0.13 — to learn
*why* `openclaw gateway install` fails; (2) fix that, and make the swallowed rc
fail loud at the point of failure; (3) only then re-run the suite for the headline
isolation claim, which remains **unproven** and is still the project's #1 owed item.

---

## 9. Commits

```
0a05c72  fix(harness): teardown deletes by explicit name, proof is unfiltered (L3)
eb4a480  feat(diag): in-session payload mode + step-8c diagnostic bundle
9e4db5a  fix(harness): L5 -- a stream redirect turned az WARNINGS into fatal errors
327eb85  fix(diag): pass the bundle as base64, not via /mnt/c -- automount is off
d4c09fc  fix(harness): stage the payload via blob+SAS, not inline through --scripts
8a114bb  fix(harness): L6 -- check $LASTEXITCODE; a failed az call was passing silently
a050ffa  fix(harness): wait for the VM agent before run-command (trap 6, made cheap)
d1e205b  fix(harness): run-command scripts must be ONE LINE (L2 sharpened)
a0722f8  fix(harness): route all run-command through Invoke-Rc (@file + both streams) -- L7
b39cd58  fix(diag): retrieve the bundle via blob (message truncates at ~4KB) + H alias bug
```
Lessons file gained **L5, L6, L7** and a sharpened **L2**. The harness that entered
this session could not have produced this evidence; the one leaving it did.
