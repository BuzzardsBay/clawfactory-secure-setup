# ClawFactory Kill Switch [R6] - stops all agent containers + gateway.
# Safe to run any time. Preserves Docker, WSL, and unrelated containers.

$ErrorActionPreference = 'Continue'

Write-Host 'ClawFactory Kill Switch' -ForegroundColor Yellow
Write-Host '-----------------------'

Write-Host 'Stopping labeled agent containers...'
wsl -d Ubuntu -u clawuser -- bash -lc 'ids=$(docker ps -q --filter label=clawfactory=1); if [ -n "$ids" ]; then docker kill $ids; else echo "(no running clawfactory containers)"; fi'

Write-Host 'Stopping OpenClaw gateway...'
wsl -d Ubuntu -u clawuser -- bash -lc 'openclaw gateway stop 2>/dev/null || echo "(gateway not running)"'

Write-Host 'Done.' -ForegroundColor Green
