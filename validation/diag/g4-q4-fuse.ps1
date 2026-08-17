<#
  QUESTION 4. FUSE passthrough, the fallback candidate.

  Only worth answering if question 1 came back no, or came back yes on ext4 and
  no on drvfs. The driver decides that; this file measures.

  FOUR THINGS, AND THE FOURTH DECIDES IT
  ---------------------------------------
    1. is /dev/fuse present and does the kernel carry the fuse filesystem
    2. can root mount a FUSE filesystem inside the distro at all
    3. can a passthrough be mounted over a granted folder
    4. once it is mounted, does uid 1000 have ANY path to the backing directory

  Four is the whole question. A passthrough whose backing tree is still readable
  and writable by the agent is not a control, it is a suggestion: the agent
  simply writes to the backing path and the interposed filesystem never sees it.
  So this enumerates rather than assumes, the same discipline as question 6.

  ON INSTALLING A PACKAGE
  ----------------------
  A FUSE passthrough needs a userspace filesystem to passthrough WITH, and the
  shipped box has no reason to carry one. If bindfs has to be installed, that is
  recorded as a FINDING rather than a step: it means Guard 4 has a bundling
  dependency, and the size of that dependency is one of the numbers this whole
  probe exists to produce. Note also what installing it demonstrates in passing,
  which is worth its own line in the report: apt runs as root and the egress
  firewall is scoped to uid 1000, so a root package install is not gated by the
  control that gates the agent.
#>
param(
    [string]$Transcript = 'C:\cfv\g4-q4-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\g4-common.ps1

Start-Phase -Name 'Guard 4 Q4: FUSE passthrough as the fallback enforcement point' `
    -Transcript $Transcript -Sentinel 'G4_Q4_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'Q4.CHAN' -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { Complete-Phase -ResultsJson 'C:\cfv\g4-q4-results.json' -MarkerPrefix 'G4Q4' }

# ============================================================================
Section '1. Is FUSE available at all on a shipped box'
$p = Invoke-WslFile -Tag 'g4-q4-present' -User 'root' -Body @'
echo "DEV_FUSE=$([ -e /dev/fuse ] && echo present || echo absent)"
[ -e /dev/fuse ] && stat -c 'DEV_FUSE_MODE=%A %U:%G' /dev/fuse
echo "PROC_FS_FUSE=$(grep -c fuse /proc/filesystems 2>/dev/null | tr -d ' ')"
grep fuse /proc/filesystems 2>/dev/null
echo "FUSERMOUNT=$(command -v fusermount3 || command -v fusermount || echo ABSENT)"
echo "FUSE_CONF=$([ -f /etc/fuse.conf ] && echo present || echo absent)"
[ -f /etc/fuse.conf ] && cat /etc/fuse.conf
echo "BINDFS=$(command -v bindfs || echo ABSENT)"
echo "--- CONTROL: a device node that must NOT exist ---"
[ -e /dev/definitely-not-a-device ] && echo "CONTROL FAILED" || echo "CONTROL OK (absent)"
'@
W $p.Out
$ctl = $p.Out -match 'CONTROL OK \(absent\)'
Register-Control -Id 'Q4.1.CTL' -Name 'the presence probe can tell present from absent' `
    -Fired $ctl -Evidence 'a fabricated device node was not found' | Out-Null

$devFuse = $p.Out -match 'DEV_FUSE=present'
$kernelFuse = $p.Out -match '(?m)^\s*(nodev\s+)?fuse\s*$' -or ($p.Out -match 'fuseblk')
Record 'Q4.1' '/dev/fuse is present on a shipped box' `
    $(if ($devFuse) { 'PASS' } else { 'FAIL' }) 'read directly, not inferred from the kernel config'
Record 'Q4.2' 'The kernel carries the fuse filesystem' `
    $(if ($kernelFuse) { 'PASS' } else { 'FAIL' }) '/proc/filesystems listing above'

$hadBindfs = $p.Out -match 'BINDFS=/'
Record 'Q4.3' 'A FUSE passthrough implementation is already on the box' `
    $(if ($hadBindfs) { 'PASS' } else { 'FAIL' }) `
    "bindfs present before this probe=$hadBindfs. A FAIL here is a BUNDLING FINDING, not a product defect: it sizes the Guard 4 build."

# ============================================================================
Section '2. Install a passthrough implementation, and record that it was needed'
if (-not $hadBindfs) {
    $i = Invoke-WslFile -Tag 'g4-q4-install' -User 'root' -Body @'
echo "--- installing bindfs. This is a PROBE dependency, recorded as a finding. ---"
DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>&1 | tail -3
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bindfs 2>&1 | tail -5
echo "APT_RC=$?"
echo "BINDFS_AFTER=$(command -v bindfs || echo ABSENT)"
dpkg -l bindfs 2>/dev/null | tail -1
'@
    W $i.Out
    Record 'Q4.4' 'bindfs installs from the Ubuntu archive as root' `
        $(if ($i.Out -match 'BINDFS_AFTER=/') { 'PASS' } else { 'FAIL' }) `
        'root apt is not gated by the egress firewall, which is clawuser-scoped. Worth its own line in the report.'
}

# ============================================================================
Section '3. Can root mount a FUSE passthrough, and does it pass through'
$mnt = Invoke-WslFile -Tag 'g4-q4-mount' -User 'root' -Body @'
# UNMOUNT ANY PREVIOUS VIEW FIRST. rm -rf cannot remove a live mountpoint, so a
# re-run silently kept the earlier mount and measured it instead of the new one.
# That is what happened here: the previous mount carried default_permissions,
# which correctly enforced the backing mode 0700 through the view and locked the
# agent out, and the phase then voided on a control about a mount it had not
# made. A stale mount is a stale instrument.
fusermount3 -u /var/tmp/g4-fuse/view 2>/dev/null || fusermount -u /var/tmp/g4-fuse/view 2>/dev/null || umount -l /var/tmp/g4-fuse/view 2>/dev/null
sleep 1
echo "PRE_EXISTING_MOUNT=$(grep -c 'g4-fuse/view' /proc/mounts 2>/dev/null | tr -d ' ')"
rm -rf /var/tmp/g4-fuse
mkdir -p /var/tmp/g4-fuse/backing /var/tmp/g4-fuse/view
echo "BACKING-CANARY-Q4" > /var/tmp/g4-fuse/backing/canary.txt
# 0700 ON THE BACKING DIRECTORY, and this is a design decision being tested
# rather than tidiness. The first run made it 0755, uid 1000 could read the
# backing tree by its own path, and that was reported as "the passthrough is not
# a control". That conclusion was about the MODE THE PROBE CHOSE, not about
# FUSE. The real question is whether a passthrough plus a locked backing
# directory denies the second path, so the backing directory is locked and the
# same bypass test is run against it.
chmod 0755 /var/tmp/g4-fuse /var/tmp/g4-fuse/view
chmod 0700 /var/tmp/g4-fuse/backing
chmod 0600 /var/tmp/g4-fuse/backing/canary.txt
stat -c 'BACKING_MODE=%a %U:%G %n' /var/tmp/g4-fuse/backing

# allow_other is what makes the view usable by the agent. It needs
# user_allow_other in /etc/fuse.conf, which is a shipped-config dependency and
# is therefore part of the answer rather than a detail.
grep -q '^user_allow_other' /etc/fuse.conf 2>/dev/null || echo 'user_allow_other' >> /etc/fuse.conf
echo "FUSE_CONF_NOW=$(grep -c user_allow_other /etc/fuse.conf 2>/dev/null | tr -d ' ')"

# The view REMAPS ownership, the backing stays locked to root. That pairing is
# the whole shape of a FUSE-based Guard 4: the agent works in the view, and the
# path underneath it is not a route because it is not readable. default_permissions
# is dropped deliberately, since it would enforce the backing mode 0700 through
# the view and lock the agent out of the thing it is meant to use.
if bindfs --force-user=clawuser --force-group=clawuser --perms=a+rwD -o allow_other /var/tmp/g4-fuse/backing /var/tmp/g4-fuse/view 2>/tmp/g4-bindfs.err; then
  echo "MOUNT_RC=0"
else
  echo "MOUNT_RC=nonzero"
  head -2 /tmp/g4-bindfs.err
fi
sleep 1
echo "MOUNT_LINE=$(grep -F '/var/tmp/g4-fuse/view' /proc/mounts || echo NONE)"
echo "--- does it pass through ---"
cat /var/tmp/g4-fuse/view/canary.txt 2>&1
echo "--- a write through the view reaches the backing store ---"
echo "WRITTEN-THROUGH-VIEW" > /var/tmp/g4-fuse/view/through.txt 2>&1
echo "BACKING_SEES_IT=$(cat /var/tmp/g4-fuse/backing/through.txt 2>/dev/null || echo NO)"
echo "--- CONTROL: an unmounted sibling must NOT show the backing content ---"
mkdir -p /var/tmp/g4-fuse/notmounted
echo "CONTROL_SIBLING=$(cat /var/tmp/g4-fuse/notmounted/canary.txt 2>/dev/null || echo correctly-empty)"
'@
W $mnt.Out
$mounted = $mnt.Out -match 'MOUNT_LINE=.*g4-fuse/view'
$passes = $mnt.Out -match 'BACKING-CANARY-Q4'
$ctl2 = $mnt.Out -match 'CONTROL_SIBLING=correctly-empty'
Register-Control -Id 'Q4.5.CTL' -Name 'the passthrough test discriminates a mounted view from an unmounted directory' `
    -Fired $ctl2 -Evidence 'an unmounted sibling directory showed none of the backing content' | Out-Null
Record 'Q4.5' 'Root can mount a FUSE filesystem inside the distro' `
    $(if ($mounted) { 'PASS' } else { 'FAIL' }) 'read from /proc/mounts, not from the mount command exit code'
Record 'Q4.6' 'The passthrough actually passes through, both directions' `
    $(if ($passes -and ($mnt.Out -match 'BACKING_SEES_IT=WRITTEN-THROUGH-VIEW')) { 'PASS' } else { 'FAIL' }) `
    'read through the view, and a write through the view visible in the backing store'
Record 'Q4.7' 'allow_other had to be enabled in /etc/fuse.conf for the agent to use the view' 'INFO' `
    'a shipped-config dependency for any FUSE-based Guard 4, listed in the bundling section of the report'

# ============================================================================
Section '4. THE ONE THAT DECIDES IT: can uid 1000 reach the BACKING directory'
$b = Invoke-WslFile -Tag 'g4-q4-backing' -User 'clawuser' -Body @'
echo "whoami=$(id -un) uid=$(id -u)"
# NO `cmd | head` FOLLOWED BY $?. In a pipeline $? is head's status, which is 0
# regardless of what cat did, so the first run reported BACKING_READ_RC=0 for a
# read whose success was never actually established. Every check below is an if.
echo "--- SUBJECT: the view, which the agent is meant to use ---"
if cat /var/tmp/g4-fuse/view/canary.txt >/dev/null 2>&1; then echo "VIEW_READ=SUCCEEDED"; else echo "VIEW_READ=refused"; fi
cat /var/tmp/g4-fuse/view/canary.txt 2>/dev/null | head -1
echo
echo "--- THE BYPASS TEST: the backing directory, by its own path ---"
if cat /var/tmp/g4-fuse/backing/canary.txt >/dev/null 2>&1; then echo "BACKING_READ=SUCCEEDED"; else echo "BACKING_READ=refused"; fi
if ls /var/tmp/g4-fuse/backing >/dev/null 2>&1; then echo "BACKING_LIST=SUCCEEDED"; else echo "BACKING_LIST=refused"; fi
# The redirection failure is reported by the SHELL, not by echo, so `echo ... 2>/dev/null`
# does not suppress it. It landed on stderr, interleaved into the middle of the
# VIEW_READ line in the captured output, and turned VIEW_READ=SUCCEEDED into
# "EDED". The matcher then missed it and the phase voided on a control that had
# actually succeeded. Wrapping in a subshell puts the redirect inside the scope
# that 2>/dev/null covers.
echo "BYPASS_WRITE=$( (echo bypass > /var/tmp/g4-fuse/backing/bypass.txt) 2>/dev/null && echo SUCCEEDED || echo refused)"
echo
echo "--- every other route to the same inode ---"
echo "HARDLINK=$(ln /var/tmp/g4-fuse/backing/canary.txt /var/tmp/g4-hardlink 2>/dev/null && echo SUCCEEDED || echo refused)"
echo "PROC_ROUTE=$(ls /proc/*/root/var/tmp/g4-fuse/backing 2>/dev/null | head -1 || echo none)"
echo
echo "--- CONTROL: a path uid 1000 must be refused ---"
if cat /etc/shadow >/dev/null 2>&1; then echo "SHADOW_READ=SUCCEEDED"; else echo "SHADOW_READ=refused"; fi
'@
W $b.Out
$shadowDenied = $b.Out -match 'SHADOW_READ=refused'
Register-Control -Id 'Q4.8.CTL' -Name 'the uid 1000 probe can be refused' `
    -Fired $shadowDenied -Evidence '/etc/shadow denied to uid 1000 in the same run' | Out-Null

$viewReadable     = $b.Out -match 'VIEW_READ=SUCCEEDED'
$backingReachable = $b.Out -match 'BACKING_READ=SUCCEEDED'
$bypassWrite      = $b.Out -match 'BYPASS_WRITE=SUCCEEDED'
# The view must WORK, or a denied backing path proves nothing: a passthrough
# that denies the agent everything is trivially secure and useless, and it would
# score a PASS on the row below.
Register-Control -Id 'Q4.8.CTL2' -Name 'the agent can actually use the view, so a denied backing path is a real result' `
    -Fired $viewReadable `
    -Evidence "uid 1000 read the canary through the view = $viewReadable. Without this, Q4.8 passes for a passthrough nobody can use." | Out-Null
Record 'Q4.8' 'uid 1000 CANNOT reach the backing directory by its own path' `
    $(if (-not $backingReachable) { 'PASS' } else { 'FAIL' }) `
    "backing content readable by uid 1000 = $backingReachable, with the backing directory at 0700 root. The first run made it 0755 and reported the reachability as a property of FUSE; it was a property of the mode this probe chose."
Record 'Q4.9' 'uid 1000 CANNOT write into the backing directory, bypassing the view' `
    $(if (-not $bypassWrite) { 'PASS' } else { 'FAIL' }) `
    "direct write to the backing path = $(if($bypassWrite){'SUCCEEDED, which is the bypass'}else{'refused'})"

# Left mounted deliberately: question 2 tests whether it survives the restart
# cycle, and unmounting it here would make that test measure nothing.
W 'The bindfs mount is LEFT IN PLACE for the question 2 survival test.'

Complete-Phase -ResultsJson 'C:\cfv\g4-q4-results.json' -MarkerPrefix 'G4Q4'
