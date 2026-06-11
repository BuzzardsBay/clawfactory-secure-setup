# ClawFactory v1.0.34 — Azure validation report (re-validate after v1.0.33 install crash)

**Date (UTC):** 2026-06-11
**VM:** cfv-135 — Standard_D2s_v4 — westus2 — public IP `20.59.23.77`
**Image:** `clawfactory-win11-baseline-v2` (Gen V2, Generalized, WSL 2.7.8.0 baked in)
**Installer:** `ClawFactory-Secure-Setup.exe` v1.0.34, source commit `f6ccee0`
  - size `340545441` bytes
  - sha256 `BD4D46CCB5CE58E902ECB88D130529F1B593CCCB5FF83B48278CC810B7FFCE35`
  - on-VM SHA-256 after download: **exact match** (no transit corruption)
**License key:** `CF-TEST-TEST-TEST-TEST`
**Install flags:** `/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG /PROVIDER=claude /LICENSE=CF-TEST-TEST-TEST-TEST`

## Overall: **FAIL** — but the v1.0.34 fix is verified, and the new blocker is a pre-existing timing issue, not a regression

**The two v1.0.34 code changes did their jobs:**
1. **The v1.0.33 install-blocking crash is GONE.** v1.0.33 died ~104 s in with "Cannot call
   UninstallSilent function during Setup" during Inno's uninstall-data recording. v1.0.34 (the
   `CurUninstallStepChanged` rewrite) ran the installer cleanly for **~17 minutes** all the way
   through every file-copy and `setup.ps1` step to the **final gateway health gate** — the
   crash never occurred. **Primary objective achieved.**
2. The smoke check #9 root fix is in the binary (not reached — see below).

**The install nonetheless ended `INSTALLER_DONE=failure`**, at the very last gate:
`reason=Gateway did not respond after 60 seconds` (`setup.ps1` line 1862,
`Step-PreinstallGatewayRuntime`). This is the **pre-existing 60 s gateway-health-gate timing
issue that v1.0.24 already flagged as "still not enough"** on cold/loaded VMs — now reproduced
deterministically on D2s_v4. It is unrelated to the `.iss`/smoke changes in v1.0.34.

Per the session rule (one fix iteration per session; if a further defect surfaces, capture
evidence, FAIL, and stop for review), I stopped here rather than fixing the gateway gate and
re-running a third time.

## The gateway-gate failure is a 7-second timing miss (journal proof)

The gateway **did start and bind port 8787** — the install just gave up ~7 s too early. From
the `openclaw-gateway` systemd journal (captured post-failure via a clawadmin-context probe):

```
00:56:49  [gateway] http server listening (6 plugins ...; 35.5s)   <- bound :8787
00:57:23  [gateway] startup model warmup timed out after 5000ms; continuing
00:57:23  [gateway] ready                                          <- fully ready
```

But the install's health gate, polling `/status`, expired here:

```
00:57:16  [ERROR] Install failed: Gateway did not respond after 60 seconds
```

The gateway became `ready` at **00:57:23 — 7 seconds after** the 60 s gate gave up at 00:57:16.
Startup was slowed by a 35.5 s plugin/runtime stage plus a model warmup that did a network
fetch (`[model-pricing] OpenRouter pricing fetch failed: TypeError: fetch failed`) and "timed
out after 5000ms". Then, because the install had already failed **before Step 16** (the
`ClawFactory WSL Host` keep-alive task was never registered), the next wsl-session exit
triggered the WSL systemd shutdown and the gateway got SIGTERM'd at 00:57:31 — so later probes
saw it restart-looping (an artifact of the missing keep-alive, not a separate gateway bug).

**Root cause:** the 60 s `/status` health-gate window in `Step-PreinstallGatewayRuntime` is too
short for the gateway's cold-start time on a 2-vCPU VM (~67 s here). Exactly v1.0.24's
recommendation #1, still unimplemented.

## What the install proved (functionally complete bar the gate)

From `install.log` (cfv-135):
- `==== ClawFactory Secure Setup - starting (provider=claude) ====`, Step 1 provider =
  **Anthropic Claude** — provider=claude end-to-end, no grok drift (`default model set:
  anthropic/claude-sonnet-4-6`).
- `wsl --update exit code: 0` → *"The most recent version of Windows Subsystem for Linux is
  already installed."* — **validates baseline-v2's WSL engine** (the whole reason for the v2
  rebake).
- No-reboot path taken (mirror of cfv-130): `WSL2 kernel loaded but Ubuntu missing`, offline
  rootfs import succeeded, `distroExistedPreInstall=False`.
- Ubuntu imported, clawuser created + **locked down (removed from sudo)**, Docker (rootless)
  installed, build deps installed, **egress firewall installed (provider=claude)**.
- `Bundled openclaw-install.sh hash logged: 3a617b73ea35ac23cf856ce9615b69d0ace4090d236e0a57bbc638f01676a9ce`
  (bundled, no URL drift).
- `OpenClaw installed successfully (2026.4.27)`; gateway systemd service installed + started +
  **bound :8787** (per journal) — only the 60 s health gate timed out.

## Task results

| Task | Result | Notes |
|---|---|---|
| 0 Cleanup + live state | PASS | Sub **Enabled** (live `az rest`). Deleted preserved cfv-134 disk (per approval). RG clean. |
| 1 Build + comprehension gate | PASS | `.iss` fix + smoke #9 fix applied; every `{code:}` ref in `[Run]/[UninstallRun]/[Files]/[Icons]` audited for phase-validity (only `GetUninstallFlags` violated, now removed). ISCC compile clean. New size/sha256 recorded. Committed `f6ccee0`, pushed **before** provisioning. |
| 2 Upload | PASS | `ClawFactory-Secure-Setup-1.0.34.exe` (340,545,441 B), 8 h SAS, HEAD-verified. |
| 3 Provision cfv-135 | PASS | D2s_v4, Security Standard, non-zonal, `bake-vmSubnet`, `--nsg-rule NONE` + Standard PIP, baseline-v2. Auto-logon + wrapper task configured. |
| 4 Install (user context) | **FAIL** | Auto-logon worked; on-VM hash exact; **UninstallSilent crash gone** — installer ran ~17 min to the gateway gate, then `INSTALLER_DONE=failure reason=Gateway did not respond after 60 seconds`. |
| 5 Collect + smoke | NOT REACHED | Smoke task (Step 17) registers *after* the gateway gate; install failed first. The smoke #9 root fix is in the binary but unexercised. |
| 6 Idle stability | NOT REACHED | |
| 7 Hidden keep-alive verify | NOT REACHED | `ClawFactory WSL Host` task (Step 16) never registered (post-gate). |
| 8 State files | PARTIAL PASS | Both state files were written before the failure: `wslconfig-state.txt = [created]`, `wsl-state.txt = [false]` — exactly as specified. |
| 9 Silent uninstall + verify clean | NOT REACHED | Headline feature still unvalidated end-to-end. |
| 10 Report + cleanup | PASS (this file) | FAIL-path cleanup done. |

## v1.0.34 change verification

- **`.iss` uninstaller rewrite (the blocker fix): VERIFIED WORKING.** No "UninstallSilent during
  Setup" error; the installer completed Inno's uninstall-data recording and ran `setup.ps1` to
  the end. (The uninstall path itself — `CurUninstallStepChanged` → `uninstall.ps1` — is still
  unvalidated because no install completed to uninstall from.)
- **Smoke check #9 (nft as root): in the binary, not exercised.** The binding root-verify
  exception rule therefore **remains in force** — it retires only on a validation run where
  check #9 passes natively (the user's condition #2). Not reached this cycle.
- **`{code:}` phase-audit + lessons-learned (conditions 3, 4): done.** `ClawFactory_Install_Lessons_Learned.md`
  L1 added; brace-comment-nesting gotcha also recorded (it bit the first compile attempt).

## Cleanup (FAIL path)

- VM `cfv-135` + NIC `cfv-135VMNic` + PIP `cfv-135PublicIP` + NSG `cfv-135NSG` deleted.
- **OS disk preserved: `cfv-135_disk1_d0ff7be58c36490eaedbac93bde41c61`** (Unattached, westus2).
  Holds the near-complete install (everything bar the gateway gate). Safe to delete — the
  decisive evidence (install.log + gateway journal + state files) was captured off the VM.
- RG `clawfactory-validation`: 2 images, `bake-vmVNET/bake-vmSubnet`, storage `clawfactoryvalc467`,
  one preserved disk. No VMs/NICs/PIPs/NSGs.
- Blob `ClawFactory-Secure-Setup-1.0.34.exe` retained in `installers`.
- Diagnostic artifacts kept locally (not in repo) under `C:\Users\bmcki\AppData\Local\Temp\cfv135\`.

## Release status

**v1.0.34 is NOT tagged and NOT released.** The install-blocking `.iss` crash is fixed and
verified, but the end-to-end install still does not complete because of the gateway
health-gate timing. No ship/code-signing decision until a full install **and** uninstall cycle
passes (Tasks 5–9 remain first-ever-unreached).

## Recommendations for v1.0.35 (next session — one fix at a time)

1. **Widen / harden the gateway health gate** (`Step-PreinstallGatewayRuntime`, `setup.ps1`
   ~line 1862). The gateway needed ~67 s here; the gate allows 60 s. Apply v1.0.24's standing
   recommendation: raise the window to **≥120 s** and decouple the checks — wait for
   `systemctl --user is-active` **then** poll `/status`, e.g. `for i in $(seq 1 60); do is-active
   && curl /status && exit 0; sleep 2; done`. Optionally pre-empt the 5 s model-warmup network
   stall (the OpenRouter pricing fetch fails closed but still burns time on first start).
2. **Re-validate the full cycle on a fresh cfv-136** (baseline-v2, D2s_v4). With the gate
   widened, expect to finally reach Tasks 5–9:
   - the **11-check post-install smoke** (first-ever real run) — watch check #9 (now root) to
     confirm it passes natively and the exception rule can retire;
   - the **silent uninstall + verify-clean** (Task 9) — the v1.0.33 headline feature, still
     never run end-to-end; this exercises the new `CurUninstallStepChanged` → `uninstall.ps1`
     path for the first time and may surface its own issues.
3. Keep "one fix iteration per session": land only the gateway-gate change, then re-run.
