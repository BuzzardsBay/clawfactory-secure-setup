<#
.SYNOPSIS
  Step-8c diagnostic bundle. Captures WHY user@1000 (clawuser's systemd user
  manager) fails to come up on a clean single-distro install, which is what kills
  the gateway in Step-PreinstallGatewayRuntime.

.DESCRIPTION
  Runs AS clawadmin, in the SAME interactive session and the SAME boot as the
  failed install -- never via az vm run-command (that is SYSTEM, and WSL refuses
  to run as LocalSystem).

  DESIGN NOTE -- why one giant `wsl` call instead of many:
  Per the v1.0.2 diagnosis lineage, when the LAST wsl.exe session exits, WSL runs
  a full systemd SHUTDOWN inside the distro (not a logout) -- tearing down
  user@1000. A diagnostic made of N separate `wsl` invocations would therefore
  destroy and recreate the very state it is trying to observe, N times. So the
  whole Linux-side bundle runs in ONE invocation, giving one coherent snapshot.

  This script OBSERVES ONLY. It must not start, restart, or fix anything -- a
  probe that repairs the box destroys the evidence.
#>
$ErrorActionPreference = 'Continue'
$env:WSL_UTF8 = 1   # else wsl -l -v emits UTF-16 and reads back as garbage

# NB: do NOT name this `H`. PowerShell ships `h` as a built-in ALIAS for
# Get-History, and aliases take precedence over functions -- so every `H "..."`
# call silently ran `Get-History "..."` and threw instead of printing a header.
function Section($t) { Write-Output ""; Write-Output "########## $t ##########" }

Section "0. WINDOWS SIDE -- context"
Write-Output "--- date ---"; Get-Date -Format 'u'
Write-Output "--- whoami (must NOT be SYSTEM; WSL refuses to run as LocalSystem) ---"; whoami
Write-Output "--- INSTALLER_DONE ---"; Get-Content C:\cfv\INSTALLER_DONE.txt -ErrorAction SilentlyContinue
Write-Output "--- install.log tail (the failure + the GW-* dump) ---"
Get-Content 'C:\Program Files\ClawFactory Secure Setup\install.log' -Tail 40 -ErrorAction SilentlyContinue
Get-Content C:\cfv\install.log -Tail 15 -ErrorAction SilentlyContinue
Write-Output "--- checkpoint (how far the installer got) ---"
Get-ChildItem -Path C:\ProgramData\ClawFactory -Filter *.json -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object { $_.FullName; Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue }

Section "0b. The WSL keepalive task -- setup.ps1:2771 registers it AFTER the gateway step"
# v1.0.2 lore: 'ClawFactory WSL Host' runs `wsl -d Ubuntu -u clawuser -- sleep
# infinity` AT LOGON to hold one session open so the session-exit shutdown never
# fires. If it does not exist / has never run at gateway-start time, nothing is
# holding a session open during the install.
schtasks /query /tn "ClawFactory WSL Host" /v /fo LIST 2>&1 | Select-String -Pattern 'TaskName|Status|Last Run Time|Last Result|Scheduled Task State|Task To Run|Next Run Time'
Write-Output "--- .wslconfig (vmIdleTimeout) ---"
Get-Content "$env:USERPROFILE\.wslconfig" -ErrorAction SilentlyContinue
Write-Output "--- distros (single-distro proof, Windows side) ---"
wsl -l -v 2>&1
Write-Output "--- wsl version ---"
wsl --version 2>&1

# ---------------------------------------------------------------------------
# The Linux-side bundle: ONE invocation, root context (journal + logind need it).
# ---------------------------------------------------------------------------
$bash = @'
set +e
echo "########## 3.1 SINGLE-DISTRO PROOF (rules out the local scratch artifact) ##########"
echo "--- distro ---"; cat /etc/os-release 2>/dev/null | head -2
echo "--- boot_id ---"; cat /proc/sys/kernel/random/boot_id
echo "--- PID1 cgroup ns (LOCAL FAILURE was cgroup:[4026531835] = host root ns, shared) ---"
echo "  pid1 cgroup ns: $(readlink /proc/1/ns/cgroup)"
echo "  self cgroup ns: $(readlink /proc/self/ns/cgroup)"
echo "  pid1 net    ns: $(readlink /proc/1/ns/net)"
echo "  pid1 pid    ns: $(readlink /proc/1/ns/pid)"
echo "--- PID1 identity (must be systemd) ---"; ps -p 1 -o pid,comm,args --no-headers
echo "--- systemd running? ---"; systemctl is-system-running 2>&1
echo "--- kernel ---"; uname -r

echo ""
echo "########## 3.2 *** PRIMARY EVIDENCE *** user@1000 state + WHY ##########"
echo "--- systemctl status user@1000.service (full) ---"
systemctl status user@1000.service --no-pager -l 2>&1
echo ""
echo "--- systemctl show user@1000 (exit code, result) ---"
systemctl show user@1000.service -p ActiveState -p SubState -p Result -p ExecMainStatus -p ExecMainCode -p LoadState 2>&1
echo ""
echo "--- journalctl -u user@1000.service -n 50 ---"
journalctl -u user@1000.service -n 50 --no-pager 2>&1
echo ""
echo "--- user-runtime-dir@1000 (creates /run/user/1000; separate unit from user@) ---"
systemctl status user-runtime-dir@1000.service --no-pager -l 2>&1 | head -20

echo ""
echo "########## 3.3 LINGER + SESSIONS ##########"
echo "--- loginctl show-user clawuser ---"
loginctl show-user clawuser 2>&1
echo "--- linger marker file (root-owned; presence = linger enabled) ---"
ls -l /var/lib/systemd/linger/ 2>&1
echo "--- loginctl list-sessions (is there ANY clawuser session?) ---"
loginctl list-sessions 2>&1
echo "--- loginctl list-users ---"
loginctl list-users 2>&1

echo ""
echo "########## 3.4 RUNTIME DIR (explains 'Failed to connect to bus') ##########"
echo "--- ls -ld /run/user/1000 ---"
ls -ld /run/user/1000 2>&1
echo "--- ls /run/user/ ---"
ls -l /run/user/ 2>&1
echo "--- clawuser context: XDG_RUNTIME_DIR + can it reach its bus? ---"
su clawuser -s /bin/bash -c 'echo "  XDG_RUNTIME_DIR=[$XDG_RUNTIME_DIR]"; echo "  DBUS=[$DBUS_SESSION_BUS_ADDRESS]"; echo "  id: $(id)"' 2>&1
echo "--- exactly what setup.ps1 does at 1932 (systemctl --user as clawuser) ---"
su clawuser -s /bin/bash -c 'systemctl --user is-system-running' 2>&1
su clawuser -s /bin/bash -c 'systemctl --user is-active openclaw-gateway.service' 2>&1

echo ""
echo "########## 3.5 THE GATEWAY ITSELF ##########"
echo "--- unit file present? ---"
ls -l /home/clawuser/.config/systemd/user/openclaw-gateway.service 2>&1
echo "--- systemctl --user -M clawuser@ status openclaw-gateway (needs a live user bus) ---"
systemctl --user -M clawuser@ status openclaw-gateway.service --no-pager -l 2>&1 | head -25
echo "--- gateway journal, if any ---"
journalctl _UID=1000 -n 25 --no-pager 2>&1 | tail -25
echo "--- ss -ltnp : is ANYTHING listening on 8787/8788? ---"
ss -ltnp 2>&1 | grep -E '8787|8788' || echo "  (nothing listening on 8787/8788)"
echo "--- any openclaw/node processes alive? ---"
ps -eo pid,user,args --no-headers 2>/dev/null | grep -iE 'openclaw|node' | grep -v grep || echo "  (no openclaw/node processes)"

echo ""
echo "########## 3.6 Type=simple RACE -- ruled in or out ##########"
# Documented 3-14s window where systemctl says active but the port is not bound.
# Only meaningful if the user manager is UP. If user@1000 is down, this is MOOT.
UM=$(systemctl is-active user@1000.service 2>&1)
echo "  user@1000 is-active: $UM"
if [ "$UM" = "active" ]; then
  echo "  user manager IS up -> the race is a live candidate. Probing:"
  su clawuser -s /bin/bash -c 'systemctl --user is-active openclaw-gateway.service' 2>&1
  curl -s -o /dev/null -w "  curl 127.0.0.1:8787 -> http=%{http_code}\n" --max-time 5 http://127.0.0.1:8787/ 2>&1
else
  echo "  >>> user manager is NOT active -> the Type=simple race is MOOT."
  echo "  >>> The gateway never got far enough to race: systemctl --user cannot"
  echo "  >>> even reach a bus, so no unit was ever started to be 'active early'."
fi

echo ""
echo "########## 3.7 LOGIND HEALTH + was a clawuser session EVER created? ##########"
echo "--- systemctl status systemd-logind ---"
systemctl status systemd-logind --no-pager -l 2>&1 | head -18
echo "--- pam_systemd / logind session records in the SYSTEM journal ---"
journalctl -b --no-pager 2>&1 | grep -iE 'pam_systemd|New session|Removed session|logind|user-runtime-dir|user@1000' | tail -40
echo ""
echo "--- *** v1.0.2 LORE CHECK: did the session-exit SHUTDOWN fire during install? *** ---"
# 'System is powering down' from logind after a Plan9 channel close is the
# signature of WSL tearing the distro down when the last wsl.exe session exits.
journalctl --no-pager 2>&1 | grep -iE 'System is powering down|Reached target Shutdown|Reached target Power-Off|p9io|AcceptAsync' | tail -25
echo "--- how many distro boots? (v1.0.2 saw 12 shutdown cycles in 47 min) ---"
journalctl --list-boots --no-pager 2>&1 | tail -15
echo "--- is dbus-user-session installed? (Step-InstallBaseDeps owns this now) ---"
dpkg -l dbus-user-session 2>&1 | tail -2
echo "--- was /etc/pam.d/su|login wired for pam_systemd? ---"
grep -rn 'pam_systemd' /etc/pam.d/ 2>&1 | head
'@

Section "1-3. LINUX SIDE -- one wsl invocation (see DESIGN NOTE above)"
# TRANSPORT NOTE -- do NOT stage this through a Windows temp file + wslpath.
# ClawFactory sets [automount] enabled=false in /etc/wsl.conf (setup.ps1
# Assert-WslAutomountDisabled even THROWS if it cannot verify it). So /mnt/c does
# not exist on a correctly-installed box and the distro physically cannot read a
# file from the Windows filesystem -- the isolation being tested is the same
# isolation that would break the probe. Pass the script as base64 on the command
# line instead: no shared filesystem, nothing to mount.
# (LF only + no BOM: bash chokes on CRLF with "$'\r': command not found".)
$lf   = ($bash -replace "`r`n", "`n")
$b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($lf))
Write-Output "(bundle: $($lf.Length) bytes -> $($b64.Length) b64 chars, passed inline; /mnt/c is intentionally absent)"
wsl -d Ubuntu -u root -- bash -c "echo $b64 | base64 -d | bash" 2>&1

Section "DIAG COMPLETE"
