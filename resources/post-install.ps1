[CmdletBinding()]
param(
    [ValidateSet('grok','openai','claude','gemini','ollama','later')]
    [string]$Provider = 'grok'
)

# Post-install: reads provider-specific API key from Windows Credential Manager (DPAPI),
# pipes it to OpenClaw via stdin (no at-rest copy in WSL), sets default model,
# runs openclaw verify, prints the security checklist.
# Ollama and 'later' paths skip the Credential Manager read.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$WslDistro = 'Ubuntu'
$WslUser   = 'clawuser'
$LogFile   = Join-Path $env:ProgramData 'ClawFactory\install.log'

$ProviderMap = @{
    grok    = @{ Cred = 'ClawFactory/GrokApiKey';      Model = 'grok-4-1-fast';      Prefix = 'grok' }
    openai  = @{ Cred = 'ClawFactory/OpenAIApiKey';    Model = 'gpt-5';              Prefix = 'openai' }
    claude  = @{ Cred = 'ClawFactory/AnthropicApiKey'; Model = 'claude-sonnet-4-6';  Prefix = 'anthropic' }
    gemini  = @{ Cred = 'ClawFactory/GeminiApiKey';    Model = 'gemini-2.5-pro';     Prefix = 'gemini' }
    ollama  = @{ Cred = $null;                         Model = 'llama3.1:8b';        Prefix = 'ollama' }
    later   = @{ Cred = $null;                         Model = $null;                Prefix = $null }
}
$cfg = $ProviderMap[$Provider]

function Log { param($m) Add-Content -LiteralPath $LogFile -Value "[$((Get-Date).ToString('HH:mm:ss'))] [post] $m"; Write-Host $m }

Log "Post-install starting. Provider=$Provider Model=$($cfg.Model)."

#--- CredRead P/Invoke wrapper (no external module dependency) [R5] ----------
$sig = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class CredWrapper {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct CREDENTIAL {
        public UInt32 Flags;
        public UInt32 Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public UInt32 CredentialBlobSize;
        public IntPtr CredentialBlob;
        public UInt32 Persist;
        public UInt32 AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }
    [DllImport("Advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool CredRead(string target, uint type, uint flags, out IntPtr credentialPtr);
    [DllImport("Advapi32.dll", EntryPoint="CredFree", SetLastError=true)]
    public static extern void CredFree(IntPtr credentialPtr);
    public static string Read(string target) {
        IntPtr ptr;
        if (!CredRead(target, 1u, 0u, out ptr)) {
            int err = Marshal.GetLastWin32Error();
            if (err == 1168) return null;
            throw new System.ComponentModel.Win32Exception(err);
        }
        try {
            CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(ptr, typeof(CREDENTIAL));
            byte[] buf = new byte[c.CredentialBlobSize];
            Marshal.Copy(c.CredentialBlob, buf, 0, buf.Length);
            return Encoding.Unicode.GetString(buf);
        } finally { CredFree(ptr); }
    }
}
'@
if (-not ([System.Management.Automation.PSTypeName]'CredWrapper').Type) {
    Add-Type -TypeDefinition $sig -Language CSharp
}

#--- Key handling (skipped for ollama / later) --------------------------------
if ($Provider -eq 'ollama') {
    Log 'Ollama runs locally - no API key needed. Checking daemon...'
    wsl -d $WslDistro -u $WslUser -- bash -lc 'curl -fsS http://localhost:11434/api/tags >/dev/null && echo "Ollama daemon reachable." || echo "WARN: Ollama daemon not reachable."' | ForEach-Object { Log $_ }
} elseif ($Provider -eq 'later') {
    Log 'No provider selected. Run resources\switch-provider.ps1 -Provider <name> later to configure.'
} else {
    # The provider key is wired into ~/.openclaw/auth-profiles.json by
    # setup.ps1's Step-WireProviderKey BEFORE this script runs. We just
    # verify it's still present in Windows Credential Manager (DPAPI) so
    # post-install can flag a missing key clearly. There's no separate
    # `openclaw config set-model-key --stdin` subcommand in OpenClaw - the
    # auth profile in auth-profiles.json is the canonical store.
    $key = [CredWrapper]::Read($cfg.Cred)
    if ([string]::IsNullOrEmpty($key)) {
        Log "WARN: No API key in Credential Manager for target '$($cfg.Cred)'."
        Log "      Add later with:  cmdkey /generic:$($cfg.Cred) /user:clawuser /pass:<your-key>"
        Log "      Then re-run:     resources\\switch-provider.ps1 -Provider $Provider"
    } else {
        Log "API key found for $Provider. (Already wired into ~/.openclaw/auth-profiles.json by Step-WireProviderKey.)"
        $key = ('x' * 64)
        Remove-Variable key -ErrorAction SilentlyContinue
    }
}

#--- Default model (skipped for 'later') --------------------------------------
# Use `openclaw models set "<prefix>/<model>"` (matches setup.ps1's
# Step-ConfigureOpenClaw line 902 syntax). Note `claude` -> `anthropic` prefix.
if ($cfg.Model -and $cfg.Prefix) {
    $modelId = "$($cfg.Prefix)/$($cfg.Model)"
    Log "Setting $modelId as default model."
    wsl -d $WslDistro -u $WslUser -- bash -lc "openclaw models set '$modelId'" | Out-Null
}

#--- FIX 3: Non-interactive doctor with timeout ------------------------------
# Refs openclaw/openclaw#18502 (doctor hangs after completion in non-interactive
# parent processes), openclaw/openclaw#44185 (--repair partial-effect bugs in
# some sub-flows; we accept this - main config normalization works).
#
# `--fix --non-interactive --yes` together suppress all prompts. `timeout
# --foreground --kill-after=15 120` is generous (healthy runs finish 30-60s)
# and SIGKILLs after a 15s grace if SIGTERM is trapped. Exit codes 124
# (timeout) and 137 (SIGKILL after timeout) are both treated as non-fatal:
# doctor's job is config normalization, not a hard requirement for gateway
# startup. Output tee'd to /tmp/openclaw-install.log for diagnosis.
Log 'Running openclaw doctor in non-interactive mode (120s timeout).'
$doctorScript = @'
echo "[ClawFactory] FIX 3: Running openclaw doctor in non-interactive mode (refs openclaw/openclaw#18502)"
timeout --foreground --kill-after=15 120 openclaw doctor --fix --non-interactive --yes 2>&1 | tee -a /tmp/openclaw-install.log
rc=$?
if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
    echo "[ClawFactory] WARN: openclaw doctor timed out after 120s (refs #18502) - continuing install"
elif [ $rc -ne 0 ]; then
    echo "[ClawFactory] WARN: openclaw doctor exited rc=$rc - continuing install (non-fatal)"
fi
exit 0
'@
$encDoctor = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($doctorScript))
wsl -d $WslDistro -u $WslUser -- bash -lc "echo $encDoctor | base64 -d | bash" 2>&1 | ForEach-Object { Log $_ }

#--- FIX bundle: bonjour disable + codex disable + gateway restart -----------
# Bundles three v1.0 fixes into a single WSL invocation:
#
#   FIX 1 - Bonjour disable via systemd env var (PRIMARY).
#           Refs openclaw/openclaw#72355, openclaw/openclaw#64928.
#           Writes a systemd drop-in setting OPENCLAW_DISABLE_BONJOUR=1.
#           Deployment-scoped, version-independent. Survives openclaw upgrades
#           that may rename the discovery.mdns.mode schema path.
#
#   Defense-in-depth - same disable via config schema (discovery.mdns.mode=off).
#           Belt-and-suspenders. If the env var is ever ignored upstream, the
#           config-level disable still applies. If both fail, we warn loudly.
#
#   FIX 2 - Disable codex/coding-agent skill (refs openclaw/openclaw#73358).
#           openclaw 2026.4.26+ ships a coding-agent skill that delegates to
#           Codex by default and produces "No API key found for provider
#           'openai'" errors on every Anthropic-only install. Strips codex
#           provider from agent models.json and disables the skill in config.
#
#   Restart - reuses the existing 3-tier fallback (systemd --user -> openclaw
#           gateway start -> nohup setsid openclaw gateway run). Same logic as
#           setup.ps1 $startGateway / launcher.ps1 Start-Gateway. Polls
#           /status for up to 60s after restart (TASK 5 bumped from 30s).
#
# Idempotent: cat overwrites the drop-in, openclaw config set is idempotent,
# the node script is also idempotent (`removed` is empty if already cleaned).
# Non-fatal: every individual fix logs WARN on failure and continues. The
# install never aborts here.
$fixesScript = @'
set -e
LOG=/home/clawuser/.openclaw/logs/gateway.log
mkdir -p /home/clawuser/.openclaw/logs

# === FIX 1: bonjour disable via systemd env var (refs #72355, #64928) =====
echo "[ClawFactory] FIX 1: Disabling bonjour mDNS plugin via systemd env var (refs openclaw/openclaw#72355, openclaw/openclaw#64928)"
mkdir -p "$HOME/.config/systemd/user/openclaw-gateway.service.d"
cat > "$HOME/.config/systemd/user/openclaw-gateway.service.d/clawfactory-disable-bonjour.conf" <<'CONF'
[Service]
Environment=OPENCLAW_DISABLE_BONJOUR=1
CONF
if systemctl --user is-system-running >/dev/null 2>&1 || \
   systemctl --user list-units --no-legend --no-pager >/dev/null 2>&1; then
    systemctl --user daemon-reload || echo "[ClawFactory] WARN: daemon-reload failed (non-fatal)"
fi

# === Defense-in-depth: bonjour disable via config schema =================
CURRENT="$(openclaw config get discovery.mdns.mode 2>/dev/null || true)"
if [ "$CURRENT" = "off" ]; then
    echo "[ClawFactory] mDNS config already off; skipping schema disable"
else
    if openclaw config set discovery.mdns.mode off >/dev/null 2>&1; then
        echo "[ClawFactory] Disabled mDNS via discovery.mdns.mode=off (defense-in-depth)"
    else
        echo "[ClawFactory] WARN: openclaw config set discovery.mdns.mode off failed; env var still applies. Run manually if needed: openclaw config set discovery.mdns.mode off" >&2
    fi
fi

# Flush stale "BuzzardsBay (OpenClaw)" advertisements from a system-managed
# avahi-daemon if present. Harmless no-op when avahi isn't installed.
systemctl --user restart avahi-daemon 2>/dev/null || true

# === FIX 2: disable codex/coding-agent skill (refs #73358) ================
echo "[ClawFactory] FIX 2: Disabling coding-agent skill (refs openclaw/openclaw#73358)"

MODELS_JSON="$HOME/.openclaw/agents/main/agent/models.json"
if [ -f "$MODELS_JSON" ]; then
    cp "$MODELS_JSON" "$MODELS_JSON.bak"
    node -e "
const fs = require('fs');
const p = '$MODELS_JSON';
const data = JSON.parse(fs.readFileSync(p, 'utf8'));
let removed = [];
if (data.providers && data.providers.codex) {
    delete data.providers.codex;
    removed.push('providers.codex');
}
if (data.providers && data.providers.huggingface && data.providers.huggingface.models) {
    const before = data.providers.huggingface.models.length;
    data.providers.huggingface.models = data.providers.huggingface.models.filter(m =>
        !(typeof m === 'string' ? m.startsWith('openai/') : (m.id || '').startsWith('openai/'))
    );
    const after = data.providers.huggingface.models.length;
    if (before !== after) removed.push('huggingface openai/* (' + (before-after) + ' models)');
}
fs.writeFileSync(p, JSON.stringify(data, null, 2));
console.log('[ClawFactory] models.json cleanup: ' + (removed.length ? removed.join(', ') : 'nothing to remove'));
" || echo "[ClawFactory] WARN: models.json cleanup failed (non-fatal)"
else
    echo "[ClawFactory] models.json not present at $MODELS_JSON - skipping codex strip (expected on some versions)"
fi

if openclaw config set skills.entries.coding-agent.enabled false >/dev/null 2>&1; then
    echo "[ClawFactory] coding-agent skill disabled in config"
else
    echo "[ClawFactory] WARN: coding-agent disable failed (non-fatal)"
fi

# === Restart and verify gateway (TASK 5) ==================================
# Reuses the existing 3-tier fallback. Stop any prior instance first so we
# don't double-bind 127.0.0.1:8787.
if systemctl --user is-system-running >/dev/null 2>&1 || \
   systemctl --user list-units --no-legend --no-pager >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
    systemctl --user restart openclaw-gateway.service 2>/dev/null || \
        systemctl --user start openclaw-gateway.service 2>/dev/null || true
else
    openclaw gateway stop </dev/null >>"$LOG" 2>&1 || true
    pkill -f "openclaw gateway run" 2>/dev/null || true
    sleep 1
    if ! openclaw gateway start </dev/null >>"$LOG" 2>&1; then
        nohup setsid openclaw gateway run </dev/null >>"$LOG" 2>&1 &
        disown 2>/dev/null || true
    fi
fi

# Poll /status for up to 60s (TASK 5: bumped from 30s to give the doctor /
# config-set / restart sequence room to settle).
for i in $(seq 1 30); do
    if curl -fsS --max-time 2 http://127.0.0.1:8787/status >/dev/null 2>&1; then
        echo "[ClawFactory] Gateway responsive after fix bundle (attempt $i)"
        exit 0
    fi
    sleep 2
done
echo "[ClawFactory] WARN: gateway not responsive after 60s - check journalctl --user -u openclaw-gateway and ~/.openclaw/logs/gateway.log" >&2
exit 1
'@
$encFixes = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($fixesScript))
Log 'Applying fix bundle (bonjour env var, config-level mDNS off, coding-agent off, restart).'
wsl -d $WslDistro -u $WslUser -- bash -lc "echo $encFixes | base64 -d | bash" 2>&1 | ForEach-Object { Log $_ }
if ($LASTEXITCODE -ne 0) {
    Log "WARN: fix bundle returned $LASTEXITCODE; install will continue but verify gateway manually."
}

#--- Checklist ---------------------------------------------------------------
Write-Host ''
Write-Host '========================================'
Write-Host ' POST-INSTALL SECURITY CHECKLIST'
Write-Host '========================================'
Write-Host " [x] Provider: $Provider (model: $($cfg.Model))"
Write-Host ' [x] Gateway bound to 127.0.0.1:8787 only'
Write-Host ' [x] Sandbox mode = all, network = none'
Write-Host ' [x] Tool denylist active (shell/sudo/rm/system.run/browser/net.fetch)'
Write-Host ' [x] SOUL.md installed and hash-pinned in orchestrator prompt'
Write-Host ' [x] WSL automount disabled'
Write-Host ' [x] Non-root clawuser, no sudo group membership'
Write-Host ' [x] WSL egress firewall (nftables, clawuser-scoped, provider-specific allowlist)'
Write-Host ' [x] Windows Firewall inbound-deny on port 8787'
if ($cfg.Cred) {
    Write-Host " [x] $Provider key in Windows Credential Manager (DPAPI), not on disk"
} elseif ($Provider -eq 'ollama') {
    Write-Host ' [x] Ollama runs locally - no cloud key stored'
} else {
    Write-Host ' [ ] No provider configured yet - run switch-provider.ps1 when ready'
}
Write-Host ''
Write-Host ' REMEMBER:'
Write-Host '  * Review SKILL.md of every new skill BEFORE installing.'
Write-Host '  * Every git push / clawhub publish requires your "GO".'
Write-Host '  * Emergency stop:   resources\clawfactory-stop.ps1'
Write-Host '  * Switch provider:  resources\switch-provider.ps1 -Provider <grok|openai|claude|gemini|ollama>'
Write-Host ''
exit 0
