<#
  QUESTION 6. Second paths to the workspace.

  Every candidate enforcement point in the Guard 4 spec is PATH SCOPED. A path
  scoped control is only a control if the path is the only way in, so a second
  route is a bypass of all of them at once and it has to be found here rather
  than by a customer.

  ENUMERATE, DO NOT ASSUME. The temptation is to reason "automount is off,
  therefore /mnt/c is absent, therefore there is no second path" and stop. That
  chain is three assumptions wearing one conclusion. So this reads /proc/mounts
  directly, walks for symlinks, and asks the kernel what uid 1000 is actually
  permitted to do.

  THE CHECK THAT MATTERS MOST AND IS EASIEST TO MISS
  --------------------------------------------------
  Whether uid 1000 can create its own mount namespace. If unprivileged user
  namespaces are permitted, the agent can bind-mount a granted tree somewhere
  else in a namespace of its own. A per-directory or per-mount fanotify mark does
  not follow a bind mount into a new mount, so that would defeat a mount-scoped
  Guard 4 outright while leaving a filesystem-scoped one intact. That difference
  changes which mark scope Guard 4 must use, so it is measured rather than
  reasoned about.
#>
param(
    [string]$Transcript = 'C:\cfv\g4-q6-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\g4-common.ps1

Start-Phase -Name 'Guard 4 Q6: second paths to a granted workspace' `
    -Transcript $Transcript -Sentinel 'G4_Q6_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'Q6.CHAN' -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { Complete-Phase -ResultsJson 'C:\cfv\g4-q6-results.json' -MarkerPrefix 'G4Q6' }

# A live grant, so the enumeration has a real subject. Created empty by this
# probe: no real workspace with real content is touched.
$slug = ''
try {
    New-Item -ItemType Directory -Path 'C:\cfv\g4-paths' -Force | Out-Null
    'canary' | Out-File 'C:\cfv\g4-paths\CANARY-Q6.txt' -Encoding ascii
    . 'C:\Program Files\ClawFactory\resources\clawfactory-grants.ps1'
    $g = Grant-Workspace -Path 'C:\cfv\g4-paths' -Mode rw
    $slug = $g.id
    W "granted id=$slug target=$($g.target)"
} catch { W "Grant-Workspace threw: $($_.Exception.Message)" }

$null = Require-Precondition -Id 'Q6.PRE' -Name 'a live granted workspace exists to enumerate around' `
    -Met ([bool]$slug) -Reason 'with no grant there is no backing tree and "no second path" would be true of nothing'
if (-not $slug) { Complete-Phase -ResultsJson 'C:\cfv\g4-q6-results.json' -MarkerPrefix 'G4Q6' }

$gp = "/workspaces/$slug"

# ============================================================================
Section '1. Where the tree lives, and every mount that reaches it'
$m = Invoke-WslFile -Tag 'g4-q6-mounts' -User 'root' -Body @"
echo '=== the grant mount itself ==='
grep -F '$gp' /proc/mounts || echo '(no /proc/mounts line for the grant)'
echo
echo '=== EVERY drvfs or 9p mount on this box, unfiltered ==='
awk '{print `$1, `$2, `$3}' /proc/mounts | grep -E 'drvfs|9p|virtiofs' || echo '(none)'
echo
echo '=== the complete mount table, unfiltered ==='
cat /proc/mounts
echo
echo '=== CONTROL: a mount point that must NOT exist ==='
grep -F '/workspaces/definitely-not-a-grant' /proc/mounts && echo 'CONTROL FAILED' || echo 'CONTROL OK (absent)'
"@
W $m.Out
$ctlMount = $m.Out -match 'CONTROL OK \(absent\)'
Register-Control -Id 'Q6.1.CTL' -Name 'the mount enumeration can tell present from absent' `
    -Fired $ctlMount -Evidence 'a fabricated mount point was not found in /proc/mounts' | Out-Null
Record 'Q6.1' 'The granted workspace is a drvfs mount of a Windows folder' `
    $(if ($m.Out -match [regex]::Escape($gp)) { 'PASS' } else { 'FAIL' }) `
    'recorded verbatim above; the filesystem type is what decides whether a filesystem-scoped mark is even available'

# ============================================================================
Section '2. What uid 1000 can actually reach'
$u = Invoke-WslFile -Tag 'g4-q6-uid1000' -User 'clawuser' -Body @"
echo "whoami=`$(id -un) uid=`$(id -u)"
echo
echo '--- SUBJECT: the granted path itself, which is SUPPOSED to be reachable ---'
ls '$gp' 2>&1 | head -5
echo
echo '--- second path A: /mnt/c, which automount=false should have removed ---'
# An EMPTY DIRECTORY at /mnt/c is not a second path, and `[ -d ]` cannot tell
# the two apart. What matters is whether anything is MOUNTED there and whether
# the Windows filesystem is actually reachable through it.
echo "MNT_C_DIR_EXISTS=`$([ -d /mnt/c ] && echo yes || echo no)"
# BACKTICK, NOT BACKSLASH, and this single character cost question 6.
#
# `\$2` in a double-quoted PowerShell here-string is a backslash followed by the
# variable $2. On the VM an undefined variable reference is a TERMINATING error,
# so the here-string never evaluated, $u was never assigned, and every statement
# that touched it failed in cascade: no probe output, no positive control
# registered, and the verdict subexpressions produced NOTHING, which left five
# Record calls with an EMPTY verdict. An empty verdict is neither PASS nor FAIL
# nor VOID, so the runner counted them as nothing and reported the phase PASS.
#
# It survived an audit that grepped for `\$` followed by a letter or an open
# paren. awk field variables are DIGITS. The pattern used to prove the file
# clean could not match the defect being introduced in the same edit.
echo "MNT_C_IS_A_MOUNT=`$(awk '`$2 == "/mnt/c" {print "yes"}' /proc/mounts | head -1 || true)"
echo "MNT_C_ENTRIES=`$(ls -A /mnt/c 2>/dev/null | wc -l | tr -d ' ')"
if ls /mnt/c/Windows >/dev/null 2>&1; then echo "MNT_C_REACHES_WINDOWS=yes"; else echo "MNT_C_REACHES_WINDOWS=no"; fi
echo
echo '--- second path B: anything else under /mnt ---'
ls -la /mnt 2>&1 | head -10
echo
echo '--- second path C: the parent of the grant root ---'
ls -la /workspaces 2>&1 | head -10
echo
echo '--- second path D: symlinks anywhere in the grant tree ---'
find '$gp' -type l 2>/dev/null | head -10
echo "SYMLINKS_IN_GRANT=`$(find '$gp' -type l 2>/dev/null | wc -l | tr -d ' ')"
echo
echo '--- second path E: can uid 1000 mount anything at all ---'
# NOT `cmd | head` followed by `echo $?`. In a pipeline $? is the LAST command's
# status, so that reports head's exit code, which is 0 whatever mount did. The
# first run of this probe did exactly that and produced a confident, entirely
# invented finding that uid 1000 could bind-mount a granted workspace.
mkdir -p /var/tmp/g4-q6-mnt 2>/dev/null
if mount --bind '$gp' /var/tmp/g4-q6-mnt 2>/tmp/g4-bind.err; then echo "BIND_AS_UID1000=SUCCEEDED"; else echo "BIND_AS_UID1000=refused"; fi
echo "BIND_ERR=`$(head -1 /tmp/g4-bind.err 2>/dev/null)"
echo
echo '--- second path F: unprivileged user namespaces (would allow a private bind) ---'
echo "USERNS_CLONE=`$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo '(sysctl absent)')"
echo "USERNS_MAX=`$(cat /proc/sys/user/max_user_namespaces 2>/dev/null || echo '(sysctl absent)')"
if unshare -U -r -m true 2>/tmp/g4-uns.err; then echo "UNSHARE_USERNS=SUCCEEDED"; else echo "UNSHARE_USERNS=refused"; fi
echo "UNSHARE_ERR=`$(head -1 /tmp/g4-uns.err 2>/dev/null)"
echo '--- and the one that actually matters: a private bind INSIDE a new namespace ---'
if unshare -U -r -m --propagation private /bin/bash -c "mount --bind '$gp' /var/tmp/g4-q6-mnt && ls /var/tmp/g4-q6-mnt" 2>/tmp/g4-uns2.err; then echo "PRIVATE_BIND=SUCCEEDED"; else echo "PRIVATE_BIND=refused"; fi
echo "PRIVATE_BIND_ERR=`$(head -1 /tmp/g4-uns2.err 2>/dev/null)"
echo
echo '--- second path G: Docker, which SECFIX_CLOSE_DOORS decision A removed ---'
echo "DOCKER_BIN=`$(command -v docker || echo ABSENT)"
echo "DOCKER_SOCK=`$([ -S /var/run/docker.sock ] && echo present || echo absent)"
ls /var/lib/docker 2>&1 | head -2
echo
echo '--- CONTROL: a path that must be refused, so this probe is not simply saying yes ---'
if cat /etc/shadow >/dev/null 2>&1; then echo "SHADOW_READ=SUCCEEDED"; else echo "SHADOW_READ=refused"; fi
"@
W $u.Out

$shadowDenied = $u.Out -match 'SHADOW_READ=refused'
Register-Control -Id 'Q6.2.CTL' -Name 'the uid 1000 probe can be refused, so a success is a real success' `
    -Fired $shadowDenied -Evidence '/etc/shadow was denied to uid 1000 in the same run' | Out-Null

$mntC = $u.Out -match 'MNT_C_EXISTS=no'
Record 'Q6.2' 'uid 1000 has no /mnt/c view of the Windows filesystem' `
    $(if ($mntC) { 'PASS' } else { 'FAIL' }) `
    'automount=false is what removes this; its presence would be a second path to every granted folder at once'

$bindRefused = $u.Out -match 'BIND_AS_UID1000_RC=[1-9]'
Record 'Q6.3' 'uid 1000 cannot bind-mount the granted tree elsewhere' `
    $(if ($bindRefused) { 'PASS' } else { 'FAIL' }) `
    'a successful bind would give the agent a second path that a per-mount mark does not follow'

$usernsBlocked = $u.Out -match 'UNSHARE_RC=[1-9]'
Record 'Q6.4' 'uid 1000 cannot create its own mount namespace' `
    $(if ($usernsBlocked) { 'PASS' } else { 'FAIL' }) `
    'THIS DECIDES MARK SCOPE. If a private namespace is available, a per-mount mark is escapable by bind-mounting inside it and Guard 4 must use a filesystem-scoped mark instead.'

$noDocker = $u.Out -match 'DOCKER_BIN=ABSENT'
Record 'Q6.5' 'No Docker volume can reach the same tree, because Docker is absent' `
    $(if ($noDocker) { 'PASS' } else { 'FAIL' }) `
    'Docker was removed under SECFIX_CLOSE_DOORS decision A; re-checked here rather than assumed from the decision'

$noSymlinks = $u.Out -match 'SYMLINKS_IN_GRANT=0'
Record 'Q6.6' 'The granted tree contains no symlink leading out of it' `
    $(if ($noSymlinks) { 'PASS' } else { 'INFO' }) `
    'an empty probe-created grant; a customer tree can obviously contain symlinks, which is itself the finding'

# ============================================================================
Section '3. The backing directory, from the Windows side'
$w = Invoke-WslFile -Tag 'g4-q6-backing' -User 'root' -Body @"
echo '--- what the mount SOURCE is, as root sees it ---'
grep -F '$gp' /proc/mounts
echo
echo '--- can root reach the backing tree by a path other than the grant ---'
echo "ROOT_MNT_C=`$([ -d /mnt/c ] && echo present || echo absent)"
mkdir -p /var/tmp/g4-q6-alt
if mount -t drvfs 'C:\cfv\g4-paths' /var/tmp/g4-q6-alt 2>/dev/null; then
  echo 'ROOT_SECOND_MOUNT=established'
  ls /var/tmp/g4-q6-alt | head -3
  umount /var/tmp/g4-q6-alt
else
  echo 'ROOT_SECOND_MOUNT=refused'
fi
"@
W $w.Out
Record 'Q6.7' 'ROOT can mount the same Windows folder a second time' `
    $(if ($w.Out -match 'ROOT_SECOND_MOUNT=established') { 'INFO' } else { 'INFO' }) `
    'recorded as context, not as a defect: root is not the actor Guard 4 defends against. It matters only because a Guard 4 daemon must be the one holding that privilege.'

try { Revoke-Workspace -Id $slug | Out-Null; W "revoked $slug" } catch { W "revoke threw: $($_.Exception.Message)" }

Complete-Phase -ResultsJson 'C:\cfv\g4-q6-results.json' -MarkerPrefix 'G4Q6'
