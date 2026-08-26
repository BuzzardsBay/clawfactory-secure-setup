[CmdletBinding()]
param(
    # Inno's UninstallSilent maps here. Suppresses all UI dialogs.
    [switch]$Silent,
    # Remove the Linux environment (Ubuntu distro, clawuser, openclaw,
    # nftables chains). Default for /SILENT uninstall is RemoveAll=TRUE
    # unless -KeepLinuxEnvironment is also passed.
    [switch]$RemoveAll,
    # Explicit opt-out of DISTRO removal -- and of distro removal only. Useful
    # for /REMOVEALL=0 silent uninstall (e.g. an IT pilot deploy where the
    # Ubuntu image is shared with other tooling).
    #
    # v1.4.2: this is NOT a data-retention switch and never was. ClawFactory is
    # removed from inside the distro either way -- clawuser's home, the agent
    # config, /etc/clawfactory, openclaw, and every ClawFactory unit. The only
    # difference is whether the Ubuntu registration and its VHDX survive. The
    # uninstall dialog used to promise otherwise; the promise had nothing behind
    # it and the copy was corrected rather than the behaviour.
    [switch]$KeepLinuxEnvironment
)

# ClawFactory uninstaller (v1.0.34)
# ---------------------------------
# Invoked from CurUninstallStepChanged(usUninstall) in the .iss [Code] (v1.0.34;
# previously [UninstallRun], which crashed Setup -- see ClawFactory_Install_Lessons_Learned.md L1).
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
        # v1.4.2. Two defects fixed here, both customer-visible in the one dialog
        # where a user decides whether to delete their own data:
        #
        #  1. The old text said "Your conversation history and agent configs stay
        #     on disk" for NO. Nothing in the NO branch preserved agent configs --
        #     it runs `deluser --remove-home clawuser` unconditionally -- so the
        #     product was promising something it does not do. The choice really
        #     on offer is about the DISTRO, not about data, and it now says so.
        #  2. Hard `r`n breaks used to wrap mid-sentence. Each paragraph is now a
        #     single logical line and MessageBox does its own wrapping, so the
        #     defect class is gone rather than re-tuned.
        #
        # Yes still means RemoveAll and Button1 is still Yes: the default button
        # and the silent default must keep selecting the same branch.
        $msg = "Also remove the Ubuntu Linux distro that ClawFactory created?`r`n`r`n" +
               "ClawFactory is removed from this machine either way: the agent, its configuration and plugins, clawuser's home directory, the OpenClaw runtime, and every ClawFactory service and firewall rule.`r`n`r`n" +
               "YES also unregisters the Ubuntu distro and deletes its disk image (about 6 GB). Choose this unless something else on this machine uses that distro.`r`n`r`n" +
               "NO leaves the now-empty Ubuntu distro registered, so anything else that shares it keeps working. You can install ClawFactory again later and it will reuse the distro.`r`n`r`n" +
               "Your ClawChat conversation history is stored on Windows, under %APPDATA%\ClawChat, and neither choice deletes it."
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

#--- 4.5 Remove the ClawFactory Studio per-user component (v1.1.0, JOB 3B) ----
# Studio is a PER-USER NSIS app (installs into %LOCALAPPDATA%\Programs\ClawFactory
# Studio for whoever ran the installer). This uninstaller runs ELEVATED, and Inno's
# ExecAsOriginalUser is NOT available at uninstall time (verified against the Inno
# docs), so we cannot de-elevate here. Instead we locate the per-user Studio
# uninstaller and run it silently.
#
# In the shipping scenario -- Windows Home, one admin user who is ALSO the installing
# user -- an elevated process of that same account shares the account's HKCU and
# %LOCALAPPDATA%, so this removes Studio fully. As a best-effort secondary sweep we
# also scan every user profile on the box. RESIDUAL (documented, not hidden): if a
# DIFFERENT admin account uninstalls while the customer's Studio lives in another
# profile's HKCU, the registry-based lookup for the current user won't find it; the
# profile scan still catches the files. Everything below is LOGGED honestly -- if
# Studio is not found we SAY so; we never claim a clean removal we didn't make.
Write-Log INFO 'Step 4.5: Removing ClawFactory Studio (per-user component).'

function Invoke-StudioUninstaller {
    param([string]$Command, [string]$InstallDir)
    # Parse "<quoted-or-bare exe> <args...>" and ensure a silent (/S) uninstall.
    $exe = $null; $args = ''
    if ($Command -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $args = $Matches[2].Trim() }
    elseif ($Command -match '^\s*(\S+\.exe)\s*(.*)$') { $exe = $Matches[1]; $args = $Matches[2].Trim() }
    else { $exe = $Command.Trim() }
    if (-not (Test-Path -LiteralPath $exe)) { Write-Log WARN "Studio uninstaller not at '$exe'; skipping this candidate."; return $false }
    if ($args -notmatch '(^|\s)/S(\s|$)') { $args = ($args + ' /S').Trim() }
    try {
        Write-Log INFO "Running Studio uninstaller: `"$exe`" $args"
        # NSIS uninstallers copy themselves to %TEMP% and relaunch, so the first
        # process returns before the real work finishes -- poll the install dir.
        Start-Process -FilePath $exe -ArgumentList $args -Wait -ErrorAction Stop
    } catch { Write-Log WARN "Studio uninstaller launch failed: $($_.Exception.Message)"; return $false }
    if ($InstallDir) {
        for ($i = 0; $i -lt 30; $i++) {
            if (-not (Test-Path -LiteralPath $InstallDir)) { break }
            Start-Sleep -Milliseconds 500
        }
    }
    return $true
}

try {
    # Stop any running Studio so its files aren't locked during removal.
    Get-Process 'ClawFactory Studio' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    $studioSelfDir = Join-Path $env:LOCALAPPDATA 'Programs\ClawFactory Studio'
    $candidates    = New-Object System.Collections.Generic.List[object]

    # (1) Installing user's own HKCU uninstall entry (authoritative -- uses whatever
    #     flags electron-builder registered; independent of the uninstaller filename).
    try {
        Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like 'ClawFactory Studio*' } |
            ForEach-Object {
                $cmd = $_.QuietUninstallString; if (-not $cmd) { $cmd = $_.UninstallString }
                if ($cmd) {
                    $dir = $_.InstallLocation; if (-not $dir) { $dir = $studioSelfDir }
                    $candidates.Add([pscustomobject]@{ Command = $cmd; Dir = $dir })
                }
            }
    } catch { Write-Log WARN "Studio HKCU scan failed: $($_.Exception.Message)" }

    # (2) Current user's install dir, in case the registry entry is already gone.
    Get-ChildItem -LiteralPath $studioSelfDir -Filter 'Uninstall*.exe' -ErrorAction SilentlyContinue | ForEach-Object {
        $candidates.Add([pscustomobject]@{ Command = ('"' + $_.FullName + '" /S'); Dir = $studioSelfDir })
    }

    # (3) Best-effort all-users sweep (multi-user boxes).
    try {
        Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $d = Join-Path $_.FullName 'AppData\Local\Programs\ClawFactory Studio'
            Get-ChildItem -LiteralPath $d -Filter 'Uninstall*.exe' -ErrorAction SilentlyContinue | ForEach-Object {
                $candidates.Add([pscustomobject]@{ Command = ('"' + $_.FullName + '" /S'); Dir = $d })
            }
        }
    } catch {}

    # De-dup by uninstaller exe path and run each.
    $ran = $false; $seen = @{}
    foreach ($c in $candidates) {
        $keyMatch = [regex]::Match($c.Command, '"([^"]+)"'); $key = if ($keyMatch.Success) { $keyMatch.Groups[1].Value } else { $c.Command }
        if ($seen.ContainsKey($key.ToLower())) { continue }
        $seen[$key.ToLower()] = $true
        if (Invoke-StudioUninstaller -Command $c.Command -InstallDir $c.Dir) { $ran = $true }
    }

    # Honest verdict -- verify against the current user's install dir.
    if (Test-Path -LiteralPath $studioSelfDir) {
        Write-Log WARN "ClawFactory Studio directory still present for this user ($studioSelfDir); it may need manual removal (right-click the Studio Start Menu entry > Uninstall)."
    } elseif ($ran) {
        Write-Log INFO 'ClawFactory Studio removed.'
    } else {
        Write-Log INFO 'ClawFactory Studio not found for the current user (per-user component; may belong to a different Windows profile). Nothing removed here.'
    }
} catch { Write-Log WARN "Studio removal step failed (non-fatal): $($_.Exception.Message)" }

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
# ---------------------------------------------------------------------------
# 0. Stop the gateway.  v1.4.2, card #287.
#
# This used to be `sudo -u clawuser bash -c 'systemctl --user stop ...' 2>/dev/null`
# with NO XDG_RUNTIME_DIR. Without it systemctl cannot find clawuser's user bus,
# so it never stops anything; the failure was swallowed by the 2>/dev/null; three
# processes survived; and `deluser` below then exited 8 with
#     userdel: user clawuser is currently used by process 222
# leaving clawuser behind, which made the NEXT install abort at
#     Failed to create clawuser (exit=1)
# -- i.e. it falsified the dialog's own "you can install ClawFactory again later".
#
# The line ~15 lines down that does `daemon-reload` already had this right. The
# two are now written the same way, and the stderr is NOT discarded: swallowing it
# is precisely how a two-line defect survived into a release.
# ---------------------------------------------------------------------------
sudo -u clawuser XDG_RUNTIME_DIR=/run/user/1000 systemctl --user stop openclaw-gateway
sudo -u clawuser XDG_RUNTIME_DIR=/run/user/1000 systemctl --user disable openclaw-gateway
# ---------------------------------------------------------------------------
# 1. Disable and stop EVERY unit this product installs, BEFORE deleting anything
#    those units invoke.  v1.4.2, card #285.
#
# The list is derived from the INSTALLER (setup.ps1 + resources/install-*.sh),
# not from what this file used to happen to name. It used to name five of the
# eleven, so a complete teardown still left clawfactory-fw, clawfactory-send and
# the two timers enabled, and no number of re-runs would have disabled them.
#
# Order is the point, not tidiness: v1.4.1 added the egress-refresh disable
# specifically so systemd would not be left with an enabled unit pointing at a
# deleted script, and then deleted clawfactory-fw.service's script while leaving
# that unit enabled -- which is a failed unit in the journal at every future boot
# of a machine that no longer has ClawFactory on it. Disable first, delete second,
# for all eleven or for none.
# ---------------------------------------------------------------------------
CF_UNITS="clawfactory-allow-providers.timer clawfactory-allow-providers.service clawfactory-egress-refresh.service clawfactory-fw.service clawfactory-proxy.service clawfactory-quarantine.service clawfactory-quarantine-gc.timer clawfactory-quarantine-gc.service clawfactory-send.service clawfactory-send-gc.timer clawfactory-send-gc.service"
systemctl disable --now $CF_UNITS
# Flush the clawfactory nft chain (uses iptables on WSL1)
/usr/sbin/nft delete table inet clawfactory 2>/dev/null
# Clear immutable flags so the frozen safety files can be removed (Defect 2/4:
# SOUL.md + workspace SOUL are root:root chattr +i; rm/deluser fail otherwise).
chattr -i /home/clawuser/.openclaw/SOUL.md /home/clawuser/.openclaw/SOUL.md.sha256 /home/clawuser/.openclaw/workspace/SOUL.md 2>/dev/null
# Put the gateway back on its public port (Blocker 1). The proxy unit that owned
# 8787 is already stopped and disabled by step 1, so nothing is left holding the
# port when the drop-in goes.
rm -f /home/clawuser/.config/systemd/user/openclaw-gateway.service.d/clawfactory-real-port.conf 2>/dev/null
sudo -u clawuser XDG_RUNTIME_DIR=/run/user/1000 systemctl --user daemon-reload 2>/dev/null
# Guard 1: delete quarantine. Say how many held files go with it -- these are the
# user's own files, and removing them silently during an uninstall is exactly the
# surprise this guard exists to prevent.
if [ -f /var/lib/clawfactory/quarantine/index.json ]; then
    HELD=$(node -e 'try{console.log(JSON.parse(require("fs").readFileSync("/var/lib/clawfactory/quarantine/index.json")).length)}catch{console.log(0)}' 2>/dev/null || echo 0)
    echo "[uninstall] removing the delete quarantine and the $HELD file(s) still held in it"
fi
# ---------------------------------------------------------------------------
# 2. Unit FILES, and the drop-in directory install-send.sh creates. Everything
#    named here was disabled and stopped in step 1, never the other way round.
# ---------------------------------------------------------------------------
for u in $CF_UNITS; do
    rm -f "/etc/systemd/system/$u" 2>/dev/null
done
rm -rf /etc/systemd/system/clawfactory-allow-providers.service.d 2>/dev/null
# Drift backstop. The explicit list stays the audit trail; this stops a unit that
# a future installer adds and a future edit of CF_UNITS forgets from turning
# "never named" into "left on disk" a second time. It cannot help with ENABLEMENT,
# which is why the named list above is the real fix and this is only a sweep.
rm -f /etc/systemd/system/clawfactory-*.service /etc/systemd/system/clawfactory-*.timer 2>/dev/null
systemctl daemon-reload
# ---------------------------------------------------------------------------
# 3. The helper scripts and binaries those units invoked. INSTALLER-DERIVED:
#    setup.ps1 plus resources/install-*.sh create seventeen files under
#    /usr/local/sbin. This file used to name twelve, so five survived every
#    uninstall -- allow-providers.sh, fw-assert.sh, sendctl, sendctl.js and
#    sendd.js -- together with /usr/local/bin/clawfactory-send.
#    Guard 3's allowlist and both *-ips.map retention files live in
#    /etc/clawfactory, which goes wholesale further down.
# ---------------------------------------------------------------------------
rm -f /usr/local/sbin/clawfactory-allow-providers.sh /usr/local/sbin/clawfactory-dns-resolvers.sh /usr/local/sbin/clawfactory-egress-refresh.sh /usr/local/sbin/clawfactory-fetchctl /usr/local/sbin/clawfactory-fetchctl.js /usr/local/sbin/clawfactory-fw-apply.sh /usr/local/sbin/clawfactory-fw-assert.sh /usr/local/sbin/clawfactory-proxy.js /usr/local/sbin/clawfactory-quarantinectl.js /usr/local/sbin/clawfactory-quarantined.js /usr/local/sbin/clawfactory-read-fetch.sh /usr/local/sbin/clawfactory-sendctl /usr/local/sbin/clawfactory-sendctl.js /usr/local/sbin/clawfactory-sendd.js /usr/local/sbin/clawfactory-spend-check.js /usr/local/sbin/clawfactory-toolchain.sh /usr/local/sbin/clawfactory-turn-gate.sh 2>/dev/null
rm -f /usr/local/sbin/clawfactory-* /usr/local/bin/clawfactory-send 2>/dev/null
# Undo the /usr/bin/rm divert BEFORE removing anything the wrapper depends on.
#
# Guard 1 takes over the name `rm` via dpkg-divert. If an uninstall left that in
# place, the user would be left with a node wrapper as their system rm and no
# broker behind it. That is our bug to prevent, on their machine, after they
# asked us to leave. Restore the stock binary and PROVE it works before moving on.
if command -v dpkg-divert >/dev/null 2>&1 && dpkg-divert --list /usr/bin/rm | grep -q 'rm.real'; then
    # Delete OUR wrapper first: --rename refuses to move the real binary back
    # while something else occupies the name.
    if head -1 /usr/bin/rm 2>/dev/null | grep -q node; then
        /usr/bin/rm.real -f /usr/bin/rm 2>/dev/null || rm -f /usr/bin/rm 2>/dev/null
    fi
    dpkg-divert --rename --remove /usr/bin/rm 2>/dev/null
fi
# Fail loud rather than leave a box that cannot delete files.
if [ ! -x /usr/bin/rm ] || head -1 /usr/bin/rm 2>/dev/null | grep -q node; then
    [ -x /usr/bin/rm.real ] && cp -a /usr/bin/rm.real /usr/bin/rm 2>/dev/null
    echo "[uninstall] WARNING: /usr/bin/rm was not restored cleanly. The stock binary is at /usr/bin/rm.real; restore it with: cp -a /usr/bin/rm.real /usr/bin/rm" >&2
else
    echo "[uninstall] /usr/bin/rm divert removed; stock rm restored"
fi
rm -rf /usr/local/lib/clawfactory /var/lib/clawfactory 2>/dev/null
rm -rf /etc/clawfactory 2>/dev/null
# Remove the openclaw global install
rm -rf /usr/lib/node_modules/openclaw 2>/dev/null
rm -f /usr/bin/openclaw /usr/local/bin/openclaw /bin/openclaw 2>/dev/null
# ---------------------------------------------------------------------------
# 4. clawuser.  v1.4.2, card #287, second half.
#
# Stopping the gateway can fail for reasons other than the missing
# XDG_RUNTIME_DIR fixed at the top of this script, and `deluser` refuses to
# remove an account that still owns a live process: it exits 8 and says
# "user clawuser is currently used by process N". The old code sent that to
# /dev/null and carried on, so a surviving clawuser was indistinguishable from a
# clean removal -- until the next install aborted at Failed to create clawuser.
# Verify the processes are gone, escalate once, verify again, and REPORT.
# ---------------------------------------------------------------------------
CF_PROCS=$(pgrep -u clawuser 2>/dev/null | wc -l)
if [ "$CF_PROCS" != "0" ]; then
    echo "[uninstall] clawuser still owns $CF_PROCS process(es) after the gateway stop; terminating them"
    pkill -u clawuser 2>/dev/null
    for i in 1 2 3 4 5 6 7 8 9 10; do
        CF_PROCS=$(pgrep -u clawuser 2>/dev/null | wc -l)
        if [ "$CF_PROCS" = "0" ]; then break; fi
        sleep 1
    done
    if [ "$CF_PROCS" != "0" ]; then
        pkill -KILL -u clawuser 2>/dev/null
        for i in 1 2 3 4 5; do
            CF_PROCS=$(pgrep -u clawuser 2>/dev/null | wc -l)
            if [ "$CF_PROCS" = "0" ]; then break; fi
            sleep 1
        done
    fi
fi
if [ "$CF_PROCS" != "0" ]; then
    echo "[uninstall] ERROR: clawuser still owns $CF_PROCS process(es); deluser is expected to fail with exit 8" >&2
fi
# NOT 2>/dev/null. That redirect is why a two-line defect survived to a release.
deluser --remove-home clawuser
# Drop the WSL default-user line we added
sed -i '/^\[user\]/,/^$/d' /etc/wsl.conf 2>/dev/null
# ---------------------------------------------------------------------------
# 5. Read back what is actually left and print a terminal marker the Windows side
#    can REQUIRE.  v1.4.2, card #286.
#
# The caller used to assign this whole invocation to $null and then log
# "In-distro ClawFactory artifacts removed" unconditionally, so a teardown that
# executed half of itself reported success and reached a release. The teardown now
# states what it left, and the caller checks the marker rather than assuming it.
#
# Enablement is counted from the .wants symlinks on disk rather than from
# `systemctl list-unit-files`, so a systemctl that cannot run reads as an error
# instead of silently reading as zero.
# ---------------------------------------------------------------------------
LEFT=""
id clawuser >/dev/null 2>&1 && LEFT="$LEFT clawuser"
[ -d /home/clawuser ] && LEFT="$LEFT /home/clawuser"
[ -d /etc/clawfactory ] && LEFT="$LEFT /etc/clawfactory"
[ -e /usr/bin/openclaw ] && LEFT="$LEFT /usr/bin/openclaw"
[ -d /usr/lib/node_modules/openclaw ] && LEFT="$LEFT /usr/lib/node_modules/openclaw"
[ -d /var/lib/clawfactory ] && LEFT="$LEFT /var/lib/clawfactory"
[ -d /usr/local/lib/clawfactory ] && LEFT="$LEFT /usr/local/lib/clawfactory"
N_UNITS=$(ls -1d /etc/systemd/system/clawfactory-* 2>/dev/null | wc -l)
N_SBIN=$(ls -1d /usr/local/sbin/clawfactory-* 2>/dev/null | wc -l)
N_ENABLED=$(ls -1d /etc/systemd/system/*.wants/clawfactory-* 2>/dev/null | wc -l)
echo "[uninstall] READBACK units=$N_UNITS sbin=$N_SBIN enabled=$N_ENABLED left=[$LEFT ]"
if [ -z "$LEFT" ] && [ "$N_UNITS" = "0" ] && [ "$N_SBIN" = "0" ] && [ "$N_ENABLED" = "0" ]; then
    echo CLAWFACTORY_TEARDOWN_OK
else
    echo CLAWFACTORY_TEARDOWN_INCOMPLETE
fi
'@
        # -------------------------------------------------------------------
        # v1.4.2, card #284: LF-normalise the payload before transporting it.
        #
        # THE MECHANISM, stated so anyone can check it: this file is stored LF in
        # git but `*.ps1 text eol=lf` was added AFTER it was first checked out, and
        # git never re-normalises an existing working copy. The build machine's
        # working tree was therefore CRLF, Inno compiles from the working tree, and
        # PowerShell's here-string preserves the file's own line endings. Every
        # line of this payload consequently arrived inside WSL ending in a CR.
        # Running as root, a trailing CR only lands on the last word of each
        # line -- always `2>/dev/null` -- and root can create /dev/null<CR>, so
        # every SIMPLE command still ran with the right arguments. The first line
        # needing a RESERVED word, `if [ -f ... ]; then`, saw `then<CR>` instead of
        # `then`, and bash abandoned the rest of the script with
        #     syntax error: unexpected end of file
        # `set +e` cannot help: a parse error is fatal regardless, and `set +e<CR>`
        # had itself already failed as an invalid option. That is the exact split
        # measured on cfv-176 -- the two units named before the first `if` removed,
        # the nine named after it untouched.
        #
        # Reproduced with a control before this fix was written: LF as root ran all
        # six markers, CRLF as root ran the three before the first `if` and none
        # after, exit 2, `bash: line 11: syntax error: unexpected end of file`.
        #
        # Every other PowerShell->WSL transport in this product already did this --
        # setup.ps1 Invoke-WslBash, bootstrap.ps1, post-install.ps1,
        # switch-provider.ps1, clawfactory-grants.ps1 and all six $lfB64 lambdas.
        # This site and resources/launcher.ps1 were the two that did not.
        # Normalising here makes the teardown correct regardless of how any future
        # clone happens to have its line endings configured.
        # -------------------------------------------------------------------
        $script = $script.Replace("`r`n", "`n").Replace("`r", "`n")
        $teardownOut = @()
        $teardownOk  = $false
        if ($script.IndexOf([char]13) -ge 0) {
            # Cannot happen after the two Replace calls above; asserted rather than
            # assumed, because the whole defect was a silent truncation.
            Write-Log ERROR 'Teardown payload still contains a CR after normalisation. Refusing to send it: bash would abandon it at the first reserved word and report nothing.'
        } else {
            $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
            # card #286: capture it. This used to be `$null = ... 2>&1`, which threw
            # away the only evidence that the teardown had stopped half way.
            $raw = & wsl.exe -d Ubuntu -u root -- bash -lc "echo $enc | base64 -d | bash" 2>&1
            $rc  = $LASTEXITCODE
            $teardownOut = @($raw | ForEach-Object { "$_" })
            foreach ($line in $teardownOut) {
                if ($line -and $line.Trim()) { Write-Log INFO "  [in-distro] $($line.Trim())" }
            }
            Write-Log INFO "In-distro teardown exit code = $rc"
            $teardownOk = ($rc -eq 0) -and ($teardownOut -contains 'CLAWFACTORY_TEARDOWN_OK')
        }

        if ($teardownOk) {
            Write-Log INFO 'In-distro ClawFactory artifacts removed, verified by read-back inside the distro; Ubuntu distro left registered.'
        } else {
            # An uninstall that ABORTS leaves the user unable to remove the product,
            # which is worse than an incomplete removal. So: finish the Windows-side
            # uninstall, log the failure as a failure, and tell the user what is left
            # and how to remove it. What must never happen again is the third option,
            # which is what shipped: report success having removed nothing.
            $readback = @($teardownOut | Where-Object { $_ -like '*READBACK*' }) -join ' '
            Write-Log ERROR 'In-distro teardown did NOT complete. ClawFactory files remain inside the Ubuntu distro.'
            if ($readback) { Write-Log ERROR "Read-back from inside the distro: $readback" }
            Write-Log ERROR 'The rest of the uninstall will still finish. To clear the Linux side by hand, open a terminal and run:  wsl -d Ubuntu -u root'
            if (-not $Silent) {
                try {
                    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                    $warn = "ClawFactory has been removed from Windows, but it could not finish cleaning up inside the Ubuntu Linux distro you chose to keep.`r`n`r`n" +
                            "What is left: $(if ($readback) { $readback } else { 'see the log' })`r`n`r`n" +
                            "To remove the rest, open a terminal and run:  wsl -d Ubuntu -u root`r`n`r`n" +
                            "The full log is at $LogFile."
                    [void][System.Windows.Forms.MessageBox]::Show(
                        $warn, 'ClawFactory Uninstall - Linux cleanup incomplete',
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Warning)
                } catch { Write-Log WARN "Could not show the incomplete-teardown dialog: $($_.Exception.Message)" }
            }
        }
    } catch { Write-Log ERROR "In-distro teardown threw: $($_.Exception.Message). ClawFactory files may remain inside the Ubuntu distro." }
}

#--- 7. HKLM\SOFTWARE\ClawFactory --------------------------------------------
Write-Log INFO 'Step 7: Removing HKLM\SOFTWARE\ClawFactory.'
try {
    if (Test-Path 'HKLM:\SOFTWARE\ClawFactory') {
        Remove-Item -Path 'HKLM:\SOFTWARE\ClawFactory' -Recurse -Force -ErrorAction Stop
        Write-Log INFO 'Removed HKLM\SOFTWARE\ClawFactory.'
    }
} catch { Write-Log WARN "HKLM cleanup failed: $($_.Exception.Message)" }

#--- 8. ProgramData -- delete last so we can read state files above ---------
Write-Log INFO 'Step 8: Removing C:\ProgramData\ClawFactory.'
try {
    if (Test-Path -LiteralPath $ProgramDataDir) {
        Remove-Item -LiteralPath $ProgramDataDir -Recurse -Force -ErrorAction Stop
        Write-Log INFO 'Removed ProgramData\ClawFactory.'
    }
} catch { Write-Log WARN "ProgramData cleanup failed: $($_.Exception.Message)" }

Write-Log INFO "==== ClawFactory uninstall finished. Log at $LogFile ===="
exit 0
