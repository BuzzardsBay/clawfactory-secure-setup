<#
  Clean-install evidence probe. Runs ON the Azure VM, as clawadmin, in a real
  interactive session (auto-logon + RunOnce) -- NOT via az vm run-command, which
  is NT AUTHORITY\SYSTEM and cannot use WSL at all.

  KEYLESS BY DESIGN. No provider key is placed on the VM, so agent turns would
  401. That does not weaken the headline: the claim "the agent cannot see files
  you did not grant" is proven MODEL-INDEPENDENTLY here -- if /mnt/c is not
  mounted, nothing in the VM can read it, agent included. Asking a model to try
  is strictly weaker evidence than showing the mount does not exist. Checks that
  genuinely need a key are printed as NEEDS-KEY, never as PASS.

  Output is plain text, harvested by azure-validate.ps1.
#>
$ErrorActionPreference = 'Continue'
function W($m) { Write-Output $m }
function Wsl([string]$cmd, [string]$user = 'clawuser') {
    $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cmd))
    return (& wsl.exe -d Ubuntu -u $user -- bash -lc "echo $b | base64 -d | bash" 2>&1 | Out-String)
}
W "===== ClawFactory clean-install probe ($(Get-Date -Format s)) ====="
W "identity: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)  IsSystem=$([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem)"
if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
    W "FATAL: running as SYSTEM -- WSL is unusable here (WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED)."
    W "This probe MUST run as clawadmin via auto-logon. Results below would be meaningless."
    exit 2
}

W "`n===== 1. THE HEADLINE: can the agent see ungranted Windows files? ====="
W "--- /etc/wsl.conf (automount must be false on a correct install) ---"
W (Wsl 'cat /etc/wsl.conf' 'root')
W "--- the fail-loud automount readback actually RAN during install (not skipped) ---"
W (Get-Content 'C:\ProgramData\ClawFactory\install.log' -EA SilentlyContinue | Select-String -Pattern 'automount|Assert-WslAutomountDisabled' | Select-Object -Last 6 | Out-String)
W "--- is /mnt/c mounted at all? (model-independent proof) ---"
W (Wsl 'echo "mnt_c_exists=$([ -d /mnt/c ] && echo YES || echo NO)"; echo "mount_table_mnt=$(mount | grep -c " /mnt/c ")"; ls /mnt/c 2>&1 | head -3')
W "--- clawuser attempts the exact paths a customer worries about ---"
W (Wsl 'for p in /mnt/c /mnt/c/Users "/mnt/c/Users/clawadmin/Desktop" "/mnt/c/Users/clawadmin/Documents"; do printf "%s -> " "$p"; ls "$p" 2>&1 | head -1; done')

W "`n===== 2. INSTALL-PATH CHANGES on a box the installer actually built ====="
W "--- Docker removal: the TRAP was that Step-InstallDocker was the only installer of"
W "    nftables (the firewall backend) and dbus-user-session (systemd --user -> gateway)."
W (Wsl 'echo "docker_binary=$(command -v docker || echo ABSENT)"; echo "nft_binary=$(command -v nft || echo ABSENT)"; echo "nft_table=$(/usr/sbin/nft list table inet clawfactory >/dev/null 2>&1 && echo PRESENT || echo MISSING)"; echo "dbus_user_session=$(dpkg -l dbus-user-session 2>/dev/null | grep -c ^ii)"' 'root')
W "--- the firewall chain actually came up (DNS restricted + private-port drops) ---"
W (Wsl '/usr/sbin/nft list chain inet clawfactory output 2>&1 | head -14' 'root')
W "--- gateway + proxy: real gateway on private 8788, proxy owns 8787 ---"
W (Wsl 'ss -ltn 2>/dev/null | grep -E ":(8787|8788)" | awk "{print \$4}"; echo "proxy_service=$(systemctl is-active clawfactory-proxy 2>/dev/null)"; echo "gateway_status_via_proxy=$(curl -s -o /dev/null -w %{http_code} --max-time 8 http://127.0.0.1:8787/status)"' 'root')
W "--- Step-InstallChatProxy / turn-gate / freeze ran? (install log) ---"
W (Get-Content 'C:\ProgramData\ClawFactory\install.log' -EA SilentlyContinue | Select-String -Pattern 'Step 15b|Step 15c|Step 15d|turn-gate|injected-soul|chat-proxy|Preflight: all' | Select-Object -Last 10 | Out-String)
W "--- both SOULs root-owned, immutable, hash-matched; workspace creation survived the freeze ---"
W (Wsl 'for f in /home/clawuser/.openclaw/SOUL.md /home/clawuser/.openclaw/workspace/SOUL.md; do echo "$f: $(stat -c "%A %U:%G" $f 2>/dev/null) lsattr=$(lsattr $f 2>/dev/null | awk "{print \$1}")"; done; echo "factory_hash_eq_pin=$([ "$(sha256sum /home/clawuser/.openclaw/SOUL.md 2>/dev/null | cut -d" " -f1)" = "$(cat /etc/clawfactory/soul.sha256 2>/dev/null)" ] && echo YES || echo NO)"; echo "injected_hash_eq_pin=$([ "$(sha256sum /home/clawuser/.openclaw/workspace/SOUL.md 2>/dev/null | cut -d" " -f1)" = "$(cat /etc/clawfactory/workspace-soul.sha256 2>/dev/null)" ] && echo YES || echo NO)"; echo "workspace_files=$(ls /home/clawuser/.openclaw/workspace/ 2>/dev/null | tr "\n" " ")"' 'root')
W "--- the injected rules are TRUE (no Docker sandbox claim) ---"
W (Wsl 'grep -c "no Docker sandbox" /home/clawuser/.openclaw/workspace/SOUL.md; grep -c "network=none" /home/clawuser/.openclaw/workspace/SOUL.md' 'root')

W "`n===== 3. ESCAPES (one folder granted; UID-level = model-independent) ====="
W "NOTE: run after granting C:\cfv\granted via the grants engine; each must FAIL."
W (Wsl 'G=/workspaces; echo "mounts:"; mount | grep /workspaces | head -3; echo "traversal:"; ls $G/../ 2>&1 | head -2; echo "absolute-ungranted:"; ls /mnt/c/Users 2>&1 | head -1')

W "`n===== 4. METER-UNKNOWN FAILS SAFE (T1.3b -- needs a disposable box; this is it) ====="
W "Stopping the gateway so the spend meter cannot read, then attempting a gated turn."
W (Wsl 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user stop openclaw-gateway 2>/dev/null; sleep 2; echo "gateway=$(systemctl --user is-active openclaw-gateway 2>/dev/null)"; echo "--- gate verdict with an unreadable meter (must BLOCK, never $0.00) ---"; /usr/local/sbin/clawfactory-turn-gate.sh 2>&1 | head -2; echo "gate_rc=$?"')
W (Wsl 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start openclaw-gateway 2>/dev/null; sleep 8; echo "gateway_restarted=$(systemctl --user is-active openclaw-gateway)"')

W "`n===== 5. SMOKE TEST (fresh install) ====="
$smoke = 'C:\Program Files\ClawFactory\resources\smoke-test.ps1'
if (Test-Path $smoke) { W (& powershell -NoProfile -ExecutionPolicy Bypass -File $smoke 2>&1 | Select-Object -Last 25 | Out-String) }
else { W "smoke-test.ps1 not found at $smoke" }

W "`n===== 6. NEEDS-KEY (not run; no provider key on this VM by design) ====="
W "  - agent-narrated isolation/escape wording (the UID-level proof above is stronger)"
W "  - cold-start to a real agent RESULT (mechanical time-to-demo-ready is measurable without a key)"
W "===== probe complete ====="
