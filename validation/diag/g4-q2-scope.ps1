<#
  QUESTION 2. Mark scope, and survival of the teardown that killed the gateway.

  Two arms, selected by -PostReboot, because the second half of the question
  cannot be answered without a human logging in over RDP first.

  WHY SURVIVAL IS THE HALF THAT MATTERS
  --------------------------------------
  This product has already fought this exact battle once. WSL tears down the
  distro init chain whenever the last wsl.exe session exits, which took down
  user@1000, the gateway and everything under it, and needed BOTH vmIdleTimeout=-1
  and the keepalive scheduled task before it stopped. A Guard 4 that dies on that
  same trigger is not a control: it is a control-shaped thing that is absent
  during exactly the window an agent keeps running in.

  So the test runs with the SHIPPED keepalive in place, because that is the
  configuration a customer has, and it measures survival FUNCTIONALLY rather than
  by asking systemd whether it is happy. A unit can be active with no mark. The
  holder therefore delays every allow by a fixed interval, and the survival test
  is an ordinary open from uid 1000 that must still be observed to block. If it
  returns instantly, the mark is gone no matter what systemctl says.

  L30.1 applies to the restart itself: the phase proves the distro actually went
  down and came back, because a restart that did not happen is a survival test
  that tested nothing and it looks exactly like a pass.
#>
param(
    [string]$Transcript = 'C:\cfv\g4-q2-out-probe.txt',
    [switch]$PostReboot
)

$ErrorActionPreference = 'Continue'
. C:\cfv\g4-common.ps1

$tag = if ($PostReboot) { 'POSTREBOOT' } else { 'PRE' }
Start-Phase -Name "Guard 4 Q2: mark scope and restart survival, pass=$tag" `
    -Transcript $Transcript -Sentinel 'G4_Q2_COMPLETE'

$HOLD_DELAY = 2.0

$chan = Test-WslChannel
Register-Control -Id "Q2.CHAN.$tag" -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { Complete-Phase -ResultsJson "C:\cfv\g4-q2-results-$tag.json" -MarkerPrefix "G4Q2_$tag" }

# The functional survival test, used identically in both arms so the two are
# actually comparable.
function Test-MarkLive {
    param([string]$Label)
    $r = Invoke-WslFile -Tag "g4-q2-live-$Label" -User 'root' -Body @"
echo "UNIT_STATE=`$(systemctl is-active clawfactory-g4-hold.service 2>&1)"
echo "UNIT_ENABLED=`$(systemctl is-enabled clawfactory-g4-hold.service 2>&1)"
echo "HOLDER_PID_FILE=`$(cat /var/tmp/g4/hold.pid 2>/dev/null || echo NONE)"
echo "HOLDER_ALIVE=`$(pgrep -f 'g4-probe.py hold' | head -1 || echo NONE)"
echo '--- FUNCTIONAL: time an open from uid 1000 inside the marked directory ---'
# Integer nanosecond arithmetic in bash, deliberately, rather than bc. A timing
# probe that depends on a package being installed reports "no timing" as an
# empty string, and an empty string parses to zero, which reads as "the open was
# instant" -- the exact false negative this test exists to avoid.
su -s /bin/bash -c 'S=`$(date +%s%N); : > /var/tmp/g4/marked/allow.txt 2>/dev/null; E=`$(date +%s%N); echo "OPEN_ELAPSED_MS=`$(( (E - S) / 1000000 ))"' clawuser 2>&1
echo '--- CONTROL: the same timing on an UNMARKED file, which must be fast ---'
su -s /bin/bash -c 'S=`$(date +%s%N); : > /var/tmp/g4/unmarked/free.txt 2>/dev/null; E=`$(date +%s%N); echo "CONTROL_ELAPSED_MS=`$(( (E - S) / 1000000 ))"' clawuser 2>&1
echo '--- the FUSE candidate, same question ---'
echo "FUSE_MOUNT=`$(grep -F '/var/tmp/g4-fuse/view' /proc/mounts || echo NONE)"
echo "FUSE_READS=`$(cat /var/tmp/g4-fuse/view/canary.txt 2>/dev/null || echo UNREADABLE)"
"@
    W $r.Out
    # -1 means NOT MEASURED and must never be confused with 0, which would mean
    # an instant open and therefore a dead mark.
    $open = if ($r.Out -match 'OPEN_ELAPSED_MS=(\d+)') { [double]$Matches[1] / 1000.0 } else { -1 }
    $ctl  = if ($r.Out -match 'CONTROL_ELAPSED_MS=(\d+)') { [double]$Matches[1] / 1000.0 } else { -1 }
    return @{
        UnitActive = $r.Out -match 'UNIT_STATE=active'
        Pid        = $(if ($r.Out -match 'HOLDER_ALIVE=(\d+)') { $Matches[1] } else { 'NONE' })
        OpenSecs   = $open
        CtlSecs    = $ctl
        MarkLive   = ($open -ge ($HOLD_DELAY * 0.7)) -and ($ctl -ge 0) -and ($ctl -lt ($HOLD_DELAY * 0.5))
        FuseMounted = $r.Out -match 'FUSE_MOUNT=.*g4-fuse/view'
        FuseReads  = $r.Out -match 'BACKING-CANARY-Q4'
        Raw        = $r.Out
    }
}

if (-not $PostReboot) {
    # ========================================================================
    Section '1. Which mark SCOPES this kernel accepts, on both filesystems'
    $py = Install-G4Py
    Register-Control -Id 'Q2.PY' -Name 'python3 reaches libc and runs THIS payload' `
        -Fired $py.Ok -Evidence $py.Detail | Out-Null
    if (-not $py.Ok) { Complete-Phase -ResultsJson "C:\cfv\g4-q2-results-$tag.json" -MarkerPrefix "G4Q2_$tag" }

    $slug = ''
    try {
        New-Item -ItemType Directory -Path 'C:\cfv\g4-scope' -Force | Out-Null
        . 'C:\Program Files\ClawFactory\resources\clawfactory-grants.ps1'
        $g = Grant-Workspace -Path 'C:\cfv\g4-scope' -Mode rw
        $slug = $g.id
        W "granted id=$slug"
    } catch { W "Grant-Workspace threw: $($_.Exception.Message)" }

    $targets = @(@{ n = 'ext4 (/var/tmp)'; p = '/var/tmp/g4/marked' })
    if ($slug) { $targets += @{ n = "drvfs (/workspaces/$slug)"; p = "/workspaces/$slug" } }

    foreach ($t in $targets) {
        $s = Invoke-WslFile -Tag ("g4-q2-scope-" + ($t.n -replace '[^a-z0-9]', '')) -User 'root' -Body @"
mkdir -p '$($t.p)'
python3 /var/tmp/g4-probe.py scope '$($t.p)' 2>&1
"@
        W $s.Out
        $js = @(Get-G4Json -Text $s.Out) | Where-Object { $_.cmd -eq 'scope' } | Select-Object -First 1
        if (-not $js) {
            Record "Q2.1.$($t.n)" "Mark scopes accepted on $($t.n)" 'VOID' 'no G4JSON line from the scope probe'
        } else {
            $sc = $js.scopes
            foreach ($name in @('directory', 'directory_with_children', 'mount', 'filesystem')) {
                $v = $sc.$name
                W ("  scope {0,-24} ok={1} errno={2}" -f $name, $v.ok, $v.errno)
            }
            Record "Q2.1.$($t.n)" "Mount-scoped mark accepted on $($t.n)" `
                $(if ($sc.mount.ok) { 'PASS' } else { 'FAIL' }) "errno=$($sc.mount.errno)"
            Record "Q2.2.$($t.n)" "Filesystem-scoped mark accepted on $($t.n)" `
                $(if ($sc.filesystem.ok) { 'PASS' } else { 'FAIL' }) `
                "errno=$($sc.filesystem.errno). Question 6 decides whether this scope is REQUIRED: a per-mount mark does not follow a bind mount into a private namespace."
        }
    }
    if ($slug) { try { Revoke-Workspace -Id $slug | Out-Null } catch { } }

    # ========================================================================
    Section '2. Install a root systemd unit that HOLDS a permission mark'
    $unit = Invoke-WslFile -Tag 'g4-q2-unit' -User 'root' -Body @"
mkdir -p /var/tmp/g4/marked /var/tmp/g4/unmarked
: > /var/tmp/g4/marked/allow.txt
: > /var/tmp/g4/unmarked/free.txt
chmod -R 0777 /var/tmp/g4
cat > /etc/systemd/system/clawfactory-g4-hold.service <<'UEOF'
[Unit]
Description=Guard 4 ground-truth probe: holds a fanotify permission mark
After=local-fs.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /var/tmp/g4-probe.py hold /var/tmp/g4/marked $HOLD_DELAY 21600 /var/tmp/g4/hold.pid
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UEOF
systemctl daemon-reload
systemctl enable --now clawfactory-g4-hold.service 2>&1
sleep 3
systemctl is-active clawfactory-g4-hold.service
echo "UNIT_ENABLED=`$(systemctl is-enabled clawfactory-g4-hold.service 2>&1)"
"@
    W $unit.Out

    $before = Test-MarkLive -Label 'before'
    Register-Control -Id 'Q2.3.CTL' -Name 'the mark is demonstrably LIVE before any restart is attempted' `
        -Fired $before.MarkLive `
        -Evidence "marked open took $($before.OpenSecs)s against a ${HOLD_DELAY}s hold; unmarked control took $($before.CtlSecs)s. Without this, a post-restart failure could mean the mark was never up." | Out-Null
    Record 'Q2.3' 'A root systemd unit can hold a permission mark at all' `
        $(if ($before.MarkLive) { 'PASS' } else { 'FAIL' }) "unit active=$($before.UnitActive) pid=$($before.Pid)"

    # ========================================================================
    Section '3. The WSL restart cycle, the trigger that killed the gateway'
    $pidBefore = $before.Pid
    W "holder pid before the restart cycle: $pidBefore"
    W 'Running wsl.exe --shutdown from the Windows side...'
    & wsl.exe --shutdown 2>&1 | ForEach-Object { W "  $_" }
    Start-Sleep -Seconds 8

    # L30.1 applied to the restart: prove the distro actually went down. A
    # shutdown that did not happen is a survival test that tested nothing.
    $downProof = (& wsl.exe --list --running --quiet 2>&1 | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ }) -join ','
    W "running distros immediately after --shutdown: '$downProof'"
    Register-Control -Id 'Q2.4.CTL' -Name 'the restart cycle ACTUALLY tore the distro down' `
        -Fired ([string]::IsNullOrWhiteSpace($downProof)) `
        -Evidence "wsl --list --running reported '$downProof' straight after the shutdown; empty is the proof the teardown happened" | Out-Null

    # Re-trigger the shipped keepalive, because --shutdown drops it. This is the
    # customer configuration, not a workaround for the test.
    $ka = & schtasks.exe /Run /TN 'ClawFactory WSL Host' 2>&1
    W "keepalive re-trigger: $ka"
    Start-Sleep -Seconds 20

    $after = Test-MarkLive -Label 'after-cycle'
    Record 'Q2.4' 'The permission mark SURVIVES the WSL restart cycle' `
        $(if ($after.MarkLive) { 'PASS' } else { 'FAIL' }) `
        "marked open $($after.OpenSecs)s / control $($after.CtlSecs)s; unit active=$($after.UnitActive); pid before=$pidBefore after=$($after.Pid) (a changed pid means it was re-established by systemd, which is an acceptable answer and a different one from surviving)"
    Record 'Q2.5' 'The FUSE mount SURVIVES the WSL restart cycle' `
        $(if ($after.FuseMounted -and $after.FuseReads) { 'PASS' } else { 'FAIL' }) `
        "mount present=$($after.FuseMounted) content readable=$($after.FuseReads). A candidate that dies on the same trigger that killed the gateway is not a control."
} else {
    # ========================================================================
    Section '4. POST-REBOOT arm: the same two candidates after a full reboot'
    # Nothing is re-established here on purpose. Whatever is running is what came
    # back on its own, which is the entire question.
    $post = Test-MarkLive -Label 'post-reboot'
    Register-Control -Id 'Q2.6.CTL' -Name 'the timing probe still discriminates after the reboot' `
        -Fired (($post.CtlSecs -ge 0) -and ($post.CtlSecs -lt ($HOLD_DELAY * 0.5))) `
        -Evidence "the unmarked control opened in $($post.CtlSecs)s, so a slow marked open is the mark and not a slow box" | Out-Null
    Record 'Q2.6' 'The permission mark SURVIVES a full Windows reboot' `
        $(if ($post.MarkLive) { 'PASS' } else { 'FAIL' }) `
        "marked open $($post.OpenSecs)s / control $($post.CtlSecs)s; unit active=$($post.UnitActive) pid=$($post.Pid)"
    Record 'Q2.7' 'The FUSE mount SURVIVES a full Windows reboot' `
        $(if ($post.FuseMounted -and $post.FuseReads) { 'PASS' } else { 'FAIL' }) `
        "mount present=$($post.FuseMounted) content readable=$($post.FuseReads). A bindfs mount established by hand has no unit behind it, so a FAIL here sizes the Guard 4 build rather than condemning the candidate."
}

Complete-Phase -ResultsJson "C:\cfv\g4-q2-results-$tag.json" -MarkerPrefix "G4Q2_$tag"
