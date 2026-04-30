# Smoke test for ClawFactory-Secure-Setup v1.0
# Run on a clean Win11 22H2+ VM AFTER walking the ClawFactory-Secure-Setup.exe wizard.
# Requires: admin PowerShell.

$ok = 0; $fail = 0
function Check { param($Name, [scriptblock]$Test)
    try { if (& $Test) { Write-Host "  PASS  $Name" -ForegroundColor Green; $script:ok++ }
          else         { Write-Host "  FAIL  $Name" -ForegroundColor Red;   $script:fail++ } }
    catch              { Write-Host "  FAIL  $Name :: $($_.Exception.Message)" -ForegroundColor Red; $script:fail++ } }

Check 'WSL automount disabled' { (wsl -d Ubuntu -u clawuser -- cat /etc/wsl.conf) -match 'enabled\s*=\s*false' }

Check 'Four agent.md files present' {
    $script = "for a in orchestrator skill-scout skill-builder publisher; do f=`$HOME/.openclaw/agents/`$a/agent.md; [ -s `$f ] || exit 1; done; echo OK"
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    (wsl -d Ubuntu -u clawuser --cd ~ -- bash -lc "echo $enc | base64 -d | bash") -eq 'OK' }

Check 'AgentBootstrap checkpoint recorded' {
    $cp = Join-Path $env:ProgramData 'ClawFactory\checkpoint.json'
    (Get-Content $cp -Raw | ConvertFrom-Json).completedSteps -contains 'AgentBootstrap' }

# Layered gateway start: prefer systemd --user, then `openclaw gateway start`,
# then `nohup setsid openclaw gateway run`. Same three-tier fallback as
# setup.ps1's $startGateway block and launcher.ps1's Start-Gateway. Required
# because default WSL2 kernels often don't have systemd available, in which
# case `systemctl --user start` silently no-ops and the gateway never binds.
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
wsl -d Ubuntu -u clawuser --cd ~ -- bash -lc "echo $encStart | base64 -d | bash" 2>&1 | Out-Null
Start-Sleep -Seconds 8
Check 'Gateway responds 200 on loopback' {
    try { (Invoke-WebRequest -Uri http://127.0.0.1:8787/status -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 }
    catch { $false } }

Check 'Firewall inbound-deny rule on 8787' {
    $r = Get-NetFirewallRule -DisplayName 'ClawFactory-Block-Inbound-8787' -ErrorAction SilentlyContinue
    $r -and $r.Enabled -eq 'True' -and $r.Action -eq 'Block' }

Check 'Orchestrator SOUL hash substituted' {
    $script = 'grep -q "{{SOUL_SHA256}}" $HOME/.openclaw/agents/orchestrator/agent.md && echo BAD || echo OK'
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    (wsl -d Ubuntu -u clawuser --cd ~ -- bash -lc "echo $enc | base64 -d | bash") -eq 'OK' }

Write-Host ""; Write-Host "Result: $ok pass, $fail fail" -ForegroundColor $(if ($fail) {'Red'} else {'Green'})
exit $fail
