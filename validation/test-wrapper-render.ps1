<#
  Render test for the JOB 3 wrapper builder + evidence gate + probe structure. NO
  Azure calls, no VM -- runs for free, forever. This is the simulate-before-execute
  step cfv-149 lacked: [Parser]::ParseFile only proves the script is syntactically
  valid, but the cfv-149 defect WAS valid PowerShell (6 array elements is legal). So
  we BUILD the wrapper content and assert its STRUCTURE, exercise the gate against
  the exact 102-byte failure that slipped through, and STATICALLY LINT the JOB 3
  probe for the combined-installer flow + the two new cells + the dropped cell.

  Exercises the SAME functions the driver dot-sources (wrapper-builder.ps1), so a
  regression in the real code fails this test.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'wrapper-builder.ps1')

$script:fail = 0
function Check($name, [bool]$cond) {
    if ($cond) { Write-Host "PASS  $name" -ForegroundColor Green }
    else       { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}

Write-Host "--- 1. wrapper cmdLines structure (combined installer) ---" -ForegroundColor Cyan
$lines = Build-Job3CmdLines -SeedEnc 'SEEDENC_DUMMY_BASE64'
Check "cmdLines has exactly 4 elements (cfv-149 produced 6)" ($lines.Count -eq 4)
$probe = [string]$lines[2]
Check "probe line contains the probe script path"             ($probe -match [regex]::Escape('C:\cfv\job3-probe.ps1'))
Check "probe line passes the SINGLE combined installer (-CombinedExe)" ($probe -match '-CombinedExe\s+C:\\cfv\\combined-setup\.exe')
Check "probe line has NO separate -StudioExe (combined flow)"  (-not ($probe -match '-StudioExe'))
Check "probe line has NO separate -SecureExe (combined flow)"  (-not ($probe -match '-SecureExe'))
Check "probe line contains -SeedKeyTarget on the SAME line"   ($probe -match '-SeedKeyTarget')
Check "probe line contains the redirect on the SAME line"     ($probe -match [regex]::Escape('> C:\cfv\job3-out.txt 2>&1'))
Check "on that line, -SeedKeyTarget precedes the redirect (one command)" (
    ($probe.IndexOf('-SeedKeyTarget') -ge 0) -and
    ($probe.IndexOf('-SeedKeyTarget') -lt $probe.IndexOf('> C:\cfv\job3-out.txt')))
Check "NO array element is a bare '-SeedKeyTarget...' fragment (the cfv-149 signature)" (
    -not ($lines | Where-Object { $_ -match '^\s*-SeedKeyTarget' }))
Check "line 0 is @echo off"          ([string]$lines[0] -eq '@echo off')
Check "line 3 writes JOB3_DONE"      ([string]$lines[3] -match 'JOB3_DONE')

Write-Host "`n--- 2. evidence-before-teardown gate (JOB3 sentinel) ---" -ForegroundColor Cyan
$tmp = Join-Path $env:TEMP ("wraptest3-{0}" -f ([Guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    # the EXACT cfv-149 dead bundle (~102 B, no sentinel)
    $dead = Join-Path $tmp 'dead.txt'
    "'-LicenseKey' is not recognized as an internal or external command,`r`noperable program or batch file." |
        Out-File $dead -Encoding ascii
    Check "gate REJECTS the ~102-byte cfv-149 dead bundle" (-not (Test-Job3Evidence -Files @($dead)))

    # a plausible run with the sentinel (well above the floor)
    $good = Join-Path $tmp 'good.txt'
    (('x' * 5000) + "`r`nJOB3_PROBE_COMPLETE rc=0 bytes=5000") | Out-File $good -Encoding ascii
    Check "gate ACCEPTS a plausible bundle WITH the JOB3 sentinel" (Test-Job3Evidence -Files @($good))

    # big but NO sentinel -> reject (a full-size but sentinel-less capture is suspect)
    $noSent = Join-Path $tmp 'nosent.txt'
    ('y' * 5000) | Out-File $noSent -Encoding ascii
    Check "gate REJECTS a big bundle with NO sentinel" (-not (Test-Job3Evidence -Files @($noSent)))

    # a JOB2 sentinel must NOT satisfy the JOB3 gate (right shape, wrong run)
    $wrong = Join-Path $tmp 'wrong.txt'
    (('z' * 5000) + "`r`nJOB2_PROBE_COMPLETE rc=0 bytes=5000") | Out-File $wrong -Encoding ascii
    Check "gate REJECTS a JOB2 sentinel (must be JOB3_PROBE_COMPLETE)" (-not (Test-Job3Evidence -Files @($wrong)))

    # sentinel present but below the size floor -> reject (truncated/corrupt)
    $small = Join-Path $tmp 'small.txt'
    'JOB3_PROBE_COMPLETE rc=0 bytes=10' | Out-File $small -Encoding ascii
    Check "gate REJECTS a sentinel-only file below the 512-byte floor" (-not (Test-Job3Evidence -Files @($small)))

    # redundancy: one dead channel + one good channel -> accept
    Check "gate ACCEPTS when EITHER channel is valid (redundancy)" (Test-Job3Evidence -Files @($dead, $good))

    # both missing/null -> reject
    Check "gate REJECTS when both channels are missing" (-not (Test-Job3Evidence -Files @($null, $null)))
} finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host "`n--- 3. probe: COMBINED single-installer flow ---" -ForegroundColor Cyan
$probeSrc = Get-Content (Join-Path $PSScriptRoot 'job3-probe.ps1') -Raw
Check "probe installs the SINGLE combined installer (`$CombinedExe)"       ($probeSrc -match '\$CombinedExe')
Check "probe has the '1. INSTALL COMBINED' step"                          ($probeSrc -match 'INSTALL COMBINED')
Check "probe does NOT run a separate Secure-Setup install (-SecureExe)"    (-not ($probeSrc -match '\$SecureExe'))
Check "probe does NOT run a separate Studio install (-StudioExe)"          (-not ($probeSrc -match '\$StudioExe'))
Check "probe emits the JOB3_PROBE_COMPLETE sentinel via Finish"            ($probeSrc -match 'JOB3_PROBE_COMPLETE')
Check "probe Wsl helper strips CR before base64 (F2 / L21)"               ($probeSrc -match "\`$cmd = \`$cmd -replace")

Write-Host "`n--- 4. probe: NEW CELL A (elevation rule -- Studio in invoking user profile) ---" -ForegroundColor Cyan
$cA = [regex]::Match($probeSrc, '(?s)===== A\. ELEVATION RULE.*?(?====== B\.)').Value
Check "extracted CELL A block"                                             ($cA.Length -gt 0)
Check "CELL A resolves Studio under the invoking user's %LOCALAPPDATA%"    (
    ($cA -match [regex]::Escape('$env:LOCALAPPDATA')) -and
    ($cA -match [regex]::Escape('Programs\ClawFactory Studio')))
Check "CELL A asserts Studio present in THIS user's profile"               ($cA -match 'landedSelf')
Check "CELL A does a per-profile scan (no stray copy in another profile)"  ($cA -match 'per-profile scan' -and $cA -match "C:\\Users")
Check "CELL A reports EnableLUA + elevation (conditions explicit)"         ($cA -match 'EnableLUA' -and $cA -match 'IsElevatedAdmin')
Check "CELL A flags a wrong landing as a CONCERN"                          ($cA -match 'CELL A CONCERN')
Check "CELL A writes its progress marker"                                  ($cA -match "Marker 'STUDIO_PROFILE'")

Write-Host "`n--- 5. probe: NEW CELL B (installed Studio binaries Authenticode Valid) ---" -ForegroundColor Cyan
$cB = [regex]::Match($probeSrc, '(?s)===== B\. INSTALLED STUDIO BINARIES.*?(?====== 4\.)').Value
Check "extracted CELL B block"                                             ($cB.Length -gt 0)
Check "CELL B calls Get-AuthenticodeSignature on the installed binaries"   ($cB -match 'Get-AuthenticodeSignature')
Check "CELL B checks Status -ne 'Valid' and flags a CONCERN"               ($cB -match "Status -ne 'Valid'" -and $cB -match 'CELL B CONCERN')
Check "CELL B also verifies the uninstaller binary"                        ($cB -match "Filter 'Uninstall\*\.exe'")
Check "CELL B writes its progress marker"                                  ($cB -match "Marker 'STUDIO_SIGNED'")

Write-Host "`n--- 6. probe: engine-absent cell DROPPED (cited, not silently omitted) ---" -ForegroundColor Cyan
Check "probe does NOT run the JOB2 engine-absent read (rEngineAbsent)"     (-not ($probeSrc -match '\$rEngineAbsent'))
Check "probe has NO live ENGINE_ABSENT marker"                            (-not ($probeSrc -match "Marker 'ENGINE_ABSENT'"))
Check "probe CITES cfv-150/151 as the engine-absent standing proof"       ($probeSrc -match 'cfv-150' -and $probeSrc -match 'cfv-151')
Check "probe explains WHY engine-absent is impossible in the combined flow" ($probeSrc -match 'ordering (is|cannot)')

Write-Host "`n--- 7. probe: functional matrix + F1 revoke decontamination carried over ---" -ForegroundColor Cyan
$c4 = [regex]::Match($probeSrc, '(?s)--- CELL 4:.*?(?=--- CELL 5:)').Value
Check "extracted the CELL 4 block from the probe"                          ($c4.Length -gt 0)
Check "probe generates a FRESH post-revoke marker (CANARY-A2)"            ($probeSrc.Contains('CANARY-A2'))
Check "cell 4 A-revoked read targets marker2.txt (fresh, unseen)"        ($c4.Contains('marker2.txt'))
Check "cell 4 does NOT re-read A's original marker.txt (cfv-150 contamination)" (-not $c4.Contains('/workspaces/$idA/marker.txt'))
Check "cell 4 keeps the independent NO-MOUNT check"                       ($c4.Contains('NO-MOUNT'))
Check "cell 4 keeps the B-control read (idB/marker.txt)"                  ($c4.Contains('/workspaces/$idB/marker.txt'))
Check "cell 4 flags a fresh-marker readback as an ANOMALY"               ($c4.Contains('ANOMALY'))
Check "matrix keeps the granted read at /workspaces/<grant-id> (L19)"     ($probeSrc -match '/workspaces/\$idA/marker\.txt')

Write-Host ""
if ($script:fail -eq 0) { Write-Host "ALL RENDER TESTS PASSED" -ForegroundColor Green; exit 0 }
else { Write-Host "$($script:fail) RENDER TEST(S) FAILED" -ForegroundColor Red; exit 1 }
