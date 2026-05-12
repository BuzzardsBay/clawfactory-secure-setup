[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('grok','openai','claude','gemini','ollama')]
    [string]$Provider,

    [Parameter()]
    [string]$ApiKey   # optional; if omitted you'll be prompted (password-masked)
)

# Switch the active provider for an existing ClawFactory install.
# - Stores the new API key in Windows Credential Manager (unless Ollama).
# - Updates auth.profiles.<id> + auth.order.<provider> in openclaw.json
#   via `openclaw config set` (canonical CLI; never edits the JSON directly).
# - Sets default model via `openclaw models set <prefix>/<model>`.
# - Updates egress firewall: detects nftables vs iptables-legacy backend,
#   re-applies the full baseHosts allowlist + new provider, and persists to
#   /etc/clawfactory/allowed-ips.txt so boot-time apply matches.
# - Restarts the OpenClaw gateway via `systemctl --user` so the new
#   provider takes effect immediately (no manual restart needed).
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

# Per-provider data. Shape mirrors setup.ps1's $ProviderConfig + the
# auth-profile fields Step-ConfigureOpenClaw writes. ModelPrefix is the
# `openclaw models set` namespace; ProfileId is the openclaw.json
# auth.profiles dot-path key; InternalId is what openclaw expects in
# the profile.provider field (note: claude maps to "anthropic").
$ProviderMap = @{
    grok    = @{
        Cred         = 'ClawFactory/GrokApiKey'
        ModelPrefix  = 'grok'
        Model        = 'grok-4-1-fast'
        ProfileId    = 'grok:default'
        InternalId   = 'grok'
        DisplayName  = 'Grok (xAI)'
        Mode         = 'api_key'
        Host         = 'api.x.ai'
    }
    openai  = @{
        Cred         = 'ClawFactory/OpenAIApiKey'
        ModelPrefix  = 'openai'
        Model        = 'gpt-5'
        ProfileId    = 'openai:default'
        InternalId   = 'openai'
        DisplayName  = 'OpenAI (ChatGPT)'
        Mode         = 'api_key'
        Host         = 'api.openai.com'
    }
    claude  = @{
        Cred         = 'ClawFactory/AnthropicApiKey'
        ModelPrefix  = 'anthropic'
        Model        = 'claude-sonnet-4-6'
        ProfileId    = 'anthropic:default'
        InternalId   = 'anthropic'
        DisplayName  = 'Anthropic Claude'
        Mode         = 'api_key'
        Host         = 'api.anthropic.com'
    }
    gemini  = @{
        Cred         = 'ClawFactory/GeminiApiKey'
        ModelPrefix  = 'gemini'
        Model        = 'gemini-2.5-pro'
        ProfileId    = 'gemini:default'
        InternalId   = 'gemini'
        DisplayName  = 'Google Gemini'
        Mode         = 'api_key'
        Host         = 'generativelanguage.googleapis.com'
    }
    ollama  = @{
        Cred         = $null
        ModelPrefix  = 'ollama'
        Model        = 'llama3.1:8b'
        ProfileId    = 'ollama:default'
        InternalId   = 'ollama'
        DisplayName  = 'Ollama (local)'
        Mode         = 'token'
        Host         = $null   # local-only; no external host needed in allowlist
    }
}
$cfg = $ProviderMap[$Provider]

# Bash transport helper. Normalizes CRLF -> LF before base64 encoding so
# bash doesn't choke on `set -e\r` (v1.0.x CR bug pattern that setup.ps1's
# Invoke-WslBash also guards against -- see setup.ps1:536).
function Invoke-WslBashBlock {
    param(
        [Parameter(Mandatory)][string]$Script,
        [Parameter(Mandatory)][string]$User,
        [string]$Cd = '/'
    )
    $normalized = $Script.Replace("`r`n", "`n").Replace("`r", "`n")
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
    $null = wsl -d $WslDistro -u $User --cd $Cd -- bash -lc "echo '$b64' | base64 -d | bash -l"
    return $LASTEXITCODE
}

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

# 2. Update egress firewall (backend-aware: nftables OR iptables-legacy)
# baseHosts list must stay in sync with setup.ps1 Step-EgressFirewall ($baseHosts).
# /etc/clawfactory/allowed-ips.txt is updated so the boot-time
# clawfactory-fw.service re-applies the same allowlist on next WSL boot --
# without this, the OLD provider's IPs would come back at boot.
$providerHostLiteral = if ($cfg.Host) { $cfg.Host } else { '' }
$fwScript = @"
set -euo pipefail

# Full baseHosts list -- must stay in sync with setup.ps1 Step-EgressFirewall.
# 19 hosts: github (4) + openclaw/clawhub (4) + npm/node (3) + docker (3) + ubuntu apt (5).
BASE_HOSTS="api.github.com github.com raw.githubusercontent.com codeload.github.com openclaw.ai docs.openclaw.ai clawhub.ai api.clawhub.ai registry.npmjs.org nodejs.org deb.nodesource.com registry-1.docker.io auth.docker.io production.cloudflare.docker.com archive.ubuntu.com security.ubuntu.com ports.ubuntu.com esm.ubuntu.com ppa.launchpad.net"
PROVIDER_HOST="$providerHostLiteral"

# Resolve all allowlist hosts to IPv4s.
ALLOWED_IPS=""
for h in `$BASE_HOSTS `$PROVIDER_HOST; do
    [ -z "`$h" ] && continue
    for ip in `$(getent ahostsv4 "`$h" 2>/dev/null | awk '{print `$1}' | sort -u); do
        ALLOWED_IPS="`$ALLOWED_IPS `$ip"
    done
done

# Detect active backend (set by setup.ps1 Step-EgressFirewall at install).
BACKEND="`$(cat /etc/clawfactory/fw-backend 2>/dev/null || echo nftables)"

if [ "`$BACKEND" = "iptables-legacy" ]; then
    IPT="`$(command -v iptables-legacy || true)"
    [ -n "`$IPT" ] || { echo "[switch-provider] iptables-legacy missing" >&2; exit 1; }
    "`$IPT" -F OUTPUT
    "`$IPT" -A OUTPUT -m owner --uid-owner clawuser -o lo -j ACCEPT
    "`$IPT" -A OUTPUT -m owner --uid-owner clawuser -p udp --dport 53 -j ACCEPT
    "`$IPT" -A OUTPUT -m owner --uid-owner clawuser -p tcp --dport 53 -j ACCEPT
    "`$IPT" -A OUTPUT -m owner --uid-owner clawuser -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    for ip in `$ALLOWED_IPS; do
        "`$IPT" -A OUTPUT -m owner --uid-owner clawuser -d "`$ip" -p tcp --dport 443 -j ACCEPT
    done
    "`$IPT" -A OUTPUT -m owner --uid-owner clawuser -d 127.0.0.1 -p tcp --dport 11434 -j ACCEPT
    "`$IPT" -A OUTPUT -m owner --uid-owner clawuser -j DROP
else
    /usr/sbin/nft flush set inet clawfactory allowed_ipv4 2>/dev/null || true
    for ip in `$ALLOWED_IPS; do
        /usr/sbin/nft add element inet clawfactory allowed_ipv4 "{ `$ip }" 2>/dev/null || true
    done
fi

# Persist for boot-time apply (clawfactory-fw.service reads this file).
mkdir -p /etc/clawfactory
printf '%s\n' `$ALLOWED_IPS | sed '/^`$/d' > /etc/clawfactory/allowed-ips.txt

HOST_COUNT=`$(echo `$BASE_HOSTS `$PROVIDER_HOST | wc -w)
IP_COUNT=`$(echo `$ALLOWED_IPS | wc -w)
echo "[switch-provider] firewall updated; backend=`$BACKEND; hosts=`$HOST_COUNT; ips=`$IP_COUNT"
"@

# v1.0.3 regression guard: ensure the literal /usr/sbin/nft token survives
# transport. Same assertion as setup.ps1 Step-EgressFirewall line 1181.
if ($fwScript -notmatch '/usr/sbin/nft') {
    throw 'switch-provider: firewall script missing /usr/sbin/nft full-path token.'
}

$fwExit = Invoke-WslBashBlock -Script $fwScript -User 'root' -Cd '/'
if ($fwExit -ne 0) {
    Write-Warning "Firewall update returned exit $fwExit. Check above output for details."
}
Write-Host "  [x] egress allowlist updated (backend auto-detected)"

# 3. Update openclaw.json via openclaw CLI (no python3, no direct JSON edit).
# Builds auth.profiles.<id> + auth.order.<provider> using `openclaw config
# set --strict-json` -- matches setup.ps1 Step-ConfigureOpenClaw lines
# 1761-1777. Sets default model via `openclaw models set` -- canonical CLI
# matches setup.ps1:1755. Restarts gateway so the new config takes effect
# (gateway caches config at startup; same restart pattern as setup.ps1
# Step-EnableChatCompletions).
$profileObject = [ordered]@{
    provider    = $cfg.InternalId
    mode        = $cfg.Mode
    displayName = $cfg.DisplayName
}
$profileJson = ConvertTo-Json -Compress -InputObject $profileObject
$orderJson   = ConvertTo-Json -Compress -InputObject @($cfg.ProfileId)
$modelId     = "$($cfg.ModelPrefix)/$($cfg.Model)"

$ocScript = @"
set -euo pipefail
openclaw config set auth.profiles.'$($cfg.ProfileId)' --strict-json '$profileJson' >/dev/null
openclaw config set auth.order.'$($cfg.InternalId)' --strict-json '$orderJson' >/dev/null
openclaw models set '$modelId' >/dev/null
echo "[switch-provider] config set (profile=$($cfg.ProfileId), order=$($cfg.InternalId), model=$modelId)"
systemctl --user restart openclaw-gateway 2>&1 || true
for i in 1 2 3 4 5 6; do
    if curl -fsS --max-time 5 http://127.0.0.1:8787/status >/dev/null 2>&1; then
        echo "[switch-provider] gateway healthy on attempt `$i"
        exit 0
    fi
    sleep 2
done
echo "[switch-provider] WARNING: gateway did not respond within 12s after restart" >&2
exit 1
"@
$ocExit = Invoke-WslBashBlock -Script $ocScript -User $WslUser -Cd '/home/clawuser'
if ($ocExit -eq 0) {
    Write-Host "  [x] openclaw config updated (model=$modelId, profile=$($cfg.ProfileId))"
} else {
    Write-Warning "openclaw config update returned exit $ocExit (profile=$($cfg.ProfileId), model=$modelId)."
}

Write-Host ''
if ($ocExit -eq 0) {
    Write-Host "Switched to $Provider. Gateway restarted automatically; switch is live." -ForegroundColor Green
} else {
    Write-Host "Switched to $Provider (gateway did not confirm health within 12s)." -ForegroundColor Yellow
    Write-Host 'If the gateway is unresponsive, restart it manually:'
    Write-Host '  wsl -d Ubuntu -u clawuser -- bash -lc "systemctl --user restart openclaw-gateway"'
}
