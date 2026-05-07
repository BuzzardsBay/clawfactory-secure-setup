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
    [string]$SourceExe = '',
    # Path to the Inno Setup {tmp} directory where the bundled
    # ubuntu-rootfs.tar.gz lives during install (passed by [Run] as {tmp}).
    # When non-empty AND the tarball is present, Install-WslDistroWithFallback
    # uses `wsl --import` as the primary path; otherwise falls through to
    # `wsl --install` (network). Empty on dev-tree invocations and on
    # /resume relaunches (the tarball has already been consumed).
    [string]$BundledRootfsDir = ''
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
# v1.0.4 - pre-install OpenClaw build deps before install.sh runs
$InstallerVersion      = '1.0.4'
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
$OpenClawNpmVersion    = '2026.4.23'
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
    # PRIMARY: `wsl --import` from a bundled rootfs tarball passed in via
    # $BundledRootfs. Offline, fast, deterministic. Single WSL2 attempt;
    # any non-zero exit (including HCS_E_HYPERV_NOT_INSTALLED) falls through
    # to the network install path below, which has its own WSL1 fallback.
    #
    # FALLBACK: existing `wsl --install` (network) path. Used when no
    # bundle was passed, the tarball is absent, or the bundled import
    # failed. Same WSL2 → WSL1 fallback shape as before, unchanged.
    #
    # Returns the variant string ('wsl2' or 'wsl1') for logging.
    param([string]$BundledRootfs = '')

    if ($BundledRootfs -and (Test-Path -LiteralPath $BundledRootfs)) {
        $WslInstallDir = 'C:\Program Files\ClawFactory\WSL'
        if (-not (Test-Path -LiteralPath $WslInstallDir)) {
            New-Item -ItemType Directory -Path $WslInstallDir -Force | Out-Null
        }
        Write-Log INFO 'Installing Ubuntu from bundled rootfs (offline).'
        & wsl.exe --import $WslDistro $WslInstallDir $BundledRootfs --version 2 2>&1 |
            ForEach-Object { Add-Content -LiteralPath $LogFile -Value "[wsl --import v2] $_" -Encoding UTF8 }
        $exit = $LASTEXITCODE
        if ($exit -eq 0) {
            Write-Log INFO 'WSL2 import from bundle succeeded.'
            return 'wsl2'
        }
        Write-Log WARN "wsl --import failed (exit $exit), falling through to wsl --install."
    }

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
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script.Replace("`r`n", "`n").Replace("`r", "`n")))

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
    #   3. WSL not installed at all -> run wsl --install --no-distribution,
    #      write RunOnce key, save checkpoint, show restart dialog, reboot.
    #      The $Resume branch above completes the distro install after restart.
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
        $bundledTarball = if ($BundledRootfsDir) { Join-Path $BundledRootfsDir 'ubuntu-rootfs.tar.gz' } else { '' }
        $variant = Install-WslDistroWithFallback -BundledRootfs $bundledTarball
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
    # Uses Process.Start (not 2>&1) — same reason as Invoke-WslBash: PS 5.1
    # converts each stderr line to an ErrorRecord and $ErrorActionPreference =
    # 'Stop' turns those into terminating errors before we can check ExitCode.
    $psiStatus = New-Object System.Diagnostics.ProcessStartInfo
    $psiStatus.FileName               = 'wsl.exe'
    $psiStatus.Arguments              = '--status'
    $psiStatus.RedirectStandardOutput = $true
    $psiStatus.RedirectStandardError  = $true
    $psiStatus.UseShellExecute        = $false
    $psiStatus.CreateNoWindow         = $true
    $procStatus = [System.Diagnostics.Process]::Start($psiStatus)
    $null = $procStatus.StandardOutput.ReadToEnd()
    $null = $procStatus.StandardError.ReadToEnd()
    $procStatus.WaitForExit()
    $kernelOk = ($procStatus.ExitCode -eq 0)

    if ($kernelOk) {
        Write-Log INFO 'WSL2 kernel loaded but Ubuntu missing - installing Ubuntu only.'
        $bundledTarball = if ($BundledRootfsDir) { Join-Path $BundledRootfsDir 'ubuntu-rootfs.tar.gz' } else { '' }
        $variant = Install-WslDistroWithFallback -BundledRootfs $bundledTarball
        Write-Log INFO "WSL variant installed: $variant"
        New-ClawUserAndSetDefault
        Start-Sleep -Seconds 5
        if (-not (Test-WslFunctional)) {
            throw 'WSL could not be configured on this machine. Please contact support at hello@avitalresearch.com'
        }
        Save-Checkpoint 'EnsureWsl'
        return
    }

    # WSL not installed — install kernel (no distro), then reboot.
    # The $Resume branch above completes the distro install after restart.
    Write-Log INFO 'WSL2 not installed. Running wsl --install --no-distribution.'
    $psiInstall = New-Object System.Diagnostics.ProcessStartInfo
    $psiInstall.FileName               = 'wsl.exe'
    $psiInstall.Arguments              = '--install --no-distribution'
    $psiInstall.RedirectStandardOutput = $true
    $psiInstall.RedirectStandardError  = $true
    $psiInstall.UseShellExecute        = $false
    $psiInstall.CreateNoWindow         = $true
    $procInstall = [System.Diagnostics.Process]::Start($psiInstall)
    $wslOut = $procInstall.StandardOutput.ReadToEnd() + $procInstall.StandardError.ReadToEnd()
    $procInstall.WaitForExit()
    $wslRc  = $procInstall.ExitCode
    Write-Log INFO "wsl --install --no-distribution exit code: $wslRc"
    if ($wslRc -notin @(0, 3010)) {
        throw "wsl --install --no-distribution failed (exit $wslRc): $wslOut"
    }

    # Detect whether the kernel is immediately usable without a reboot.
    $psiStatus2 = New-Object System.Diagnostics.ProcessStartInfo
    $psiStatus2.FileName               = 'wsl.exe'
    $psiStatus2.Arguments              = '--status'
    $psiStatus2.RedirectStandardOutput = $true
    $psiStatus2.RedirectStandardError  = $true
    $psiStatus2.UseShellExecute        = $false
    $psiStatus2.CreateNoWindow         = $true
    $procStatus2 = [System.Diagnostics.Process]::Start($psiStatus2)
    $null = $procStatus2.StandardOutput.ReadToEnd()
    $null = $procStatus2.StandardError.ReadToEnd()
    $procStatus2.WaitForExit()
    if ($procStatus2.ExitCode -eq 0) {
        Write-Log INFO 'WSL kernel loaded without reboot — installing distro now.'
        $bundledTarball = if ($BundledRootfsDir) { Join-Path $BundledRootfsDir 'ubuntu-rootfs.tar.gz' } else { '' }
        $variant = Install-WslDistroWithFallback -BundledRootfs $bundledTarball
        Write-Log INFO "WSL variant installed: $variant"
        New-ClawUserAndSetDefault
        Start-Sleep -Seconds 5
        if (-not (Test-WslFunctional)) {
            throw 'WSL could not be configured on this machine. Please contact support at hello@avitalresearch.com'
        }
        Save-Checkpoint 'EnsureWsl'
        return
    }

    # Reboot required — write RunOnce key, save checkpoint, restart.
    $runOnceVal = "`"$SourceExe`" /SILENT /SUPPRESSMSGBOXES /NORESTART /resume"
    Set-ItemProperty -Path $RunOnceRegPath -Name 'ClawFactoryResume' -Value $runOnceVal -Type String
    Write-Log INFO "Reboot required. RunOnce key registered: $runOnceVal"
    Save-Checkpoint 'EnsureWsl'
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "WSL2 requires a restart to complete setup.`nClawFactory will continue automatically after restart.`nClick OK to restart now.",
        'Restart Required',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    Restart-Computer -Force
}

function Step-ConfigureWslConfig {
    # v1.0.1: write/merge %USERPROFILE%\.wslconfig with [wsl2] vmIdleTimeout=-1
    # so the WSL VM (and the gateway) stays alive while Windows is up. WSL2's
    # default vmIdleTimeout is 60s; without this the gateway flaps every minute.
    # Singular "WslConfig" (Windows-side .wslconfig) vs the existing plural
    # "WslConf" function below (Ubuntu-side /etc/wsl.conf).
    Write-Log INFO 'Step 2b: Ensuring %USERPROFILE%\.wslconfig has [wsl2] vmIdleTimeout=-1.'
    try {
        $WslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'
        $needsShutdown = $false
        $banner    = '# Added by ClawFactory v1.0.1 - keeps WSL VM alive so the gateway stays running.'
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

        if (-not (Test-Path -LiteralPath $WslConfigPath)) {
            # Branch 1: file missing - create it.
            $content = "[wsl2]`r`nvmIdleTimeout=-1`r`n$banner`r`n"
            [System.IO.File]::WriteAllText($WslConfigPath, $content, $utf8NoBom)
            Write-Log INFO "Created .wslconfig at $WslConfigPath"
            $needsShutdown = $true
        } else {
            $existing = [System.IO.File]::ReadAllText($WslConfigPath)
            if ($null -eq $existing) { $existing = '' }

            $hasWsl2Section = $existing -match '(?im)^\s*\[wsl2\]\s*$'

            # Pull the [wsl2] section body (until next [section] or EOF) for
            # inspection. Used to test for an existing vmIdleTimeout key only
            # within that section, so a key in a different section doesn't
            # confuse the merge.
            $wsl2BodyMatch = [regex]::Match($existing, '(?ims)^\s*\[wsl2\]\s*\r?\n(.*?)(?=^\s*\[[^\]]+\]\s*\r?\n|\z)')
            $wsl2Body      = if ($wsl2BodyMatch.Success) { $wsl2BodyMatch.Groups[1].Value } else { '' }
            $vmIdleMatch   = [regex]::Match($wsl2Body, '(?im)^\s*vmIdleTimeout\s*=\s*(\S+)\s*$')

            if (-not $hasWsl2Section) {
                # Branch 2: file exists, no [wsl2] section - append one.
                $sep = if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) { "`r`n" } else { '' }
                $newContent = $existing + $sep + "[wsl2]`r`nvmIdleTimeout=-1`r`n$banner`r`n"
                [System.IO.File]::WriteAllText($WslConfigPath, $newContent, $utf8NoBom)
                Write-Log INFO 'Added [wsl2] section to existing .wslconfig'
                $needsShutdown = $true
            } elseif (-not $vmIdleMatch.Success) {
                # Branch 3: [wsl2] exists, no vmIdleTimeout key - inject it
                # immediately after the [wsl2] header (only first match).
                $patched = [regex]::Replace($existing, '(?im)^(\s*\[wsl2\]\s*)$', "`$1`r`nvmIdleTimeout=-1", 1)
                [System.IO.File]::WriteAllText($WslConfigPath, $patched, $utf8NoBom)
                Write-Log INFO 'Added vmIdleTimeout=-1 to existing [wsl2] section'
                $needsShutdown = $true
            } else {
                $currentValue = $vmIdleMatch.Groups[1].Value.Trim()
                if ($currentValue -eq '-1') {
                    # Branch 4: already correct - no-op.
                    Write-Log INFO '.wslconfig already has vmIdleTimeout=-1; no change needed'
                    $needsShutdown = $false
                } else {
                    # Branch 5: different value already set. Visible install:
                    # WARN + MessageBox + proceed (user has an opinion; respect
                    # it but tell them). Silent install or non-interactive
                    # session: hard-fail through Invoke-WithRollback. Shipping
                    # a broken-on-idle gateway silently is worse than aborting.
                    Write-Log WARN ".wslconfig has vmIdleTimeout=$currentValue (recommended: -1). File NOT modified. User must edit $WslConfigPath manually and reboot for gateway stability."
                    $isInteractive = [System.Environment]::UserInteractive
                    $shownDialog   = $false
                    if ($isInteractive) {
                        try {
                            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                            [System.Windows.Forms.MessageBox]::Show(
                                "Your .wslconfig has a vmIdleTimeout setting that is different from ClawFactory's recommended value (-1).`r`n`r`nCurrent: $currentValue`r`nRecommended: -1`r`n`r`nWe did not modify your file. ClawFactory will install but the gateway may stop unexpectedly when WSL is idle.`r`n`r`nTo fix: edit $WslConfigPath and set vmIdleTimeout=-1, then restart your machine.`r`n`r`nSee README.md for details.",
                                'ClawFactory Setup - Manual Action Recommended',
                                [System.Windows.Forms.MessageBoxButtons]::OK,
                                [System.Windows.Forms.MessageBoxIcon]::Warning
                            ) | Out-Null
                            $shownDialog = $true
                        } catch {
                            Write-Log WARN "Could not show MessageBox: $($_.Exception.Message)"
                        }
                    }
                    if (-not $shownDialog) {
                        Write-Log ERROR ".wslconfig has vmIdleTimeout=$currentValue (not -1) and silent install detected. Cannot prompt user. Aborting install. Edit $WslConfigPath and set vmIdleTimeout=-1, then re-run setup."
                        # 'ClawFactory:' prefix is the hard-fail signature - the
                        # outer catch in this function re-throws on that prefix
                        # so Invoke-WithRollback can run its rollback path.
                        throw 'ClawFactory: .wslconfig conflict detected during silent install. See log for fix instructions.'
                    }
                    $needsShutdown = $false
                }
            }
        }

        if ($needsShutdown) {
            # Need a wsl --shutdown to make .wslconfig take effect immediately.
            # Only safe if Ubuntu is the only running distro - otherwise the
            # user has work in flight in another distro and we must ask first.
            $running = & wsl.exe --list --running --quiet 2>$null
            $runningDistros = @()
            if ($running) {
                $runningDistros = @(($running -split "`n") |
                    ForEach-Object { ($_ -replace "`0", '').Trim() } |
                    Where-Object { $_ -ne '' })
            }
            $otherDistros = @($runningDistros | Where-Object { $_ -ne $WslDistro })

            $proceedShutdown = $true
            if ($otherDistros.Count -gt 0) {
                $list = ($otherDistros -join "`r`n  ")
                try {
                    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                    $choice = [System.Windows.Forms.MessageBox]::Show(
                        "ClawFactory needs to restart WSL to apply the .wslconfig change. The following WSL distros are running:`r`n  $list`r`n`r`nContinuing will shut down ALL running WSL distros. Save any work in those distros before clicking OK.`r`n`r`nClick Cancel to skip - the .wslconfig change will take effect when WSL next idles.",
                        'ClawFactory Setup - Restart WSL?',
                        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
                        [System.Windows.Forms.MessageBoxIcon]::Question
                    )
                    if ($choice -ne [System.Windows.Forms.DialogResult]::OK) {
                        $proceedShutdown = $false
                    }
                } catch {
                    Write-Log WARN "Could not show MessageBox; defaulting to skip wsl --shutdown: $($_.Exception.Message)"
                    $proceedShutdown = $false
                }
            }

            if ($proceedShutdown) {
                & wsl.exe --shutdown 2>&1 | Out-Null
                Write-Log INFO 'Ran wsl --shutdown to apply .wslconfig change'
            } else {
                Write-Log INFO 'Skipped wsl --shutdown per user choice; .wslconfig will take effect on next WSL idle'
            }
        }

        Save-Checkpoint 'ConfigureWslConfig'
    } catch {
        if ($_.Exception.Message -like 'ClawFactory:*') {
            # Deliberate hard-fail (e.g. silent-install Branch 5 conflict).
            # Re-throw so Invoke-WithRollback runs the rollback path.
            throw
        }
        Write-Log WARN "Step-ConfigureWslConfig hit an error and is continuing: $($_.Exception.Message)"
    }
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

function Step-PreInstallOpenClawDeps {
    # v1.0.4: pre-install the build tools that OpenClaw's install.sh needs
    # ("Installing Linux build tools" phase). Without this, install.sh runs
    # apt-get install during Step-InstallOpenClaw - on slow/flaky networks
    # the apt fetch can stall well past Step-InstallOpenClaw's 15-minute
    # timeout. Pre-installing here moves the apt fetch into setup.ps1's own
    # apt step, which is logged separately and runs BEFORE Step-EgressFirewall
    # so there's no allowlist dependency. install.sh then finds the packages
    # already present and skips its own apt phase entirely.
    # Excludes nodejs deliberately - install.sh owns NodeSource setup.
    Write-Log INFO 'Step 6b: Pre-installing OpenClaw build dependencies (make g++ cmake python3 iptables).'
    $script = @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
timeout 300 apt-get install -y --no-install-recommends make g++ cmake python3 iptables
'@
    $rc = Invoke-WslBash -Script $script -User 'root'
    if ($rc -ne 0) { throw 'OpenClaw build deps install failed' }
    Save-Checkpoint 'OpenClawBuildDeps'
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
        'registry-1.docker.io','auth.docker.io','production.cloudflare.docker.com',
        # v1.0.3: Ubuntu apt repos. apt-as-root currently bypasses the firewall
        # (clawuser-scoped), but listed here as defense-in-depth in case install.sh
        # or a future skill drops privileges before running apt.
        'archive.ubuntu.com','security.ubuntu.com','ports.ubuntu.com','esm.ubuntu.com','ppa.launchpad.net'
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

if /usr/sbin/nft -f /etc/nftables.conf 2>`"`$NFT_ERR`"; then
    FW_BACKEND=`"nftables`"
    for ip in `$ALLOWED_IPS; do
        /usr/sbin/nft add element inet clawfactory allowed_ipv4 `"{ `$ip }`" 2>/dev/null || true
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
    # v1.0.3 regression guard: the laptop's runtime log showed bash receiving
    # 'ft' instead of 'nft' (line 41: ft: command not found) despite static
    # analysis showing intact source. We now use full path /usr/sbin/nft
    # throughout — this assertion fails the install if a future edit
    # accidentally drops back to the bare 'nft' form or otherwise loses
    # the full-path token before transport to bash.
    if ($script -notmatch '/usr/sbin/nft') {
        Write-Log ERROR 'Firewall script missing /usr/sbin/nft full-path token - aborting to avoid silent firewall misconfiguration.'
        throw 'ClawFactory: firewall script validation failed'
    }

    $rc = Invoke-WslBash -Script $script -User 'root'
    if ($rc -ne 0) {
        # v1.0.3: do NOT checkpoint on failure. Was previously WARN+checkpoint,
        # which silently masked the firewall never coming up (exit 127 from
        # the nft mangling looked like a successful step). Logging ERROR and
        # skipping Save-Checkpoint means a -Resume run will retry this step.
        Write-Log ERROR "Egress firewall setup returned exit $rc. Firewall is NOT active. Check install.log; re-run setup.ps1 -Resume after diagnosing."
        return
    }

    # Surface which backend the script picked so the install log is
    # explicit (the bash output is also captured in install.log).
    $backendCheck = @'
cat /etc/clawfactory/fw-backend 2>/dev/null || echo unknown
'@
    $null = Invoke-WslBash -Script $backendCheck -User 'root'

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
# inside install.sh) hangs waiting on interactive input. 15 minutes is enough
# for any non-interactive run; longer than that means we're stuck. SIGTERM
# first (graceful), then SIGKILL after 30s (--kill-after) if the child
# trapped SIGTERM. timeout's exit code 124 = timed out.
set +e
NO_ONBOARD=1 OPENCLAW_VERSION=$OpenClawNpmVersion HOME=/home/clawuser USER=clawuser LOGNAME=clawuser timeout --foreground --kill-after=30 900 bash `"`$TMP`" -- --no-onboard > >(tee /tmp/openclaw-install.log) 2>&1
INSTALL_RC=`$?
set -e
if [ `$INSTALL_RC -eq 124 ]; then
    echo `"!! OpenClaw install.sh did not complete within 15 minutes (timeout). The install hung - check the actual install.sh output above for the real cause (apt mirror outage, npm registry latency, DNS issue, or interactive prompt on closed stdin).`" >&2
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
    if ($rc -eq 44) { throw 'OpenClaw install timed out after 15 minutes. install.sh hung; check install.log for the actual stalled command (apt, npm, or interactive prompt). Re-run setup.ps1 -Resume to retry.' }
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
    Write-Log INFO 'Step 8b: Installing OpenClaw Gateway systemd service via canonical `openclaw gateway install --force`.'

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

# --- b. Systemd unit override: disable per-start timeout + retry caps ----
# The plugin loader can spend many seconds waiting on each non-pre-installed
# plugin's npm install before timing out. Default TimeoutStartSec=30s in the
# unit means systemd SIGTERMs the gateway mid-init. Bumping to infinity lets
# the loader finish and the HTTP server bind. Once all bundled plugins are
# pre-installed, this should drop to a low number (e.g. 60).
#
# StartLimitBurst=0 + StartLimitIntervalSec=0 disable systemd's "too many
# restarts in too short a window" cap. Without these, a few rapid restarts
# (e.g. while iterating on first-boot config) trip the rate-limit and
# systemd refuses further restarts until the user runs `reset-failed`.
# Zero on both means: never give up retrying.
OVERRIDE_DIR=/home/clawuser/.config/systemd/user/openclaw-gateway.service.d
mkdir -p "$OVERRIDE_DIR"
cat > "$OVERRIDE_DIR/clawfactory-tunables.conf" <<'EOF'
[Service]
TimeoutStartSec=infinity

[Unit]
StartLimitBurst=0
StartLimitIntervalSec=0
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

    # Pre-install gateway config: `openclaw gateway install --force` starts
    # the service immediately after writing the unit, and the service exits
    # 78/CONFIG if gateway.mode isn't already set in ~/.openclaw/openclaw.json
    # (the unit's ExecStart parses config before binding the socket). Set the
    # three required keys here as clawuser before the install fires. Step 9a
    # (Step-ConfigureOpenClaw $script9a) re-applies the same three values
    # idempotently as defense-in-depth.
    $script8c = @'
set -e
openclaw config set gateway.mode local >/dev/null
openclaw config set gateway.bind loopback >/dev/null
openclaw config set gateway.port 8787 >/dev/null
echo "[gateway-preconfig] gateway.{mode,bind,port} set"
'@
    $rcPreconfig = Invoke-WslBash -Script $script8c -User $WslUser
    if ($rcPreconfig -ne 0) { throw "Failed to pre-configure gateway (exit=$rcPreconfig)" }

    # Install the OpenClaw Gateway systemd user service via the canonical
    # `openclaw gateway install --force --port 8787`. Validated 2026-04-30 on
    # the laptop with 2026.4.27: this single command auto-generates a gateway
    # token (saved to ~/.openclaw/openclaw.json), writes the unit at
    # ~/.config/systemd/user/openclaw-gateway.service (~923 bytes), and is
    # idempotent on re-runs. Replaces the prior systemctl-start-then-fallback
    # dance which was a workaround for the missing unit (the prior code tried
    # to start a unit nothing in our flow had ever created).
    #
    # After install, daemon-reload + enable + restart per openclaw issue
    # #65184 (a known race where the service stays in 'inactive' state if
    # these steps are skipped). The TimeoutStartSec=infinity drop-in written
    # in $script sub-block (b) is auto-loaded on daemon-reload because
    # systemd merges all *.d/*.conf overrides when the unit loads.
    #
    # Runs as clawuser (not root) so the unit lands under /home/clawuser/
    # .config/systemd/user/, not /root/.
    $gatewayInstall = @'
set -e
LOG=/tmp/openclaw-install.log
mkdir -p "$(dirname "$LOG")"

echo "[gateway-install] openclaw gateway install --force --port 8787"
set +e
openclaw gateway install --force --port 8787 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
    echo "[gateway-install] WARN: openclaw gateway install --force returned $rc - continuing to daemon-reload/restart; PowerShell-side /status poll is the source of truth for health." >&2
fi

echo "[gateway-install] systemctl --user daemon-reload"
systemctl --user daemon-reload 2>&1 | tee -a "$LOG" || true

echo "[gateway-install] systemctl --user enable openclaw-gateway.service"
systemctl --user enable openclaw-gateway.service 2>&1 | tee -a "$LOG" || true

echo "[gateway-install] systemctl --user restart openclaw-gateway.service"
systemctl --user restart openclaw-gateway.service 2>&1 | tee -a "$LOG" || true

# Per #65184, give the unit ~5s to fully bind before probing is-active.
sleep 5

# Poll is-active up to 6x with 2s gaps (~12s total). Non-blocking on miss.
for i in 1 2 3 4 5 6; do
    state="$(systemctl --user is-active openclaw-gateway.service 2>/dev/null || true)"
    if [ "$state" = "active" ]; then
        echo "[gateway-install] Gateway service active (attempt $i)"
        exit 0
    fi
    sleep 2
done
echo "[gateway-install] WARNING: gateway service did not become active within 12s - install will continue" >&2
exit 0
'@
    $rcGateway = Invoke-WslBash -Script $gatewayInstall -User $WslUser
    if ($rcGateway -ne 0) {
        Write-Log WARN "openclaw gateway install --force returned $rcGateway; the install command's exit code is no longer treated as fatal. Health is determined by the /status poll below."
    }

    # Poll gateway health via curl /status for up to 60s (6 attempts, 10s
    # apart). The install command can return non-zero for transient reasons
    # (e.g., racing with a prior unit shutdown) while still leaving the
    # gateway healthy after restart. Trust the HTTP probe, not the exit code.
    $healthy = $false
    for ($i = 1; $i -le 6; $i++) {
        $rcCurl = Invoke-WslBash -Script 'curl -fsS --max-time 5 http://127.0.0.1:8787/status >/dev/null 2>&1' -User $WslUser
        if ($rcCurl -eq 0) {
            Write-Log INFO "Gateway confirmed healthy via poll (attempt $i)."
            $healthy = $true
            break
        }
        if ($i -lt 6) { Start-Sleep -Seconds 10 }
    }
    if (-not $healthy) {
        throw 'Gateway did not respond after 60 seconds'
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

    # Step 9a: gateway settings (loopback + port + mode) + bonjour disable.
    # gateway.mode=local is required - without it `openclaw gateway run` refuses
    # to start with "existing config is missing gateway.mode".
    #
    # plugins.entries.bonjour.enabled=false: on 2026.4.23 the
    # OPENCLAW_DISABLE_BONJOUR=1 env var (post-install drop-in, defense-in-depth)
    # is not honored - bonjour runs anyway, gets stuck in probing state, and
    # saturates the gateway event loop. Disabling at the config level here
    # (pre-gateway-start, no #47133 risk) is the load-bearing fix; the env
    # var drop-in stays as a forward-compat hedge for newer OpenClaw versions
    # where the env var IS honored.
    $script9a = @'
set -e
openclaw config set gateway.bind loopback >/dev/null
openclaw config set gateway.port 8787 >/dev/null
openclaw config set gateway.mode local >/dev/null
openclaw config set plugins.entries.bonjour.enabled false >/dev/null
echo "gateway configured (bonjour disabled at plugins.entries.bonjour.enabled)"
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

function Step-EnableChatCompletions {
    # v1.0.1: enable the OpenClaw gateway's HTTP /v1/chat/completions endpoint
    # so a future native chat app can talk to the gateway over loopback. Idempotent
    # (`openclaw config set` is idempotent). Failure is non-fatal: gateway works
    # without it; only the native chat app stops working.
    Write-Log INFO 'Step 9b: Enabling gateway.http.endpoints.chatCompletions.enabled.'
    try {
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $tmpErr = [System.IO.Path]::GetTempFileName()
        try {
            $proc = Start-Process -FilePath 'wsl.exe' `
                -ArgumentList @('-d', $WslDistro, '-u', $WslUser, '--', 'bash', '-lc', 'openclaw config set gateway.http.endpoints.chatCompletions.enabled true') `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
            $exit   = $proc.ExitCode
            $stdout = (Get-Content -LiteralPath $tmpOut -Raw -ErrorAction SilentlyContinue) -as [string]
            $stderr = (Get-Content -LiteralPath $tmpErr -Raw -ErrorAction SilentlyContinue) -as [string]
        } finally {
            Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tmpErr -Force -ErrorAction SilentlyContinue
        }

        if ($exit -eq 0) {
            Write-Log INFO 'Enabled gateway.http.endpoints.chatCompletions.enabled'
            Save-Checkpoint 'EnableChatCompletions'
        } else {
            Write-Log WARN 'Failed to enable chatCompletions endpoint. The gateway will work, but the native chat app will not connect until this is fixed manually. See logs for details.'
            if ($stdout) { Write-Log WARN "EnableChatCompletions stdout: $($stdout.Trim())" }
            if ($stderr) { Write-Log WARN "EnableChatCompletions stderr: $($stderr.Trim())" }
            Write-Log WARN "EnableChatCompletions exit code: $exit"
        }
    } catch {
        Write-Log WARN "Step-EnableChatCompletions hit an error and is continuing: $($_.Exception.Message)"
    }
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

function Step-RegisterWslHostTask {
    # v1.0.2: keep one wsl.exe session alive permanently via a hidden Windows
    # scheduled task. WSL issues a full systemd shutdown inside the distro
    # when the LAST wsl.exe session exits, tearing down user@1000, docker,
    # containerd, and the gateway regardless of linger or vmIdleTimeout=-1
    # (v1.0.1). vmIdleTimeout keeps the kernel alive; this task keeps the
    # distro-level init chain alive. Together they cover both shutdown paths.
    # Non-fatal: gateway works without it, just won't survive idle.
    Write-Log INFO 'Step 16: Registering ClawFactory WSL Host task (keeps gateway alive during idle).'
    $TaskName = 'ClawFactory WSL Host'
    $TaskDesc = 'Keeps a WSL session alive so the OpenClaw gateway stays running. Do not disable.'
    try {
        $currentUser = "$env:USERDOMAIN\$env:USERNAME"
        $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>$TaskDesc</Description>
    <Author>ClawFactory</Author>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$currentUser</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$currentUser</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>999</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>wsl.exe</Command>
      <Arguments>-d $WslDistro -u $WslUser -- sleep infinity</Arguments>
    </Exec>
  </Actions>
</Task>
"@

        # Idempotent: remove any prior registration so we always end up with
        # the v1.0.2 XML, not whatever a previous install left behind.
        $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log INFO "Removed existing '$TaskName' task before re-registering."
        }

        Register-ScheduledTask -Xml $taskXml -TaskName $TaskName -Force | Out-Null

        # Start immediately so the gateway has a keep-alive session right now,
        # rather than waiting for the next logon.
        Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

        $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($t -and $t.State -ne 'Disabled') {
            Write-Log INFO "Scheduled task '$TaskName' registered and enabled (state=$($t.State))."
            Save-Checkpoint 'RegisterWslHostTask'
        } else {
            Write-Log WARN "Scheduled task '$TaskName' is missing or Disabled after registration. Gateway may go dark on idle."
        }
    } catch {
        Write-Log WARN "Step-RegisterWslHostTask hit an error and is continuing: $($_.Exception.Message)"
    }
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
    Step-ConfigureWslConfig      # v1.0.1: Windows-side .wslconfig (vmIdleTimeout=-1)
    Step-ConfigureWslConf
    Step-RestartWsl
    Step-CreateClawUser
    Step-SetDefaultUser
    Step-InstallDocker
    Step-PreInstallOpenClawDeps  # v1.0.4: apt-fetch make/g++/cmake/python3 BEFORE the firewall comes up
    Step-EgressFirewall
    Step-InstallOllama           # no-op unless Provider = ollama
    Step-InstallOpenClaw
    # Step-ConfigureOpenClaw runs BEFORE Step-PreinstallGatewayRuntime so all
    # `openclaw config set` / `openclaw models set` calls execute while the
    # gateway is NOT yet started. Per openclaw/openclaw#47133, CLI commands
    # that connect to a running gateway can trigger SIGTERM on disconnect;
    # writing config to ~/.openclaw/openclaw.json directly (no gateway
    # connection) avoids the cycle entirely.
    Step-ConfigureOpenClaw       # gateway, default model, auth profile registration (writes openclaw.json)
    Step-PreinstallGatewayRuntime  # bypass egress firewall: install gateway deps as root, then start gateway
    Step-EnableChatCompletions   # v1.0.1, repositioned in v1.0.2: must run AFTER runtime install (`openclaw config set` needs the runtime present, or it just prints --help)
    Step-CreateAgentDirectories  # pre-create 4 agent dirs (orchestrator, scout, builder, publisher)
    Step-ApplySafetyRules        # SOUL.md + hash pinning
    Step-WireProviderKey         # write auth-profiles.json with API key
    Step-WindowsFirewallDeny
    Step-PostInstall
    Step-ConfigureAgents         # step 15: stage agent.md prompts via bootstrap.ps1
}

#--- Final gateway health gate ------------------------------------------------
# After all install steps complete, confirm the gateway is responding before
# reporting success. This is the real health gate — replaces the old
# `openclaw doctor` final-check (removed because of openclaw/openclaw#47133:
# CLI commands that open a WS connection to the running gateway trigger
# SIGTERM on disconnect, restart cycle). HTTP /status uses no WS and never
# triggers #47133. Polled from the Windows side (Invoke-WebRequest), which
# reaches WSL2's loopback via the kernel's localhost forwarding.
# 15 attempts × 2-second intervals = 30 seconds total.
Write-Log INFO 'Final gateway health gate: polling http://127.0.0.1:8787/status for up to 30s.'
$healthy = $false
for ($i = 1; $i -le 15; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:8787/status' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) {
            Write-Log INFO "Final health gate: gateway responsive on attempt $i."
            $healthy = $true
            break
        }
    } catch {
        # Not yet responding - sleep and retry. Common reasons: the unit is
        # still in restart back-off (StartLimitBurst=0 means it will keep
        # retrying), or the WSL2 localhost forwarder hasn't picked up the
        # listening socket yet (Windows<->WSL2 forwarding is one-way and
        # has a ~1-2s settle window after the listener binds).
    }
    Start-Sleep -Seconds 2
}
if (-not $healthy) {
    throw 'Final gateway health gate failed: http://127.0.0.1:8787/status did not return 200 within 30 seconds. Diagnose with: wsl -d Ubuntu -u clawuser -- journalctl --user -u openclaw-gateway -n 100, then `cat ~/.openclaw/logs/gateway.log`. After the underlying issue is fixed, re-run setup.ps1 (the 15 install steps will skip via checkpoints; only the final gate re-runs).'
}

# v1.0.2: register the WSL Host keep-alive task only after the gateway has
# been proven healthy. If the health gate above throws, this never runs and
# we don't leave a dangling task pointing at a broken install. Outside the
# Invoke-WithRollback block on purpose - failure here is non-fatal.
Step-RegisterWslHostTask

Write-Log INFO '==== ClawFactory Secure Setup - completed successfully ===='
Remove-ResumeFlag
Remove-RunOnceResume

Write-Host ''
Write-Host 'SUCCESS. Your hardened Skills Factory is ready.' -ForegroundColor Green
Write-Host "Log: $LogFile"
Write-Host "Provider: $($ThisProvider.DisplayName)  |  Default model: $($ThisProvider.DefaultModel)"
# Next-step commands are printed by bootstrap.ps1 (Step 15).
exit 0
