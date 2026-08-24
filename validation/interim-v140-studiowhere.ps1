<#
  Where is Studio, and did it install at all?

  stagecards' asar check returned ASAR_FOUND=0 with its negative control
  behaving correctly, so the glob discriminates and the file genuinely is not at
  %LOCALAPPDATA%\Programs\ClawFactory Studio\resources\app.asar for any profile
  visible from the distro.

  Two very different explanations and they must not be conflated:
    * Studio installed somewhere else, and the path in uninstall.ps1 step 4.5 is
      not where the packaged NSIS installer actually puts it. A documentation or
      harness fault.
    * Studio did not install. A PRODUCT fault, and a serious one, because the
      combined installer's whole point is that the customer gets Studio without
      a second download.

  This asks from the WINDOWS side rather than through the distro, because the
  /mnt/c view depends on automount and on which profiles are visible, and a
  question about whether a Windows program exists should be asked of Windows.
#>
param([string]$Transcript = 'C:\cfv\studiowhere-out-probe.txt')

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'Diagnostic: where is ClawFactory Studio on this box' `
    -Transcript $Transcript -Sentinel 'STUDIOWHERE_PROBE_COMPLETE'

Section '1. Every app.asar anywhere under the user profiles, by search rather than by assumption'
$found = @(Get-ChildItem 'C:\Users' -Recurse -Filter 'app.asar' -ErrorAction SilentlyContinue -Force |
           Select-Object -First 20)
foreach ($f in $found) {
    $h = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower()
    W "ASAR $($f.FullName) $($f.Length) B sha256=$h"
}
W "ASAR_COUNT=$($found.Count)"
# CONTROL: the search mechanism must be able to find something it is pointed at,
# or 'found nothing' is indistinguishable from 'cannot look'.
$ctlProbe = @(Get-ChildItem 'C:\Users' -Recurse -Filter 'NTUSER.DAT' -ErrorAction SilentlyContinue -Force | Select-Object -First 1)
Record 'SW.0' 'CONTROL: the recursive profile search can find a file that certainly exists' `
    $(if ($ctlProbe.Count -gt 0) { 'PASS' } else { 'VOID' }) `
    "control hits=$($ctlProbe.Count) (NTUSER.DAT); without this, ASAR_COUNT=0 means nothing"

Section '2. Studio program directories and the uninstall registration'
foreach ($p in @(
    "$env:LOCALAPPDATA\Programs",
    'C:\Program Files\ClawFactory Studio',
    'C:\Program Files (x86)\ClawFactory Studio'
)) {
    if (Test-Path $p) { W "DIR $p :: " + ((Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object Name) -join ', ') }
    else { W "DIR $p :: ABSENT" }
}
W '--- every user profile Programs directory ---'
foreach ($u in (Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue)) {
    $pp = Join-Path $u.FullName 'AppData\Local\Programs'
    if (Test-Path $pp) { W "PROFILE $($u.Name) :: " + ((Get-ChildItem $pp -ErrorAction SilentlyContinue | ForEach-Object Name) -join ', ') }
}
W '--- uninstall registrations mentioning Studio ---'
foreach ($k in @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)) {
    Get-ItemProperty $k -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Studio|ClawFactory' } |
        ForEach-Object { W "UNINST $($_.DisplayName) | $($_.DisplayVersion) | $($_.InstallLocation) | $($_.UninstallString)" }
}
$studioDirs = @(Get-ChildItem 'C:\Users' -Recurse -Directory -Filter '*Studio*' -ErrorAction SilentlyContinue -Force | Select-Object -First 10)
foreach ($d in $studioDirs) { W "STUDIODIR $($d.FullName)" }
Record 'SW.1' 'A Studio program directory exists somewhere on this box' `
    $(if ($studioDirs.Count -gt 0 -or $found.Count -gt 0) { 'PASS' } else { 'FAIL' }) `
    "studioDirs=$($studioDirs.Count) asarFiles=$($found.Count)"

Section '3. What the installer log says it did with the Studio component'
$logs = @(Get-ChildItem 'C:\ProgramData\ClawFactory' -Recurse -Filter '*.log' -ErrorAction SilentlyContinue) +
        @(Get-ChildItem $env:TEMP -Filter 'Setup Log*.txt' -ErrorAction SilentlyContinue)
W "LOGS_FOUND=$($logs.Count)"
foreach ($l in $logs) {
    W "--- $($l.FullName) ($($l.Length) B) ---"
    $hits = @(Select-String -Path $l.FullName -Pattern 'Studio' -ErrorAction SilentlyContinue | Select-Object -First 25)
    foreach ($h in $hits) { W ("  " + $h.Line.Trim()) }
    if ($hits.Count -eq 0) { W '  (no Studio lines)' }
}
Record 'SW.2' 'An installer log exists and can be read for the Studio step' `
    $(if ($logs.Count -gt 0) { 'PASS' } else { 'VOID' }) `
    "logFiles=$($logs.Count); with none, the install sequence cannot be reconstructed from this box"

Section '4. Is Studio running, and is it on the Start menu'
$procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'Studio|ClawFactory' })
W ("PROCS=" + (($procs | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ', '))
foreach ($sm in @(
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
)) {
    $lnks = @(Get-ChildItem $sm -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Claw|Studio' })
    foreach ($l in $lnks) { W "SHORTCUT $($l.FullName)" }
}
Complete-Phase -ResultsJson 'C:\cfv\studiowhere-results.json' -MarkerPrefix 'STUDIOWHERE'
