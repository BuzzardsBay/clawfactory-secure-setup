<#
  BOX D: THE NEXT BOOT OF A DISTRO THE USER CHOSE TO KEEP.

  THE PROPERTY
  ------------
  A keep-Linux uninstall leaves the Ubuntu distro registered and in use. The
  claim v1.4.2 card #285 makes is that nothing ClawFactory installed runs at the
  NEXT boot of that distro -- not merely that the files are gone now. Those are
  different claims: `systemctl disable` and `rm` are separate operations, and
  v1.4.1 shipped a teardown that deleted clawfactory-fw.service's script while
  leaving the unit ENABLED, which is a failed unit in the journal at every future
  boot of a machine whose owner believes they have uninstalled the product.

  WHY A DISTRO RESTART IS THE RIGHT SUBJECT
  -----------------------------------------
  The units are inside the distro, so the boot that matters is the distro's. A
  full Windows reboot also restarts the distro but costs an interactive login,
  and it tests strictly more than the claim needs. What is NOT claimed here is
  anything about the Windows side across a Windows reboot; that is stated rather
  than blurred.

  THE TWO CONTROLS, WITHOUT WHICH EVERY READING BELOW IS EMPTY
  -----------------------------------------------------------
  NB.CTL.RESTART  the boot_id CHANGED. Without a proven restart, an unchanged
                  unit list proves only that nothing happened. This is the
                  RD.CTL2 shape that made the PG.3f rig durability result mean
                  something on box B.
  NB.CTL.QUERY    `systemctl list-unit-files` returns rows for a glob that MUST
                  match on any Ubuntu. A systemctl that cannot reach a running
                  systemd prints nothing and exits nonzero, and "nothing is
                  enabled" then reads exactly like a clean box. This is the
                  single most likely way this probe could report a false PASS.

  CLAUSE 2: the ClawFactory unit reading is CLASSIFIED, not tested for absence.
      NONE_LISTED         systemctl knows of no clawfactory-* unit at all
      LISTED_NOT_ENABLED  unit files exist but none is enabled
      SOME_ENABLED        at least one is enabled -- the defect
      QUERY_FAILED        systemctl could not answer, so nothing was measured
#>
param(
    [string]$Transcript  = 'C:\cfv\nextboot-out-probe.txt',
    [string]$ResultsJson = 'C:\cfv\nextboot-results.json',
    [string]$LibDir      = 'C:\cfv',
    [string]$Distro      = 'Ubuntu',
    # DRY-RUN SEAM ONLY. Skips the `wsl --shutdown` call so the classifier and
    # both controls can be exercised against rigged readings on the build machine
    # without touching that machine's own WSL. It deliberately does NOT excuse
    # NB.CTL.RESTART: the control still evaluates the two boot_id values it was
    # handed, so a rig that forgets to change them fails the control exactly as a
    # real distro that did not restart would. Never passed on a box.
    [switch]$SkipShutdown
)

$ErrorActionPreference = 'Continue'
. (Join-Path $LibDir 'interim-v120-wslchan.ps1')
. (Join-Path $LibDir 'interim-v120-phaselib.ps1')

Start-Phase -Name 'ClawFactory v1.4.4 box D: the next boot of the kept distro' `
    -Transcript $Transcript -Sentinel 'NEXTBOOT_PROBE_COMPLETE'

function Finish($code) { W ''; W "NEXTBOOT_PROBE_COMPLETE rc=$code"; exit $code }
function Val([string]$text, [string]$key) {
    if ($text -match "(?m)^$([regex]::Escape($key))=(.*)$") { return $Matches[1].Trim() }
    return '(not reported)'
}

$chan = Test-WslChannel
Register-Control -Id 'NB.CHAN' -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'NEXTBOOT'; Finish 2 }

Section '1. The boot_id BEFORE the restart'
$b4 = Invoke-WslFile -Tag 'nb-before' -User 'root' -Body @'
echo "BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
echo "UPTIME=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)"
'@
foreach ($ln in @($b4.Out -split "`r?`n" | Where-Object { $_.Trim() })) { W "   PRE> $ln" }
$bootBefore = Val $b4.Out 'BOOT_ID'

if (-not $SkipShutdown) {
    Section '2. Restart the distro. Not a sleep: the boot_id below is what proves it happened'
    W 'wsl --shutdown'
    $null = & wsl.exe --shutdown 2>&1
    W "wsl --shutdown exit=$LASTEXITCODE"
    Start-Sleep -Seconds 8
} else {
    Section '2. Shutdown call skipped (-SkipShutdown, dry-run seam). NB.CTL.RESTART still decides.'
}

Section '3. The reading, taken on the distro as it now stands'
$after = Invoke-WslFile -Tag 'nb-after' -User 'root' -Body @'
echo "BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
echo "SYSTEM_STATE=$(systemctl is-system-running 2>&1 | head -1)"
echo "--CTLQUERY--"
systemctl list-unit-files 'systemd-*' --no-pager --no-legend 2>/dev/null | head -5
echo "--END-CTLQUERY--"
# No `echo "RC=$?"` here on purpose. In a pipeline $? is the LAST command's
# status, and after the echo above it is the echo's. The control below counts
# ROWS and reads /run/systemd/system instead, which cannot be faked by an exit
# code that describes something other than the query.
echo "--CFUNITS--"
systemctl list-unit-files 'clawfactory-*' --no-pager --no-legend 2>/dev/null
echo "--END-CFUNITS--"
echo "--CFENABLED--"
systemctl list-unit-files 'clawfactory-*' --no-pager --no-legend 2>/dev/null | awk '$2=="enabled"{print $1}'
echo "--END-CFENABLED--"
echo "FW_LOADSTATE=$(systemctl show -p LoadState --value clawfactory-fw.service 2>&1 | head -1)"
echo "FW_ACTIVESTATE=$(systemctl show -p ActiveState --value clawfactory-fw.service 2>&1 | head -1)"
echo "FW_UNITFILE=$( [ -f /etc/systemd/system/clawfactory-fw.service ] && echo present || echo absent )"
echo "--FAILED--"
systemctl list-units --state=failed --no-pager --no-legend 2>/dev/null | grep -i clawfactory
echo "--END-FAILED--"
echo "--JOURNALCF--"
journalctl -b --no-pager 2>/dev/null | grep -i 'clawfactory' | tail -5
echo "--END-JOURNALCF--"
echo "CTL_SYSTEMD_ALIVE=$( [ -d /run/systemd/system ] && echo yes || echo no )"
'@
foreach ($ln in @($after.Out -split "`r?`n" | Where-Object { $_.Trim() })) { W "   POST> $ln" }
$t = $after.Out
$bootAfter = Val $t 'BOOT_ID'

function Fenced([string]$text, [string]$b, [string]$e) {
    $o = @(); $on = $false
    foreach ($ln in ($text -split "`r?`n")) {
        $s = $ln.Trim()
        if ($s -eq $b) { $on = $true; continue }
        if ($s -eq $e) { $on = $false; continue }
        if ($on -and $s) { $o += $s }
    }
    return @($o)
}
$ctlRows   = Fenced $t '--CTLQUERY--'  '--END-CTLQUERY--'
$cfRows    = Fenced $t '--CFUNITS--'   '--END-CFUNITS--'
$cfEnabled = Fenced $t '--CFENABLED--' '--END-CFENABLED--'
$failed    = Fenced $t '--FAILED--'    '--END-FAILED--'
$journal   = Fenced $t '--JOURNALCF--' '--END-JOURNALCF--'

W ''
W "BOOT_BEFORE=$bootBefore"
W "BOOT_AFTER =$bootAfter"
W "CTLQUERY_ROWS=$($ctlRows.Count)  CFUNIT_ROWS=$($cfRows.Count)  CFENABLED_ROWS=$($cfEnabled.Count)"
W "CF_UNIT_LISTING=[$($cfRows -join ' | ')]"
W "CF_ENABLED_LISTING=[$($cfEnabled -join ' | ')]"

Section '4. The two controls'
$restarted = ($bootBefore -ne '(not reported)') -and ($bootAfter -ne '(not reported)') -and
             ($bootBefore -ne '') -and ($bootAfter -ne '') -and ($bootBefore -ne $bootAfter)
Register-Control -Id 'NB.CTL.RESTART' -Name 'the distro really restarted: its boot_id changed' `
    -Fired $restarted `
    -Evidence "before=$bootBefore after=$bootAfter changed=$restarted. Without a proven restart an unchanged unit list proves only that nothing happened. Two absent readings would also compare equal, so both are required to be present as well as different." | Out-Null

$queryOk = ($ctlRows.Count -ge 1) -and ((Val $t 'CTL_SYSTEMD_ALIVE') -eq 'yes')
Register-Control -Id 'NB.CTL.QUERY' -Name 'systemctl list-unit-files can actually answer on this distro' `
    -Fired $queryOk `
    -Evidence "a glob that must match on any Ubuntu ('systemd-*') returned $($ctlRows.Count) row(s); /run/systemd/system present=$(Val $t 'CTL_SYSTEMD_ALIVE'); is-system-running='$(Val $t 'SYSTEM_STATE')'. A systemctl that cannot reach systemd prints nothing, and 'nothing is enabled' would then read exactly like a clean box." | Out-Null

Section '5. The reading, classified'
$state = if (-not $queryOk) { 'QUERY_FAILED' }
         elseif ($cfEnabled.Count -ge 1) { 'SOME_ENABLED' }
         elseif ($cfRows.Count -ge 1) { 'LISTED_NOT_ENABLED' }
         else { 'NONE_LISTED' }
W "CFUNIT_STATE=$state   (NONE_LISTED | LISTED_NOT_ENABLED | SOME_ENABLED | QUERY_FAILED)"

Record 'NB.1' "systemctl list-unit-files 'clawfactory-*' returns nothing enabled at the next boot" `
    $(if ($state -eq 'NONE_LISTED') { 'PASS' } elseif ($state -eq 'QUERY_FAILED') { 'VOID' } else { 'FAIL' }) `
    "CFUNIT_STATE=$state; listing=[$($cfRows -join ' | ')]; enabled=[$($cfEnabled -join ' | ')]. LISTED_NOT_ENABLED would mean unit files survived the teardown even though nothing starts them; SOME_ENABLED is card #285's defect recurring; QUERY_FAILED means nothing was measured."

$fwLoad = Val $t 'FW_LOADSTATE'; $fwActive = Val $t 'FW_ACTIVESTATE'; $fwFile = Val $t 'FW_UNITFILE'
$fwState = if (-not $queryOk) { 'QUERY_FAILED' }
           elseif ($fwActive -eq 'failed') { 'PRESENT_FAILED' }
           elseif ($fwFile -eq 'present' -or $fwLoad -eq 'loaded') { 'PRESENT' }
           else { 'ABSENT' }
W "FW_STATE=$fwState   (ABSENT | PRESENT | PRESENT_FAILED | QUERY_FAILED)"

Record 'NB.2' 'clawfactory-fw.service is neither present nor failed' `
    $(if ($fwState -eq 'ABSENT') { 'PASS' } elseif ($fwState -eq 'QUERY_FAILED') { 'VOID' } else { 'FAIL' }) `
    "LoadState='$fwLoad' ActiveState='$fwActive' unitFileOnDisk=$fwFile -> FW_STATE=$fwState. This unit is named specifically because v1.4.1 deleted its script and left it enabled, which is the exact shape of a failed unit in the journal of a machine that no longer has ClawFactory on it."

Record 'NB.3' 'no ClawFactory unit is in the failed state after the restart' `
    $(if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
    "systemctl list-units --state=failed, filtered for clawfactory: $($failed.Count) row(s) [$($failed -join ' | ')]"

Record 'NB.4' 'what this boot journal says about ClawFactory, reported as a fact' 'INFO' `
    "last 5 matching lines from journalctl -b: [$($journal -join ' | ')]. Empty is the expected reading on a cleanly torn-down distro and is reported rather than asserted."

Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'NEXTBOOT'
Finish 0
