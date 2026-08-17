<#
  QUESTION 1. Does the kernel ENFORCE fanotify permission decisions?

  This is the question that decides structural versus advisory, so it is the one
  most worth being pedantic about.

  WHAT IS DELIBERATELY NOT BEING MEASURED
  ---------------------------------------
  Not "does fanotify_init succeed". Not "does an event arrive". Both are true on
  a kernel that will happily deliver notifications and ignore every verdict, and
  a Guard 4 built on either would be advisory while claiming to be structural.

  The measurement is three-part and all three must hold:
    * the opener BLOCKS for an interval the daemon chose, so the kernel is
      genuinely waiting rather than informing
    * a FAN_DENY makes the open FAIL WITH EPERM, so the verdict is honoured
    * a file outside the mark opens normally, so the mark is what is doing the
      work rather than something else being broken

  L30.1, and it applies to the deny case specifically. A fault injection that
  does not inject scores a false pass and looks exactly like a working control.
  "The daemon decided to deny" is not evidence; the payload therefore records the
  BYTE COUNT returned by the write of the response, and the deny is only credited
  when the kernel accepted all eight bytes of it.

  THE ARM THAT IS NOT IN THE WORK PACKAGE, AND WHY IT IS HERE
  -----------------------------------------------------------
  The work package says to mark a synthetic tree under /var/tmp, which is ext4.
  But granted workspaces are not ext4: clawfactory-grants.ps1 mounts each granted
  Windows folder at /workspaces/<slug> over drvfs. A YES on ext4 and a NO on
  drvfs would mean Guard 4 is impossible exactly where it has to work, while
  reading as a green result. So the same measurement is taken twice, on both
  filesystems, and the drvfs arm is the one that decides the product question.
  The drvfs arm grants a NEWLY CREATED EMPTY folder: no real workspace with real
  content is touched anywhere in this phase.
#>
param(
    [string]$Transcript = 'C:\cfv\g4-q1-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\g4-common.ps1

Start-Phase -Name 'Guard 4 Q1: does the kernel enforce fanotify permission decisions?' `
    -Transcript $Transcript -Sentinel 'G4_Q1_COMPLETE'

$DELAY = 3.0   # seconds the daemon holds the allow. Must be well above scheduler noise.

# ---------------------------------------------------------------- channel ---
$chan = Test-WslChannel
Register-Control -Id 'Q1.CHAN' -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { Complete-Phase -ResultsJson 'C:\cfv\g4-q1-results.json' -MarkerPrefix 'G4Q1' }

# ------------------------------------------------------------- interpreter --
Section '0. The interpreter, and proof it is the thing reporting'
$py = Install-G4Py
Register-Control -Id 'Q1.PY' -Name 'python3 reaches libc and runs THIS payload' `
    -Fired $py.Ok -Evidence $py.Detail | Out-Null
Record 'Q1.0' 'python3 is present on a shipped box without being installed by this probe' `
    $(if ($py.Present) { 'PASS' } else { 'FAIL' }) `
    "python3=$($py.Python). If ABSENT, a Guard 4 using these syscalls has a bundling dependency."
if (-not $py.Ok) {
    W 'The interpreter could not be shown to work, so nothing below would be a kernel answer.'
    Complete-Phase -ResultsJson 'C:\cfv\g4-q1-results.json' -MarkerPrefix 'G4Q1'
}

# -------------------------------------------------------------- uid check ---
Section '0b. The opener uid, checked rather than assumed'
# The payload setuids to 1000. If the agent is not uid 1000 on this box then the
# opener is some other account and the whole measurement is about the wrong
# subject, which is a precondition failure and not a product verdict.
$uid = Invoke-WslFile -Tag 'g4-uid' -User 'root' -Body @'
echo "CLAWUSER_UID=$(id -u clawuser 2>/dev/null || echo ABSENT)"
echo "CLAWUSER_GID=$(id -g clawuser 2>/dev/null || echo ABSENT)"
echo "CONTROL_NOSUCHUSER=$(id -u definitelynotauser 2>/dev/null || echo correctly-absent)"
'@
W $uid.Out
$uidOk = ($uid.Out -match 'CLAWUSER_UID=1000') -and ($uid.Out -match 'CONTROL_NOSUCHUSER=correctly-absent')
$null = Require-Precondition -Id 'Q1.PRE.UID' -Name 'the agent account is uid 1000, which is what the payload opens as' `
    -Met $uidOk -Reason 'the payload setuids to 1000 before opening; if clawuser is a different uid the opener is the wrong subject'

# ============================================================================
Section '1. ext4 arm: a synthetic tree under /var/tmp'
$mk = Invoke-WslFile -Tag 'g4-q1-tree' -User 'root' -Body @'
rm -rf /var/tmp/g4/marked /var/tmp/g4/unmarked
mkdir -p /var/tmp/g4/marked /var/tmp/g4/unmarked
: > /var/tmp/g4/marked/allow.txt
: > /var/tmp/g4/marked/deny.txt
: > /var/tmp/g4/unmarked/free.txt
chmod 0777 /var/tmp/g4 /var/tmp/g4/marked /var/tmp/g4/unmarked
chmod 0666 /var/tmp/g4/marked/allow.txt /var/tmp/g4/marked/deny.txt /var/tmp/g4/unmarked/free.txt
echo "FSTYPE_MARKED=$(stat -f -c %T /var/tmp/g4/marked)"
echo "--- the tree, as clawuser sees it ---"
su -s /bin/bash -c 'ls -l /var/tmp/g4/marked /var/tmp/g4/unmarked' clawuser 2>&1
echo "--- CONTROL: clawuser can open these for writing with NO daemon running ---"
su -s /bin/bash -c 'if : > /var/tmp/g4/marked/allow.txt; then echo BASELINE_WRITE_OK; else echo BASELINE_WRITE_FAILED; fi' clawuser 2>&1
'@
W $mk.Out
# Without this, an EPERM later could be an ordinary permissions problem wearing
# the costume of a kernel enforcement result.
$baseOk = $mk.Out -match 'BASELINE_WRITE_OK'
Register-Control -Id 'Q1.1.CTL' -Name 'clawuser can open the subject files for writing when nothing is watching' `
    -Fired $baseOk -Evidence 'so an EPERM under the daemon is the verdict being honoured, not a file-mode problem' | Out-Null

$r1 = Invoke-WslFile -Tag 'g4-q1-perm-ext4' -User 'root' -Body @"
cd /var/tmp/g4
timeout 120 python3 /var/tmp/g4-probe.py perm /var/tmp/g4/marked /var/tmp/g4/unmarked $DELAY 2>&1
echo "PERM_RC=`$?"
"@
W $r1.Out
$j1 = @(Get-G4Json -Text $r1.Out) | Where-Object { $_.cmd -eq 'perm' } | Select-Object -First 1

if (-not $j1) {
    Record 'Q1.1' 'The ext4 arm produced a machine-readable result' 'VOID' `
        'no G4JSON line: the payload did not complete, so the kernel was not asked'
} else {
    W ("init_errno={0} mark_ok={1} mark_errno={2} verdict={3}" -f $j1.init_errno, $j1.mark_ok, $j1.mark_errno, $j1.verdict)
    $e = $j1.evidence
    if ($e) { W ("evidence: " + ($j1.evidence | ConvertTo-Json -Compress)) }
    foreach ($d in @($j1.daemon_log)) { W ("  daemon: {0} -> {1}, response_bytes={2}, held={3}s, abi=v{4}" -f $d.path, $d.verdict, $d.response_bytes, $d.delayed, $d.abi_version) }

    # An EINVAL from fanotify_init with FAN_CLASS_CONTENT is the kernel's own
    # answer and is a CLEAN NO, distinct from a bug in the call.
    if ($j1.verdict -eq 'NO_PERM_CLASS') {
        Record 'Q1.1' 'ext4: the kernel supports fanotify PERMISSION events at all' 'FAIL' `
            "fanotify_init(FAN_CLASS_CONTENT) returned $($j1.init_errno). EINVAL here means permission events are compiled out of this kernel: a clean no, not a probe defect."
    } else {
        Record 'Q1.1' 'ext4: the kernel supports fanotify PERMISSION events at all' 'PASS' `
            "fanotify_init(FAN_CLASS_CONTENT) succeeded, mark accepted=$($j1.mark_ok)"

        Record 'Q1.2' 'ext4: the opener BLOCKS until the daemon answers' `
            $(if ($e.allow_blocked) { 'PASS' } else { 'FAIL' }) `
            "daemon held the allow for ${DELAY}s; opener measured $($e.allow_elapsed)s. An immediate return means the event is a notification and the candidate is dead."

        Record 'Q1.3' 'ext4: FAN_DENY makes the open FAIL WITH EPERM' `
            $(if ($e.deny_refused) { 'PASS' } else { 'FAIL' }) `
            "opener errno=$($e.deny_errno) (must be EPERM)"

        # L30.1. The deny result is only creditable if the deny actually landed.
        Register-Control -Id 'Q1.3.CTL' -Name 'the FAN_DENY was ISSUED, not merely intended' `
            -Fired ([bool]$e.deny_was_issued) `
            -Evidence 'the kernel accepted all 8 bytes of the fanotify_response carrying FAN_DENY; without this the EPERM could have come from anywhere' | Out-Null

        Record 'Q1.4' 'ext4: an UNMARKED file opens normally, so the mark is what is doing the work' `
            $(if ($e.unmarked_opened_normally) { 'PASS' } else { 'FAIL' }) `
            "unmarked open took $($e.unmarked_elapsed)s and succeeded=$($e.unmarked_opened_normally)"

        Record 'Q1.5' 'ext4 OVERALL: the kernel waits for a root daemon and honours its verdict' `
            $(if ($j1.verdict -eq 'ENFORCED') { 'PASS' } else { 'FAIL' }) `
            "payload verdict=$($j1.verdict), events delivered=$($e.events_delivered)"
    }
}

# ============================================================================
Section '2. drvfs arm: the filesystem granted workspaces ACTUALLY live on'
# clawfactory-grants.ps1:35 mounts each granted Windows folder at
# /workspaces/<slug> over drvfs. An ext4-only answer would not be the product
# answer, so the same three measurements are taken again over a real drvfs mount.
# The granted folder is created empty by this probe.
$grantOut = ''
$slug = ''
try {
    New-Item -ItemType Directory -Path 'C:\cfv\g4-drvfs' -Force | Out-Null
    . 'C:\Program Files\ClawFactory\resources\clawfactory-grants.ps1'
    $g = Grant-Workspace -Path 'C:\cfv\g4-drvfs' -Mode rw
    $slug = $g.id
    $grantOut = "granted id=$slug target=$($g.target)"
} catch {
    $grantOut = "Grant-Workspace threw: $($_.Exception.Message)"
}
W $grantOut

$drvOk = [bool]$slug
$null = Require-Precondition -Id 'Q1.PRE.DRVFS' -Name 'a drvfs workspace mount exists to measure' `
    -Met $drvOk -Reason 'without a live /workspaces mount the drvfs arm has no subject, and an ext4-only answer is not the product answer'

if ($drvOk) {
    $gp = "/workspaces/$slug"
    $mk2 = Invoke-WslFile -Tag 'g4-q1-tree-drvfs' -User 'root' -Body @"
echo "MOUNT_LINE=`$(mount | grep -F '$gp' | head -1)"
echo "FSTYPE=`$(stat -f -c %T '$gp' 2>&1)"
mkdir -p '$gp/marked' '$gp/unmarked'
: > '$gp/marked/allow.txt'
: > '$gp/marked/deny.txt'
: > '$gp/unmarked/free.txt'
echo '--- CONTROL: clawuser can write here with no daemon running ---'
su -s /bin/bash -c "if : > '$gp/marked/allow.txt'; then echo BASELINE_WRITE_OK; else echo BASELINE_WRITE_FAILED; fi" clawuser 2>&1
"@
    W $mk2.Out
    $base2 = $mk2.Out -match 'BASELINE_WRITE_OK'
    Register-Control -Id 'Q1.6.CTL' -Name 'clawuser can write into the granted drvfs mount when nothing is watching' `
        -Fired $base2 -Evidence 'so a later refusal is the daemon, not the mount being read-only' | Out-Null

    $r2 = Invoke-WslFile -Tag 'g4-q1-perm-drvfs' -User 'root' -Body @"
timeout 120 python3 /var/tmp/g4-probe.py perm '$gp/marked' '$gp/unmarked' $DELAY 2>&1
echo "PERM_RC=`$?"
"@
    W $r2.Out
    $j2 = @(Get-G4Json -Text $r2.Out) | Where-Object { $_.cmd -eq 'perm' } | Select-Object -First 1

    if (-not $j2) {
        Record 'Q1.6' 'drvfs: the arm produced a machine-readable result' 'VOID' `
            'no G4JSON line from the drvfs arm'
    } else {
        W ("drvfs: init_errno={0} mark_ok={1} mark_errno={2} verdict={3}" -f $j2.init_errno, $j2.mark_ok, $j2.mark_errno, $j2.verdict)
        foreach ($d in @($j2.daemon_log)) { W ("  daemon: {0} -> {1}, response_bytes={2}, held={3}s" -f $d.path, $d.verdict, $d.response_bytes, $d.delayed) }

        Record 'Q1.6' 'drvfs: fanotify will MARK the filesystem granted workspaces live on' `
            $(if ($j2.mark_ok) { 'PASS' } else { 'FAIL' }) `
            "fanotify_mark on $gp returned $($j2.mark_errno). This is the product question: an ext4-only yes does not reach a granted workspace."

        if ($j2.mark_ok) {
            $e2 = $j2.evidence
            Record 'Q1.7' 'drvfs: the opener BLOCKS until the daemon answers' `
                $(if ($e2.allow_blocked) { 'PASS' } else { 'FAIL' }) `
                "opener measured $($e2.allow_elapsed)s against a ${DELAY}s hold"
            Record 'Q1.8' 'drvfs: FAN_DENY makes the open FAIL WITH EPERM' `
                $(if ($e2.deny_refused) { 'PASS' } else { 'FAIL' }) `
                "opener errno=$($e2.deny_errno), deny issued=$($e2.deny_was_issued)"
            Record 'Q1.9' 'drvfs OVERALL: enforcement reaches a granted workspace' `
                $(if ($j2.verdict -eq 'ENFORCED') { 'PASS' } else { 'FAIL' }) `
                "payload verdict=$($j2.verdict)"
        } else {
            Record 'Q1.9' 'drvfs OVERALL: enforcement reaches a granted workspace' 'FAIL' `
                "the mark was refused with $($j2.mark_errno), so no enforcement is possible on a granted workspace by this mechanism"
        }
    }

    # Leave the box as it was found.
    try { Revoke-Workspace -Id $slug | Out-Null; W "revoked $slug" } catch { W "revoke threw: $($_.Exception.Message)" }
}

Complete-Phase -ResultsJson 'C:\cfv\g4-q1-results.json' -MarkerPrefix 'G4Q1'
