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

wsl -d Ubuntu -u clawuser -- bash -lc "systemctl --user start openclaw-gateway" 2>&1 | Out-Null
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
