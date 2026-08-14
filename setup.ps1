[CmdletBinding()]
param(
    [switch]$AcknowledgedOpenClawUrl,
    [ValidateSet('grok','openai','claude','gemini','ollama','later')]
    [string]$Provider = 'grok',
    # Set when re-launched by the ClawFactory-Resume scheduled task after a
    # reboot triggered by Step-EnsureWsl. Skips the WSL install and waits for
    # the kernel to come up instead.
    [switch]$Resume,
    # Path to the original installer .exe; passed by Inno's [Run] section as
    # {srcexe} so we can register a scheduled task that relaunches the same
    # .exe with /SILENT /resume after a reboot. Empty when setup.ps1 is invoked outside
    # of the Inno wizard - in that case we fall back to relaunching setup.ps1
    # directly via powershell.exe.
    [string]$SourceExe = '',
    # Path to the Inno Setup {tmp} directory where the bundled
    # ubuntu-rootfs.tar.gz lives during install (passed by [Run] as {tmp}).
    # When non-empty AND the tarball is present, Install-WslDistroWithFallback
    # uses `wsl --import` as the primary path; otherwise falls through to
    # `wsl --install` (network). Empty on dev-tree invocations and on
    # /resume relaunches (the tarball has already been consumed).
    [string]$BundledRootfsDir = '',
    # v1.0.12: silent-mode propagation. Set by Inno [Run] when WizardSilent()
    # is true, so setup.ps1's helpers can refuse interactive primitives
    # (Read-Host, MessageBox.Show) instead of hanging the install.
    [switch]$Silent
)

# ClawFactory Secure Setup - main automation script.
# Runs as admin on Windows; drops to clawuser inside WSL for non-privileged work.
# Targets PowerShell 5.1 (ships with Win11) - no PS7 bootstrap required.
#
# Security controls baked in:
#   [R2] OpenClaw install.sh SHA-256 logged at install time to checkpoint.json (no pin).
#   [R3] WSL egress firewall (nftables, clawuser UID-scoped, provider-specific allowlist).
#   [R4] Windows Firewall inbound-deny on gateway port.
#   [R5] Provider API key read from Windows Credential Manager (DPAPI).
#   [R6] SOUL.md frozen root-owned + immutable and hash-pinned; the turn gate
#        refuses the turn (soul_mismatch) if the hash changes. The pin has NOT
#        been in the orchestrator prompt since 8eaeb60, which replaced a
#        prompt-level "compute the hash yourself" rule with this code gate.
#   [R7] Checkpoint + rollback on failure.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

#--- Constants ----------------------------------------------------------------
# v1.0.4 - pre-install OpenClaw build deps before install.sh runs
# MUST equal MyAppVersion in ClawFactory-Secure-Setup.iss. That is the value the
# customer sees (it feeds AppVersion, so Apps & Features and the uninstall entry
# show it), which makes it the authority; this constant follows it.
# scripts/build_release.ps1 fails the build if the two disagree.
# It sat at 1.0.34 from 2026-05 through v1.1.1, roughly fifteen releases, because
# nothing referenced it and nothing compared it. It is still unreferenced today;
# the assertion exists so that stops being possible rather than staying luck.
$InstallerVersion      = '1.2.0'
# [R2] OpenClaw install.sh is BUNDLED into the installer (resources\openclaw-install.sh).
# No network call to openclaw.ai/install.sh during install — that URL tracks "latest" and
# changed twice in 24 hours on 2026-05-09/10. Hash is computed at install time and written
# to checkpoint.json under "installShHash" for audit; no pinned hash, so upstream install.sh
# updates no longer break installs. To upgrade OpenClaw, see the comment block at the top
# of Step-InstallOpenClaw.
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
# v1.0.27: Switched from HKLM RunOnce to a Scheduled Task triggered AtStartup
# under NT AUTHORITY\SYSTEM. RunOnce only fires on interactive user logon,
# which never happens under `az vm run-command invoke` (SYSTEM context, no
# logon) - that broke headless validation in v1.0.26. The scheduled task
# fires unconditionally on the next boot and self-unregisters on first run.
$ResumeFlagFile        = Join-Path $LogDir 'resume-after-restart.flag'
$ResumeTaskName        = 'ClawFactory-Resume'
$ResumeTaskScript      = Join-Path $LogDir 'resume-task.ps1'

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

#--- Silent-mode safety -----------------------------------------------------
# v1.0.12: every interactive primitive in this script (Read-Host, MessageBox)
# routes through one of these two helpers. Under -Silent or a non-interactive
# session, prompts return a default and dialogs are skipped, so /SILENT installs
# can never hang on stdin. See Task 2 of CLAWFACTORY COMPREHENSIVE HARDENING.
function Test-IsSilent {
    return ($script:Silent -or -not [Environment]::UserInteractive)
}

function Confirm-Or-Default {
    param([string]$Prompt, [string]$Default)
    if (Test-IsSilent) {
        Write-Log INFO "Silent mode: auto-answering '$Prompt' with default '$Default'"
        return $Default
    }
    return (Read-Host $Prompt)
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
function Invoke-WslExe {
    # v1.0.12: thin Process.Start wrapper for `wsl.exe <args>` so callers
    # never trip the PowerShell 5.1 + 2>&1 + ErrorActionPreference='Stop'
    # bug that v1.0.7 fixed in Invoke-WslBash. Returns @{ ExitCode; StdOut;
    # StdErr }. Stderr is captured but not merged into stdout.
    # PS 5.1's ProcessStartInfo only has .Arguments (single string), not
    # .ArgumentList - so we quote args here. Callers pass plain tokens and
    # any token containing whitespace gets double-quoted.
    param([Parameter(Mandatory)][string[]]$Arguments)
    $quoted = $Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'wsl.exe'
    $psi.Arguments              = ($quoted -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    # v1.0.14: wsl.exe always outputs UTF-16-LE. Without explicit encoding
    # the StreamReader uses Console.OutputEncoding (CP1252/CP437) and decodes
    # output as null-padded bytes, breaking -contains checks and HCS_E detection.
    $psi.StandardOutputEncoding = [System.Text.Encoding]::Unicode
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::Unicode
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return @{ ExitCode = $proc.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

function Update-WslEngine {
    # v1.0.28: Run `wsl --update` so the WSL engine/kernel is current before
    # `wsl --install -d Ubuntu`. The baseline image's wsl.exe and kernel can
    # lag the WSL feature engine that ships with Windows, and the mismatch
    # surfaces as "Windows Subsystem for Linux must be updated to the latest
    # version" - a non-fatal WARN on the pre-reboot path (Step-ConfigureWslConfig)
    # but a HARD FATAL on the post-reboot resume path (where Install-Wsl
    # DistroWithFallback throws). v1.0.27 cycle on cfv-128 caught this:
    # resume branch hit wsl --install exit 1 with no recovery. Run --update
    # first so --install has a current engine to work with.
    #
    # Idempotent: wsl --update returns 0 on success AND on "already current"
    # AND on "no kernel installed yet, downloading" - all fine. A non-zero
    # exit is logged as WARN and we proceed (best-effort: if --update can't
    # run, --install may still succeed on a system that's already current).
    # Uses Process.Start (not 2>&1) for the same PS-5.1 / $ErrorActionPreference
    # = 'Stop' reason as the existing `wsl --status` calls in Step-EnsureWsl.
    Write-Log INFO 'Running wsl --update before distro install (v1.0.28 preflight).'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'wsl.exe'
    $psi.Arguments              = '--update'
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $out  = $proc.StandardOutput.ReadToEnd() + $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $rc = $proc.ExitCode
    Write-Log INFO "wsl --update exit code: $rc"
    if ($out) {
        # wsl.exe emits UTF-16 LE; strip the null bytes that show as 
        # gibberish in the log if we don't.
        $clean = ($out -replace "`0", '' -replace "`r?`n+", ' | ').Trim(' |')
        if ($clean) { Write-Log INFO "wsl --update output: $clean" }
    }
    if ($rc -ne 0) {
        Write-Log WARN "wsl --update returned $rc (continuing anyway - install may still succeed if the engine was already current)."
    }
}

function Test-WslFunctional {
    # True iff WSL2 + Ubuntu can actually run a command. Distinguishes:
    #   - WSL features just enabled but kernel not loaded (post-install,
    #     pre-reboot): `wsl --status` may succeed but `wsl -d Ubuntu -- true`
    #     fails or hangs.
    #   - WSL fully ready (post-reboot): both work.
    # v1.0.12: replaced `& wsl.exe ... 2>&1` with Process.Start (Invoke-WslExe)
    # for the same reason Invoke-WslBash uses Process.Start - PS 5.1 wraps
    # native stderr lines as ErrorRecords under $ErrorActionPreference='Stop'.
    try {
        $r = Invoke-WslExe -Arguments @('--status')
        if ($r.ExitCode -ne 0) { return $false }
    } catch { return $false }
    try {
        $rList = Invoke-WslExe -Arguments @('--list','--quiet')
    } catch { return $false }
    $list = ($rList.StdOut -split "`n") |
        ForEach-Object { $_.Trim() -replace "`0", '' }
    if (-not ($list -contains $WslDistro)) { return $false }
    $rTrue = Invoke-WslExe -Arguments @('-d', $WslDistro, '-u', 'root', '--', 'true')
    return ($rTrue.ExitCode -eq 0)
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

function Register-ResumeScheduledTask {
    # v1.0.27: Register a Scheduled Task that runs ONCE at next system startup
    # as NT AUTHORITY\SYSTEM and self-unregisters on first execution. Replaces
    # the v1.0.25/v1.0.26 HKLM RunOnce mechanism, which only fired on
    # interactive user logon - incompatible with `az vm run-command invoke`
    # headless validation (SYSTEM, no logon ever happens). The Scheduled Task
    # fires regardless of who (if anyone) logs in.
    #
    # The task action runs a sidecar PS1 (resume-task.ps1, written below) so
    # we avoid the nested-quoting hazard of cramming the relaunch command into
    # a New-ScheduledTaskAction -Argument string.
    param([string]$ExePath, [string]$ScriptPath)
    # Prefer relaunching the original installer .exe (so the user sees the
    # branded Inno wizard with /SILENT progress). Fall back to running
    # setup.ps1 directly if the .exe path is missing (e.g. user moved/deleted
    # the downloaded installer between launch and reboot).
    if ($ExePath -and (Test-Path -LiteralPath $ExePath)) {
        $launchLine = "Start-Process -FilePath '$ExePath' -ArgumentList '/SILENT','/SUPPRESSMSGBOXES','/NORESTART','/resume' -Wait"
    } else {
        $launchLine = "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','`"$ScriptPath`"','-AcknowledgedOpenClawUrl','-Resume' -Wait"
    }
    $scriptBody = @"
# ClawFactory-Resume scheduled-task body. Auto-generated by setup.ps1
# (v1.0.27). Self-unregisters first so the task is single-shot, then
# launches the installer's /resume branch under SYSTEM context.
Unregister-ScheduledTask -TaskName '$ResumeTaskName' -Confirm:`$false -ErrorAction SilentlyContinue
$launchLine
"@
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Set-Content -LiteralPath $ResumeTaskScript -Value $scriptBody -Encoding UTF8 -Force

    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
                   -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ResumeTaskScript`""
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable `
                   -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $ResumeTaskName `
        -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Log INFO "Scheduled Task '$ResumeTaskName' registered (AtStartup, SYSTEM). Resume command: $launchLine"
}

function Unregister-ResumeScheduledTask {
    # v1.0.27: Belt-and-suspenders cleanup. The task self-unregisters on its
    # first run, but if for some reason it didn't (manual resume, task ran
    # but unregister step errored, etc.), make sure it's gone.
    $task = Get-ScheduledTask -TaskName $ResumeTaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $ResumeTaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $ResumeTaskScript) {
        Remove-Item -LiteralPath $ResumeTaskScript -Force -ErrorAction SilentlyContinue
    }
}

function Show-RestartDialog {
    param([string]$Title, [string]$Message)
    # Use WPF MessageBox so we don't depend on WinForms init order. Falls back
    # to a console prompt if PresentationFramework is unavailable (very rare
    # on Win11).
    if (Test-IsSilent) {
        Write-Log INFO "Silent mode: skipping restart-notice dialog ($Title)."
        return
    }
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Information') | Out-Null
    } catch {
        Write-Host ''
        Write-Host "==== $Title ====" -ForegroundColor Yellow
        Write-Host $Message
        $null = Confirm-Or-Default 'Press Enter to restart now' ''
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
    # failed. Same WSL2 -> WSL1 fallback shape as before, unchanged.
    #
    # Returns the variant string ('wsl2' or 'wsl1') for logging.
    param([string]$BundledRootfs = '')

    if ($BundledRootfs -and (Test-Path -LiteralPath $BundledRootfs)) {
        # --- Rootfs pin. Same anchor as the SOUL and persona pins: a literal in
        # signed source, compared at install time, REFUSING on mismatch rather
        # than adopting whatever is on disk.
        #
        # This filesystem is the one every structural control in the product runs
        # inside: the nftables chain, both root brokers, the credential file
        # modes, the turn gate. Until 2026-08-05 it was a 341 MB gitignored blob
        # with no recorded source and no digest anywhere, so nothing at any layer
        # would have noticed a substituted one. A control built on an
        # unidentified filesystem is only as trustworthy as that filesystem.
        #
        # PROVENANCE (recorded 2026-08-05, see the close-out of the same date):
        #   Ubuntu 22.04.5 LTS (jammy), amd64, image built 2025-03-18.
        #   Source:  https://cloud-images.ubuntu.com/wsl/jammy/20250318/ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz
        #   Checked against Canonical's published SHA256SUMS at that same dated
        #   URL, retrieved over HTTPS on 2026-08-05. The digest below IS the
        #   published one, so this is upstream's value and not one we computed
        #   from the file we happen to hold. Use the DATED path when refetching;
        #   .../wsl/jammy/current/ moves to whatever the newest build is.
        #   The bytes are stock: no packages added, no users added, no file with
        #   an mtime later than the 2025-03-18 build stamp.
        #
        # A mismatch does NOT fall through to the network install path below.
        # Falling through would let a substituted rootfs turn into a quiet
        # "installed from the network instead" and lose the signal entirely.
        $expectedRootfsHash = '1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109'
        $rootfsHash = (Get-FileHash -LiteralPath $BundledRootfs -Algorithm SHA256).Hash.ToLower()
        if ($rootfsHash -ne $expectedRootfsHash) {
            throw ("The bundled Ubuntu rootfs does not match the digest this installer was built with. " +
                   "Expected $expectedRootfsHash but found $rootfsHash. Every security control ClawFactory " +
                   "installs runs inside this filesystem. Refusing to import an unverified one.")
        }
        Write-Log INFO "Bundled rootfs SHA-256 = $rootfsHash (matches the build-time pin)"

        $WslInstallDir = 'C:\Program Files\ClawFactory\WSL'
        if (-not (Test-Path -LiteralPath $WslInstallDir)) {
            New-Item -ItemType Directory -Path $WslInstallDir -Force | Out-Null
        }
        Write-Log INFO 'Installing Ubuntu from bundled rootfs (offline).'
        # v1.0.12: Process.Start instead of `wsl ... 2>&1 | ForEach-Object`
        # for the same reason as Invoke-WslBash.
        $rImp = Invoke-WslExe -Arguments @('--import', $WslDistro, $WslInstallDir, $BundledRootfs, '--version', '2')
        foreach ($line in (($rImp.StdOut + "`n" + $rImp.StdErr) -split "`r?`n")) {
            $t = $line.Trim()
            if ($t) { Add-Content -LiteralPath $LogFile -Value "[wsl --import v2] $t" -Encoding UTF8 }
        }
        if ($rImp.ExitCode -eq 0) {
            Write-Log INFO 'WSL2 import from bundle succeeded.'
            return 'wsl2'
        }
        Write-Log WARN "wsl --import failed (exit $($rImp.ExitCode)), falling through to wsl --install."
    }

    Write-Log INFO 'Installing Ubuntu (attempting WSL2 first).'
    $rInst = Invoke-WslExe -Arguments @('--install', '--no-launch', '-d', $WslDistro)
    $output = $rInst.StdOut + "`n" + $rInst.StdErr
    foreach ($line in ($output -split "`r?`n")) {
        $t = $line.TrimEnd()
        if ($t) { Add-Content -LiteralPath $LogFile -Value "[wsl install out] $t" -Encoding UTF8 }
    }
    if ($rInst.ExitCode -eq 0) {
        Write-Log INFO 'WSL2 install succeeded.'
        return 'wsl2'
    }
    $hyperVMissing = ($output -match 'HCS_E_HYPERV_NOT_INSTALLED' -or $output -match '0x80370102')
    if (-not $hyperVMissing) {
        throw "wsl --install failed (exit $($rInst.ExitCode)) and no fallback signal detected. See $LogFile."
    }
    Write-Log WARN 'WSL2 unavailable (HCS_E_HYPERV_NOT_INSTALLED). Falling back to WSL1.'
    $rFb1 = Invoke-WslExe -Arguments @('--install', '--no-distribution')
    foreach ($line in (($rFb1.StdOut + "`n" + $rFb1.StdErr) -split "`r?`n")) {
        $t = $line.Trim()
        if ($t) { Add-Content -LiteralPath $LogFile -Value "[wsl install fallback] $t" -Encoding UTF8 }
    }
    $rFb2 = Invoke-WslExe -Arguments @('--set-default-version', '1')
    foreach ($line in (($rFb2.StdOut + "`n" + $rFb2.StdErr) -split "`r?`n")) {
        $t = $line.Trim()
        if ($t) { Add-Content -LiteralPath $LogFile -Value "[wsl set-default-version] $t" -Encoding UTF8 }
    }
    $rFb3 = Invoke-WslExe -Arguments @('--install', '-d', $WslDistro, '--no-launch')
    foreach ($line in (($rFb3.StdOut + "`n" + $rFb3.StdErr) -split "`r?`n")) {
        $t = $line.Trim()
        if ($t) { Add-Content -LiteralPath $LogFile -Value "[wsl install -d $WslDistro] $t" -Encoding UTF8 }
    }
    if ($rFb3.ExitCode -ne 0) {
        throw "WSL1 fallback install also failed (exit $($rFb3.ExitCode))."
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
    # state, registers the ClawFactory-Resume scheduled task, prompts the
    # user, and reboots. The actual `wsl --install -d Ubuntu` happens AFTER
    # the reboot in the resume branch of Step-EnsureWsl - until features are
    # loaded post-reboot, `wsl --install` cannot create a usable instance.
    Write-Log INFO 'Persisting resume state and scheduling restart for WSL setup.'

    $credTarget = if ($ThisProvider.CredentialTarget) { $ThisProvider.CredentialTarget } else { '' }
    Save-ResumeFlag -Provider $Provider -InstallDir $PSScriptRoot -SourceExe $SourceExe -CredentialTarget $credTarget

    $scriptPath = Join-Path $PSScriptRoot 'setup.ps1'
    Register-ResumeScheduledTask -ExePath $SourceExe -ScriptPath $scriptPath

    Show-RestartDialog -Title 'ClawFactory - Restart Required' -Message (
        "WSL2 needs to be installed. Your computer will restart to complete this step.`r`n`r`n" +
        'ClawFactory will resume automatically after restart.'
    )

    Write-Log INFO 'Initiating restart.'
    # v1.0.12: pre-reboot path is not "done" - the resume run after reboot
    # will write the real INSTALLER_DONE marker. Setting this flag tells the
    # top-level finally to skip writing failure on this exit path.
    $script:RebootPending = $true
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
                $ans = Confirm-Or-Default "Rollback: unregister WSL '$WslDistro' distro? This deletes the Ubuntu distro and any files inside it. Type YES to confirm" 'YES'
                if ($ans -eq 'YES') {
                    # v1.0.12: Process.Start instead of `wsl ... 2>&1` for the
                    # same reason as Invoke-WslBash - PS 5.1 turns native stderr
                    # lines into terminating errors under $ErrorActionPreference='Stop'.
                    $rUnreg = Invoke-WslExe -Arguments @('--unregister', $WslDistro)
                    Write-Log INFO "WSL distro '$WslDistro' unregistered (exit=$($rUnreg.ExitCode))."
                    if ($rUnreg.ExitCode -ne 0 -and $rUnreg.StdErr) {
                        Write-Log WARN "wsl --unregister stderr: $($rUnreg.StdErr.Trim())"
                    }
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
        # v1.0.14: @() forces array context. PS 5.1 unrolls single-element
        # array returns to a bare scalar; under StrictMode 3 a string has no
        # .Count property, which threw "property 'Count' cannot be found"
        # in v1.0.13 when only the Preflight checkpoint had been saved.
        $done = @(Get-CompletedSteps)
        if ($done.Count -gt 0) {
            $ans = Confirm-Or-Default 'Installation failed. Run automatic rollback? (y/N)' 'n'
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
    # The script travels over STDIN, never over argv.
    #
    # It used to be base64'd onto the command line. That silently capped every
    # caller at the Windows CreateProcess limit of 32,767 characters, and on
    # 2026-08-05 the v1.2.0 clean-box validation found that BOTH v1 guards had
    # sailed past it: Step-InstallQuarantine needed 84,692 characters and
    # Step-InstallSend 153,912, so neither Guard 1 nor Guard 2 could install at
    # all. Step-InstallChatProxy was passing with 4,091 characters to spare,
    # which is a countdown rather than a margin.
    #
    # The limit was already known in this very file: Step-InstallOpenClaw
    # streams the ~93K install.sh over stdin for exactly this reason and says so
    # in its comment. That workaround was never generalised, so four later
    # security steps inherited the broken path. Generalising it is the fix.
    $lf = $Script.Replace("`r`n", "`n").Replace("`r", "`n")

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'wsl.exe'
    # bash -l -s: login shell (so ~/.profile is sourced and PATH picks up
    # ~/.local/bin for clawuser, where the openclaw shim lives) reading the
    # script from stdin. Same shell semantics as the old `bash -lc "... | bash -l"`,
    # including that a command inside the script which reads stdin will consume
    # script text; that exposure is unchanged, since the old inner shell was fed
    # by a pipe too.
    $psi.Arguments              = "-d $WslDistro -u $User --cd ~ -- bash -l -s"
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    # The command line is now fixed-size and tiny. Assert it anyway: this is the
    # guard that makes the whole class fail LOUDLY AND BY NAME if a future edit
    # puts a payload back on argv. Without it, the next oversized step deletes
    # itself from the product on a customer's machine with no code change to blame.
    if ($psi.Arguments.Length -gt 8000) {
        throw ("Invoke-WslBash: command line is $($psi.Arguments.Length) characters. " +
               'The script must travel over stdin, never argv (Windows caps a command line at 32,767). ' +
               'Something has put payload back on the command line. Refusing rather than truncating a security control.')
    }

    # .NET Framework builds the child's StandardInput StreamWriter from
    # Console.InputEncoding and writes that encoding's PREAMBLE into the pipe
    # before our first byte. When the console is UTF-8 the preamble is a BOM and
    # bash fails line 1 with "<BOM>set: command not found", which would silently
    # decapitate every script sent to WSL.
    #
    # Measured on 2026-08-05, not assumed. With a UTF-8 console the child
    # received `ef bb bf 65 63 68 6f`; after neutralising, `65 63 68 6f`. The
    # preamble appears even when writing raw bytes to BaseStream, and even when
    # BaseStream is captured before any write, because it is emitted when the
    # StreamWriter is constructed. Setting Console.OutputEncoding does nothing;
    # InputEncoding is the lever.
    #
    # This is environment-dependent, which is worse than a plain bug: it works on
    # a default console and breaks on a machine set to UTF-8. Hence fail loud
    # rather than best-effort. Where there is NO console the encoding is the OEM
    # codepage, which has no preamble, so the problem cannot arise and the catch
    # correctly swallows the failure to read or set it.
    $prevIn  = $null
    $bomRisk = $false
    try {
        if ([Console]::InputEncoding.GetPreamble().Length -gt 0) {
            $prevIn = [Console]::InputEncoding
            [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
            $bomRisk = ([Console]::InputEncoding.GetPreamble().Length -gt 0)
        }
    } catch {
        $bomRisk = $false
    }
    if ($bomRisk) {
        throw ('Invoke-WslBash: the console input encoding emits a byte-order mark that would corrupt ' +
               'line 1 of every script sent to WSL, and it could not be cleared. Refusing rather than ' +
               'half-installing a security control.')
    }

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)

        # Drain stdout/stderr BEFORE writing stdin. A large script can exceed the
        # pipe buffer; if the child blocks writing stdout while we block writing
        # stdin, both sides wait on each other forever. Async reads make the
        # order safe for any payload size.
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()

        # Raw UTF-8 bytes to the BaseStream: the StreamWriter would re-encode
        # through the console codepage and mangle non-ASCII, and PS 5.1 has no
        # StandardInputEncoding to set.
        $bytes = [Text.Encoding]::UTF8.GetBytes($lf)
        $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $proc.StandardInput.BaseStream.Flush()
        $proc.StandardInput.Close()

        $stdout = $outTask.Result
        $stderr = $errTask.Result
        $proc.WaitForExit()
        $exit = $proc.ExitCode
    } finally {
        if ($prevIn) { try { [Console]::InputEncoding = $prevIn } catch { } }
    }

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
    # Assert every resource the later steps stream into WSL is actually present.
    # These are read by Step-ApplySafetyRules / Step-InstallTurnGate /
    # Step-FreezeInjectedSoul / Step-InstallChatProxy. A real bug shipped past
    # review once: the steps were added across three security jobs but the
    # matching .iss [Files] entries were not, so a fresh install aborted at
    # step 15b with a bare FileNotFoundException and NO security controls. Fail
    # here instead -- loud, named, and before anything is changed on the machine.
    $required = @(
        'safety-rules.md', 'persona.md', 'openclaw-shim.sh', 'clawfactory-turn-gate.sh',
        'clawfactory-spend-check.js', 'install-turn-gate.sh', 'freeze-injected-soul.sh',
        'clawfactory-proxy.js', 'clawfactory-proxy.service', 'install-chat-proxy.sh',
        'gateway-wait.sh',
        'quarantine-lib.js', 'clawfactory-quarantined.js', 'clawfactory-quarantinectl.js',
        'clawfactory-quarantine-rm.js', 'clawfactory-quarantine.service',
        'clawfactory-quarantine-gc.service', 'clawfactory-quarantine-gc.timer',
        'install-quarantine.sh',
        'send-lib.js', 'send-smtp.js', 'clawfactory-sendd.js', 'clawfactory-sendctl.js',
        'clawfactory-send.js', 'clawfactory-send.service', 'clawfactory-send-gc.service',
        'clawfactory-send-gc.timer', 'clawfactory-fw-assert.sh', 'egress-policy.json',
        'install-send.sh',
        'clawfactory-read-fetch.sh', 'clawfactory-fetchctl.js', 'install-read-fetch.sh'
    )
    $resDir  = Join-Path $PSScriptRoot 'resources'
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $resDir $_)) })
    if ($missing.Count -gt 0) {
        throw ("Preflight: this build is missing security resources that the installer needs: {0}. " -f ($missing -join ', ') +
               "They exist in the repo but were not bundled into the installer ([Files] in ClawFactory-Secure-Setup.iss). " +
               "Installing anyway would produce an agent with NO turn gate, NO SOUL enforcement and NO chat proxy. Refusing.")
    }
    Write-Log INFO ("Preflight: all {0} security resources present." -f $required.Count)
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
    #      register ClawFactory-Resume scheduled task, save checkpoint, show
    #      restart dialog, reboot. The $Resume branch above completes the
    #      distro install after restart.
    Write-Log INFO 'Step 2: Ensuring WSL2 + Ubuntu are available.'

    # v1.0.33: record whether the target distro existed BEFORE we touched WSL.
    # Used by the uninstaller to decide whether `wsl --unregister` is destroying
    # something we created (safe to default-yes) or something the user owned
    # (default-no, require explicit -RemoveAll). The checkbox in the uninstall
    # UI remains the authority; this is defense-in-depth messaging only.
    # Only captured on the FIRST entry, not on /resume re-entry where Ubuntu
    # may have been imported pre-reboot.
    if (-not $Resume) {
        try {
            $rList = Invoke-WslExe -Arguments @('--list', '--quiet')
            $distroExisted = $false
            if ($rList.ExitCode -eq 0 -and $rList.StdOut) {
                $distros = @(($rList.StdOut -split "`n") |
                    ForEach-Object { ($_ -replace "`0", '').Trim() } |
                    Where-Object { $_ -ne '' })
                $distroExisted = ($distros -contains $WslDistro)
            }
            if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
            Set-Content -LiteralPath (Join-Path $LogDir 'wsl-state.txt') `
                -Value ([string]$distroExisted).ToLower() -Encoding UTF8 -NoNewline
            Write-Log INFO "Recorded distroExistedPreInstall=$distroExisted to wsl-state.txt"
        } catch {
            Write-Log WARN "Could not record wsl-state.txt: $($_.Exception.Message)"
        }
    }

    # v1.0.28: refresh the WSL engine BEFORE any wsl --install path. The
    # baseline image's bundled wsl.exe lags the latest engine and the v1.0.27
    # cycle on cfv-128 hit a fatal "must be updated to the latest version"
    # on the resume branch's distro install. Running --update first is
    # idempotent and covers all three branches below.
    Update-WslEngine

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
    # Uses Process.Start (not 2>&1) - same reason as Invoke-WslBash: PS 5.1
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

    # WSL not installed - install kernel (no distro), then reboot.
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
        Write-Log INFO "wsl --install returned $wslRc (elevation required or reboot pending) - proceeding to reboot-and-resume path."
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
        Write-Log INFO 'WSL kernel loaded without reboot - installing distro now.'
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

    # Reboot required - register ClawFactory-Resume scheduled task, save
    # checkpoint, restart. v1.0.27: was an HKLM RunOnce inline write; the
    # helper now registers a SYSTEM-context AtStartup task that fires
    # regardless of interactive logon.
    $scriptPath = Join-Path $PSScriptRoot 'setup.ps1'
    Register-ResumeScheduledTask -ExePath $SourceExe -ScriptPath $scriptPath
    Write-Log INFO 'Reboot required. ClawFactory-Resume scheduled task is registered.'
    # v1.0.32: Persist the resume flag here. Invoke-WslInstallWithRestart calls
    # Save-ResumeFlag before reboot; this Step-EnsureWsl reboot path was missing
    # the call, so after the SYSTEM-context Resume task fired post-reboot it
    # aborted with "resume flag is missing or unreadable" (cfv-131, v1.0.31
    # Azure validation). Same Save-ResumeFlag helper used by the other site, so
    # the JSON shape (provider/installDir/sourceExe/credentialTarget/timestamp)
    # matches what the resume branch expects at the secondary 'provider' check.
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $credTarget = if ($ThisProvider.CredentialTarget) { $ThisProvider.CredentialTarget } else { '' }
    Save-ResumeFlag -Provider $Provider -InstallDir $PSScriptRoot -SourceExe $SourceExe -CredentialTarget $credTarget
    if (-not (Test-Path $ResumeFlagFile)) {
        Write-Log ERROR "Failed to write resume flag at $ResumeFlagFile -- aborting before reboot."
        exit 1
    }
    Write-Log INFO "Resume flag written: $ResumeFlagFile"
    Save-Checkpoint 'EnsureWsl'
    if (-not (Test-IsSilent)) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "WSL2 requires a restart to complete setup.`nClawFactory will continue automatically after restart.`nClick OK to restart now.",
            'Restart Required',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } else {
        Write-Log INFO 'Silent mode: skipping restart-required dialog; rebooting now.'
    }
    # v1.0.12: same as Initiate-Restart - pre-reboot is not "done"; the
    # resume run will emit the real marker.
    $script:RebootPending = $true
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
        # v1.0.33: record which branch fired so the uninstaller can surgically
        # reverse our edit. Written to ProgramData\ClawFactory\wslconfig-state.txt
        # at the bottom of this try block.
        $wslConfigAction = 'unknown'

        if (-not (Test-Path -LiteralPath $WslConfigPath)) {
            # Branch 1: file missing - create it.
            $content = "[wsl2]`r`nvmIdleTimeout=-1`r`n$banner`r`n"
            [System.IO.File]::WriteAllText($WslConfigPath, $content, $utf8NoBom)
            Write-Log INFO "Created .wslconfig at $WslConfigPath"
            $needsShutdown = $true
            $wslConfigAction = 'created'
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
                $wslConfigAction = 'appended-section'
            } elseif (-not $vmIdleMatch.Success) {
                # Branch 3: [wsl2] exists, no vmIdleTimeout key - inject it
                # immediately after the [wsl2] header (only first match).
                $patched = [regex]::Replace($existing, '(?im)^(\s*\[wsl2\]\s*)$', "`$1`r`nvmIdleTimeout=-1", 1)
                [System.IO.File]::WriteAllText($WslConfigPath, $patched, $utf8NoBom)
                Write-Log INFO 'Added vmIdleTimeout=-1 to existing [wsl2] section'
                $needsShutdown = $true
                $wslConfigAction = 'added-key'
            } else {
                $currentValue = $vmIdleMatch.Groups[1].Value.Trim()
                if ($currentValue -eq '-1') {
                    # Branch 4: already correct - no-op.
                    Write-Log INFO '.wslconfig already has vmIdleTimeout=-1; no change needed'
                    $needsShutdown = $false
                    $wslConfigAction = 'unchanged'
                } else {
                    # Branch 5: different value already set. Visible install:
                    # WARN + MessageBox + proceed (user has an opinion; respect
                    # it but tell them). Silent install or non-interactive
                    # session: hard-fail through Invoke-WithRollback. Shipping
                    # a broken-on-idle gateway silently is worse than aborting.
                    Write-Log WARN ".wslconfig has vmIdleTimeout=$currentValue (recommended: -1). File NOT modified. User must edit $WslConfigPath manually and reboot for gateway stability."
                    # v1.0.12: use Test-IsSilent (covers both /SILENT and
                    # non-interactive contexts) instead of bare UserInteractive.
                    $shownDialog = $false
                    if (-not (Test-IsSilent)) {
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
                    $wslConfigAction = 'conflict'
                }
            }
        }

        # v1.0.33: persist the action so the uninstaller knows what to reverse.
        # Lives in ProgramData (uninstaller reads before nuking the dir).
        try {
            if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
            Set-Content -LiteralPath (Join-Path $LogDir 'wslconfig-state.txt') `
                -Value $wslConfigAction -Encoding UTF8 -NoNewline
        } catch {
            Write-Log WARN "Could not write wslconfig-state.txt: $($_.Exception.Message)"
        }

        if ($needsShutdown) {
            # Need a wsl --shutdown to make .wslconfig take effect immediately.
            # Only safe if Ubuntu is the only running distro - otherwise the
            # user has work in flight in another distro and we must ask first.
            # v1.0.29: Invoke-WslExe (CreateNoWindow=$true) prevents a visible console flash.
            $rRunning = Invoke-WslExe -Arguments @('--list', '--running', '--quiet')
            $running = $rRunning.StdOut
            $runningDistros = @()
            if ($running) {
                $runningDistros = @(($running -split "`n") |
                    ForEach-Object { ($_ -replace "`0", '').Trim() } |
                    Where-Object { $_ -ne '' })
            }
            $otherDistros = @($runningDistros | Where-Object { $_ -ne $WslDistro })

            $proceedShutdown = $true
            if ($otherDistros.Count -gt 0) {
                if (Test-IsSilent) {
                    Write-Log INFO "Silent mode: skipping wsl --shutdown to avoid disturbing other distros: $($otherDistros -join ', ')"
                    $proceedShutdown = $false
                }
            }
            if ($otherDistros.Count -gt 0 -and $proceedShutdown) {
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
                # v1.0.12: Process.Start - see Invoke-WslExe rationale.
                $null = Invoke-WslExe -Arguments @('--shutdown')
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

function Assert-WslAutomountDisabled {
    # v1.1 (Phase 1 Task 1.0): fail-loud readback verification for automount.
    # The product's core security claim -- "the Windows filesystem is invisible
    # to the agent" -- depends entirely on `[automount] enabled=false` in
    # /etc/wsl.conf. Before this, the installer WROTE the setting and checkpointed
    # but never READ IT BACK, so post-install drift (or a botched write) flipping
    # automount to true would go completely undetected. That is exactly the
    # silent-fake-success failure this project keeps producing. This helper reads
    # the file back and THROWS -- non-zero exit, clear error, no checkpoint -- if
    # automount is not verifiably disabled.
    param([string]$Context = 'readback')
    $check = @'
set -e
if [ ! -f /etc/wsl.conf ]; then echo "MISSING /etc/wsl.conf"; exit 3; fi
# Section-aware (v1.0.47): verify [automount] SPECIFICALLY has enabled=false. A
# bare grep for 'enabled=false' would now be satisfied by the [interop] block
# even if automount drifted to true, silently weakening the P0 file-isolation
# guard -- so scope the check to the [automount] section only.
if awk 'BEGIN{f=0} /^\[/{s=$0} s ~ /^\[automount\]/ && /^[ \t]*enabled[ \t]*=[ \t]*false/{f=1} END{exit f?0:1}' /etc/wsl.conf; then
    echo "OK: automount disabled"; exit 0
fi
echo "BAD: /etc/wsl.conf does not show [automount] enabled=false. Current [automount]/[interop]/enabled lines:"
grep -nEi 'automount|interop|enabled' /etc/wsl.conf || echo "(no automount/enabled lines at all)"
exit 1
'@
    $rc = Invoke-WslBash -Script $check -User 'root'
    if ($rc -ne 0) {
        Write-Log ERROR "AUTOMOUNT VERIFICATION FAILED ($Context): /etc/wsl.conf does not verifiably show 'enabled=false' (rc=$rc). The agent runtime may be able to read the Windows filesystem via /mnt/c. This is a P0 file-isolation failure. Refusing to continue; no checkpoint written."
        throw "wsl.conf automount verification failed ($Context): expected '[automount] enabled=false' in /etc/wsl.conf (rc=$rc)."
    }
    Write-Log INFO "Verified: /etc/wsl.conf shows automount disabled ($Context)."
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

[interop]
enabled=false
appendWindowsPath=false

[boot]
systemd=true

[network]
generateResolvConf=true
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($wslConf))
    # v1.0.29: route through Invoke-WslExe (CreateNoWindow=$true) to suppress visible console flash.
    $rWslConf = Invoke-WslExe -Arguments @('-d', $WslDistro, '-u', 'root', '--', 'bash', '-c', "echo '$encoded' | base64 -d > /etc/wsl.conf && chmod 644 /etc/wsl.conf")
    if ($rWslConf.ExitCode -ne 0) { throw 'Failed to write /etc/wsl.conf' }
    # v1.1 (Phase 1 Task 1.0): verify the write actually landed before checkpointing.
    Assert-WslAutomountDisabled -Context 'ConfigureWslConf-write'
    Save-Checkpoint 'WslConf'
}

function Step-RestartWsl {
    Write-Log INFO 'Step 4: Restarting WSL.'
    # v1.0.14: route through Invoke-WslExe for consistency with the rest
    # of the script. These calls don't parse output but the bare `wsl ...`
    # form sits in the same hazard class as the v1.0.7 fix targeted.
    $rShutdown = Invoke-WslExe -Arguments @('--shutdown')
    Write-Log INFO "wsl --shutdown exit=$($rShutdown.ExitCode)"
    Start-Sleep -Seconds 3
    # -u root explicitly: avoids getpwnam errors if wsl.conf default user is stale/missing.
    $rBoot = Invoke-WslExe -Arguments @('-d', $WslDistro, '-u', 'root', '--', 'true')
    Write-Log INFO "wsl -d $WslDistro boot exit=$($rBoot.ExitCode)"
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
    # v1.0.29: Invoke-WslExe (CreateNoWindow=$true) prevents visible console flashes on all three calls.
    $null = Invoke-WslExe -Arguments @('--shutdown')
    Start-Sleep -Seconds 3
    $rDefaultBoot = Invoke-WslExe -Arguments @('-d', $WslDistro, '-u', $WslUser, '--', 'true')
    if ($rDefaultBoot.ExitCode -ne 0) {
        # Fall back to root restart if clawuser-default somehow still fails.
        $null = Invoke-WslExe -Arguments @('-d', $WslDistro, '-u', 'root', '--', 'true')
        Write-Log WARN 'Default-user restart fell back to root. Check /etc/wsl.conf.'
    }
    # v1.1 (Phase 1 Task 1.0): after the FINAL WSL restart, confirm automount is
    # still disabled. This is the authoritative post-restart readback: it catches
    # both a botched initial write and any later step clobbering [automount].
    # Fails loud (throws, no checkpoint) if the isolation guarantee is not intact.
    Assert-WslAutomountDisabled -Context 'post-restart'
    Save-Checkpoint 'DefaultUser'
}

function Step-InstallBaseDeps {
    # Was Step-InstallDocker. DOCKER REMOVED (SECFIX_CLOSE_DOORS_2026-07-14,
    # decision A): nothing ever ran a container. The agent is a clawuser PROCESS
    # (Phase 0 + 2.5 VERIFIED, zero containers even during agent work), OpenClaw's
    # own sandbox is off, the kill switch's container-stop matched nothing, and no
    # healthcheck used it. It cost a large apt install + a rootless daemon while
    # protecting nothing -- and the safety rules falsely claimed a Docker sandbox.
    #
    # TRAP (why this is NOT a plain deletion): the old Docker step also installed
    # packages the rest of the product depends on --
    #   * nftables          -> the egress firewall backend (/usr/sbin/nft). NOT
    #                          installed anywhere else (Step-PreInstallOpenClawDeps
    #                          installs iptables only). Removing it silently breaks
    #                          the firewall on a fresh install.
    #   * dbus-user-session -> systemd --user, which runs the gateway.
    #   * loginctl enable-linger clawuser -> gateway survives between sessions.
    # Those are preserved here. Dropped: uidmap / fuse-overlayfs / slirp4netns
    # (rootless-Docker only), the docker apt repo + gpg key, docker-ce et al,
    # dockerd-rootless-setuptool, and the DOCKER_HOST export in .bashrc.
    Write-Log INFO 'Step 6: Installing base Linux dependencies (nftables + dbus-user-session; Docker removed).'
    $script = @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
timeout 300 apt-get update -y
timeout 300 apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg dbus-user-session \
    iptables nftables
# Linger so clawuser's systemd --user manager (and the gateway) survives between
# sessions. Previously a side-effect of the Docker step; kept explicitly.
# v1.0.42 (L13, A2): verify the readback instead of a silent `|| true`. Linger is
# what makes `systemctl --user` work in the no-login install context; a silent
# failure here is what let the gateway port-move restart be a no-op. The
# authoritative fail-loud assert is in gateway-wait.sh (assert_user_manager_ready),
# re-run right before that restart; this is the early best-effort with a loud WARN.
loginctl enable-linger clawuser || true
if [ "$(loginctl show-user clawuser --property=Linger --value 2>/dev/null || echo no)" = "yes" ]; then
    echo "[linger] enabled for clawuser"
else
    echo "[linger] WARN: enable-linger did not stick for clawuser (re-asserted before the gateway port-move)" >&2
fi
'@
    $rc = Invoke-WslBash -Script $script -User 'root'
    if ($rc -ne 0) { throw 'Base dependency install failed' }
    Save-Checkpoint 'BaseDeps'
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
        # (Docker Hub hosts removed with Docker itself -- SECFIX_CLOSE_DOORS decision A.
        #  Nothing pulls images any more, so the allowlist no longer opens egress to them.)
        # v1.0.3: Ubuntu apt repos. apt-as-root currently bypasses the firewall
        # (clawuser-scoped), but listed here as defense-in-depth in case install.sh
        # or a future skill drops privileges before running apt.
        'archive.ubuntu.com','security.ubuntu.com','ports.ubuntu.com','esm.ubuntu.com','ppa.launchpad.net'
        # v1 Guard 2: the five Google API hosts that used to sit here are GONE.
        # They were added in v1.0.33 for the Gmail PubSub watcher, and
        # gmail.googleapis.com is the host that serves users.messages.send. On a
        # uid-1000 allowlist that is a live outbound mail route for the agent:
        # recon confirmed clawuser reaching /gmail/v1/users/me/profile and
        # getting a 401, i.e. the request arrived at Google and only the absent
        # credential stopped it.
        #
        # Nothing is lost. The watcher cannot run here at all -- it needs the
        # gcloud CLI, the `gog` binary and a Tailscale Funnel endpoint, none of
        # which ClawFactory ships. Gemini as a MODEL provider uses
        # generativelanguage.googleapis.com, which is added per-provider from
        # $ThisProvider.AllowlistHosts and is unaffected.
        #
        # THE INVARIANT: no send path may ever run as uid 1000. If Google mail
        # is ever wanted, it goes behind the root broker, which is exempt from
        # this chain by `meta skuid != clawuser return`. Putting a send host
        # back on this list is forbidden, not merely discouraged.
    )
    $providerHosts = @($ThisProvider.AllowlistHosts)
    $allHosts      = ($baseHosts + $providerHosts) | Where-Object { $_ } | Sort-Object -Unique
    $hostList      = ($allHosts -join ' ')
    Write-Log INFO "Allowlist hosts: $hostList"

    # Defect 1 (DNS exfiltration): the resolver-allowlist helper is shipped as a
    # base64 blob so its regex/awk survive the PowerShell->wsl->bash transport
    # without backtick-escaping. It prints the IPv4 resolver(s) clawuser may
    # reach on port 53 (the WSL NAT forwarder from /etc/resolv.conf), with a
    # persisted fallback for the boot race. See in-file header for rationale.
    $dnsHelper = @'
#!/bin/bash
# ClawFactory Defect-1 DNS restriction: print the IPv4 resolver(s) clawuser is
# permitted to reach on port 53, one per line.
#   Primary source : /etc/resolv.conf nameservers (WSL writes the NAT DNS
#                     forwarder here via [network] generateResolvConf=true).
#   Fallback       : last-known-good /etc/clawfactory/dns-resolvers.txt, used
#                     only if resolv.conf has no nameserver yet (boot race).
# IPv6 nameservers are intentionally excluded: the DNS allow rules are IPv4
# (ip daddr), so any port-53 packet to an IPv6 resolver hits the drop rule.
ns="$(awk '/^[[:space:]]*nameserver/ { print $2 }' /etc/resolv.conf 2>/dev/null | grep -Eo '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | sort -u)"
if [ -z "$ns" ] && [ -f /etc/clawfactory/dns-resolvers.txt ]; then
    ns="$(grep -Eo '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' /etc/clawfactory/dns-resolvers.txt 2>/dev/null | sort -u)"
fi
printf '%s\n' $ns | sed '/^$/d'
'@
    $dnsHelperB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($dnsHelper.Replace("`r`n", "`n")))

    $script = @"
set -euo pipefail

# --- Install the DNS-resolver allowlist helper (Defect 1) ------------------
mkdir -p /etc/clawfactory
echo '$dnsHelperB64' | base64 -d > /usr/local/sbin/clawfactory-dns-resolvers.sh
chmod 755 /usr/local/sbin/clawfactory-dns-resolvers.sh
CF_RESOLVERS=`$(/usr/local/sbin/clawfactory-dns-resolvers.sh)
printf '%s\n' `$CF_RESOLVERS | sed '/^`$/d' > /etc/clawfactory/dns-resolvers.txt
echo `"[clawfactory-fw] DNS resolvers restricted to: `$(printf '%s ' `$CF_RESOLVERS)`"

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
    set dns_resolvers {
        type ipv4_addr
    }
    # v1 Guard 3: destinations the USER has allowed the agent to fetch from.
    # Separate from allowed_ipv4 on purpose. The provider set is refreshed
    # additively by hostname and its elements carry a timeout, so nothing in it
    # is ever deliberately removed; a user destination placed there could not be
    # revoked. This set is flushed and rebuilt from the root-owned egress policy
    # by clawfactory-read-fetch.sh, so removing a site in Studio removes its
    # route. Empty on a fresh install, which is the denied state.
    set read_fetch_ipv4 {
        type ipv4_addr
    }
    chain output {
        type filter hook output priority 0; policy accept;
        meta skuid != clawuser return
        # Blocker 1: the REAL OpenClaw gateway listens on a PRIVATE loopback port
        # (8788) and is reachable only through the ClawFactory gating proxy, which
        # owns 8787 and runs as ROOT. Drop clawuser's direct path to the private
        # port so the agent cannot skip the proxy's SOUL + spend gate by talking
        # to the gateway itself. Both loopback families -- the gateway binds
        # 127.0.0.1 AND [::1]. Must precede the blanket `oifname lo accept`.
        # The proxy is root, so `meta skuid != clawuser return` exempts it.
        ip daddr 127.0.0.1 tcp dport 8788 drop
        ip6 daddr ::1 tcp dport 8788 drop
        oifname `"lo`" accept
        # Defect 1: port 53 is restricted to the WSL resolver(s) only (populated
        # into @dns_resolvers from /etc/resolv.conf by the apply step). An agent
        # can no longer pick an arbitrary resolver (dig @1.1.1.1) to smuggle data
        # out inside a DNS lookup.
        ip daddr @dns_resolvers udp dport 53 accept
        ip daddr @dns_resolvers tcp dport 53 accept
        ct state established,related accept
        ip daddr @allowed_ipv4 tcp dport 443 accept
        # v1 Guard 3. Port-scoped to 443 for the same reason the provider accept
        # is: a widened port here would make every co-hosted address reachable on
        # whatever was opened. The chain-shape tripwire checks both accepts.
        ip daddr @read_fetch_ipv4 tcp dport 443 accept
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
# nft -f exits non-zero with "Unable to initialize Netlink socket". We
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
    # Defect 1: populate the DNS resolver allowlist (port 53 -> WSL resolver only).
    for ip in `$CF_RESOLVERS; do
        /usr/sbin/nft add element inet clawfactory dns_resolvers `"{ `$ip }`" 2>/dev/null || true
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
    # Defect 1: port 53 restricted to the WSL resolver(s) only.
    for ip in `$CF_RESOLVERS; do
        `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -d `"`$ip`" -p udp --dport 53 -j ACCEPT
        `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -d `"`$ip`" -p tcp --dport 53 -j ACCEPT
    done
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
# Defect 1: refresh the DNS resolver allowlist from the (boot-regenerated)
# /etc/resolv.conf, falling back to the last-known-good persisted list. Port 53
# is only ever opened to these resolver(s), never to an arbitrary one.
CF_RESOLVERS=`"`$(/usr/local/sbin/clawfactory-dns-resolvers.sh 2>/dev/null)`"
printf '%s\n' `$CF_RESOLVERS | sed '/^`$/d' > /etc/clawfactory/dns-resolvers.txt
if [ `"`$BACKEND`" = `"iptables-legacy`" ]; then
    IPT=`"`$(command -v iptables-legacy || true)`"
    [ -n `"`$IPT`" ] || { echo `"[clawfactory-fw] iptables-legacy missing`" >&2; exit 1; }
    `"`$IPT`" -F OUTPUT
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -o lo -j ACCEPT
    for ip in `$CF_RESOLVERS; do
        `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -d `"`$ip`" -p udp --dport 53 -j ACCEPT
        `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -d `"`$ip`" -p tcp --dport 53 -j ACCEPT
    done
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    while IFS= read -r ip; do
        [ -n `"`$ip`" ] || continue
        `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -d `"`$ip`" -p tcp --dport 443 -j ACCEPT
    done < /etc/clawfactory/allowed-ips.txt
    # v1 Guard 3: the user's read-fetch destinations, same 443 scoping as the
    # provider route. A missing file means an empty list, which is the denied
    # state, so a lost file fails closed rather than open.
    if [ -f /etc/clawfactory/read-fetch-ips.txt ]; then
        while IFS= read -r ip; do
            [ -n `"`$ip`" ] || continue
            `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -d `"`$ip`" -p tcp --dport 443 -j ACCEPT
        done < /etc/clawfactory/read-fetch-ips.txt
    fi
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -d 127.0.0.1 -p tcp --dport 11434 -j ACCEPT
    `"`$IPT`" -A OUTPUT -m owner --uid-owner clawuser -j DROP
else
    /usr/sbin/nft -f /etc/nftables.conf
    while IFS= read -r ip; do
        [ -n `"`$ip`" ] || continue
        /usr/sbin/nft add element inet clawfactory allowed_ipv4 `"{ `$ip }`" 2>/dev/null || true
    done < /etc/clawfactory/allowed-ips.txt
    for ip in `$CF_RESOLVERS; do
        /usr/sbin/nft add element inet clawfactory dns_resolvers `"{ `$ip }`" 2>/dev/null || true
    done
    # v1 Guard 3: rebuild the read-fetch set. `nft -f` above flushed the whole
    # ruleset, so this set starts empty on every boot and only the persisted
    # list re-opens anything. No file means nothing is re-opened.
    if [ -f /etc/clawfactory/read-fetch-ips.txt ]; then
        while IFS= read -r ip; do
            [ -n `"`$ip`" ] || continue
            /usr/sbin/nft add element inet clawfactory read_fetch_ipv4 `"{ `$ip }`" 2>/dev/null || true
        done < /etc/clawfactory/read-fetch-ips.txt
    fi
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
    # throughout - this assertion fails the install if a future edit
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
        Write-Log ERROR "Egress firewall setup returned exit $rc. Firewall is NOT active. Check the install log at C:\ProgramData\ClawFactory\install.log; re-run setup.ps1 -Resume after diagnosing."
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
    # v1.0.12: timeout 120 on the install.sh download (small file, but
    # ollama.com has been flaky); timeout 1800 on the model pull (4.7 GB,
    # 30 min ceiling). Without these the entire installer can wedge here
    # on slow networks with no error visible to the validation harness.
    $script = @'
set -euo pipefail
if ! command -v ollama >/dev/null 2>&1; then
    timeout 120 curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh
    # Basic integrity check: must be a shell script, not HTML
    head -c 2 /tmp/ollama-install.sh | grep -q '#!' || { echo "ollama install.sh is not a shell script"; exit 1; }
    bash /tmp/ollama-install.sh
    rm -f /tmp/ollama-install.sh
fi
systemctl enable ollama 2>/dev/null || true
systemctl restart ollama 2>/dev/null || true
sleep 3
su - clawuser -c 'timeout 1800 ollama pull llama3.1:8b || echo "[WARN] ollama pull timed out or failed - model will need to be pulled manually"'
'@
    $rc = Invoke-WslBash -Script $script -User 'root'
    if ($rc -ne 0) { Write-Log WARN 'Ollama install returned non-zero; you may need to run `wsl -u clawuser -- ollama pull llama3.1:8b` manually.' }
    Save-Checkpoint 'Ollama'
}

function Step-InstallOpenClaw {
    # openclaw-install.sh is BUNDLED -- no network call for this step.
    # Hash is computed at install time and written to checkpoint.json under
    # "installShHash" for audit. No pinned hash -- upstream install.sh updates
    # are accepted (the file is reviewed and re-bundled out-of-band).
    #
    # To upgrade OpenClaw:
    #   1. Download new install.sh from openclaw.ai/install.sh
    #   2. Review diff against current bundled version
    #   3. Run security sub-agent review
    #   4. Copy to resources\openclaw-install.sh in both repos
    #   5. Bump version, rebuild, validate on Azure
    #   DO NOT restore the URL-download path -- it tracks latest
    #   and will drift without warning.
    Write-Log INFO 'Step 8 [R2]: Installing OpenClaw from bundled install.sh (hash logged at install time).'
    if (-not $AcknowledgedOpenClawUrl) {
        throw 'OpenClaw install acknowledgement missing. Re-run via the wizard.'
    }
    $bundledScript = Join-Path $PSScriptRoot 'resources\openclaw-install.sh'
    if (-not (Test-Path -LiteralPath $bundledScript)) {
        throw 'openclaw-install.sh not found in resources. Installer may be corrupted.'
    }
    $installShHash = (Get-FileHash -LiteralPath $bundledScript -Algorithm SHA256).Hash.ToLower()
    Write-Host "  [INFO] install.sh SHA-256: $installShHash (computed at install time)"
    $state = [ordered]@{ completedSteps = @() }
    if (Test-Path $CheckpointFile) {
        $json = Get-Content -LiteralPath $CheckpointFile -Raw | ConvertFrom-Json
        $state.completedSteps = @($json.completedSteps)
    }
    $state.installShHash = $installShHash
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $CheckpointFile -Encoding UTF8
    Write-Log INFO "Bundled openclaw-install.sh hash logged: $installShHash"

    # Stream the bundled script into WSL /tmp via stdin. Cannot use Invoke-WslBash
    # for the file content because wsl.exe argv has a Windows ~32K limit and the
    # install.sh is ~93K (base64 ~125K). Stdin pipe sidesteps argv entirely.
    $bytes = [System.IO.File]::ReadAllBytes($bundledScript)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'wsl.exe'
    $psi.Arguments              = "-d $WslDistro -u root --cd / -- bash -c `"cat > /tmp/openclaw-install.sh`""
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $proc.StandardInput.Close()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) {
        throw "Failed to stream openclaw-install.sh into WSL (exit $($proc.ExitCode)). stderr: $stderr"
    }

    $fetch = @"
set -euo pipefail
# install.sh runs ``sudo`` internally but falls back to direct exec when already root.
# Set HOME/USER/LOGNAME so per-user artifacts (shim at \$HOME/.local/bin, config
# under \$HOME/.openclaw) land in clawuser's home, not /root.
#
# Wrap bash with ``timeout`` to fail fast if openclaw-onboard (invoked from
# inside install.sh) hangs waiting on interactive input. 15 minutes is enough
# for any non-interactive run; longer than that means we're stuck. SIGTERM
# first (graceful), then SIGKILL after 30s (--kill-after) if the child
# trapped SIGTERM. timeout's exit code 124 = timed out.
set +e
NO_ONBOARD=1 OPENCLAW_VERSION=$OpenClawNpmVersion HOME=/home/clawuser USER=clawuser LOGNAME=clawuser timeout --foreground --kill-after=30 900 bash /tmp/openclaw-install.sh -- --no-onboard > >(tee /tmp/openclaw-install.log) 2>&1
INSTALL_RC=`$?
set -e
rm -f /tmp/openclaw-install.sh
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
    # be updated. The install.sh SHA-256 is logged to checkpoint.json on every
    # install for audit (no pin), so upstream changes are visible after the fact.
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
# OWNERSHIP FIX (v1.0.39). This block runs as ROOT, so the mkdir -p above created
# .config, .config/systemd and .config/systemd/user OWNED BY ROOT. Later
# `openclaw gateway install` runs as CLAWUSER (deliberately, so the unit lands in
# /home/clawuser not /root) and must WRITE the unit into .../systemd/user -- which
# fails EACCES if root owns that chain. The leaf-only `chown -R ...service.d` in
# sub-block (h) descends INTO the leaf; it never climbs to these parents. Chown the
# whole chain to clawuser now: non-recursive per level, so it touches only these
# four directories -- it CORRECTS them if root owns them (the v1.0.38 bug) and is a
# harmless no-op if clawuser already owns them (Docker-era boxes, re-runs).
# Docker's rootless setuptool used to create this chain as clawuser first, which is
# why the bug stayed latent for 38 versions until Docker's removal
# (SECFIX_CLOSE_DOORS). Do NOT reintroduce Docker -- make ownership explicit and
# assert it (see the guard at the top of $gatewayInstall).
chown clawuser:clawuser \
    /home/clawuser/.config \
    /home/clawuser/.config/systemd \
    /home/clawuser/.config/systemd/user \
    "$OVERRIDE_DIR"
cat > "$OVERRIDE_DIR/clawfactory-tunables.conf" <<'EOF'
[Service]
TimeoutStartSec=infinity

[Unit]
StartLimitBurst=0
StartLimitIntervalSec=0
EOF

# --- c. Per-agent auth-profiles ------------------------------------------
# The gateway looks for API keys at ~/.openclaw/agents/<agent>/agent/auth-profiles.json,
# NOT the global ~/.openclaw/auth-profiles.json. Copy global -> per-agent for
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
# v1.0.42 (L13, A2): verify the readback instead of a silent `|| true` (the
# fail-loud assert before the gateway port-move is in gateway-wait.sh).
loginctl enable-linger clawuser || true
if [ "$(loginctl show-user clawuser --property=Linger --value 2>/dev/null || echo no)" = "yes" ]; then
    echo "[linger] enabled for clawuser"
else
    echo "[linger] WARN: enable-linger did not stick for clawuser (re-asserted before the gateway port-move)" >&2
fi

# --- e. Resolve LLM-provider hostnames into the egress firewall allowlist
# (this depends on Step-EgressFirewall having run already so the table or
# the iptables-legacy chain exists). Both backends get the same auxiliary
# host list (auth endpoints, registry mirrors, etc.) so OpenClaw's first-run
# auth flows succeed regardless of which firewall is active.
# v1 Guard 2: generativelanguage.googleapis.com and aiplatform.googleapis.com
# were REMOVED from this list. They resolve to the same Google front-end IPs as
# gmail.googleapis.com (measured: both are 172.217.112.4 through 172.217.119.4),
# so pre-allowlisting them on EVERY install silently re-opened the agent's route
# to users.messages.send. Proved by execution: after the five Gmail hostnames
# were taken off the base list and their IPs deleted, clawuser was blocked; one
# run of this refresh script put the same IPs straight back and clawuser reached
# the Gmail API again.
#
# Nothing is lost for non-Google installs. A customer who selects or switches to
# Gemini still gets generativelanguage.googleapis.com from the per-provider
# allowlist at install, and from PROVIDER_HOST in switch-provider.ps1 on switch.
#
# RESIDUAL, STATED PLAINLY: for a Gemini customer that per-provider entry
# re-allowlists the shared IPs, so the Gmail API becomes reachable again.
# IP-based allowlisting cannot separate two hostnames served by one front-end.
# Closing that needs a root-owned outbound injector so clawuser needs no Google
# IP at all. Do not "fix" it by dropping the shared IPs -- that breaks Gemini.
AUX_HOSTS="api.anthropic.com console.anthropic.com api.openai.com auth.openai.com api.x.ai \
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
# v1 Guard 2: generativelanguage.googleapis.com and aiplatform.googleapis.com
# were REMOVED from this list. They resolve to the same Google front-end IPs as
# gmail.googleapis.com (measured: both are 172.217.112.4 through 172.217.119.4),
# so pre-allowlisting them on EVERY install silently re-opened the agent's route
# to users.messages.send. Proved by execution: after the five Gmail hostnames
# were taken off the base list and their IPs deleted, clawuser was blocked; one
# run of this refresh script put the same IPs straight back and clawuser reached
# the Gmail API again.
#
# Nothing is lost for non-Google installs. A customer who selects or switches to
# Gemini still gets generativelanguage.googleapis.com from the per-provider
# allowlist at install, and from PROVIDER_HOST in switch-provider.ps1 on switch.
#
# RESIDUAL, STATED PLAINLY: for a Gemini customer that per-provider entry
# re-allowlists the shared IPs, so the Gmail API becomes reachable again.
# IP-based allowlisting cannot separate two hostnames served by one front-end.
# Closing that needs a root-owned outbound injector so clawuser needs no Google
# IP at all. Do not "fix" it by dropping the shared IPs -- that breaks Gemini.
AUX_HOSTS="api.anthropic.com console.anthropic.com api.openai.com auth.openai.com api.x.ai \
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

# v1 Guard 3: re-derive the user's read-fetch set from the root-owned policy on
# the same five-hourly cycle, so a destination whose addresses have moved keeps
# working and a destination removed in Studio actually loses its route on a
# machine that has been up for days. The resolver flushes before it adds, so a
# failure here denies read-fetch rather than leaving a stale hole open.
if [ -x /usr/local/sbin/clawfactory-read-fetch.sh ]; then
    /usr/local/sbin/clawfactory-read-fetch.sh \
        || echo "[clawfactory-fw] read-fetch refresh FAILED; every read-fetch destination is denied until it succeeds" >&2
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
openclaw config set gateway.port 8787 --json >/dev/null
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
set -o pipefail

# --- GUARD (v1.0.39, Task 2): the systemd user-unit chain MUST be clawuser-owned.
# We run as clawuser here; `openclaw gateway install` will write
# ~/.config/systemd/user/openclaw-gateway.service. If root owns ANY level of that
# chain, the write fails EACCES and the unit is never created (the v1.0.38 bug:
# root's mkdir -p in sub-block (b) created the chain, the leaf-only chown never
# climbed to the parents). The absence of exactly this assertion is what let a
# 38-version-old bug hide behind Docker's rootless setuptool. Fail loud, named.
UNIT_DIR=/home/clawuser/.config/systemd/user
for d in /home/clawuser/.config /home/clawuser/.config/systemd "$UNIT_DIR"; do
    owner="$(stat -c '%U' "$d" 2>/dev/null || echo MISSING)"
    if [ "$owner" != "clawuser" ]; then
        echo "[gateway-install] FATAL: $d is owned by '$owner', not clawuser -- 'openclaw gateway install' runs as clawuser and cannot write the gateway unit through a directory it does not own (EACCES). This is the gateway-unit ownership bug; the fix is in Step-PreinstallGatewayRuntime sub-block (b)." >&2
        ls -ld /home/clawuser/.config /home/clawuser/.config/systemd "$UNIT_DIR" 2>/dev/null >&2 || true
        exit 90
    fi
done
echo "[gateway-install] ownership guard OK: .config/systemd/user chain is clawuser-owned"

echo "[gateway-install] openclaw gateway install --force --port 8787"
set +e
install_out="$(openclaw gateway install --force --port 8787 2>&1)"
rc=$?
set -e
printf '%s\n' "$install_out"

# --- FAIL LOUD (v1.0.39, Task 3). The success criterion for this command is that
# it CREATED the unit file. The prior WARN-and-continue swallowed a non-zero rc and
# marched on to daemon-reload/enable/restart against a non-existent unit, so a
# precise EACCES surfaced 120s later as the misleading "Gateway did not respond".
UNIT="$UNIT_DIR/openclaw-gateway.service"
if [ ! -f "$UNIT" ]; then
    echo "[gateway-install] FATAL: 'openclaw gateway install' exited $rc and did NOT create $UNIT." >&2
    echo "[gateway-install] install output was:" >&2
    printf '%s\n' "$install_out" >&2
    if [ "$rc" -ne 0 ]; then exit "$rc"; else exit 1; fi
fi
# The unit exists. A non-zero rc HERE is the documented transient case (unit
# written, service auto-start hiccup); the downstream PowerShell /status poll is the
# source of truth for that, so do NOT abort on rc alone once the unit is present.
if [ "$rc" -ne 0 ]; then
    echo "[gateway-install] note: install exited $rc but $UNIT exists; deferring health to the /status poll" >&2
fi

# daemon-reload / enable / restart -- BELT-AND-SUSPENDERS (openclaw #65184). The
# gateway is ALREADY started by `openclaw gateway install --force` itself; these
# three are best-effort and the PowerShell /status poll below is the health
# authority. They legitimately fail in this `wsl -u clawuser` NON-LOGIN context
# (no user bus), so v1.0.38 ran them under `|| true`. v1.0.39 wrongly removed that
# and, under `set -e`/`pipefail`, a benign non-zero here aborted the install AFTER
# the unit was created (PROVEN on cfv-0716w -- unit present, chain clawuser-owned,
# guard OK, yet exit 1). v1.0.40 restores tolerance two ways: (1) give them a real
# user bus via XDG_RUNTIME_DIR (the pattern the rest of the tree uses) so they
# actually succeed, AND (2) keep `|| true` as the safety net regardless -- because
# whether XDG is the true cause is unconfirmed and the /status poll decides health
# either way.
#
# v1.0.41 (false-failure fix): these three lines previously ended `2>&1 | tee -a
# "$LOG"` with $LOG=/tmp/openclaw-install.log. That log is created ROOT-owned by the
# npm-install step (its `> >(tee /tmp/openclaw-install.log)` runs as root); this
# block runs as clawuser, so under `set -o pipefail` the tee failed "Permission
# denied" and the block surfaced exit 1 EVEN THOUGH the gateway was up (unit
# created, service active) -- the PowerShell throw below then wrongly reported "did
# not create the unit" (cfv-0716q, verbatim). The tee was pure redundancy:
# Invoke-WslBash already captures every stdout/stderr line into
# C:\ProgramData\ClawFactory\install.log. Dropped it; `2>&1` still merges each
# command's stderr into this block's stdout, so which (if any) systemctl call fails
# is still on record in the real install log. The /status poll is deliberately NOT
# tightened.
XDG=/run/user/$(id -u clawuser 2>/dev/null || echo 1000)
echo "[gateway-install] systemctl --user daemon-reload"
XDG_RUNTIME_DIR="$XDG" systemctl --user daemon-reload 2>&1 || true

echo "[gateway-install] systemctl --user enable openclaw-gateway.service"
XDG_RUNTIME_DIR="$XDG" systemctl --user enable openclaw-gateway.service 2>&1 || true

echo "[gateway-install] systemctl --user restart openclaw-gateway.service"
XDG_RUNTIME_DIR="$XDG" systemctl --user restart openclaw-gateway.service 2>&1 || true

# Per #65184, give the unit ~5s to fully bind before probing is-active. This loop
# is a soft, best-effort check (it exits 0 either way); the authoritative health
# gate is the PowerShell /status poll, NOT tightened here.
sleep 5
for i in 1 2 3 4 5 6; do
    state="$(systemctl --user is-active openclaw-gateway.service 2>/dev/null || true)"
    if [ "$state" = "active" ]; then
        echo "[gateway-install] Gateway service active (attempt $i)"
        exit 0
    fi
    sleep 2
done
echo "[gateway-install] note: service not 'active' within 12s; the PowerShell /status poll (120s) is authoritative" >&2
exit 0
'@
    $rcGateway = Invoke-WslBash -Script $gatewayInstall -User $WslUser
    if ($rcGateway -ne 0) {
        # The ownership guard (exit 90) is always a real, non-recoverable failure:
        # the unit could NOT have been written, so fail loud with that exact case.
        if ($rcGateway -eq 90) {
            throw "gateway install aborted: the ownership guard tripped (exit 90) -- /home/clawuser/.config/systemd/user is not clawuser-owned, so 'openclaw gateway install' (runs as clawuser) cannot write the unit (EACCES). See the FATAL ownership-guard lines in the install log at $LogFile."
        }
        # v1.0.41 (false-failure fix): a NON-90 non-zero block exit is NOT sufficient
        # to declare failure. On a clean box the gateway genuinely comes up (unit
        # created 923 B clawuser-owned, service active) yet the block could still
        # surface a benign non-zero -- historically the root-owned-log `tee` under
        # pipefail (now removed, A1), and more generally the best-effort systemctl
        # calls in a no-user-bus context. So gate on the INVARIANT (does the unit
        # file exist?), not on the noisy block exit code. If the unit is genuinely
        # missing, that is the real failure and we say so accurately. If it exists,
        # WARN and defer to the /status health poll below -- the authority -- exactly
        # as the block's internal note and v1.0.38 WARN-not-throw intended.
        $unit = '/home/clawuser/.config/systemd/user/openclaw-gateway.service'
        $rcUnit = Invoke-WslBash -Script "test -f $unit" -User $WslUser
        if ($rcUnit -ne 0) {
            throw "gateway install failed (exit=$rcGateway): 'openclaw gateway install' did not create the unit $unit (verified missing with test -f). See the [wsl:clawuser ...] lines in the install log at $LogFile for the exact error."
        }
        Write-Log WARN "gateway-install block exited $rcGateway, but the unit file $unit exists (verified with test -f). This is the known-benign non-zero block exit (best-effort systemctl in a no-user-bus context); NOT a gateway failure. Deferring the verdict to the /status health poll below, which is the authority."
    }

    # Poll gateway health via curl /status for up to ~120s (13 attempts, 10s
    # apart). The install command can return non-zero for transient reasons
    # (e.g., racing with a prior unit shutdown) while still leaving the
    # gateway healthy after restart. Trust the HTTP probe, not the exit code.
    #
    # v1.0.35: widened from 6 attempts (~60s) to 13 attempts. cfv-135 proved
    # the install runs clean end to end but the gateway's cold start on a
    # 2-vCPU VM (~67s: bound :8787 at 35.5s, fully ready ~67s after a ~5s
    # model-warmup network stall) overran the old 60s gate by ~7s. 13 attempts
    # sleep on iterations 1..12 = 12 x 10s = 120s of guaranteed wait, clearing
    # the observed 67s cold start with >= 50s of headroom.
    $healthy = $false
    for ($i = 1; $i -le 13; $i++) {
        $rcCurl = Invoke-WslBash -Script 'curl -fsS --max-time 5 http://127.0.0.1:8787/status >/dev/null 2>&1' -User $WslUser
        if ($rcCurl -eq 0) {
            Write-Log INFO "Gateway confirmed healthy via poll (attempt $i)."
            $healthy = $true
            break
        }
        if ($i -lt 13) { Start-Sleep -Seconds 10 }
    }
    if (-not $healthy) {
        # v1.0.12: capture diagnostics before throwing so the validation
        # harness (and any future incident review) can see WHY the gateway
        # didn't bind. Each Invoke-WslBash call writes its output to
        # install.log under [wsl:clawuser out]/[wsl:clawuser err] prefixes;
        # the GW-* markers below are just human-readable section headers
        # for log scanners.
        Write-Log INFO 'Collecting gateway diagnostics before failure...'
        $gwJournal = Invoke-WslBash -Script 'journalctl --user -u openclaw-gateway --no-pager --since "10 min ago" 2>&1 || echo "journalctl unavailable"' -User 'clawuser'
        $gwStatus  = Invoke-WslBash -Script 'systemctl --user status openclaw-gateway --no-pager 2>&1 || echo "systemctl unavailable"' -User 'clawuser'
        $gwPort    = Invoke-WslBash -Script 'ss -tlnp 2>&1 | grep -E "8787|LISTEN" || echo "nothing listening on 8787"' -User 'clawuser'
        $gwTmpLog  = Invoke-WslBash -Script 'ls -la /tmp/openclaw-install.log 2>&1; cat /tmp/openclaw-install.log 2>&1 || echo "log not found"' -User 'clawuser'
        Write-Log INFO "GW-JOURNAL: $gwJournal"
        Write-Log INFO "GW-STATUS:  $gwStatus"
        Write-Log INFO "GW-PORT:    $gwPort"
        Write-Log INFO "GW-TMPLOG:  $gwTmpLog"
        throw 'Gateway did not respond after 120 seconds'
    }
    Save-Checkpoint 'GatewayRuntime'
}

function Step-ConfigureOpenClaw {
    # Replaces the old Step-WriteOpenClawJson which used a fabricated CLI.
    # The real OpenClaw uses `openclaw config set <dot.path> <value>` to build
    # ~/.openclaw/openclaw.json piece by piece. Most subcommands (setup, onboard,
    # agents add, models auth login, paste-token) require an interactive TTY and
    # hang in non-interactive contexts even with --non-interactive flags.
    #
    # Note: no user-facing auto-update disable flag found in openclaw-install.sh
    # (v1.0.20 audit). install.sh sets OPENCLAW_UPDATE_IN_PROGRESS=1 before its
    # own internal openclaw subcommand calls -- that's a context signal to
    # suppress runtime self-update during the install itself, not a persistent
    # disable. Verify manually on next OpenClaw upgrade whether the runtime
    # has introduced a user-disable mechanism worth wiring in here.
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
    # Step 9a (v1.0.48): structural tool policy. Deny the `browser` tool at the
    # gateway config level so it is unavailable regardless of model or prompt --
    # this makes the orchestrator-prompt "browser denied" claim structural instead
    # of advisory, and shrinks the tool surface (defense-in-depth for unattended
    # runs). Deliberately NARROW: `exec` is NOT denied -- the agent needs shell to
    # do any file/code work, and SOUL permits it gated by "GO"; denying it would
    # break the product. `net.fetch`/`web_fetch` is left to the nftables egress
    # firewall (the real, already-structural network control). Failure mode of a
    # denied tool is proven consumer-side in validation, not assumed here.
    $script9a = @'
set -e
openclaw config set gateway.bind loopback >/dev/null
openclaw config set gateway.port 8787 --json >/dev/null
openclaw config set gateway.mode local >/dev/null
openclaw config set plugins.entries.bonjour.enabled false --json >/dev/null
openclaw config set tools.deny --strict-json '["browser"]' >/dev/null
echo "gateway configured (bonjour disabled; tools.deny=[browser])"
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

function Step-StageGatewayHelper {
    # v1.0.42 (cold-start class sweep, L13): stage the shared gateway-health helper
    # (resources/gateway-wait.sh) to a stable, world-readable path so BOTH
    # Step-EnableChatCompletions and install-chat-proxy.sh source ONE definition of
    # the 120s cold-start health window (wait_for_gateway_healthy) and the
    # user-manager readiness assert (assert_user_manager_ready). This is what stops
    # the windows drifting apart and re-introducing the v1.0.41 class of
    # false-failure. MUST run before Step-EnableChatCompletions and Step-InstallChatProxy.
    Write-Log INFO 'Staging shared gateway-health helper (gateway-wait.sh).'
    $libPath = Join-Path $PSScriptRoot 'resources\gateway-wait.sh'
    if (-not (Test-Path -LiteralPath $libPath)) { throw "gateway-wait.sh not found at $libPath (installer bundling error -- Step-Preflight should have caught this)." }
    $libB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($libPath)).Replace("`r`n","`n").Replace("`r","`n")))
    $drop = @"
set -e
mkdir -p /usr/local/lib/clawfactory
echo '$libB64' | base64 -d > /usr/local/lib/clawfactory/gateway-wait.sh
chown root:root /usr/local/lib/clawfactory/gateway-wait.sh
chmod 0644 /usr/local/lib/clawfactory/gateway-wait.sh
bash -n /usr/local/lib/clawfactory/gateway-wait.sh
. /usr/local/lib/clawfactory/gateway-wait.sh
type wait_for_gateway_healthy >/dev/null 2>&1 || { echo '[gateway-helper] FATAL: wait_for_gateway_healthy not defined after source' >&2; exit 1; }
type assert_user_manager_ready >/dev/null 2>&1 || { echo '[gateway-helper] FATAL: assert_user_manager_ready not defined after source' >&2; exit 1; }
echo '[gateway-helper] staged /usr/local/lib/clawfactory/gateway-wait.sh'
"@
    $rc = Invoke-WslBash -Script $drop -User 'root'
    if ($rc -ne 0) { throw "Failed to stage the shared gateway-health helper gateway-wait.sh (exit=$rc). See the [wsl:root ...] lines in the install log at $LogFile." }
    Save-Checkpoint 'StageGatewayHelper'
}

function Step-EnableChatCompletions {
    # v1.0.1: enable the OpenClaw gateway's HTTP /v1/chat/completions endpoint
    # so a future native chat app can talk to the gateway over loopback. Idempotent
    # (`openclaw config set` is idempotent). Failure is non-fatal: gateway works
    # without it; only the native chat app stops working.
    #
    # v1.0.17: switched from `Start-Process -FilePath wsl.exe` to `Invoke-WslBash`
    # to match the working pattern used by $script8c / $script9a in
    # Step-PreinstallGatewayRuntime / Step-ConfigureOpenClaw. The Start-Process
    # path returned exit 1 with no openclaw stdout during install (silent
    # bash-launch failure under the wrapper.cmd auto-logon context) even though
    # identical commands ran fine via scheduled task. Invoke-WslBash uses the
    # base64-script transport that the rest of the installer relies on. Same
    # call also adds the gateway restart inside the bash script (openclaw
    # caches gateway config at startup; route stays unregistered until restart).
    # Also: --strict-json was the wrong flag for boolean values - --json is
    # what writes booleans correctly.
    Write-Log INFO 'Step 9b: Enabling gateway.http.endpoints.chatCompletions.enabled.'
    # v1.0.43 (restart class, L14): enabling chatCompletions needs the gateway to
    # restart to pick up the config. The prior bare `systemctl --user restart`
    # (v1.0.42) with no XDG demonstrably took the gateway DOWN on 8787 and it did
    # not come back within 120s (cfv-0716s: exit=1). Use the shared reliable restart
    # instead -- `openclaw gateway restart` (openclaw's own), falling back to
    # `openclaw gateway install --force` (the mechanism the install proves works),
    # with XDG + a login PATH. Runs as clawuser; the 8787 health probe is a
    # clawuser-allowed path (only ->8788 is firewall-dropped).
    $script9b = @'
set -e
. /usr/local/lib/clawfactory/gateway-wait.sh
openclaw config set gateway.http.endpoints.chatCompletions.enabled true --json >/dev/null
echo "[chatCompletions-set] gateway.http.endpoints.chatCompletions.enabled = true"
if restart_gateway_reliably 8787; then
    echo "[chatCompletions-restart] gateway healthy after reliable restart"
    exit 0
fi
echo "[chatCompletions-restart] WARNING: gateway did not respond after reliable restart" >&2
exit 1
'@
    try {
        $rc = Invoke-WslBash -Script $script9b -User $WslUser
        if ($rc -eq 0) {
            Write-Log INFO 'Enabled gateway.http.endpoints.chatCompletions.enabled and confirmed gateway healthy after restart.'
            Save-Checkpoint 'EnableChatCompletions'
        } else {
            Write-Log WARN "Step-EnableChatCompletions returned exit=$rc. The gateway may still be operational; the native chat app may not connect until this is fixed manually."
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

    # THE PIN IS A BUILD-TIME CONSTANT, NOT AN INSTALL-TIME SELF-HASH.
    #
    # This used to read $soulHash = (Get-FileHash $soulSrc), i.e. it hashed
    # whatever safety-rules.md happened to be sitting in {app}\resources at
    # install time and pinned THAT. A pin computed from the artefact it is meant
    # to certify certifies nothing: swap the file after the installer is built
    # and it installs cleanly, with the launch gate then faithfully enforcing the
    # attacker's version of the safety rules.
    #
    # So the expected digest is a literal baked in from the repo copy at BUILD
    # time (scripts/build_release.ps1 fails the build if this constant and the
    # file disagree). Install compares and REFUSES on mismatch rather than
    # adopting what it finds.
    # Changed when resources/safety-rules.md was normalised to LF. It had been
    # CRLF on disk with no .gitattributes rule, so its digest followed whatever
    # core.autocrlf a given clone used: a clone configured differently would have
    # produced a different hash and this very check would have refused its own
    # safety rules. The file is now pinned to eol=lf in .gitattributes.
    $expectedSoulHash = 'e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941'
    $soulHash = (Get-FileHash -LiteralPath $soulSrc -Algorithm SHA256).Hash.ToLower()
    if ($soulHash -ne $expectedSoulHash) {
        throw ("resources/safety-rules.md does not match the digest this installer was built with. " +
               "Expected $expectedSoulHash but found $soulHash. The safety rules have been altered since " +
               "the build was signed. Refusing to install rather than pinning an unknown file.")
    }
    Write-Log INFO "SOUL.md SHA-256 = $soulHash (matches the build-time pin)"

    $soulB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($soulSrc))
    # Defect 2 / Layer 1: SOUL.md must be tamper-proof against the agent's own
    # UID. It is written AS ROOT, owned root:root, mode 444, and made immutable
    # with `chattr +i`. The immutable attribute is enforced by the kernel on the
    # inode, so clawuser cannot write it, chmod it, OR delete-and-recreate it --
    # even though clawuser owns ~/.openclaw (delete would otherwise be allowed by
    # the directory's write bit). A root-owned copy of the pin is also written to
    # /etc/clawfactory/soul.sha256 (outside clawuser's control) for the Layer 2
    # launch-time gate (Test-SoulIntegrity in clawfactory-grants.ps1).
    # Runs as ROOT, so ~ would be /root -- absolute paths are used throughout.
    $apply = @"
set -e
CLAW_HOME=/home/clawuser
install -d -o clawuser -g clawuser -m 700 `"`$CLAW_HOME/.openclaw`"
mkdir -p /etc/clawfactory
# Clear any prior immutable flag so a re-run / upgrade can overwrite.
chattr -i `"`$CLAW_HOME/.openclaw/SOUL.md`" 2>/dev/null || true
chattr -i `"`$CLAW_HOME/.openclaw/SOUL.md.sha256`" 2>/dev/null || true
echo '$soulB64' | base64 -d > `"`$CLAW_HOME/.openclaw/SOUL.md`"
printf '%s' '$soulHash' > `"`$CLAW_HOME/.openclaw/SOUL.md.sha256`"
printf '%s' '$soulHash' > /etc/clawfactory/soul.sha256
chown root:root `"`$CLAW_HOME/.openclaw/SOUL.md`" `"`$CLAW_HOME/.openclaw/SOUL.md.sha256`" /etc/clawfactory/soul.sha256
chmod 444 `"`$CLAW_HOME/.openclaw/SOUL.md`" `"`$CLAW_HOME/.openclaw/SOUL.md.sha256`" /etc/clawfactory/soul.sha256
# Immutability is the control that defeats delete-and-recreate. Verify + WARN
# loudly if the filesystem cannot hold it (do not silently ship degraded).
chattr +i `"`$CLAW_HOME/.openclaw/SOUL.md`" `"`$CLAW_HOME/.openclaw/SOUL.md.sha256`" 2>/dev/null || true
if lsattr `"`$CLAW_HOME/.openclaw/SOUL.md`" 2>/dev/null | awk '{print `$1}' | grep -q i; then
    echo 'OK: SOUL.md is immutable (chattr +i)'
else
    echo 'WARN: could not set immutable flag on SOUL.md -- delete-and-recreate protection is DEGRADED on this filesystem'
fi
HAVE=`$(sha256sum `"`$CLAW_HOME/.openclaw/SOUL.md`" | awk '{print `$1}')
EXPECT=`$(cat /etc/clawfactory/soul.sha256)
if [ `"`$HAVE`" = `"`$EXPECT`" ]; then echo 'OK: SOUL.md hash verified'; else echo 'MISMATCH'; exit 1; fi
"@
    $rc = Invoke-WslBash -Script $apply -User 'root'
    if ($rc -ne 0) { throw 'Failed to apply SOUL.md.' }
    Save-Checkpoint 'SafetyRules'
}

function Step-InstallTurnGate {
    # Defect 3 (gate coverage): install the gated openclaw shim so NO caller
    # (Studio, the CLI, this engine, or the agent) can launch an UNGATED turn.
    # The shim replaces /usr/bin/openclaw and runs the universal turn gate (SOUL
    # integrity + spend cap, in WSL) before `openclaw agent`; every other
    # subcommand passes straight through. The bash logic lives in reviewable
    # resource scripts (base64-dropped) to avoid PS->bash quoting hazards.
    Write-Log INFO 'Step 15b [Defect 3]: Installing gated openclaw shim (SOUL + spend gate on every turn).'
    $resourceDir = Join-Path $PSScriptRoot 'resources'
    # Normalize CRLF->LF before transport: these are bash/node scripts and a \r
    # in the shebang/`set -e` line breaks them (git autocrlf can introduce CRLF).
    $lfB64 = { param($p) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($p)).Replace("`r`n","`n").Replace("`r","`n"))) }
    $shimB64  = & $lfB64 (Join-Path $resourceDir 'openclaw-shim.sh')
    $gateB64  = & $lfB64 (Join-Path $resourceDir 'clawfactory-turn-gate.sh')
    $spendB64 = & $lfB64 (Join-Path $resourceDir 'clawfactory-spend-check.js')
    $instB64  = & $lfB64 (Join-Path $resourceDir 'install-turn-gate.sh')
    $drop = @"
set -e
mkdir -p /usr/local/sbin /etc/clawfactory
echo '$gateB64'  | base64 -d > /usr/local/sbin/clawfactory-turn-gate.sh
echo '$spendB64' | base64 -d > /usr/local/sbin/clawfactory-spend-check.js
echo '$shimB64'  | base64 -d > /tmp/oc-shim
echo '$instB64'  | base64 -d > /tmp/install-turn-gate.sh
bash /tmp/install-turn-gate.sh
rm -f /tmp/install-turn-gate.sh
"@
    $rc = Invoke-WslBash -Script $drop -User 'root'
    if ($rc -ne 0) { throw 'Failed to install the openclaw turn-gate shim (Defect 3).' }
    Save-Checkpoint 'InstallTurnGate'
}

function Step-FreezeInjectedSoul {
    # Defect 4 (SOUL delivery): the factory safety rules must reach the agent's
    # runtime prompt. OpenClaw injects only the fixed workspace-file set (SOUL.md
    # first) and has no config-level system-prompt channel, so we prepend the
    # factory rules to ~/.openclaw/workspace/SOUL.md, freeze it (root:root 444 +
    # chattr +i), and pin its hash for the launch gate (Test-SoulIntegrity /
    # the shim). Runs late so the workspace is likely already created.
    Write-Log INFO 'Step 15c [Defect 4]: Delivering + freezing the injected workspace SOUL.'
    $resourceDir = Join-Path $PSScriptRoot 'resources'

    # v1: the injected workspace SOUL is a BUILD-TIME CONSTANT -- the factory
    # safety rules plus a fixed persona, composed in a fixed order. The script no
    # longer reads anything off the box, so there is nothing to adopt and no
    # marker to parse. Two literals below, both baked from the repo copies at
    # build time and both enforced by scripts/build_release.ps1:
    #   $expectedPersonaHash        covers resources/persona.md
    #   $expectedWorkspaceSoulHash  covers the COMPOSED file the agent reads
    # Same anchor as $expectedSoulHash above: a literal in signed source, never a
    # digest taken from the artefact it certifies (L24).
    $expectedPersonaHash       = '0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0'
    $expectedWorkspaceSoulHash = '441b6279f6613c313e87e9e9e034f97a220540cddbf1cf738bb9a86c37a5a257'

    $personaSrc = Join-Path $resourceDir 'persona.md'
    if (-not (Test-Path -LiteralPath $personaSrc)) { throw "Missing resources/persona.md at $personaSrc" }
    $personaHash = (Get-FileHash -LiteralPath $personaSrc -Algorithm SHA256).Hash.ToLower()
    if ($personaHash -ne $expectedPersonaHash) {
        throw ("resources/persona.md does not match the digest this installer was built with. " +
               "Expected $expectedPersonaHash but found $personaHash. Refusing to install rather than " +
               "freezing an unknown persona into the agent's prompt.")
    }
    Write-Log INFO "persona.md SHA-256 = $personaHash (matches the build-time pin)"

    # Raw bytes, NOT CRLF-normalised: the digests above are over the repo bytes,
    # so anything else would compose to a different file. .gitattributes pins
    # persona.md and safety-rules.md to eol=lf so every clone agrees.
    $personaB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($personaSrc))
    # The freeze script itself IS transported LF-normalised: it is executed through
    # bash, where a trailing CR in the shebang is fatal (L20/L21).
    $frzB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText((Join-Path $resourceDir 'freeze-injected-soul.sh'))).Replace("`r`n","`n").Replace("`r","`n")))
    $drop = @"
set -e
mkdir -p /etc/clawfactory
echo '$personaB64' | base64 -d > /etc/clawfactory/persona.md
chown root:root /etc/clawfactory/persona.md
chmod 444 /etc/clawfactory/persona.md
echo '$frzB64' | base64 -d > /tmp/freeze-injected-soul.sh
CLAWFACTORY_WORKSPACE_SOUL_SHA256='$expectedWorkspaceSoulHash' bash /tmp/freeze-injected-soul.sh
rm -f /tmp/freeze-injected-soul.sh
"@
    $rc = Invoke-WslBash -Script $drop -User 'root'
    # THROW, do not warn. This used to log a WARN and let the install finish and
    # report success. That was the worst available outcome, because
    # clawfactory-turn-gate.sh enforces the injected SOUL only IF its pin exists:
    # a freeze that failed left no pin, so every turn ran unchecked while the
    # installer, the checklist and the smoke suite all reported green. A green
    # install with no SOUL enforcement is the exact failure class this product
    # exists to eliminate.
    #
    # The audit's fix to freeze-injected-soul.sh makes this path MORE likely to
    # fire, by design: the script now refuses to pin in cases where it previously
    # proceeded. That refusal has to reach the customer, not the log.
    if ($rc -ne 0) {
        throw ("Step-FreezeInjectedSoul failed (exit $rc): the factory safety rules were not delivered " +
               "into the agent's prompt, or could not be frozen and pinned. Refusing to finish the install, " +
               "because the launch gate enforces the injected safety rules only once their pin exists -- " +
               "continuing would produce an install that looks complete but runs the agent unchecked. " +
               "NOTHING was changed on this run. Do NOT just re-run: if the workspace SOUL no longer matches " +
               "its pin, the freeze refuses on purpose rather than adopting contents it cannot attribute, so " +
               "a plain re-run will refuse again. The step logged the exact recovery commands for your case; " +
               "read the lines beginning '[injected-soul]' in $LogFile and follow one of the numbered options " +
               "there, then re-run setup.ps1 -Resume.")
    }
    Save-Checkpoint 'FreezeInjectedSoul'
}

function Step-InstallSend {
    # v1 Guard 2: approval-gated email. Unlike Guard 1, BOTH halves are
    # structural, and the close-out says so in these terms:
    #
    #   The agent can compose. It cannot send. There is no send capability at
    #   uid 1000 at all: no credential, no transport, no socket that executes.
    #   The only sender is a root process the agent cannot modify, reachable for
    #   ENQUEUE only over a 0660 root:clawuser socket. Approval arrives on a
    #   separate 0600 root:root socket the agent cannot open.
    #
    # THE INVARIANT IS PERMANENT: no send path may ever run as uid 1000. The
    # gateway runs as uid 1000, so it and the agent are one security principal;
    # a gate placed there is a code path the agent routes around, not a boundary.
    #
    # This step adds NO firewall accept and NO exemption. The broker reaches SMTP
    # because the egress chain returns early for every uid that is not the agent.
    # install-send.sh only makes that property legible (an explicit SMTP drop in
    # /etc/nftables.conf) and adds a read-only tripwire on the refresh cycle.
    Write-Log INFO 'Step 15f [Guard 2]: Installing the approval-gated send broker (root-owned SMTP, no send at uid 1000).'
    $resourceDir = Join-Path $PSScriptRoot 'resources'
    $lfB64 = { param($p) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($p)).Replace("`r`n","`n").Replace("`r","`n"))) }
    $sLibB64  = & $lfB64 (Join-Path $resourceDir 'send-lib.js')
    $sSmtpB64 = & $lfB64 (Join-Path $resourceDir 'send-smtp.js')
    $sDmnB64  = & $lfB64 (Join-Path $resourceDir 'clawfactory-sendd.js')
    $sCtlB64  = & $lfB64 (Join-Path $resourceDir 'clawfactory-sendctl.js')
    $sCliB64  = & $lfB64 (Join-Path $resourceDir 'clawfactory-send.js')
    $sAsrtB64 = & $lfB64 (Join-Path $resourceDir 'clawfactory-fw-assert.sh')
    $sSvcB64  = & $lfB64 (Join-Path $resourceDir 'clawfactory-send.service')
    $sGcSvB64 = & $lfB64 (Join-Path $resourceDir 'clawfactory-send-gc.service')
    $sGcTmB64 = & $lfB64 (Join-Path $resourceDir 'clawfactory-send-gc.timer')
    $sPolB64  = & $lfB64 (Join-Path $resourceDir 'egress-policy.json')
    $sInstB64 = & $lfB64 (Join-Path $resourceDir 'install-send.sh')
    $drop = @"
set -e
mkdir -p /usr/local/lib/clawfactory /usr/local/sbin /usr/local/bin
echo '$sLibB64'  | base64 -d > /usr/local/lib/clawfactory/send-lib.js
echo '$sSmtpB64' | base64 -d > /usr/local/lib/clawfactory/send-smtp.js
echo '$sDmnB64'  | base64 -d > /usr/local/sbin/clawfactory-sendd.js
echo '$sCtlB64'  | base64 -d > /usr/local/sbin/clawfactory-sendctl.js
echo '$sAsrtB64' | base64 -d > /usr/local/sbin/clawfactory-fw-assert.sh
echo '$sCliB64'  | base64 -d > /usr/local/bin/clawfactory-send
echo '$sSvcB64'  | base64 -d > /tmp/clawfactory-send.service
echo '$sGcSvB64' | base64 -d > /tmp/clawfactory-send-gc.service
echo '$sGcTmB64' | base64 -d > /tmp/clawfactory-send-gc.timer
echo '$sPolB64'  | base64 -d > /tmp/egress-policy.json
echo '$sInstB64' | base64 -d > /tmp/install-send.sh
bash /tmp/install-send.sh
rm -f /tmp/install-send.sh
"@
    $rc = Invoke-WslBash -Script $drop -User 'root'
    if ($rc -ne 0) { throw 'Failed to install the approval-gated send broker (Guard 2). Refusing to finish: the product would claim that email needs your approval while the mechanism that enforces it is absent.' }
    Save-Checkpoint 'InstallSend'
}

function Step-InstallReadFetch {
    # v1 Guard 3: web off by default, allowlist only.
    #
    # READ THIS BEFORE DESCRIBING IT ANYWHERE CUSTOMER-FACING. Guard 3 does not
    # create the denial. The egress chain written by Step-EgressFirewall scopes
    # itself to uid 1000 and ends in a terminal drop, so a destination in no
    # allowlisted set was already unreachable, and that was true before this step
    # existed. What Guard 3 adds is the user-controlled way to open and close a
    # named hole in that denial, and it turns the previously inert read_fetch
    # policy section into the thing that governs it.
    #
    # Runs AFTER Guard 2 for two hard reasons: clawfactory-fetchctl.js loads the
    # shared egress-policy helpers out of send-lib.js, and the policy file itself
    # is written by install-send.sh.
    #
    # Enforcement is by ADDRESS, not by hostname, because that is what an
    # nftables set holds. A site sharing an address with something already
    # reachable is reachable regardless of the list. Stated here so the next
    # reader does not have to rediscover it from the shape of the code.
    Write-Log INFO 'Step 15g [Guard 3]: Installing the read-fetch allowlist (web off by default; the user opens named destinations from Studio).'
    $resourceDir = Join-Path $PSScriptRoot 'resources'
    $lfB64 = { param($p) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($p)).Replace("`r`n","`n").Replace("`r","`n"))) }
    $fResB64  = & $lfB64 (Join-Path $resourceDir 'clawfactory-read-fetch.sh')
    $fCtlB64  = & $lfB64 (Join-Path $resourceDir 'clawfactory-fetchctl.js')
    $fInstB64 = & $lfB64 (Join-Path $resourceDir 'install-read-fetch.sh')
    $drop = @"
set -e
mkdir -p /usr/local/sbin
echo '$fResB64'  | base64 -d > /usr/local/sbin/clawfactory-read-fetch.sh
echo '$fCtlB64'  | base64 -d > /usr/local/sbin/clawfactory-fetchctl.js
echo '$fInstB64' | base64 -d > /tmp/install-read-fetch.sh
bash /tmp/install-read-fetch.sh
rm -f /tmp/install-read-fetch.sh
"@
    $rc = Invoke-WslBash -Script $drop -User 'root'
    if ($rc -ne 0) { throw 'Failed to install the read-fetch allowlist (Guard 3). Refusing to finish: the product would offer a Web access panel with nothing behind it, and a control that is absent is worse than one that was never claimed.' }
    Save-Checkpoint 'InstallReadFetch'
}

function Step-InstallQuarantine {
    # v1 Guard 1: recoverable deletes. Two halves, and they are NOT equally strong
    # -- the close-out and the customer copy both have to keep saying so:
    #
    #   STRUCTURAL: a quarantined file is chowned to root inside a root:root 0700
    #   store. clawuser cannot list it, restore it or purge it. Once held, held.
    #
    #   ADVISORY:  routing the delete into the store. There is no delete TOOL in
    #   OpenClaw to deny (group:fs is read/write/edit/apply_patch); deletion is
    #   just `rm` under the `exec` tool, and exec is the product. So we put a
    #   wrapper at the front of the exec PATH -- which catches `rm <path>`, the
    #   form a delete essentially always takes -- and accept that /bin/rm,
    #   unlink, find -delete and fs.rmSync still go straight through.
    #
    # The broker runs as ROOT because only root can chown a payload out of the
    # agent's reach. It is not a new capability: before every move it re-derives
    # POSIX unlink permission AS clawuser and refuses anything the caller could
    # not have deleted itself (VERIFIED: a root-owned file in a non-writable
    # granted folder comes back EACCES, and a symlink out of the grant resolves
    # out of scope rather than escaping).
    Write-Log INFO 'Step 15e [Guard 1]: Installing the delete quarantine (broker + retention timer + rm wrapper).'
    $resourceDir = Join-Path $PSScriptRoot 'resources'
    $lfB64 = { param($p) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($p)).Replace("`r`n","`n").Replace("`r","`n"))) }
    $libB64   = & $lfB64 (Join-Path $resourceDir 'quarantine-lib.js')
    $dmnB64   = & $lfB64 (Join-Path $resourceDir 'clawfactory-quarantined.js')
    $ctlB64   = & $lfB64 (Join-Path $resourceDir 'clawfactory-quarantinectl.js')
    $rmB64    = & $lfB64 (Join-Path $resourceDir 'clawfactory-quarantine-rm.js')
    $svcB64   = & $lfB64 (Join-Path $resourceDir 'clawfactory-quarantine.service')
    $gcSvcB64 = & $lfB64 (Join-Path $resourceDir 'clawfactory-quarantine-gc.service')
    $gcTmrB64 = & $lfB64 (Join-Path $resourceDir 'clawfactory-quarantine-gc.timer')
    $instB64  = & $lfB64 (Join-Path $resourceDir 'install-quarantine.sh')
    $drop = @"
set -e
mkdir -p /usr/local/sbin /usr/local/lib/clawfactory/execbin
echo '$libB64'   | base64 -d > /usr/local/lib/clawfactory/quarantine-lib.js
echo '$dmnB64'   | base64 -d > /usr/local/sbin/clawfactory-quarantined.js
echo '$ctlB64'   | base64 -d > /usr/local/sbin/clawfactory-quarantinectl.js
echo '$rmB64'    | base64 -d > /usr/local/lib/clawfactory/execbin/rm
echo '$svcB64'   | base64 -d > /tmp/clawfactory-quarantine.service
echo '$gcSvcB64' | base64 -d > /tmp/clawfactory-quarantine-gc.service
echo '$gcTmrB64' | base64 -d > /tmp/clawfactory-quarantine-gc.timer
echo '$instB64'  | base64 -d > /tmp/install-quarantine.sh
bash /tmp/install-quarantine.sh
rm -f /tmp/install-quarantine.sh
"@
    $rc = Invoke-WslBash -Script $drop -User 'root'
    if ($rc -ne 0) { throw 'Failed to install the delete quarantine (Guard 1). Deletes would be permanent while the product says they are recoverable - do not ship this install.' }

    # Put the wrapper on the FRONT of the exec tool's PATH. tools.exec.pathPrepend
    # is a gateway-side setting and OpenClaw REJECTS agent-supplied env.PATH
    # overrides for host execution, so the agent cannot shove the wrapper off its
    # own PATH from inside a turn. Runs as clawuser (config is per-account) and
    # BEFORE Step-InstallChatProxy, whose gateway restart picks the value up.
    $pathScript = @'
set -e
openclaw config set tools.exec.pathPrepend --strict-json '["/usr/local/lib/clawfactory/execbin"]' >/dev/null
openclaw config get tools.exec.pathPrepend
'@
    $rc2 = Invoke-WslBash -Script $pathScript -User $WslUser
    if ($rc2 -ne 0) {
        throw 'Quarantine broker installed but tools.exec.pathPrepend could not be set: the agent would still reach the raw rm. Refusing to report a guard that is not wired.'
    }
    Save-Checkpoint 'InstallQuarantine'
}

function Step-InstallChatProxy {
    # Blocker 1 (CHATCOMPLETIONS_PROXY): ClawChat -- the bundled desktop app --
    # sends every turn to POST 127.0.0.1:8787/v1/chat/completions, which never
    # runs the `openclaw agent` CLI, so the shim's gate never saw it: those turns
    # had neither the spend cap nor the SOUL check. This installs a ClawFactory
    # proxy that OWNS 8787 and gates that route with the same turn gate the shim
    # runs, and moves the real gateway to private loopback 8788.
    #
    # Fail-CLOSED by construction: the real gateway no longer listens on 8787, so
    # if the proxy is down nothing answers there -- ClawChat cannot fall through
    # to an ungated gateway. The proxy runs as ROOT on purpose: a different UID
    # from the agent is what lets the nft rule (Step-EgressFirewall) drop
    # clawuser -> 8788 while the proxy still reaches it.
    Write-Log INFO 'Step 15d [Blocker 1]: Installing the chatCompletions gating proxy (owns 8787; real gateway -> 8788).'
    $resourceDir = Join-Path $PSScriptRoot 'resources'
    $lfB64 = { param($p) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($p)).Replace("`r`n","`n").Replace("`r","`n"))) }
    $proxyB64 = & $lfB64 (Join-Path $resourceDir 'clawfactory-proxy.js')
    $unitB64  = & $lfB64 (Join-Path $resourceDir 'clawfactory-proxy.service')
    $instB64  = & $lfB64 (Join-Path $resourceDir 'install-chat-proxy.sh')
    $drop = @"
set -e
mkdir -p /usr/local/sbin
echo '$proxyB64' | base64 -d > /usr/local/sbin/clawfactory-proxy.js
echo '$unitB64'  | base64 -d > /tmp/clawfactory-proxy.service
echo '$instB64'  | base64 -d > /tmp/install-chat-proxy.sh
bash /tmp/install-chat-proxy.sh
rm -f /tmp/install-chat-proxy.sh
"@
    $rc = Invoke-WslBash -Script $drop -User 'root'
    if ($rc -ne 0) { throw 'Failed to install the chatCompletions gating proxy (Blocker 1). The installer rolled the gateway back to 8787; ClawChat turns would be UNGATED - do not ship this install.' }
    Save-Checkpoint 'InstallChatProxy'
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
    # Running on Windows is functionally equivalent - the agent.md files still
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
    # v1.0.33: action wraps wsl.exe in wscript+VBS (vbHide=0) instead of
    # invoking wsl.exe directly. Interactive LogonTrigger tasks that exec
    # wsl.exe on Win11 with Windows Terminal as default open a wt.exe window
    # at every logon; on Win10 (or wt absent) they flash a console. wscript
    # under vbHide=0 is zero-flash on both. wsl.exe is reparented from
    # wscript and persists after wscript exits, so the keep-alive guarantee
    # is unchanged. The VBS file is bundled at {app}\resources\wsl-keepalive.vbs.
    $KeepAliveVbs = Join-Path $PSScriptRoot 'resources\wsl-keepalive.vbs'
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
      <Repetition>
        <Interval>PT1H</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </LogonTrigger>
    <BootTrigger>
      <Enabled>true</Enabled>
      <Repetition>
        <Interval>PT1H</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </BootTrigger>
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
      <Command>wscript.exe</Command>
      <Arguments>"$KeepAliveVbs" $WslDistro $WslUser</Arguments>
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

function Step-RegisterPostInstallSmokeTask {
    # v1.0.29: Write a smoke-check script to ProgramData and register a
    # Scheduled Task that fires AtLogon (BUILTIN\Users), runs 11 checks as
    # the interactive user (so WSL is accessible), writes results to
    # C:\ProgramData\ClawFactory\smoke-results.json, and self-unregisters.
    # CC reads smoke-results.json via run-command (SYSTEM can read ProgramData)
    # without needing WSL access directly.
    Write-Log INFO 'Step 17: Registering ClawFactory-PostInstall-Smoke scheduled task.'
    try {
        $smokePath = 'C:\ProgramData\ClawFactory\run-smoke.ps1'
        $smokeScript = @'
$ok = 0; $fail = 0; $results = @{}
function Check { param($Name, [scriptblock]$Test)
    try {
        $pass = (& $Test)
        $results[$Name] = if ($pass) { "PASS" } else { "FAIL" }
        if ($pass) { $script:ok++ } else { $script:fail++ }
    } catch {
        $results[$Name] = "FAIL: $($_.Exception.Message)"
        $script:fail++
    }
}

Check "WSL automount disabled" {
    # Section-aware (v1.0.47): join lines and scope to [automount] so the new
    # [interop] enabled=false line cannot mask automount drift as a false pass.
    ((wsl -d Ubuntu -u clawuser -- cat /etc/wsl.conf) -join "`n") -match "\[automount\][^\[]*enabled\s*=\s*false" }

Check "Four agent.md files present" {
    $s = "for a in orchestrator skill-scout skill-builder publisher; do f=`$HOME/.openclaw/agents/`$a/agent.md; [ -s `$f ] || exit 1; done; echo OK"
    $e = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))
    (wsl -d Ubuntu -u clawuser --cd ~ -- bash -lc "echo $e | base64 -d | bash") -eq "OK" }

Check "AgentBootstrap checkpoint recorded" {
    $cp = Join-Path $env:ProgramData "ClawFactory\checkpoint.json"
    (Get-Content $cp -Raw | ConvertFrom-Json).completedSteps -contains "AgentBootstrap" }

Check "Gateway responds 200 on loopback" {
    # v1.0.42 (cold-start class sweep, L13): poll up to 120s (break on first 200)
    # instead of a single 5s probe. This smoke task fires AtLogon and can race the
    # ~67s gateway cold start on a just-booted box; a single-shot probe produced a
    # false FAIL. Matches the install-path 120s standard (gateway-wait.sh).
    $deadline = (Get-Date).AddSeconds(120); $ok = $false
    do {
        try { if ((Invoke-WebRequest -Uri http://127.0.0.1:8787/status -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200) { $ok = $true; break } } catch {}
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    $ok }

Check "Firewall inbound-deny rule on 8787" {
    $r = Get-NetFirewallRule -DisplayName "ClawFactory-Block-Inbound-8787" -ErrorAction SilentlyContinue
    $r -and $r.Enabled -eq "True" -and $r.Action -eq "Block" }

Check "Orchestrator SOUL hash substituted" {
    $s = 'grep -q "{{SOUL_SHA256}}" $HOME/.openclaw/agents/orchestrator/agent.md && echo BAD || echo OK'
    $e = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))
    (wsl -d Ubuntu -u clawuser --cd ~ -- bash -lc "echo $e | base64 -d | bash") -eq "OK" }

Check ".wslconfig vmIdleTimeout present" {
    $w = Get-Content "$env:USERPROFILE\.wslconfig" -Raw -ErrorAction SilentlyContinue
    $w -match "vmIdleTimeout\s*=\s*-1" }

Check "WSL host task registered" {
    $t = Get-ScheduledTask -TaskName "ClawFactory WSL Host" -ErrorAction SilentlyContinue
    $t -and $t.State -ne "Disabled" }

Check "nft clawfactory chain present" {
    # v1.0.34: list as root. clawuser has no CAP_NET_ADMIN (its temp NOPASSWD
    # sudoers is stripped post-create), so `nft list ruleset` as clawuser fails
    # with a permission error and the chain never shows -- a privilege false
    # positive that FAILed this check in v1.0.23/.24. Root reads the real ruleset.
    $r = wsl -d Ubuntu -u root -- bash -lc "/usr/sbin/nft list ruleset 2>&1"
    $r -match "clawfactory" }

Check "OpenClaw build deps present" {
    $s = "which make g++ cmake python3 > /dev/null 2>&1 && echo OK || echo MISSING"
    $e = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))
    (wsl -d Ubuntu -u clawuser --cd ~ -- bash -lc "echo $e | base64 -d | bash") -eq "OK" }

Check "No ft-mangling in install log" {
    $m = Select-String -Path "$env:ProgramData\ClawFactory\install.log" `
        -Pattern "ft: command not found" -ErrorAction SilentlyContinue
    -not $m }

# Unregister self before writing results
Unregister-ScheduledTask -TaskName "ClawFactory-PostInstall-Smoke" -Confirm:$false -ErrorAction SilentlyContinue

# Write results JSON
$output = @{
    timestamp = (Get-Date -Format "o")
    pass      = $ok
    fail      = $fail
    total     = ($ok + $fail)
    results   = $results
} | ConvertTo-Json -Depth 3
Set-Content -Path "C:\ProgramData\ClawFactory\smoke-results.json" -Value $output -Encoding UTF8
'@

        New-Item -ItemType Directory -Force -Path 'C:\ProgramData\ClawFactory' | Out-Null
        Set-Content -Path $smokePath -Value $smokeScript -Encoding UTF8
        Write-Log INFO "PostInstall smoke script written to $smokePath"

        # v1.0.33: -WindowStyle Hidden suppresses the PowerShell console
        # window that otherwise flashes at logon (the -Hidden task setting
        # only hides the task entry in Task Scheduler MMC, not the action's
        # console window).
        $action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
                       -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$smokePath`""
        $trigger   = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet -Hidden
        Register-ScheduledTask -TaskName 'ClawFactory-PostInstall-Smoke' `
            -Action $action -Trigger $trigger -Principal $principal `
            -Settings $settings -Force | Out-Null
        Write-Log INFO 'PostInstall smoke task registered (fires at next user logon)'
        Save-Checkpoint 'PostInstallSmokeTask'
    } catch {
        Write-Log WARN "Step-RegisterPostInstallSmokeTask hit an error and is continuing: $($_.Exception.Message)"
    }
}

#--- Main ---------------------------------------------------------------------
# v1.0.12: every exit path - success, install failure, final-health-gate
# failure, or pre-Invoke-WithRollback failure - must write INSTALLER_DONE
# to both install.log and C:\install-result.txt. The validation harness
# polls for INSTALLER_DONE; before v1.0.12 it was never emitted, so even
# a clean failure looked like a TIMEOUT to the harness.
$script:InstallSucceeded = $false
$script:InstallFailReason = ''
$script:RebootPending = $false
try {

if ($Resume) {
    # Recover provider from the resume flag. The cmdline -Provider value on a
    # /resume relaunch is whatever Inno's GetProviderLabel returned - which
    # itself reads the flag, and defaults to 'grok' if the flag is missing or
    # malformed. Falling back to that default silently has caused real
    # provider drift in the past (v1.0.27 bisect on cfv-128: an Anthropic
    # install resumed as Grok because the flag was wiped by a prior
    # installer's startup). v1.0.28: treat a missing/empty/malformed flag as
    # a hard failure with a clear message, rather than silently shipping a
    # different provider than the user selected.
    $flag = Read-ResumeFlag
    if (-not $flag) {
        Write-Log ERROR "FATAL: -Resume passed but resume flag at $ResumeFlagFile is missing or unreadable. Refusing to continue with a guessed provider (would silently install Grok config on what may be a Claude install). To recover: delete $CheckpointFile and re-run the installer from scratch."
        throw "Resume flag not found at $ResumeFlagFile. Cannot resume safely - see the install log at C:\ProgramData\ClawFactory\install.log."
    }
    if ([string]::IsNullOrEmpty($flag.provider)) {
        Write-Log ERROR "FATAL: Resume flag at $ResumeFlagFile is present but missing the 'provider' field. Refusing to continue with a guessed provider. To recover: delete $CheckpointFile and $ResumeFlagFile and re-run the installer."
        throw "Resume flag at $ResumeFlagFile lacks 'provider' field. Cannot resume safely - see the install log at C:\ProgramData\ClawFactory\install.log."
    }
    if ($flag.provider -ne $Provider) {
        Write-Log INFO "Resume: switching provider from cmdline '$Provider' to flag value '$($flag.provider)'."
        $Provider     = $flag.provider
        $ThisProvider = $ProviderConfig[$Provider]
    }
    # Scheduled task self-unregisters as its first action when it fires; this
    # is belt-and-suspenders for the case where it didn't (manually triggered
    # resume, task ran but unregister step errored, etc).
    Unregister-ResumeScheduledTask
    # v1.0.14: @() defends against PS 5.1 single-element-array unrolling
    # for consistency with the Invoke-WithRollback fix. Current downstream
    # use is -join only, so the bug wouldn't fire here, but the array-wrap
    # discipline is cheaper than discovering the same bug a third time.
    $existing = @(Get-CompletedSteps)
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
    # v1.0.11: rootfs bundle ships with /tmp owned root:root 755; clawuser
    # cannot write there, causing "tee: /tmp/openclaw-install.log: Permission
    # denied" during gateway install. Fix immediately after WSL is running.
    $null = Invoke-WslBash -Script 'chmod 1777 /tmp && chmod 1777 /var/tmp' -User 'root'
    Write-Log INFO 'v1.0.11: Set /tmp and /var/tmp to 1777 (sticky+world-writable).'
    # v1.0.12: pre-create /tmp/openclaw-install.log owned by clawuser. The
    # gateway-install step runs `tee /tmp/openclaw-install.log` as clawuser;
    # if the file already exists with root ownership (created by an earlier
    # root-context tee invocation), sticky-bit /tmp won't let clawuser
    # overwrite it - "tee: Permission denied" was the v1.0.11 symptom.
    # v1.0.13: also chmod 0666 so any user (root, clawuser, or other)
    # can append to the file even if install.sh internally re-creates
    # it via a sudo context. Mode-only fix; ownership stays clawuser.
    $null = Invoke-WslBash -Script 'rm -f /tmp/openclaw-install.log && touch /tmp/openclaw-install.log && chown clawuser:clawuser /tmp/openclaw-install.log && chmod 0666 /tmp/openclaw-install.log' -User 'root'
    Write-Log INFO 'v1.0.13: Pre-created /tmp/openclaw-install.log owned by clawuser, mode 0666.'
    Step-CreateClawUser
    Step-SetDefaultUser
    Step-InstallBaseDeps         # was Step-InstallDocker; Docker removed (SECFIX_CLOSE_DOORS), nftables/dbus-user-session preserved
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
    Step-StageGatewayHelper      # v1.0.42: stage the shared 120s gateway-health helper (gateway-wait.sh) BEFORE the two steps that source it
    Step-EnableChatCompletions   # v1.0.1, repositioned in v1.0.2: must run AFTER runtime install (`openclaw config set` needs the runtime present, or it just prints --help)
    Step-CreateAgentDirectories  # pre-create 4 agent dirs (orchestrator, scout, builder, publisher)
    Step-ApplySafetyRules        # SOUL.md + hash pinning
    Step-WireProviderKey         # write auth-profiles.json with API key
    Step-WindowsFirewallDeny
    Step-PostInstall
    Step-ConfigureAgents         # step 15: stage agent.md prompts via bootstrap.ps1
    Step-InstallTurnGate         # Defect 3: gated openclaw shim (SOUL + spend on every turn, all callers)
    Step-FreezeInjectedSoul      # Defect 4: deliver + freeze the factory safety rules into the injected SOUL
    Step-InstallQuarantine       # Guard 1: recoverable deletes. Before the proxy step, whose gateway restart picks up pathPrepend
    Step-InstallSend             # Guard 2: approval-gated email. After the firewall steps: it asserts the live chain shape and refuses if it has drifted
    Step-InstallReadFetch        # Guard 3: web off by default. After Guard 2: shares its policy file and its egress-policy helpers
    Step-InstallChatProxy        # Blocker 1: gate ClawChat's HTTP path; real gateway -> private 8788
}

#--- Final gateway health gate ------------------------------------------------
# After all install steps complete, confirm the gateway is responding before
# reporting success. This is the real health gate - replaces the old
# `openclaw doctor` final-check (removed because of openclaw/openclaw#47133:
# CLI commands that open a WS connection to the running gateway trigger
# SIGTERM on disconnect, restart cycle). HTTP /status uses no WS and never
# triggers #47133.
#
# v1.0.37: poll IN-WSL via Invoke-WslBash curl, mirroring the pre-install gate
# (Step-PreinstallGatewayRuntime / gate #1). The v1.0.36 cfv-136 journal proved
# the failure was NOT timing: the prior Windows-side Invoke-WebRequest poll
# opened no WSL session, so once bootstrap's last WSL session exited the distro
# shut down (last-session-exit teardown, ref v1.0.2 lineage) and the gateway was
# SIGTERM'd mid-gate - the gate then polled a dead port for the full window.
# Polling via Invoke-WslBash opens a clawuser (user@1000) session on every
# attempt, holding the distro - and the gateway's user service - alive for the
# duration of the gate. Same probe / success-test / loop discipline as gate #1:
# 13 attempts, 10s apart (iterations 1..12 sleep = 120s guaranteed), clearing
# the observed ~67s cold start with >= 50s headroom.
Write-Log INFO 'Final gateway health gate: polling http://127.0.0.1:8787/status in-WSL for up to 120s.'
$healthy = $false
for ($i = 1; $i -le 13; $i++) {
    $rcCurl = Invoke-WslBash -Script 'curl -fsS --max-time 5 http://127.0.0.1:8787/status >/dev/null 2>&1' -User 'clawuser'
    if ($rcCurl -eq 0) {
        Write-Log INFO "Final health gate: gateway responsive on attempt $i."
        $healthy = $true
        break
    }
    if ($i -lt 13) { Start-Sleep -Seconds 10 }
}
if (-not $healthy) {
    throw 'Final gateway health gate failed: in-WSL curl http://127.0.0.1:8787/status did not return 200 within 120 seconds. Diagnose with: wsl -d Ubuntu -u clawuser -- journalctl --user -u openclaw-gateway -n 100, then `cat ~/.openclaw/logs/gateway.log`. After the underlying issue is fixed, re-run setup.ps1 (the 15 install steps will skip via checkpoints; only the final gate re-runs).'
}

# v1.0.45: PRIME THE SPEND METER (L18). The turn-gate reads spend via
# `openclaw gateway usage-cost --json --days 400`; that WS endpoint is NOT ready
# for ~1-2 min after the gateway's final (port-move) restart, even though /status
# is already 200. So a fresh install's FIRST customer turn was fail-safe-blocked
# (spend_meter_unknown) until the meter warmed (cfv-0717d/e). Warm the EXACT query
# the turn-gate uses now, as clawuser (dials the proxy on 8787), so the first turn
# is not blocked. NON-FATAL: the turn-gate's own retry + fail-safe still protect if
# this never warms -- so `|| true` semantics; never throw here.
Write-Log INFO 'Priming the spend meter (usage-cost) so the first turn is not fail-safe-blocked...'
$spendPrime = @'
for i in $(seq 1 40); do
    u="$(openclaw gateway usage-cost --json --days 400 2>/dev/null)"
    if [ -n "$u" ]; then echo "[spend-prime] meter warm on attempt $i"; exit 0; fi
    sleep 3
done
echo "[spend-prime] WARNING: meter not readable after ~120s; the turn-gate retry + fail-safe will cover it" >&2
exit 0
'@
try { $null = Invoke-WslBash -Script $spendPrime -User 'clawuser' } catch { Write-Log WARN "Spend-meter prime hit an error (non-fatal): $($_.Exception.Message)" }

# v1.0.2: register the WSL Host keep-alive task only after the gateway has
# been proven healthy. If the health gate above throws, this never runs and
# we don't leave a dangling task pointing at a broken install. Outside the
# Invoke-WithRollback block on purpose - failure here is non-fatal.
Step-RegisterWslHostTask
Step-RegisterPostInstallSmokeTask

Write-Log INFO '==== ClawFactory Secure Setup - completed successfully ===='
Remove-ResumeFlag
Unregister-ResumeScheduledTask

Write-Host ''
Write-Host 'SUCCESS. Your hardened Skills Factory is ready.' -ForegroundColor Green
Write-Host "Log: $LogFile"
Write-Host "Provider: $($ThisProvider.DisplayName)  |  Default model: $($ThisProvider.DefaultModel)"
# Next-step commands are printed by bootstrap.ps1 (Step 15).
$script:InstallSucceeded = $true

} catch {
    $script:InstallFailReason = $_.Exception.Message
    Write-Log ERROR "Top-level handler caught: $($_.Exception.Message)"
    throw
} finally {
    # v1.0.12: emit INSTALLER_DONE marker on EVERY exit path EXCEPT
    # mid-install reboot. The reboot path's resume run will emit the
    # real marker after the rest of the install completes.
    # PowerShell forbids `return` inside a finally block, so we gate
    # the entire emit logic on a single guard expression.
    if ($script:RebootPending) {
        Write-Log INFO 'INSTALLER_PAUSED=reboot (resume run will emit INSTALLER_DONE).'
    } else {
        $marker = if ($script:InstallSucceeded) { 'success' } else { 'failure' }
        $reason = if ($script:InstallFailReason) { " reason=$($script:InstallFailReason)" } else { '' }
        Write-Log INFO "INSTALLER_DONE=$marker$reason"
        # Best-effort write to a stable filesystem location. Write to ProgramData
        # first (always exists, always writable by the install context); also
        # try C:\ for compatibility with the existing validation harness, but
        # don't fail if it's locked down.
        $pdMarker = Join-Path $LogDir 'install-result.txt'
        try {
            Set-Content -LiteralPath $pdMarker -Value "INSTALLER_DONE=$marker$reason" -Encoding Ascii -ErrorAction Stop
        } catch {
            # ProgramData write should never fail; if it does, install.log still
            # contains the marker, which the validation harness already scans.
        }
        try {
            Set-Content -LiteralPath 'C:\install-result.txt' -Value "INSTALLER_DONE=$marker$reason" -Encoding Ascii -ErrorAction Stop
        } catch {
            # C:\ may be locked down on some hosts - non-fatal, the ProgramData
            # copy and install.log marker are sufficient.
        }
    }
}

exit ([int](-not $script:InstallSucceeded))
