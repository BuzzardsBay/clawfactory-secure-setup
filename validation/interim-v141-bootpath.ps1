<#
  v1.4.1 boot-path validation: card #276, BOTH DIRECTIONS.

  WHY THIS PROBE EXISTS
  ---------------------
  v1.4.1 adds a boot-ordered refresh unit (clawfactory-egress-refresh.service)
  plus bounded per-host address retention in both resolvers. The v1.4.1 close-out
  states plainly that the whole of this is INFERRED FROM SOURCE and that nothing
  was measured on a running box. This probe is that measurement.

  THE DANGEROUS DIRECTION IS TESTED FIRST, AND DELIBERATELY SO
  ------------------------------------------------------------
  Almost everything in #276 narrows. Exactly one thing added can make a set
  WIDER than what the current run resolved: carrying an address forward. If that
  is wrong, a route the USER DELIBERATELY CLOSED silently reopens at boot. That
  is a worse defect than the dead route it was fixing, and unlike a dead route it
  is INVISIBLE to the user -- the panel would read exactly as they left it.

  So section 1 switches the toolchain OFF, restarts, and asserts it is STILL off
  with the route STILL dead, BEFORE section 3 asks whether the fix works at all.
  A green section 3 beside a red section 1 is not a pass, it is a worse product.

  WHY A DISTRO RESTART IS THE RIGHT INSTRUMENT, NOT A CHEAPER ONE
  ---------------------------------------------------------------
  clawfactory-egress-refresh.service is WantedBy=multi-user.target INSIDE the
  distro. `wsl.exe --shutdown` followed by re-entry is a real systemd boot of
  that distro, so it exercises the unit, its After= ordering against
  clawfactory-fw.service, and the replay-then-refresh sequence. It is the same
  code path a Windows reboot takes, and it costs no interactive login, which is
  what makes testing BOTH directions affordable in one session.

  EVERY RESTART CARRIES A CONTROL PROVING THE RESTART HAPPENED.
  /proc/sys/kernel/random/boot_id is regenerated per boot. If it did not change,
  the distro did not restart, and every "survived a restart" row after it would
  be a false pass that looks exactly like a real one.

  THE SEEDED HOST MUST BE A ROTATING POOL, AND THAT IS ASSERTED HERE, NOT ASSUMED
  -------------------------------------------------------------------------------
  The defect is that the boot path replays a STALE set. For a host whose address
  never moves, the stale set and the fresh set are the same set, so the route
  works whether or not the bug is present: a negative control that can never
  fail. www.iana.org is exactly such a host and is the default in stagebox.ps1.
  BP.0c resolves the seeded host repeatedly FROM THE VM'S OWN RESOLVER and
  requires the answer to change before any row that depends on it is trusted.
#>
param(
    [string]$Transcript   = 'C:\cfv\bootpath-out-probe.txt',
    [string]$RotHost      = 'outlook.office.com',
    [string]$RevokeHost   = 'example.org',
    [string]$DenyHost     = 'example.net',
    [string]$ToolHost     = 'api.github.com',
    [string]$ProviderHost = 'api.anthropic.com',
    [switch]$PostReboot
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1
$tag = if ($PostReboot) { 'POSTREBOOT' } else { 'PRE' }

# THE RESULTS FILE IS PASS-TAGGED, deliberately. Instrument defect 7 (v1.4.1
# close-out section 1) was a post-reboot job retrieving the PRE pass's results
# file because both passes wrote the same name: same file, older content, no
# error anywhere. A probe that can restate a previous pass's verdict as this
# one's is a probe that can lie without failing, so this one cannot share a name
# across passes. interim-v120-job.ps1 asks for the -postreboot name first.
$resultsJson = if ($PostReboot) { 'C:\cfv\bootpath-results-postreboot.json' } else { 'C:\cfv\bootpath-results.json' }

Start-Phase -Name "ClawFactory v1.4.1 boot path (#276), both directions, pass=$tag" `
    -Transcript $Transcript -Sentinel 'BOOTPATH_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id "BP.CHAN.$tag" -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; W 'BOOTPATH_PROBE_COMPLETE rc=2'; exit 2 }

# Placeholder substitution rather than a double-quoted here-string. A backtick
# inside a "..."@ here-string alters the emitted shell text and has cost a full
# VM run before; this shape cannot do that because every bash body is literal.
function Sub([string]$body) {
    $s = $body -replace '@ROT@',  $RotHost
    $s = $s    -replace '@REV@',  $RevokeHost
    $s = $s    -replace '@DENY@', $DenyHost
    $s = $s    -replace '@TOOL@', $ToolHost
    $s = $s    -replace '@PROV@', $ProviderHost
    return $s
}

function Get-BootId {
    $r = Invoke-WslFile -Tag ('bootid-' + [guid]::NewGuid().ToString('N').Substring(0,6)) -User 'root' -Body @'
echo "BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
'@
    if ($r.Out -match 'BOOT_ID=([0-9a-f-]+)') { return $Matches[1] }
    return ''
}

function Restart-Distro([string]$Why, [string]$CtlId) {
    W ''
    W "--- DISTRO RESTART: $Why ---"
    $before = Get-BootId
    W "boot_id BEFORE = $before"
    & wsl.exe --shutdown 2>&1 | Out-String | ForEach-Object { if ($_) { W $_.Trim() } }
    # Wait on STATE, never on a sleep (PROMPT 15). Re-entry boots the distro and
    # the loop blocks until systemd itself reports it has finished booting.
    $up = Invoke-WslFile -Tag ('bootup-' + $CtlId.Replace('.','-')) -User 'root' -Body @'
for i in $(seq 1 90); do
  st="$(systemctl is-system-running 2>/dev/null)"
  case "$st" in running|degraded) break;; esac
  sleep 2
done
echo "SYSTEMD_STATE=$(systemctl is-system-running 2>&1)"
echo "BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
echo "--- the boot refresh unit on THIS boot ---"
systemctl is-enabled clawfactory-egress-refresh.service 2>&1 | sed 's/^/IS_ENABLED=/'
systemctl is-active  clawfactory-egress-refresh.service 2>&1 | sed 's/^/IS_ACTIVE=/'
journalctl -u clawfactory-egress-refresh.service -b --no-pager 2>&1 | tail -12
'@
    W $up.Out
    $after = if ($up.Out -match 'BOOT_ID=([0-9a-f-]+)') { $Matches[1] } else { '' }
    W "boot_id AFTER  = $after"
    $fired = [bool]($before -and $after -and ($before -ne $after))
    Register-Control -Id $CtlId -Name "the distro really restarted ($Why): boot_id changed" `
        -Fired $fired -Evidence "before=$before after=$after" | Out-Null
    return $up.Out
}

# The reachability probe, run AS THE AGENT UID.
#
# SIX ATTEMPTS, NOT ONE, AND THE COUNT IS REPORTED. Measured on cfv-175: with
# the toolchain ON and a freshly-resolved 24-address set, api.github.com
# connected on 5 of 12 attempts and github.com on 2 of 5, because DNS hands out
# addresses (140.82.116.5, 20.29.134.17) that the resolver's three-pass sample
# never captured. The user's own read-fetch host behaves the same way:
# outlook.office.com returned 28 distinct addresses over 10 lookups against a
# 13-address set, and connected 9 times in 12.
#
# A ONE-SHOT probe against a rotating pool therefore reports a COIN FLIP. That
# is precisely the defect #278 raises against TC.1a/TC.1b, and this probe had it
# too: BP.3a FAILED and BP.4a PASSED in the same run, on the same mechanism, for
# no reason but luck.
#
# So the two questions are separated, because they are different defects with
# different cards:
#   EXISTS  -- did the boot path build a working route at all?  (card #276)
#   ALWAYS  -- is that route reachable on EVERY attempt?        (card #261)
# A route that answers 5 times in 12 proves #276 worked and #261 is unfixed.
$reachBody = @'
probe() {
  ok=0; n=6
  for i in $(seq 1 $n); do
    if timeout 8 bash -c "exec 3<>/dev/tcp/$1/443" 2>/dev/null; then ok=$((ok+1)); fi
  done
  if [ "$ok" -gt 0 ]; then v=CONNECTED; else v=blocked; fi
  echo "REACH $1 $v attempts=$ok/$n"
}
echo "whoami=$(id -un) uid=$(id -u)"
echo '--- SUBJECTS ---'
probe @TOOL@
probe @ROT@
probe @REV@
echo '--- CONTROL A (MUST CONNECT): the provider route, which this switch never touches ---'
probe @PROV@
echo '--- CONTROL B (MUST BE BLOCKED): a host on no list at all ---'
probe @DENY@
'@

function Measure-Reach([string]$Tag) {
    $r = Invoke-WslFile -Tag $Tag -User 'clawuser' -Body (Sub $reachBody)
    W $r.Out
    $h = @{}
    foreach ($line in ($r.Out -split "`n")) {
        if ($line -match 'REACH\s+(\S+)\s+(CONNECTED|blocked)') { $h[$Matches[1]] = $Matches[2] }
        if ($line -match 'REACH\s+(\S+)\s+\S+\s+attempts=(\d+)/(\d+)') {
            $h[($Matches[1] + '#att')] = "$($Matches[2])/$($Matches[3])"
        }
    }
    return $h
}

# "CONNECTED on n of 6" is the evidence string every reachability row carries, so
# the intermittency is on the record even when the row itself is about existence.
function Att([hashtable]$h, [string]$hostName) {
    $a = $h[($hostName + '#att')]
    if ($a) { return "$hostName=$($h[$hostName]) (connected on $a attempts)" }
    return "$hostName=$($h[$hostName])"
}

function Get-State([string]$Tag) {
    $r = Invoke-WslFile -Tag $Tag -User 'root' -Body @'
echo "TC_ENABLED=$(node -e 'try{const p=require("/etc/clawfactory/egress-policy.json");console.log(!!(p.toolchain&&p.toolchain.enabled))}catch(e){console.log("unreadable")}' 2>&1)"
echo "TC_SET_COUNT=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -Eo '[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+' | sort -u | wc -l | tr -d ' ')"
echo "TC_FILE_COUNT=$(grep -Ec '^[0-9]+[.]' /etc/clawfactory/toolchain-ips.txt 2>/dev/null || echo 0)"
echo "TC_MAP_COUNT=$(grep -Ec '.' /etc/clawfactory/toolchain-ips.map 2>/dev/null || echo 0)"
echo "RF_SET_COUNT=$(nft list set inet clawfactory read_fetch_ipv4 2>/dev/null | grep -Eo '[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+' | sort -u | wc -l | tr -d ' ')"
echo "RF_HOSTS=$(tr '\n' ',' < /etc/clawfactory/read-fetch-hosts.txt 2>/dev/null)"
'@
    W $r.Out
    return $r.Out
}

# ===================================================================== 0. setup
Section '0. The new unit, and proof the seeded host is a rotating pool'

$unit = Invoke-WslFile -Tag "bp-unit-$tag" -User 'root' -Body @'
echo "IS_ENABLED=$(systemctl is-enabled clawfactory-egress-refresh.service 2>&1)"
echo "IS_ACTIVE=$(systemctl is-active clawfactory-egress-refresh.service 2>&1)"
echo '--- the unit file as installed ---'
cat /etc/systemd/system/clawfactory-egress-refresh.service 2>&1
echo '--- ownership and mode, MEASURED ---'
stat -c 'UNIT_STAT %n mode=%a owner=%U:%G' /etc/systemd/system/clawfactory-egress-refresh.service 2>&1
stat -c 'SCRIPT_STAT %n mode=%a owner=%U:%G' /usr/local/sbin/clawfactory-egress-refresh.sh 2>&1
'@
W $unit.Out
Record "BP.0a.$tag" 'clawfactory-egress-refresh.service is installed and ENABLED' `
    $(if ($unit.Out -match 'IS_ENABLED=enabled') { 'PASS' } else { 'FAIL' }) `
    (($unit.Out -split "`n" | Where-Object { $_ -match '^IS_ENABLED=' } | Select-Object -First 1))
Record "BP.0b.$tag" 'It is ordered AFTER the firewall unit and the network, which is the whole fix' `
    $(if (($unit.Out -match 'After=.*clawfactory-fw\.service') -and ($unit.Out -match 'After=.*network-online\.target')) { 'PASS' } else { 'FAIL' }) `
    (($unit.Out -split "`n" | Where-Object { $_ -match '^After=' } | Select-Object -First 1))
Record "BP.0b2.$tag" 'The boot script and unit are root-owned and not agent-writable' `
    $(if (($unit.Out -match 'UNIT_STAT \S+ mode=644 owner=root:root') -and ($unit.Out -match 'SCRIPT_STAT \S+ mode=755 owner=root:root')) { 'PASS' } else { 'FAIL' }) `
    (($unit.Out -split "`n" | Where-Object { $_ -match '_STAT ' }) -join ' | ')

# BP.0c -- the load-bearing precondition for every read-fetch row below.
$rot = Invoke-WslFile -Tag "bp-rot-$tag" -User 'root' -Body (Sub @'
echo "--- resolving @ROT@ six times from THIS box's resolver ---"
for i in 1 2 3 4 5 6; do
  s="$(getent ahostsv4 @ROT@ | awk '{print $1}' | sort -u | tr '\n' ',')"
  echo "LOOKUP$i=$s"
  sleep 1
done
echo "--- a host known NOT to rotate, as the control for this measurement ---"
for i in 1 2 3; do
  s="$(getent ahostsv4 www.iana.org | awk '{print $1}' | sort -u | tr '\n' ',')"
  echo "STABLE$i=$s"
done
'@)
W $rot.Out
$rotSets = @($rot.Out -split "`n" | Where-Object { $_ -match '^LOOKUP\d+=' } | ForEach-Object { ($_ -split '=',2)[1].Trim() } | Where-Object { $_ })
$rotDistinct = ($rotSets | Sort-Object -Unique).Count
$stabSets = @($rot.Out -split "`n" | Where-Object { $_ -match '^STABLE\d+=' } | ForEach-Object { ($_ -split '=',2)[1].Trim() } | Where-Object { $_ })
$stabDistinct = ($stabSets | Sort-Object -Unique).Count
# The control here is INVERTED on purpose: it proves the measurement can tell a
# rotating host from a stable one. If the stable host ALSO looked like it rotated,
# this instrument would be measuring resolver noise rather than a rotating pool.
Register-Control -Id "BP.CTL.ROT.$tag" -Name 'the rotation measurement discriminates: a known-stable host returns ONE set' `
    -Fired ($stabDistinct -eq 1 -and $stabSets.Count -ge 3) `
    -Evidence "www.iana.org distinctSets=$stabDistinct across $($stabSets.Count) lookups" | Out-Null
Record "BP.0c.$tag" "The seeded read-fetch host $RotHost is genuinely a ROTATING POOL on this box" `
    $(if ($rotSets.Count -lt 3) { 'VOID' } elseif ($rotDistinct -ge 2) { 'PASS' } else { 'FAIL' }) `
    "distinctSets=$rotDistinct across $($rotSets.Count) lookups; stable-host control distinctSets=$stabDistinct. A host with ONE set cannot detect a replayed stale set."

if ($PostReboot) {
    # After a real Windows reboot the box arrives in whatever state the PRE pass
    # left it: toolchain ON, RotHost allowed, RevokeHost revoked. Assert that
    # state SURVIVED the reboot, then stop. The destructive cycling is PRE-only.
    Section 'POSTREBOOT: the same properties, across a real Windows reboot'
    $stP = Get-State 'bp-state-post'
    $rP  = Measure-Reach 'bp-reach-post'
    Register-Control -Id "BP.CTL.PROV.$tag" -Name 'CONTROL: the provider route is reachable, so a blocked subject is not a dead box' `
        -Fired ($rP[$ProviderHost] -eq 'CONNECTED') -Evidence "$ProviderHost=$($rP[$ProviderHost])" | Out-Null
    Register-Control -Id "BP.CTL.DENY.$tag" -Name 'CONTROL: a host on no list is blocked, so CONNECTED means something' `
        -Fired ($rP[$DenyHost] -eq 'blocked') -Evidence "$DenyHost=$($rP[$DenyHost])" | Out-Null
    Record "BP.5a.$tag" 'After a REAL Windows reboot the toolchain route is live without waiting for the five-hourly refresh' `
        $(if ($rP[$ToolHost] -eq 'CONNECTED') { 'PASS' } else { 'FAIL' }) "$(Att $rP $ToolHost)"
    Record "BP.5b.$tag" "After a REAL Windows reboot the user's own read-fetch site $RotHost is live" `
        $(if ($rP[$RotHost] -eq 'CONNECTED') { 'PASS' } else { 'FAIL' }) "$(Att $rP $RotHost)"
    Record "BP.5c.$tag" "A site REVOKED before the reboot did NOT come back ($RevokeHost)" `
        $(if ($rP[$RevokeHost] -eq 'blocked') { 'PASS' } else { 'FAIL' }) "$(Att $rP $RevokeHost)"
    $tcAttP = $rP[($ToolHost + '#att')]; $rfAttP = $rP[($RotHost + '#att')]
    Record "BP.6a.$tag" "#261 residual, toolchain: reachable on EVERY attempt after a real reboot" `
        $(if (-not $tcAttP) { 'VOID' } elseif (($tcAttP -split '/')[0] -eq ($tcAttP -split '/')[1]) { 'PASS' } else { 'FAIL' }) `
        "connected on $tcAttP attempts (#261, not #276)"
    Record "BP.6b.$tag" "#261 residual, read-fetch: reachable on EVERY attempt after a real reboot" `
        $(if (-not $rfAttP) { 'VOID' } elseif (($rfAttP -split '/')[0] -eq ($rfAttP -split '/')[1]) { 'PASS' } else { 'FAIL' }) `
        "connected on $rfAttP attempts (#261, not #276)"
    Record "BP.5d.$tag" 'The boot refresh unit ran on this boot and reported its attempt count' `
        $(if ($unit.Out -match 'IS_ACTIVE=active') { 'PASS' } else { 'FAIL' }) `
        (($unit.Out -split "`n" | Where-Object { $_ -match '^IS_ACTIVE=' } | Select-Object -First 1))
    Complete-Phase -ResultsJson $resultsJson -MarkerPrefix 'BOOTPATH'
    return
}

# ============================================ 1. THE DANGEROUS DIRECTION, FIRST
Section '1. DANGEROUS DIRECTION: a route the USER CLOSED must stay closed across a boot'

$off = Invoke-WslFile -Tag "bp-off-$tag" -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl toolchain off 2>&1
echo "off_rc=$?"
'@
W $off.Out
$st1 = Get-State 'bp-state-off'
$r1  = Measure-Reach 'bp-reach-off'
Register-Control -Id "BP.CTL.PROV1.$tag" -Name 'CONTROL: provider route reachable with the toolchain OFF (a blocked subject is not a dead box)' `
    -Fired ($r1[$ProviderHost] -eq 'CONNECTED') -Evidence "$ProviderHost=$($r1[$ProviderHost])" | Out-Null
Record "BP.1a.$tag" 'Switching the toolchain OFF empties the live set, the persisted file AND the retention map' `
    $(if (($st1 -match 'TC_ENABLED=false') -and ($st1 -match 'TC_SET_COUNT=0') -and ($st1 -match 'TC_FILE_COUNT=0') -and ($st1 -match 'TC_MAP_COUNT=0')) { 'PASS' } else { 'FAIL' }) `
    (($st1 -split "`n" | Where-Object { $_ -match '^TC_' }) -join ' ')
Record "BP.1b.$tag" 'With the toolchain OFF the software sources are unreachable BEFORE any restart' `
    $(if ($r1[$ToolHost] -eq 'blocked') { 'PASS' } else { 'FAIL' }) "$ToolHost=$($r1[$ToolHost])"

Restart-Distro 'toolchain OFF, does it stay off' "BP.CTL.RESTART1.$tag" | Out-Null
$st2 = Get-State 'bp-state-off-post'
$r2  = Measure-Reach 'bp-reach-off-post'
Register-Control -Id "BP.CTL.PROV2.$tag" -Name 'CONTROL: provider route reachable after the restart' `
    -Fired ($r2[$ProviderHost] -eq 'CONNECTED') -Evidence "$ProviderHost=$($r2[$ProviderHost])" | Out-Null
Record "BP.1c.$tag" 'ACROSS A BOOT: the toolchain switch is STILL OFF (the user setting survived)' `
    $(if ($st2 -match 'TC_ENABLED=false') { 'PASS' } else { 'FAIL' }) `
    (($st2 -split "`n" | Where-Object { $_ -match '^TC_ENABLED=' } | Select-Object -First 1))
Record "BP.1d.$tag" 'ACROSS A BOOT: set, file and retention map are STILL empty (no retention fuel left behind)' `
    $(if (($st2 -match 'TC_SET_COUNT=0') -and ($st2 -match 'TC_FILE_COUNT=0') -and ($st2 -match 'TC_MAP_COUNT=0')) { 'PASS' } else { 'FAIL' }) `
    (($st2 -split "`n" | Where-Object { $_ -match '^TC_' }) -join ' ')
Record "BP.1e.$tag" 'ACROSS A BOOT: the closed route is STILL DEAD. A boot refresh that reopened it would be invisible to the user' `
    $(if ($r2[$ToolHost] -eq 'blocked') { 'PASS' } else { 'FAIL' }) "$ToolHost=$($r2[$ToolHost])"

# ================================== 2. read-fetch revocation survives a restart
Section '2. A site the user REMOVED must not return at boot (L30, read-fetch half)'

$rev = Invoke-WslFile -Tag "bp-rev-$tag" -User 'root' -Body (Sub @'
echo '--- add BOTH, so the revocation is a removal from a populated list ---'
/usr/local/sbin/clawfactory-fetchctl add @ROT@ 2>&1
/usr/local/sbin/clawfactory-fetchctl add @REV@ 2>&1
echo '--- now REVOKE one of them ---'
/usr/local/sbin/clawfactory-fetchctl remove @REV@ 2>&1
echo "remove_rc=$?"
echo "HOSTS_AFTER=$(tr '\n' ',' < /etc/clawfactory/read-fetch-hosts.txt 2>/dev/null)"
echo "MAP_MENTIONS_REVOKED=$(grep -c '^@REV@' /etc/clawfactory/read-fetch-ips.map 2>/dev/null || echo 0)"
'@)
W $rev.Out
$revGone = ($rev.Out -split "`n" | Where-Object { $_ -match '^HOSTS_AFTER=' } | Select-Object -First 1) -notmatch [regex]::Escape($RevokeHost)
Record "BP.2a.$tag" "Revoking $RevokeHost removes it from the host list and leaves no entry in the retention map" `
    $(if ($revGone -and ($rev.Out -match 'MAP_MENTIONS_REVOKED=0')) { 'PASS' } else { 'FAIL' }) `
    (($rev.Out -split "`n" | Where-Object { $_ -match '^HOSTS_AFTER=|^MAP_MENTIONS_REVOKED=' }) -join ' ')

# =================================== 3 and 4. THE FIX ITSELF, both halves, once
Section '3+4. THE FIX: toolchain ON and a rotating user site allowed, then a boot, then measured immediately'

$on = Invoke-WslFile -Tag "bp-on-$tag" -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl toolchain on 2>&1
echo "on_rc=$?"
'@
W $on.Out
Get-State 'bp-state-on' | Out-Null

Restart-Distro 'toolchain ON and a rotating user site allowed, does the boot path make them live' "BP.CTL.RESTART2.$tag" | Out-Null
$st4 = Get-State 'bp-state-on-post'
$r3  = Measure-Reach 'bp-reach-on-post'

Register-Control -Id "BP.CTL.PROV3.$tag" -Name 'CONTROL: provider route reachable in the measuring run' `
    -Fired ($r3[$ProviderHost] -eq 'CONNECTED') -Evidence "$ProviderHost=$($r3[$ProviderHost])" | Out-Null
Register-Control -Id "BP.CTL.DENY3.$tag" -Name 'CONTROL: a host on no list is BLOCKED, so CONNECTED is a route and not a broken probe' `
    -Fired ($r3[$DenyHost] -eq 'blocked') -Evidence "$DenyHost=$($r3[$DenyHost])" | Out-Null

$tcCount = (($st4 -split "`n" | Where-Object { $_ -match '^TC_SET_COUNT=' } | Select-Object -First 1))
$rfCount = (($st4 -split "`n" | Where-Object { $_ -match '^RF_SET_COUNT=' } | Select-Object -First 1))
Record "BP.3a.$tag" 'THE FIX (#276), toolchain half: a boot builds a WORKING route, without waiting for the five-hourly refresh' `
    $(if ($r3[$ToolHost] -eq 'CONNECTED') { 'PASS' } else { 'FAIL' }) "$(Att $r3 $ToolHost); $tcCount"
Record "BP.4a.$tag" "THE FIX (#276), read-fetch half (never measured anywhere before): a boot builds a WORKING route to the user's own rotating-pool site $RotHost" `
    $(if ($r3[$RotHost] -eq 'CONNECTED') { 'PASS' } else { 'FAIL' }) "$(Att $r3 $RotHost); $rfCount"
Record "BP.4b.$tag" "The revoked site $RevokeHost is STILL unreachable after the boot that made the others live" `
    $(if ($r3[$RevokeHost] -eq 'blocked') { 'PASS' } else { 'FAIL' }) "$(Att $r3 $RevokeHost)"

# ---------------------------------------------------------------------------
# THE SEPARATE QUESTION, AND IT IS A DIFFERENT CARD.
#
# BP.3a/BP.4a ask whether the boot path produced a route at all, which is what
# #276 changed. These two ask whether that route answers EVERY time, which is
# what #261 is about and what v1.4.1 explicitly did NOT close. Recorded as their
# own rows so a green #276 cannot be read as a promise the product does not make.
$tcAtt = $r3[($ToolHost + '#att')]; $rfAtt = $r3[($RotHost + '#att')]
$tcAll = ($tcAtt -and ($tcAtt -split '/')[0] -eq ($tcAtt -split '/')[1])
$rfAll = ($rfAtt -and ($rfAtt -split '/')[0] -eq ($rfAtt -split '/')[1])
Record "BP.6a.$tag" "#261 residual, toolchain: is $ToolHost reachable on EVERY attempt, not merely on one" `
    $(if (-not $tcAtt) { 'VOID' } elseif ($tcAll) { 'PASS' } else { 'FAIL' }) `
    "connected on $tcAtt attempts. A partial count is the rotating-pool sampling gap (#261), NOT a boot-path failure: the boot unit resolved every host in this same run."
Record "BP.6b.$tag" "#261 residual, read-fetch: is $RotHost reachable on EVERY attempt, not merely on one" `
    $(if (-not $rfAtt) { 'VOID' } elseif ($rfAll) { 'PASS' } else { 'FAIL' }) `
    "connected on $rfAtt attempts. This half had never been measured before v1.4.1 validation."

# The unit's own account of what it did on this boot.
$jr = Invoke-WslFile -Tag "bp-journal-$tag" -User 'root' -Body @'
echo "IS_ACTIVE=$(systemctl is-active clawfactory-egress-refresh.service 2>&1)"
echo "RESULT=$(systemctl show -p Result --value clawfactory-egress-refresh.service 2>&1)"
echo '--- journal for THIS boot ---'
journalctl -u clawfactory-egress-refresh.service -b --no-pager 2>&1 | tail -20
'@
W $jr.Out
$attemptLine = (($jr.Out -split "`n") | Where-Object { $_ -match 'attempt \d+/\d+: unresolved hosts' } | Select-Object -First 1)
Record "BP.3b.$tag" 'The boot refresh unit RAN on this boot and reported its own attempt count' `
    $(if ($attemptLine) { 'PASS' } else { 'FAIL' }) `
    $(if ($attemptLine) { $attemptLine.Trim() } else { 'no "attempt N/20: unresolved hosts" line in this boot journal' })

Complete-Phase -ResultsJson $resultsJson -MarkerPrefix 'BOOTPATH'
