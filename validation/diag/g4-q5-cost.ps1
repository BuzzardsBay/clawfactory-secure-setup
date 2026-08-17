<#
  QUESTION 5. What it costs.

  Only meaningful for a candidate that survived questions 1 to 4, so this phase
  reads the earlier result files and declares a NAMED precondition rather than
  producing timings for a mechanism that cannot be used. A cost figure for an
  unavailable design is not a cheap extra data point, it is a number that will be
  quoted later without its caveat.

  THREE RUNS, AND THE TWO DIFFERENCES ARE DIFFERENT PROBLEMS
  ----------------------------------------------------------
    A  baseline, no daemon
    B  permission mode, allow everything, copy nothing
    C  permission mode with the snapshot copy actually performed

  B minus A is the cost of ENFORCEMENT: the round trip to userspace on every
  open, paid whether or not anything is stored. C minus B is the cost of COPYING.
  They have different fixes. Enforcement cost is attacked with mark scope and
  kernel-side exclusions; copy cost is attacked with reflinks, hard links or not
  copying. Reporting them as one number hides which lever to pull, so they are
  reported separately and never summed.

  Identical work each time, wall clock, no impressions.
#>
param(
    [string]$Transcript = 'C:\cfv\g4-q5-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\g4-common.ps1

Start-Phase -Name 'Guard 4 Q5: the cost of enforcement, and the cost of copying' `
    -Transcript $Transcript -Sentinel 'G4_Q5_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'Q5.CHAN' -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { Complete-Phase -ResultsJson 'C:\cfv\g4-q5-results.json' -MarkerPrefix 'G4Q5' }

# --- did anything survive -----------------------------------------------------
$survived = $false
$why = 'no earlier result file was readable'
try {
    if (Test-Path 'C:\cfv\g4-q1-results.json') {
        $q1 = Get-Content 'C:\cfv\g4-q1-results.json' -Raw | ConvertFrom-Json
        $ext4 = @($q1.Results | Where-Object { $_.Id -eq 'Q1.5' -and $_.Verdict -eq 'PASS' }).Count -gt 0
        $drvfs = @($q1.Results | Where-Object { $_.Id -eq 'Q1.9' -and $_.Verdict -eq 'PASS' }).Count -gt 0
        $survived = $ext4 -or $drvfs
        $why = "Q1 ext4 enforced=$ext4, Q1 drvfs enforced=$drvfs"
    }
} catch { $why = "could not read the Q1 results: $($_.Exception.Message)" }

$null = Require-Precondition -Id 'Q5.PRE' -Name 'at least one enforcement candidate survived questions 1 to 4' `
    -Met $survived -Reason "$why. Timing a mechanism that cannot be used produces a number that outlives its caveat."
if (-not $survived) {
    W 'No surviving candidate, so no cost is measured. This is the correct output, not a gap.'
    Complete-Phase -ResultsJson 'C:\cfv\g4-q5-results.json' -MarkerPrefix 'G4Q5'
}

$py = Install-G4Py
Register-Control -Id 'Q5.PY' -Name 'python3 reaches libc and runs THIS payload' `
    -Fired $py.Ok -Evidence $py.Detail | Out-Null
if (-not $py.Ok) { Complete-Phase -ResultsJson 'C:\cfv\g4-q5-results.json' -MarkerPrefix 'G4Q5' }

# --- the workspace under test -------------------------------------------------
$slug = ''
try {
    New-Item -ItemType Directory -Path 'C:\cfv\g4-cost' -Force | Out-Null
    . 'C:\Program Files\ClawFactory\resources\clawfactory-grants.ps1'
    $g = Grant-Workspace -Path 'C:\cfv\g4-cost' -Mode rw
    $slug = $g.id
    W "granted id=$slug"
} catch { W "Grant-Workspace threw: $($_.Exception.Message)" }
$null = Require-Precondition -Id 'Q5.PRE.WS' -Name 'a granted workspace exists to time work inside' `
    -Met ([bool]$slug) -Reason 'timing work outside a granted workspace measures a path the daemon would not be watching'
if (-not $slug) { Complete-Phase -ResultsJson 'C:\cfv\g4-q5-results.json' -MarkerPrefix 'G4Q5' }
$gp = "/workspaces/$slug"

# The identical unit of work, defined once. Anything that differs between runs
# is a confound, so the project is rebuilt from scratch each time and the agent
# is warmed before every run rather than only before the first.
$WORK = @"
su -s /bin/bash -c "
  rm -rf '$gp/proj'
  mkdir -p '$gp/proj'
  cd '$gp/proj'
  printf '{\"name\":\"g4cost\",\"version\":\"1.0.0\",\"dependencies\":{\"ms\":\"2.1.3\"}}\n' > package.json
" clawuser 2>&1 | tail -2
su -s /bin/bash -c "timeout 120 openclaw agent --agent main --message 'Reply with the single word WARM.' 2>&1 | tail -1" clawuser 2>&1 | tail -1
S=`$(date +%s)
su -s /bin/bash -c "cd '$gp/proj' && timeout 240 openclaw agent --agent main --message 'Create a file called cost.txt in $gp/proj containing one sentence, then stop.' 2>&1 | tail -2" clawuser 2>&1 | tail -2
su -s /bin/bash -c "cd '$gp/proj' && timeout 180 npm install --no-audit --no-fund 2>&1 | tail -2" clawuser 2>&1 | tail -2
E=`$(date +%s)
# Whole seconds, and no bc. The runs are minutes long, so sub-second precision
# would be false precision, and a missing package must not be able to turn a
# timing into an empty string that parses as zero.
echo "RUN_SECONDS=`$(( E - S ))"
"@

function Invoke-CostRun {
    param([string]$Label, [string]$Pre, [string]$Post)
    $r = Invoke-WslFile -Tag "g4-q5-$Label" -User 'root' -Body @"
$Pre
$WORK
$Post
"@
    W $r.Out
    $secs = if ($r.Out -match 'RUN_SECONDS=([\d.]+)') { [double]$Matches[1] } else { -1 }
    W "  ==> run $Label wall clock: $secs s"
    return @{ Secs = $secs; Raw = $r.Out }
}

# ============================================================================
Section 'Run A: baseline, no daemon'
$A = Invoke-CostRun -Label 'A' -Pre 'echo "no daemon"' -Post 'echo "A done"'

Section 'Run B: permission mode, allow everything, copy nothing'
$B = Invoke-CostRun -Label 'B' `
    -Pre @"
rm -f /var/tmp/g4/daemonB.log
nohup python3 /var/tmp/g4-probe.py daemon '$gp' 900 > /var/tmp/g4/daemonB.log 2>&1 &
echo "DAEMON_B_PID=`$!"
sleep 4
grep -q HOLDING /var/tmp/g4/daemonB.log 2>/dev/null; echo "B_STARTED=`$?"
head -3 /var/tmp/g4/daemonB.log
"@ `
    -Post @"
pkill -f 'g4-probe.py daemon' 2>/dev/null
sleep 2
echo '--- daemon B accounting ---'
tail -3 /var/tmp/g4/daemonB.log
"@

Section 'Run C: permission mode with the snapshot copy actually performed'
$C = Invoke-CostRun -Label 'C' `
    -Pre @"
rm -rf /var/tmp/g4/snap; mkdir -p /var/tmp/g4/snap
rm -f /var/tmp/g4/daemonC.log
nohup python3 /var/tmp/g4-probe.py daemon '$gp' 900 /var/tmp/g4/snap > /var/tmp/g4/daemonC.log 2>&1 &
echo "DAEMON_C_PID=`$!"
sleep 4
head -3 /var/tmp/g4/daemonC.log
"@ `
    -Post @"
pkill -f 'g4-probe.py daemon' 2>/dev/null
sleep 2
echo "SNAPSHOT_FILES=`$(ls /var/tmp/g4/snap 2>/dev/null | wc -l | tr -d ' ')"
echo "SNAPSHOT_BYTES=`$(du -sb /var/tmp/g4/snap 2>/dev/null | cut -f1)"
tail -3 /var/tmp/g4/daemonC.log
"@

# The comparison means nothing unless run B's daemon was actually adjudicating.
# A daemon that failed to mark would produce a B time equal to A and read as
# "enforcement is free", which is the most attractive wrong answer available.
$bAdjudicated = ($B.Raw -match '"handled":\s*[1-9]') -or ($B.Raw -match 'handled=[1-9]')
$cCopied = ($C.Raw -match 'SNAPSHOT_FILES=([1-9]\d*)')
Register-Control -Id 'Q5.CTL' -Name 'run B''s daemon actually adjudicated events, and run C actually copied' `
    -Fired ($bAdjudicated -and $cCopied) `
    -Evidence "B handled events=$bAdjudicated; C wrote snapshot files=$cCopied. Without both, an equal-to-baseline timing reads as 'enforcement is free' when it means 'the daemon was not attached'." | Out-Null

Section 'Result'
$ok = ($A.Secs -gt 0) -and ($B.Secs -gt 0) -and ($C.Secs -gt 0)
if (-not $ok) {
    Record 'Q5.1' 'Three comparable timed runs completed' 'VOID' "A=$($A.Secs) B=$($B.Secs) C=$($C.Secs); a missing run makes both differences unreportable"
} else {
    $ba = [math]::Round($B.Secs - $A.Secs, 1)
    $cb = [math]::Round($C.Secs - $B.Secs, 1)
    W ("A={0}s  B={1}s  C={2}s" -f $A.Secs, $B.Secs, $C.Secs)
    W ("cost of ENFORCEMENT (B-A) = {0}s" -f $ba)
    W ("cost of COPYING     (C-B) = {0}s" -f $cb)
    Record 'Q5.1' 'Three comparable timed runs completed' 'PASS' "A=$($A.Secs)s B=$($B.Secs)s C=$($C.Secs)s, identical work each time"
    Record 'Q5.2' 'Cost of ENFORCEMENT, B minus A' 'INFO' `
        "$ba s on the same work. Attacked with mark scope and kernel-side exclusions."
    Record 'Q5.3' 'Cost of COPYING, C minus B' 'INFO' `
        "$cb s on the same work. A different problem with different fixes; deliberately not summed with the line above."
}

try { Revoke-Workspace -Id $slug | Out-Null; W "revoked $slug" } catch { W "revoke threw: $($_.Exception.Message)" }
Complete-Phase -ResultsJson 'C:\cfv\g4-q5-results.json' -MarkerPrefix 'G4Q5'
