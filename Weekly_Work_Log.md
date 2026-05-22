# ClawFactory Weekly Work Log

---

## Week of Monday May 18, 2026

### Completed

- v1.0.27 full headless validation cycle (cfv-126 through cfv-128) -- bisect confirmed
  reboot-resume regression; Scheduled Task mechanism (AtStartup, SYSTEM) validated
- v1.0.26 build + full headless validation cycle
  Completed across cfv-126 through cfv-130 -- shipped as v1.0.28
- v1.0.28 SHIPPED (commit 6f4f3f2) -- wsl --update preflight + resume-flag hardening
  - Fix 1 verified in log: wsl --update exit 0, ran before wsl --install
  - Fix 2 code-complete (reboot not triggered on cfv-130)
  - Manual RDP install on cfv-130 -- run-command/WSL per-user mechanism blocked headless
  - All 20 checkpoint steps + AgentBootstrap + gateway health gate passed
- v1.0.29 in progress: WSL console fix + PostInstall smoke task + baseline rebake queued

### In Progress

- Baseline image rebake (clawfactory-win11-baseline) -- carry to v1.0.30 session
  Deferred from v1.0.28; current baseline predates wsl --update preflight

### Notes / Blockers

- run-command/WSL per-user mechanism blocked headless on cfv-130: `az vm run-command invoke`
  runs as SYSTEM which has no WSL user session; wsl.exe calls that require a user context
  (distro start, bash as clawuser) silently fail or hang. Workaround used: RDP for
  install, headless for pre/post checks.
- PostInstall smoke task (v1.0.29 Fix 2) works around this by firing AtLogon in a real
  user session. WSL-dependent smoke checks will pass when cfvadmin logs in; non-WSL
  checks (firewall, checkpoint, wslconfig, scheduled task) can be verified headlessly.

---

## Open Items for v1.0.30

1. Baseline image rebake (carried from v1.0.28 / v1.0.29)
2. Smoke suite WSL checks -- need user-context execution (AtLogon fires in user session;
   Start-ScheduledTask from SYSTEM does not have WSL access)
   Fix options: wire cfvadmin auto-logon for validation VMs, or accept install-log
   evidence as authoritative and drop WSL smoke checks from headless suite
