<#
  v1.4.1 release-closure probe: WHY THE KEEP-LINUX TEARDOWN STOPPED.

  Measured on cfv-176 after a real by-hand keep-Linux uninstall: the teardown
  removed everything named in the FIRST half of its script (the nft table, the
  proxy unit, the turn-gate helpers, the read-fetch resolver, the toolchain
  resolver, and the v1.4.1 boot refresh unit) and NOTHING named in the second
  half (the quarantine units and helpers, /etc/clawfactory, /usr/bin/openclaw,
  clawuser). Both halves are in the same shipped here-string in
  resources/uninstall.ps1 lines 365-439, and the script opens with `set +e`, so
  an error cannot explain the split.

  THE HYPOTHESIS, and it is a hypothesis until this probe fires.
  uninstall.ps1 runs that script by PIPING IT INTO BASH'S STDIN:

      wsl.exe -d Ubuntu -u root -- bash -lc "echo <b64> | base64 -d | bash"

  When a script arrives on bash's stdin, any command inside it that READS stdin
  consumes the rest of the script. setup.ps1's own Invoke-WslBash comment names
  this exposure in as many words. The first command in the second half is:

      HELD=$(node -e 'try{...readFileSync(".../index.json")...}catch{...}')

  If node touches stdin, every line after it is eaten and the teardown ends
  silently at exactly the boundary observed -- with no error, because the shell
  simply reaches end of input.

  WHY THIS IS INVISIBLE IN PRODUCTION. uninstall.ps1 discards the result:

      $null = & wsl.exe -d Ubuntu -u root -- bash -lc "echo $enc | base64 -d | bash" 2>&1

  so neither stdout nor stderr reaches the uninstall log, and the very next line
  logs 'In-distro ClawFactory artifacts removed' unconditionally.

  THIS PROBE IS NON-DESTRUCTIVE. It does not re-run the teardown. It reproduces
  the SHAPE with a minimal rig whose correct answer is known in advance, through
  the identical pipe-into-stdin invocation, and pairs it with a control that
  differs only in the suspect line. If the subject truncates and the control
  does not, the mechanism is identified rather than argued.
#>
param(
    [string]$Transcript  = 'C:\cfv\teardownstop-out-probe.txt',
    [string]$ResultsJson = 'C:\cfv\teardownstop-results.json'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'ClawFactory v1.4.1: why the keep-Linux teardown stopped half way' `
    -Transcript $Transcript -Sentinel 'TEARDOWNSTOP_PROBE_COMPLETE'

function Finish($code) { W ''; W "TEARDOWNSTOP_PROBE_COMPLETE rc=$code"; exit $code }

# Run a script through the EXACT shape uninstall.ps1 uses: base64 on the command
# line, decoded, and piped into a bash whose stdin is therefore the script.
function Invoke-PipedIntoBash([string]$Body, [string]$Tag) {
    $lf  = ($Body -replace "`r`n", "`n") -replace "`r", "`n"
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($lf))
    $out = "C:\cfv\wsl\pipe-$Tag.out"
    New-Item -ItemType Directory -Path 'C:\cfv\wsl' -Force | Out-Null
    cmd.exe /c "wsl.exe -d Ubuntu -u root -- bash -lc ""echo $enc | base64 -d | bash"" > ""$out"" 2>&1"
    $rc = $LASTEXITCODE
    $text = if (Test-Path $out) { [string](Get-Content $out -Raw) } else { '' }
    return @{ Out = $text; Rc = $rc }
}

Section '1. Does the branch that guards the suspect line even execute?'
$pre = Invoke-WslFile -Tag 'tdpre' -User 'root' -Body @'
echo "INDEX_JSON=$( [ -f /var/lib/clawfactory/quarantine/index.json ] && echo present || echo absent )"
echo "NODE=$(command -v node 2>/dev/null || echo none)"
echo "READER_CTL=$( [ -d /etc ] && echo present || echo absent )"
'@
foreach ($ln in @($pre.Out -split "`r?`n" | Where-Object { $_ -match '=' })) { W "   PRE> $ln" }
$indexPresent = ($pre.Out -match '(?m)^INDEX_JSON=present')
$nodePath     = if ($pre.Out -match '(?m)^NODE=(.*)$') { $Matches[1].Trim() } else { 'none' }

Register-Control -Id 'TD.CTL.READER' -Name 'the file-channel reader answers present for /etc' `
    -Fired ($pre.Out -match '(?m)^READER_CTL=present') `
    -Evidence "/etc reads $(if ($pre.Out -match '(?m)^READER_CTL=(.*)$') { $Matches[1].Trim() })" | Out-Null

Record 'TD.0' 'the quarantine index the suspect branch tests for' `
    $(if ($indexPresent) { 'INFO' } else { 'INFO' }) `
    "/var/lib/clawfactory/quarantine/index.json = $(if ($indexPresent) { 'present, so the if-branch runs and node is invoked' } else { 'absent, so the if-branch is SKIPPED and node is never invoked -- which would refute the node hypothesis and point at the next stdin reader instead' }). node = $nodePath."

Section '2. CALIBRATION: a rig whose correct answer is known before it runs'
# Both rigs print A, then the middle, then B and C. A shell that reaches the end
# of its input prints A and nothing after the consumer. The ONLY difference
# between subject and control is the command in the middle.
$SUBJECT_RIG = @'
set +e
echo "RIG_A"
HELD=$(node -e 'try{console.log(JSON.parse(require("fs").readFileSync("/etc/hostname")).length)}catch{console.log(0)}' 2>/dev/null || echo 0)
echo "RIG_HELD=$HELD"
echo "RIG_B"
echo "RIG_C"
'@
$CONTROL_RIG = @'
set +e
echo "RIG_A"
HELD=0
echo "RIG_HELD=$HELD"
echo "RIG_B"
echo "RIG_C"
'@

$ctl = Invoke-PipedIntoBash $CONTROL_RIG 'ctl'
foreach ($ln in @($ctl.Out -split "`r?`n" | Where-Object { $_ })) { W "   CTL> $ln" }
$ctlComplete = ($ctl.Out -match 'RIG_A') -and ($ctl.Out -match 'RIG_B') -and ($ctl.Out -match 'RIG_C')
Register-Control -Id 'TD.CTL.RIG' -Name 'the rig runs to completion through the pipe-into-stdin shape' `
    -Fired $ctlComplete `
    -Evidence "control rig printed RIG_A=$($ctl.Out -match 'RIG_A') RIG_B=$($ctl.Out -match 'RIG_B') RIG_C=$($ctl.Out -match 'RIG_C'). If the control cannot finish, the shape itself is broken and the subject proves nothing." | Out-Null

$subj = Invoke-PipedIntoBash $SUBJECT_RIG 'subj'
foreach ($ln in @($subj.Out -split "`r?`n" | Where-Object { $_ })) { W "   SUBJ> $ln" }
$subjTruncated = ($subj.Out -match 'RIG_A') -and (-not ($subj.Out -match 'RIG_C'))

Record 'TD.1' 'THE MECHANISM: a command reading stdin eats the rest of a piped script' `
    $(if ($subjTruncated -and $ctlComplete) { 'PASS' } else { 'FAIL' }) `
    "subject rig (with the node command substitution) printed RIG_A=$($subj.Out -match 'RIG_A') RIG_B=$($subj.Out -match 'RIG_B') RIG_C=$($subj.Out -match 'RIG_C'); control rig, identical but for that one line, printed RIG_C=$($ctl.Out -match 'RIG_C'). PASS here means the subject truncated where the control did not, which reproduces the observed teardown split on the same box through the same invocation shape."

Section '3. The same question asked of the FILE channel, which is the fix'
$file = Invoke-WslFile -Tag 'tdfile' -User 'root' -Body $SUBJECT_RIG
foreach ($ln in @($file.Out -split "`r?`n" | Where-Object { $_ })) { W "   FILE> $ln" }
Record 'TD.2' 'the identical script run from a FILE instead of stdin completes' `
    $(if (($file.Out -match 'RIG_A') -and ($file.Out -match 'RIG_C')) { 'PASS' } else { 'FAIL' }) `
    "same bytes, run as bash against a /var/tmp script file with stdin bound elsewhere: RIG_A=$($file.Out -match 'RIG_A') RIG_C=$($file.Out -match 'RIG_C'). This is the discriminator: if the file channel completes and the pipe channel truncates, the defect is the delivery shape, not the script."

Section '4. What uninstall.ps1 does with the result, which is why nobody saw it'
Record 'TD.3' 'the teardown result is discarded, so a partial run is invisible' 'INFO' `
    "resources/uninstall.ps1 line 437 assigns the invocation to `$null and merges 2>&1 into it, then line 439 logs 'In-distro ClawFactory artifacts removed; Ubuntu distro left registered.' unconditionally. Neither stdout nor stderr reaches ClawFactory-Uninstall.log, and the log line asserts completion that was never checked. Whatever the cause of the split, this is why it survived to a release."

Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'TEARDOWNSTOP'
Finish 0
