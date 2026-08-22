<#
  TASK 1, STEP 2: DOES THE TOOLCHAIN TOGGLE ACTUALLY STOP SKILL INSTALLATION?

  This is an ADJUDICATION INPUT, not a fix. It changes no shipped file and no
  panel copy. It answers one question so a product-copy decision can be made on
  a measurement instead of on an inference.

  THE QUESTION, AND WHY IT IS NOT ALREADY ANSWERED
  ------------------------------------------------
  Two shipped surfaces tell the user that switching the toolchain toggle off
  stops skill installation:

    resources/clawfactory-fetchctl.js:262   the CLI usage text
    the Studio Web access panel             pinned by scripts/build_release.ps1:163
                                            and checked by interim-v120-phase6.ps1:496

  Enforcement is by resolved ADDRESS, not by name. clawhub.ai resolves to
  216.150.1.1, and so does openclaw.ai, which is a permanent base host in
  @allowed_ipv4 that no toggle can revoke. So bare clawhub.ai stays reachable
  with the toggle off, and cfv-169 measured exactly that. If skill installation
  talks to bare clawhub.ai, the shipped copy is false. If it talks to
  api.clawhub.ai, which resolves elsewhere, the copy is true as written and the
  finding downgrades to "a website stays reachable", which the ratified footnote
  already discloses by saying matching is by address.

  WHAT STEP 1 ESTABLISHED, so this phase is not built on a guess
  --------------------------------------------------------------
  Measured on cfv-169, 2026-08-22, from the shipped CLI's own help text:

    openclaw skills install <slug>   "Install a skill from ClawHub into the
                                      active workspace"
    openclaw skills search           "Search ClawHub skills"

  So installation is a ClawHub operation, not the npm-registry plugins path the
  year-old recon note described. Which of the two ClawHub hostnames it opens is
  the open question and is what this phase measures.

  A WARNING STEP 1 ALSO PRODUCED, and it shapes how this reads
  ------------------------------------------------------------
  api.clawhub.ai resolved to 216.150.1.193 and 216.150.16.129, while
  toolchain_ipv4 held 216.150.1.65, 216.150.16.1 and 216.150.16.193. NOT ONE of
  the addresses it currently resolves to was in the set, with the toggle ON.
  That is the card #261 rotating-pool coverage gap, previously seen only on
  GitHub, appearing on the API hub as well.

  It means the earlier reading "api.clawhub.ai measured BLOCKED with the toggle
  off" cannot be attributed to the toggle: it would measure blocked with the
  toggle ON too. This phase therefore records the toggle-ON reachability of both
  hub hostnames as a first-class row, because without it a toggle-OFF failure is
  unattributable in exactly the way cfv-167 was.

  WHY THE SUBJECT RUNS BEFORE ITS CONTROL
  ---------------------------------------
  A real installation caches. If the control ran first with the toggle ON, it
  would populate a workspace and a download cache that the toggle-OFF subject
  could then satisfy locally, and the subject would "succeed" without a packet
  leaving the box. Running the subject first, on a workspace with no skills
  installed, removes that confound: there is nothing cached to succeed from.

  The cost of that ordering is the mirror risk, that a failed subject leaves a
  partial cache the control then satisfies. That matters less (a control passing
  is the expected direction, and a failed subject caches nothing useful), and it
  is closed anyway by deleting the target skill directory between the arms and
  asserting it is gone before the control runs.

  DO NOT CHANGE THE PANEL COPY FROM THIS PHASE, either way, and do not remove
  openclaw.ai from $baseHosts. Both are the operator's decisions once this is
  measured.
#>
param(
    [string]$Transcript = 'C:\cfv\skillinstall-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'Task 1: does the toolchain toggle actually stop skill installation?' `
    -Transcript $Transcript -Sentinel 'SKILLINSTALL_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'SK.CHAN' -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) {
    W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'
    Complete-Phase -ResultsJson 'C:\cfv\skillinstall-results.json' -MarkerPrefix 'SKILLINSTALL'
}

# The workspace skill directory. Read rather than assumed: "the active
# workspace" is the CLI's phrase and the path it resolves to is what a
# successful install has to be looked for in. NAME THE REAL SUBJECT.
$wsProbe = Invoke-WslFile -Tag 'sk-ws' -User 'clawuser' -Body @'
echo "whoami=$(id -un) uid=$(id -u)"
echo "--- candidate workspace roots ---"
for d in /workspaces /home/clawuser/.openclaw/agents /home/clawuser/.openclaw/workspace; do
  [ -d "$d" ] && { echo "ROOT_PRESENT $d"; ls -1 "$d" 2>/dev/null | head -10 | sed "s|^|  under $d: |"; } || echo "ROOT_ABSENT $d"
done
echo "--- every existing skills directory anywhere clawuser can see ---"
find /workspaces /home/clawuser -maxdepth 5 -type d -name skills 2>/dev/null | head -10 | sed 's/^/SKILLDIR /'
'@
W $wsProbe.Out

# =========================================================================
Section '0. Install and calibrate the drop instrument, in BOTH directions'
# Lesson #5 from reference_validation_probe_gotchas, which cost cfv-167 a false
# ship-blocker: an nft drop log proven only against a must-drop target passes
# whether it sits above or below the accept rules. Placed above them it
# faithfully logs packets that are then ACCEPTED, and a reader records those as
# drops. So the instrument must do BOTH: name a destination that must be
# dropped, and stay SILENT for one that is allowed.
$cal = Invoke-WslFile -Tag 'sk-calibrate' -User 'root' -Body @'
set -u
H=$(nft -a list chain inet clawfactory output 2>/dev/null \
    | grep -E '^[[:space:]]*counter packets [0-9]+ bytes [0-9]+ drop # handle [0-9]+$' \
    | tail -1 | awk '{print $NF}')
echo "TERMINAL_DROP_HANDLE=${H:-NONE}"
if [ -z "${H:-}" ]; then echo "CALIBRATION_NAMED=0"; echo "DISCRIMINATES=0"; exit 0; fi
nft insert rule inet clawfactory output handle "$H" limit rate 200/second log prefix '"SKDROP:"' 2>&1
if nft list chain inet clawfactory output 2>/dev/null | grep -q 'SKDROP'; then
  echo "INSTRUMENT_INSTALLED=1"
else
  echo "INSTRUMENT_INSTALLED=0"; echo "CALIBRATION_NAMED=0"; echo "DISCRIMINATES=0"; exit 0
fi
echo "--- placement, read rather than assumed: everything at and after the log rule ---"
nft list chain inet clawfactory output 2>/dev/null | sed -n '/SKDROP/,$p'
echo "--- and everything before it, so a reader can see the accepts sit ABOVE the log ---"
nft list chain inet clawfactory output 2>/dev/null | sed -n '1,/SKDROP/p'

echo "--- HALF 1: an address that MUST be dropped. The log must NAME it. ---"
CALIP=$(getent ahostsv4 example.org 2>/dev/null | awk '{print $1}' | head -1)
echo "CALIBRATION_TARGET=${CALIP:-NONE}"
if [ -z "${CALIP:-}" ]; then echo "CALIBRATION_NAMED=0"; echo "DISCRIMINATES=0"; exit 0; fi
MARK=$(dmesg 2>/dev/null | wc -l)
su -s /bin/bash -c "timeout 6 bash -c 'exec 3<>/dev/tcp/$CALIP/443'" clawuser >/dev/null 2>&1 || true
sleep 3
HITS=$(dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep -c "SKDROP:.*DST=$CALIP")
echo "CALIBRATION_HITS=$HITS"
[ "$HITS" -gt 0 ] && echo "CALIBRATION_NAMED=1" || echo "CALIBRATION_NAMED=0"

echo "--- HALF 2: an address that is ALLOWED. The log must stay SILENT for it. ---"
PROVIP=$(getent ahostsv4 api.anthropic.com 2>/dev/null | awk '{print $1}' | head -1)
echo "DISCRIM_TARGET=${PROVIP:-NONE}"
echo "PROV_IN_SET=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -c "\b$PROVIP\b")"
MARK2=$(dmesg 2>/dev/null | wc -l)
su -s /bin/bash -c "timeout 8 bash -c 'exec 3<>/dev/tcp/$PROVIP/443'" clawuser >/dev/null 2>&1 && echo "PROV_TCP=CONNECTED" || echo "PROV_TCP=blocked"
sleep 3
NOISE=$(dmesg 2>/dev/null | tail -n +$((MARK2+1)) | grep -c "SKDROP:.*DST=$PROVIP")
echo "DISCRIM_HITS=$NOISE"
[ "$NOISE" -eq 0 ] && echo "DISCRIMINATES=1" || echo "DISCRIMINATES=0"
'@
W $cal.Out
$calNamed = $cal.Out -match 'CALIBRATION_NAMED=1'
$calDiscr = $cal.Out -match 'DISCRIMINATES=1'
Register-Control -Id 'SK.0.CTL1' -Name 'the drop log NAMES an address that must be dropped' `
    -Fired $calNamed `
    -Evidence "target $(if ($cal.Out -match 'CALIBRATION_TARGET=(\S+)') { $Matches[1] } else { '?' }), hits $(if ($cal.Out -match 'CALIBRATION_HITS=(\d+)') { $Matches[1] } else { '?' }) (must be more than 0)" | Out-Null
Register-Control -Id 'SK.0.CTL2' -Name 'the drop log stays SILENT for an address that IS allowed' `
    -Fired $calDiscr `
    -Evidence ("target $(if ($cal.Out -match 'DISCRIM_TARGET=(\S+)') { $Matches[1] } else { '?' }), " +
               "in_set=$(if ($cal.Out -match 'PROV_IN_SET=(\d+)') { $Matches[1] } else { '?' }), " +
               "tcp=$(if ($cal.Out -match 'PROV_TCP=(\S+)') { $Matches[1] } else { '?' }), " +
               "spurious hits $(if ($cal.Out -match 'DISCRIM_HITS=(\d+)') { $Matches[1] } else { '?' }) (must be 0). " +
               'Without this half, an instrument placed above the allowlist accept would report drops for traffic that was in fact accepted.') | Out-Null
$instrumentOk = $calNamed -and $calDiscr

# =========================================================================
Section '1. Set the precondition explicitly: toggle ON, and measure what ON reaches'
# The handoff warns that the toggle was left ON by the #261 diagnostic while
# SP.9 reports it OFF. Neither is trusted. It is SET here and read back.
$onState = Invoke-WslFile -Tag 'sk-on' -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl toolchain on 2>&1 | tail -2
echo "POLICY_AFTER_ON=$(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))' 2>/dev/null || echo unknown)"
echo "TOOLCHAIN_COUNT_ON=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
echo "--- what each hub hostname resolves to RIGHT NOW, and whether those addresses are in a set ---"
for h in clawhub.ai api.clawhub.ai openclaw.ai; do
  A=$(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')
  echo "RESOLVE $h -> $A"
  for ip in $A; do
    IN_ALLOWED=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -c "\b$ip\b")
    IN_TOOL=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -c "\b$ip\b")
    echo "  MEMBER $h $ip allowed=$IN_ALLOWED toolchain=$IN_TOOL"
  done
done
'@
W $onState.Out
$toggleOn = $onState.Out -match 'POLICY_AFTER_ON=true'
Record 'SK.1a' 'The toolchain toggle was SET on by this phase, not inherited from a previous one' `
    $(if ($toggleOn) { 'PASS' } else { 'FAIL' }) `
    ("policy reads $(if ($onState.Out -match 'POLICY_AFTER_ON=(\w+)') { $Matches[1] } else { '?' }) after an explicit switch-on, " +
     "toolchain_ipv4 holds $(if ($onState.Out -match 'TOOLCHAIN_COUNT_ON=(\d+)') { $Matches[1] } else { '?' }). " +
     'Set and read back rather than inherited: the handoff records SP.9 reporting OFF while a later diagnostic left it ON.')

# Both hub hostnames, reachability with the toggle ON. This is the row that makes
# a toggle-OFF failure attributable, and its absence is what made cfv-167
# unreadable.
$ProbeFn = @'
probe() {
  if timeout 10 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then echo "$1:$2 CONNECTED"; else echo "$1:$2 blocked"; fi
}
'@
$hubOn = Invoke-WslFile -Tag 'sk-hub-on' -User 'clawuser' -Body @"
$ProbeFn
echo '--- SUBJECT: both ClawHub hostnames, toggle ON ---'
for h in clawhub.ai api.clawhub.ai; do probe `$h 443; done
echo '--- CONTROL A (MUST CONNECT): the provider route, which no toggle may affect ---'
probe api.anthropic.com 443
echo '--- CONTROL B (MUST BE REFUSED): a site nobody allowed ---'
probe example.org 443
"@
W $hubOn.Out
$hubOnA   = $hubOn.Out -match '(?m)^clawhub\.ai:443 CONNECTED'
$hubOnApi = $hubOn.Out -match 'api\.clawhub\.ai:443 CONNECTED'
$provOn   = $hubOn.Out -match 'api\.anthropic\.com:443 CONNECTED'
$negOn    = $hubOn.Out -match 'example\.org:443 blocked'
Register-Control -Id 'SK.1.CTL' -Name 'the reachability probe can both connect and be refused in the same run' `
    -Fired ($provOn -and $negOn) `
    -Evidence "provider reachable=$provOn (must be true); un-allowlisted site refused=$negOn (must be true)" | Out-Null
Record 'SK.1b' 'With the toggle ON, which ClawHub hostnames are actually reachable' `
    $(if ($hubOnA -and $hubOnApi) { 'PASS' } else { 'FAIL' }) `
    ("clawhub.ai CONNECTED=$hubOnA, api.clawhub.ai CONNECTED=$hubOnApi, both with the toggle ON. " +
     'A hostname unreachable HERE cannot be read as closed by the toggle later. Step 1 measured api.clawhub.ai resolving to addresses that were in NO set while the toggle was ON, which is the card #261 rotating-pool gap appearing outside GitHub.')

# =========================================================================
Section '2. Find a real ClawHub skill slug to install'
# Discovered rather than hard-coded. A slug invented here that does not exist
# would fail to install with the toggle OFF for a reason that has nothing to do
# with the toggle, and would look exactly like the toggle working.
# search may or may not require a query term. Several forms are tried and ALL
# of their output is printed, because a phase that voided for want of an
# argument would have spent a VM run saying nothing.
$search = Invoke-WslFile -Tag 'sk-search' -User 'clawuser' -Body @'
for q in "" "git" "a" "e"; do
  echo "=== openclaw skills search ${q:-<no argument>} ==="
  if [ -z "$q" ]; then timeout 120 openclaw skills search 2>&1 | head -30
  else timeout 120 openclaw skills search "$q" 2>&1 | head -30; fi
  echo "SEARCH_RC=$?"
done
echo "=== openclaw skills list (what is already available, so the subject targets one that is NOT installed) ==="
timeout 60 openclaw skills list 2>&1 | head -40
echo "=== openclaw skills check ==="
timeout 60 openclaw skills check 2>&1 | head -20
'@
W $search.Out
# The slug is parsed out of the search output. Anything that looks like a slug
# on a line of its own or in a list column.
#
# The parser is itself a probe (AN AUDIT REGEX IS ITSELF A PROBE), so it is run
# against a rigged line whose answer is known BEFORE it is trusted on the real
# output, and against a line it must reject. A parser that scraped "SEARCH_RC"
# or a banner word out of this transcript would hand the install arm a slug that
# does not exist, and a nonexistent slug fails with the toggle off for reasons
# that have nothing to do with the toggle.
function Get-Slug([string[]]$Lines) {
    foreach ($line in $Lines) {
        if ($line -match '^\s*(===|SEARCH_RC|Usage:|Options:|Commands:|Docs:|Error|error)') { continue }
        if ($line -match '=') { continue }
        if ($line -match '^\s*([a-z][a-z0-9-]{2,40})\s{2,}\S') { return $Matches[1] }
        if ($line -match '^\s*[-*]\s+([a-z][a-z0-9-]{2,40})\s*$') { return $Matches[1] }
    }
    return $null
}
function Get-Slugs([string[]]$Lines) {
    $out = New-Object System.Collections.ArrayList
    foreach ($line in $Lines) {
        if ($line -match '^\s*(===|SEARCH_RC|Usage:|Options:|Commands:|Docs:|Error|error)') { continue }
        if ($line -match '=') { continue }
        if ($line -match '^\s*([a-z][a-z0-9-]{2,40})\s{2,}\S') { if ($out -notcontains $Matches[1]) { [void]$out.Add($Matches[1]) } }
    }
    return $out.ToArray()
}
$slugPosCtl = (Get-Slug @('  hello-world      A rigged line whose answer is known')) -eq 'hello-world'
$slugNegCtl = ($null -eq (Get-Slug @('SEARCH_RC=0', '=== openclaw skills search ===', 'Usage: openclaw skills')))
Register-Control -Id 'SK.2.CTL' -Name 'the slug parser finds a known slug AND rejects the transcript furniture around it' `
    -Fired ($slugPosCtl -and $slugNegCtl) `
    -Evidence ("rigged line parsed correctly=$slugPosCtl, banner and RC lines correctly rejected=$slugNegCtl. " +
               'A parser that scraped a banner word would supply a nonexistent slug, which fails with the toggle off for its own reasons and is indistinguishable from the toggle working.') | Out-Null
$slug = if ($slugPosCtl -and $slugNegCtl) { Get-Slug ($search.Out -split "`r?`n") } else { $null }
Record 'SK.2a' 'A real ClawHub skill slug was discovered from the product, not invented' `
    $(if ($slug) { 'PASS' } else { 'FAIL' }) `
    ("slug=$(if ($slug) { $slug } else { 'NONE FOUND' }). " +
     'Parsed from openclaw skills search run with the toggle ON. An invented slug would fail to install for a reason unrelated to the toggle and would be indistinguishable from the toggle working.')

# RESOLVE THE TARGET TO SOMETHING UNAMBIGUOUS, and do it with a READ.
#
# Run 1 of this phase picked the slug "git", which is real but is published by
# two owners, so both arms died on a 409 AMBIGUOUS_SKILL_SLUG and the control
# could not fire. A slug that cannot install in ANY toggle state is a broken
# measurement, not a product finding.
#
# The resolution uses `skills info`, which reads rather than installs, so it
# cannot populate a cache that the toggle-OFF subject would later succeed from.
# That ordering constraint is the whole reason the subject runs first.
# Run 2 tried to resolve this with `skills info`, which turned out to read only
# LOCALLY INSTALLED skills: it answered "Skill git not found" for a slug the hub
# had just returned from search, so the target stayed ambiguous and both arms
# died on the 409 a second time.
#
# The resolution therefore comes from the hub's own 409, which lists the fully
# qualified refs the slug could mean. An attempt that ends in 409 INSTALLS
# NOTHING, so it cannot seed a cache the toggle-OFF subject would later succeed
# from. The workspace is swept immediately afterwards regardless, so the subject
# arm is a fresh install even in the branch where this attempt succeeds.
$candidates = @(Get-Slugs ($search.Out -split "`r?`n")) | Select-Object -First 6
$target = $null
if ($candidates.Count -gt 0) {
    $candList = $candidates -join ' '
    $findExpr = '\( ' + (($candidates | ForEach-Object { "-name `"$_`"" }) -join ' -o ') + ' \)'
    # The bash body is a NON-INTERPOLATING here-string with placeholders, and the
    # candidate list is substituted afterwards.
    #
    # Run 4 of this phase used an interpolating here-string and escaped its shell
    # variables C-style, as backslash-dollar. Inside @"..."@ a literal dollar
    # needs a BACKTICK, so every one of them emitted a stray backslash and then
    # interpolated an undefined PowerShell variable to empty. The loop reached
    # bash as 'su: user  rc=" does n  swept "; done', produced no candidate
    # result at all, and the sweep control caught it. Placeholders remove the
    # entire class of error rather than fixing one instance of it.
    $resolveBody = @'
# Try candidates with the toggle ON until one INSTALLS CLEANLY, then sweep it.
#
# Run 2 tried skills info, which reads only LOCALLY INSTALLED skills and answered
# "not found" for a slug the hub had just returned from search. Run 3 tried the
# fully qualified ref the hub's own 409 supplies, and the CLI rejected it locally
# with "Invalid skill slug" before opening a socket. So the only target this
# command accepts is a bare slug that is unique on the hub, and the only way to
# know which of those is unique is to try them.
#
# Each attempt is swept immediately, so the toggle-OFF subject that follows is
# still a fresh install.
TARGET=NONE
for s in __CANDLIST__; do
  echo "--- candidate: $s ---"
  su -s /bin/bash -c "cd /home/clawuser && timeout 120 openclaw skills install $s" clawuser 2>&1 | head -8
  RC=${PIPESTATUS[0]}
  echo "CANDIDATE $s rc=$RC"
  if [ "$RC" -eq 0 ]; then TARGET=$s; fi
  for d in $(find /workspaces /home/clawuser -maxdepth 6 -type d -name "$s" 2>/dev/null); do rm -rf "$d"; echo "  swept $d"; done
  if [ "$TARGET" != "NONE" ]; then break; fi
done
echo "RESOLVED_TARGET=$TARGET"
echo "RESOLVE_RESIDUE=$(find /workspaces /home/clawuser -maxdepth 6 -type d __FINDEXPR__ 2>/dev/null | wc -l)"
'@
    $resolveBody = $resolveBody.Replace('__CANDLIST__', $candList).Replace('__FINDEXPR__', $findExpr)
    $resolve = Invoke-WslFile -Tag 'sk-resolve' -User 'root' -Body $resolveBody
    W $resolve.Out
    $tm = [regex]::Match($resolve.Out, 'RESOLVED_TARGET=(\S+)')
    if ($tm.Success -and $tm.Groups[1].Value -ne 'NONE') { $target = $tm.Groups[1].Value }
    Register-Control -Id 'SK.2.CTL2' -Name 'the workspace was swept after every resolution attempt, so the subject arm is still a fresh install' `
        -Fired ($resolve.Out -match 'RESOLVE_RESIDUE=0') `
        -Evidence 'without this, a resolution attempt that succeeded would leave the skill on disk and the toggle-OFF subject would "succeed" from it without a packet leaving the box' | Out-Null
}
Record 'SK.2b' 'The install target was resolved to something unambiguous before either arm ran' `
    $(if ($target) { 'INFO' } else { 'INFO' }) `
    ("first-parsed slug=$slug, candidates tried=$($candidates -join ', '), RESOLVED TARGET=$(if ($target) { $target } else { 'NONE INSTALLABLE' }). " +
     'Three resolution routes were tried and two were dead ends worth recording: the bare slug "git" is published by two owners and 409s as AMBIGUOUS_SKILL_SLUG; the fully qualified ref the hub returns in that 409 is rejected LOCALLY by the CLI as "Invalid skill slug" before any socket opens; and skills info reads only locally installed skills, so it answers "not found" for a slug search had just returned. ' +
     'The only target this command accepts is a bare slug that is unique on the hub, so candidates are tried with the toggle ON until one installs cleanly, and each attempt is swept immediately.')

$pre = Require-Precondition -Id 'SK.PRE' `
    -Name 'the instrument calibrated in both directions AND a real installable slug exists' `
    -Met ($instrumentOk -and $target -and $toggleOn) `
    -Reason ("instrument calibrated both ways=$instrumentOk, an INSTALLABLE target was resolved=$([bool]$target) (target=$target), toggle set on=$toggleOn. " +
             'All three are needed: an uncalibrated drop log cannot attribute a block, an invented slug fails for its own reasons, and an unset toggle means the control arm was never in a known state.')

if (-not $pre) {
    Record 'SK.3' 'A real skill installation with the toolchain toggle OFF' 'VOID' `
        'NOT RUN. Its preconditions were not met, so no packet was sent and nothing here is a statement about the toggle.'
    Record 'SK.4' 'CONTROL: the same installation with the toolchain toggle ON' 'VOID' `
        'NOT RUN, for the same reason.'
    Complete-Phase -ResultsJson 'C:\cfv\skillinstall-results.json' -MarkerPrefix 'SKILLINSTALL'
}

# =========================================================================
Section "3. SUBJECT: install skill '$target' with the toolchain toggle OFF"
$offRun = Invoke-WslFile -Tag 'sk-off' -User 'root' -Body @"
set -u
/usr/local/sbin/clawfactory-fetchctl toolchain off 2>&1 | tail -2
echo "POLICY_AFTER_OFF=`$(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))' 2>/dev/null || echo unknown)"
echo "TOOLCHAIN_COUNT_OFF=`$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
echo "--- 216.150.1.1 is clawhub.ai AND openclaw.ai. It should still be in allowed_ipv4, which is the whole finding. ---"
echo "HUB_ADDR_IN_ALLOWED=`$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -c '216\.150\.1\.1\b')"

MARK=`$(dmesg 2>/dev/null | wc -l)
echo "--- THE INSTALL, as uid 1000, toggle OFF ---"
# The install runs in the background so its ESTABLISHED peers can be sampled
# while it is talking. A 409 from the hub already proves the connection
# succeeded, but it does not name the ADDRESS, and the address is the whole
# question: 216.150.1.1 is the co-hosted base host, anything else is not.
: > /var/tmp/sk-off.conns
su -s /bin/bash -c "cd /home/clawuser && timeout 180 openclaw skills install $target" clawuser > /var/tmp/sk-off.log 2>&1 &
IPID=`$!
while kill -0 "`$IPID" 2>/dev/null; do
  ss -tnH state established 2>/dev/null | awk '{print `$4}' >> /var/tmp/sk-off.conns
  sleep 0.2
done
wait "`$IPID"; echo "INSTALL_OFF_RC=`$?"
head -60 /var/tmp/sk-off.log
echo "--- remote :443 peers this box actually held open during the toggle-OFF install ---"
sort -u /var/tmp/sk-off.conns | grep ':443`$' | sed 's/^/OFFPEER /'
sleep 3
echo "--- every address this box was refused a route to during the install ---"
dmesg 2>/dev/null | tail -n +`$((MARK+1)) | grep "SKDROP:" \
  | sed -nE 's/.*DST=([0-9.]+).*DPT=([0-9]+).*/OFFDROP \1 \2/p' | sort | uniq -c
echo "OFF_DROP_TOTAL=`$(dmesg 2>/dev/null | tail -n +`$((MARK+1)) | grep -c 'SKDROP:')"
echo "--- did the skill land on disk? ---"
find /workspaces /home/clawuser -maxdepth 6 -type d -name '$target' 2>/dev/null | sed 's/^/OFF_ONDISK /'
"@
W $offRun.Out
$offRc      = if ($offRun.Out -match 'INSTALL_OFF_RC=(\d+)') { [int]$Matches[1] } else { -1 }
$offOnDisk  = $offRun.Out -match 'OFF_ONDISK /'
$offSucceeded = ($offRc -eq 0) -and $offOnDisk
$toggleOff  = $offRun.Out -match 'POLICY_AFTER_OFF=false'
$hubStillAllowed = if ($offRun.Out -match 'HUB_ADDR_IN_ALLOWED=(\d+)') { [int]$Matches[1] -gt 0 } else { $false }

# =========================================================================
Section '4. Clear what the subject left, so the control is a genuine fresh install'
$clear = Invoke-WslFile -Tag 'sk-clear' -User 'root' -Body @"
for d in `$(find /workspaces /home/clawuser -maxdepth 6 -type d -name '$target' 2>/dev/null); do rm -rf "`$d"; echo "REMOVED `$d"; done
echo "REMAINING=`$(find /workspaces /home/clawuser -maxdepth 6 -type d -name '$target' 2>/dev/null | wc -l)"
"@
W $clear.Out
$cleared = $clear.Out -match 'REMAINING=0'
Record 'SK.4a' 'The subject left nothing on disk for the control to succeed from' `
    $(if ($cleared) { 'PASS' } else { 'FAIL' }) `
    'the control arm is only a fresh install if the workspace skill directory is gone before it runs'

# =========================================================================
Section "5. CONTROL: the SAME installation with the toolchain toggle ON"
# Without this, a failure with the toggle off proves nothing: it could be a bad
# slug, a hub outage, an expired token, or the #261 pool gap.
$onRun = Invoke-WslFile -Tag 'sk-on-run' -User 'root' -Body @"
set -u
/usr/local/sbin/clawfactory-fetchctl toolchain on 2>&1 | tail -2
echo "POLICY_AFTER_ON2=`$(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))' 2>/dev/null || echo unknown)"
MARK=`$(dmesg 2>/dev/null | wc -l)
echo "--- THE SAME INSTALL, as uid 1000, toggle ON ---"
: > /var/tmp/sk-on.conns
su -s /bin/bash -c "cd /home/clawuser && timeout 180 openclaw skills install $target" clawuser > /var/tmp/sk-on.log 2>&1 &
IPID=`$!
while kill -0 "`$IPID" 2>/dev/null; do
  ss -tnH state established 2>/dev/null | awk '{print `$4}' >> /var/tmp/sk-on.conns
  sleep 0.2
done
wait "`$IPID"; echo "INSTALL_ON_RC=`$?"
head -60 /var/tmp/sk-on.log
echo "--- remote :443 peers held open during the toggle-ON control install ---"
sort -u /var/tmp/sk-on.conns | grep ':443`$' | sed 's/^/ONPEER /'
sleep 3
dmesg 2>/dev/null | tail -n +`$((MARK+1)) | grep "SKDROP:" \
  | sed -nE 's/.*DST=([0-9.]+).*DPT=([0-9]+).*/ONDROP \1 \2/p' | sort | uniq -c
echo "ON_DROP_TOTAL=`$(dmesg 2>/dev/null | tail -n +`$((MARK+1)) | grep -c 'SKDROP:')"
find /workspaces /home/clawuser -maxdepth 6 -type d -name '$target' 2>/dev/null | sed 's/^/ON_ONDISK /'
"@
W $onRun.Out
$onRc     = if ($onRun.Out -match 'INSTALL_ON_RC=(\d+)') { [int]$Matches[1] } else { -1 }
$onOnDisk = $onRun.Out -match 'ON_ONDISK /'
$onSucceeded = ($onRc -eq 0) -and $onOnDisk

Register-Control -Id 'SK.5.CTL' -Name 'the SAME skill installation succeeds with the toggle ON' `
    -Fired $onSucceeded `
    -Evidence ("exit=$onRc, landed on disk=$onOnDisk. " +
               'If this did not succeed, the toggle-OFF arm is unattributable: it would have failed with the toggle ON too, which is exactly the cfv-167 error.') | Out-Null

Record 'SK.5' 'CONTROL: the same installation completes with the toolchain toggle ON' `
    $(if ($onSucceeded) { 'PASS' } else { 'FAIL' }) `
    "openclaw skills install $target exited $onRc with the toggle ON, on disk=$onOnDisk"

# =========================================================================
# Peers are parsed BEFORE the answer block, because the answer branches on whether
# the toggle-OFF arm ever held a socket at all.
$offPeers = @([regex]::Matches($offRun.Out, '(?m)^OFFPEER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
$onPeers  = @([regex]::Matches($onRun.Out,  '(?m)^ONPEER\s+(\S+)')  | ForEach-Object { $_.Groups[1].Value })
$offHitCoHost = @($offPeers | Where-Object { $_ -like '216.150.1.1:*' }).Count -gt 0
Section '6. THE ANSWER'
$subjectPre = Require-Precondition -Id 'SK.3.PRE' `
    -Name 'the same installation succeeds with the toggle ON, in this same run' `
    -Met $onSucceeded `
    -Reason ('a skill installation that fails in BOTH toggle states is a hub, slug or #261 pool failure, not a toggle finding. ' +
             'Recording it as a toggle finding is the inference cfv-166 made and cfv-167 refuted.')

if (-not $subjectPre) {
    Record 'SK.3' 'A real skill installation with the toolchain toggle OFF' 'VOID' `
        ("NOT INTERPRETABLE. The install exited $offRc with the toggle OFF, but the control arm with the toggle ON also did not succeed (exit $onRc), " +
         'so nothing here separates the toggle from a hub outage, a bad slug, or the card #261 rotating-pool gap.')
} elseif ($offSucceeded -and $offPeers.Count -eq 0) {
    # A SUCCESS WITH NO SOCKET IS NOT A NETWORK RESULT. If the toggle-OFF arm
    # completed without ever holding a :443 peer, it was satisfied from
    # something already on the box, and recording that as "the toggle does not
    # stop installation" would be the strongest possible claim drawn from the
    # weakest possible evidence.
    Record 'SK.3' 'A real skill installation with the toolchain toggle OFF' 'VOID' `
        ("the install exited $offRc with the toggle OFF and the skill landed on disk, but NO established :443 peer was sampled while it ran, " +
         'so it cannot be shown to have crossed the network at all. A local cache satisfying the install is indistinguishable here from a route staying open, ' +
         'and the two have opposite meanings for the panel copy. Re-run with the cache cleared before treating this as a toggle result.')
} else {
    Record 'SK.3' 'A real skill installation with the toolchain toggle OFF' `
        $(if ($offSucceeded) { 'FAIL' } else { 'PASS' }) `
        ("openclaw skills install $target exited $offRc with the toggle OFF, landed on disk=$offOnDisk, " +
         "policy read back as off=$toggleOff, 216.150.1.1 still in allowed_ipv4=$hubStillAllowed. " +
         'PASS here means the toggle DID stop skill installation and the shipped copy is accurate as written. ' +
         'FAIL means the installation completed with the toggle off, and the copy on clawfactory-fetchctl.js:262 and the Studio Web access panel overstates what the control does. ' +
         'This phase does not change either. The decision is the operator I report to.')
}

# THE ATTRIBUTION ROW. 216.150.1.1 is the address clawhub.ai and openclaw.ai
# share, and it is the one @allowed_ipv4 holds permanently. Seeing it as a live
# peer during a toggle-OFF install is what turns "the hub answered" into "the
# hub was reached THROUGH the co-hosted base host", which is the finding.

Record 'SK.6a' 'The toggle-OFF install held a connection to 216.150.1.1, the address clawhub.ai shares with the permanently-allowed openclaw.ai' `
    $(if ($offPeers.Count -gt 0) { 'INFO' } else { 'INFO' }) `
    ("peers observed during the toggle-OFF install: $(if ($offPeers.Count) { $offPeers -join ', ' } else { 'NONE SAMPLED' }). " +
     "co-hosted base address 216.150.1.1 among them=$offHitCoHost. " +
     "peers during the toggle-ON control: $(if ($onPeers.Count) { $onPeers -join ', ' } else { 'NONE SAMPLED' }). " +
     'Sampled from ss while the install was running. This is what separates "installation reached the hub" from "installation reached the hub through the base host no toggle can revoke".')

Record 'SK.6' 'Which addresses the installation was refused a route to, with the toggle OFF' 'INFO' `
    ("total drop lines during the toggle-OFF install=$(if ($offRun.Out -match 'OFF_DROP_TOTAL=(\d+)') { $Matches[1] } else { '?' }); " +
     "during the toggle-ON control=$(if ($onRun.Out -match 'ON_DROP_TOTAL=(\d+)') { $Matches[1] } else { '?' }). " +
     'The per-address OFFDROP and ONDROP tallies are in the transcript. 216.150.1.1 is clawhub.ai and openclaw.ai together; api.clawhub.ai resolves elsewhere.')

# =========================================================================
Section '7. Put the box back, and prove the firewall was left intact'
$restore = Invoke-WslFile -Tag 'sk-restore' -User 'root' -Body @"
for d in `$(find /workspaces /home/clawuser -maxdepth 6 -type d -name '$target' 2>/dev/null); do rm -rf "`$d"; echo "CLEANED `$d"; done
H=`$(nft -a list chain inet clawfactory output 2>/dev/null | grep 'SKDROP' | grep -oE 'handle [0-9]+' | awk '{print `$2}' | head -1)
if [ -n "`${H:-}" ]; then nft delete rule inet clawfactory output handle "`$H" && echo "INSTRUMENT_REMOVED=1"; else echo "INSTRUMENT_ALREADY_GONE=1"; fi
echo "INSTRUMENT_STILL_PRESENT=`$(nft list chain inet clawfactory output 2>/dev/null | grep -c 'SKDROP')"
/usr/local/sbin/clawfactory-fetchctl toolchain on 2>&1 | tail -1
echo "FINAL_POLICY=`$(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))' 2>/dev/null || echo unknown)"
/usr/local/sbin/clawfactory-fw-assert.sh 2>&1; echo "fw_assert_rc=`$?"
"@
W $restore.Out
Record 'SK.7' 'The box is left in the shipped default state and the chain-shape tripwire passes' `
    $(if (($restore.Out -match 'INSTRUMENT_STILL_PRESENT=0') -and ($restore.Out -match 'FINAL_POLICY=true') -and ($restore.Out -match 'fw_assert_rc=0')) { 'PASS' } else { 'FAIL' }) `
    'the log rule is removed, the toggle is back on, and fw-assert confirms the chain shape is unmodified'

Complete-Phase -ResultsJson 'C:\cfv\skillinstall-results.json' -MarkerPrefix 'SKILLINSTALL'
