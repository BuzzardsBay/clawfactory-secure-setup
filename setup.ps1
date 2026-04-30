[CmdletBinding()]
param(
    [switch]$AcknowledgedOpenClawUrl,
    [ValidateSet('grok','openai','claude','gemini','ollama','later')]
    [string]$Provider = 'grok',
    # Set when re-launched by RunOnce after a reboot triggered by Step-EnsureWsl.
    # Skips the WSL install and waits for the kernel to come up instead.
    [switch]$Resume,
    # Path to the original installer .exe; passed by Inno's [Run] section as
    # {srcexe} so we can register a RunOnce that relaunches the same .exe with
    # /SILENT /resume after a reboot. Empty when setup.ps1 is invoked outside
    # of the Inno wizard - in that case we fall back to relaunching setup.ps1
    # directly via powershell.exe.
    [string]$SourceExe = ''
)

# ClawFactory Secure Setup - main automation script.
# Runs as admin on Windows; drops to clawuser inside WSL for non-privileged work.
# Targets PowerShell 5.1 (ships with Win11) - no PS7 bootstrap required.
#
# Security controls baked in:
#   [R2] OpenClaw install.sh SHA-256 pinning (edit $OpenClawInstallSha256 below).
#   [R3] WSL egress firewall (nftables, clawuser UID-scoped, provider-specific allowlist).
#   [R4] Windows Firewall inbound-deny on gateway port.
#   [R5] Provider API key read from Windows Credential Manager (DPAPI).
#   [R6] SOUL.md hash pinned into orchestrator prompt.
#   [R7] Checkpoint + rollback on failure.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

#--- Constants ----------------------------------------------------------------
$OpenClawInstallUrl    = 'https://openclaw.ai/install.sh'
# [R2] Pin me. See README.md section "Pinning the OpenClaw install.sh hash".
$OpenClawInstallSha256 = '57f025ba0272e2da3238984360e37fad5230bc7cea81854d154a362ea989d49d'
# Pin OpenClaw npm package to a known-validated version.
# ClawFactory v1.0 ships with OpenClaw 2026.4.27 - the version manually
# validated on 2026-04-30 with the four bundled bug-workarounds intact:
#   - openclaw/openclaw#72355, #64928 (bonjour mDNS crash loop)
#   - openclaw/openclaw#73358 (codex/coding-agent silent default)
#   - openclaw/openclaw#44571, #12003 (auth-profiles per-agent path)
#   - openclaw/openclaw#18502 (doctor non-interactive hang)
# When bumping this pin, manually re-validate the four fixes against
# the new version before shipping. install.sh honors OPENCLAW_VERSION
# via env var (install.sh:1012, install_spec construction at 2342) - no
# fallback needed; install.sh:2354's @latest fallback only fires when
# OPENCLAW_VERSION literally equals 'latest', so a pinned version skips it.
$OpenClawNpmVersion    = '2026.4.27'
$LogDir                = Join-Path $env:ProgramData 'ClawFactory'
$LogFile               = Join-Path $LogDir 'install.log'
$CheckpointFile        = Join-Path $LogDir 'checkpoint.json'
$ProviderStateFile     = Join-Path $LogDir 'provider.json'
$WslDistro             = 'Ubuntu'
$WslUser               = 'clawuser'
$GatewayPort           = 8787
$FirewallRuleName      = 'ClawFactory-Block-Inbound-8787'
# Restart-and-resume plumbing for the WSL2-needs-a-reboot case.
$ResumeFlagFile        = Join-Path $LogDir 'resume-after-restart.flag'
$RunOnceRegPath        = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
$RunOnceRegName        = 'ClawFactoryResumeInstall'

#--- Provider map ------------------------------------------------------------
$ProviderConfig = @{
    grok = @{
        DisplayName      = 'Grok (xAI)'
        DefaultModel     = 'grok-4-1-fast'
        CredentialTarget = 'ClawFactory/GrokApiKey'
        AllowlistHosts   = @('api.x.ai')
        KeySource        = 'windows-credential-manager:ClawFactory/GrokApiKey'
        Endpoint         = 'https://api.x.ai/v1'
    }
    openai = @{
        DisplayName      = 'OpenAI (ChatGPT)'
        DefaultModel     = 'gpt-5'
        CredentialTarget = 'ClawFactory/OpenAIApiKey'
        AllowlistHosts   = @('api.openai.com')
        KeySource        = 'windows-credential-manager:ClawFactory/OpenAIApiKey'
        Endpoint         = 'https://api.openai.com/v1'
    }
    claude = @{
        DisplayName      = 'Anthropic Claude'
        DefaultModel     = 'claude-sonnet-4-6'
        CredentialTarget = 'ClawFactory/AnthropicApiKey'
        AllowlistHosts   = @('api.anthropic.com')
        KeySource        = 'windows-credential-manager:ClawFactory/AnthropicApiKey'
        Endpoint         = 'https://api.anthropic.com/v1'
    }
    gemini = @{
        DisplayName      = 'Google Gemini'
        DefaultModel     = 'gemini-2.5-pro'
        CredentialTarget = 'ClawFactory/GeminiApiKey'
        AllowlistHosts   = @('generativelanguage.googleapis.com')
        KeySource        = 'windows-credential-manager:ClawFactory/GeminiApiKey'
        Endpoint         = 'https://generativelanguage.googleapis.com/v1'
    }
    ollama = @{
        DisplayName      = 'Ollama (local)'
        DefaultModel     = 'llama3.1:8b'
        CredentialTarget = $null
        AllowlistHosts   = @('ollama.com','registry.ollama.ai')
        KeySource        = 'none'
        Endpoint         = 'http://localhost:11434/v1'
    }
    later = @{
        DisplayName      = 'None (configure later)'
        DefaultModel     = $null
        CredentialTarget = $null
        AllowlistHosts   = @()
        KeySource        = 'none'
        Endpoint         = $null
    }
}
$ThisProvider = $ProviderConfig[$Provider]

#--- Logging ------------------------------------------------------------------
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Level] $Message"
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    if     ($Level -eq 'ERROR') { Write-Host $line -ForegroundColor Red }
    elseif ($Level -eq 'WARN')  { Write-Host $line -ForegroundColor Yellow }
    else                        { Write-Host $line }
}

function Save-Checkpoint {
    param([string]$Step)
    $state = [ordered]@{ completedSteps = @() }
    if (Test-Path $CheckpointFile) {
        $json  = Get-Content -LiteralPath $CheckpointFile -Raw | ConvertFrom-Json
        $state.completedSteps = @($json.completedSteps)
    }
    # Idempotent: don't double-append if a step re-runs after a resume.
    if ($state.completedSteps -notcontains $Step) {
        $state.completedSteps += $Step
        $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $CheckpointFile -Encoding UTF8
    }
}

function Get-CompletedSteps {
    if (-not (Test-Path $CheckpointFile)) { return @() }
    $json = Get-Content -LiteralPath $CheckpointFile -Raw | ConvertFrom-Json
    return @($json.completedSteps)
}

#--- WSL availability + restart-and-resume -----------------------------------
function Test-WslFunctional {
    # True iff WSL2 + Ubuntu can actually run a command. Distinguishes:
    #   - WSL features just enabled but kernel not loaded (post-install,
    #     pre-reboot): `wsl --status` may succeed but `wsl -d Ubuntu -- true`
    #     fails or hangs.
    #   - WSL fully ready (post-reboot): both work.
    try {
        $null = & wsl.exe --status 2>&1
        if ($LASTEXITCODE -ne 0) { return $false }
    } catch { return $false }
    $list = (& wsl.exe --list --quiet 2>$null) -split "`n" |
        ForEach-Object { $_.Trim() -replace "`0", '' }
    if (-not ($list -contains $WslDistro)) { return $false }
    $null = & wsl.exe -d $WslDistro -u root -- true 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Save-ResumeFlag {
    param(
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$InstallDir,
        [string]$SourceExe         = '',
        [string]$CredentialTarget  = ''
    )
    # Atomic write: serialize to .tmp first, then move into place.
    $obj = [ordered]@{
        provider         = $Provider
        installDir       = $InstallDir
        sourceExe        = $SourceExe
        credentialTarget = $CredentialTarget
        timestamp        = (Get-Date).ToString('o')
    }
    $tmp = "$ResumeFlagFile.tmp"
    $obj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $ResumeFlagFile -Force
}

function Read-ResumeFlag {
    if (-not (Test-Path $ResumeFlagFile)) { return $null }
    try {
        return Get-Content -LiteralPath $ResumeFlagFile -Raw | ConvertFrom-Json
    } catch {
        Write-Log WARN "Could not parse resume flag at ${ResumeFlagFile}: $($_.Exception.Message)"
        return $null
    }
}

function Remove-ResumeFlag {
    if (Test-Path $ResumeFlagFile) {
        Remove-Item -LiteralPath $ResumeFlagFile -Force -ErrorAction SilentlyContinue
    }
}

function Set-RunOnceResume {
    param([string]$ExePath, [string]$ScriptPath)
    # Prefer relaunching the original installer .exe (so the user sees the
    # branded Inno wizard with /SILENT progress). Fall back to running
    # setup.ps1 directly if the .exe path is missing (e.g. user moved/deleted
    # the downloaded installer between launch and reboot).
    if ($ExePath -and (Test-Path -LiteralPath $ExePath)) {
        $cmd = "`"$ExePath`" /SILENT /resume"
    } else {
        $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -AcknowledgedOpenClawUrl -Resume"
    }
    if (-not (Test-Path $RunOnceRegPath)) {
        New-Item -Path $RunOnceRegPath -Force | Out-Null
    }
    Set-ItemProperty -Path $RunOnceRegPath -Name $RunOnceRegName -Value $cmd -Force
    Write-Log INFO "RunOnce registered: $cmd"
}

function Remove-RunOnceResume {
    if (-not (Test-Path $RunOnceRegPath)) { return }
    $existing = Get-ItemProperty -Path $RunOnceRegPath -Name $RunOnceRegName -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-ItemProperty -Path $RunOnceRegPath -Name $RunOnceRegName -Force -ErrorAction SilentlyContinue
    }
}

function Show-RestartDialog {
    param([string]$Title, [string]$Message)
    # Use WPF MessageBox so we don't depend on WinForms init order. Falls back
    # to a console prompt if PresentationFramework is unavailable (very rare
    # on Win11).
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Information') | Out-Null
    } catch {
        Write-Host ''
        Write-Host "==== $Title ====" -ForegroundColor Yellow
        Write-Host $Message
        Read-Host 'Press Enter to restart now'
    }
}

function Enable-WindowsFeaturesForWsl {
    # Three Windows features must be enabled for WSL2 to function on a clean
    # Win11 machine. After they're enabled the machine MUST reboot before the
    # WSL kernel is available. DISM exit codes: 0=success, 3010=success-needs-
    # restart. Both are fine here since we're about to restart anyway.
    Write-Log INFO 'Enabling Windows features for WSL via DISM (3 features).'
    $features = @(
        'Microsoft-Windows-Subsystem-Linux',
        'VirtualMachinePlatform',
        'HypervisorPlatform'
    )
    foreach ($f in $features) {
        Write-Log INFO "  DISM /enable-feature /featurename:$f"
        $proc = Start-Process -FilePath 'dism.exe' `
            -ArgumentList '/online','/enable-feature',"/featurename:$f",'/all','/norestart' `
            -NoNewWindow -PassThru -Wait
        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
            throw "Windows features could not be enabled. Please ensure you are running as Administrator. (DISM /featurename:$f exit=$($proc.ExitCode))"
        }
        Write-Log INFO "    DISM /featurename:$f -> exit $($proc.ExitCode)"
    }
}

function Install-WslDistroWithFallback {
    # Tries WSL2 first; on `HCS_E_HYPERV_NOT_INSTALLED` (0x80370102 - common in
    # nested-VM testing or hardware without VT-x) falls back to WSL1.
    # Returns the variant string ('wsl2' or 'wsl1') for logging.
    Write-Log INFO 'Installing Ubuntu (attempting WSL2 first).'
    $output = & wsl.exe --install --no-launch -d $WslDistro 2>&1
    $exit = $LASTEXITCODE
    foreach ($line in @($output)) {
        $t = ($line | Out-String).TrimEnd()
        if ($t) { Add-Content -LiteralPath $LogFile -Value "[wsl install out] $t" -Encoding UTF8 }
    }
    if ($exit -eq 0) {
        Write-Log INFO 'WSL2 install succeeded.'
        return 'wsl2'
    }
    $hyperVMissing = $false
    foreach ($line in @($output)) {
        $t = ($line | Out-String)
        if ($t -match 'HCS_E_HYPERV_NOT_INSTALLED' -or $t -match '0x80370102') {
            $hyperVMissing = $true; break
        }
    }
    if (-not $hyperVMissing) {
        throw "wsl --install failed (exit $exit) and no fallback signal detected. See $LogFile."
    }
    Write-Log WARN 'WSL2 unavailable (HCS_E_HYPERV_NOT_INSTALLED). Falling back to WSL1.'
    & wsl.exe --install --no-distribution 2>&1 |
        ForEach-Object { Add-Content -LiteralPath $LogFile -Value "[wsl install fallback] $_" -Encoding UTF8 }
    & wsl.exe --set-default-version 1 2>&1 |
        ForEach-Object { Add-Content -LiteralPath $LogFile -Value "[wsl set-default-version] $_" -Encoding UTF8 }
    & wsl.exe --install -d $WslDistro --no-launch 2>&1 |
        ForEach-Object { Add-Content -LiteralPath $LogFile -Value "[wsl install -d $WslDistro] $_" -Encoding UTF8 }
    if ($LASTEXITCODE -ne 0) {
        throw "WSL1 fallback install also failed (exit $LASTEXITCODE)."
    }
    Write-Log WARN 'WSL1 fallback install succeeded. Some features (systemd, networking) behave differently on WSL1.'
    return 'wsl1'
}

function New-ClawUserAndSetDefault {
    # Pre-creates clawuser as a TEMPORARY sudoer (NOPASSWD) so Ubuntu's
    # first-launch locale-setup script and other OOBE hooks don't block
    # waiting for an interactive default user, and sets it as the WSL
    # default in /etc/wsl.conf. Step-CreateClawUser strips both the sudoers
    # line and the sudo group membership later, restoring the non-privileged
    # security model (DEVIATION A2: clawuser is non-sudo at runtime).
    Write-Log INFO 'Pre-creating clawuser stub (temp sudoer) and setting WSL default user.'
    $script = @'
set -e
if ! id clawuser >/dev/null 2>&1; then
    useradd -m -s /bin/bash clawuser
fi
usermod -aG sudo clawuser
grep -qx 'clawuser ALL=(ALL) NOPASSWD:ALL' /etc/sudoers || \
    echo 'clawuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
touch /etc/wsl.conf
sed -i '/^\[user\]/,/^$/d' /etc/wsl.conf
printf '\n[user]\ndefault=clawuser\n' >> /etc/wsl.conf
chmod 644 /etc/wsl.conf
echo "clawuser-stub ready: uid=$(id -u clawuser)"
'@
    $rc = Invoke-WslBash -Script $script -User 'root'
    if ($rc -ne 0) { throw "Failed to pre-create clawuser stub (exit=$rc)" }
}

function Invoke-WslInstallWithRestart {
    # Caller has already run Enable-WindowsFeaturesForWsl. Persists resume
    # state, registers RunOnce, prompts the user, and reboots. The actual
    # `wsl --install -d Ubuntu` happens AFTER the reboot in the resume
    # branch of Step-EnsureWsl - until features are loaded post-reboot,
    # `wsl --install` cannot create a usable instance.
    Write-Log INFO 'Persisting resume state and scheduling restart for WSL setup.'

    $credTarget = if ($ThisProvider.CredentialTarget) { $ThisProvider.CredentialTarget } else { '' }
    Save-ResumeFlag -Provider $Provider -InstallDir $PSScriptRoot -SourceExe $SourceExe -CredentialTarget $credTarget

    $scriptPath = Join-Path $PSScriptRoot 'setup.ps1'
    Set-RunOnceResume -ExePath $SourceExe -ScriptPath $scriptPath

    Show-RestartDialog -Title 'ClawFactory - Restart Required' -Message (
        "WSL2 needs to be installed. Your computer will restart to complete this step.`r`n`r`n" +
        'ClawFactory will resume automatically after restart.'
    )

    Write-Log INFO 'Initiating restart.'
    try {
        Restart-Computer -Force
        # Restart-Computer is async - give the OS time to tear us down.
        Start-Sleep -Seconds 60
        exit 0
    } catch {
        Write-Log ERROR "Restart failed: $($_.Exception.Message). Reboot manually; ClawFactory will resume on next login."
        exit 0
    }
}

#--- Rollback [R7] ------------------------------------------------------------
function Invoke-Rollback {
    param([string[]]$CompletedSteps)
    Write-Log ERROR 'Running rollback for completed steps...'
    $reversed = @($CompletedSteps)
    [Array]::Reverse($reversed)
    foreach ($s in $reversed) {
        Write-Log INFO "Undoing: $s"
        switch ($s) {
            'FirewallRule' {
                Remove-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue
            }
            'EnsureWsl' {
                $ans = Read-Host "Rollback: unregister WSL '$WslDistro' distro? This deletes the Ubuntu distro and any files inside it. Type YES to confirm"
                if ($ans -eq 'YES') {
                    wsl --unregister $WslDistro 2>&1 | Out-Null
                    Write-Log INFO "WSL distro '$WslDistro' unregistered."
                } else {
                    Write-Log WARN 'WSL distro left in place by user choice.'
                }
            }
            default { }
        }
    }
}

function Invoke-WithRollback {
    param([scriptblock]$Body)
    try { & $Body }
    catch {
        Write-Log ERROR "Install failed: $($_.Exception.Message)"
        Write-Log ERROR $_.ScriptStackTrace
        $done = Get-CompletedSteps
        if ($done.Count -gt 0) {
            $ans = Read-Host 'Installation failed. Run automatic rollback? (y/N)'
            if ($ans -match '^[Yy]') {
                Invoke-Rollback -CompletedSteps $done
            } else {
                Write-Log INFO "Rollback skipped. Log: $LogFile"
            }
        }
        throw
    }
}

#--- WSL helper ---------------------------------------------------------------
# Uses Process.Start (not `wsl ... 2>&1`) because PowerShell 5.1 converts each
# stderr line from a native command to an ErrorRecord when merged via 2>&1,
# and with $ErrorActionPreference = 'Stop' that triggers a terminating error
# on harmless WSL warnings like "Failed to translate 'C:\\Windows\\system32'".
function Invoke-WslBash {
    param(
        [Parameter(Mandatory)][string]$Script,
        [string]$User = 'root'
    )
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'wsl.exe'
    # Use bash -lc (login shell) so ~/.profile is sourced and PATH picks up
    # ~/.local/bin for clawuser (where the openclaw shim lives).
    $psi.Arguments              = "-d $WslDistro -u $User --cd ~ -- bash -lc `"echo '$enc' | base64 -d | bash -l`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc   = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $exit = $proc.ExitCode

    foreach ($line in ($stdout -split "`r?`n")) {
        $t = $line.Trim()
        if ($t) { Add-Content -LiteralPath $LogFile -Value "[wsl:$User out] $t" -Encoding UTF8 }
    }
    foreach ($line in ($stderr -split "`r?`n")) {
        $t = $line.Trim()
        # Filter benign WSL warnings (PATH entries it couldn't translate).
        if ($t -and ($t -notmatch '^wsl: Failed to translate ')) {
            Add-Content -LiteralPath $LogFile -Value "[wsl:$User err] $t" -Encoding UTF8
        }
    }
    Add-Content -LiteralPath $LogFile -Value "[wsl:$User exit] $exit" -Encoding UTF8
    return $exit
}

#--- Steps --------------------------------------------------------------------
function Step-Preflight {
    Write-Log INFO "Step 1: Preflight checks. Selected provider: $($ThisProvider.DisplayName)."
    $os = Get-CimInstance Win32_OperatingSystem
    if ([int]$os.BuildNumber -lt 22000) {
        throw "Windows 11 required (detected build $($os.BuildNumber))."
    }
    try {
        $cpu = Get-CimInstance Win32_Processor
        if (-not $cpu.VirtualizationFirmwareEnabled) {
            Write-Log WARN 'Virtualization may be disabled in BIOS. WSL2 may fail to start.'
        }
    } catch {
        Write-Log WARN 'Could not query CPU virtualization state.'
    }
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'wsl.exe not found on PATH. Install the Windows Subsystem for Linux feature first.'
    }
    Save-Checkpoint 'Preflight'
}

function Step-EnsureWsl {
    # Three cases:
    #   1. WSL2 + Ubuntu already functional -> skip.
    #   2. WSL kernel loaded but Ubuntu missing -> install Ubuntu (with WSL1
    #      fallback on HCS_E_HYPERV_NOT_INSTALLED), no reboot.
    #   3. WSL not installed at all (clean Win11) -> enable Windows features
    #      via DISM (Microsoft-Windows-Subsystem-Linux, VirtualMachinePlatform,
    #      HypervisorPlatform), persist resume state, restart. The ACTUAL
    #      `wsl --install -d Ubuntu` runs in the resume branch below, after
    #      the kernel features are loaded.
    Write-Log INFO 'Step 2: Ensuring WSL2 + Ubuntu are available.'

    if ($Resume) {
        Write-Log INFO 'Resuming after restart - completing WSL install if needed.'
        if (Test-WslFunctional) {
            Write-Log INFO 'WSL2 + Ubuntu already functional after restart.'
            Save-Checkpoint 'EnsureWsl'
            return
        }
        # Pre-reboot we ran DISM but not `wsl --install`. Run it now. WSL1
        # fallback kicks in if HCS_E_HYPERV_NOT_INSTALLED is detected.
        $variant = Install-WslDistroWithFallback
        Write-Log INFO "WSL variant installed: $variant"
        New-ClawUserAndSetDefault

        $ready = $false
        for ($i = 1; $i -le 12; $i++) {
            if (Test-WslFunctional) { $ready = $true; break }
            Start-Sleep -Seconds 5
        }
        if (-not $ready) {
            throw 'WSL could not be configured on this machine. Please contact support at hello@avitalresearch.com'
        }
        Save-Checkpoint 'EnsureWsl'
        return
    }

    if (Test-WslFunctional) {
        Write-Log INFO 'WSL2 + Ubuntu already functional - skipping install.'
        Save-Checkpoint 'EnsureWsl'
        return
    }

    # Kernel-loaded check. If `wsl --status` returns 0 the feature is active
    # and we can install Ubuntu without rebooting. Otherwise enable features
    # via DISM and reboot - the resume branch above completes the install.
    $null = & wsl.exe --status 2>&1
    $kernelOk = ($LASTEXITCODE -eq 0)

    if ($kernelOk) {
        Write-Log INFO 'WSL2 kernel loaded but Ubuntu missing - installing Ubuntu only.'
        $variant = Install-WslDistroWithFallback
        Write-Log INFO "WSL variant installed: $variant"
        New-ClawUserAndSetDefault
        Start-Sleep -Seconds 5
        if (-not (Test-WslFunctional)) {
            throw 'WSL could not be configured on this machine. Please contact support at hello@avitalresearch.com'
        }
        Save-Checkpoint 'EnsureWsl'
        return
    }

    # Kernel not loaded - DISM the features then reboot. Resume branch
    # completes the install on next launch. Does not return.
    Enable-WindowsFeaturesForWsl
    Invoke-WslInstallWithRestart
}

function Step-ConfigureWslConf {
    # Phase 1: write wsl.conf WITHOUT [user] default=clawuser. The user does not
    # exist yet; setting it here causes getpwnam(clawuser) failures on every WSL
    # invocation (including -u root ones). Default user is added in Step-SetDefaultUser
    # AFTER clawuser is created.
    Write-Log INFO 'Step 3: Writing initial /etc/wsl.conf (automount off, systemd on).'
    $wslConf = @"
[automount]
enabled=false

[boot]
systemd=true

[network]
generateResolvConf=true
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($wslConf))
    wsl -d $WslDistro -u root -- bash -c "echo '$encoded' | base64 -d > /etc/wsl.conf && chmod 644 /etc/wsl.conf"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to write /etc/wsl.conf' }
    Save-Checkpoint 'WslConf'
}

function Step-RestartWsl {
    Write-Log INFO 'Step 4: Restarting WSL.'
    wsl --shutdown | Out-Null
    Start-Sleep -Seconds 3
    # -u root explicitly: avoids getpwnam errors if wsl.conf default user is stale/missing.
    wsl -d $WslDistro -u root -- true | Out-Null
    Save-Checkpoint 'WslRestart'
}

function Step-CreateClawUser {
    Write-Log INFO "Step 5: Locking down '$WslUser' (no sudo, no password login)."
    $script = @'
set -e
if ! id clawuser >/dev/null 2>&1; then
    useradd -m -s /bin/bash clawuser
fi
# Lock the account so nobody can password-login. Non-fatal if the password was
# never set (usermod -L returns 0 on a newly-created account).
usermod -L clawuser 2>/dev/null || true
chmod 700 /home/clawuser
# Strip the temporary NOPASSWD sudoers entry that Step-EnsureWsl added to
# bypass Ubuntu's first-launch interactive setup. The egress firewall and
# overall security model assume clawuser is fully non-privileged
# (DEVIATION A2: nft mutations run via -u root, not via clawuser sudo).
sed -i '/^clawuser[[:space:]]\+ALL=(ALL)[[:space:]]\+NOPASSWD:ALL$/d' /etc/sudoers || true
# Remove sudo group membership (fresh users aren't in sudo anyway, but
# Step-EnsureWsl added clawuser to sudo to bridge the OOBE gap).
gpasswd -d clawuser sudo 2>/dev/null || true
echo "clawuser locked down: uid=$(id -u clawuser), groups=$(id -nG clawuser | tr ' ' ',')"
'@
    $rc = Invoke-WslBash -Script $script -User 'root'
    if ($rc -ne 0) { throw "Failed to create clawuser (exit=$rc) - check install.log for [wsl:root] lines." }
    Save-Checkpoint 'CreateClawUser'
}

function Step-SetDefaultUser {
    # Phase 2: now that clawuser exists, append default-user directive and restart.
    Write-Log INFO "Step 5b: Setting '$WslUser' as default WSL user + restarting."
    $append = @'
set -e
# Remove any existing [user] block (idempotent on re-runs), then append the correct one.
sed -i '/^\[user\]/,/^$/d' /etc/wsl.conf
printf '\n[user]\ndefault=clawuser\n' >> /etc/wsl.conf
chmod 644 /etc/wsl.conf
'@
    $rc = Invoke-WslBash -Script $append -User 'root'
    if ($rc -ne 0) { throw "Failed to append default user to /etc/wsl.conf (exit=$rc)" }
    wsl --shutdown | Out-Null
    Start-Sleep -Seconds 3
    wsl -d $WslDistro -u $WslUser -- true | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # Fall back to root restart if clawuser-default somehow still fails.
        wsl -d $WslDistro -u root -- true | Out-Null
        Write-Log WARN 'Default-user restart fell back to root. Check /etc/wsl.conf.'
    }
    Save-Checkpoint 'DefaultUser'
}

function Step-InstallDocker {
    Write-Log INFO 'Step 6: Installing Docker Engine (rootless for clawuser).'
    $script = @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg uidmap dbus-user-session \
    iptables nftables fuse-overlayfs slirp4netns
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
fi
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
ARCH=$(dpkg --print-architecture)
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
loginctl enable-linger clawuser || true
su - clawuser -c 'dockerd-rootless-setuptool.sh install --force' || true
grep -q 'DOCKER_HOST=unix' /home/clawuser/.bashrc || \
    echo 'export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock' >> /home/clawuser/.bashrc
'@
    $rc = Invoke-WslBash -Script $script -User 'root'
    if ($rc -ne 0) { throw 'Docker install failed' }
    Save-Checkpoint 'Docker'
}

function Step-EgressFirewall {
    # [R3] nftables egress firewall scoped to clawuser's UID.
    # Allowlist includes only the SELECTED provider's host(s) plus infra essentials.
    Write-Log INFO "Step 7 [R3]: Installing WSL egress firewall (clawuser-scoped, provider=$Provider)."
    $baseHosts     = @(
        # Git / source hosts
        'api.github.com','github.com','raw.githubusercontent.com','codeload.github.com',
        # OpenClaw + ClawHub
        'openclaw.ai','docs.openclaw.ai','clawhub.ai','api.clawhub.ai',
        # npm + Node.js (for skills and updates)
        'registry.npmjs.org','nodejs.org','deb.nodesource.com',
        # Docker Hub
        'registry-1.docker.io','auth.docker.io','production.cloudflare.docker.com'
    )
    $providerHosts = @($ThisProvider.AllowlistHosts)
    $allHosts      = ($baseHosts + $providerHosts) | Where-Object { $_ } | Sort-Object -Unique
    $hostList      = ($allHosts -join ' ')
    Write-Log INFO "Allowlist hosts: $hostList"

    $script = @"
set -euo pipefail

# --- Write nftables config (used if nf_tables is available) ----------------
cat > /etc/nftables.conf <<'NFT'
#!/usr/sbin/nft -f
flush ruleset
table inet clawfactory {
    set allowed_ipv4 {
        type ipv4_addr
        flags dynamic, timeout
        timeout 6h
    }
    chain output {
        type filter hook output priority 0; policy accept;
        meta skuid != clawuser return
        oifname `"lo`" accept
        udp dport 53 accept
        tcp dport 53 accept
        ct state established,related accept
        ip daddr @allowed_ipv4 tcp dport 443 accept
        # Allow Ollama local API on port 11434 (localhost only is enforced by bind)
        ip daddr 127.0.0.1 tcp dport 11434 accept
        counter drop
    }
}
NFT
chmod 644 /etc/nftables.conf

# --- Resolve allowlist hosts to IPv4s --------------------------------------
HOSTS=`"$hostList`"
ALLOWED_IPS=`"`"
for h in `$HOSTS; do
    for ip in `$(getent ahostsv4 `"`$h`" 2>/dev/null | awk '{print `$1}' | sort -u); do
        ALLOWED_IPS=`"`$ALLOWED_IPS `$ip`"
    done
done

# --- Try nftables first; fall back to iptables-legacy on Netlink failure ---
# Default WSL2 kernels often ship without nf_tables loaded, in which case
# `nft -f` exits non-zero with `Unable to initialize Netlink socket`. We
# detect that specific signal and re-apply equivalent rules using
# iptables-legacy (xt_owner + xt_conntrack are usually available on the
# same kernels that lack nf_tables).
NFT_ERR=`$(mktemp)
trap 'rm -f `"`$NFT_ERR`"' EXIT
FW_BACKEND=`"`"

if nft -f /etc/nftables.conf 2>`"`$NFT_ERR`"; then
    FW_BACKEND=`"nftables`"
    for ip in `$ALLOWED_IPS; do
        nft add element inet clawfactory allowed_ipv4 `"{ `$ip }`" 2>/dev/null || true
    done
elif grep -qE 'Unable to initialize Netlink|netlink|nf_tables' `"`$NFT_ERR`"; then
    echo `"[clawfactory-fw] nftables not supported on this WSL kernel - falling back to iptables-legacy`"
    cat `"`$NFT_ERR`" >&2 || true
    IPT=`"`$(command -v iptables-legacy || true)`"
    if [ -z `"`$IPT`" ]; then
        echo `"[clawfactory-fw] iptables-legacy binary not found - cannot apply firewall`" >&2
        exit 1
    fi
    FW_BACKEND=`"iptables-legacy`"
    `"`$IPT`" -F OUTPUT
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -o lo -j ACCEPT
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -p udp --dport 53 -j ACCEPT
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -p tcp --dport 53 -j ACCEPT
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    for ip in `$ALLOWED_IPS; do
        `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -d `"`$ip`" -p tcp --dport 443 -j ACCEPT
    done
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -d 127.0.0.1 -p tcp --dport 11434 -j ACCEPT
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -j DROP
else
    echo `"[clawfactory-fw] nft -f failed for an unexpected reason:`" >&2
    cat `"`$NFT_ERR`" >&2
    exit 1
fi

echo `"[clawfactory-fw] active backend: `$FW_BACKEND`"

# --- Persist the active backend choice + IP list for the boot-time unit ----
mkdir -p /etc/clawfactory
echo `"`$FW_BACKEND`" > /etc/clawfactory/fw-backend
printf '%s\n' `$ALLOWED_IPS | sed '/^`$/d' > /etc/clawfactory/allowed-ips.txt

# --- Boot-time apply script: re-applies whichever backend is active --------
cat > /usr/local/sbin/clawfactory-fw-apply.sh <<'APPLY'
#!/bin/bash
set -euo pipefail
BACKEND=`"`$(cat /etc/clawfactory/fw-backend 2>/dev/null || echo nftables)`"
if [ `"`$BACKEND`" = `"iptables-legacy`" ]; then
    IPT=`"`$(command -v iptables-legacy || true)`"
    [ -n `"`$IPT`" ] || { echo `"[clawfactory-fw] iptables-legacy missing`" >&2; exit 1; }
    `"`$IPT`" -F OUTPUT
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -o lo -j ACCEPT
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -p udp --dport 53 -j ACCEPT
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -p tcp --dport 53 -j ACCEPT
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    while IFS= read -r ip; do
        [ -n `"`$ip`" ] || continue
        `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -d `"`$ip`" -p tcp --dport 443 -j ACCEPT
    done < /etc/clawfactory/allowed-ips.txt
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -d 127.0.0.1 -p tcp --dport 11434 -j ACCEPT
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -j DROP
else
    /usr/sbin/nft -f /etc/nftables.conf
    while IFS= read -r ip; do
        [ -n `"`$ip`" ] || continue
        /usr/sbin/nft add element inet clawfactory allowed_ipv4 `"{ `$ip }`" 2>/dev/null || true
    done < /etc/clawfactory/allowed-ips.txt
fi
APPLY
chmod +x /usr/local/sbin/clawfactory-fw-apply.sh

cat > /etc/systemd/system/clawfactory-fw.service <<'UNIT'
[Unit]
Description=ClawFactory egress firewall (nftables or iptables-legacy fallback)
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/clawfactory-fw-apply.sh

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload 2>/dev/null || true
systemctl enable clawfactory-fw.service 2>/dev/null || true
"@
    $rc = Invoke-WslBash -Script $script -User 'root'
    if ($rc -ne 0) {
        Write-Log WARN 'Egress firewall setup returned non-zero. Check install.log; firewall may not be active.'
    } else {
        # Surface which backend the script picked so the install log is
        # explicit (the bash output is also captured in install.log).
        $backendCheck = @'
cat /etc/clawfactory/fw-backend 2>/dev/null || echo unknown
'@
        $null = Invoke-WslBash -Script $backendCheck -User 'root'
    }
    Save-Checkpoint 'EgressFirewall'
}

function Step-InstallOllama {
    # Only runs if Provider = ollama. Installs Ollama daemon inside WSL, pulls default model.
    if ($Provider -ne 'ollama') { return }
    Write-Log INFO 'Step 7b: Installing Ollama (local LLM runtime) inside WSL.'
    $script = @'
set -euo pipefail
if ! command -v ollama >/dev/null 2>&1; then
    curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh
    # Basic integrity check: must be a shell script, not HTML
    head -c 2 /tmp/ollama-install.sh | grep -q '#!' || { echo "ollama install.sh is not a shell script"; exit 1; }
    bash /tmp/ollama-install.sh
    rm -f /tmp/ollama-install.sh
fi
systemctl enable ollama 2>/dev/null || true
systemctl restart ollama 2>/dev/null || true
sleep 3
su - clawuser -c 'ollama pull llama3.1:8b' || echo "ollama pull failed - you can retry later with: wsl -u clawuser -- ollama pull llama3.1:8b"
'@
    $rc = Invoke-WslBash -Script $script -User 'root'
    if ($rc -ne 0) { Write-Log WARN 'Ollama install returned non-zero; you may need to run `wsl -u clawuser -- ollama pull llama3.1:8b` manually.' }
    Save-Checkpoint 'Ollama'
}

function Step-InstallOpenClaw {
    # [R2] Pinned fetch: refuses to run install.sh unless its SHA-256 matches.
    Write-Log INFO 'Step 8 [R2]: Installing OpenClaw with SHA-256 pinning.'
    if (-not $AcknowledgedOpenClawUrl) {
        throw 'OpenClaw install URL not acknowledged. Re-run via the wizard.'
    }
    $fetch = @"
set -euo pipefail
TMP=`$(mktemp)
trap 'rm -f `"`$TMP`"' EXIT
curl -fsSL '$OpenClawInstallUrl' -o `"`$TMP`"
ACTUAL=`$(sha256sum `"`$TMP`" | awk '{print `$1}')
EXPECTED='$OpenClawInstallSha256'
echo `"OpenClaw install.sh SHA-256: `$ACTUAL`"
if [ `"`$EXPECTED`" = 'REPLACE_ME_WITH_REAL_SHA256_OF_install.sh' ]; then
    echo '!! SHA-256 pin not set in setup.ps1. Refusing to execute. See README.md.'
    exit 42
fi
if [ `"`$ACTUAL`" != `"`$EXPECTED`" ]; then
    echo `"!! SHA-256 mismatch. expected=`$EXPECTED got=`$ACTUAL`"
    exit 43
fi
# install.sh runs `sudo` internally but falls back to direct exec when already root.
# Set HOME/USER/LOGNAME so per-user artifacts (shim at \$HOME/.local/bin, config
# under \$HOME/.openclaw) land in clawuser's home, not /root.
#
# Wrap bash with `timeout` to fail fast if openclaw-onboard (invoked from
# inside install.sh) hangs waiting on interactive input. 5 minutes is enough
# for any non-interactive run; longer than that means we're stuck. SIGTERM
# first (graceful), then SIGKILL after 30s (--kill-after) if the child
# trapped SIGTERM. timeout's exit code 124 = timed out.
set +e
NO_ONBOARD=1 OPENCLAW_VERSION=$OpenClawNpmVersion HOME=/home/clawuser USER=clawuser LOGNAME=clawuser timeout --foreground --kill-after=30 900 bash `"`$TMP`" -- --no-onboard > >(tee /tmp/openclaw-install.log) 2>&1
INSTALL_RC=`$?
set -e
if [ `$INSTALL_RC -eq 124 ]; then
    echo `"!! OpenClaw install.sh did not complete within 5 minutes (timeout). The install hung - typically because openclaw-onboard prompted for interactive input on a closed stdin.`" >&2
    exit 44
fi
if [ `$INSTALL_RC -ne 0 ]; then
    exit `$INSTALL_RC
fi
# Ensure the installed shim is owned by clawuser (install.sh runs as root).
chown -R clawuser:clawuser /home/clawuser/.local 2>/dev/null || true
chown -R clawuser:clawuser /home/clawuser/.openclaw 2>/dev/null || true
chown -R clawuser:clawuser /home/clawuser/.npm 2>/dev/null || true
"@
    $rc = Invoke-WslBash -Script $fetch -User 'root'
    if ($rc -eq 42) { throw 'OpenClaw install blocked: SHA-256 pin not set. See README "Pinning the OpenClaw install.sh hash".' }
    if ($rc -eq 43) { throw 'OpenClaw install blocked: SHA-256 mismatch. The install.sh on the server does not match the pinned hash.' }
    if ($rc -eq 44) { throw 'OpenClaw install timed out after 5 minutes. install.sh hung (typically an interactive openclaw-onboard prompt waiting on closed stdin). See install.log for details and re-run setup.ps1 -Resume to retry.' }
    if ($rc -ne 0)  { throw "OpenClaw install failed with exit $rc" }
    Save-Checkpoint 'OpenClaw'
}

function Step-PreinstallGatewayRuntime {
    # The OpenClaw gateway lazy-installs npm deps on first boot for both:
    #   1. its core runtime (@modelcontextprotocol/sdk, express, ws, ...) at
    #      ~/.openclaw/plugin-runtime-deps/openclaw-<version>-<hash>/
    #   2. each bundled plugin's runtime deps at
    #      /usr/lib/node_modules/openclaw/dist/extensions/<name>/.openclaw-install-stage/
    # Both run as clawuser, but Step-EgressFirewall drops clawuser's outbound
    # to anywhere except DNS, loopback, and the (empty) dynamic allowlist. The
    # installs hang or fail, the gateway either never binds or comes up with
    # zero LLM providers.
    #
    # Fix (this step):
    #   a. Install both as root while the firewall exempts us (skuid != 1001).
    #   b. Add a systemd-unit override that disables the per-start timeout
    #      (the bundled plugin loader can take 2-7 minutes on first boot
    #      because of timeouts on the still-blocked plugin installs we
    #      didn't pre-cover).
    #   c. Copy the global auth-profiles.json into each agent's per-agent
    #      directory so the gateway finds API keys when the agent runs.
    #   d. chown everything back to clawuser at the end.
    #
    # If a future openclaw release adds new bundled plugins or changes deps,
    # the lazy-install fallback will silently fail; setup.ps1 will need to
    # be updated. The install.sh SHA-256 pin prevents silent upgrades.
    Write-Log INFO 'Step 8b: Pre-installing OpenClaw gateway + bundled plugin deps as root.'

    # M8: Compute the default `main` agent model based on the selected
    # provider so the agent.md sub-block g writes a model line that matches
    # what `Step-WireProviderKey` actually authenticated. Hardcoding
    # anthropic/claude-sonnet-4-6 broke every non-claude install. The
    # provider->prefix mapping mirrors Step-ConfigureOpenClaw: 'claude' maps
    # to 'anthropic'; everyone else uses their own name.
    $mainAgentPrefix = switch ($Provider) {
        'claude' { 'anthropic' }
        default  { $Provider }
    }
    $mainAgentModel = if ($Provider -eq 'later' -or -not $ThisProvider.DefaultModel) {
        ''
    } else {
        "$mainAgentPrefix/$($ThisProvider.DefaultModel)"
    }
    Write-Log INFO "Default main agent model: $(if ($mainAgentModel) { $mainAgentModel } else { '(none - skipping main agent.md)' })"

    $script = @'
set -e

# --- a1. Core runtime deps -----------------------------------------------
ROOT=/home/clawuser/.openclaw/plugin-runtime-deps
if [ -d "$ROOT" ]; then
    DIR=$(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -name 'openclaw-*' | head -1)
    if [ -n "$DIR" ]; then
        cd "$DIR"
        if [ -d node_modules ] && [ -f package.json ]; then
            echo "[gateway-preinstall] core node_modules already populated; skip"
        else
            echo "[gateway-preinstall] installing core runtime deps in $DIR"
            npm install --no-audit --no-fund --no-progress \
                '@modelcontextprotocol/sdk@1.29.0' \
                'commander@^14.0.3' \
                'express@^5.2.1' \
                'playwright-core@1.59.1' \
                'typebox@1.1.28' \
                'undici@8.1.0' \
                'ws@^8.20.0'
        fi
    fi
fi

# --- a2. Bundled plugin deps ---------------------------------------------
# Known plugins that lazy-install at gateway boot. Each entry is "<plugin>:<deps>"
# where deps is space-separated. Add more as they're discovered.
EXT_ROOT=/usr/lib/node_modules/openclaw/dist/extensions
declare -A PLUGIN_DEPS=(
    [acpx]='acpx@0.5.3 typebox@1.1.28'
    [anthropic]='@mariozechner/pi-ai@0.70.0 typebox@1.1.28'
    [openai]='@mariozechner/pi-ai@0.70.0 typebox@1.1.28'
    [google]='@mariozechner/pi-ai@0.70.0 typebox@1.1.28'
    [groq]='@mariozechner/pi-ai@0.70.0 typebox@1.1.28'
    [xai]='@mariozechner/pi-ai@0.70.0 typebox@1.1.28'
)
for name in "${!PLUGIN_DEPS[@]}"; do
    if [ ! -d "$EXT_ROOT/$name" ]; then continue; fi
    STAGE="$EXT_ROOT/$name/.openclaw-install-stage"
    mkdir -p "$STAGE"
    if [ -d "$STAGE/node_modules" ] && [ -f "$STAGE/package.json" ] && [ -d "$STAGE/node_modules/.bin" ]; then
        echo "[gateway-preinstall] plugin $name already staged; skip"
        continue
    fi
    cd "$STAGE"
    echo "[gateway-preinstall] installing plugin deps for $name: ${PLUGIN_DEPS[$name]}"
    # shellcheck disable=SC2086
    npm install --no-audit --no-fund --no-progress ${PLUGIN_DEPS[$name]} 2>&1 | tail -2 || echo "  (warn) $name install reported $?"
done

# --- b. Systemd unit override: disable per-start timeout -----------------
# The plugin loader can spend many seconds waiting on each non-pre-installed
# plugin's npm install before timing out. Default TimeoutStartSec=30s in the
# unit means systemd SIGTERMs the gateway mid-init. Bumping to infinity lets
# the loader finish and the HTTP server bind. Once all bundled plugins are
# pre-installed, this should drop to a low number (e.g. 60).
OVERRIDE_DIR=/home/clawuser/.config/systemd/user/openclaw-gateway.service.d
mkdir -p "$OVERRIDE_DIR"
cat > "$OVERRIDE_DIR/clawfactory-tunables.conf" <<'EOF'
[Service]
TimeoutStartSec=infinity
EOF

# --- c. Per-agent auth-profiles ------------------------------------------
# The gateway looks for API keys at ~/.openclaw/agents/<agent>/agent/auth-profiles.json,
# NOT the global ~/.openclaw/auth-profiles.json. Copy global → per-agent for
# every agent dir we set up.
if [ -f /home/clawuser/.openclaw/auth-profiles.json ]; then
    for agent_dir in /home/clawuser/.openclaw/agents/*/; do
        [ -d "$agent_dir" ] || continue
        target="$agent_dir/agent"
        mkdir -p "$target"
        cp -f /home/clawuser/.openclaw/auth-profiles.json "$target/auth-profiles.json"
        chmod 600 "$target/auth-profiles.json"
    done
fi

# --- d. Enable linger so user-systemd survives between sessions ----------
# Without linger, WSL2's user-systemd manager exits to exit.target whenever
# clawuser has no active session, killing openclaw-gateway. Studio's
# wsl-keepalive helper holds a session at runtime, but linger covers the
# install / reboot / restart gap.
loginctl enable-linger clawuser || true

# --- e. Resolve LLM-provider hostnames into the egress firewall allowlist
# (this depends on Step-EgressFirewall having run already so the table or
# the iptables-legacy chain exists). Both backends get the same auxiliary
# host list (auth endpoints, registry mirrors, etc.) so OpenClaw's first-run
# auth flows succeed regardless of which firewall is active.
AUX_HOSTS="api.anthropic.com console.anthropic.com api.openai.com auth.openai.com api.x.ai \
generativelanguage.googleapis.com aiplatform.googleapis.com \
clawhub.ai api.github.com raw.githubusercontent.com objects.githubusercontent.com \
registry.npmjs.org"
if nft list table inet clawfactory >/dev/null 2>&1; then
    for h in $AUX_HOSTS; do
        for ip in $(getent ahostsv4 "$h" | awk '{print $1}' | sort -u); do
            nft add element inet clawfactory allowed_ipv4 "{ $ip }" 2>/dev/null || true
        done
    done
elif [ "$(cat /etc/clawfactory/fw-backend 2>/dev/null)" = "iptables-legacy" ]; then
    # iptables-legacy backend: the OUTPUT chain has explicit ACCEPT rules
    # per IP and a final DROP for clawuser. Insert new ACCEPTs at position 1
    # so they take precedence over the DROP, with -C as an idempotency guard
    # against duplicate rules on re-runs. Persist each new IP into
    # /etc/clawfactory/allowed-ips.txt so clawfactory-fw-apply.sh re-applies
    # them at boot.
    IPT="$(command -v iptables-legacy || true)"
    if [ -n "$IPT" ]; then
        touch /etc/clawfactory/allowed-ips.txt
        for h in $AUX_HOSTS; do
            for ip in $(getent ahostsv4 "$h" | awk '{print $1}' | sort -u); do
                if ! "$IPT" -C OUTPUT -m owner --uid-owner clawuser -d "$ip" -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
                    "$IPT" -I OUTPUT 1 -m owner --uid-owner clawuser -d "$ip" -p tcp --dport 443 -j ACCEPT
                fi
                grep -qx "$ip" /etc/clawfactory/allowed-ips.txt || echo "$ip" >> /etc/clawfactory/allowed-ips.txt
            done
            echo "[clawfactory-fw] iptables-legacy: allowlisted $h"
        done
    else
        echo "[clawfactory-fw] iptables-legacy backend declared but binary missing - auxiliary IPs NOT applied" >&2
    fi
fi

# --- f. Systemd timer to refresh the firewall allowlist every 5 hours ----
# The dynamic set has 6 h timeout; refresh before then.
cat > /etc/systemd/system/clawfactory-allow-providers.service <<'SVC'
[Unit]
Description=ClawFactory: refresh LLM provider IPs in nft allowlist
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/clawfactory-allow-providers.sh
SVC

cat > /etc/systemd/system/clawfactory-allow-providers.timer <<'TMR'
[Unit]
Description=ClawFactory: refresh LLM provider IPs every 5h

[Timer]
OnBootSec=30s
OnUnitActiveSec=5h
Unit=clawfactory-allow-providers.service

[Install]
WantedBy=timers.target
TMR

cat > /usr/local/sbin/clawfactory-allow-providers.sh <<'REFRESH'
#!/usr/bin/env bash
# Re-resolve auxiliary LLM-provider host IPs and re-add them to the active
# firewall. Routes to nftables or iptables-legacy based on the backend
# persisted by Step-EgressFirewall. Runs every 5h via the systemd timer.
set -e
AUX_HOSTS="api.anthropic.com console.anthropic.com api.openai.com auth.openai.com api.x.ai \
generativelanguage.googleapis.com aiplatform.googleapis.com \
clawhub.ai api.github.com raw.githubusercontent.com objects.githubusercontent.com \
registry.npmjs.org"
BACKEND="$(cat /etc/clawfactory/fw-backend 2>/dev/null || echo nftables)"
if [ "$BACKEND" = "nftables" ]; then
    nft list table inet clawfactory >/dev/null 2>&1 || exit 0
    for h in $AUX_HOSTS; do
        for ip in $(getent ahostsv4 "$h" | awk '{print $1}' | sort -u); do
            nft add element inet clawfactory allowed_ipv4 "{ $ip }" 2>/dev/null || true
        done
    done
elif [ "$BACKEND" = "iptables-legacy" ]; then
    IPT="$(command -v iptables-legacy || true)"
    [ -n "$IPT" ] || exit 0
    touch /etc/clawfactory/allowed-ips.txt
    for h in $AUX_HOSTS; do
        for ip in $(getent ahostsv4 "$h" | awk '{print $1}' | sort -u); do
            if ! "$IPT" -C OUTPUT -m owner --uid-owner clawuser -d "$ip" -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
                "$IPT" -I OUTPUT 1 -m owner --uid-owner clawuser -d "$ip" -p tcp --dport 443 -j ACCEPT
            fi
            grep -qx "$ip" /etc/clawfactory/allowed-ips.txt || echo "$ip" >> /etc/clawfactory/allowed-ips.txt
        done
    done
fi
REFRESH
chmod +x /usr/local/sbin/clawfactory-allow-providers.sh
systemctl daemon-reload
systemctl enable --now clawfactory-allow-providers.timer 2>/dev/null || true

# --- g. Default agent.md for the `main` agent ---------------------------
# Without this, the agent receives messages but has no system prompt and
# silently no-ops. setup.ps1's Step-CreateAgentDirectories only mkdir's the
# agent dir; this gives `main` a sane default. Other agents (the factory
# team) get their prompts from bootstrap-factory.sh later.
if [ -d /home/clawuser/.openclaw/agents/main ] && [ ! -f /home/clawuser/.openclaw/agents/main/agent.md ]; then
    if [ -n "${DEFAULT_MAIN_MODEL:-}" ]; then
        # Unquoted heredoc marker so $DEFAULT_MAIN_MODEL expands. Quoting
        # the YAML value defends against models whose names contain ':'
        # (e.g. ollama/llama3.1:8b).
        cat > /home/clawuser/.openclaw/agents/main/agent.md <<AGENT
---
name: main
model: "$DEFAULT_MAIN_MODEL"
---

You are the default chat assistant for the ClawFactory operator. Reply directly and concisely to whatever the operator asks. Keep answers under three sentences unless explicitly asked for detail.
AGENT
    else
        echo "[gateway-preinstall] no provider model configured (Provider=later); skipping main agent.md - run switch-provider.ps1 later"
    fi
fi

# --- h. Chown everything back to clawuser --------------------------------
chown -R clawuser:clawuser /home/clawuser/.openclaw
chown -R clawuser:clawuser /home/clawuser/.config/systemd/user/openclaw-gateway.service.d
chown -R clawuser:clawuser /usr/lib/node_modules/openclaw/dist/extensions/

echo "[gateway-preinstall] complete"
'@
    # M8: Prepend the resolved default model so sub-block g's heredoc can
    # interpolate it. Single-quoted on the bash side so shell metachars in
    # the model name are literal; PowerShell's escaping for the embedded
    # single-quote (rare in model names but possible) is belt-and-suspenders.
    $modelEscaped = $mainAgentModel -replace "'", "'\''"
    $script = "DEFAULT_MAIN_MODEL='$modelEscaped'`n" + $script

    $rc = Invoke-WslBash -Script $script -User 'root'
    if ($rc -ne 0) { Write-Log WARN "Gateway runtime pre-install returned $rc; the gateway may need manual help on first boot." }

    # Start the gateway as clawuser. Three layered paths:
    #   1. If systemd --user is functional, use the openclaw-gateway.service
    #      unit (existing path; respects the install.sh-supplied systemd unit
    #      and our TimeoutStartSec=infinity override from sub-block b).
    #   2. If systemd is unavailable (WSL1 fallback, or systemd-disabled WSL),
    #      try `openclaw gateway start` - the CLI may have its own
    #      non-systemd daemonization.
    #   3. If even that fails, daemonize directly via `nohup setsid openclaw
    #      gateway run` writing to ~/.openclaw/logs/gateway.log.
    # Verify by polling http://127.0.0.1:8787/status. The script logs which
    # path won so install.log is unambiguous.
    $startGateway = @'
set -e
LOG=/home/clawuser/.openclaw/logs/gateway.log
mkdir -p /home/clawuser/.openclaw/logs

# Skip the start dance if the gateway is already responding (re-run case).
if curl -fsS --max-time 3 http://127.0.0.1:8787/status >/dev/null 2>&1; then
    echo "[gateway-start] gateway already running on 127.0.0.1:8787"
    exit 0
fi

# Detect a usable systemd --user manager. `is-system-running` returns
# non-zero if systemd is missing or DBus isn't reachable; we also accept
# `list-units` succeeding as a softer probe.
SYSTEMD_OK=false
if systemctl --user is-system-running >/dev/null 2>&1 || \
   systemctl --user list-units --no-legend --no-pager >/dev/null 2>&1; then
    SYSTEMD_OK=true
fi

if [ "$SYSTEMD_OK" = "true" ]; then
    echo "[gateway-start] systemd --user available - starting via systemd"
    systemctl --user daemon-reload || true
    systemctl --user reset-failed openclaw-gateway.service 2>/dev/null || true
    systemctl --user enable --now openclaw-gateway.service 2>/dev/null || \
        systemctl --user start openclaw-gateway.service || true
    GATEWAY_BACKEND=systemd
else
    echo "[gateway-start] systemd --user unavailable - falling back to direct start"
    if openclaw gateway start </dev/null >>"$LOG" 2>&1; then
        echo "[gateway-start] openclaw gateway start succeeded"
        GATEWAY_BACKEND=openclaw-cli
    else
        echo "[gateway-start] openclaw gateway start failed - launching gateway in background via nohup setsid"
        nohup setsid openclaw gateway run </dev/null >>"$LOG" 2>&1 &
        disown 2>/dev/null || true
        GATEWAY_BACKEND=nohup
    fi
fi

# Poll the status endpoint. Up to ~30s for the gateway to bind + accept.
for i in $(seq 1 15); do
    if curl -fsS --max-time 3 http://127.0.0.1:8787/status >/dev/null 2>&1; then
        echo "[gateway-start] gateway responding on 127.0.0.1:8787 via $GATEWAY_BACKEND (attempt $i)"
        exit 0
    fi
    sleep 2
done
echo "[gateway-start] WARNING: gateway not responding on 127.0.0.1:8787 after ~30s (backend=$GATEWAY_BACKEND)" >&2
echo "[gateway-start] last 40 lines of $LOG:" >&2
tail -n 40 "$LOG" >&2 2>/dev/null || true
exit 1
'@
    $rc = Invoke-WslBash -Script $startGateway -User $WslUser
    if ($rc -ne 0) {
        Write-Log WARN "Gateway did not come up cleanly (exit=$rc). Check ~/.openclaw/logs/gateway.log. The install will continue; start it manually with: wsl -u clawuser -- openclaw gateway start"
    }
    Save-Checkpoint 'GatewayRuntime'
}

function Step-ConfigureOpenClaw {
    # Replaces the old Step-WriteOpenClawJson which used a fabricated CLI.
    # The real OpenClaw uses `openclaw config set <dot.path> <value>` to build
    # ~/.openclaw/openclaw.json piece by piece. Most subcommands (setup, onboard,
    # agents add, models auth login, paste-token) require an interactive TTY and
    # hang in non-interactive contexts even with --non-interactive flags.
    Write-Log INFO 'Step 9: Configuring OpenClaw via `openclaw config set` (real CLI).'

    # Map provider id to the auth-profile shape OpenClaw expects.
    $providerAuth = switch ($Provider) {
        'grok'   { @{ id = 'grok:default';      provider = 'grok';      modelPrefix = 'grok' } }
        'openai' { @{ id = 'openai:default';    provider = 'openai';    modelPrefix = 'openai' } }
        'claude' { @{ id = 'anthropic:default'; provider = 'anthropic'; modelPrefix = 'anthropic' } }
        'gemini' { @{ id = 'gemini:default';    provider = 'gemini';    modelPrefix = 'gemini' } }
        'ollama' { @{ id = 'ollama:default';    provider = 'ollama';    modelPrefix = 'ollama' } }
        default  { @{ id = $null; provider = $null; modelPrefix = $null } }
    }

    # Step 9a: gateway settings (loopback + port + mode).
    # gateway.mode=local is required - without it `openclaw gateway run` refuses
    # to start with "existing config is missing gateway.mode".
    $script9a = @'
set -e
openclaw config set gateway.bind loopback >/dev/null
openclaw config set gateway.port 8787 >/dev/null
openclaw config set gateway.mode local >/dev/null
echo "gateway configured"
'@
    $rc = Invoke-WslBash -Script $script9a -User $WslUser
    if ($rc -ne 0) { throw "Failed to configure gateway (exit=$rc)" }

    # Step 9b: default model (only if provider != later).
    if ($Provider -ne 'later' -and $ThisProvider.DefaultModel) {
        $modelId = "$($providerAuth.modelPrefix)/$($ThisProvider.DefaultModel)"
        $rc = Invoke-WslBash -Script "set -e; openclaw models set '$modelId' >/dev/null && echo 'default model set: $modelId'" -User $WslUser
        if ($rc -ne 0) { Write-Log WARN "Failed to set default model $modelId (exit=$rc)" }
    }

    # Step 9c: register the auth profile in openclaw.json (metadata only - the
    # secret goes into auth-profiles.json in Step-WireProviderKey).
    if ($providerAuth.id) {
        $profileJson = ConvertTo-Json -Compress -InputObject @{
            provider    = $providerAuth.provider
            mode        = if ($Provider -eq 'ollama') { 'token' } else { 'api_key' }
            displayName = $ThisProvider.DisplayName
        }
        $orderJson = ConvertTo-Json -Compress -InputObject @($providerAuth.id)

        $script9c = @"
set -e
openclaw config set auth.profiles.'$($providerAuth.id)' --strict-json '$profileJson' >/dev/null
openclaw config set auth.order.'$($providerAuth.provider)' --strict-json '$orderJson' >/dev/null
echo 'auth profile registered'
"@
        $rc = Invoke-WslBash -Script $script9c -User $WslUser
        if ($rc -ne 0) { Write-Log WARN "Failed to register auth profile (exit=$rc)" }
    }

    # Persist provider choice so switch-provider.ps1 and post-install.ps1 can read it.
    @{ provider = $Provider; selectedAt = (Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $ProviderStateFile -Encoding UTF8
    Save-Checkpoint 'OpenClawConfigured'
}

function Step-CreateAgentDirectories {
    # OpenClaw's `openclaw agents add` is interactive (TUI) even with
    # --non-interactive flag and hangs reliably in scripted contexts.
    # Workaround: pre-create the agent workspace directories so they show
    # up in the dashboard. The user adds the actual agent metadata via
    # the dashboard or `openclaw dashboard` later.
    Write-Log INFO 'Step 10: Pre-creating 4 agent workspace dirs (orchestrator + scout + builder + publisher; ratified 2026-04-26).'
    $agents = 'orchestrator','skill-scout','skill-builder','publisher'
    $mkdirCmds = $agents | ForEach-Object { "mkdir -p /home/clawuser/.openclaw/agents/$_" }
    $script = (@('set -e') + $mkdirCmds + @('echo "agent dirs ready"')) -join "`n"
    $rc = Invoke-WslBash -Script $script -User $WslUser
    if ($rc -ne 0) { Write-Log WARN "Failed to create agent dirs (exit=$rc)" }
    Save-Checkpoint 'AgentDirs'
}

function Step-ApplySafetyRules {
    # [R6] Apply SOUL.md to OpenClaw's main config dir with hash pinning.
    Write-Log INFO 'Step 11 [R6]: Applying SOUL.md + hash pinning to ~/.openclaw/.'
    $resourceDir = Join-Path $PSScriptRoot 'resources'
    $soulSrc     = Join-Path $resourceDir 'safety-rules.md'
    if (-not (Test-Path $soulSrc)) { throw "Missing resources/safety-rules.md at $soulSrc" }

    $soulHash = (Get-FileHash -LiteralPath $soulSrc -Algorithm SHA256).Hash.ToLower()
    Write-Log INFO "SOUL.md SHA-256 = $soulHash"

    $soulB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($soulSrc))
    $apply = @"
set -e
mkdir -p ~/.openclaw
echo '$soulB64' | base64 -d > ~/.openclaw/SOUL.md
printf '%s' '$soulHash' > ~/.openclaw/SOUL.md.sha256
chmod 444 ~/.openclaw/SOUL.md ~/.openclaw/SOUL.md.sha256
HAVE=`$(sha256sum ~/.openclaw/SOUL.md | awk '{print `$1}')
EXPECT=`$(cat ~/.openclaw/SOUL.md.sha256)
if [ `"`$HAVE`" = `"`$EXPECT`" ]; then echo 'OK: SOUL.md hash verified'; else echo 'MISMATCH'; exit 1; fi
"@
    $rc = Invoke-WslBash -Script $apply -User $WslUser
    if ($rc -ne 0) { throw 'Failed to apply SOUL.md.' }
    Save-Checkpoint 'SafetyRules'
}

function Step-WindowsFirewallDeny {
    # [R4] Belt-and-suspenders inbound-deny on gateway port.
    Write-Log INFO "Step 13 [R4]: Creating Windows Firewall inbound-deny rule on TCP/$GatewayPort."
    $existing = Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue
    if ($existing) { Remove-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue }
    New-NetFirewallRule `
        -DisplayName $FirewallRuleName `
        -Direction   Inbound `
        -Action      Block `
        -Protocol    TCP `
        -LocalPort   $GatewayPort `
        -Profile     Any `
        -Description 'ClawFactory gateway must never be reachable from the network.' | Out-Null
    Save-Checkpoint 'FirewallRule'
}

function Step-WireProviderKey {
    # Read the API key from Windows Credential Manager and write it directly to
    # ~/.openclaw/auth-profiles.json. The native CLI (`openclaw models auth
    # paste-token`, `models auth login --method api-key`) all require an
    # interactive TTY and hang in scripted contexts, even with --non-interactive.
    # Direct file write is the only reliable non-interactive path.
    if ($Provider -eq 'ollama' -or $Provider -eq 'later') {
        Write-Log INFO "Step 12: Skipping API key wiring (provider=$Provider)."
        Save-Checkpoint 'ProviderKey'
        return
    }
    Write-Log INFO "Step 12: Wiring $Provider API key from Credential Manager into ~/.openclaw/auth-profiles.json."
    $credTarget = $ThisProvider.CredentialTarget

    # Use a small inline C# wrapper to read from Windows Credential Manager.
    if (-not ([System.Management.Automation.PSTypeName]'CredW').Type) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class CredW {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct CRED {
        public UInt32 Flags; public UInt32 Type; public IntPtr T; public IntPtr C;
        public System.Runtime.InteropServices.ComTypes.FILETIME L;
        public UInt32 BS; public IntPtr B; public UInt32 P;
        public UInt32 AC; public IntPtr A; public IntPtr TA; public IntPtr U;
    }
    [DllImport("Advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool CredRead(string t, uint y, uint f, out IntPtr p);
    [DllImport("Advapi32.dll", EntryPoint="CredFree")] public static extern void CredFree(IntPtr p);
    public static string Read(string t) {
        IntPtr p; if (!CredRead(t, 1u, 0u, out p)) return null;
        try { CRED c = (CRED)Marshal.PtrToStructure(p, typeof(CRED));
            byte[] b = new byte[c.BS]; Marshal.Copy(c.B, b, 0, b.Length);
            return Encoding.Unicode.GetString(b); } finally { CredFree(p); }
    }
}
'@ -Language CSharp
    }
    $key = [CredW]::Read($credTarget)
    if ([string]::IsNullOrEmpty($key)) {
        Write-Log WARN "No API key in Credential Manager at '$credTarget'. Use switch-provider.ps1 later."
        Save-Checkpoint 'ProviderKey'
        return
    }
    Write-Log INFO "API key found (length=$($key.Length))."

    # Map provider id to OpenClaw's expected provider name.
    $ocProvider = switch ($Provider) {
        'grok'   { 'grok' }
        'openai' { 'openai' }
        'claude' { 'anthropic' }
        'gemini' { 'gemini' }
        default  { 'unknown' }
    }
    $profileId = "${ocProvider}:default"

    # Build auth-profiles.json content.
    $authObj = [ordered]@{
        version = 1
        profiles = [ordered]@{
            "$profileId" = [ordered]@{
                type     = 'api_key'
                provider = $ocProvider
                key      = $key
            }
        }
    }
    $authJson = ($authObj | ConvertTo-Json -Compress -Depth 10)
    $authB64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($authJson))

    $write = @"
set -e
echo '$authB64' | base64 -d > ~/.openclaw/auth-profiles.json
chmod 600 ~/.openclaw/auth-profiles.json
echo "auth-profiles.json written (mode 600)"
"@
    $rc = Invoke-WslBash -Script $write -User $WslUser
    # zero out the key in PowerShell memory
    $key = ('x' * 256)
    Remove-Variable key -ErrorAction SilentlyContinue
    if ($rc -ne 0) { throw "Failed to write auth-profiles.json (exit=$rc)" }
    Save-Checkpoint 'ProviderKey'
}

function Step-PostInstall {
    Write-Log INFO "Step 14: Running post-install.ps1 (provider=$Provider)."
    $postInstall = Join-Path $PSScriptRoot 'resources\post-install.ps1'
    if (-not (Test-Path $postInstall)) { throw 'Missing resources/post-install.ps1' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $postInstall -Provider $Provider
    if ($LASTEXITCODE -ne 0) { Write-Log WARN "post-install.ps1 exited $LASTEXITCODE - some non-critical steps may have failed." }
    Save-Checkpoint 'PostInstall'
}

function Step-ConfigureAgents {
    # Step 15 of 15: stage role-specific agent.md prompts into each agent dir
    # via resources/bootstrap.ps1. The bootstrap script reads the SOUL.md hash
    # already pinned by Step-ApplySafetyRules and substitutes {{SOUL_SHA256}}
    # into the orchestrator prompt; missing prompt files become explicit
    # placeholders, never silent skips.
    #
    # Why we run on Windows (not pwsh inside WSL): stock Ubuntu has no pwsh,
    # and the egress firewall (Step 7) does not whitelist packages.microsoft.com
    # so apt-installing pwsh would fail without firewall changes (out of scope).
    # Running on Windows is functionally equivalent — the agent.md files still
    # land in clawuser's home inside WSL, owned by clawuser, mode 644.
    Write-Log INFO 'Step 15 of 15: Configuring agents (running bootstrap.ps1).'
    $bootstrap = Join-Path $PSScriptRoot 'resources\bootstrap.ps1'
    if (-not (Test-Path -LiteralPath $bootstrap)) {
        throw "Missing resources/bootstrap.ps1 at $bootstrap"
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrap `
        -WslDistro $WslDistro -WslUser $WslUser -LogFile $LogFile
    if ($LASTEXITCODE -ne 0) {
        throw "bootstrap.ps1 exited $LASTEXITCODE - agents not configured."
    }
    Save-Checkpoint 'AgentBootstrap'
}

#--- Main ---------------------------------------------------------------------
if ($Resume) {
    # Recover provider from the resume flag (the cmdline value may be the
    # default 'grok' if Inno didn't pass -Provider on the silent relaunch).
    $flag = Read-ResumeFlag
    if ($flag -and $flag.provider) {
        if ($flag.provider -ne $Provider) {
            Write-Log INFO "Resume: switching provider from cmdline '$Provider' to flag value '$($flag.provider)'."
            $Provider     = $flag.provider
            $ThisProvider = $ProviderConfig[$Provider]
        }
    } else {
        Write-Log WARN '-Resume passed but no resume flag found. Continuing with whatever -Provider was given.'
    }
    # RunOnce auto-deletes when it fires; this is belt-and-suspenders for the
    # case where it didn't (manually triggered resume, etc).
    Remove-RunOnceResume
    $existing = Get-CompletedSteps
    Write-Log INFO "==== ClawFactory Secure Setup - resuming after restart (provider=$Provider) ===="
    Write-Host ''
    Write-Host 'Welcome back - continuing installation.' -ForegroundColor Cyan
    Write-Host "Steps already completed before restart: $($existing -join ', ')"
    Write-Host ''
} else {
    if (Test-Path $CheckpointFile) { Remove-Item $CheckpointFile -Force }
    Remove-ResumeFlag
    Write-Log INFO "==== ClawFactory Secure Setup - starting (provider=$Provider) ===="
}

Invoke-WithRollback {
    Step-Preflight
    Step-EnsureWsl
    Step-ConfigureWslConf
    Step-RestartWsl
    Step-CreateClawUser
    Step-SetDefaultUser
    Step-InstallDocker
    Step-EgressFirewall
    Step-InstallOllama           # no-op unless Provider = ollama
    Step-InstallOpenClaw
    Step-PreinstallGatewayRuntime  # bypass egress firewall: install gateway deps as root
    Step-ConfigureOpenClaw       # gateway, default model, auth profile registration
    Step-CreateAgentDirectories  # pre-create 4 agent dirs (orchestrator, scout, builder, publisher)
    Step-ApplySafetyRules        # SOUL.md + hash pinning
    Step-WireProviderKey         # write auth-profiles.json with API key
    Step-WindowsFirewallDeny
    Step-PostInstall
    Step-ConfigureAgents         # step 15: stage agent.md prompts via bootstrap.ps1
}
Write-Log INFO '==== ClawFactory Secure Setup - completed successfully ===='
Remove-ResumeFlag
Remove-RunOnceResume

Write-Host ''
Write-Host 'SUCCESS. Your hardened Skills Factory is ready.' -ForegroundColor Green
Write-Host "Log: $LogFile"
Write-Host "Provider: $($ThisProvider.DisplayName)  |  Default model: $($ThisProvider.DefaultModel)"
# Next-step commands are printed by bootstrap.ps1 (Step 15).
exit 0
