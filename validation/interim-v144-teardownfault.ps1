<#
  BOX D, TASK 2.7: THE NEGATIVE HALF. MAKE THE TEARDOWN FAIL, ON PURPOSE.

  WHY THIS IS NOT OPTIONAL
  ------------------------
  A success marker that has never been observed to fail is indistinguishable
  from one that CANNOT fail. CLAWFACTORY_TEARDOWN_OK is new in v1.4.2 and has
  never been seen to go the other way on any release. Reading it once on a clean
  box proves the happy path and says nothing about whether the check is wired to
  anything -- which is precisely the defect v1.4.2 fixed, where the caller logged
  "In-distro ClawFactory artifacts removed" unconditionally.

  THE FAULT, AND WHY THIS ONE
  ---------------------------
  One file inside /etc/clawfactory is made IMMUTABLE with `chattr +i`. The
  shipped teardown then runs, as root:

      rm -rf /etc/clawfactory 2>/dev/null

  which cannot remove an immutable file, leaves the directory in place, and has
  its error suppressed -- so the failure is invisible to the caller EXCEPT
  through the read-back this test is here to exercise. The teardown's own
  read-back then finds `[ -d /etc/clawfactory ]` and must emit
  CLAWFACTORY_TEARDOWN_INCOMPLETE with /etc/clawfactory named in its left=[ ]
  list, and the Windows side must log the failure AS a failure and show the
  operator a dialog naming what was left.

  Three properties made this fault the right choice over the alternatives:
    - The shipped teardown does NOT clear it. It runs `chattr -i` on exactly
      three paths, all under /home/clawuser/.openclaw, so an immutable file in
      /etc/clawfactory survives the very operation it is meant to obstruct.
      (A rigged systemd unit would be swept by the drift backstop
      `rm -f /etc/systemd/system/clawfactory-*.service`, which is why that shape
      was rejected: the rig would be erased by the run it exists to interrupt --
      the same mistake that cost PG.3f two installs on boxes B and C.)
    - It is exactly reversible with `chattr -i`, verified from both directions.
    - It touches no shipped byte. Clause 5 is not in play.

  CLAUSE 1: THE SUBJECT IS DISCOVERED. The file to make immutable is chosen by
  LISTING /etc/clawfactory and taking a named entry, and the name chosen is
  printed. Nothing here assumes a filename.

  EVERY INJECTED FAULT CARRIES A CONTROL PROVING THE FAULT LANDED, and this one
  carries two, because "chattr reported success" and "rm is now actually
  refused" are different claims:
    FI.CTL.LANDED  root cannot delete the immutable file, and it is still there
    FI.CTL.RM      root CAN delete a sibling file in the same directory, so the
                   refusal above is the attribute and not a broken rm or a
                   read-only mount
#>
param(
    [ValidateSet('Inject','Cleanup')][string]$Mode = 'Inject',
    [string]$Transcript  = '',
    [string]$ResultsJson = '',
    [string]$LibDir      = 'C:\cfv',
    [string]$MarkerFile  = 'C:\cfv\teardownfault-target.txt'
)

$ErrorActionPreference = 'Continue'
if (-not $Transcript)  { $Transcript  = "C:\cfv\teardownfault-$($Mode.ToLower())-out-probe.txt" }
if (-not $ResultsJson) { $ResultsJson = "C:\cfv\teardownfault-$($Mode.ToLower())-results.json" }

. (Join-Path $LibDir 'interim-v120-wslchan.ps1')
. (Join-Path $LibDir 'interim-v120-phaselib.ps1')

Start-Phase -Name "ClawFactory v1.4.4 box D: teardown fault injection, mode=$Mode" `
    -Transcript $Transcript -Sentinel 'TEARDOWNFAULT_PROBE_COMPLETE'

function Finish($code) { W ''; W "TEARDOWNFAULT_PROBE_COMPLETE rc=$code"; exit $code }
function Val([string]$text, [string]$key) {
    if ($text -match "(?m)^$([regex]::Escape($key))=(.*)$") { return $Matches[1].Trim() }
    return '(not reported)'
}

$chan = Test-WslChannel
Register-Control -Id "FI.CHAN.$Mode" -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'TEARDOWNFAULT'; Finish 2 }

# ==========================================================================
if ($Mode -eq 'Inject') {

    Section '1. Discover the subject. The listing is printed before anything is chosen.'
    $disc = Invoke-WslFile -Tag 'fi-discover' -User 'root' -Body @'
echo "ETC_CF=$( [ -d /etc/clawfactory ] && echo present || echo absent )"
echo "--LISTING--"
ls -1 /etc/clawfactory 2>/dev/null
echo "--END-LISTING--"
echo "CHATTR=$( command -v chattr >/dev/null 2>&1 && echo present || echo absent )"
echo "LSATTR=$( command -v lsattr >/dev/null 2>&1 && echo present || echo absent )"
echo "FSTYPE=$(stat -f -c %T /etc/clawfactory 2>/dev/null)"
'@
    foreach ($ln in @($disc.Out -split "`r?`n" | Where-Object { $_.Trim() })) { W "   DISC> $ln" }

    $listing = @()
    $on = $false
    foreach ($ln in ($disc.Out -split "`r?`n")) {
        $s = $ln.Trim()
        if ($s -eq '--LISTING--') { $on = $true; continue }
        if ($s -eq '--END-LISTING--') { $on = $false; continue }
        if ($on -and $s) { $listing += $s }
    }
    W "DISCOVERED_ETC_CLAWFACTORY count=$($listing.Count) [$($listing -join ' ')]"

    $ready = Require-Precondition -Id 'FI.PRE' -Name '/etc/clawfactory exists, is non-empty, and chattr is available on an ext-family filesystem' `
        -Met (((Val $disc.Out 'ETC_CF') -eq 'present') -and ($listing.Count -ge 1) -and ((Val $disc.Out 'CHATTR') -eq 'present')) `
        -Reason "measured: /etc/clawfactory=$(Val $disc.Out 'ETC_CF') entries=$($listing.Count) chattr=$(Val $disc.Out 'CHATTR') fstype=$(Val $disc.Out 'FSTYPE'). Without a file to make immutable there is no fault to inject, and a run that injects nothing scores a false pass that looks exactly like a working control"
    if (-not $ready) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'TEARDOWNFAULT'; Finish 4 }

    # Deterministic choice, printed. Sorted so the same box picks the same file
    # on a re-run, and named in the evidence so the read-back knows what to expect.
    $target = @($listing | Sort-Object)[0]
    W "CHOSEN_TARGET=/etc/clawfactory/$target"
    [IO.File]::WriteAllText($MarkerFile, "/etc/clawfactory/$target")

    Section '2. Inject, then prove the fault LANDED from two directions'
    $body = @"
T=/etc/clawfactory/$target
echo "TARGET=`$T"
chattr +i "`$T" 2>&1
echo "CHATTR_RC=`$?"
echo "LSATTR=`$(lsattr "`$T" 2>&1 | head -1)"
echo '--- SUBJECT: root deleting the immutable file MUST fail ---'
rm -f "`$T" 2>&1 | head -2
echo "RM_SUBJECT_RC=`$?"
echo "TARGET_STILL_THERE=`$( [ -e "`$T" ] && echo yes || echo no )"
echo '--- CONTROL: root deleting a sibling in the SAME directory MUST succeed ---'
C=/etc/clawfactory/cf-fault-control-b7f31c
: > "`$C"
echo "CONTROL_CREATED=`$( [ -e "`$C" ] && echo yes || echo no )"
rm -f "`$C" 2>&1 | head -2
echo "CONTROL_GONE=`$( [ -e "`$C" ] && echo no || echo yes )"
echo '--- and the directory itself must now refuse to go ---'
rm -rf /etc/clawfactory 2>/dev/null
echo "DIR_STILL_THERE=`$( [ -d /etc/clawfactory ] && echo yes || echo no )"
"@
    $inj = Invoke-WslFile -Tag 'fi-inject' -User 'root' -Body $body
    foreach ($ln in @($inj.Out -split "`r?`n" | Where-Object { $_.Trim() })) { W "   INJ> $ln" }
    $o = $inj.Out

    $landed = ((Val $o 'TARGET_STILL_THERE') -eq 'yes') -and ((Val $o 'DIR_STILL_THERE') -eq 'yes')
    Register-Control -Id 'FI.CTL.LANDED' -Name 'THE FAULT LANDED: root cannot delete the file, and rm -rf leaves the directory' `
        -Fired $landed `
        -Evidence "target=/etc/clawfactory/$target lsattr='$(Val $o 'LSATTR')' targetStillThere=$(Val $o 'TARGET_STILL_THERE') dirStillThere=$(Val $o 'DIR_STILL_THERE'). A fault injection that does not inject scores a false pass and looks exactly like a working control." | Out-Null

    $rmWorks = ((Val $o 'CONTROL_CREATED') -eq 'yes') -and ((Val $o 'CONTROL_GONE') -eq 'yes')
    Register-Control -Id 'FI.CTL.RM' -Name 'CONTROL: root CAN delete a sibling file in the same directory' `
        -Fired $rmWorks `
        -Evidence "control file created=$(Val $o 'CONTROL_CREATED') deleted=$(Val $o 'CONTROL_GONE'). Without this, the refusal above could be a broken rm, a read-only mount or a missing directory rather than the attribute -- three different findings that look identical." | Out-Null

    Record 'FI.1' 'the box is now rigged so the shipped teardown CANNOT complete' `
        $(if ($landed -and $rmWorks) { 'PASS' } else { 'FAIL' }) `
        "immutable: /etc/clawfactory/$target. The shipped teardown clears the immutable bit on exactly three paths, all under /home/clawuser/.openclaw, so this one survives the operation it obstructs. Expected consequence: READBACK left=[ /etc/clawfactory ] and CLAWFACTORY_TEARDOWN_INCOMPLETE."
    Record 'FI.2' 'the fault is recorded where the read-back pass can find it' `
        $(if (Test-Path -LiteralPath $MarkerFile) { 'PASS' } else { 'FAIL' }) `
        "wrote $MarkerFile = '/etc/clawfactory/$target'. The verification pass asserts on THIS name rather than on a remembered one."

    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'TEARDOWNFAULT'
    Finish 0
}

# ==========================================================================
Section '1. Cleanup: remove the injected fault and prove BOTH that it is gone and that removal worked'
$target = if (Test-Path -LiteralPath $MarkerFile) { (Get-Content -LiteralPath $MarkerFile -Raw).Trim() } else { '' }
W "TARGET_FROM_MARKER=$target"
$known = Require-Precondition -Id 'FI.C.PRE' -Name 'the injected target is known from the marker written at injection time' `
    -Met ([bool]$target) `
    -Reason 'without the recorded name this pass would be guessing which file to clear, and clearing the wrong one would leave the box rigged'
if (-not $known) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'TEARDOWNFAULT'; Finish 4 }

$body = @"
T='$target'
echo "TARGET=`$T"
echo "EXISTS_BEFORE=`$( [ -e "`$T" ] && echo yes || echo no )"
chattr -i "`$T" 2>&1
echo "CHATTR_RC=`$?"
echo "LSATTR_AFTER=`$(lsattr "`$T" 2>&1 | head -1)"
rm -f "`$T" 2>&1 | head -2
echo "EXISTS_AFTER=`$( [ -e "`$T" ] && echo yes || echo no )"
rm -rf /etc/clawfactory 2>/dev/null
echo "DIR_AFTER=`$( [ -d /etc/clawfactory ] && echo present || echo absent )"
echo "RESIDUAL_LISTING=`$(ls -1 /etc/clawfactory 2>/dev/null | tr '\n' ' ')"
"@
$c = Invoke-WslFile -Tag 'fi-cleanup' -User 'root' -Body $body
foreach ($ln in @($c.Out -split "`r?`n" | Where-Object { $_.Trim() })) { W "   CLN> $ln" }
$o = $c.Out

Record 'FI.C.1' 'the immutable attribute is cleared and the file is gone' `
    $(if ((Val $o 'EXISTS_AFTER') -eq 'no') { 'PASS' } else { 'FAIL' }) `
    "existedBefore=$(Val $o 'EXISTS_BEFORE') lsattrAfterClear='$(Val $o 'LSATTR_AFTER')' existsAfter=$(Val $o 'EXISTS_AFTER'). Both halves matter: the attribute being cleared and the file actually going are different claims."
Record 'FI.C.2' 'the fault no longer obstructs the removal it was injected to obstruct' `
    $(if ((Val $o 'DIR_AFTER') -eq 'absent') { 'PASS' } else { 'FAIL' }) `
    "/etc/clawfactory after clearing and re-running the same rm -rf = $(Val $o 'DIR_AFTER'); residual entries: '$(Val $o 'RESIDUAL_LISTING')'. A probe that left this fault behind would leave the box in a state no uninstall could clean."

Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'TEARDOWNFAULT'
Finish 0
