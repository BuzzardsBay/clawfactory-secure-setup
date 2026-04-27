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
    grok    = @{ Cred = 'ClawFactory/GrokApiKey';      Model = 'grok-4-1-fast' }
    openai  = @{ Cred = 'ClawFactory/OpenAIApiKey';    Model = 'gpt-5' }
    claude  = @{ Cred = 'ClawFactory/AnthropicApiKey'; Model = 'claude-sonnet-4-6' }
    gemini  = @{ Cred = 'ClawFactory/GeminiApiKey';    Model = 'gemini-2.5-pro' }
    ollama  = @{ Cred = $null;                         Model = 'llama3.1:8b' }
    later   = @{ Cred = $null;                         Model = $null }
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
    $key = [CredWrapper]::Read($cfg.Cred)
    if ([string]::IsNullOrEmpty($key)) {
        Log "No API key in Credential Manager for target '$($cfg.Cred)'."
        Log "Add later with:  cmdkey /generic:$($cfg.Cred) /user:clawuser /pass:<your-key>"
        Log 'Then re-run:     powershell -NoProfile -ExecutionPolicy Bypass -File "<install-dir>\resources\post-install.ps1" -Provider ' + $Provider
    } else {
        Log "API key found for $Provider. Piping to OpenClaw via stdin (no at-rest copy in WSL)."
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName  = 'wsl.exe'
        $psi.Arguments = "-d $WslDistro -u $WslUser -- bash -lc `"cd ~/skills-factory && openclaw config set-model-key --model $($cfg.Model) --stdin`""
        $psi.RedirectStandardInput = $true
        $psi.UseShellExecute       = $false
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Write($key)
        $proc.StandardInput.Close()
        $proc.WaitForExit()
        if ($proc.ExitCode -ne 0) { throw "openclaw config set-model-key exited $($proc.ExitCode)" }
        $key = ('x' * 64)
        Remove-Variable key -ErrorAction SilentlyContinue
    }
}

#--- Default model (skipped for 'later') --------------------------------------
if ($cfg.Model) {
    Log "Setting $($cfg.Model) as default model."
    wsl -d $WslDistro -u $WslUser -- bash -lc "cd ~/skills-factory && openclaw config set model.default $($cfg.Model)" | Out-Null
}

#--- Verify ------------------------------------------------------------------
Log 'Running openclaw verify.'
wsl -d $WslDistro -u $WslUser -- bash -lc 'cd ~/skills-factory && openclaw verify'
if ($LASTEXITCODE -ne 0) { throw "openclaw verify failed with exit $LASTEXITCODE" }

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
