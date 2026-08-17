<#
  QUESTION 3. Write volume, and where it lands.

  THE QUESTION MOST LIKELY TO KILL THE DESIGN, AND IT IS OBSERVATIONAL.

  Notification mode only. FAN_CLASS_NOTIF cannot block anything, so a realistic
  session runs at full speed and nothing is at risk while it is measured. That is
  deliberate: the point is to find out how much traffic a permission-mode daemon
  would have had to adjudicate, without adjudicating any of it.

  THE FOLLOW-UP IS THE PART THAT DECIDES VIABILITY
  ------------------------------------------------
  Raw counts alone do not settle anything. If node_modules is 95 percent of the
  writes but the kernel can be told to ignore that subtree AT MARK PLACEMENT
  TIME, the cost is never paid and the number is irrelevant. If instead every
  write has to be delivered to userspace before it can be discarded, the cost is
  paid whether or not a snapshot is taken, and the design is in trouble at
  exactly this number.

  fanotify has FAN_MARK_IGNORED_MASK for precisely this, so the measurement is
  whether it WORKS here, on this kernel and this filesystem, rather than whether
  the flag exists. The test has a control on both sides: writes inside the
  ignored subtree must stop arriving while writes outside it keep arriving in the
  same run. One side alone proves nothing, because a daemon that has stopped
  receiving everything also shows zero from the ignored subtree.
#>
param(
    [string]$Transcript = 'C:\cfv\g4-q3-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\g4-common.ps1

Start-Phase -Name 'Guard 4 Q3: write volume in a real session, and where the exclusion can be applied' `
    -Transcript $Transcript -Sentinel 'G4_Q3_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'Q3.CHAN' -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { Complete-Phase -ResultsJson 'C:\cfv\g4-q3-results.json' -MarkerPrefix 'G4Q3' }

$py = Install-G4Py
Register-Control -Id 'Q3.PY' -Name 'python3 reaches libc and runs THIS payload' `
    -Fired $py.Ok -Evidence $py.Detail | Out-Null
if (-not $py.Ok) { Complete-Phase -ResultsJson 'C:\cfv\g4-q3-results.json' -MarkerPrefix 'G4Q3' }

# ============================================================================
Section '1. A granted workspace carrying a realistic project'
$slug = ''
try {
    New-Item -ItemType Directory -Path 'C:\cfv\g4-work' -Force | Out-Null
    . 'C:\Program Files\ClawFactory\resources\clawfactory-grants.ps1'
    $g = Grant-Workspace -Path 'C:\cfv\g4-work' -Mode rw
    $slug = $g.id
    W "granted id=$slug"
} catch { W "Grant-Workspace threw: $($_.Exception.Message)" }

$null = Require-Precondition -Id 'Q3.PRE' -Name 'a granted workspace exists to instrument' `
    -Met ([bool]$slug) -Reason 'the question is about writes in a GRANTED workspace; measuring somewhere else answers a different question'
if (-not $slug) { Complete-Phase -ResultsJson 'C:\cfv\g4-q3-results.json' -MarkerPrefix 'G4Q3' }
$gp = "/workspaces/$slug"

$seed = Invoke-WslFile -Tag 'g4-q3-seed' -User 'root' -Body @"
chown -R clawuser:clawuser '$gp' 2>/dev/null
su -s /bin/bash -c "
  mkdir -p '$gp/proj/src'
  cd '$gp/proj'
  printf '{\"name\":\"g4probe\",\"version\":\"1.0.0\",\"dependencies\":{\"ms\":\"2.1.3\"}}\n' > package.json
  printf 'console.log(1);\n' > src/index.js
  git init -q 2>&1 | head -2
  git config user.email probe@example.invalid
  git config user.name probe
  git add -A 2>&1 | head -2
  git commit -q -m seed 2>&1 | head -2
" clawuser 2>&1 | tail -5
echo "GIT_PRESENT=`$(command -v git || echo ABSENT)"
echo "NPM_PRESENT=`$(command -v npm || echo ABSENT)"
echo "PROJ_READY=`$([ -d '$gp/proj/.git' ] && echo yes || echo no)"
"@
W $seed.Out
$toolsOk = ($seed.Out -match 'PROJ_READY=yes') -and ($seed.Out -match 'NPM_PRESENT=/')
$null = Require-Precondition -Id 'Q3.PRE.TOOLS' -Name 'git and npm are available so the session is realistic' `
    -Met $toolsOk -Reason 'a dependency install and a git operation are two of the three workloads; without them the counts describe a different session'

# ============================================================================
Section '2. Count write events during a realistic session'
# The daemon runs for a fixed window and the workload runs inside it. The window
# is generous because a real agent turn is minutes, not seconds, and a daemon
# that expires mid-turn undercounts in a way that looks like a light workload.
$WINDOW = 420
$run = Invoke-WslFile -Tag 'g4-q3-count' -User 'root' -Body @"
rm -f /var/tmp/g4/count.json
nohup python3 /var/tmp/g4-probe.py count '$gp' $WINDOW /var/tmp/g4/count.json > /var/tmp/g4/count.log 2>&1 &
DPID=`$!
sleep 4
echo "DAEMON_PID=`$DPID"
echo "DAEMON_ALIVE=`$(kill -0 `$DPID 2>/dev/null && echo yes || echo no)"

echo '=== workload 1: a real agent turn doing ordinary file work ==='
# L17: warm first. A cold first turn measures start-up, not file work.
su -s /bin/bash -c "timeout 180 openclaw agent --agent main --message 'Reply with the single word READY.' 2>&1 | tail -3" clawuser 2>&1 | tail -3
echo '--- warmed, now the load-bearing turn ---'
su -s /bin/bash -c "cd '$gp/proj' && timeout 240 openclaw agent --agent main --message 'In the folder $gp/proj, create three small text files called note1.txt, note2.txt and note3.txt, each containing one sentence about the project, then append a line to src/index.js. Do it now.' 2>&1 | tail -6" clawuser 2>&1 | tail -8

echo '=== workload 2: a dependency install ==='
su -s /bin/bash -c "cd '$gp/proj' && timeout 180 npm install --no-audit --no-fund 2>&1 | tail -4" clawuser 2>&1 | tail -5

echo '=== workload 3: a git operation that touches the object store ==='
su -s /bin/bash -c "cd '$gp/proj' && git add -A && git commit -q -m 'after workload' 2>&1 | tail -2 && git log --oneline | head -3" clawuser 2>&1 | tail -5

echo '=== CONTROL: a write this probe makes itself, which MUST be counted ==='
su -s /bin/bash -c "echo COUNTED-CONTROL > '$gp/proj/counted-control.txt'" clawuser 2>&1

echo '--- waiting for the counting window to close ---'
wait `$DPID 2>/dev/null
echo "COUNT_JSON_PRESENT=`$([ -s /var/tmp/g4/count.json ] && echo yes || echo no)"
cat /var/tmp/g4/count.json 2>/dev/null | head -c 4000
echo
echo '--- daemon log ---'
tail -5 /var/tmp/g4/count.log
"@
W $run.Out
$j = @(Get-G4Json -Text $run.Out) | Where-Object { $_.cmd -eq 'count' } | Select-Object -First 1
if (-not $j) {
    # The JSON also lands in a file; read it independently rather than voiding on
    # a lost stdout line.
    $c = Invoke-WslFile -Tag 'g4-q3-countread' -User 'root' -Body 'python3 -c "import sys;sys.stdout.write(open(\"/var/tmp/g4/count.json\").read())" 2>/dev/null | sed "s/^/G4JSON /"'
    $j = @(Get-G4Json -Text $c.Out) | Select-Object -First 1
}

if (-not $j) {
    Record 'Q3.1' 'Write events were counted during a realistic session' 'VOID' `
        'no counting result from either channel, so no volume number exists to report'
} else {
    W ("mount_mark_ok={0} errno={1} total={2}" -f $j.mount_mark_ok, $j.mount_mark_errno, $j.total)
    W ("buckets: " + ($j.buckets | ConvertTo-Json -Compress))
    foreach ($s in @($j.samples)) { W "   sample: $s" }

    Register-Control -Id 'Q3.2.CTL' -Name 'the counter saw at least one event it was guaranteed to see' `
        -Fired ($j.total -gt 0) `
        -Evidence "total=$($j.total). A zero here is not a quiet session, it is a counter that was not attached, and the bucket percentages below would be meaningless." | Out-Null

    Record 'Q3.1' 'A mount-scoped notification mark could be placed on the granted workspace' `
        $(if ($j.mount_mark_ok) { 'PASS' } else { 'FAIL' }) `
        "errno=$($j.mount_mark_errno); fell back to a directory mark=$($j.dir_mark_ok)"
    Record 'Q3.2' 'Absolute write-event volume for one realistic session' 'INFO' `
        "total=$($j.total) events over ${WINDOW}s covering one agent turn, one npm install and one git commit"
    Record 'Q3.3' 'Share of events landing in the excluded prefixes' 'INFO' `
        "$($j.excluded_prefix_count) of $($j.total) = $($j.excluded_prefix_pct) percent in .git, node_modules, __pycache__, .venv or build output"
}

# ============================================================================
Section '3. THE FOLLOW-UP THAT DECIDES VIABILITY: where can the exclusion be applied'
# FAN_MARK_IGNORED_MASK is an exclusion the KERNEL applies. If it works, the
# events never reach userspace and the volume above stops being a cost. If it
# does not, every write in node_modules is delivered before it can be discarded
# and the cost is paid whether or not a snapshot is taken.
$ig = Invoke-WslFile -Tag 'g4-q3-ignore' -User 'root' -Body @"
# THE IGNORE MARK GOES ON THE DIRECTORY THE WRITES ACTUALLY LAND IN.
#
# The first run marked .../node_modules and then wrote to
# .../node_modules/probe-pkg/. fanotify ignore masks are PER INODE: a mark on a
# directory does not cover its subdirectories. So every event arrived, and the
# probe reported that the kernel-side exclusion does not work. It had not been
# asked. That per-inode property is itself a first-class finding for Guard 4,
# because it means excluding node_modules means walking it and marking every
# directory in it, not placing one mark at the top.
#
# The writes are also generated by a SCRIPT FILE rather than an inline loop. The
# first run wrote `f$i.txt` through two levels of quoting, the outer shell
# expanded $i to empty, and all ten writes hit one filename. A file has one
# level of quoting and cannot do that.
IGDIR='$gp/proj/node_modules/probe-pkg'
mkdir -p "`$IGDIR"
chown -R clawuser:clawuser '$gp/proj' 2>/dev/null
cat > /var/tmp/g4/writes.sh <<'WEOF'
#!/bin/bash
IGDIR="`$1"
OUTDIR="`$2"
for i in 1 2 3 4 5 6 7 8 9 10; do echo x > "`$IGDIR/ig-`$i.txt"; done
for i in 1 2 3 4 5; do echo x > "`$OUTDIR/out-`$i.txt"; done
echo "WROTE_INSIDE=`$(ls "`$IGDIR" | wc -l | tr -d ' ')"
echo "WROTE_OUTSIDE=`$(ls "`$OUTDIR"/out-*.txt 2>/dev/null | wc -l | tr -d ' ')"
WEOF
chmod 0755 /var/tmp/g4/writes.sh
rm -f /var/tmp/g4/ignore.json
nohup python3 /var/tmp/g4-probe.py count '$gp' 60 /var/tmp/g4/ignore.json "`$IGDIR" > /var/tmp/g4/ignore.log 2>&1 &
DPID=`$!
sleep 4
echo '--- 10 writes INSIDE the ignored directory, 5 OUTSIDE, same run ---'
su -s /bin/bash -c "/var/tmp/g4/writes.sh '`$IGDIR' '$gp/proj'" clawuser 2>&1
wait `$DPID 2>/dev/null
cat /var/tmp/g4/ignore.json 2>/dev/null | head -c 3000
echo
tail -3 /var/tmp/g4/ignore.log
"@
W $ig.Out
$ji = @(Get-G4Json -Text $ig.Out) | Where-Object { $_.cmd -eq 'count' } | Select-Object -First 1
if (-not $ji) {
    $c2 = Invoke-WslFile -Tag 'g4-q3-igread' -User 'root' -Body 'python3 -c "import sys;sys.stdout.write(open(\"/var/tmp/g4/ignore.json\").read())" 2>/dev/null | sed "s/^/G4JSON /"'
    $ji = @(Get-G4Json -Text $c2.Out) | Select-Object -First 1
}

if (-not $ji) {
    Record 'Q3.4' 'A kernel-side exclusion can be applied at mark placement time' 'VOID' `
        'no result from the ignore-mask run, so the exclusion question is unmeasured'
} else {
    $ignored = [int]$ji.buckets.ignored_subtree
    $outside = [int]$ji.total - $ignored
    W ("ignore_mark_ok={0} errno={1} ignored_subtree={2} other={3}" -f $ji.ignore_mark_ok, $ji.ignore_mark_errno, $ignored, $outside)

    # Both halves, or neither means anything. A daemon receiving nothing at all
    # also reports zero from the ignored subtree.
    Register-Control -Id 'Q3.4.CTL' -Name 'writes OUTSIDE the ignored subtree were still delivered in the same run' `
        -Fired ($outside -gt 0) `
        -Evidence "$outside event(s) arrived from outside the ignored subtree, so a zero from inside it is the exclusion working rather than the counter being detached" | Out-Null

    # L30.1 applied to the WRITES THEMSELVES. The first run's ten writes all
    # landed on one filename because a variable expanded in the wrong shell, and
    # the event count was then read as a kernel behaviour. A generator that did
    # not generate is a fault injection that did not inject.
    $wroteIn  = if ($ig.Out -match 'WROTE_INSIDE=(\d+)')  { [int]$Matches[1] } else { -1 }
    $wroteOut = if ($ig.Out -match 'WROTE_OUTSIDE=(\d+)') { [int]$Matches[1] } else { -1 }
    Register-Control -Id 'Q3.5.CTL' -Name 'the writes this test depends on were actually made, as distinct files' `
        -Fired (($wroteIn -eq 10) -and ($wroteOut -eq 5)) `
        -Evidence "distinct files written inside=$wroteIn (must be 10), outside=$wroteOut (must be 5)" | Out-Null

    Record 'Q3.4' 'FAN_MARK_IGNORED_MASK is accepted on this kernel and filesystem' `
        $(if ($ji.ignore_mark_ok) { 'PASS' } else { 'FAIL' }) "errno=$($ji.ignore_mark_errno)"
    Record 'Q3.5' 'The exclusion is applied BY THE KERNEL, so excluded writes cost nothing' `
        $(if ($ignored -eq 0 -and $outside -gt 0) { 'PASS' } else { 'FAIL' }) `
        "$ignored event(s) from 10 writes inside the ignored subtree, $outside from 5 writes outside. Zero inside with non-zero outside is the answer that makes the volume number harmless."
}

try { Revoke-Workspace -Id $slug | Out-Null; W "revoked $slug" } catch { W "revoke threw: $($_.Exception.Message)" }
Complete-Phase -ResultsJson 'C:\cfv\g4-q3-results.json' -MarkerPrefix 'G4Q3'
