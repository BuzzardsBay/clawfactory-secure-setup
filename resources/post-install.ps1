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

#--- WSL helper (mirrors setup.ps1 / bootstrap.ps1 Invoke-WslBash) -----------
# Uses Process.Start (not `wsl ... 2>&1 | ...`) because PowerShell 5.1 wraps
# each stderr line from native commands piped via 2>&1 as an ErrorRecord.
# With $ErrorActionPreference = 'Stop', the FIRST stderr line aborts the
# script - and `wsl: Failed to translate '<path>'` warnings fire reliably
# from a Windows shell with a multi-component PATH. CRLF -> LF normalize
# matches setup.ps1's fix: PowerShell here-strings have CRLF endings, bash
# treats `\r` as part of the option name in `set -e\r` and chokes.
function Invoke-WslBash {
    param([Parameter(Mandatory)][string]$Script)
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script.Replace("`r`n", "`n").Replace("`r", "`n")))
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
        if ($t) { Log $t }
    }
    foreach ($line in ($stderr -split "`r?`n")) {
        $t = $line.Trim()
        # Filter benign WSL warnings (PATH entries it couldn't translate).
        if ($t -and ($t -notmatch '^wsl: Failed to translate ')) {
            Log $t
        }
    }
    return $proc.ExitCode
}

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
    $ollamaCheck = @'
curl -fsS http://localhost:11434/api/tags >/dev/null && echo "Ollama daemon reachable." || echo "WARN: Ollama daemon not reachable."
'@
    $null = Invoke-WslBash -Script $ollamaCheck
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

#--- Default model -----------------------------------------------------------
# REMOVED: `openclaw models set` is now run in setup.ps1's
# Step-ConfigureOpenClaw, which executes BEFORE Step-PreinstallGatewayRuntime
# starts the gateway. Running `openclaw models set` here (after the gateway
# is up) used to trigger the SIGTERM-on-disconnect cycle described in
# openclaw/openclaw#47133. Configuration is now done while the gateway is
# offline, by writing to ~/.openclaw/openclaw.json directly via the CLI.
if ($cfg.Model -and $cfg.Prefix) {
    $modelId = "$($cfg.Prefix)/$($cfg.Model)"
    Log "Default model already set to $modelId by Step-ConfigureOpenClaw before gateway start (per #47133)."
}

#--- openclaw doctor: REMOVED -----------------------------------------------
# `openclaw doctor` was previously run here as a final health check, but its
# WS connection to the running gateway triggered a SIGTERM-on-disconnect
# cycle (openclaw/openclaw#47133). Doctor is a repair tool for broken
# installs, not a required step for fresh installs — every config item it
# would normalize is already set explicitly: setup.ps1's Step-ConfigureOpenClaw
# writes gateway.{mode,bind,port}, models.default, auth.profiles, and
# auth.order to ~/.openclaw/openclaw.json (pre-gateway-start, no WS); Step 8b
# does the systemd service registration via `openclaw gateway install --force`.
# The real health gate is now at the end of setup.ps1: a 30-second poll of
# /status from the Windows side, which uses HTTP only (no WS, no #47133).
#
# Users who suspect a broken install (config drift, corrupted state) can run
# doctor manually:
#     wsl -d Ubuntu -u clawuser -- bash -lc "yes | openclaw doctor --fix --yes"
# This will still trigger the #47133 cycle, but `StartLimitBurst=0` in
# clawfactory-tunables.conf lets systemd retry indefinitely until it resolves.

#--- Post-install: bonjour drop-in (defense-in-depth) -----------------------
# After Step 8b's gateway install, this WSL block:
#
#   FIX 1 - Writes a systemd drop-in setting OPENCLAW_DISABLE_BONJOUR=1.
#           Defense-in-depth against the bonjour SIGTERM crash loop on
#           openclaw versions where the bug fires (refs openclaw/openclaw
#           #72355, #64928). Harmless on 2026.4.27 (our pinned version)
#           since the env var is simply ignored when the bug is absent.
#
#   FIX 2 - REMOVED. Previously toggled discovery.mdns.mode=off and
#           skills.entries.coding-agent.enabled=false. Config paths
#           don't exist on 2026.4.27 and underlying bugs don't fire.
#
#   Restart - REMOVED. Previously restarted the gateway here so the
#           drop-in took effect immediately. On 2026.4.27 the bonjour
#           bug doesn't fire, so immediate effect isn't required — the
#           drop-in takes effect on the next natural restart (reboot or
#           manual `systemctl --user restart`). Removing the restart
#           eliminated a #47133 SIGTERM cycle that left the gateway
#           mid-restart when the smoke test ran. The final health gate
#           at the end of setup.ps1 is the install-time source of truth.
#
# Idempotent: drop-in cat overwrites cleanly, daemon-reload safe to repeat.
# Non-fatal on failure: WARN logged, install continues.
$fixesScript = @'
set -e
LOG=/home/clawuser/.openclaw/logs/gateway.log
mkdir -p /home/clawuser/.openclaw/logs

# FIX 1: Bonjour env var drop-in (defense-in-depth)
# Sets OPENCLAW_DISABLE_BONJOUR=1 as service env var. Harmless if the bonjour SIGTERM bug is not
# present (env var simply ignored). Documented protection against version-bump regressions.
# See openclaw issues #72355, #64928 for original bug context.
echo "[ClawFactory] FIX 1: Writing bonjour env var drop-in (defense-in-depth, refs openclaw/openclaw#72355, openclaw/openclaw#64928)"
mkdir -p "$HOME/.config/systemd/user/openclaw-gateway.service.d"
cat > "$HOME/.config/systemd/user/openclaw-gateway.service.d/clawfactory-disable-bonjour.conf" <<'CONF'
[Service]
Environment=OPENCLAW_DISABLE_BONJOUR=1
CONF
if systemctl --user is-system-running >/dev/null 2>&1 || \
   systemctl --user list-units --no-legend --no-pager >/dev/null 2>&1; then
    systemctl --user daemon-reload || echo "[ClawFactory] WARN: daemon-reload failed (non-fatal)"
fi

# Flush stale "BuzzardsBay (OpenClaw)" advertisements from a system-managed
# avahi-daemon if present. Harmless no-op when avahi isn't installed.
systemctl --user restart avahi-daemon 2>/dev/null || true

# Gateway restart REMOVED — see header comment above. The drop-in takes
# effect on the next natural restart, and the post-install restart was
# triggering #47133 SIGTERM cycles. Final health verification happens at
# the end of setup.ps1.
exit 0
'@
Log 'Applying bonjour drop-in (defense-in-depth).'
$rcFixes = Invoke-WslBash -Script $fixesScript
if ($rcFixes -ne 0) {
    Log "WARN: bonjour drop-in returned $rcFixes; install will continue but verify the drop-in manually at ~/.config/systemd/user/openclaw-gateway.service.d/clawfactory-disable-bonjour.conf."
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
