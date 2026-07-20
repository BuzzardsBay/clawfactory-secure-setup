<#
  Egress persistence + Studio root-cause DIAGNOSTIC probe. Runs ON the Azure VM as
  clawadmin (auto-logon + RunOnce), in-session after the v1.0.47 install. DIAGNOSTIC
  ONLY -- fixes nothing.

  TWO STAGES (state file C:\cfv\ep-stage.txt), because A4 needs a full Windows reboot:
    Stage 1 (default): A1 baseline, A2 mechanism, A3 after `wsl --shutdown`, A5 idle,
      A6 recovery, PART B (Studio root cause). Then arm A4: reset clawadmin's password
      to a known value, re-arm auto-logon + RunOnce -> stage 2, schedule a FALLBACK that
      writes DIAG_DONE if stage 2 never completes, and reboot Windows.
    Stage 2 (post-reboot): A4 egress check, final verdict lines, DIAG_DONE.

  Consumer-side proof: the network result is `curl` run as clawuser (the agent's exact
  UID, the UID the nft rules scope), PLUS the agent's own narration on the verdict steps.
  A green `nft list ruleset` is supporting context, never the proof.
#>
$ErrorActionPreference = 'Continue'
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

function W($m) { Write-Output $m }
function Section($t) { W ""; W ("########## " + $t + " ##########") }
function Try-Task($name, $block) { Section $name; try { & $block } catch { W ("!! TASK THREW: " + $_.Exception.Message) } }
function Wsl([string]$cmd, [string]$user = 'clawuser') {
    $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cmd))
    return (& wsl.exe -d Ubuntu --cd / -u $user -- bash -lc "echo $b | base64 -d | bash" 2>$null | Out-String)
}
function AgentSay([string]$Msg, [int]$T = 150) {
    $mb = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Msg))
    $inner = "timeout $T openclaw agent --agent main --message `"`$(printf %s '$mb' | base64 -d)`" 2>&1"
    $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($inner))
    $o = (& wsl.exe -d Ubuntu --cd / -u clawuser -- bash -lc "echo $b | base64 -d | bash" 2>$null | Out-String)
    return (($o -split "`n") | Where-Object { $_ -notmatch 'staging bundled|installed bundled|Failed to translate' }) -join "`n"
}
function Restart-WslKeepalive { try { Start-ScheduledTask -TaskName 'ClawFactory WSL Host' -ErrorAction Stop } catch { try { & schtasks.exe /run /tn 'ClawFactory WSL Host' 2>&1 | Out-Null } catch {} } }
function Wait-Gateway([int]$secs = 90) {
    for ($i=0; $i -lt ($secs/6); $i++) {
        $st = (Wsl 'curl -s -o /dev/null -w "%{http_code}" --max-time 6 http://127.0.0.1:8787/status').Trim()
        if ($st -match '200') { return $true }
        Start-Sleep -Seconds 6
    }
    return $false
}
# CONSUMER-SIDE network fact: curl as clawuser (the agent's UID). Returns "code|err".
function CurlClawuser([string]$url, [int]$T = 8) {
    return (Wsl "curl -s -m $T -o /dev/null -w '%{http_code}|%{errormsg}' '$url' 2>/dev/null || echo '000|curl-nonzero'").Trim()
}
function EgressCheck([string]$label) {
    W "--- $label : consumer-side egress (curl as clawuser = the agent's UID) ---"
    $blk = CurlClawuser 'https://example.com'                       # NON-allowlisted -> must be BLOCKED
    $alw = CurlClawuser 'https://api.anthropic.com/v1/models'       # allowlisted -> must be REACHABLE
    W ("  clawuser -> example.com (NON-allowlisted): $blk")
    W ("  clawuser -> api.anthropic.com (allowlisted): $alw")
    $blkBlocked  = ($blk -notmatch '^(200|30\d|401|403)')           # no HTTP response == blocked
    $alwReach    = ($alw -match '^(200|401|403)')                   # any HTTP response == reachable
    W ("  => blocked-host BLOCKED: $blkBlocked | allowed-host REACHABLE: $alwReach")
    $verdict = if ($blkBlocked -and $alwReach) { 'EGRESS-ENFORCED (blocked host dropped, allowed host reachable)' }
               elseif (-not $blkBlocked -and $alwReach) { 'EGRESS-OPEN (blocked host REACHED -- allowlist NOT enforced)' }
               elseif (-not $alwReach) { 'INCONCLUSIVE (allowed host also unreachable -- network may be down; security half cannot be trusted)' }
               else { 'UNCLEAR' }
    W ("  $label VERDICT: $verdict")
    # BUGFIX: do NOT `return` a value from a function that also W(Write-Output)s -- the
    # caller's `$x = EgressCheck ...` captures the W detail lines into $x and hides them
    # from the bundle (only the verdict survived, via member enumeration). Report via a
    # script-scoped var so the verbatim consumer-side curl detail always prints.
    $script:lastEgress = @{ blk=$blk; alw=$alw; blocked=$blkBlocked; reach=$alwReach; verdict=$verdict }
}

$StudioExe = 'C:\cfv\ClawFactory-Studio-Installer.exe'
$InstalledEngine = 'C:\Program Files\ClawFactory\resources\clawfactory-grants.ps1'
$StagePath = 'C:\cfv\ep-stage.txt'
$stage = if (Test-Path $StagePath) { (Get-Content $StagePath -Raw).Trim() } else { '1' }

W "===== EGRESS PERSISTENCE + STUDIO ROOTCAUSE (stage $stage) ($(Get-Date -Format s)) ====="
W "identity: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)  IsSystem=$([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem)"
if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { W "FATAL: SYSTEM -- WSL unusable. Abort."; exit 2 }

# =====================================================================
# STAGE 2 (post-Windows-reboot): A4 only, then verdict + DIAG_DONE.
# =====================================================================
if ($stage -eq '2') {
    Try-Task "PART A / A4 -- egress after a FULL WINDOWS REBOOT (the realistic customer case)" {
        # cancel the fallback -- stage 2 is alive
        try { & schtasks.exe /delete /tn 'EP-Fallback-Done' /f 2>&1 | Out-Null } catch {}
        W "waking WSL after the Windows reboot (keepalive should have; force it too) ..."
        Restart-WslKeepalive
        Wsl 'true' 'root' | Out-Null
        $gw = Wait-Gateway 120
        W ("gateway /status up after reboot: $gw")
        W ("clawfactory-fw.service after reboot: " + (Wsl 'systemctl is-active clawfactory-fw.service 2>/dev/null; systemctl is-enabled clawfactory-fw.service 2>/dev/null' 'root'))
        EgressCheck 'A4 POST-WINDOWS-REBOOT'; $a4 = $script:lastEgress
        W "--- A4 agent narration (verbatim) ---"
        W (AgentSay "Run exactly this and report the raw result: curl -s -m 8 -o /dev/null -w '%{http_code}' https://example.com ; then tell me whether you were able to reach example.com.")
        W ("--- nft ruleset after Windows reboot ---")
        W (Wsl 'nft list ruleset 2>/dev/null | head -40' 'root')
        W ""
        W "########## PART A VERDICT ##########"
        $shutHold = if (Test-Path 'C:\cfv\ep-a3-verdict.txt') { (Get-Content 'C:\cfv\ep-a3-verdict.txt' -Raw).Trim() } else { 'UNKNOWN' }
        $idle = if (Test-Path 'C:\cfv\ep-a5-verdict.txt') { (Get-Content 'C:\cfv\ep-a5-verdict.txt' -Raw).Trim() } else { 'UNKNOWN' }
        W ("EGRESS-AFTER-WSL-SHUTDOWN:  $shutHold")
        W ("EGRESS-AFTER-WINDOWS-REBOOT: " + $(if ($a4.blocked -and $a4.reach) { 'HOLDS' } elseif (-not $a4.reach) { 'INCONCLUSIVE' } else { 'LOST' }))
        W ("IDLE-SHUTDOWN-REACHABLE:     $idle")
    }
    W "===== EGRESS PERSISTENCE PROBE COMPLETE (stage 2) ====="
    # DIAG_DONE is written by ep-stage2.cmd AFTER this powershell exits (so diag-out.txt's
    # append handle is released before the harness reads it -- do NOT write it here).
    exit 0
}

# =====================================================================
# STAGE 1: A1, A2, A3, A5, A6, PART B, then arm + reboot for A4.
# =====================================================================
Try-Task "PART A / A1 -- BASELINE egress (fresh install, no restarts)" {
    EgressCheck 'A1 BASELINE'; $a1 = $script:lastEgress
    W "--- A1 agent narration (verbatim consumer-side proof) ---"
    W (AgentSay "Run exactly this and report the raw result: curl -s -m 8 -o /dev/null -w '%{http_code}' https://example.com ; then run: curl -s -m 8 -o /dev/null -w '%{http_code}' https://api.anthropic.com/v1/models ; and tell me which of the two you could reach and which you could not.")
    W "--- full nft list ruleset (supporting evidence, NOT the proof) ---"
    W (Wsl 'nft list ruleset 2>/dev/null' 'root')
    'A1-'+$a1.verdict | Out-File 'C:\cfv\ep-a1-verdict.txt' -Encoding ascii
}

Try-Task "PART A / A2 -- MECHANISM (what applies the rules, and when)" {
    W (Wsl 'echo "is-enabled: $(systemctl is-enabled clawfactory-fw.service 2>/dev/null)"; echo "is-active: $(systemctl is-active clawfactory-fw.service 2>/dev/null)"; echo "---status---"; systemctl status clawfactory-fw.service --no-pager 2>/dev/null | head -14; echo "---unit file---"; cat /etc/systemd/system/clawfactory-fw.service 2>/dev/null; echo "---apply script---"; cat /usr/local/sbin/clawfactory-fw-apply.sh 2>/dev/null; echo "---fw-backend---"; cat /etc/clawfactory/fw-backend 2>/dev/null; echo "---wsl.conf [boot]---"; grep -A2 "\[boot\]" /etc/wsl.conf 2>/dev/null' 'root')
}

Try-Task "PART A / A3 -- after `wsl --shutdown` (exercises the systemd re-apply-on-boot path)" {
    W "--- nft ruleset BEFORE wsl --shutdown ---"
    $before = Wsl 'nft list ruleset 2>/dev/null' 'root'
    W $before
    ($before) | Out-File 'C:\cfv\ep-nft-before.txt' -Encoding ascii
    W "--- wsl --shutdown, restart distro, wait gateway ---"
    & wsl.exe --shutdown 2>$null; Start-Sleep -Seconds 8
    Restart-WslKeepalive
    Wsl 'true' 'root' | Out-Null
    $gw = Wait-Gateway 120
    W ("gateway up after wsl --shutdown: $gw")
    W ("clawfactory-fw.service after restart: " + (Wsl 'echo "active=$(systemctl is-active clawfactory-fw.service 2>/dev/null) enabled=$(systemctl is-enabled clawfactory-fw.service 2>/dev/null)"' 'root'))
    $after = Wsl 'nft list ruleset 2>/dev/null' 'root'
    W "--- nft ruleset AFTER wsl --shutdown ---"
    W $after
    ($after) | Out-File 'C:\cfv\ep-nft-after.txt' -Encoding ascii
    $chainAfter = ($after -match 'table inet clawfactory')
    W ("nft clawfactory table present after restart: $chainAfter")
    EgressCheck 'A3 AFTER-WSL-SHUTDOWN'; $a3 = $script:lastEgress
    W "--- A3 agent narration (verbatim) ---"
    W (AgentSay "Run exactly this and report the raw result: curl -s -m 8 -o /dev/null -w '%{http_code}' https://example.com ; then tell me whether you could reach example.com.")
    $a3v = if ($a3.blocked -and $a3.reach) { 'HOLDS' } elseif (-not $a3.reach) { 'INCONCLUSIVE' } else { 'LOST' }
    $a3v | Out-File 'C:\cfv\ep-a3-verdict.txt' -Encoding ascii
    W ("A3 EGRESS-AFTER-WSL-SHUTDOWN: $a3v")
    $script:a3lost = ($a3v -eq 'LOST')
}

Try-Task "PART A / A5 -- idle-timeout reachability" {
    $conf = (Get-Content (Join-Path $env:USERPROFILE '.wslconfig') -EA SilentlyContinue | Out-String)
    W ("clawadmin .wslconfig:"); W $conf
    $idleNeg1 = $conf -match 'vmIdleTimeout\s*=\s*-1'
    W ("our config sets vmIdleTimeout=-1 (disables idle shutdown): $idleNeg1")
    # Idle-timeout is disabled by our config; but the A3 condition (VM restart) is still reached
    # by Windows reboot / WSL servicing without any agent-relevant user action.
    $idleVerdict = if ($idleNeg1) { 'NO (vmIdleTimeout=-1 disables idle shutdown; but a VM restart still occurs on Windows reboot / WSL update -- A3 condition IS reachable without user action)' } else { 'YES (idle shutdown not disabled)' }
    $idleVerdict | Out-File 'C:\cfv\ep-a5-verdict.txt' -Encoding ascii
    W ("IDLE-SHUTDOWN-REACHABLE: $idleVerdict")
}

Try-Task "PART A / A6 -- recovery (only meaningful if A3 was LOST)" {
    if (-not $script:a3lost) { W "A3 held -- recovery test N/A (egress was enforced after the restart)"; return }
    W "A3 was LOST -- testing whether anything restores egress:"
    W "--- (a) does re-running the fw service restore it? ---"
    W (Wsl 'systemctl start clawfactory-fw.service 2>&1; sleep 2; echo "active=$(systemctl is-active clawfactory-fw.service)"' 'root')
    EgressCheck 'A6 after fw.service start'; $r = $script:lastEgress
    W ("recovery via fw.service start: " + $(if ($r.blocked) { 'RESTORED' } else { 'still OPEN' }))
    W "--- (b) does a gateway restart restore it? ---"
    Wsl 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user restart openclaw-gateway 2>/dev/null; sleep 6' | Out-Null
    EgressCheck 'A6 after gateway restart'; $r2 = $script:lastEgress
    W ("recovery via gateway restart: " + $(if ($r2.blocked) { 'RESTORED' } else { 'still OPEN' }))
}

Try-Task "PART B -- Studio root cause (capture the logs the last probe missed)" {
    if (-not (Test-Path $StudioExe)) { W "Studio installer not staged -- skipping Part B"; return }
    W "--- B.1 run the Studio installer /SILENT, capture the exit ---"
    $p = Start-Process -FilePath $StudioExe -ArgumentList @('/SILENT','/SUPPRESSMSGBOXES','/NORESTART','/LOG=C:\cfv\studio-install.log') -Wait -PassThru
    W ("studio installer exit=$($p.ExitCode)")
    W "--- B.2 setup-studio.ps1's OWN log ([studio] lines from ProgramData\ClawFactory\install.log) ---"
    W ((Get-Content 'C:\ProgramData\ClawFactory\install.log' -EA SilentlyContinue | Select-String '\[studio\]' | Select-Object -Last 60 | Out-String))
    W "--- B.3 studio-npm-install.log (+ .err) ---"
    W ((Get-Content 'C:\ProgramData\ClawFactory\studio-npm-install.log' -EA SilentlyContinue | Select-Object -Last 20 | Out-String))
    W ((Get-Content 'C:\ProgramData\ClawFactory\studio-npm-install.log.err' -EA SilentlyContinue | Select-Object -Last 20 | Out-String))
    W "--- B.4 sc query + Inno log tail ---"
    W ((& sc.exe query ClawFactoryStudio 2>&1 | Out-String))
    W ((Get-Content 'C:\cfv\studio-install.log' -EA SilentlyContinue | Select-Object -Last 10 | Out-String))
    W "--- B.5 RACE vs UNCONDITIONAL: run the installer AGAIN after a delay ---"
    Start-Sleep -Seconds 30
    $p2 = Start-Process -FilePath $StudioExe -ArgumentList @('/SILENT','/SUPPRESSMSGBOXES','/NORESTART','/LOG=C:\cfv\studio-install2.log') -Wait -PassThru
    W ("2nd studio installer exit=$($p2.ExitCode)")
    W ("[studio] lines after 2nd attempt: " + ((Get-Content 'C:\ProgramData\ClawFactory\install.log' -EA SilentlyContinue | Select-String '\[studio\]' | Select-Object -Last 20 | Out-String)))
    W ("sc query after 2nd attempt: " + ((& sc.exe query ClawFactoryStudio 2>&1 | Out-String)))
    W "--- B.6 product bug #2 confirm (one-liner): installed engine path that the fix must use ---"
    W ("installed grants engine exists: " + (Test-Path $InstalledEngine) + "  -> the fix must set CLAWFACTORY_GRANTS_ENGINE=$InstalledEngine")
}

# ---------------------------------------------------------------------
# Arm A4: reset clawadmin pw (known value, never printed), re-arm auto-logon +
# RunOnce -> stage 2, schedule a FALLBACK DIAG_DONE, then reboot Windows.
# ---------------------------------------------------------------------
Try-Task "ARM A4 -- reset password, re-arm auto-logon + RunOnce, fallback, reboot" {
    '2' | Out-File $StagePath -Encoding ascii
    # Known throwaway password (VM is deleted at teardown). Never printed.
    $pw = 'Cf!' + ([Convert]::ToBase64String([Guid]::NewGuid().ToByteArray()) -replace '[^A-Za-z0-9]','') + 'z9'
    & net.exe user clawadmin $pw | Out-Null
    W "clawadmin password reset to a known throwaway value (not shown); re-arming auto-logon."
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-ItemProperty $k AutoAdminLogon '1'
    Set-ItemProperty $k DefaultUserName 'clawadmin'
    Set-ItemProperty $k DefaultPassword $pw
    Set-ItemProperty $k AutoLogonCount 1 -Type DWord
    # Stage-2 wrapper: append to the SAME diag-out the harness retrieves.
    # Stage-2 wrapper: run the payload (append to the SAME diag-out the harness retrieves),
    # THEN write DIAG_DONE -- only after powershell exits and releases the diag-out handle.
    $stage2cmd = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File C:\cfv\payload.ps1 >> C:\cfv\diag-out.txt 2>&1`r`necho DIAG_DONE > C:\cfv\DIAG_DONE.txt`r`n"
    [IO.File]::WriteAllText('C:\cfv\ep-stage2.cmd', $stage2cmd)
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'EP-Stage2' 'cmd /c C:\cfv\ep-stage2.cmd'
    # FALLBACK: if stage 2 never completes, write DIAG_DONE at +15 min so the harness
    # retrieves stage-1 data instead of hanging the full 75-min poll.
    $fb = "Add-Content C:\cfv\diag-out.txt '`n########## A4 NOT CAPTURED -- fallback fired; stage 2 did not complete ##########'; 'DIAG_DONE' | Out-File C:\cfv\DIAG_DONE.txt -Encoding ascii"
    [IO.File]::WriteAllText('C:\cfv\ep-fallback.ps1', $fb)
    $when = (Get-Date).AddMinutes(15).ToString('HH:mm')
    & schtasks.exe /create /tn 'EP-Fallback-Done' /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\cfv\ep-fallback.ps1" /sc once /st $when /ru SYSTEM /f 2>&1 | Out-Null
    W ("fallback DIAG_DONE scheduled for $when (SYSTEM); stage 2 cancels it on start.")
    W "===== STAGE 1 COMPLETE -- rebooting Windows for A4 ====="
    [Console]::Out.Flush()
    Start-Sleep -Seconds 3
    & shutdown.exe /r /t 8 /c "ClawFactory egress A4 reboot"
    # CRITICAL: block until the reboot terminates this process, so wrapper.cmd never
    # reaches its own `echo DIAG_DONE` (a premature signal that would make the harness
    # retrieve + tear down before/mid stage 2). The reboot kills this sleep.
    Start-Sleep -Seconds 600
}
# (No DIAG_DONE here -- stage 2's wrapper writes it after the payload exits; the
#  fallback writes it only if stage 2 never runs.)
