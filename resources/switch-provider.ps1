[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('grok','openai','claude','gemini','ollama')]
    [string]$Provider,

    [Parameter()]
    [string]$ApiKey   # optional; if omitted you'll be prompted (password-masked)
)

# Switch the active provider for an existing ClawFactory install.
# - Updates nftables allowlist (removes old provider host, adds new one).
# - Stores the new API key in Windows Credential Manager (unless Ollama).
# - Updates openclaw.json model.default and keySource.
# - Does NOT reinstall anything. Does NOT touch SOUL.md or agents.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

# Elevation check
$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object System.Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'switch-provider.ps1 must be run as Administrator (needs to modify nftables inside WSL and Windows Firewall).'
}

$WslDistro = 'Ubuntu'
$WslUser   = 'clawuser'

$ProviderMap = @{
    grok    = @{ Cred = 'ClawFactory/GrokApiKey';      Model = 'grok-4-1-fast';       Host = 'api.x.ai' }
    openai  = @{ Cred = 'ClawFactory/OpenAIApiKey';    Model = 'gpt-5';               Host = 'api.openai.com' }
    claude  = @{ Cred = 'ClawFactory/AnthropicApiKey'; Model = 'claude-sonnet-4-6';   Host = 'api.anthropic.com' }
    gemini  = @{ Cred = 'ClawFactory/GeminiApiKey';    Model = 'gemini-2.5-pro';      Host = 'generativelanguage.googleapis.com' }
    ollama  = @{ Cred = $null;                         Model = 'llama3.1:8b';         Host = $null }
}
$cfg = $ProviderMap[$Provider]

Write-Host "Switching active provider to: $Provider" -ForegroundColor Cyan

# 1. Store API key (unless Ollama)
if ($Provider -ne 'ollama') {
    if (-not $ApiKey) {
        $secure = Read-Host "Paste your $Provider API key" -AsSecureString
        $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        $ApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    cmdkey /generic:$($cfg.Cred) /user:clawuser /pass:$ApiKey | Out-Null
    $ApiKey = ('x' * 64); Remove-Variable ApiKey -ErrorAction SilentlyContinue
    Write-Host "  [x] API key stored at credential target '$($cfg.Cred)'"
} else {
    # Ensure Ollama is installed and running
    wsl -d $WslDistro -u root -- bash -lc 'command -v ollama >/dev/null 2>&1 || (curl -fsSL https://ollama.com/install.sh | bash); systemctl enable ollama 2>/dev/null || true; systemctl restart ollama 2>/dev/null || true'
    wsl -d $WslDistro -u $WslUser -- bash -lc "ollama pull $($cfg.Model)" | Out-Null
    Write-Host "  [x] Ollama running with model $($cfg.Model)"
}

# 2. Update nftables allowlist inside WSL (flush provider-specific hosts, add new one)
$updateScript = @"
set -euo pipefail
# Drop all old dynamic entries (they'll re-resolve from the allowlist below)
nft flush set inet clawfactory allowed_ipv4 2>/dev/null || true
BASE="api.github.com github.com raw.githubusercontent.com registry-1.docker.io auth.docker.io production.cloudflare.docker.com"
PROVIDER="$($cfg.Host)"
for h in \$BASE \$PROVIDER; do
    [ -z "\$h" ] && continue
    for ip in \$(getent ahostsv4 "\$h" 2>/dev/null | awk '{print \$1}' | sort -u); do
        nft add element inet clawfactory allowed_ipv4 "{ \$ip }" 2>/dev/null || true
    done
done
"@
wsl -d $WslDistro -u root --cd ~ -- bash -lc "echo '$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($updateScript)))' | base64 -d | bash -l"
Write-Host '  [x] nftables egress allowlist updated'

# 3. Update openclaw.json
$patch = @"
set -euo pipefail
cd ~/skills-factory
python3 - <<'PY'
import json, pathlib
p = pathlib.Path('openclaw.json')
d = json.loads(p.read_text())
d['model'] = {
    'provider':  '$Provider',
    'default':   '$($cfg.Model)',
    'keySource': ( 'windows-credential-manager:$($cfg.Cred)' if '$($cfg.Cred)' else 'none' ),
    'endpoint':  ( 'http://localhost:11434/v1' if '$Provider'=='ollama' else None ),
}
p.write_text(json.dumps(d, indent=2))
PY
chmod 600 openclaw.json
"@
wsl -d $WslDistro -u $WslUser --cd ~ -- bash -lc "echo '$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($patch)))' | base64 -d | bash -l"
Write-Host "  [x] openclaw.json default model set to '$($cfg.Model)'"

Write-Host ''
Write-Host "Switched. Restart the orchestrator to pick up the change:" -ForegroundColor Green
Write-Host '  wsl -d Ubuntu -u clawuser -- bash -lc "cd ~/skills-factory && openclaw restart orchestrator"'
