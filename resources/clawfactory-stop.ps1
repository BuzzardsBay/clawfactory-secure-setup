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
# AND THE REPLACEMENT WAS ALSO A NO-OP, on every release from v1.0 (d9b6d36)
# until v1.4.4. Measured on cfv-178, 2026-08-27: both WSL lines died with a bash
# syntax error, the script exited 0 regardless, and it told the user "the gateway
# is stopped, and any running agent turn is killed" while the gateway was still
# answering 200 and its process was still alive.
#
# TWO defects, and the second is the more serious one.
#
#   1. QUOTING. PowerShell 5.1 wraps a native-command argument that contains
#      spaces in double quotes and does NOT escape the double quotes already
#      inside it, so a bash payload carrying its own double quotes ends the
#      argument early and bash is handed a fragment. Single quotes survive the
#      pass intact. Every payload below is therefore free of double quotes, and
#      Invoke-StopWsl REFUSES a payload that contains one, so the defect cannot
#      come back silently through an ordinary-looking edit.
#
#   2. AN UNCHECKED RESULT REPORTED AS SUCCESS. The old code discarded both exit
#      codes and printed its success banner unconditionally. That is the same
#      shape as the uninstaller that logged "In-distro ClawFactory artifacts
#      removed" over a teardown which had failed. A control that cannot report
#      its own failure is worse than an absent one, because the user stops
#      looking. Every step below captures its result, and the closing summary is
#      decided by a VERIFICATION performed after the stop, not by the fact that
#      a command was issued.
#
# KILL != REVOKE: this unmounts your granted folders but LEAVES the grants in the
# ledger (marked active). The next time ClawFactory starts, they are replayed
# (remounted) automatically. To remove a folder grant permanently, use Revoke,
# not the Kill Switch.

$ErrorActionPreference = 'Continue'

$Distro = 'Ubuntu'

# Run one bash payload inside the distro as clawuser and return BOTH its exit
# code and its combined output. This function interprets nothing: each caller
# decides what its own output means, and no caller may assume success.
function Invoke-StopWsl {
    param([Parameter(Mandatory = $true)][string]$Bash)
    if ($Bash.Contains('"')) {
        return [pscustomobject]@{
            Code = 255
            Text = 'REFUSED: payload contains a double quote; see the quoting note at the top of this file'
        }
    }
    $raw  = & wsl.exe -d $Distro -u clawuser -- bash -lc $Bash 2>&1
    $code = $LASTEXITCODE
    return [pscustomobject]@{ Code = $code; Text = (($raw | Out-String).Trim()) }
}

Write-Host 'ClawFactory Kill Switch' -ForegroundColor Yellow
Write-Host '-----------------------'

# --- 1. Any running agent turn ---------------------------------------------
# The agent is a clawuser process, not a container. The [o] bracket keeps
# pkill's -f pattern from matching this command's own shell.
Write-Host 'Stopping any running agent turn...'
$kill = Invoke-StopWsl 'if pkill -u clawuser -f ''[o]penclaw agent'' 2>/dev/null; then echo CF_TURNS_KILLED; else echo CF_TURNS_NONE; fi'
if ($kill.Text -match 'CF_TURNS_KILLED') {
    Write-Host '  (killed running agent turn(s))'
} elseif ($kill.Text -match 'CF_TURNS_NONE') {
    Write-Host '  (no running agent turns)'
} else {
    Write-Host "  COULD NOT RUN THIS STEP (exit $($kill.Code)): $($kill.Text)" -ForegroundColor Red
}

# --- 2. The gateway ---------------------------------------------------------
# CF_GW_RC carries the openclaw CLI's own exit code out of the sandbox. It is
# reported, not trusted: section 4 below decides whether the gateway is down.
Write-Host 'Stopping OpenClaw gateway...'
$gw   = Invoke-StopWsl 'openclaw gateway stop 2>/dev/null; echo CF_GW_RC=$?'
$gwRc = $null
if ($gw.Text -match 'CF_GW_RC=(\d+)') { $gwRc = [int]$Matches[1] }
$gwSaid = @($gw.Text -split "`n" | Where-Object { $_ -notmatch 'CF_GW_RC=' -and $_.Trim() }) -join '; '
if ($null -eq $gwRc) {
    Write-Host "  COULD NOT RUN THIS STEP (exit $($gw.Code)): $($gw.Text)" -ForegroundColor Red
} elseif ($gwRc -eq 0) {
    Write-Host ('  (gateway stop reported success' + $(if ($gwSaid) { ": $gwSaid" } else { '' }) + ')')
} else {
    Write-Host ("  (gateway stop returned $gwRc; it may not have been running" + $(if ($gwSaid) { ": $gwSaid" } else { '' }) + ')')
}

# --- 3. Granted Windows folders --------------------------------------------
Write-Host 'Unmounting granted Windows folders...'
$unmounted   = $null
$unmountNote = ''
try {
    $grantsLib = Join-Path $PSScriptRoot 'clawfactory-grants.ps1'
    if (Test-Path -LiteralPath $grantsLib) {
        . $grantsLib
        $unmounted = Invoke-GrantKillUnmount
        Write-Host "  Unmounted $unmounted workspace folder(s). Grants are kept (active) and will replay on next start."
    } else {
        $unmountNote = 'grants library not found'
        Write-Host '  (grants library not found; skipping folder unmount)'
    }
} catch {
    $unmountNote = $_.Exception.Message
    Write-Host "  (folder unmount error: $unmountNote)" -ForegroundColor Red
}

# --- 4. Verify, because a command that was issued is not a state that holds --
# The reader is a process count inside the distro, not an HTTP probe. Port 8787
# is the root-owned gating proxy and answers 502 while the gateway behind it is
# dead, so a reply is not evidence the gateway is up. The gateway and any agent
# turn both run as clawuser, so one count settles both claims. CF_VERIFY_OK is
# printed only when pgrep actually exists: an unverified state must never be
# able to read as zero.
#
# NO SHELL VARIABLE AND NO COMMAND SUBSTITUTION, and that is measured rather than
# stylistic. On cfv-178 a payload of the form
#     n=$(pgrep -u clawuser -f '[o]penclaw' | wc -l); echo CF_PROCS=$n
# printed `CF_PROCS=` with n EMPTY, as clawuser and as root, with the gateway both
# up and down -- while the identical pipeline run WITHOUT the assignment reported
# the count correctly through the same wsl.exe channel. `$?` survives this channel;
# a variable assigned from $( ) does not. Two earlier versions of this verifier
# were emptied that way and reported COULD NOT BE VERIFIED over a stop that had
# genuinely succeeded.
#
# So the count is emitted directly as the payload's only output and parsed here.
# The pgrep-presence check is a SEPARATE call and is not optional: if pgrep were
# missing, its error would go to /dev/null and `wc -l` would print 0, and a
# missing tool would read as "nothing is running" -- the exact false negative this
# file exists to prevent, inverted.
#
# Worth keeping in view: through both wrong readers the script still refused to
# claim success. A false "could not verify" is a bug. A false "everything is
# stopped" is the defect that shipped for four months.
Write-Host 'Verifying...'
$havePgrep = Invoke-StopWsl 'command -v pgrep >/dev/null 2>&1 && echo CF_PGREP_PRESENT || echo CF_PGREP_ABSENT'
$countOut  = Invoke-StopWsl 'pgrep -u clawuser -f ''[o]penclaw'' 2>/dev/null | wc -l'
$verified  = $false
$procs     = -1
# [regex]::Match, not -match: a second -match overwrites $Matches, and reading it
# after the wrong one is a defect this session already shipped once today.
$countMatch = [regex]::Match($countOut.Text, '(?m)^\s*(\d+)\s*$')
if (($havePgrep.Text -match 'CF_PGREP_PRESENT') -and $countMatch.Success) {
    $verified = $true
    $procs    = [int]$countMatch.Groups[1].Value
}

# --- 5. Say only what was measured -----------------------------------------
Write-Host ''
Write-Host 'Result'
Write-Host '------'

if ($null -ne $unmounted) {
    Write-Host "  Granted folders:   unmounted ($unmounted folder(s)). The agent can no longer see them." -ForegroundColor Green
} else {
    Write-Host "  Granted folders:   NOT UNMOUNTED ($unmountNote). The agent may still be able to see them." -ForegroundColor Red
}

if ($verified -and $procs -eq 0) {
    Write-Host '  Gateway and turns: stopped (0 OpenClaw processes running as the agent).' -ForegroundColor Green
} elseif ($verified) {
    Write-Host "  Gateway and turns: STILL RUNNING ($procs OpenClaw process(es) as the agent)." -ForegroundColor Red
} else {
    # Print what the verifier actually returned. The first version of this file
    # swallowed it, so a reader defect was indistinguishable from a sandbox that
    # could not be reached, and diagnosing it cost a round trip to a running box.
    Write-Host '  Gateway and turns: COULD NOT BE VERIFIED. No claim is made either way.' -ForegroundColor Red
    Write-Host "                     (pgrep check: $($havePgrep.Text -replace '\s+', ' '))" -ForegroundColor Red
    Write-Host "                     (count read:  $($countOut.Text  -replace '\s+', ' '))" -ForegroundColor Red
}

Write-Host ''
if (($null -ne $unmounted) -and $verified -and $procs -eq 0) {
    Write-Host 'Everything is stopped. Your folder grants are preserved and will be re-mounted' -ForegroundColor Green
    Write-Host 'next time you start ClawFactory (use Revoke to remove a grant permanently).'    -ForegroundColor Green
    exit 0
}

if ($verified -and $procs -gt 0) {
    Write-Host 'The kill switch did NOT fully stop ClawFactory. Reboot the machine, or run'     -ForegroundColor Red
    Write-Host '  wsl --shutdown'                                                               -ForegroundColor Red
    Write-Host 'from a Windows terminal, which stops the sandbox and everything inside it.'     -ForegroundColor Red
    exit 1
}

Write-Host 'The kill switch could not confirm that ClawFactory stopped. Treat it as still'      -ForegroundColor Red
Write-Host 'running. Reboot the machine, or run'                                                -ForegroundColor Red
Write-Host '  wsl --shutdown'                                                                   -ForegroundColor Red
Write-Host 'from a Windows terminal, which stops the sandbox and everything inside it.'         -ForegroundColor Red
exit 2
