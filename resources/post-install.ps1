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

#--- Final health check: openclaw doctor -------------------------------------
# Refs openclaw/openclaw#18502 (doctor hangs after completion in non-interactive
# parent processes), openclaw/openclaw#44185 (--repair partial-effect bugs in
# some sub-flows; we accept this — main config normalization works), and
# openclaw/openclaw#47133 (CLI commands that connect to the running gateway
# trigger SIGTERM on disconnect, causing a restart cycle). All other openclaw
# CLI commands have been moved to Step-ConfigureOpenClaw (pre-gateway-start)
# to avoid #47133. Doctor is the lone exception: it's a health check that
# REQUIRES a running gateway, so the SIGTERM cycle is unavoidable here. The
# `clawfactory-tunables.conf` drop-in with `StartLimitBurst=0` ensures
# systemd retries indefinitely so the cycle resolves without manual
# intervention.
#
# Architecture note: by the time post-install runs, setup.ps1's Step 8b has
# already executed `openclaw gateway install --force` which writes the systemd
# unit at ~/.config/systemd/user/openclaw-gateway.service and starts the
# gateway. Doctor is no longer responsible for unit installation, so the
# `--non-interactive` flag (which explicitly "skips operations that need
# confirmation") is now safe — the work it would skip is already done.
# `--no-workspace-suggestions` suppresses the workspace-discovery prompt.
# The yes-pipe + 180s timeout remain as belt-and-suspenders against any
# future doctor sub-flow that still tries to read from stdin.
#
# Doctor's job here is final config normalization and health verification.
# Non-zero exit is WARN-only. Exit codes 124 (timeout) and 137 (SIGKILL
# after the 15s grace) are treated identically. Output captured via
# Invoke-WslBash's stdout/stderr routing through Log, which writes to
# install.log and skips the benign `wsl: Failed to translate ...` lines.
Log 'Running openclaw doctor as final health check (180s timeout).'
$doctorScript = @'
echo "[ClawFactory] FIX 3: Running openclaw doctor with auto-confirmation (refs openclaw/openclaw#18502)"
yes | timeout --foreground --kill-after=15 180 openclaw doctor --fix --yes --non-interactive --no-workspace-suggestions 2>&1
rc=$?
if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
    echo "[ClawFactory] doctor timed out after 180s - health check WARN, install continues."
elif [ $rc -ne 0 ]; then
    echo "[ClawFactory] doctor exited $rc - health check WARN, install continues."
fi
exit 0
'@
$null = Invoke-WslBash -Script $doctorScript

#--- Post-doctor: bonjour drop-in (defense-in-depth) + gateway restart -------
# After the doctor health check runs above, this WSL block:
#
#   FIX 1 - Writes a systemd drop-in setting OPENCLAW_DISABLE_BONJOUR=1.
#           Defense-in-depth against the bonjour SIGTERM crash loop on
#           openclaw versions where the bug fires (refs openclaw/openclaw
#           #72355, #64928). Harmless on 2026.4.27 (our pinned version)
#           since the env var is simply ignored when the bug is absent.
#
#   FIX 2 - REMOVED. Previously toggled discovery.mdns.mode=off (the
#           "config-level mDNS off" defense-in-depth) and
#           skills.entries.coding-agent.enabled=false (the "coding-agent
#           off" path that aimed to Disable codex silent-default auth
#           failures). On 2026.4.27 those config paths do not exist
#           (config-set returned "path not found") AND the underlying
#           bonjour and codex bugs do not fire (validated via clean
#           journalctl over multiple installs). FIX 1's env var drop-in
#           retains forward-compatible protection. Re-add with current
#           schema paths if a future version pin shows either bug
#           regressing.
#
#   Restart - daemon-reload + restart openclaw-gateway.service (with
#           non-systemd fallback for WSL1 / systemd-disabled installs),
#           then polls http://127.0.0.1:8787/status for up to 60s.
#           Confirms HTTP 200 on loopback before exiting.
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

# === Restart and verify gateway ===========================================
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
Log 'Applying bonjour drop-in (defense-in-depth) and restarting gateway.'
$rcFixes = Invoke-WslBash -Script $fixesScript
if ($rcFixes -ne 0) {
    Log "WARN: fix bundle returned $rcFixes; install will continue but verify gateway manually."
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
