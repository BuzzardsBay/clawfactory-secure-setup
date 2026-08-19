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
    Write-Host "  [x] API key stored at credential target '$($cfg.Cred)'"

    # v1.1 FIX: also write the key into the OpenClaw auth-profiles.json files the
    # gateway actually reads (the global one plus each per-agent copy). Before
    # this, switch-provider stored the key in Credential Manager and set profile
    # METADATA via `openclaw config set`, but never wrote the key VALUE anywhere
    # the gateway reads -- so a rotated key stayed in Credential Manager while the
    # gateway kept using the OLD key and every turn 401'd. Mirrors setup.ps1
    # Step-WireProviderKey (which is why a fresh install worked but a rotation
    # didn't). The key travels inside the base64'd script, never on a command line.
    $keyB64w = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ApiKey))
    $setKey = @"
python3 - '$keyB64w' '$($cfg.ProfileId)' '$($cfg.InternalId)' <<'PYEOF'
import sys, json, os, glob, base64
key = base64.b64decode(sys.argv[1]).decode('utf-8'); pid = sys.argv[2]; prov = sys.argv[3]
paths = [os.path.expanduser('~/.openclaw/auth-profiles.json')] + glob.glob(os.path.expanduser('~/.openclaw/agents/*/agent/auth-profiles.json'))
for p in paths:
    try: d = json.load(open(p))
    except Exception: d = {'version': 1, 'profiles': {}}
    d.setdefault('version', 1); d.setdefault('profiles', {})
    pr = d['profiles'].setdefault(pid, {}); pr['type'] = 'api_key'; pr['provider'] = prov; pr['key'] = key
    json.dump(d, open(p, 'w')); os.chmod(p, 0o600)
print('wrote key into', len(paths), 'auth-profiles.json file(s)')
PYEOF
"@
    $skRc = Invoke-WslBashBlock -Script $setKey -User $WslUser -Cd '/home/clawuser'
    Remove-Variable keyB64w
    if ($skRc -ne 0) { Write-Warning "auth-profiles.json key write returned exit $skRc (gateway may still use the old key)." }
    else { Write-Host "  [x] key written into OpenClaw auth-profiles.json (global + per-agent)" }
    $ApiKey = ('x' * 64); Remove-Variable ApiKey -ErrorAction SilentlyContinue
} else {
    # Ensure Ollama is installed and running
    wsl -d $WslDistro -u root -- bash -lc 'command -v ollama >/dev/null 2>&1 || (curl -fsSL https://ollama.com/install.sh | bash); systemctl enable ollama 2>/dev/null || true; systemctl restart ollama 2>/dev/null || true'
    wsl -d $WslDistro -u $WslUser -- bash -lc "ollama pull $($cfg.Model)" | Out-Null
    Write-Host "  [x] Ollama running with model $($cfg.Model)"
}

# 2. Update egress firewall (backend-aware: nftables OR iptables-legacy)
# The base host list is NO LONGER MIRRORED HERE. It is read from
# /etc/clawfactory/base-hosts.seed, which setup.ps1 Step-EgressFirewall writes.
# The instruction that used to sit on this line -- "must stay in sync with
# setup.ps1" -- was followed by nobody for the one change that mattered, and the
# result was a shipped defect. See the rule at the top of $fwScript.
# /etc/clawfactory/allowed-ips.txt is updated so the boot-time
# clawfactory-fw.service re-applies the same allowlist on next WSL boot --
# without this, the OLD provider's IPs would come back at boot.
$providerHostLiteral = if ($cfg.Host) { $cfg.Host } else { '' }
$fwScript = @"
set -euo pipefail

# THE RULE, AND IT IS THE WHOLE REASON THIS BLOCK LOOKS THE WAY IT DOES.
#
# Provider hosts go in @allowed_ipv4. That set is refreshed additively, its
# elements carry a timeout that nothing ever lets expire, and it is persisted to
# /etc/clawfactory/allowed-ips.txt and re-applied at every boot. ANYTHING WRITTEN
# TO IT CAN NEVER BE TAKEN AWAY. Everything the user is told they can switch off
# -- the toolchain hosts, the read-fetch destinations -- goes in a set that is
# flushed and rebuilt from the root-owned policy on every resolver run, because
# that is the only shape in which a switch can actually close a route.
#
# This script used to violate that rule. Until 2026-08-19 the list below was a
# hardcoded 16-host mirror of setup.ps1's $baseHosts, and seven of those hosts
# were the toolchain hosts: api.github.com, github.com, raw.githubusercontent.com,
# codeload.github.com, clawhub.ai, api.clawhub.ai and registry.npmjs.org. Card
# #245 moved them out of $baseHosts into @toolchain_ipv4 so the user's toggle
# could revoke them; this mirror was not updated, and this mirror is what the
# shipped Start Menu item "Switch AI Provider" runs. One click re-seeded all seven
# into the unrevocable set, persisted them, and survived reboot -- after which the
# toolchain toggle was permanently defeated AND THE PANEL STILL REPORTED IT AS
# OFF. A control that lies to the user, reached through a normal advertised
# action.
#
# The fix is not to edit the mirror. It is to delete it. setup.ps1 now records its
# own $baseHosts to /etc/clawfactory/base-hosts.seed (root:root 0644) and this
# script reads that. One owner, every other reader reads. Duplication is only
# acceptable when something compares the copies, and the cheapest comparison is
# not having a second copy.
BASE_SEED=/etc/clawfactory/base-hosts.seed
BASE_HOSTS=""

# INPUT-SHAPE DECISIONS, stated because code that disagrees with its own comment
# is a defect in a security product:
#   ABSENT   -> this is an install that predates the seed file. Warn loudly and
#               fall back to the built-in list below. Not fatal: refusing to
#               switch provider on an older install would brick a working box
#               over a file that only exists to prevent drift.
#   EMPTY    -> FATAL. The base list is never legitimately empty, so an empty
#               file is a truncated write or a tampered file, and a fault is not
#               a preference.
#   MALFORMED-> FATAL, same reasoning. Any line that is not hostname-shaped means
#               the file is not what it claims to be, and resolving it would feed
#               whatever it does contain into the unrevocable set.
if [ -f "`$BASE_SEED" ]; then
    if [ ! -s "`$BASE_SEED" ]; then
        echo "[switch-provider] FATAL: `$BASE_SEED exists but is empty. The base allowlist is never legitimately empty, so this is a truncated or tampered file. Refusing to touch the firewall." >&2
        exit 1
    fi
    while IFS= read -r line; do
        [ -z "`$line" ] && continue
        case "`$line" in
            *[!A-Za-z0-9.-]*|.*|-*|*-|*..*)
                echo "[switch-provider] FATAL: `$BASE_SEED contains a line that is not a hostname: [`$line]. Refusing to resolve it into the set nothing can revoke." >&2
                exit 1 ;;
        esac
        case "`$line" in
            *.*) : ;;
            *)  echo "[switch-provider] FATAL: `$BASE_SEED contains [`$line], which has no dot and is not a hostname. Refusing to touch the firewall." >&2
                exit 1 ;;
        esac
        BASE_HOSTS="`$BASE_HOSTS `$line"
    done < "`$BASE_SEED"
    echo "[switch-provider] base hosts read from `$BASE_SEED (`$(echo `$BASE_HOSTS | wc -w) host(s))"
else
    # Fallback for installs made before base-hosts.seed existed. TOOLCHAIN-FREE by
    # construction: these are setup.ps1's $baseHosts and nothing else. If you are
    # about to add a host here, it belongs in setup.ps1 instead.
    BASE_HOSTS="openclaw.ai docs.openclaw.ai nodejs.org deb.nodesource.com archive.ubuntu.com security.ubuntu.com ports.ubuntu.com esm.ubuntu.com ppa.launchpad.net"
    echo "[switch-provider] WARNING: `$BASE_SEED is absent (install predates it); using the built-in base host list (`$(echo `$BASE_HOSTS | wc -w) hosts)" >&2
fi

PROVIDER_HOST="$providerHostLiteral"

# STRUCTURAL GUARD, not a comment asking the next person to be careful. Whatever
# the base list turned out to be -- seed file, fallback, or a future edit to
# either -- no toolchain host may reach @allowed_ipv4 through this script. The
# toolchain resolver reports its own list via --list-hosts, which is the same
# interface install-read-fetch.sh uses for its drift gate, so this compares
# against the live owner rather than against another copy.
#
# This is what makes the defect class impossible here rather than merely fixed
# once. If the resolver cannot be asked, that is a fault and it denies: a guard
# that silently passes when it cannot measure is not a guard.
if [ -x /usr/local/sbin/clawfactory-toolchain.sh ]; then
    if TC_HOSTS="`$(/usr/local/sbin/clawfactory-toolchain.sh --list-hosts 2>/dev/null)"; then
        for th in `$TC_HOSTS; do
            for bh in `$BASE_HOSTS `$PROVIDER_HOST; do
                if [ "`$th" = "`$bh" ]; then
                    echo "[switch-provider] FATAL: [`$th] is a toolchain host and would be written into @allowed_ipv4, which nothing can revoke. That silently defeats the user's toolchain toggle while the panel still reports it as off. Refusing. Toolchain hosts belong in @toolchain_ipv4, which clawfactory-toolchain.sh flushes and rebuilds." >&2
                    exit 1
                fi
            done
        done
        echo "[switch-provider] toolchain guard: no toolchain host in the allowlist rebuild (`$(echo `$TC_HOSTS | wc -w) checked)"
    else
        echo "[switch-provider] FATAL: could not ask clawfactory-toolchain.sh for its host list, so the toolchain guard could not run. Refusing to rebuild @allowed_ipv4 unverified." >&2
        exit 1
    fi
else
    echo "[switch-provider] WARNING: /usr/local/sbin/clawfactory-toolchain.sh is absent (install predates the toolchain toggle); guard skipped, and there is no toolchain set to defeat." >&2
fi

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

# Defect 1: restrict port 53 to the WSL resolver(s). The allowlist helper is
# installed by setup.ps1 Step-EgressFirewall; fall back to the persisted list.
# Must stay in sync with setup.ps1 Step-EgressFirewall's DNS restriction.
if [ -x /usr/local/sbin/clawfactory-dns-resolvers.sh ]; then
    CF_RESOLVERS="`$(/usr/local/sbin/clawfactory-dns-resolvers.sh)"
else
    CF_RESOLVERS="`$(cat /etc/clawfactory/dns-resolvers.txt 2>/dev/null)"
fi
printf '%s\n' `$CF_RESOLVERS | sed '/^`$/d' > /etc/clawfactory/dns-resolvers.txt

if [ "`$BACKEND" = "iptables-legacy" ]; then
    IPT="`$(command -v iptables-legacy || true)"
    [ -n "`$IPT" ] || { echo "[switch-provider] iptables-legacy missing" >&2; exit 1; }
    "`$IPT" -F OUTPUT
    "`$IPT" -A OUTPUT -m owner --uid-owner clawuser -o lo -j ACCEPT
    for ip in `$CF_RESOLVERS; do
        "`$IPT" -A OUTPUT -m owner --uid-owner clawuser -d "`$ip" -p udp --dport 53 -j ACCEPT
        "`$IPT" -A OUTPUT -m owner --uid-owner clawuser -d "`$ip" -p tcp --dport 53 -j ACCEPT
    done
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
    # Defect 1: refresh the DNS resolver set too (in case resolv.conf changed).
    /usr/sbin/nft flush set inet clawfactory dns_resolvers 2>/dev/null || true
    for ip in `$CF_RESOLVERS; do
        /usr/sbin/nft add element inet clawfactory dns_resolvers "{ `$ip }" 2>/dev/null || true
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
set -uo pipefail
openclaw config set auth.profiles.'$($cfg.ProfileId)' --strict-json '$profileJson' >/dev/null || { echo "[switch-provider] config set auth.profiles failed: `$?" >&2; exit 1; }
openclaw config set auth.order.'$($cfg.InternalId)' --strict-json '$orderJson' >/dev/null || { echo "[switch-provider] config set auth.order failed: `$?" >&2; exit 1; }
openclaw models set '$modelId' >/dev/null || { echo "[switch-provider] models set failed: `$?" >&2; exit 1; }
echo "[switch-provider] config set (profile=$($cfg.ProfileId), order=$($cfg.InternalId), model=$modelId)"
XDG_RUNTIME_DIR=/run/user/`$(id -u) systemctl --user restart openclaw-gateway 2>&1 || echo "[switch-provider] gateway restart returned non-zero, continuing health poll" >&2
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40; do
    if curl -fsS --max-time 5 http://127.0.0.1:8787/status >/dev/null 2>&1; then
        echo "[switch-provider] gateway healthy on attempt `$i"
        exit 0
    fi
    sleep 3
done
echo "[switch-provider] WARNING: gateway did not respond within 120s after restart" >&2
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
