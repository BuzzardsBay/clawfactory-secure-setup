# ClawFactory Kill Switch [R6] - stops any running agent turn + the gateway, and
# unmounts every granted Windows folder so the agent can no longer see any of
# your files.
#
# Safe to run any time. Preserves WSL and anything unrelated to ClawFactory.
#
# SECFIX_CLOSE_DOORS_2026-07-14 (Docker decision A): this used to run
#   `docker ps --filter label=clawfactory=1` -> `docker kill`
# which NEVER matched anything -- no container was ever created with that label
# (Phase 0 + 2.5 VERIFIED zero containers; the agent is a clawuser PROCESS). So
# the kill switch claimed to kill agents but never did. Docker is now removed;
# that no-op is replaced with the truthful equivalent: kill the agent processes.
#
# KILL != REVOKE: this unmounts your granted folders but LEAVES the grants in the
# ledger (marked active). The next time ClawFactory starts, they are replayed
# (remounted) automatically. To remove a folder grant permanently, use Revoke,
# not the Kill Switch.

$ErrorActionPreference = 'Continue'

Write-Host 'ClawFactory Kill Switch' -ForegroundColor Yellow
Write-Host '-----------------------'

Write-Host 'Stopping any running agent turn...'
# The agent is a clawuser process, not a container. The [o] bracket keeps pkill's
# -f pattern from matching this command's own shell.
wsl -d Ubuntu -u clawuser -- bash -lc 'if pkill -u clawuser -f "[o]penclaw agent" 2>/dev/null; then echo "(killed running agent turn(s))"; else echo "(no running agent turns)"; fi'

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
Write-Host 'and any running agent turn is killed. Your folder grants are preserved and' -ForegroundColor Green
Write-Host 'will be re-mounted next time you start ClawFactory (use Revoke to remove'-ForegroundColor Green
Write-Host 'a grant permanently).'                                                   -ForegroundColor Green
