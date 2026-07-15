# Step 8c gateway failure — local diagnosis — 2026-07-15

**STOPPED AT THE TASK-1 GATE. The linger hypothesis is FALSIFIED. No fix was built.**

The gate did its job: the fix this session was scoped to build — "add
`loginctl enable-linger clawuser` before the gateway starts" — **already exists in
the product, in two places, and already succeeds.** Building it would have shipped
a no-op and cost an Azure cycle to discover.

A second, harder finding: **the local scratch-distro method cannot reproduce this
class of bug at all** while the daily driver is running. Details in §3.

---

## 1. Ledger

| # | Item | Result |
|---|---|---|
| Gate 1 | Read `CLAUDE_ClawFactory.md` (step-ordering, dashboard rule, misleading errors) | **DONE** |
| Gate 2 | Read cfv-0715 close-out (`03d4059`) | **DONE** |
| Gate 3 | Fetch #124 comments | **DONE** — Blocked; no scope-changing comments |
| **Task 0** | **Gateway service model: `--user` or `--system`?** | **CONFIRMED `--user`** (§2) |
| 1.1 | Scratch distro + systemd | **DONE** — `cf-scratch`, `is-system-running: degraded`, PID1 systemd, logind active |
| 1.2 | Reproduce Linux-side path (clawuser, BaseDeps, linger) | **DONE** |
| 1.3 | Capture mechanism verbatim | **DONE** (§3) |
| **1.4** | **Gate: hypothesis confirmed?** | **NOT CONFIRMED — FALSIFIED** (§3). Stop condition "linger already on" met. |
| 2.x | Surgical fix | **NOT ATTEMPTED — gate** |
| 3.x | Prove fix on clean scratch | **NOT ATTEMPTED — gate** |
| 4.x | Regression safety | **NOT ATTEMPTED — gate** |
| 5.x | Version bump / tag | **NOT ATTEMPTED — no behavior change to version** |
| 6.1 | Scratch teardown + proof | **DONE** (§6) |

---

## 2. Task 0 — the gateway is a systemd `--user` service (confirmed)

From `setup.ps1` (the failing step drives it exclusively through `--user`):
```
setup.ps1:1918: openclaw gateway install --force --port 8787
setup.ps1:1926: systemctl --user daemon-reload
setup.ps1:1929: systemctl --user enable openclaw-gateway.service
setup.ps1:1932: systemctl --user restart openclaw-gateway.service
setup.ps1:1939: state="$(systemctl --user is-active openclaw-gateway.service 2>/dev/null || true)"
```
From the live unit on the working box:
```
unit path: /home/clawuser/.config/systemd/user/openclaw-gateway.service
[Install]
WantedBy=default.target        <-- --user install target (system units use multi-user.target)

--- is there any SYSTEM unit for the gateway? ---
  (none - confirms --user only)
```
So the linger/user-session hypothesis was **viable in principle**, and Task 1 was
the right next step. It is the evidence, not the model, that killed it.

---

## 3. Task 1 — what the reproduction actually showed

### 3a. The hypothesis is falsified: linger is already on, and already called twice

`loginctl enable-linger clawuser` is invoked **twice before the gateway ever
starts**, and the second call is **inside the failing step itself**:
```
line 1204 -> Step-InstallBaseDeps            (step 6, before the gateway)
line 1735 -> Step-PreinstallGatewayRuntime   (sub-block d, before the start at 1918)
```
Reproduced verbatim on the scratch distro, running the installer's own commands:
```
--- the linger call, exactly as the installer runs it (note: || true = silent) ---
enable-linger raw rc=0
--- loginctl show-user clawuser ---
UID=1000
Name=clawuser
State=opening
Linger=yes                   <-- ALREADY ON
--- linger marker file ---
-rw-r--r--  1 root root    0 Jul 15 14:38 clawuser
```
**Task 2's fix already exists and already works.** Per the gate's explicit stop
list ("linger already on"), this session stops here.

### 3b. The real mechanism on the scratch box: `user@1000` dies with `219/CGROUP`

```
Process: 237 ExecStart=/lib/systemd/systemd --user (code=exited, status=219/CGROUP)
Main PID: 237 (code=exited, status=219/CGROUP)
user@1000.service: Failed to kill control group /user.slice/user-1000.slice/user@1000.service,
                   ignoring: Input/output error
Failed to start User Manager for UID 1000.       (looping)

--- XDG_RUNTIME_DIR present? ---
  ls: cannot access '/run/user/1000': No such file or directory
--- can systemctl --user be reached the way setup.ps1 does it? ---
  Failed to connect to bus: Operation not permitted
```
`219/CGROUP` = the user manager cannot set up its cgroup. Downstream, `/run/user/1000`
never exists and `systemctl --user` cannot reach a bus — which is exactly the shape
that would break `systemctl --user restart openclaw-gateway` at 8c.

**But this is not (yet) the Azure cause — see 3c.**

### 3c. The scratch reproduction is CONTAMINATED and cannot answer the question

```
Bret's Ubuntu (WORKING):   user@1000: active    boot_id: e993d27b-797f-4d2d-919a-7d04bfeeb846
cf-scratch  (FAILING):     user@1000: failed    boot_id: e993d27b-797f-4d2d-919a-7d04bfeeb846
cf-scratch PID1 cgroup ns: cgroup:[4026531835]   (host root ns -- NOT its own)
kernel: 6.6.114.1-microsoft-standard-WSL2
```
**Identical `boot_id` and a shared cgroup namespace.** WSL2 runs every distro in a
single utility VM; the scratch distro's PID 1 is not in its own cgroup namespace, so
two systemd instances contend for `/user.slice/user-1000.slice`. The first distro
(Bret's Ubuntu) owns it and works; the second (`cf-scratch`) fails `219/CGROUP`.
Corroborating: `ss -ltnp` inside `cf-scratch` listed **Ubuntu's** 8787/8788 — a
shared network namespace, same VM.

**cfv-0715 had exactly one distro.** So `219/CGROUP` here is an artifact of the test
method, not evidence about the clean-install failure. Reporting it as the root cause
would be a fabrication.

### 3d. Bonus: the "restore the Docker login shell" fix is also unproven

The old Docker step ran `su - clawuser -c 'dockerd-rootless-setuptool.sh install'` —
a PAM login shell, the side effect the removal deleted. Tested directly:
```
  login shell ran as clawuser; XDG_RUNTIME_DIR=/run/user/1000
    after login shell: /run/user/1000 -> /run/user/1000     <-- created
    after login shell: user@1000 -> failed                  <-- STILL failed
    after login shell: State -> State=closing
```
The login shell creates the runtime dir (via the separate `user-runtime-dir@1000`
unit) but does **not** rescue `user@1000`. So the obvious second-guess fix — "put the
login shell back" — has no evidence behind it either. (On the contaminated box; see 3c.)

---

## 4. What this means for the Azure failure

**The cause of cfv-0715 remains UNCONFIRMED**, and both candidate fixes are now
evidence-free:
- "Add enable-linger" — **already present twice, rc=0, Linger=yes**. Dead.
- "Restore the Docker `su -` login shell" — creates `/run/user/1000` but does not
  start `user@1000`. Unsupported.

**Why it cannot be settled locally:** a faithful reproduction needs `cf-scratch` to be
the *only* systemd distro in the WSL VM. That requires `wsl --shutdown` — which stops
Bret's gateway and drops the keepalive task — i.e. touching the daily driver, which
this session forbids. A single-distro machine is, by definition, the Azure VM.

**Recommended next move (cheap, ~$0.10, and it is a DIAGNOSTIC not a fix):** re-run
the existing Azure harness on one VM and, at the failure point, capture what the
current failure dump omits. `Step-PreinstallGatewayRuntime` already emits
`GW-JOURNAL / GW-STATUS / GW-PORT / GW-TMPLOG` (all returned `0` on cfv-0715 —
i.e. the dump told us nothing). Add, to that same failure path:
```
loginctl show-user clawuser            # Linger / State
systemctl status user@1000.service     # is the user manager even up?
journalctl -u user@1000.service -n 30  # WHY it failed (e.g. 219/CGROUP?)
ls -ld /run/user/1000                  # XDG_RUNTIME_DIR
su clawuser -s /bin/bash -c 'systemctl --user is-system-running'
```
That single instrumented cycle returns the actual cause. Then, and only then, build
the fix. Adding this instrumentation is deliberately **not** done in this session —
the gate says stop, and better diagnostics are a change of their own.

**Separate real gap, found in passing (not fixed):** both linger calls are
`loginctl enable-linger clawuser || true`. If `enable-linger` ever fails on a real
box, **nothing notices** — it is silent, and the install proceeds to a gateway start
that then fails 120 s later with a message that points at the gateway rather than at
the session. This is a member of the fail-loud family the installer otherwise
follows. Worth fixing regardless of the root cause; not in scope today.

---

## 5. SURPRISES

1. **The fix I was sent to build was already in the code — twice — including inside
   the very step that fails.** Reading `setup.ps1` for the insertion point is what
   revealed it. The gate caught this before an Azure cycle, which is precisely what
   it was designed for.
2. **`loginctl enable-linger` returning rc=0 and `Linger=yes` does not mean the user
   manager is running.** Linger is a *policy flag*; it is not proof of a live
   `user@1000`. Any future check must assert the manager, not the flag.
3. **A scratch WSL distro is not an isolated machine.** Same VM, same kernel, same
   `boot_id`, same cgroup namespace, same network namespace — the scratch distro even
   saw the daily driver's listening ports. "Test it on a throwaway distro" is invalid
   for anything touching systemd-user, cgroups, or ports. This invalidates the
   session's core method, and it is better to say so than to ship a conclusion drawn
   from a contaminated box.
4. **Even the fallback hypothesis died.** The Docker `su -` login shell creates
   `/run/user/1000` but leaves `user@1000` failed — so "put the side effect back" was
   never the answer either.

## 6. Resource ledger + teardown proof

```
=== Task 6: unregister the scratch distro ===
The operation completed successfully.

=== 6.1 PROOF: no scratch distros remain ===
  NAME      STATE           VERSION
* Ubuntu    Running         2
```
`C:\cf-scratch` removed; `/tmp/repro.sh`, `/tmp/why.sh` removed; repo tree: 0 changes
before this report. **No Azure resources were created — this session cost $0.**

**Bret's daily driver: untouched and healthy at exit** (only ever read, plus one
read-only `curl`):
```
  gateway http=200
  user@1000: active
  factory  hash==pin: YES   (cd0199d52b9e...)   lsattr ----i---------e-------
  injected hash==pin: YES   (6d211ded10ac...)   lsattr ----i---------e-------
```
`wsl --shutdown` was never issued; the keepalive and `ClawFactory WSL Host` task were
not disturbed. Only `wsl --terminate cf-scratch` was used.

## 7. END-OF-SESSION GATE

**Task accounting:** Gate 1-3 DONE · Task 0 **CONFIRMED (`--user`)** · Task 1.1-1.3
DONE · **Task 1.4 NOT CONFIRMED → STOP** · Tasks 2/3/4/5 **NOT ATTEMPTED (gate)** ·
Task 6 DONE.

**Resource ledger:** one scratch distro (`cf-scratch`) created and unregistered;
`wsl -l -v` proof above shows only `Ubuntu`. `C:\cf-scratch` deleted. No Azure, no
cost. No leftover scratch files.

**Delta security sweep:** **no product code was changed this session** — the only
commit is this report, so there is no diff to sweep. Nothing was weakened; no new
egress, credential, or permission. No key or token material appears in this report.
The daily driver's SOUL files remain root-owned, immutable, and hash-matched (§6).

**Delta bug review:** the falsified hypothesis is recorded as falsified (§3a), the
contaminated method is recorded as contaminated rather than dressed up as a result
(§3c), the second-guess fix is recorded as equally unsupported (§3d), and the silent
`|| true` linger gap found in passing is logged for a future session (§4). Nothing
dropped, and nothing concluded beyond what the evidence supports.

**Card #124: remains BLOCKED** — reason: root cause unconfirmed; the assumed cause is
disproven; the next step is one instrumented Azure diagnostic cycle (§4), not a fix.
