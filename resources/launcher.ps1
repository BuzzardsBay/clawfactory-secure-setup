[CmdletBinding()]
param(
    [string]$WslDistro  = 'Ubuntu',
    [string]$WslUser    = 'clawuser',
    [int]   $TimeoutSec = 15,
    [int]   $PollSec    = 2
)

# launcher.ps1 — desktop shortcut entry point.
#
# Wired in by the [Icons] entry in ClawFactory-Secure-Setup.iss. Runs as the
# end user (not admin) when they double-click the ClawFactory icon. The
# shortcut starts PowerShell with -WindowStyle Hidden, so this script must
# never spill console output. All user-facing errors come through a Windows
# MessageBox dialog.
#
# Sequence:
#   1. Ask `systemctl --user is-active openclaw-gateway` (inside WSL).
#      If "active" AND http://127.0.0.1:8787/status responds → log
#      ALREADY_RUNNING and open Windows Terminal into `openclaw chat`.
#   2. Otherwise, fire-and-forget `systemctl --user start openclaw-gateway`.
#   3. Poll http://127.0.0.1:8787/status every $PollSec seconds for up to
#      $TimeoutSec seconds via Invoke-WebRequest -UseBasicParsing -TimeoutSec 2.
#      As soon as it responds → log STARTED and open Windows Terminal into
#      `openclaw chat`.
#   4. If the deadline elapses with no response → log TIMEOUT and show a
#      single-button warning dialog with the canonical "could not start" copy.
#
# The dashboard at http://127.0.0.1:8787 is reachable via the Start Menu
# "ClawFactory Dashboard" shortcut for users who prefer the browser UI; the
# desktop double-click drops them into the TUI chat directly because the
# dashboard requires manual device pairing the installer doesn't yet wire up.
#
# The launcher log lives at $env:ProgramData\ClawFactory\launcher.log; one
# line per launch, written via tmp+rename for atomicity (matches the write
# convention used by bootstrap.ps1 and Step-ApplySafetyRules in setup.ps1).

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

Add-Type -AssemblyName System.Windows.Forms

#--- Constants ---------------------------------------------------------------
$DashboardUrl = 'http://127.0.0.1:8787'
$StatusUrl    = 'http://127.0.0.1:8787/status'
$LogDir       = Join-Path $env:ProgramData 'ClawFactory'
$LogFile      = Join-Path $LogDir 'launcher.log'

#--- Logging (atomic tmp+rename) --------------------------------------------
function Write-LauncherLog {
    # State semantics:
    #   STARTED         = launched `openclaw chat` after starting the gateway.
    #   ALREADY_RUNNING = launched `openclaw chat` with the gateway already up.
    #   TIMEOUT         = gateway failed to respond within $TimeoutSec; chat
    #                     was not launched and the failure dialog was shown.
    param([Parameter(Mandatory)][ValidateSet('STARTED', 'ALREADY_RUNNING', 'TIMEOUT')][string]$State)
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $line = "[$ts] [$State]"
        $existing = if (Test-Path -LiteralPath $LogFile) {
            Get-Content -LiteralPath $LogFile -Raw -Encoding UTF8
        } else { '' }
        $combined = $existing + $line + "`r`n"
        $tmp      = "$LogFile.tmp.$PID"
        Set-Content -LiteralPath $tmp -Value $combined -Encoding UTF8 -NoNewline
        Move-Item  -LiteralPath $tmp -Destination $LogFile -Force
    } catch {
        # Best-effort. A failed log write must never block the launcher from
        # opening the chat window or surfacing the failure dialog.
    }
}

#--- Helpers -----------------------------------------------------------------
function Show-FailureDialog {
    [System.Windows.Forms.MessageBox]::Show(
        "ClawFactory could not start. Check that WSL is running and try again.`n`nIf this keeps happening, use the Kill Switch from the Start Menu and restart.",
        'ClawFactory',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
}

function Test-GatewayResponding {
    # 200..399 → up. Connection refused, timeout, DNS, etc. → not yet.
    try {
        $resp = Invoke-WebRequest -Uri $StatusUrl -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        return ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400)
    } catch {
        return $false
    }
}

function Invoke-WslSilent {
    # Hidden-window wsl.exe call; returns @{ ExitCode; Stdout } with both
    # streams drained. Never spawns a visible console.
    param([Parameter(Mandatory)][string]$Command)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'wsl.exe'
    $psi.Arguments              = "-d $WslDistro -u $WslUser -- bash -lc `"$Command`""
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $proc   = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $null   = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return @{ ExitCode = $proc.ExitCode; Stdout = $stdout.Trim() }
}

function Invoke-WslSilentScript {
    # Multi-line variant of Invoke-WslSilent: base64-encodes the script so
    # quoting/escaping doesn't break across the powershell -> wsl -> bash
    # boundary. Mirrors setup.ps1's Invoke-WslBash strategy.
    param([Parameter(Mandatory)][string]$Script)
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'wsl.exe'
    $psi.Arguments              = "-d $WslDistro -u $WslUser -- bash -lc `"echo '$enc' | base64 -d | bash -l`""
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $null = $proc.StandardOutput.ReadToEnd()
    $null = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return $proc.ExitCode
}

function Start-Gateway {
    # Same three-tier fallback as setup.ps1's Step-PreinstallGatewayRuntime
    # `$startGateway` block: prefer systemd --user, fall back to
    # `openclaw gateway start`, fall back to `nohup setsid openclaw gateway run`.
    # Fire-and-forget; the Windows-side polling loop verifies via
    # http://127.0.0.1:8787/status. Idempotent: skips if gateway is already up.
    $script = @'
set -e
LOG=/home/clawuser/.openclaw/logs/gateway.log
mkdir -p /home/clawuser/.openclaw/logs

if curl -fsS --max-time 2 http://127.0.0.1:8787/status >/dev/null 2>&1; then
    exit 0
fi

SYSTEMD_OK=false
if systemctl --user is-system-running >/dev/null 2>&1 || \
   systemctl --user list-units --no-legend --no-pager >/dev/null 2>&1; then
    SYSTEMD_OK=true
fi

if [ "$SYSTEMD_OK" = "true" ]; then
    systemctl --user start openclaw-gateway.service 2>/dev/null || true
else
    if ! openclaw gateway start </dev/null >>"$LOG" 2>&1; then
        nohup setsid openclaw gateway run </dev/null >>"$LOG" 2>&1 &
        disown 2>/dev/null || true
    fi
fi
exit 0
'@
    $null = Invoke-WslSilentScript -Script $script
}

function Open-Chat {
    # Drop the user directly into `openclaw chat` running as clawuser inside
    # WSL. Windows Terminal first (ships with Win11, has tabs and a sane font);
    # plain PowerShell window as fallback for older Win10 boxes that haven't
    # had `wt` installed.
    $wt = Get-Command wt -ErrorAction SilentlyContinue
    if ($wt) {
        Start-Process wt -ArgumentList "wsl.exe -d $WslDistro -u $WslUser bash -lc `"openclaw chat`""
    } else {
        Start-Process powershell -ArgumentList "-NoProfile -NoExit -Command `"wsl -d $WslDistro -u $WslUser bash -lc 'openclaw chat'`""
    }
}

#--- 1. Already running? ----------------------------------------------------
# The HTTP /status probe is the real source of truth. The previous
# `systemctl --user is-active` check was systemd-specific and silently
# returned "inactive" on systemd-less WSL installs (WSL1 fallback or
# systemd-disabled), causing the launcher to always TIMEOUT.
if (Test-GatewayResponding) {
    Write-LauncherLog -State 'ALREADY_RUNNING'
    Open-Chat
    exit 0
}

#--- 2. Not running — start it (fire-and-forget; idempotent) ----------------
# Layered fallback: systemd --user → openclaw gateway start → nohup setsid
# openclaw gateway run. Same logic as setup.ps1's Step-PreinstallGatewayRuntime.
Start-Gateway

#--- 3. Poll for up to $TimeoutSec seconds ----------------------------------
$deadline = (Get-Date).AddSeconds($TimeoutSec)
do {
    Start-Sleep -Seconds $PollSec
    if (Test-GatewayResponding) {
        Write-LauncherLog -State 'STARTED'
        Open-Chat
        exit 0
    }
} while ((Get-Date) -lt $deadline)

#--- 4. Timed out -----------------------------------------------------------
Write-LauncherLog -State 'TIMEOUT'
Show-FailureDialog
exit 1
