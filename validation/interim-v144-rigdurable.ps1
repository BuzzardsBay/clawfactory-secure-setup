<#
  CALIBRATE THE LEVEL-2 RIG BEFORE SPENDING A FULL INSTALL ON IT.

  PG.3f's level-2 control writes an unroutable address for the provider host into
  the distro's /etc/hosts and re-runs the installer, expecting a refusal. On
  cfv-180 the rig landed and the install completed anyway. Measured cause
  (interim-v144-hostsdiag.ps1): /etc/wsl.conf sets no generateHosts, WSL's default
  is to regenerate /etc/hosts on every distro start, the shipped file carries WSL's
  own "automatically generated" header, and the install runs `wsl --shutdown` at
  Step 4 -- three seconds after the rig lands.

  So the rig is erased by the very install it is meant to interrupt. The probe's
  header already rejected a firewall-rule rig for the symmetric reason
  (Step-EgressFirewall rewrites the ruleset); nobody had noticed that /etc/hosts
  has the same problem for a different reason.

  THIS FILE DOES NOT RUN AN INSTALL. It asks one question, in about a minute:
  does a rig that ALSO sets [network] generateHosts=false survive a distro
  restart? A full-install control is worth running only if the answer is yes, and
  running one to find out costs ten minutes and leaves the question unanswered
  either way -- which is exactly what happened on cfv-180.

  It is written to leave the box EXACTLY as it found it, and to prove it did.
#>
param(
    [string]$Transcript   = 'C:\cfv\rigdurable-out-probe.txt',
    [string]$ResultsJson  = 'C:\cfv\rigdurable-results.json',
    [string]$ProviderHost = 'api.anthropic.com',
    [string]$LibDir       = 'C:\cfv'
)
$ErrorActionPreference = 'Continue'
. (Join-Path $LibDir 'interim-v120-wslchan.ps1')
. (Join-Path $LibDir 'interim-v120-phaselib.ps1')

Start-Phase -Name 'Calibration: does a generateHosts=false rig survive a distro restart?' `
    -Transcript $Transcript -Sentinel 'RIGDURABLE_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'RD.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'RIGDURABLE' }

# ---------------------------------------------------------------- 1. baseline
Section '1. BASELINE: the provider resolves normally, and wsl.conf is as shipped'
$before = Invoke-WslFile -Tag 'rd-before' -User 'root' -Body @"
cp /etc/wsl.conf /var/tmp/wsl.conf.rdbak
cp /etc/hosts    /var/tmp/hosts.rdbak
echo "WSLCONF_SHA_BEFORE=`$(sha256sum /etc/wsl.conf | cut -d' ' -f1)"
echo "GENHOSTS_BEFORE=`$(grep -ci 'generateHosts' /etc/wsl.conf || true)"
echo "RESOLVES_BEFORE=`$(getent ahostsv4 $ProviderHost | awk '{print `$1}' | sort -u | tr '\n' ' ')"
"@
W $before.Out
$resolvesBefore = ($before.Out -match 'RESOLVES_BEFORE=\s*\d') -and ($before.Out -notmatch 'RESOLVES_BEFORE=.*192\.0\.2\.1')
Register-Control -Id 'RD.CTL0' -Name 'the provider resolves to a real address BEFORE the rig' `
    -Fired $resolvesBefore `
    -Evidence "without this, 'the rig held' and 'this host never resolved' are indistinguishable. $(if ($before.Out -match 'RESOLVES_BEFORE=(.*)') { 'RESOLVES_BEFORE=' + $Matches[1] })" | Out-Null

# --------------------------------------------------------------- 2. rig it
Section '2. Write the rig: generateHosts=false FIRST, then the hosts entry'
# ORDER MATTERS. generateHosts=false must be in place before the restart, or the
# restart regenerates /etc/hosts and erases the entry -- which is the cfv-180
# failure exactly. It is inserted after the generateResolvConf line so it lands
# inside the EXISTING [network] section; a second [network] section would be
# ambiguous and setup.ps1's own wsl.conf edit only rewrites [user], so this
# survives the install's Step 5b.
$rig = Invoke-WslFile -Tag 'rd-rig' -User 'root' -Body @"
if grep -qi 'generateHosts' /etc/wsl.conf; then
  sed -i 's/^[[:space:]]*generateHosts.*/generateHosts=false/I' /etc/wsl.conf
elif grep -qi 'generateResolvConf' /etc/wsl.conf; then
  sed -i '0,/generateResolvConf.*/s//&\ngenerateHosts=false/' /etc/wsl.conf
else
  printf '\n[network]\ngenerateHosts=false\n' >> /etc/wsl.conf
fi
grep -q '192.0.2.1 $ProviderHost' /etc/hosts || echo "192.0.2.1 $ProviderHost" >> /etc/hosts
echo "GENHOSTS_AFTER_WRITE=`$(grep -ci 'generateHosts=false' /etc/wsl.conf || true)"
echo "HOSTS_ENTRY_AFTER_WRITE=`$(grep -c '192.0.2.1 $ProviderHost' /etc/hosts || true)"
echo "RESOLVES_AFTER_WRITE=`$(getent ahostsv4 $ProviderHost | awk '{print `$1}' | sort -u | tr '\n' ' ')"
echo '--- wsl.conf [network] section as it now stands ---'
sed -n '/\[network\]/,/^\[/p' /etc/wsl.conf
"@
W $rig.Out
$rigLanded = ($rig.Out -match 'GENHOSTS_AFTER_WRITE=1') -and ($rig.Out -match 'RESOLVES_AFTER_WRITE=.*192\.0\.2\.1')
Register-Control -Id 'RD.CTL1' -Name 'THE FAULT LANDED before the restart' -Fired $rigLanded `
    -Evidence "generateHosts=false written=$($rig.Out -match 'GENHOSTS_AFTER_WRITE=1'); provider now resolves to the unroutable address=$($rig.Out -match 'RESOLVES_AFTER_WRITE=.*192\.0\.2\.1'). A rig that does not rig scores a false pass and looks exactly like a working control" | Out-Null

# --------------------------------------------------- 3. restart and re-measure
Section '3. Restart the distro the way the install does, then re-measure'
# WAIT ON STATE, NEVER ON A SLEEP: the boot id is read back and must CHANGE, so
# "the distro restarted" is measured rather than assumed.
$bootBefore = (Invoke-WslFile -Tag 'rd-boot1' -User 'root' -Body 'cat /proc/sys/kernel/random/boot_id').Out
W "boot_id BEFORE: $($bootBefore.Trim())"
& wsl.exe --shutdown | Out-Null
Start-Sleep -Seconds 8
$after = Invoke-WslFile -Tag 'rd-after' -User 'root' -Body @"
echo "BOOTID_AFTER=`$(cat /proc/sys/kernel/random/boot_id)"
echo "HOSTS_ENTRY_SURVIVED=`$(grep -c '192.0.2.1 $ProviderHost' /etc/hosts || true)"
echo "WSL_HEADER_PRESENT=`$(head -3 /etc/hosts | grep -ci 'automatically generated by WSL' || true)"
echo "RESOLVES_AFTER_RESTART=`$(getent ahostsv4 $ProviderHost | awk '{print `$1}' | sort -u | tr '\n' ' ')"
"@
W $after.Out
$bootChanged = ($after.Out -match 'BOOTID_AFTER=(\S+)') -and ($Matches[1].Trim() -ne $bootBefore.Trim())
Register-Control -Id 'RD.CTL2' -Name 'the distro really restarted: boot_id changed' -Fired $bootChanged `
    -Evidence "before=$($bootBefore.Trim()) after=$(if ($after.Out -match 'BOOTID_AFTER=(\S+)') { $Matches[1] }). Without a real restart this measures nothing: an unchanged /etc/hosts across a restart that never happened proves only that nothing happened" | Out-Null

$survived = ($after.Out -match 'HOSTS_ENTRY_SURVIVED=1') -and ($after.Out -match 'RESOLVES_AFTER_RESTART=.*192\.0\.2\.1')
Record 'RD.1' 'a generateHosts=false rig SURVIVES the distro restart the install performs' `
    $(if (-not $bootChanged) { 'VOID' } elseif ($survived) { 'PASS' } else { 'FAIL' }) `
    "hosts entry present after restart=$($after.Out -match 'HOSTS_ENTRY_SURVIVED=1'); provider still resolves unroutable=$($after.Out -match 'RESOLVES_AFTER_RESTART=.*192\.0\.2\.1'); bootIdChanged=$bootChanged. PASS here means PG.3f's level-2 control is worth a full install; FAIL means it is not and a different rig is needed"

# ------------------------------------------------------------- 4. restore
Section '4. Restore the box EXACTLY as it was found, and prove it'
$restore = Invoke-WslFile -Tag 'rd-restore' -User 'root' -Body @"
cp /var/tmp/wsl.conf.rdbak /etc/wsl.conf
cp /var/tmp/hosts.rdbak    /etc/hosts
echo "WSLCONF_SHA_AFTER=`$(sha256sum /etc/wsl.conf | cut -d' ' -f1)"
echo "GENHOSTS_AFTER_RESTORE=`$(grep -ci 'generateHosts' /etc/wsl.conf || true)"
echo "HOSTS_RIG_AFTER_RESTORE=`$(grep -c '192.0.2.1 $ProviderHost' /etc/hosts || true)"
echo "RESOLVES_AFTER_RESTORE=`$(getent ahostsv4 $ProviderHost | awk '{print `$1}' | sort -u | tr '\n' ' ')"
"@
W $restore.Out
$shaBefore = if ($before.Out  -match 'WSLCONF_SHA_BEFORE=([a-f0-9]{64})') { $Matches[1] } else { '' }
$shaAfter  = if ($restore.Out -match 'WSLCONF_SHA_AFTER=([a-f0-9]{64})')  { $Matches[1] } else { '' }
$clean = $shaBefore -and ($shaBefore -eq $shaAfter) -and
         ($restore.Out -match 'HOSTS_RIG_AFTER_RESTORE=0') -and
         ($restore.Out -notmatch 'RESOLVES_AFTER_RESTORE=.*192\.0\.2\.1')
Record 'RD.2' 'the box is left byte-identical to how it was found' `
    $(if ($clean) { 'PASS' } else { 'FAIL' }) `
    "wsl.conf sha before=$shaBefore after=$shaAfter (must be equal); rig line count in /etc/hosts after restore must be 0; provider must resolve to a real address again. A probe that leaves its fault behind poisons every phase after it"

Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'RIGDURABLE'
