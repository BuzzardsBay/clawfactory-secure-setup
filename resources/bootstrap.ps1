[CmdletBinding()]
param(
    [string]$WslDistro = 'Ubuntu',
    [string]$WslUser   = 'clawuser',
    [string]$LogFile   = (Join-Path $env:ProgramData 'ClawFactory\install.log')
)

# bootstrap.ps1 — installs role-specific agent.md prompts into clawuser's
# ~/.openclaw/agents/<name>/ dirs and prints the exact next-step commands.
#
# Runs on Windows (PowerShell 5.1, the same runtime setup.ps1 runs in). All
# WSL-side work goes through wsl.exe + a base64-decoded bash heredoc, mirroring
# setup.ps1's Invoke-WslBash. File writes use atomic tmp+rename, the same
# convention as Step-ApplySafetyRules.
#
# Why not "run pwsh inside WSL": stock Ubuntu doesn't ship pwsh, and the
# nftables egress firewall (Step 7 of setup.ps1) does not whitelist
# packages.microsoft.com — so apt-installing pwsh would fail without firewall
# changes (out of scope per the task constraints). Running on Windows is
# functionally equivalent: the agent.md files still land in clawuser's home
# inside WSL, owned by clawuser, mode 644.
#
# Idempotent: re-running overwrites each agent.md atomically. Existing files
# are replaced via mv -f over the tmp file.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

#--- Logging -----------------------------------------------------------------
function Write-BootstrapLog {
    param([string]$Level, [string]$Message)
    $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Level] [bootstrap] $Message"
    if (Test-Path -LiteralPath (Split-Path -Parent $LogFile)) {
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    }
    if     ($Level -eq 'ERROR') { Write-Host $line -ForegroundColor Red }
    elseif ($Level -eq 'WARN')  { Write-Host $line -ForegroundColor Yellow }
    else                        { Write-Host $line }
}

#--- WSL helper (mirrors setup.ps1's Invoke-WslBash on purpose) --------------
function Invoke-WslBash {
    param([Parameter(Mandatory)][string]$Script)
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'wsl.exe'
    $psi.Arguments              = "-d $WslDistro -u $WslUser --cd ~ -- bash -lc `"echo '$enc' | base64 -d | bash -l`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $proc   = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    foreach ($line in ($stdout -split "`r?`n")) {
        $t = $line.Trim()
        if ($t) {
            if (Test-Path -LiteralPath (Split-Path -Parent $LogFile)) {
                Add-Content -LiteralPath $LogFile -Value "[wsl:$WslUser out] $t" -Encoding UTF8
            }
            Write-Host $t
        }
    }
    foreach ($line in ($stderr -split "`r?`n")) {
        $t = $line.Trim()
        # Filter benign WSL warnings (PATH entries it couldn't translate).
        if ($t -and ($t -notmatch '^wsl: Failed to translate ')) {
            if (Test-Path -LiteralPath (Split-Path -Parent $LogFile)) {
                Add-Content -LiteralPath $LogFile -Value "[wsl:$WslUser err] $t" -Encoding UTF8
            }
            Write-Host $t -ForegroundColor Yellow
        }
    }
    return $proc.ExitCode
}

#--- Agent map ---------------------------------------------------------------
# Source-of-truth for which file in resources/ maps to which agent dir.
# A missing file produces a placeholder agent.md, never a silent skip.
$ResourceDir = $PSScriptRoot
$Agents = @(
    [pscustomobject]@{
        Name        = 'orchestrator'
        PromptFile  = 'orchestrator-prompt.md'
        Description = 'Routes work between scout/builder/publisher and is the only agent that talks to you directly.'
    },
    [pscustomobject]@{
        Name        = 'skill-scout'
        PromptFile  = 'skill-scout-prompt.md'
        Description = 'Mines real-evidence opportunities for new OpenClaw skills (no building, no publishing).'
    },
    [pscustomobject]@{
        Name        = 'skill-builder'
        PromptFile  = 'skill-builder-prompt.md'
        Description = 'Builds and tests OpenClaw skills from scout opportunities; never publishes on its own.'
    },
    [pscustomobject]@{
        Name        = 'publisher'
        PromptFile  = 'publisher-prompt.md'
        Description = 'After your explicit "GO", pushes a finished skill to ClawHub + GitHub and verifies it is live.'
    }
)

function New-PlaceholderPrompt {
    param([string]$Name, [string]$Description)
    @"
# $Name — placeholder

This agent's role-specific prompt has not shipped with this installer build.
The file ``resources/$($Name)-prompt.md`` was missing when bootstrap.ps1 ran;
this placeholder will be replaced atomically the next time the installer
runs against a build that does include the real prompt.

## What this agent is supposed to do

$Description

## What it can do today

Nothing useful, by design. Until a real prompt lands here, the orchestrator
will not route work to this agent — and a direct chat against it will get a
stub reply.

## Inherited safety boundaries

The factory-wide rules in ``~/.openclaw/SOUL.md`` apply to every agent
regardless of this file. SOUL.md is hash-pinned at install time and is
read-only (mode 444) until the next install.

## Tool allowlist

Falls back to the gateway-level allowlist. Inspect with
``openclaw config get tools`` from inside WSL as ``clawuser``.
"@
}

function Get-SoulSha256 {
    # Read ~/.openclaw/SOUL.md.sha256 from inside WSL. Returns '' if absent
    # (e.g., bootstrap is being re-run before Step-ApplySafetyRules has
    # completed). Caller decides what to do; we leave the {{SOUL_SHA256}}
    # placeholder unsubstituted so the orchestrator's integrity check fails
    # loudly instead of silently passing.
    $script = @"
if [ -f `"`$HOME/.openclaw/SOUL.md.sha256`" ]; then
    cat `"`$HOME/.openclaw/SOUL.md.sha256`"
fi
"@
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'wsl.exe'
    $psi.Arguments              = "-d $WslDistro -u $WslUser --cd ~ -- bash -lc `"echo '$enc' | base64 -d | bash -l`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $proc   = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    return $stdout.Trim()
}

function Write-AgentMd {
    param(
        [Parameter(Mandatory)][string]$AgentName,
        [Parameter(Mandatory)][string]$Content
    )
    # Base64-stream the content; bash writes <agent.md>.tmp.<pid> then
    # atomic-renames over <agent.md>. Mode 644.
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Content))
    $script = @"
set -euo pipefail
DIR="`$HOME/.openclaw/agents/$AgentName"
mkdir -p "`$DIR"
TMP="`$DIR/agent.md.tmp.`$`$"
printf '%s' '$b64' | base64 -d > "`$TMP"
chmod 644 "`$TMP"
mv -f "`$TMP" "`$DIR/agent.md"
SIZE=`$(wc -c < "`$DIR/agent.md")
echo "  ${AgentName}: agent.md installed (`$SIZE bytes)"
"@
    $rc = Invoke-WslBash -Script $script
    if ($rc -ne 0) { throw "Failed to write agent.md for $AgentName (exit=$rc)" }
}

function Write-DefaultAgentName {
    # Step-15 side-effect: ensure %ProgramData%\ClawFactory\agent-name.txt
    # exists with the silent default "Claw". Rename script and Studio's
    # NamingBanner both read from this file. We never overwrite an existing
    # value — if the user already renamed once, that decision sticks.
    $nameFile = Join-Path $env:ProgramData 'ClawFactory\agent-name.txt'
    if (Test-Path -LiteralPath $nameFile) {
        Write-BootstrapLog INFO "agent-name.txt already present at $nameFile; not overwriting."
        return
    }
    try {
        $tmp = "$nameFile.tmp.$PID"
        Set-Content -LiteralPath $tmp -Value 'Claw' -Encoding UTF8 -NoNewline
        Move-Item -LiteralPath $tmp -Destination $nameFile -Force
        Write-BootstrapLog INFO "Wrote default agent name (Claw) to $nameFile."
    } catch {
        Write-BootstrapLog WARN "Failed to write agent-name.txt: $($_.Exception.Message)"
    }
}

#--- Main --------------------------------------------------------------------
Write-BootstrapLog INFO "Bootstrap starting (resourceDir=$ResourceDir)."
Write-Host ''
Write-Host '== ClawFactory bootstrap: installing agent prompts ==' -ForegroundColor Cyan

Write-DefaultAgentName

$soulHash = Get-SoulSha256
if ($soulHash) {
    Write-BootstrapLog INFO "SOUL.md SHA-256 read from WSL: $($soulHash.Substring(0, [Math]::Min(16, $soulHash.Length)))..."
} else {
    Write-BootstrapLog WARN '~/.openclaw/SOUL.md.sha256 not found — orchestrator integrity check will literal-match {{SOUL_SHA256}} (intentional fail-loudly).'
}

foreach ($agent in $Agents) {
    $name       = $agent.Name
    $promptPath = Join-Path $ResourceDir $agent.PromptFile
    if (Test-Path -LiteralPath $promptPath) {
        $content = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
        if ($soulHash) {
            $content = $content -replace '\{\{SOUL_SHA256\}\}', $soulHash
        }
        Write-BootstrapLog INFO ("{0}: source={1} ({2:N0} chars)" -f $name, $agent.PromptFile, $content.Length)
    } else {
        $content = New-PlaceholderPrompt -Name $name -Description $agent.Description
        Write-BootstrapLog WARN "${name}: placeholder (no $($agent.PromptFile) shipped in resources/)"
    }
    Write-AgentMd -AgentName $name -Content $content
}

#--- FIX 4: auth-profiles per-agent fan-out ----------------------------------
# Refs openclaw/openclaw#44571 (auth-profiles only written to main agent),
# openclaw/openclaw#12003 (OpenAI auth not persisted to auth-profiles.json).
# The OpenClaw runtime reads auth from the per-agent canonical path
# ~/.openclaw/agents/<id>/agent/auth-profiles.json and the legacy fallback to
# ~/.openclaw/auth-profiles.json is unreliable across the 2026.4.x line.
# Step 12 (Step-WireProviderKey in setup.ps1) writes the legacy path; we
# fan it out to all 5 agent dirs (main + the 4 sub-agents) here in Step 15.
# Idempotent: cp overwrites cleanly, mkdir -p / chmod are idempotent.
# Graceful skip when SOURCE missing (Provider=later case).
$fanOutScript = @'
set -e
echo "[ClawFactory] Fanning out auth-profiles.json to all configured agents (refs openclaw/openclaw#44571, openclaw/openclaw#12003)"

SOURCE="$HOME/.openclaw/auth-profiles.json"
if [ ! -f "$SOURCE" ]; then
    echo "[ClawFactory] No auth-profiles.json at $SOURCE - skipping fan-out (likely Provider=later)"
    exit 0
fi

for agent in main orchestrator publisher skill-builder skill-scout; do
    target_dir="$HOME/.openclaw/agents/$agent/agent"
    mkdir -p "$target_dir"
    cp "$SOURCE" "$target_dir/auth-profiles.json"
    chmod 600 "$target_dir/auth-profiles.json"
    if [ -f "$target_dir/auth-profiles.json" ]; then
        echo "[ClawFactory]   $agent: auth-profiles wired"
    else
        echo "[ClawFactory] ERROR: failed to write auth-profiles for $agent" >&2
        exit 13
    fi
done
'@
$rcFanOut = Invoke-WslBash -Script $fanOutScript
if ($rcFanOut -ne 0) {
    Write-BootstrapLog WARN "auth-profiles fan-out returned $rcFanOut; check ~/.openclaw/agents/<id>/agent/auth-profiles.json manually."
}

Write-BootstrapLog INFO 'Bootstrap complete.'

# Append 'AgentBootstrap' to %ProgramData%\ClawFactory\checkpoint.json. Mirrors
# setup.ps1's Save-Checkpoint shape: ordered hashtable -> JSON, idempotent via
# -notcontains. The smoke-test checks completedSteps for 'AgentBootstrap' to
# confirm Step 15 (this script) finished. Wrapped in try/catch because a
# checkpoint write failure must not block the user from seeing the next-steps
# guidance below.
$checkpointFile = Join-Path $env:ProgramData 'ClawFactory\checkpoint.json'
try {
    $state = [ordered]@{ completedSteps = @() }
    if (Test-Path -LiteralPath $checkpointFile) {
        $json = Get-Content -LiteralPath $checkpointFile -Raw | ConvertFrom-Json
        $state.completedSteps = @($json.completedSteps)
    }
    if ($state.completedSteps -notcontains 'AgentBootstrap') {
        $state.completedSteps += 'AgentBootstrap'
        $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $checkpointFile -Encoding UTF8
        Write-BootstrapLog INFO "Checkpoint updated: AgentBootstrap appended to $checkpointFile."
    } else {
        Write-BootstrapLog INFO "Checkpoint already contains AgentBootstrap; nothing to do."
    }
} catch {
    Write-BootstrapLog WARN "Failed to update checkpoint at ${checkpointFile}: $($_.Exception.Message)"
}

#--- "What to do next" -------------------------------------------------------
Write-Host ''
Write-Host '================================================================' -ForegroundColor Green
Write-Host '   Agents configured. What to do next:                         ' -ForegroundColor Green
Write-Host '================================================================' -ForegroundColor Green
Write-Host ''
Write-Host ' 1. Start the OpenClaw gateway (one-time after install):' -ForegroundColor White
Write-Host '      wsl -d Ubuntu -u clawuser -- bash -lc "systemctl --user start openclaw-gateway"' -ForegroundColor Gray
Write-Host ''
Write-Host ' 2. Verify it is reachable from this host:' -ForegroundColor White
Write-Host '      curl http://127.0.0.1:8787/status' -ForegroundColor Gray
Write-Host '      (Expect HTTP 200. Any LAN machine that tries the same URL is' -ForegroundColor Gray
Write-Host '       blocked by the Windows Firewall inbound-deny rule on TCP/8787.)' -ForegroundColor Gray
Write-Host ''
Write-Host ' 3. Open a chat session with the orchestrator:' -ForegroundColor White
Write-Host '      wsl -d Ubuntu -u clawuser -- bash -lc "openclaw chat"' -ForegroundColor Gray
Write-Host '      (Pick "orchestrator" from the agent list when the TUI prompts.)' -ForegroundColor Gray
Write-Host ''
Write-Host ' 4. The four agents:' -ForegroundColor White
foreach ($agent in $Agents) {
    Write-Host ('      - {0,-15} {1}' -f $agent.Name, $agent.Description) -ForegroundColor Gray
}
Write-Host ''
Write-Host ' 5. Logs:' -ForegroundColor White
Write-Host '      Installer:   %ProgramData%\ClawFactory\install.log' -ForegroundColor Gray
Write-Host '      OpenClaw:    wsl -d Ubuntu -u clawuser -- ls /tmp/openclaw/' -ForegroundColor Gray
Write-Host ''
Write-Host ' 6. Emergency stop (Start Menu "ClawFactory Kill Switch" or):' -ForegroundColor White
Write-Host '      powershell -ExecutionPolicy Bypass -File "<install-dir>\resources\clawfactory-stop.ps1"' -ForegroundColor Gray
Write-Host ''
Write-Host ' To re-run this configuration step at any time:' -ForegroundColor White
Write-Host '      powershell -ExecutionPolicy Bypass -File "<install-dir>\resources\bootstrap.ps1"' -ForegroundColor Gray
Write-Host ''

exit 0
