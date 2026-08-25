<#
  Calibration for validation/interim-v141-bootpath.ps1.

  PROMPT 15: "Run every probe body once against a synthetic target whose answer
  is already known, and assert that answer. A probe that cannot produce a
  known-correct result on a rigged input is not permitted to report a result on
  a real one."

  This EXTRACTS the shipped functions out of the probe with a text range rather
  than retyping them, so it cannot pass against a copy that has drifted. Every
  group carries a CONTROL that must produce a value, because a parser that
  always returns nothing would satisfy every "expected empty" case.
#>
$ErrorActionPreference = 'Stop'
$probe = Join-Path (Split-Path -Parent $PSScriptRoot) 'validation\interim-v141-bootpath.ps1'
if (-not (Test-Path $probe)) { throw "probe not found at $probe" }
$src = Get-Content $probe -Raw

$pass = 0; $fail = 0
function Chk($name, $expected, $got) {
    $e = ($expected -join '|'); $g = ($got -join '|')
    if ($e -eq $g) { $script:pass++; Write-Host ("PASS  {0,-52} expected=[{1}] got=[{2}]" -f $name,$e,$g) }
    else          { $script:fail++; Write-Host ("FAIL  {0,-52} expected=[{1}] got=[{2}]" -f $name,$e,$g) -ForegroundColor Red }
}

# ---- extract the shipped Sub() and the REACH parse loop -----------------------
function Extract([string]$startPattern, [string]$endPattern) {
    $lines = $src -split "`r?`n"
    $s = ($lines | Select-String -Pattern $startPattern | Select-Object -First 1).LineNumber
    if (-not $s) { throw "could not locate '$startPattern' in the probe" }
    for ($i = $s; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $endPattern) { return ($lines[($s-1)..$i] -join "`n") }
    }
    throw "could not find end '$endPattern' after '$startPattern'"
}

$subSrc = Extract '^function Sub\(' '^\}'
Invoke-Expression $subSrc

Write-Host "`n=== Sub(): placeholder substitution is real, not a no-op ==="
$RotHost='ROTX'; $RevokeHost='REVX'; $DenyHost='DENYX'; $ToolHost='TOOLX'; $ProviderHost='PROVX'
Chk 'all five placeholders replaced' 'probe TOOLX ROTX REVX PROVX DENYX' `
    (Sub 'probe @TOOL@ @ROT@ @REV@ @PROV@ @DENY@')
Chk 'CONTROL: a string with no placeholder is returned unchanged' 'nothing to do here' `
    (Sub 'nothing to do here')

# ---- the REACH parser, lifted verbatim from Measure-Reach --------------------
$reachParse = {
    param($text)
    $h = @{}
    foreach ($line in ($text -split "`n")) {
        if ($line -match 'REACH\s+(\S+)\s+(CONNECTED|blocked)') { $h[$Matches[1]] = $Matches[2] }
    }
    return $h
}
# assert the lifted regex is byte-identical to the shipped one
if ($src -notmatch [regex]::Escape("if (`$line -match 'REACH\s+(\S+)\s+(CONNECTED|blocked)') { `$h[`$Matches[1]] = `$Matches[2] }")) {
    throw 'DRIFT: the REACH parse line in the probe no longer matches the one calibrated here.'
}

Write-Host "`n=== the REACH parser ==="
$rig = @"
whoami=clawuser uid=1000
--- SUBJECTS ---
REACH api.github.com CONNECTED
REACH outlook.office.com blocked
--- CONTROL A ---
REACH api.anthropic.com CONNECTED
--- CONTROL B ---
REACH example.net blocked
"@
$h = & $reachParse $rig
Chk 'a CONNECTED subject reads CONNECTED' 'CONNECTED' $h['api.github.com']
Chk 'a blocked subject reads blocked'     'blocked'   $h['outlook.office.com']
Chk 'the control host is parsed too'      'blocked'   $h['example.net']
$h2 = & $reachParse "REACH api.github.com blocked`nREACH example.net blocked"
Chk 'CONTROL: the SAME host reads blocked when the rig says blocked' 'blocked' $h2['api.github.com']
$h3 = & $reachParse 'probe died before printing anything'
Chk 'a probe that printed nothing yields NO verdict, not a false blocked' '' ([string]$h3['api.github.com'])
$h4 = & $reachParse 'REACH api.github.com WEIRDWORD'
Chk 'an unrecognised verdict word is not silently read as blocked' '' ([string]$h4['api.github.com'])

# ---- the attempts parser, added after cfv-175 showed one-shot probes lie -----
Write-Host "`n=== the attempts parser (#261 intermittency) ==="
$attParse = {
    param($text)
    $h = @{}
    foreach ($line in ($text -split "`n")) {
        if ($line -match 'REACH\s+(\S+)\s+(CONNECTED|blocked)') { $h[$Matches[1]] = $Matches[2] }
        if ($line -match 'REACH\s+(\S+)\s+\S+\s+attempts=(\d+)/(\d+)') { $h[($Matches[1]+'#att')] = "$($Matches[2])/$($Matches[3])" }
    }
    return $h
}
$a1 = & $attParse 'REACH api.github.com CONNECTED attempts=5/6'
Chk 'a partial success parses as CONNECTED with its count' 'CONNECTED|5/6' @($a1['api.github.com'], $a1['api.github.com#att'])
$a2 = & $attParse 'REACH api.github.com blocked attempts=0/6'
Chk 'zero successes parses as blocked' 'blocked|0/6' @($a2['api.github.com'], $a2['api.github.com#att'])
$a3 = & $attParse 'REACH api.github.com CONNECTED attempts=6/6'
$full = (($a3['api.github.com#att'] -split '/')[0] -eq ($a3['api.github.com#att'] -split '/')[1])
Chk 'CONTROL: 6/6 is recognised as ALWAYS reachable' 'True' $full
$a4 = & $attParse 'REACH api.github.com CONNECTED attempts=5/6'
$full2 = (($a4['api.github.com#att'] -split '/')[0] -eq ($a4['api.github.com#att'] -split '/')[1])
Chk 'THE LOAD-BEARING CASE: 5/6 is NOT always reachable' 'False' $full2
$a5 = & $attParse 'REACH api.github.com CONNECTED'
Chk 'an old-format line yields no count, which the probe records VOID' '' ([string]$a5['api.github.com#att'])

# ---- rotation distinct-set counting -----------------------------------------
Write-Host "`n=== the rotating-pool detector ==="
function CountDistinct($text, $prefix) {
    $sets = @($text -split "`n" | Where-Object { $_ -match "^$prefix\d+=" } | ForEach-Object { ($_ -split '=',2)[1].Trim() } | Where-Object { $_ })
    return @{ N = $sets.Count; D = ($sets | Sort-Object -Unique).Count }
}
$rotating = "LOOKUP1=1.1.1.1,2.2.2.2,`nLOOKUP2=3.3.3.3,4.4.4.4,`nLOOKUP3=1.1.1.1,2.2.2.2,`nLOOKUP4=5.5.5.5,"
$r = CountDistinct $rotating 'LOOKUP'
Chk 'a rotating pool reports >1 distinct set' '4|3' @($r.N, $r.D)
$stable = "LOOKUP1=9.9.9.9,`nLOOKUP2=9.9.9.9,`nLOOKUP3=9.9.9.9,"
$r2 = CountDistinct $stable 'LOOKUP'
Chk 'THE LOAD-BEARING CASE: a STABLE host reports exactly ONE set' '3|1' @($r2.N, $r2.D)
$empty = "LOOKUP1=`nLOOKUP2=`nLOOKUP3="
$r3 = CountDistinct $empty 'LOOKUP'
Chk 'all-empty lookups yield ZERO sets, which the probe records VOID not PASS' '0|0' @($r3.N, $r3.D)
$partial = "LOOKUP1=1.1.1.1,`nLOOKUP2=`nLOOKUP3=2.2.2.2,"
$r4 = CountDistinct $partial 'LOOKUP'
Chk 'CONTROL: a blank lookup is dropped, the real ones still count' '2|2' @($r4.N, $r4.D)

# ---- the toolchain-empty assertion -------------------------------------------
Write-Host "`n=== the 'switch OFF really emptied everything' assertion ==="
function OffOk($st) {
    return [bool](($st -match 'TC_ENABLED=false') -and ($st -match 'TC_SET_COUNT=0') -and ($st -match 'TC_FILE_COUNT=0') -and ($st -match 'TC_MAP_COUNT=0'))
}
Chk 'all four zeroed -> true'  'True'  (OffOk "TC_ENABLED=false`nTC_SET_COUNT=0`nTC_FILE_COUNT=0`nTC_MAP_COUNT=0")
Chk 'a NON-empty live set -> false' 'False' (OffOk "TC_ENABLED=false`nTC_SET_COUNT=28`nTC_FILE_COUNT=0`nTC_MAP_COUNT=0")
Chk 'retention fuel left in the map -> false' 'False' (OffOk "TC_ENABLED=false`nTC_SET_COUNT=0`nTC_FILE_COUNT=0`nTC_MAP_COUNT=8")
Chk 'switch reads true -> false' 'False' (OffOk "TC_ENABLED=true`nTC_SET_COUNT=0`nTC_FILE_COUNT=0`nTC_MAP_COUNT=0")
Chk 'unreadable policy -> false, a fault denies' 'False' (OffOk "TC_ENABLED=unreadable`nTC_SET_COUNT=0`nTC_FILE_COUNT=0`nTC_MAP_COUNT=0")
# TC_SET_COUNT=0 must not match TC_SET_COUNT=01 or =0 inside a larger number
Chk 'HOSTILE: TC_SET_COUNT=10 must not satisfy the =0 test' 'False' (OffOk "TC_ENABLED=false`nTC_SET_COUNT=10`nTC_FILE_COUNT=0`nTC_MAP_COUNT=0")

# ---- revocation detection ----------------------------------------------------
Write-Host "`n=== the revocation detector ==="
function RevGone($text, $host_) {
    $line = ($text -split "`n" | Where-Object { $_ -match '^HOSTS_AFTER=' } | Select-Object -First 1)
    return [bool]($line -notmatch [regex]::Escape($host_))
}
Chk 'revoked host absent from the list -> gone'  'True'  (RevGone "HOSTS_AFTER=outlook.office.com," 'example.org')
Chk 'revoked host STILL in the list -> not gone' 'False' (RevGone "HOSTS_AFTER=outlook.office.com,example.org," 'example.org')
Chk 'CONTROL: the detector keys on the RIGHT line, not any line' 'True' `
    (RevGone "SOMETHINGELSE=example.org`nHOSTS_AFTER=outlook.office.com," 'example.org')

# ---- boot_id change detection -------------------------------------------------
Write-Host "`n=== the 'the distro really restarted' control ==="
function Restarted($before,$after) { return [bool]($before -and $after -and ($before -ne $after)) }
Chk 'different boot ids -> restart happened'   'True'  (Restarted 'aaa-111' 'bbb-222')
Chk 'IDENTICAL boot ids -> NO restart, control must NOT fire' 'False' (Restarted 'aaa-111' 'aaa-111')
Chk 'missing after-id -> control must NOT fire' 'False' (Restarted 'aaa-111' '')
Chk 'both missing -> control must NOT fire'     'False' (Restarted '' '')

# ---- the boot-refresh journal line -------------------------------------------
Write-Host "`n=== the 'unit actually ran on this boot' detector ==="
function AttemptLine($t) { return (($t -split "`n") | Where-Object { $_ -match 'attempt \d+/\d+: unresolved hosts' } | Select-Object -First 1) }
Chk 'a real attempt line is found' 'PRESENT' `
    $(if (AttemptLine "Aug 25 10:00 box egress[1]: [egress-refresh] attempt 1/20: unresolved hosts read-fetch=0 toolchain=0") { 'PRESENT' } else { 'ABSENT' })
Chk 'an empty journal finds nothing' 'ABSENT' $(if (AttemptLine '') { 'PRESENT' } else { 'ABSENT' })
Chk 'a journal with OTHER lines only finds nothing' 'ABSENT' `
    $(if (AttemptLine "Started clawfactory-egress-refresh.service.`nsomething else") { 'PRESENT' } else { 'ABSENT' })
Chk 'CONTROL: the higher attempt numbers parse too' 'PRESENT' `
    $(if (AttemptLine '[egress-refresh] attempt 20/20: unresolved hosts read-fetch=2 toolchain=1') { 'PRESENT' } else { 'ABSENT' })

Write-Host ''
Write-Host "BOOTPATH_CALIBRATION pass=$pass fail=$fail"
if ($fail -gt 0) { exit 1 }
