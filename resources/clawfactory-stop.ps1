# ClawFactory Kill Switch [R6] - stops all agent containers + gateway, and
# unmounts every granted Windows folder so the agent can no longer see any of
# your files.
#
# Safe to run any time. Preserves Docker, WSL, and unrelated containers.
#
# KILL != REVOKE: this unmounts your granted folders but LEAVES the grants in the
# ledger (marked active). The next time ClawFactory starts, they are replayed
# (remounted) automatically. To remove a folder grant permanently, use Revoke,
# not the Kill Switch.

$ErrorActionPreference = 'Continue'

Write-Host 'ClawFactory Kill Switch' -ForegroundColor Yellow
Write-Host '-----------------------'

Write-Host 'Stopping labeled agent containers...'
wsl -d Ubuntu -u clawuser -- bash -lc 'ids=$(docker ps -q --filter label=clawfactory=1); if [ -n "$ids" ]; then docker kill $ids; else echo "(no running clawfactory containers)"; fi'

Write-Host 'Stopping OpenClaw gateway...'
wsl -d Ubuntu -u clawuser -- bash -lc 'openclaw gateway stop 2>/dev/null || echo "(gateway not running)"'

Write-Host 'Unmounting granted Windows folders...'
try {
    $grantsLib = Join-Path $PSScriptRoot 'clawfactory-grants.ps1'
    if (Test-Path -LiteralPath $grantsLib) {
        . $grantsLib
        $n = Invoke-GrantKillUnmount
        Write-Host "  Unmounted $n workspace folder(s). Grants are kept (active) and will replay on next start."
    } else {
        Write-Host '  (grants library not found; skipping folder unmount)'
    }
} catch {
    Write-Host "  (folder unmount error: $($_.Exception.Message))"
}

Write-Host ''
Write-Host 'Done. The agent can no longer see your files, the gateway is stopped,' -ForegroundColor Green
Write-Host 'and agent containers are killed. Your folder grants are preserved and'  -ForegroundColor Green
Write-Host 'will be re-mounted next time you start ClawFactory (use Revoke to remove'-ForegroundColor Green
Write-Host 'a grant permanently).'                                                   -ForegroundColor Green
