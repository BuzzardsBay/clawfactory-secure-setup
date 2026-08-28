<#
  #261: a REPEATED-ATTEMPT reachability measurement, as the agent uid.

  WHAT THIS IS FOR, AND WHAT IT DELIBERATELY DOES NOT DO
  ------------------------------------------------------
  #261 is a claim about INTERMITTENCY: the firewall holds a snapshot of addresses
  resolved at one moment, while the services behind those names answer from a
  rotating pool, so a connection that succeeds now can fail in ten seconds with
  nothing having changed. Box A has exactly two samples against that -- one PASS
  before a reboot and one after -- and two samples settle nothing, because one
  PASS and one FAIL are both consistent with the residual exactly as documented.

  So this probe takes MANY attempts per host and REPORTS THE RAW COUNTS. It does
  not propose a fix, does not recommend one, and records no verdict on #261. That
  is the operator's call and he has it.

  TWO QUESTIONS, TWO ROWS, because they are different defects with different cards
  -------------------------------------------------------------------------------
  This is the shape interim-v141-bootpath.ps1 already uses and it is the reason
  that probe could report an honest result where a one-shot probe reported a coin
  flip:

      EXISTS  did the box build a working route to this host AT ALL?   -> a verdict
      ALWAYS  does that route answer on EVERY attempt?                 -> raw count only

  A host that answers 5 times in 12 means EXISTS is true and ALWAYS is false. A
  single-attempt probe collapses those two into one reading and then reports
  whichever one luck handed it.

  CLAUSE 1 -- DISCOVER, DO NOT ASSUME.
  The subject hosts are not hardcoded guesses. The toolchain set and the
  read-fetch set are READ OFF THE BOX from the files the product itself writes,
  printed, and only then probed. A probe that asserts against a host the box does
  not actually allow measures the guess, not the product.

  CLAUSE 2 -- CLASSIFY.
  Every host lands in exactly one of three named states, and the state is printed:
      ALWAYS      ok == n
      INTERMITTENT 0 < ok < n
      NEVER       ok == 0
  "not blocked" is not a state here, because it is satisfied by a probe that never
  ran.
#>
param(
    [string]$Transcript = 'C:\cfv\attempts-out.txt',
    [int]$Attempts      = 12,
    # Timeout per attempt, seconds. Kept short deliberately: a long timeout turns
    # an intermittency measurement into a patience measurement.
    [int]$TimeoutSec    = 8,
    # CONTROLS. The provider route is never touched by any switch, so it must
    # answer; the deny host is on no list at all, so it must not. Both are read
    # back as counts, not as booleans.
    [string]$ProviderHost = 'api.anthropic.com',
    [string]$DenyHost     = 'example.org',
    [string]$ResultsJson  = 'C:\cfv\attempts-results.json',
    # Where the channel and the phase runner live. A parameter, not a constant, so
    # this probe can be DRY-RUN on the build machine against a rigged channel that
    # returns known output, before it is ever pointed at a real box. Every probe
    # box A wrote after hour four was defective and none of them could be dry-run.
    [string]$LibDir       = 'C:\cfv'
)

$ErrorActionPreference = 'Continue'
. (Join-Path $LibDir 'interim-v120-wslchan.ps1')
. (Join-Path $LibDir 'interim-v120-phaselib.ps1')

Start-Phase -Name "#261 repeated-attempt reachability, $Attempts attempts per host, as uid 1000" `
    -Transcript $Transcript -Sentinel 'ATTEMPTS_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'AT.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'ATTEMPTS' }

# =========================================================================
Section '0. DISCOVER the state and the subject hosts, from the files the product writes'
$state = Invoke-WslFile -Tag 'at-state' -User 'root' -Body @'
echo "TC_ENABLED=$(node -e 'try{const p=require("/etc/clawfactory/egress-policy.json");console.log(!!(p.toolchain&&p.toolchain.enabled))}catch(e){console.log("unreadable")}' 2>&1)"
echo "TC_SET_COUNT=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -Eo '[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+' | sort -u | wc -l | tr -d ' ')"
echo "RF_SET_COUNT=$(nft list set inet clawfactory read_fetch_ipv4 2>/dev/null | grep -Eo '[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+' | sort -u | wc -l | tr -d ' ')"
echo "--- everything the product actually wrote here, so the reads below are not guesses ---"
ls -1 /etc/clawfactory 2>&1 | sed 's/^/ETC /'
echo "--- toolchain host list. setup.ps1:1721 writes it, and this is the name it writes:"
echo "      printf '%s\n' \"\$TOOLCHAIN_HOSTS\" > /etc/clawfactory/toolchain-hosts.seed"
sed -n '1,40p' /etc/clawfactory/toolchain-hosts.seed 2>/dev/null | sed 's/^/TC_HOST /'
echo "--- read-fetch host list. resources/clawfactory-read-fetch.sh:36 -> HOSTS_FILE=/etc/clawfactory/read-fetch-hosts.txt"
sed -n '1,40p' /etc/clawfactory/read-fetch-hosts.txt 2>/dev/null | sed 's/^/RF_HOST /'
'@
W $state.Out

$tcHosts = @()
foreach ($line in ($state.Out -split "`n")) {
    if ($line -match '^\s*TC_HOST\s+(\S+)') { $tcHosts += $Matches[1] }
}
$rfHosts = @()
foreach ($line in ($state.Out -split "`n")) {
    if ($line -match '^\s*RF_HOST\s+(\S+)') { $rfHosts += $Matches[1] }
}
$tcHosts = @($tcHosts | Where-Object { $_ -match '^[a-z0-9]' } | Sort-Object -Unique)
$rfHosts = @($rfHosts | Where-Object { $_ -match '^[a-z0-9]' } | Sort-Object -Unique)
W "DISCOVERED_TOOLCHAIN_HOSTS  = $(if ($tcHosts.Count) { $tcHosts -join ' ' } else { '(none)' })"
W "DISCOVERED_READFETCH_HOSTS  = $(if ($rfHosts.Count) { $rfHosts -join ' ' } else { '(none)' })"

$tcEnabled = $state.Out -match 'TC_ENABLED=true'
W "TOOLCHAIN_SWITCH_ENABLED    = $tcEnabled"

# A repeated-attempt measurement of the toolchain route means nothing with the
# switch off: zero of twelve would then be the switch working, not #261.
$switchOn = Require-Precondition -Id 'AT.PRE.SWITCH' -Name 'the toolchain switch is ON, so the toolchain hosts are supposed to be reachable' `
    -Met ([bool]$tcEnabled) `
    -Reason "TC_ENABLED reads '$(if ($state.Out -match 'TC_ENABLED=(\S+)') { $Matches[1] } else { 'unreadable' })'. With the switch OFF a count of 0 of $Attempts is the switch doing its job, not the intermittency #261 describes, and the two readings are indistinguishable from the counts alone"

$haveSubjects = Require-Precondition -Id 'AT.PRE.HOSTS' -Name 'at least one toolchain host was discovered on the box' `
    -Met ($tcHosts.Count -gt 0) `
    -Reason 'the subject list is read off the box rather than hardcoded, so an empty list means there is nothing to measure rather than nothing reachable'

# =========================================================================
Section "1. $Attempts attempts per host, as uid 1000"
$subjects = @()
$subjects += $tcHosts
$subjects += $rfHosts
$subjects = @($subjects | Sort-Object -Unique)
$allHosts = @($subjects + @($ProviderHost, $DenyHost) | Sort-Object -Unique)

$hostArg = ($allHosts -join ' ')
$body = @"
probe() {
  ok=0; n=$Attempts
  for i in `$(seq 1 `$n); do
    if timeout $TimeoutSec bash -c "exec 3<>/dev/tcp/`$1/443" 2>/dev/null; then ok=`$((ok+1)); fi
  done
  echo "ATT `$1 ok=`$ok n=`$n"
}
echo "whoami=`$(id -un) uid=`$(id -u)"
for h in $hostArg; do probe `$h; done
"@
$r = Invoke-WslFile -Tag 'at-probe' -User 'clawuser' -Body $body
W $r.Out

$counts = @{}
foreach ($line in ($r.Out -split "`n")) {
    if ($line -match 'ATT\s+(\S+)\s+ok=(\d+)\s+n=(\d+)') {
        $counts[$Matches[1]] = @{ Ok = [int]$Matches[2]; N = [int]$Matches[3] }
    }
}
W "HOSTS_MEASURED=$($counts.Count) of $($allHosts.Count) requested"

function StateOf($h) {
    if (-not $counts.ContainsKey($h)) { return 'NOT_MEASURED' }
    $c = $counts[$h]
    if ($c.Ok -eq 0)      { return 'NEVER' }
    if ($c.Ok -eq $c.N)   { return 'ALWAYS' }
    return 'INTERMITTENT'
}
function CountOf($h) {
    if (-not $counts.ContainsKey($h)) { return '(not measured)' }
    return "$($counts[$h].Ok)/$($counts[$h].N)"
}
foreach ($h in $allHosts) { W ("  {0,-32} {1,-8} {2}" -f $h, (CountOf $h), (StateOf $h)) }

# =========================================================================
Section '2. CONTROLS, both directions, in this same run'
$provOk  = ($counts.ContainsKey($ProviderHost)) -and ($counts[$ProviderHost].Ok -gt 0)
$denyOk  = ($counts.ContainsKey($DenyHost))     -and ($counts[$DenyHost].Ok -eq 0)
Register-Control -Id 'AT.CTL' -Name 'the probe can BOTH connect and be refused in this same run' `
    -Fired ($provOk -and $denyOk) `
    -Evidence "$ProviderHost $(CountOf $ProviderHost) (must be > 0 of $Attempts) and $DenyHost $(CountOf $DenyHost) (must be 0 of $Attempts). Without both halves a column of zeros could just be a dead network and a column of full counts could just be a probe that always says yes" | Out-Null
Record 'AT.CTL.DENY' "CONTROL: $DenyHost is on no list and answers on NO attempt" `
    $(if ($counts.ContainsKey($DenyHost)) { $(if ($denyOk) { 'PASS' } else { 'FAIL' }) } else { 'VOID' }) `
    "$(CountOf $DenyHost), state=$(StateOf $DenyHost)"

# =========================================================================
Section '3. THE MEASUREMENT. Two rows per host, and no verdict on #261'
foreach ($h in $subjects) {
    $st = StateOf $h
    $cnt = CountOf $h
    $cls = if ($rfHosts -contains $h) { 'read-fetch' } else { 'toolchain' }
    $gated = ($cls -eq 'toolchain') -and (-not $switchOn)

    # EXISTS is a real verdict: it is the boot/refresh path having built a working
    # route at all, which is card #276 territory and is closed.
    Record "AT.EXISTS.$h" "a route to $h ($cls) EXISTS for uid 1000: it answered at least once" `
        $(if (-not $haveSubjects -or $st -eq 'NOT_MEASURED') { 'VOID' } `
          elseif ($gated) { 'VOID' } `
          elseif ($st -eq 'NEVER') { 'FAIL' } else { 'PASS' }) `
        "$cnt attempts connected, state=$st. This row asks ONLY whether a working route was built; whether it answers every time is the row below"

    # ALWAYS is the #261 question. RAW COUNT ONLY, deliberately: the job card
    # directs that this session take samples and report them, fix nothing, and
    # recommend nothing. A PASS/FAIL here would be exactly the single-reading
    # verdict that two prior runs have already produced and that settled nothing.
    # The cause clause is CONDITIONAL. An earlier draft asserted "a shortfall here
    # is the rotating-pool sampling gap rather than a switch position" regardless
    # of the switch, which is false whenever the switch is off -- and a dry-run
    # against a switch-off rig printed exactly that sentence over a 0/12 that the
    # switch had caused. An evidence field that names the wrong cause is the same
    # defect class as a probe that measures the wrong subject.
    $why = if ($cls -eq 'read-fetch') {
        'the toolchain switch does not govern read-fetch hosts, so a shortfall here is not a switch position either way'
    } elseif ($tcEnabled) {
        'the toolchain switch is ON, so a shortfall here is the rotating-pool sampling gap rather than a switch position'
    } else {
        'the toolchain switch is OFF, so a shortfall here may simply be the switch working; this reading cannot separate the two and the phase is voided above for that reason'
    }
    Record "AT.ALWAYS.$h" "how often the route to $h ($cls) answered, raw" 'INFO' `
        "$cnt, state=$st. Recorded as INFO on purpose: this is the #261 intermittency sample and this session takes no verdict, proposes no fix and makes no recommendation about it. $why"
}

Record 'AT.SUMMARY' 'the raw counts, on one line, so the reading survives being quoted out of context' 'INFO' `
    (($allHosts | ForEach-Object { "$_=$(CountOf $_)/$(StateOf $_)" }) -join ' ; ')

Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'ATTEMPTS'
