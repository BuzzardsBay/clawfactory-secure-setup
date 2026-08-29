<#
  BOX D diagnostic: WHAT IS ACTUALLY IN THE READ-FETCH ALLOWLIST.

  WHY THIS EXISTS
  ---------------
  interim-v140-sinktls.ps1's ST.0 reported readFetchIsSeededOnly=False on cfv-182
  and explained it with a hard-coded parenthetical from a DIFFERENT run:
  "(the operator added and removed docs.python.org during check 3 and check 5)".
  No operator has touched Studio on this box. So that explanation cannot be the
  explanation here, and an unexplained FAIL left standing is how a real finding
  gets talked away later -- or how a harmless one becomes a ship-blocker.

  This reads the list rather than inferring it. Clause 1: discover the VALUE.

  It asserts nothing about what SHOULD be there. It prints what IS there, from
  two independent directions -- the shipped control tool and the file the resolver
  actually reads -- and compares them. A single reading could not tell a stale
  file apart from a tool that lies about it.

  READ-ONLY. It adds nothing, removes nothing, and restores nothing, because it
  changes nothing.
#>
param(
    [string]$Transcript  = 'C:\cfv\fetchlist-out-probe.txt',
    [string]$ResultsJson = 'C:\cfv\fetchlist-results.json',
    [string]$LibDir      = 'C:\cfv',
    [string]$SeedHost    = 'outlook.office.com'
)

$ErrorActionPreference = 'Continue'
. (Join-Path $LibDir 'interim-v120-wslchan.ps1')
. (Join-Path $LibDir 'interim-v120-phaselib.ps1')

Start-Phase -Name 'ClawFactory v1.4.4 box D: what is in the read-fetch allowlist' `
    -Transcript $Transcript -Sentinel 'FETCHLIST_PROBE_COMPLETE'

function Finish($code) { W ''; W "FETCHLIST_PROBE_COMPLETE rc=$code"; exit $code }
function Val([string]$text, [string]$key) {
    if ($text -match "(?m)^$([regex]::Escape($key))=(.*)$") { return $Matches[1].Trim() }
    return '(not reported)'
}
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

$chan = Test-WslChannel
Register-Control -Id 'FL.CHAN' -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'FETCHLIST'; Finish 2 }

Section '1. Two independent readings of the same list, printed in full'
$r = Invoke-WslFile -Tag 'fl-read' -User 'root' -Body @'
echo "--TOOL--"
node /usr/local/sbin/clawfactory-fetchctl.js list 2>&1
echo "--END-TOOL--"
echo "FILE_PATH=/etc/clawfactory/read-fetch-hosts.txt"
echo "FILE_EXISTS=$( [ -f /etc/clawfactory/read-fetch-hosts.txt ] && echo yes || echo no )"
echo "--FILE--"
cat /etc/clawfactory/read-fetch-hosts.txt 2>/dev/null
echo "--END-FILE--"
echo "--POLICY--"
node -e 'try{const j=require("/etc/clawfactory/egress-policy.json");process.stdout.write(JSON.stringify(j.read_fetch||j.readFetch||null))}catch(e){process.stdout.write("(unreadable: "+e.message+")")}' 2>&1
echo ""
echo "--END-POLICY--"
echo "CTL_TOOL_PRESENT=$( [ -f /usr/local/sbin/clawfactory-fetchctl.js ] && echo yes || echo no )"
'@
foreach ($ln in @($r.Out -split "`r?`n" | Where-Object { $_.Trim() })) { W "   FL> $ln" }
$t = $r.Out

$toolRaw = @(Fenced $t '--TOOL--' '--END-TOOL--')
$fileRaw = @(Fenced $t '--FILE--' '--END-FILE--')
$policy  = @(Fenced $t '--POLICY--' '--END-POLICY--')

# The tool prints prose around its entries; take the hostnames out of both
# readings the same way so the comparison is like for like.
$hostPat = '(?i)\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\b'
$toolHosts = @($toolRaw | ForEach-Object { ([regex]$hostPat).Matches($_) | ForEach-Object { $_.Value } } | Sort-Object -Unique)
$fileHosts = @($fileRaw | ForEach-Object { ([regex]$hostPat).Matches($_) | ForEach-Object { $_.Value } } | Sort-Object -Unique)

W ''
W "TOOL_HOSTS count=$($toolHosts.Count) [$($toolHosts -join ' ')]"
W "FILE_HOSTS count=$($fileHosts.Count) [$($fileHosts -join ' ')]"
W "POLICY_READ_FETCH=$($policy -join ' ')"

$readable = ((Val $t 'CTL_TOOL_PRESENT') -eq 'yes') -and ((Val $t 'FILE_EXISTS') -eq 'yes')
Register-Control -Id 'FL.CTL.READ' -Name 'both readings had something to read' `
    -Fired $readable `
    -Evidence "fetchctl.js present=$(Val $t 'CTL_TOOL_PRESENT'); read-fetch-hosts.txt present=$(Val $t 'FILE_EXISTS'). Two empty readings from two absent sources would agree perfectly and mean nothing." | Out-Null

Compare-Independent -Id 'FL.1' -Name 'the control tool and the file the resolver reads agree' `
    -Mine ($fileHosts -join ',') -Reported ($toolHosts -join ',') `
    -MineLabel 'the file /etc/clawfactory/read-fetch-hosts.txt' `
    -ReportedLabel 'clawfactory-fetchctl list' | Out-Null

Record 'FL.2' 'the seeded host is present' `
    $(if ($fileHosts -contains $SeedHost) { 'PASS' } else { 'FAIL' }) `
    "seeded=$SeedHost; file carries [$($fileHosts -join ' ')]"

$extra = @($fileHosts | Where-Object { $_ -ne $SeedHost })
Record 'FL.3' 'anything in the list BESIDES the seeded host, reported as a fact' 'INFO' `
    "entries other than the seed: $($extra.Count) [$($extra -join ' ')]. This row takes no verdict. Its purpose is to say what ST.0 was actually looking at, because ST.0's own evidence string explains a non-seeded-only list with an operator action that has not happened on this box."

Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'FETCHLIST'
Finish 0
