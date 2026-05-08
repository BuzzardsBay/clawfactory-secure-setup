# Smoke test for ClawFactory-Secure-Setup v1.0.15
# Run on a clean Win11 22H2+ VM AFTER walking the ClawFactory-Secure-Setup.exe wizard.
# Requires: admin PowerShell as clawadmin (or any non-SYSTEM admin user).
#
# WSL refuses to run as NT AUTHORITY\SYSTEM (WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED).
# When invoked under SYSTEM (e.g. via az vm run-command), every WSL-dependent
# check is SKIPPED rather than failed. Re-run as clawadmin for full coverage.
# Exit code is the number of FAILS only - SKIPs do not fail the suite.

$ok = 0; $fail = 0; $skip = 0

# v1.0.15: SYSTEM detection. WSL refuses to run as LocalSystem; if this
# script is invoked via az vm run-command (which always runs as SYSTEM on
# Windows VMs), every WSL-dependent check would otherwise fail with a
# misleading error. Detect the context up-front and skip those checks.
$isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
if ($isSystem) {
    Write-Host "Running as NT AUTHORITY\SYSTEM - WSL checks will be SKIPPED." -ForegroundColor Yellow
    Write-Host "Re-run as clawadmin (or any non-SYSTEM admin) for full coverage." -ForegroundColor Yellow
    Write-Host ""
}

# v1.0.15: Process.Start wrapper for wsl.exe with explicit UTF-8 encoding.
#
# Encoding choice differs from setup.ps1's Invoke-WslExe (which uses UTF-16-LE).
# Reason: setup.ps1's Invoke-WslExe calls wsl.exe's OWN commands (--status,
# --list, --shutdown) whose output is UTF-16-LE. Smoke-test.ps1 only ever
# calls `wsl -d Ubuntu -- bash -lc "..."` or `wsl -d Ubuntu -- cat ...`,
# which forward Linux-side stdout (UTF-8 pass-through). Decoding UTF-8 bytes
# as UTF-16-LE would produce garbage (e.g. "OK\n" -> "U+4B4F + stray byte").
# Explicit UTF-8 here matches the actual byte format and is robust to any
# non-ASCII output a future Linux command might produce.
function Invoke-WslCapture {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $quoted = $Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'wsl.exe'
    $psi.Arguments              = ($quoted -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return @{ ExitCode = $proc.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

function Check {
    param(
        [Parameter(Position = 0)]$Name,
        [Parameter(Position = 1)][scriptblock]$Test,
        [switch]$RequiresWsl
    )
    if ($RequiresWsl -and $isSystem) {
        Write-Host "  SKIP  $Name (requires WSL; running as SYSTEM)" -ForegroundColor Yellow
        $script:skip++
        return
    }
    try {
        if (& $Test) { Write-Host "  PASS  $Name" -ForegroundColor Green; $script:ok++ }
        else         { Write-Host "  FAIL  $Name" -ForegroundColor Red;   $script:fail++ }
    }
    catch {
        Write-Host "  FAIL  $Name :: $($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
    }
}

Check 'WSL automount disabled' -RequiresWsl {
    $r = Invoke-WslCapture -Arguments @('-d','Ubuntu','-u','clawuser','--','cat','/etc/wsl.conf')
    $r.StdOut -match 'enabled\s*=\s*false'
}

Check 'Four agent.md files present' -RequiresWsl {
    $script = "for a in orchestrator skill-scout skill-builder publisher; do f=`$HOME/.openclaw/agents/`$a/agent.md; [ -s `$f ] || exit 1; done; echo OK"
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    $r = Invoke-WslCapture -Arguments @('-d','Ubuntu','-u','clawuser','--cd','~','--','bash','-lc',"echo $enc | base64 -d | bash")
    $r.StdOut.Trim() -eq 'OK'
}

Check 'AgentBootstrap checkpoint recorded' {
    $cp = Join-Path $env:ProgramData 'ClawFactory\checkpoint.json'
    (Get-Content $cp -Raw | ConvertFrom-Json).completedSteps -contains 'AgentBootstrap'
}

# Layered gateway start: prefer systemd --user, then `openclaw gateway start`,
# then `nohup setsid openclaw gateway run`. Same three-tier fallback as
# setup.ps1's $startGateway block and launcher.ps1's Start-Gateway. Required
# because default WSL2 kernels often don't have systemd available, in which
# case `systemctl --user start` silently no-ops and the gateway never binds.
# Skipped under SYSTEM (no WSL access).
if (-not $isSystem) {
    $startScript = @'
set -e
LOG=/home/clawuser/.openclaw/logs/gateway.log
mkdir -p /home/clawuser/.openclaw/logs
if curl -fsS --max-time 2 http://127.0.0.1:8787/status >/dev/null 2>&1; then
    exit 0
fi
if systemctl --user is-system-running >/dev/null 2>&1 || \
   systemctl --user list-units --no-legend --no-pager >/dev/null 2>&1; then
    systemctl --user start openclaw-gateway.service 2>/dev/null || true
else
    if ! openclaw gateway start </dev/null >>"$LOG" 2>&1; then
        nohup setsid openclaw gateway run </dev/null >>"$LOG" 2>&1 &
        disown 2>/dev/null || true
    fi
fi
exit 0
'@
    $encStart = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($startScript))
    $null = Invoke-WslCapture -Arguments @('-d','Ubuntu','-u','clawuser','--cd','~','--','bash','-lc',"echo $encStart | base64 -d | bash")
    Start-Sleep -Seconds 8
}

Check 'Gateway responds 200 on loopback' {
    try { (Invoke-WebRequest -Uri http://127.0.0.1:8787/status -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 }
    catch { $false }
}

Check 'Firewall inbound-deny rule on 8787' {
    $r = Get-NetFirewallRule -DisplayName 'ClawFactory-Block-Inbound-8787' -ErrorAction SilentlyContinue
    $r -and $r.Enabled -eq 'True' -and $r.Action -eq 'Block'
}

Check 'Orchestrator SOUL hash substituted' -RequiresWsl {
    $script = 'grep -q "{{SOUL_SHA256}}" $HOME/.openclaw/agents/orchestrator/agent.md && echo BAD || echo OK'
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    $r = Invoke-WslCapture -Arguments @('-d','Ubuntu','-u','clawuser','--cd','~','--','bash','-lc',"echo $enc | base64 -d | bash")
    $r.StdOut.Trim() -eq 'OK'
}

Check 'auth-profiles.json present for all 5 agents' -RequiresWsl {
    $script = 'ok=0; for a in main orchestrator publisher skill-builder skill-scout; do
      f=$HOME/.openclaw/agents/$a/agent/auth-profiles.json
      [ -f "$f" ] && [ "$(stat -c %a "$f")" = "600" ] && ok=$((ok+1))
    done
    [ "$ok" = "5" ] && echo OK || echo BAD'
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    $r = Invoke-WslCapture -Arguments @('-d','Ubuntu','-u','clawuser','--cd','~','--','bash','-lc',"echo $enc | base64 -d | bash")
    $r.StdOut.Trim() -eq 'OK'
}

# v1.0.1: confirms Step-ConfigureWslConfig wrote the gateway-stability setting
# into %USERPROFILE%\.wslconfig. Tagged -RequiresWsl because it's WSL-related
# config; under SYSTEM, $env:USERPROFILE is the SYSTEM profile (not clawadmin's)
# and the file isn't there - skipping avoids a false negative.
Check '.wslconfig has vmIdleTimeout=-1' -RequiresWsl {
    $cfg = Join-Path $env:USERPROFILE '.wslconfig'
    if (-not (Test-Path $cfg)) { return $false }
    (Get-Content $cfg -Raw) -match 'vmIdleTimeout\s*=\s*-1'
}

# v1.0.2: confirms Step-RegisterWslHostTask landed. The task holds one
# wsl.exe session alive permanently so WSL doesn't fire its
# last-session-exit shutdown sequence inside the distro.
Check 'WSL Host scheduled task registered and enabled' {
    $t = Get-ScheduledTask -TaskName 'ClawFactory WSL Host' -ErrorAction SilentlyContinue
    $t -and $t.State -ne 'Disabled'
}

# v1.0.3: confirms the egress firewall actually activated (nft table 'inet
# clawfactory' is loaded). On v1.0.2 and earlier, runtime nft mangling
# meant the firewall script exited 127 but was checkpointed as completed,
# so this check would have silently failed there.
Check 'Egress firewall clawfactory chain present in nft ruleset' -RequiresWsl {
    $r = Invoke-WslCapture -Arguments @('-d','Ubuntu','-u','clawuser','--','bash','-lc',"/usr/sbin/nft list ruleset 2>/dev/null | grep -c 'clawfactory'")
    # v1.0.15: defensive parse - extract first integer from output. Avoids
    # "Cannot convert Object[] to Int32" when wsl returns multi-line output
    # (e.g. SYSTEM-not-supported error, login-shell warnings).
    $first = ($r.StdOut -split "`n" | Select-Object -First 1).Trim()
    $m = [regex]::Match($first, '\d+')
    if ($m.Success) { [int]$m.Value -gt 0 } else { $false }
}

# v1.0.4: confirms Step-PreInstallOpenClawDeps landed make/g++/cmake/python3
# so install.sh's "Installing Linux build tools" phase finds them present
# and skips its own apt fetch (which stalls on slow networks).
Check 'OpenClaw build deps present (make g++ cmake python3)' -RequiresWsl {
    $r = Invoke-WslCapture -Arguments @('-d','Ubuntu','-u','clawuser','--','bash','-lc',"dpkg -l make g++ cmake python3 2>/dev/null | grep -c '^ii'")
    # v1.0.15: same defensive parse - first integer in first non-empty line.
    # Fixes the "Cannot convert Object[] to Int32" crash observed in v1.0.14.
    $first = ($r.StdOut -split "`n" | Select-Object -First 1).Trim()
    $m = [regex]::Match($first, '\d+')
    if ($m.Success) { [int]$m.Value -ge 4 } else { $false }
}

Write-Host ""
$resultColor = if ($fail) { 'Red' } else { 'Green' }
Write-Host "Result: $ok pass, $fail fail, $skip skip" -ForegroundColor $resultColor
exit $fail
