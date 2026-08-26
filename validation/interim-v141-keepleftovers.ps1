<#
  v1.4.1 release-closure probe: WHAT THE KEEP-LINUX UNINSTALL LEAVES BEHIND.

  interim-v141-uninstall.ps1 -Mode AfterKeepLinux recorded five FAIL rows on
  cfv-176. A count is not a diagnosis. "12 unit files survive" could mean the
  uninstaller's removal list is incomplete, or that its teardown script died
  part way, or that the survivors are inert files that nothing will ever load.
  Those are three different findings with three different severities, and the
  difference between them is measurable rather than arguable.

  THE QUESTION THAT DECIDES SEVERITY IS NOT "IS IT PRESENT" BUT "IS IT LIVE".
  A unit FILE on disk does nothing. A unit that is ENABLED runs at the next
  boot of a machine whose owner believes they have uninstalled the product.
  A helper script on disk does nothing. A helper that a live timer or an
  enabled service invokes is a different object entirely. So every survivor is
  read twice: does it exist, and is anything going to run it.

  The reader carries its own control: /etc and /bin/bash must read present, and
  a name that never existed must read absent. Without both, "present" and
  "absent" are the same word.
#>
param(
    [string]$Transcript  = 'C:\cfv\keepleftovers-out-probe.txt',
    [string]$ResultsJson = 'C:\cfv\keepleftovers-results.json'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'ClawFactory v1.4.1: what the keep-Linux uninstall leaves behind' `
    -Transcript $Transcript -Sentinel 'KEEPLEFT_PROBE_COMPLETE'

function Finish($code) { W ''; W "KEEPLEFT_PROBE_COMPLETE rc=$code"; exit $code }
function Val([string]$text, [string]$key) {
    if ($text -match "(?m)^$([regex]::Escape($key))=(.*)$") { return $Matches[1].Trim() }
    return '(not reported)'
}

Section '1. The uninstaller''s own account of what it did on this branch'
$ulog = Join-Path $env:TEMP 'ClawFactory-Uninstall.log'
$ulogText = if (Test-Path -LiteralPath $ulog) { [string](Get-Content -LiteralPath $ulog -Raw) } else { '' }
foreach ($ln in @($ulogText -split "`r?`n" | Where-Object { $_ -match 'DoRemoveAll|Step [1-9]|WARN|ERROR|wsl|quarantine|Keeping' })) { W "   ULOG> $ln" }

Assert-Searchable -Id 'KL.CTL.ULOG' -Name 'the uninstall log' `
    -PositiveMarkerFound ($ulogText -match 'ClawFactory uninstall starting') `
    -MarkerDescription "the uninstaller's own opening line" | Out-Null

Require-Precondition -Id 'KL.PRE' -Name 'this really was the keep-Linux branch' `
    -Met ([bool]($ulogText -match 'Resolved DoRemoveAll = False')) `
    -Reason 'the whole point of this probe is the branch in which the v1.4.1 changes execute' | Out-Null

Section '2. Windows side: what is left in the application directory'
$APPDIR = 'C:\Program Files\ClawFactory'
$winLeft = @()
if (Test-Path -LiteralPath $APPDIR) {
    $winLeft = @(Get-ChildItem -LiteralPath $APPDIR -Recurse -Force -ErrorAction SilentlyContinue |
                 ForEach-Object { $_.FullName.Substring($APPDIR.Length + 1) + $(if ($_.PSIsContainer) { '\' } else { " ($($_.Length) B)" }) })
}
foreach ($f in $winLeft) { W "   LEFT> $f" }
Record 'KL.1' 'the application directory after a keep-Linux uninstall' `
    $(if ($winLeft.Count -eq 0) { 'PASS' } else { 'INFO' }) `
    "Test-Path '$APPDIR' = $([bool](Test-Path -LiteralPath $APPDIR)); entries remaining = $($winLeft.Count) [$(@($winLeft) -join '; ')]. Inno removes only what it installed, so anything written after install stays and the directory stays with it."

Section '3. Distro side: every survivor read twice, present AND live'
$body = @'
set +e
echo "READER_CTL_ETC=$( [ -d /etc ] && echo present || echo absent )"
echo "READER_CTL_BASH=$( [ -x /bin/bash ] && echo present || echo absent )"
echo "READER_CTL_ABSENT=$( [ -e /usr/local/sbin/clawfactory-b7f31c-never-existed ] && echo present || echo absent )"

echo "--- unit files on disk ---"
for f in /etc/systemd/system/clawfactory-*; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  echo "UNITFILE $b state=$(systemctl is-enabled "$b" 2>&1 | head -1) active=$(systemctl is-active "$b" 2>&1 | head -1)"
done
echo "UNITFILE_COUNT=$(ls -1 /etc/systemd/system/clawfactory-* 2>/dev/null | wc -l | tr -d ' ')"

echo "--- anything ENABLED is the row that matters ---"
echo "ENABLED_LIST=$(systemctl list-unit-files 'clawfactory-*' --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
echo "ENABLED_COUNT=$(systemctl list-unit-files 'clawfactory-*' --state=enabled --no-legend 2>/dev/null | wc -l | tr -d ' ')"
echo "WANTS_LINKS=$(ls -1 /etc/systemd/system/*.wants/clawfactory-* 2>/dev/null | wc -l | tr -d ' ')"
echo "WANTS_LIST=$(ls -1 /etc/systemd/system/*.wants/clawfactory-* 2>/dev/null | tr '\n' ' ')"
echo "ACTIVE_COUNT=$(systemctl list-units 'clawfactory-*' --state=active --no-legend 2>/dev/null | wc -l | tr -d ' ')"
echo "ACTIVE_LIST=$(systemctl list-units 'clawfactory-*' --state=active --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
echo "TIMERS=$(systemctl list-timers 'clawfactory-*' --all --no-legend 2>/dev/null | wc -l | tr -d ' ')"

echo "--- helper binaries ---"
for f in /usr/local/sbin/clawfactory-*; do
  [ -e "$f" ] || continue
  echo "HELPER $(basename "$f")"
done
echo "HELPER_COUNT=$(ls -1 /usr/local/sbin/clawfactory-* 2>/dev/null | wc -l | tr -d ' ')"

echo "--- /etc/clawfactory ---"
echo "ETC_PRESENT=$( [ -d /etc/clawfactory ] && echo present || echo absent )"
for f in /etc/clawfactory/*; do
  [ -e "$f" ] || continue
  echo "ETCFILE $(basename "$f") $(stat -c '%s B mode=%a owner=%U' "$f" 2>/dev/null)"
done

echo "--- openclaw and the gateway ---"
echo "OPENCLAW_BIN=$( [ -e /usr/bin/openclaw ] && echo present || echo absent )"
echo "OPENCLAW_TYPE=$( [ -L /usr/bin/openclaw ] && echo symlink || ([ -f /usr/bin/openclaw ] && echo file || echo none) )"
echo "OPENCLAW_HEAD=$(head -c 120 /usr/bin/openclaw 2>/dev/null | tr '\n' ' ')"
echo "GATEWAY_USERUNIT=$( [ -f /home/clawuser/.config/systemd/user/openclaw-gateway.service ] && echo present || echo absent )"
echo "PROXY_UNIT=$( [ -f /etc/systemd/system/clawfactory-proxy.service ] && echo present || echo absent )"
echo "NFT_TABLE=$(nft list table inet clawfactory >/dev/null 2>&1 && echo present || echo absent)"

echo "--- is anything actually RUNNING as the agent ---"
echo "CLAWUSER_PROCS=$(ps -u clawuser --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "LISTENERS=$(ss -ltnp 2>/dev/null | grep -cE ':8787|:8788')"
'@
$r = Invoke-WslFile -Tag 'keepleft' -User 'root' -Body $body
foreach ($ln in @($r.Out -split "`r?`n" | Where-Object { $_ })) { W "   D> $ln" }
$t = $r.Out

$readerOk = ((Val $t 'READER_CTL_ETC') -eq 'present') -and ((Val $t 'READER_CTL_BASH') -eq 'present') -and ((Val $t 'READER_CTL_ABSENT') -eq 'absent')
Register-Control -Id 'KL.CTL.READER' -Name 'the reader discriminates present from absent' `
    -Fired $readerOk `
    -Evidence "/etc=$(Val $t 'READER_CTL_ETC') /bin/bash=$(Val $t 'READER_CTL_BASH') never-existed-path=$(Val $t 'READER_CTL_ABSENT'). All three required: two that must read present and one that must read absent." | Out-Null

Section '4. The rows that decide severity'

Record 'KL.2' 'SEVERITY ROW: is any surviving ClawFactory unit ENABLED to run at boot?' `
    $(if ((Val $t 'ENABLED_COUNT') -eq '0' -and (Val $t 'WANTS_LINKS') -eq '0') { 'PASS' } else { 'FAIL' }) `
    "units in state=enabled: $(Val $t 'ENABLED_COUNT') [$(Val $t 'ENABLED_LIST')]; .wants symlinks pointing at clawfactory units: $(Val $t 'WANTS_LINKS') [$(Val $t 'WANTS_LIST')]. A unit FILE on disk is inert. An ENABLED unit runs at the next boot of a machine whose owner believes they uninstalled the product, and that is a different finding."

Record 'KL.3' 'SEVERITY ROW: is any surviving ClawFactory unit ACTIVE right now?' `
    $(if ((Val $t 'ACTIVE_COUNT') -eq '0') { 'PASS' } else { 'FAIL' }) `
    "active units: $(Val $t 'ACTIVE_COUNT') [$(Val $t 'ACTIVE_LIST')]; processes running as clawuser: $(Val $t 'CLAWUSER_PROCS'); listeners on the gateway/proxy ports: $(Val $t 'LISTENERS')."

Record 'KL.4' 'SEVERITY ROW: the firewall table is gone, so no rule outlives the product' `
    $(if ((Val $t 'NFT_TABLE') -eq 'absent') { 'PASS' } else { 'FAIL' }) `
    "nft list table inet clawfactory = $(Val $t 'NFT_TABLE')."

Section '5. The inventory of what survived, stated exactly'
Record 'KL.5a' 'systemd unit FILES left on disk' 'INFO' `
    "count=$(Val $t 'UNITFILE_COUNT'). Each is listed above with its own is-enabled and is-active state."
Record 'KL.5b' 'helper binaries left in /usr/local/sbin' 'INFO' `
    "count=$(Val $t 'HELPER_COUNT'). Named individually above."
Record 'KL.5c' '/etc/clawfactory and its contents' 'INFO' `
    "directory=$(Val $t 'ETC_PRESENT'). Contents listed above with size, mode and owner, including the v1.4.1 *-ips.map retention files."
Record 'KL.5d' '/usr/bin/openclaw' 'INFO' `
    "present=$(Val $t 'OPENCLAW_BIN') type=$(Val $t 'OPENCLAW_TYPE'). First bytes: $(Val $t 'OPENCLAW_HEAD')"

Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'KEEPLEFT'
Finish 0
