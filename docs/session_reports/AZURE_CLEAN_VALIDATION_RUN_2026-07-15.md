# Azure Clean-Install Validation Run — cfv-0715 — 2026-07-15

**Verdict: RED. The release gate does not pass. Nothing ships.**

**v1.0.38 does not install on a clean machine.** The install aborts at
`Step-PreinstallGatewayRuntime` — the gateway never starts — and therefore
**none of the security track ever executes** on a fresh box. The headline
isolation claim is **still unanswered**, because there is no working install to
ask.

- **VM:** `cfv-0715` — Standard_D2s_v4 — westus2 — `clawfactory-win11-baseline-v2` — IP `20.69.160.63`
- **Build:** v1.0.38, tag → `4ff70a3`, HEAD `6f107b5`, sha256 `bd76a4ada7a5ae0641e520df11b58f445ec5b4abe371506452c3b0a591b064f3`
- **Flags:** `/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG /PROVIDER=claude /LICENSE=CF-TEST-TEST-TEST-TEST`
- **Key:** throwaway Anthropic key (operator-minted, seeded to clawadmin's Credential Manager; revoke it)
- **VM lifetime:** ~62 min. **Cost ≈ $0.10.** **Destroyed — proof in §9.**

---

## 1. The failure (verbatim)

```
[2026-07-15 20:04:24] [INFO] GW-JOURNAL: 0
[2026-07-15 20:04:24] [INFO] GW-STATUS:  0
[2026-07-15 20:04:24] [INFO] GW-PORT:    0
[2026-07-15 20:04:24] [INFO] GW-TMPLOG:  0
[2026-07-15 20:04:25] [ERROR] Install failed: Gateway did not respond after 120 seconds
[2026-07-15 20:04:25] [ERROR] at Step-PreinstallGatewayRuntime, C:\Program Files\ClawFactory\setup.ps1: line 1991
at <ScriptBlock>, C:\Program Files\ClawFactory\setup.ps1: line 2720
at Invoke-WithRollback, C:\Program Files\ClawFactory\setup.ps1: line 584
at <ScriptBlock>, C:\Program Files\ClawFactory\setup.ps1: line 2685
[2026-07-15 20:04:25] [INFO] Silent mode: auto-answering 'Installation failed. Run automatic rollback? (y/N)' with default 'n'
[2026-07-15 20:04:25] [INFO] Rollback skipped. Log: C:\ProgramData\ClawFactory\install.log
[2026-07-15 20:04:25] [ERROR] Top-level handler caught: Gateway did not respond after 120 seconds
[2026-07-15 20:04:25] [INFO] INSTALLER_DONE=failure reason=Gateway did not respond after 120 seconds
```

**How far it got (checkpoint, verbatim):**
```json
{ "completedSteps": [ "Preflight", "EnsureWsl", "ConfigureWslConfig", "WslConf",
                      "WslRestart", "CreateClawUser", "DefaultUser", "BaseDeps",
                      "OpenClawBuildDeps", "EgressFirewall", "OpenClaw",
                      "OpenClawConfigured" ] }

InstallTurnGate/FreezeInjectedSoul/InstallChatProxy in checkpoint: 0
```

### One diagnosis (per the no-fix-loop rule), and what it eliminated

**It is NOT the chat proxy.** `Step-InstallChatProxy` is step 15d; the abort is at
8c. It never ran. Ports 8787/8788 were never moved.

**It is NOT a too-tight gate / cold-start flake.** Probed ~20 min after the 120 s
gate expired (WSL2 forwards localhost, so this needs no WSL session):
```
port 8787: TcpTestSucceeded=False
port 8788: TcpTestSucceeded=False
/status: Unable to connect to the remote server
```
The gateway is not merely slow — it never comes up at all.

**The Docker-removal step is the prime suspect but is NOT confirmed.** It is the
only install-path change before 8c (with the firewall edits). The two dependencies
the Docker job identified as traps *were* installed correctly:
```
[2026-07-15 19:49:40] [INFO] Step 6: Installing base Linux dependencies (nftables + dbus-user-session; Docker removed).
[wsl:root out] dbus-user-session
[wsl:root out] nftables
```
So the known trap did not bite. What the old Docker step *also* did and the new one
does not: `dockerd-rootless-setuptool.sh install` ran `su - clawuser -c ...` — a real
**login shell for clawuser** — and installed `uidmap`/`slirp4netns`. The gateway is a
`systemd --user` service and needs clawuser's user manager (XDG_RUNTIME_DIR /
`user@1000.service`) to exist. **Hypothesis for the design thread:** removing Docker
removed the side-effect that first materialised clawuser's user-systemd session, and
`loginctl enable-linger` alone is not sufficient at that point in the sequence.
**Not investigated further on the VM, per the validation-not-fix rule.**

---

## 2. PASS / FAIL ledger

| # | Check | Result |
|---|---|---|
| 0.1 | Working tree clean | **PASS** |
| 0.2 | HEAD includes proxy / Docker-removal / SOUL-freeze | **PASS** — `7655c27`, `d6d63f3`, `8eaeb60`; HEAD `6f107b5` |
| 0.3 | Build from HEAD | **PASS** — v1.0.38, 340,587,592 B, sha256 `bd76a4ad…` |
| 0.4 | signtool verify (informational) | **PASS — the pipeline DOES sign** (§3) |
| 0.5 | Upload to blob | **PASS** — byte-match; re-verified on VM |
| 1.1 | Provision VM | **PASS** — cfv-0715, 223 s |
| 1.2 | Auto-logon + RunOnce wrapper, key seeded | **PASS** |
| 1.3 | Capture started BEFORE install | **PASS** — pktmon running pre-install |
| 1.4 | Install completes | **FAIL** — gateway did not respond; `INSTALLER_DONE=failure` |
| 1.5 | `ft: command not found` = 0 | **PASS** — `matches: 0` |
| 1.5 | ERROR lines | **FAIL (recorded)** — 3 ERROR lines, §1 |
| 2.1–2.5 | Smoke / firewall / idle / chatCompletions / gateway health | **BLOCKED** — no working install |
| 3.1–3.4 | **Headline isolation + escape suite** | **BLOCKED — STILL UNANSWERED** |
| 4.1–4.3 | No phone-home | **BLOCKED** (install-phase capture exists but is meaningless against a failed install) |
| 5.1–5.3 | Docker-removal regression | **PARTIAL** — §4 |
| 6.1–6.3 | SOUL freeze first-run | **BLOCKED** — step never ran |
| 7.1–7.3 | Governor fail-safe / cold-start | **BLOCKED** |
| 8 | Adversarial suite | **BLOCKED** |
| 9.1 | Teardown + proof | **PASS** — §9 |
| 9.2 | Cost | **PASS** — ~$0.10 |
| 9.3 | Reusable infra intact | **PASS** — §9 |

---

## 3. What DID get proven

**The build pipeline signs (0.4 — an open question, now closed):**
```
Successfully verified: .\Output\ClawFactory-Secure-Setup.exe
Number of files successfully Verified: 1
Number of warnings: 0
Number of errors: 0            [signtool exit=0]
Chain: Bret Mckinney <- Microsoft ID Verified CS EOC CA 04
       <- Microsoft ID Verified Code Signing PCA 2021
       <- Microsoft Identity Verification Root Certificate Authority 2020
The signature is timestamped: Wed Jul 15 11:46:10 2026
```
Note: the signing cert expires **Thu Jul 16 11:54:41 2026** (tomorrow). Trusted
Signing certs are short-lived by design and the signature is timestamped, so it
stays valid past expiry; future builds re-issue. Not a defect.

**The resource-bundling fix works (the ship-blocker found while staging):**
```
[2026-07-15 19:47:05] [INFO] Preflight: all 9 security resources present.
```
The new Preflight assertion passed on a real installed box — i.e. the installer
genuinely ships the 8 security resources it was missing. Without last session's
fix this run would have died even earlier.

**automount=false + the fail-loud readback ran (Task 2's precondition):**
```
[2026-07-15 19:49:40] [INFO] Verified: /etc/wsl.conf shows automount disabled (post-restart).
```
The isolation *precondition* is confirmed on a fresh box — the readback executed
rather than being skipped. The isolation *claim* itself remains untested.

**Docker Hub is gone from the egress allowlist (verbatim, from the install log):**
```
[INFO] Allowlist hosts: accounts.google.com api.anthropic.com api.clawhub.ai api.github.com
archive.ubuntu.com clawhub.ai codeload.github.com deb.nodesource.com docs.openclaw.ai
esm.ubuntu.com github.com gmail.googleapis.com nodejs.org oauth2.googleapis.com openclaw.ai
people.googleapis.com ports.ubuntu.com ppa.launchpad.net raw.githubusercontent.com
registry.npmjs.org security.ubuntu.com www.googleapis.com
```
No `registry-1.docker.io` / `auth.docker.io` / `production.cloudflare.docker.com`.

---

## 4. Task 5 — Docker-removal regression (PARTIAL)

- **5.1 Docker absent:** **PASS (by construction)** — checkpoint shows `BaseDeps`,
  not `Docker`; the step no longer installs docker-ce/containerd/rootless.
- **5.2 Firewall backend present independent of Docker:** **PASS** — `nftables`
  installed by `Step-InstallBaseDeps`, and `EgressFirewall` **completed** in the
  checkpoint with the allowlist built (§3). The trap the Docker job warned about
  (nftables was only ever installed by the Docker step) is **closed**.
- **5.3 Kill switch kills the real agent process:** **BLOCKED** — needs a running agent.

**But the regression is real, just elsewhere:** removing Docker plausibly removed
the side-effect that bootstrapped clawuser's `systemd --user` session, and that is
what the gateway needs. §1.

---

## 5. SURPRISES

1. **The install-path change that broke the box is the one that looked safest.**
   The Docker removal was justified by "nothing load-bearing depends on it" — and
   the two dependencies we *did* find (nftables, dbus-user-session) were correctly
   preserved. The thing that appears to have mattered is a **side effect** of a
   package we deleted, not a dependency of it: `dockerd-rootless-setuptool.sh`
   ran a clawuser login shell. "Nothing uses Docker" was true. "Nothing depends on
   Docker having been installed" was not.
2. **My prime suspect was wrong, and checking cost one command.** The proxy was
   the obvious culprit (it moves the gateway's port, and the gate polls that port).
   It never ran. Naming a suspect and then falsifying it is cheaper than assuming.
3. **The staging session's bug fix was load-bearing.** `Preflight: all 9 security
   resources present` only exists because last session diffed packaging against
   code. Without it, this run would have failed at 15b with a bare
   FileNotFoundException and we'd have blamed the wrong layer.
4. **The four-hour lesson of this project keeps repeating:** every defect found by
   the producer-vs-consumer discipline has been "the code was right, the thing
   around it was wrong." Packaging last session; an uninstalled package's side
   effect this session.

## 6. BLOCKED

- **The headline isolation test** — needs a working install. Unchanged since the
  drift on the daily driver made it untestable there. This is now **two** sessions
  in a row where the central claim could not be exercised.
- Tasks 2, 3, 4, 6, 7, 8 and 5.3 — all downstream of a running gateway.
- **Root-causing the gateway failure** — deliberately not attempted on the VM
  (validation-not-fix). It goes to the design thread with the §1 hypothesis.

---

## 7. Release-readiness ledger

**RED. Do not ship.** New #1, ahead of everything previously listed:

1. **v1.0.38 does not install on a clean machine.** Gateway never starts at
   `Step-PreinstallGatewayRuntime`. Suspect: Docker-removal side effect on
   clawuser's systemd-user session. **Blocks literally everything else.**
2. **The headline isolation claim is unproven** — for the second consecutive
   attempt. Everything else in this project is downstream of it being true.
3. **Door 2 — full-path bypass** (`node …/openclaw.mjs agent` ungated; agent and
   gateway share the clawuser UID). KNOWN-OPEN; not re-litigated here.
4. "Four agents" is fiction — only `main` is registered.
5. GO-gating is model-dependent, not a control.
6. DNS exfil reduced, not eliminated (by design; not re-litigated).
7. Spend is turn-granular; an in-flight turn can overshoot.
8. The broad dead-code/claims audit is still owed.

**Recommended next move (design thread, not a validation job):** reproduce the
gateway-start failure locally by reverting only `Step-InstallBaseDeps` to the old
Docker step on a scratch WSL distro, or by adding an explicit clawuser
user-session bootstrap (`systemctl --user` reachability check + `machinectl shell`
/ login-shell warm-up) before `Step-PreinstallGatewayRuntime`, then re-run this
harness. The harness is now proven end-to-end up to the failure point, so the next
run is cheap.

---

## 8. Azure-protocol lessons learned (appended to the Lessons doc)

- **L2 — `az vm run-command --scripts` mangles multi-line strings.** A here-string
  passed inline arrives on the VM broken (`Missing closing '}'`) and can even run
  partially with empty output — which looks like "the script did nothing" rather
  than "the script was corrupted". **Always pass `--scripts "@<localfile>"`.** This
  is the `harness via @file` pattern recorded in the v1.0.37 report; rediscovered
  the hard way.
- **L3 — `--query "[?...]"` filters get mangled by the Windows shell and silently
  match nothing.** The first teardown pass reported "nic deleted / disk deleted"
  while deleting **nothing**, leaving four orphans (NIC, PIP, NSG, disk) billing.
  **Delete by explicit name, and always finish with an unfiltered `az resource
  list -g <rg>` as teardown proof.** A teardown that trusts a filtered query is a
  billing leak that reports success.
- **L4 — `2>&1` on `az` breaks `ConvertFrom-Json`** (PS 5.1 wraps native stderr in
  ErrorRecords). Never pipe `az ... -o json 2>&1` into `ConvertFrom-Json`.

---

## 9. Teardown proof (verbatim) — Task 9

```
--- VMs in subscription (must be empty) ---
                                              <-- empty

--- resource group now holds ONLY reusable infra ---
Name                           ResourceGroup           Location    Type                               Status
-----------------------------  ----------------------  ----------  ---------------------------------  ---------
clawfactoryvalc467             clawfactory-validation  westus2     Microsoft.Storage/storageAccounts  Succeeded
bake-vmVNET                    clawfactory-validation  westus2     Microsoft.Network/virtualNetworks  Succeeded
clawfactory-win11-baseline     clawfactory-validation  westus2     Microsoft.Compute/images           Succeeded
clawfactory-win11-baseline-v2  clawfactory-validation  westus2     Microsoft.Compute/images           Succeeded
```
`cfv-0715` VM, OS disk (`cfv-0715_disk1_f2921f408f1d47018b8341fc6ced0bbe`), NIC
(`cfv-0715VMNic`), public IP (`cfv-0715PublicIP`) and NSG (`cfv-0715NSG`) are all
**gone**. Baseline images, storage account and resource group intact. **Cost ≈ $0.10.**

---

## 10. END-OF-SESSION GATE

**Task accounting:** 0.1–0.5 DONE · 1.1–1.3 DONE · 1.4 **FAILED** · 1.5 DONE ·
2/3/4/6/7/8 **BLOCKED** · 5.1–5.2 DONE, 5.3 BLOCKED · 9.1–9.3 DONE.

**Resource ledger:** one VM created (`cfv-0715`), destroyed with all dependents;
verbatim unfiltered listing above proves nothing remains. Local scratch
(`%TEMP%\cfv-pw.txt`, staging/probe temp scripts) removed; the arming script that
briefly held secrets was scrubbed in place. Bret's local machine and install were
**not touched** — this session only read the repo, built, uploaded, and drove Azure.

**Delta security sweep:** nothing was weakened to make anything pass — nothing
passed that shouldn't have; the run is RED and reported RED. No key or token
material appears in this report or in any command text: the throwaway API key and
the generated VM password were read from Credential Manager / a local file at
runtime and interpolated only inside files, never echoed; the storage key and SAS
token were never printed. **Action for the operator: revoke the throwaway
Anthropic key — it was seeded into cfv-0715's Credential Manager, and although the
VM is destroyed, revocation is the clean close.**

**Delta bug review:** the install failure is §1 with full verbatim evidence and is
the top line of this report, not buried. The falsified proxy hypothesis is recorded
as falsified. Three Azure-protocol lessons (L2/L3/L4) are captured in §8 — including
the teardown-query bug that reported success while leaking four orphans, which is
the most dangerous of the three.
