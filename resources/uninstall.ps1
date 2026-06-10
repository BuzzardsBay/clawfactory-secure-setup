[CmdletBinding()]
param(
    # Inno's UninstallSilent maps here. Suppresses all UI dialogs.
    [switch]$Silent,
    # Remove the Linux environment (Ubuntu distro, clawuser, openclaw,
    # nftables chains). Default for /SILENT uninstall is RemoveAll=TRUE
    # unless -KeepLinuxEnvironment is also passed.
    [switch]$RemoveAll,
    # Explicit opt-out of distro removal. Useful for /REMOVEALL=0 silent
    # uninstall (e.g. an IT pilot deploy where the Ubuntu image is shared
    # with other tooling).
    [switch]$KeepLinuxEnvironment
)

# ClawFactory uninstaller (v1.0.33)
# ---------------------------------
# Invoked by [UninstallRun] from the Inno-generated uninstall.exe.
# Reverses every persistent artifact the installer created -- see TASK 1
# inventory in the v1.0.33 work package for the authoritative list.
#
# Design rules:
#   - TOLERANT: every step swallows "already gone" / "not present" errors
#     and keeps moving. A partial install with missing artifacts must still
#     uninstall cleanly.
#   - SURGICAL: %USERPROFILE%\.wslconfig is edited based on the state file
#     setup.ps1 wrote at install time. Branches: created / appended-section
#     / added-key / unchanged / conflict. Branches 4 and 5 are no-op.
#   - LOGGED: writes to %TEMP%\ClawFactory-Uninstall.log because
#     C:\ProgramData\ClawFactory is one of the things we're deleting.
#   - SILENT-CAPABLE: no Read-Host, no MessageBox unless -Silent is absent.
#
# Exit codes are advisory only; Inno proceeds with its own file/icon
# cleanup regardless. We always exit 0 unless something fundamentally
# unexpected happens.

$ErrorActionPreference = 'Continue'

#--- Logging -----------------------------------------------------------------
$LogFile = Join-Path $env:TEMP 'ClawFactory-Uninstall.log'
function Write-Log {
    param([string]$Level, [string]$Message)
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 's'), $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch {}
    Write-Host $line
}

Write-Log INFO "==== ClawFactory uninstall starting (Silent=$Silent RemoveAll=$RemoveAll KeepLinuxEnvironment=$KeepLinuxEnvironment) ===="

#--- Cached state we need before nuking ProgramData --------------------------
$ProgramDataDir   = Join-Path $env:ProgramData 'ClawFactory'
$WslConfigPath    = Join-Path $env:USERPROFILE '.wslconfig'
$WslConfigState   = $null
$DistroPreExisted = $null
$LicenseKey       = $null

try {
    $sf = Join-Path $ProgramDataDir 'wslconfig-state.txt'
    if (Test-Path -LiteralPath $sf) {
        $WslConfigState = (Get-Content -LiteralPath $sf -Raw).Trim()
        Write-Log INFO "Cached wslconfig-state = '$WslConfigState'"
    } else {
        Write-Log WARN "wslconfig-state.txt missing; .wslconfig edit cannot be reversed surgically. Will skip."
    }
} catch { Write-Log WARN "wslconfig-state.txt read failed: $($_.Exception.Message)" }

try {
    $sf = Join-Path $ProgramDataDir 'wsl-state.txt'
    if (Test-Path -LiteralPath $sf) {
        $DistroPreExisted = ((Get-Content -LiteralPath $sf -Raw).Trim() -eq 'true')
        Write-Log INFO "Cached distroExistedPreInstall = $DistroPreExisted"
    }
} catch { Write-Log WARN "wsl-state.txt read failed: $($_.Exception.Message)" }

# License key for best-effort deactivation. HKLM read - silent failure if absent.
try {
    $LicenseKey = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\ClawFactory' -Name 'LicenseKey' -ErrorAction Stop).LicenseKey
    if ($LicenseKey) { Write-Log INFO "Cached license key for deactivation call." }
} catch { Write-Log INFO "No license key in HKLM\SOFTWARE\ClawFactory (already gone or never set)." }

#--- Decide RemoveAll --------------------------------------------------------
if ($KeepLinuxEnvironment) {
    $script:DoRemoveAll = $false
} elseif ($RemoveAll) {
    $script:DoRemoveAll = $true
} elseif ($Silent) {
    # Default for silent uninstall is to remove everything. /REMOVEALL=0 -> -KeepLinuxEnvironment.
    $script:DoRemoveAll = $true
} else {
    # Interactive: ask. Default = Yes (the spec says default checked).
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $msg = "Also remove the Linux sandbox and all agent data?`r`n`r`n" +
               "Selecting YES will:`r`n" +
               "  - Unregister the Ubuntu WSL distro that ClawFactory created`r`n" +
               "  - Delete clawuser's home directory (agents, plugins, config)`r`n" +
               "  - Delete the OpenClaw install and the bundled VHDX (~6 GB)`r`n`r`n" +
               "Selecting NO leaves the Ubuntu distro registered. Your conversation`r`n" +
               "history and agent configs stay on disk. You can re-install ClawFactory`r`n" +
               "later and reuse the existing distro."
        $choice = [System.Windows.Forms.MessageBox]::Show(
            $msg, 'ClawFactory Uninstall',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1
        )
        $script:DoRemoveAll = ($choice -eq [System.Windows.Forms.DialogResult]::Yes)
    } catch {
        Write-Log WARN "Could not show MessageBox; defaulting to RemoveAll=true: $($_.Exception.Message)"
        $script:DoRemoveAll = $true
    }
}
Write-Log INFO "Resolved DoRemoveAll = $script:DoRemoveAll"

#--- 1. Stop the gateway + terminate WSL -------------------------------------
Write-Log INFO 'Step 1: Stopping gateway and terminating WSL distro.'
try {
    # Best-effort gateway stop via the keep-alive task's user context. Failures
    # here are fine -- the distro terminate below covers it.
    $null = & wsl.exe -d Ubuntu -u clawuser -- bash -lc 'systemctl --user stop openclaw-gateway 2>/dev/null || true' 2>$null
} catch {}
try {
    $null = & wsl.exe --terminate Ubuntu 2>$null
    Write-Log INFO 'wsl --terminate Ubuntu issued.'
} catch { Write-Log WARN "wsl --terminate failed: $($_.Exception.Message)" }

#--- 2. Unregister scheduled tasks ------------------------------------------
Write-Log INFO 'Step 2: Unregistering ClawFactory scheduled tasks.'
$tasks = @(
    'ClawFactory WSL Host',           # v1.0.2 keep-alive
    'ClawFactory-Resume',              # v1.0.27 reboot resume (usually self-unregistered)
    'ClawFactory-PostInstall-Smoke'    # v1.0.29 post-install smoke (usually self-unregistered)
)
foreach ($t in $tasks) {
    try {
        $existing = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop
            Write-Log INFO "Unregistered task: $t"
        } else {
            Write-Log INFO "Task already absent: $t"
        }
    } catch { Write-Log WARN "Could not unregister '$t': $($_.Exception.Message)" }
}

#--- 3. Firewall rule --------------------------------------------------------
Write-Log INFO 'Step 3: Removing firewall rule.'
try {
    $rule = Get-NetFirewallRule -DisplayName 'ClawFactory-Block-Inbound-8787' -ErrorAction SilentlyContinue
    if ($rule) {
        Remove-NetFirewallRule -DisplayName 'ClawFactory-Block-Inbound-8787' -ErrorAction Stop
        Write-Log INFO 'Removed firewall rule ClawFactory-Block-Inbound-8787.'
    } else {
        Write-Log INFO 'Firewall rule already absent.'
    }
} catch { Write-Log WARN "Could not remove firewall rule: $($_.Exception.Message)" }

#--- 4. DPAPI credentials ----------------------------------------------------
Write-Log INFO 'Step 4: Removing DPAPI credentials.'
foreach ($cred in @(
    'ClawFactory/GrokApiKey',
    'ClawFactory/OpenAIApiKey',
    'ClawFactory/AnthropicApiKey',
    'ClawFactory/GeminiApiKey'
)) {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'cmdkey.exe'
        $psi.Arguments = "/delete:$cred"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $null = $proc.StandardOutput.ReadToEnd()
        $null = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        Write-Log INFO "cmdkey /delete:$cred exit $($proc.ExitCode)"
    } catch { Write-Log WARN "cmdkey delete '$cred' failed: $($_.Exception.Message)" }
}

#--- 5. Surgical .wslconfig edit --------------------------------------------
Write-Log INFO "Step 5: Reversing .wslconfig edit (action = $WslConfigState)."
if (-not (Test-Path -LiteralPath $WslConfigPath)) {
    Write-Log INFO '.wslconfig is already gone; nothing to do.'
} elseif ($null -eq $WslConfigState -or $WslConfigState -in @('unchanged','conflict')) {
    Write-Log INFO "Skipping .wslconfig edit (state '$WslConfigState' means we did not modify it)."
} else {
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $banner = '# Added by ClawFactory v1.0.1 - keeps WSL VM alive so the gateway stays running.'
        switch ($WslConfigState) {
            'created' {
                # We own the whole file. Delete it.
                Remove-Item -LiteralPath $WslConfigPath -Force -ErrorAction Stop
                Write-Log INFO 'Deleted .wslconfig (we created it).'
            }
            'appended-section' {
                # We appended `[wsl2]\nvmIdleTimeout=-1\n<banner>\n` to an existing file.
                # Find the banner; remove banner line + the 3 lines preceding ([wsl2], vmIdleTimeout, optional blank).
                $existing = [System.IO.File]::ReadAllText($WslConfigPath)
                $lines = $existing -split "(?:\r`n|\n)"
                $bannerIdx = -1
                for ($i = 0; $i -lt $lines.Length; $i++) {
                    if ($lines[$i].Trim() -eq $banner) { $bannerIdx = $i; break }
                }
                if ($bannerIdx -lt 0) {
                    Write-Log WARN 'appended-section: banner not found, falling back to no-op.'
                } else {
                    # Walk backward from banner removing vmIdleTimeout=-1 then [wsl2] header.
                    $removeStart = $bannerIdx
                    if ($removeStart - 1 -ge 0 -and $lines[$removeStart - 1] -match '^\s*vmIdleTimeout\s*=\s*-1\s*$') {
                        $removeStart -= 1
                    }
                    if ($removeStart - 1 -ge 0 -and $lines[$removeStart - 1] -match '^\s*\[wsl2\]\s*$') {
                        $removeStart -= 1
                    }
                    # Also eat a single blank separator before our block, if any.
                    if ($removeStart - 1 -ge 0 -and $lines[$removeStart - 1].Trim() -eq '') {
                        $removeStart -= 1
                    }
                    $kept = @()
                    if ($removeStart -gt 0) { $kept += $lines[0..($removeStart - 1)] }
                    if ($bannerIdx + 1 -lt $lines.Length) { $kept += $lines[($bannerIdx + 1)..($lines.Length - 1)] }
                    $newContent = ($kept -join "`r`n").TrimEnd("`r","`n")
                    if ($newContent.Length -eq 0) {
                        Remove-Item -LiteralPath $WslConfigPath -Force -ErrorAction Stop
                        Write-Log INFO 'Removed ClawFactory [wsl2] section; .wslconfig is now empty, deleted file.'
                    } else {
                        [System.IO.File]::WriteAllText($WslConfigPath, $newContent + "`r`n", $utf8NoBom)
                        Write-Log INFO 'Removed ClawFactory [wsl2] section from .wslconfig.'
                    }
                }
            }
            'added-key' {
                # [wsl2] section pre-existed; we injected `vmIdleTimeout=-1`
                # immediately after the header. Remove only that line.
                $existing = [System.IO.File]::ReadAllText($WslConfigPath)
                # Remove the first vmIdleTimeout=-1 line under [wsl2] only.
                # Pattern: [wsl2]\r\n<our line>  -> [wsl2]\r\n
                $patched = [regex]::Replace(
                    $existing,
                    '(?im)(^\s*\[wsl2\]\s*\r?\n)\s*vmIdleTimeout\s*=\s*-1\s*\r?\n',
                    '$1', 1)
                if ($patched -ne $existing) {
                    [System.IO.File]::WriteAllText($WslConfigPath, $patched, $utf8NoBom)
                    Write-Log INFO 'Removed vmIdleTimeout=-1 from [wsl2] section.'
                } else {
                    Write-Log WARN 'added-key: pattern not found; .wslconfig left unchanged.'
                }
            }
            default {
                Write-Log WARN "Unknown wslconfig-state '$WslConfigState'; skipping edit."
            }
        }
    } catch {
        Write-Log WARN "Surgical .wslconfig edit failed: $($_.Exception.Message)"
    }
}

#--- 6. Linux environment teardown ------------------------------------------
if ($script:DoRemoveAll) {
    Write-Log INFO 'Step 6: Removing Linux environment (RemoveAll).'
    try {
        # wsl --unregister is destructive and the cleanest possible reverse.
        # It deletes the VHDX, the registration, and everything inside.
        $null = & wsl.exe --unregister Ubuntu 2>&1
        Write-Log INFO 'wsl --unregister Ubuntu issued.'
    } catch { Write-Log WARN "wsl --unregister failed: $($_.Exception.Message)" }
} else {
    Write-Log INFO 'Step 6: Keeping Linux environment (per -KeepLinuxEnvironment).'
    try {
        # Surgical teardown inside the distro: remove openclaw + clawuser +
        # nftables chains, leave the distro registered. Best-effort.
        $script = @'
set +e
# Stop and disable gateway
sudo -u clawuser bash -c 'systemctl --user stop openclaw-gateway 2>/dev/null; systemctl --user disable openclaw-gateway 2>/dev/null' 2>/dev/null
# Flush the clawfactory nft chain (uses iptables on WSL1)
/usr/sbin/nft delete table inet clawfactory 2>/dev/null
# Remove the openclaw global install
rm -rf /usr/lib/node_modules/openclaw 2>/dev/null
rm -f /usr/bin/openclaw /usr/local/bin/openclaw 2>/dev/null
# Remove clawuser home + the user itself
deluser --remove-home clawuser 2>/dev/null
# Drop the WSL default-user line we added
sed -i '/^\[user\]/,/^$/d' /etc/wsl.conf 2>/dev/null
echo OK
'@
        $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
        $null = & wsl.exe -d Ubuntu -u root -- bash -lc "echo $enc | base64 -d | bash" 2>&1
        Write-Log INFO 'In-distro ClawFactory artifacts removed; Ubuntu distro left registered.'
    } catch { Write-Log WARN "In-distro teardown failed: $($_.Exception.Message)" }
}

#--- 7. Best-effort license deactivation ------------------------------------
Write-Log INFO 'Step 7: Best-effort license deactivation.'
if ($LicenseKey) {
    try {
        $machineId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name 'MachineGuid' -ErrorAction Stop).MachineGuid
        $body = @{ key = $LicenseKey; machine_id = $machineId } | ConvertTo-Json -Compress
        # 5-second timeout, fail-closed. Uninstall must not block on network.
        $resp = Invoke-WebRequest `
            -Uri 'https://api.clawfactory.app/deactivate' `
            -Method POST `
            -Body $body `
            -ContentType 'application/json' `
            -UseBasicParsing `
            -TimeoutSec 5 `
            -ErrorAction Stop
        Write-Log INFO "License deactivation responded HTTP $($resp.StatusCode)."
    } catch { Write-Log WARN "License deactivation failed (non-fatal): $($_.Exception.Message)" }
} else {
    Write-Log INFO 'No license key cached; skipping deactivation call.'
}

#--- 8. HKLM\SOFTWARE\ClawFactory --------------------------------------------
Write-Log INFO 'Step 8: Removing HKLM\SOFTWARE\ClawFactory.'
try {
    if (Test-Path 'HKLM:\SOFTWARE\ClawFactory') {
        Remove-Item -Path 'HKLM:\SOFTWARE\ClawFactory' -Recurse -Force -ErrorAction Stop
        Write-Log INFO 'Removed HKLM\SOFTWARE\ClawFactory.'
    }
} catch { Write-Log WARN "HKLM cleanup failed: $($_.Exception.Message)" }

#--- 9. ProgramData -- delete last so we can read state files above ---------
Write-Log INFO 'Step 9: Removing C:\ProgramData\ClawFactory.'
try {
    if (Test-Path -LiteralPath $ProgramDataDir) {
        Remove-Item -LiteralPath $ProgramDataDir -Recurse -Force -ErrorAction Stop
        Write-Log INFO 'Removed ProgramData\ClawFactory.'
    }
} catch { Write-Log WARN "ProgramData cleanup failed: $($_.Exception.Message)" }

Write-Log INFO "==== ClawFactory uninstall finished. Log at $LogFile ===="
exit 0
