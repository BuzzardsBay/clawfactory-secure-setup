# v1.3.5 validation runbook (card #258)

The run owed since card #245. Everything below is staged and syntax-checked on the
build machine; nothing here has been executed against a VM yet.

**Artifact under test:** `Output\ClawFactory-Secure-Setup.exe`, v1.3.5,
unsigned sha256 `2c3e50f07afbdd67894d9fad76916e38666d00f6a30f5f3b3be9359112e38d55`,
440,599,315 B. Authenticode `Valid`.

**Reference artifact for the A/B:** `validation/sp-prefix-fw.sh`, sha256
`bee579419e262c7028b53b8fc09388562e8bc48427a7b3d26a2364215b404da0`, rendered from
commit `9710c5a` so it is provably the shipped 1.3.4 text.

## Environment, not negotiable

- `Standard_D2s_v4`. DSv5 quota in westus2 is zero; do not "upgrade" the size.
- Image `clawfactory-win11-baseline-v2`, resource group `clawfactory-validation`.
- ONE `az vm run-command invoke` at a time.
- Every WSL probe needs the interactive auto-logon session. Auto-logon is ONE-SHOT:
  after any reboot a human logs in over RDP and starts the runner by hand.
- `/var/tmp`, never `/tmp`.
- `/mnt/c` is ABSENT BY DESIGN (`[automount] enabled=false`). Every phase here uses
  the `\\wsl$` 9p file channel. A probe needing `/mnt/c` would only work on a
  broken install.
- RDP scoped to a single /32, never `0.0.0.0/0`.
- Pass `-OutDir` explicitly to teardown. Deallocate at every human handoff.

## Task 0, before provisioning

Delete all prior FAIL VMs and their OS disks. `az vm delete` does NOT remove the OS
disk, NIC, public IP or NSG: sweep them explicitly, **NIC first**, because it
references the pip and the nsg. Then prove the starting state with an UNFILTERED
resource list. Expected residual: the storage account, the VNET, and the two
baseline images. Nothing else.

## Phase order

| # | Phase | Script | Sentinel | Notes |
| --- | --- | --- | --- | --- |
| 1 | Clean install (provider = claude) | existing install harness | `INSTALLER_DONE` | matrix test 1 |
| 2 | Provider gate | `interim-v135-providergate.ps1` | `PROVIDERGATE_PROBE_COMPLETE` | matrix tests 2, 3 |
| 3 | Switch-provider A/B | `interim-v135-switchprovider.ps1` | `SWITCHPROVIDER_PROBE_COMPLETE` | matrix tests 4, 5, 6 |
| 4 | Toolchain regression | `interim-v130-toolchain.ps1` | `TOOLCHAIN_PROBE_COMPLETE` | TC.1 to TC.8 |
| 5 | MANUAL panel checks | `stage-manual-cards.ps1` | by hand | five checks, by a human |
| 6 | REBOOT, then re-run 3 and 4 with `-PostReboot` | | | matrix test 10 |
| 7 | Harness self-test on the box | `harness-selftest.ps1` | `HARNESS_SELFTEST_COMPLETE` | matrix test 11 |

### Phase 2, provider gate

```bash
powershell -File validation/interim-v120-job.ps1 -PhaseScript validation/interim-v135-providergate.ps1 -JobName providergate -Sentinel PROVIDERGATE_PROBE_COMPLETE -VmName cfv-169
```

Level 1 (the gate's own probe, rigged and unrigged) always runs and costs seconds.
Level 2, the installer's loud abort, needs `-ScriptArgs '-RunFullInstallControl'`
and costs a full install. **If level 2 is not run, the results file carries an
explicit INFO row saying so.** A skipped control and a passed control must never
look the same.

Matrix test 3 needs a SECOND install with the provider deferred (`-Provider later`).
Run that phase with `-ScriptArgs '-DeferredProvider'` against that box.

### Phase 3, switch-provider A/B

```bash
powershell -File validation/interim-v120-job.ps1 -PhaseScript validation/interim-v135-switchprovider.ps1 -JobName switchprovider -Sentinel SWITCHPROVIDER_PROBE_COMPLETE -VmName cfv-169 -ExtraFiles validation/sp-prefix-fw.sh
```

`-ExtraFiles` is REQUIRED. Without the 1.3.4 reference the pre-fix arm cannot run,
and test 4 loses the reference it is compared against.

The phase holds the toolchain toggle OFF throughout, measures the baseline, runs
the 1.3.4 block (defect reproduced), runs the installed 1.3.5 block (defect
absent), then turns the toggle ON to prove the probe discriminates. It leaves the
box with the toggle OFF for the reboot pass.

## What must be true for any of this to count

- Every block assertion carries a control that must FAIL in the same run.
- Every injected fault carries a control proving the FAULT LANDED.
- The reachability probe is calibrated in BOTH directions in every measurement: a
  destination that must connect AND one that must be refused. A drop instrument
  proven only against a must-drop target passes whether the log rule sits above or
  below the accepts. That error produced a phantom ship-blocker on cfv-167.
- Read probe STDERR (`.out`), not just the transcript, whenever a phase produces
  less output than expected, BEFORE tearing the VM down.
- Verdict vocabulary is PASS, FAIL, VOID, INFO and nothing else.
- Zero malformed verdict rows across every phase (matrix test 12).

## Known limits, recorded before the run rather than discovered in it

- The provider gate does NOT cover the cfv-167 symptom. Those turns failed while a
  TCP connect would have succeeded, so the gate would have passed there.
- The A/B runs the shipped script's FIREWALL BLOCK, not the whole
  switch-provider.ps1. The rest of that script rotates credentials and is not the
  subject; isolating the block keeps the provider API key out of the run entirely.
- Level 2 of the provider-gate control observes the installer aborting. Level 1
  only calibrates the measurement.
