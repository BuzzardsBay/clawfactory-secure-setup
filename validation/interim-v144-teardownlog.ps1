<#
  BOX D: THE UNINSTALLER'S OWN ACCOUNT OF THE KEEP-LINUX TEARDOWN.

  WHAT IS BEING READ, AND WHY IT IS THE PRODUCT AND NOT THE PROBE
  ---------------------------------------------------------------
  v1.4.2 card #286 added a terminal marker and a read-back to the in-distro
  teardown, because the caller used to assign the whole invocation to $null and
  then log "In-distro ClawFactory artifacts removed" unconditionally -- so a
  teardown that executed half of itself reported success and reached a release.
  resources/uninstall.ps1 now emits, from inside the distro:

      [uninstall] READBACK units=N sbin=N enabled=N left=[ ... ]
      CLAWFACTORY_TEARDOWN_OK          (all four clear)
      CLAWFACTORY_TEARDOWN_INCOMPLETE  (anything left)

  and the Windows side requires the marker rather than assuming it:

      $teardownOk = ($rc -eq 0) -and ($teardownOut -contains 'CLAWFACTORY_TEARDOWN_OK')

  THIS PROBE MEASURES BOTH DIRECTIONS OF THAT MARKER.
  A success marker that has never been observed to FAIL is indistinguishable
  from one that CANNOT fail. So -Expect selects which state this run requires,
  and the identical instrument is used for the clean teardown and for the
  fault-injected one. If the same reader can produce OK on one run and
  INCOMPLETE on the next, the marker discriminates; if it can only ever produce
  one of them, that is the finding.

  CLAUSE 2: CLASSIFY, DO NOT TEST FOR ABSENCE.
  The states are NAMED and MUTUALLY EXCLUSIVE and the state is printed:

      NO_LOG              the log file was not found at all
      NO_MARKER           the log exists but carries neither terminal marker
      TEARDOWN_OK         CLAWFACTORY_TEARDOWN_OK present, INCOMPLETE absent
      TEARDOWN_INCOMPLETE CLAWFACTORY_TEARDOWN_INCOMPLETE present
      BOTH_MARKERS        both present -- two teardowns in one log, ambiguous

  Testing for the absence of "INCOMPLETE" would score NO_LOG as a clean pass.

  CLAUSE 1: THE LOG PATH IS DISCOVERED, NOT ASSUMED.
  uninstall.ps1 writes to $env:TEMP, resolved in ITS process. The uninstaller
  runs elevated; this probe runs in the operator's session; and anything
  dispatched through `az vm run-command` runs as SYSTEM with a THIRD %TEMP%.
  That exact mismatch produced a false "Studio is not installed" claim on box C.
  So every candidate profile is searched, every hit is listed with its
  timestamp, and the newest is used -- and which one was used is printed.
#>
param(
    [ValidateSet('OK','INCOMPLETE')][string]$Expect = 'OK',
    [string]$Transcript  = '',
    [string]$ResultsJson = '',
    [string]$LibDir      = 'C:\cfv',
    # Dry-run seam: point at a directory holding a rigged ClawFactory-Uninstall.log
    # so the classifier can be exercised against a known answer before any box runs.
    [string]$SearchRoot  = ''
)

$ErrorActionPreference = 'Continue'
$tag = $Expect.ToLower()
if (-not $Transcript)  { $Transcript  = "C:\cfv\teardownlog-$tag-out-probe.txt" }
if (-not $ResultsJson) { $ResultsJson = "C:\cfv\teardownlog-$tag-results.json" }

. (Join-Path $LibDir 'interim-v120-phaselib.ps1')

Start-Phase -Name "ClawFactory v1.4.4 box D: keep-Linux teardown log, expecting $Expect" `
    -Transcript $Transcript -Sentinel 'TEARDOWNLOG_PROBE_COMPLETE'

function Finish($code) { W ''; W "TEARDOWNLOG_PROBE_COMPLETE rc=$code"; exit $code }

# ---- 1. DISCOVER the log ---------------------------------------------------
Section '1. Discover the uninstall log rather than assuming which %TEMP% wrote it'

$candidates = @()
if ($SearchRoot) {
    $candidates += $SearchRoot
} else {
    $candidates += $env:TEMP
    $candidates += 'C:\Windows\Temp'
    foreach ($p in (Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue)) {
        $candidates += (Join-Path $p.FullName 'AppData\Local\Temp')
    }
    $candidates += 'C:\Windows\System32\config\systemprofile\AppData\Local\Temp'
}
$candidates = @($candidates | Where-Object { $_ } | Sort-Object -Unique)

$found = @()
foreach ($c in $candidates) {
    $f = Join-Path $c 'ClawFactory-Uninstall.log'
    if (Test-Path -LiteralPath $f) {
        $i = Get-Item -LiteralPath $f
        $found += $i
        W ("   FOUND {0}  {1} bytes  lastWrite={2}" -f $i.FullName, $i.Length, $i.LastWriteTime.ToString('s'))
    } else {
        W ("   absent {0}" -f $f)
    }
}
W "CANDIDATES_SEARCHED=$($candidates.Count)  LOGS_FOUND=$($found.Count)"

$haveLog = Require-Precondition -Id 'TL.PRE.LOG' -Name 'an uninstall log was found on this box' `
    -Met ($found.Count -ge 1) `
    -Reason "ClawFactory-Uninstall.log was not present in any of the $($candidates.Count) profiles searched, so there is no account of the teardown to read. That is a missing subject, not a product verdict"
if (-not $haveLog) {
    W 'STATE=NO_LOG'
    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'TEARDOWNLOG'
    Finish 4
}

$log = @($found | Sort-Object LastWriteTime -Descending)[0]
W "USING_LOG=$($log.FullName)  bytes=$($log.Length)  lastWrite=$($log.LastWriteTime.ToString('s'))"
$text  = Get-Content -LiteralPath $log.FullName -Raw
$lines = @($text -split "`r?`n")

# ---- 2. Prove the log is searchable before searching it for anything -------
Section '2. The log is proven SEARCHABLE before any absence in it is believed'
Assert-Searchable -Id 'TL.CTL.SEARCH' -Name 'the uninstall log' `
    -PositiveMarkerFound ($text -match 'ClawFactory uninstall starting') `
    -MarkerDescription "the uninstaller's own opening line, '==== ClawFactory uninstall starting'" | Out-Null

foreach ($ln in @($lines | Where-Object { $_ -match 'DoRemoveAll|READBACK|CLAWFACTORY_TEARDOWN|in-distro|teardown|Step 6' })) { W "   ULOG> $ln" }

# ---- 3. The BRANCH is a precondition, not a row ----------------------------
Section '3. The branch actually taken. Everything below is about the keep-Linux branch only'
$keptBranch = [bool]($text -match 'Resolved DoRemoveAll = False')
$tookAll    = [bool]($text -match 'Resolved DoRemoveAll = True')
$branchState = if ($keptBranch -and -not $tookAll) { 'KEEP_LINUX' }
               elseif ($tookAll -and -not $keptBranch) { 'REMOVE_ALL' }
               elseif ($keptBranch -and $tookAll) { 'BOTH_IN_ONE_LOG' }
               else { 'NOT_STATED' }
W "BRANCH_STATE=$branchState"
$branchOk = Require-Precondition -Id 'TL.PRE.BRANCH' -Name 'the uninstaller took the KEEP-LINUX branch' `
    -Met ($branchState -eq 'KEEP_LINUX') `
    -Reason "the log records BRANCH_STATE=$branchState. On RemoveAll the distro is unregistered and every line of the v1.4.2 change set is dead code, so a teardown marker read from that branch measures nothing this box exists to measure. BOTH_IN_ONE_LOG means the log carries more than one uninstall and no single verdict can be attributed"
if (-not $branchOk) {
    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'TEARDOWNLOG'
    Finish 4
}

# ---- 4. CLASSIFY --------------------------------------------------------
Section '4. The terminal marker, classified into one of five named states'
# ANCHORED AT END OF LINE, NOT AT START. uninstall.ps1 re-logs every line the
# distro emitted through Write-Log, so the marker arrives as
#     [2026-08-28T20:11:04] [INFO]   [in-distro] CLAWFACTORY_TEARDOWN_OK
# A start-anchored pattern matches none of that and would report NO_MARKER on a
# perfectly clean teardown. Caught by a dry-run against a rig carrying the real
# line shape rather than a simplified one -- which is the box C lesson applied.
# _OK is not a substring of _INCOMPLETE, so the two tests cannot collide.
$hasOk   = [bool]($text -match '(?m)CLAWFACTORY_TEARDOWN_OK\s*$')
$hasBad  = [bool]($text -match 'CLAWFACTORY_TEARDOWN_INCOMPLETE')
$state = if ($hasOk -and $hasBad) { 'BOTH_MARKERS' }
         elseif ($hasOk)  { 'TEARDOWN_OK' }
         elseif ($hasBad) { 'TEARDOWN_INCOMPLETE' }
         else { 'NO_MARKER' }
W "STATE=$state   (NO_LOG | NO_MARKER | TEARDOWN_OK | TEARDOWN_INCOMPLETE | BOTH_MARKERS)"

$readbackLine = @($lines | Where-Object { $_ -match 'READBACK units=' }) | Select-Object -Last 1
if (-not $readbackLine) { $readbackLine = '' }
W "READBACK_LINE=$($readbackLine.Trim())"

$rbUnits = $null; $rbSbin = $null; $rbEnabled = $null; $rbLeft = $null
if ($readbackLine -match 'READBACK units=(\d+) sbin=(\d+) enabled=(\d+) left=\[(.*)\]') {
    $rbUnits = [int]$Matches[1]; $rbSbin = [int]$Matches[2]; $rbEnabled = [int]$Matches[3]
    $rbLeft  = $Matches[4].Trim()
}
W "READBACK_PARSED units=$rbUnits sbin=$rbSbin enabled=$rbEnabled left='[$rbLeft]'"

$expectedState = if ($Expect -eq 'OK') { 'TEARDOWN_OK' } else { 'TEARDOWN_INCOMPLETE' }

Record 'TL.1' "the teardown reports state $expectedState, which is what this run injected for" `
    $(if ($state -eq $expectedState) { 'PASS' } else { 'FAIL' }) `
    "measured STATE=$state, required=$expectedState. The state set is named and exhaustive, so NO_MARKER (the teardown never reached its own read-back) cannot be scored as a clean pass by the absence of the failure string. Log: $($log.FullName)"

Record 'TL.2' 'the teardown printed a parseable READBACK line naming what it left' `
    $(if ($null -ne $rbUnits) { 'PASS' } else { 'FAIL' }) `
    "READBACK line: '$($readbackLine.Trim())'. Card #286's whole point is that the teardown STATES what it left rather than leaving it to be inferred; an unparseable or absent line means that statement was not made."

if ($Expect -eq 'OK') {
    $clean = ($rbUnits -eq 0) -and ($rbSbin -eq 0) -and ($rbEnabled -eq 0) -and ($rbLeft -eq '')
    Record 'TL.3' 'the READBACK reports units=0 sbin=0 enabled=0 left=[ ]' `
        $(if ($clean) { 'PASS' } else { 'FAIL' }) `
        "units=$rbUnits sbin=$rbSbin enabled=$rbEnabled left='[$rbLeft]'. These four are the uninstaller's OWN measurement taken inside the distro; interim-v144-uninstate.ps1 -Mode After measures the same subjects independently, and the two are compared rather than one trusted."
    Record 'TL.4' 'the Windows side logged the success sentence only because the marker was present' `
        $(if ($text -match 'verified by read-back inside the distro') { 'PASS' } else { 'FAIL' }) `
        "the v1.4.2 wording is 'In-distro ClawFactory artifacts removed, verified by read-back inside the distro; Ubuntu distro left registered.' The pre-v1.4.2 wording made the same claim unconditionally, which is the defect this row exists to detect."
} else {
    $namedSomething = ($rbLeft -ne '') -or ($rbUnits -gt 0) -or ($rbSbin -gt 0) -or ($rbEnabled -gt 0)
    Record 'TL.3' 'the READBACK NAMES what was left behind rather than only failing' `
        $(if ($namedSomething) { 'PASS' } else { 'FAIL' }) `
        "units=$rbUnits sbin=$rbSbin enabled=$rbEnabled left='[$rbLeft]'. A failure marker that names nothing tells the user their machine is dirty without telling them where."
    Record 'TL.4' 'the Windows side logged the failure AS a failure, and told the user how to finish' `
        $(if (($text -match 'In-distro teardown did NOT complete') -and ($text -match 'wsl -d Ubuntu -u root')) { 'PASS' } else { 'FAIL' }) `
        "requires both the ERROR line 'In-distro teardown did NOT complete. ClawFactory files remain inside the Ubuntu distro.' and the recovery instruction naming 'wsl -d Ubuntu -u root'. An uninstall that aborts leaves the user unable to remove the product, so finishing the Windows side AND reporting honestly is the specified behaviour."
    Record 'TL.5' 'the failure path echoed the read-back into the log for the user to act on' `
        $(if ($text -match 'Read-back from inside the distro:') { 'PASS' } else { 'FAIL' }) `
        "the dialog's 'What is left:' text is built from this same string, so its presence in the log is the machine-readable half of the user-facing claim. The dialog itself is observed by the operator."
}

Record 'TL.6' 'the in-distro teardown exit code, reported as a fact' 'INFO' `
    "$((@($lines | Where-Object { $_ -match 'In-distro teardown exit code' }) | Select-Object -Last 1))"

Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'TEARDOWNLOG'
Finish 0
