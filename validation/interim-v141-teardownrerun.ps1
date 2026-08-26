<#
  v1.4.1 release-closure probe: RE-RUN THE SHIPPED TEARDOWN AND WATCH IT.

  The keep-Linux teardown removed everything named in the first half of its
  script and nothing named in the second half. The stdin-consumption hypothesis
  was tested by interim-v141-teardownstop.ps1 and REFUTED: node -e does not eat
  a piped script, and the rig proved it on this box with a control.

  So stop theorising and watch it run. This takes the shipped bash VERBATIM out
  of resources/uninstall.ps1 lines 365-439, runs it through the IDENTICAL
  invocation shape uninstall.ps1 uses, and captures the stdout and stderr that
  production discards.

  The script emits four progress markers of its own, and where they stop is the
  measurement:

      line 40  [uninstall] removing the delete quarantine and N file(s) ...
      line 62  [uninstall] WARNING: /usr/bin/rm was not restored cleanly ...
      line 64  [uninstall] /usr/bin/rm divert removed; stock rm restored
      line 75  OK

  DESTRUCTIVE AND DELIBERATELY SO. It finishes the teardown the user actually
  asked for. Nothing later in this run needs the files it removes.

  THE CONTROL. Re-running a teardown on a box where it already ran cannot
  distinguish "this command works" from "there was nothing left to do". So the
  survivors are enumerated BEFORE and AFTER, and only a transition from present
  to absent counts as evidence that the command works and simply never
  executed the first time. Anything still present after a full second run is a
  removal the script does not attempt at all, which is the other defect and has
  to be reported separately.
#>
param(
    [string]$ScriptPath  = 'C:\cfv\uninstall-teardown-extract.sh',
    [string]$Transcript  = 'C:\cfv\teardownrerun-out-probe.txt',
    [string]$ResultsJson = 'C:\cfv\teardownrerun-results.json'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'ClawFactory v1.4.1: re-run the shipped keep-Linux teardown with its output captured' `
    -Transcript $Transcript -Sentinel 'TEARDOWNRERUN_PROBE_COMPLETE'

function Finish($code) { W ''; W "TEARDOWNRERUN_PROBE_COMPLETE rc=$code"; exit $code }
function Val([string]$text, [string]$key) {
    if ($text -match "(?m)^$([regex]::Escape($key))=(.*)$") { return $Matches[1].Trim() }
    return '(not reported)'
}

$SURVEY = @'
echo "QUAR_ENABLED=$(systemctl is-enabled clawfactory-quarantine.service 2>&1 | head -1)"
echo "QUAR_UNIT=$( [ -f /etc/systemd/system/clawfactory-quarantine.service ] && echo present || echo absent )"
echo "QUAR_HELPERS=$(ls -1 /usr/local/sbin/clawfactory-quarantine* 2>/dev/null | wc -l | tr -d ' ')"
echo "ETC_CLAWFACTORY=$( [ -d /etc/clawfactory ] && echo present || echo absent )"
echo "OPENCLAW_BIN=$( [ -e /usr/bin/openclaw ] && echo present || echo absent )"
echo "OPENCLAW_MODULES=$( [ -d /usr/lib/node_modules/openclaw ] && echo present || echo absent )"
echo "CLAWUSER=$( id -u clawuser >/dev/null 2>&1 && echo present || echo absent )"
echo "CLAWUSER_HOME=$( [ -d /home/clawuser ] && echo present || echo absent )"
echo "VARLIB=$( [ -d /var/lib/clawfactory ] && echo present || echo absent )"
echo "USRLOCALLIB=$( [ -d /usr/local/lib/clawfactory ] && echo present || echo absent )"
echo "SEND_ENABLED=$(systemctl is-enabled clawfactory-send.service 2>&1 | head -1)"
echo "FW_ENABLED=$(systemctl is-enabled clawfactory-fw.service 2>&1 | head -1)"
echo "PROV_TIMER=$(systemctl is-enabled clawfactory-allow-providers.timer 2>&1 | head -1)"
echo "ENABLED_COUNT=$(systemctl list-unit-files 'clawfactory-*' --state=enabled --no-legend 2>/dev/null | wc -l | tr -d ' ')"
echo "IMMUTABLE_ETC=$(lsattr -d /etc/clawfactory 2>/dev/null | awk '{print $1}')"
echo "IMMUTABLE_FILES=$(lsattr /etc/clawfactory/* 2>/dev/null | grep -c '^....i')"
echo "READER_CTL=$( [ -d /etc ] && echo present || echo absent )"
'@

Section '1. BEFORE: what is still here from the first teardown'
$before = Invoke-WslFile -Tag 'tdrr-before' -User 'root' -Body $SURVEY
foreach ($ln in @($before.Out -split "`r?`n" | Where-Object { $_ -match '=' })) { W "   BEFORE> $ln" }
$b = $before.Out

Register-Control -Id 'TR.CTL.READER' -Name 'the survey reader answers present for /etc' `
    -Fired ((Val $b 'READER_CTL') -eq 'present') `
    -Evidence "/etc = $(Val $b 'READER_CTL')" | Out-Null

$haveScript = Require-Precondition -Id 'TR.PRE' -Name 'the verbatim shipped teardown is staged on the box' `
    -Met (Test-Path -LiteralPath $ScriptPath) `
    -Reason 'this probe measures the SHIPPED bytes; a re-typed approximation would be measuring something else'
if (-not $haveScript) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'TEARDOWNRERUN'; Finish 4 }

$body = [string](Get-Content -LiteralPath $ScriptPath -Raw)
W "staged teardown: $($body.Length) chars, sha256 $((Get-FileHash $ScriptPath -Algorithm SHA256).Hash.ToLower())"

Section '2. Run it through the SAME shape uninstall.ps1 uses, and keep the output'
$lf  = ($body -replace "`r`n", "`n") -replace "`r", "`n"
$enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($lf))
$out = 'C:\cfv\wsl\teardown-rerun.out'
New-Item -ItemType Directory -Path 'C:\cfv\wsl' -Force | Out-Null
cmd.exe /c "wsl.exe -d Ubuntu -u root -- bash -lc ""echo $enc | base64 -d | bash"" > ""$out"" 2>&1"
$rc = $LASTEXITCODE
$captured = if (Test-Path $out) { [string](Get-Content $out -Raw) } else { '' }
W "invocation exit code: $rc"
W '--- captured output, which production assigns to $null ---'
foreach ($ln in @($captured -split "`r?`n" | Where-Object { $_ })) { W "   OUT> $ln" }
W '--- end captured output ---'

$sawQuarantineEcho = $captured -match '\[uninstall\] removing the delete quarantine'
$sawDivertEcho     = $captured -match '\[uninstall\] /usr/bin/rm divert removed'
$sawWarnEcho       = $captured -match '\[uninstall\] WARNING: /usr/bin/rm was not restored'
$sawOK             = $captured -match '(?m)^OK\s*$'

Record 'TR.1' 'HOW FAR THE SHIPPED TEARDOWN GETS, read from its own markers' `
    $(if ($sawOK) { 'PASS' } else { 'FAIL' }) `
    "quarantine marker (line 40)=$sawQuarantineEcho ; rm-divert restored marker (line 64)=$sawDivertEcho ; rm-divert WARNING marker (line 62)=$sawWarnEcho ; terminal OK (line 75)=$sawOK ; invocation exit=$rc. The markers are the script's own, in source order, so the last one seen bounds where it stopped."

Section '3. AFTER: what the second run changed'
$after = Invoke-WslFile -Tag 'tdrr-after' -User 'root' -Body $SURVEY
foreach ($ln in @($after.Out -split "`r?`n" | Where-Object { $_ -match '=' })) { W "   AFTER> $ln" }
$a = $after.Out

Register-Control -Id 'TR.CTL.READER2' -Name 'the survey reader still answers present for /etc afterwards' `
    -Fired ((Val $a 'READER_CTL') -eq 'present') `
    -Evidence "/etc = $(Val $a 'READER_CTL'). A reader that broke mid-probe would report everything absent and read as a clean teardown." | Out-Null

$rows = @(
    @{ k='ETC_CLAWFACTORY'; n='/etc/clawfactory' },
    @{ k='OPENCLAW_BIN';    n='/usr/bin/openclaw' },
    @{ k='OPENCLAW_MODULES';n='/usr/lib/node_modules/openclaw' },
    @{ k='CLAWUSER';        n='the clawuser account' },
    @{ k='CLAWUSER_HOME';   n='/home/clawuser' },
    @{ k='VARLIB';          n='/var/lib/clawfactory' },
    @{ k='USRLOCALLIB';     n='/usr/local/lib/clawfactory' },
    @{ k='QUAR_UNIT';       n='the quarantine unit file' }
)
foreach ($r in $rows) {
    $bv = Val $b $r.k; $av = Val $a $r.k
    $verdict = if ($bv -eq 'present' -and $av -eq 'absent') { 'PASS' } elseif ($av -eq 'absent') { 'INFO' } else { 'FAIL' }
    Record "TR.2.$($r.k)" "$($r.n): removed by a SECOND run of the same script?" $verdict `
        "before=$bv after=$av. PASS means the shipped command works and simply never executed during the real uninstall. FAIL means a second full run still does not remove it, which is a different defect: the script does not attempt it, or something blocks it."
}

Record 'TR.3' 'units still enabled after a full second teardown' `
    $(if ((Val $a 'ENABLED_COUNT') -eq '0') { 'PASS' } else { 'FAIL' }) `
    "enabled clawfactory units before=$(Val $b 'ENABLED_COUNT') after=$(Val $a 'ENABLED_COUNT'); fw=$(Val $a 'FW_ENABLED') send=$(Val $a 'SEND_ENABLED') providers-timer=$(Val $a 'PROV_TIMER') quarantine=$(Val $a 'QUAR_ENABLED'). These four are never named anywhere in the teardown script, so no number of re-runs will disable them."

Record 'TR.4' 'immutable attributes, ruled in or out as a blocker' 'INFO' `
    "lsattr on /etc/clawfactory before='$(Val $b 'IMMUTABLE_ETC')', files carrying +i before=$(Val $b 'IMMUTABLE_FILES'). Root cannot rm an immutable file, so this is checked rather than assumed."

Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'TEARDOWNRERUN'
Finish 0
