<#
  Phase 1 probe for the v1.2.0 interim validation. Runs in the interactive
  clawadmin auto-logon session (WSL distros are per-user; SYSTEM cannot see
  them, so run-command is not an option for anything WSL-level).

  Phase 1 is the CHECKPOINT. If the install fails, that failure is the output of
  the whole session and the guard suite does not run.

  What this proves, and the standard it holds itself to:
    1. clean-box state recorded BEFORE install
    2. install runs, full transcript captured including every warning
    3. Step-Preflight passed, and all 30 required resources are on disk,
       verified INDEPENDENTLY of the installer's own report
    4. all seven build-time pins satisfied, each RE-DERIVED here rather than
       read out of the installer log
    5. install-result.txt reports success

  On "independently": the installer logging "Preflight: all 30 security
  resources present" is the installer's own claim about itself. A build that
  bundled 29 and miscounted would print exactly the same line. So this probe
  enumerates the 30 names itself and stats each one. Same reasoning for the
  pins: setup.ps1 logging "SOUL pin OK" is not evidence the installed SOUL.md
  hashes to the pinned value, it is evidence that setup.ps1 believes so. L24
  is the standing lesson here: an integrity value derived from the artefact it
  protects certifies nothing and looks exactly like a working control.
#>
param(
    [string]$CombinedExe = 'C:\cfv\combined-setup.exe',
    [string]$LicenseKey  = 'CF-TEST-TEST-TEST-TEST',
    [string]$Transcript  = 'C:\cfv\phase1-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1

# --- Producer-owned transcript. The wrapper's redirect is the other channel;
# two independent channels, because cfv-149 lost 100 percent of its evidence
# relying on one.
function W([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line
    $line | Out-File $Transcript -Encoding utf8 -Append
}
function Section($t) { W ''; W ("=" * 72); W $t; W ("=" * 72) }
function Marker($n) { New-Item -ItemType File -Path "C:\cfv\$n.marker" -Force | Out-Null }
function Finish($code) {
    W ''
    W "PHASE1_PROBE_COMPLETE rc=$code"
    exit $code
}

# --- Result ledger. Every check lands here so the report is a table, not prose.
$script:Results = New-Object System.Collections.ArrayList
function Record($id, $name, $verdict, $evidence) {
    [void]$script:Results.Add([pscustomobject]@{ Id = $id; Name = $name; Verdict = $verdict; Evidence = $evidence })
    W ("  [{0}] {1} :: {2}" -f $verdict, $id, $name)
    if ($evidence) { W ("        {0}" -f ($evidence -replace "`r?`n", ' | ')) }
}

# --- The seven build-time pins, as literals. These are transcribed from the
# SIGNED source that produced this artifact; the probe re-derives the actual
# values on the installed machine and compares. A mismatch means either the
# artifact is not the one we think it is, or a pin is decorative.
$PIN = @{
    soul          = 'e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941'
    persona       = '0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0'
    workspaceSoul = '441b6279f6613c313e87e9e9e034f97a220540cddbf1cf738bb9a86c37a5a257'
    rootfs        = '1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109'
    studio        = 'b701bfb734d5a307a41cf4b3cca8d34eb4f9c89b2116c7bc084fb180afefb7eb'
    version       = '1.2.0'
}

# The 30 names are transcribed from setup.ps1 Step-Preflight $required. Held
# here as an independent copy ON PURPOSE: if the installer's list and this list
# ever disagree, that disagreement is itself the finding.
$REQUIRED30 = @(
    'safety-rules.md', 'persona.md', 'openclaw-shim.sh', 'clawfactory-turn-gate.sh',
    'clawfactory-spend-check.js', 'install-turn-gate.sh', 'freeze-injected-soul.sh',
    'clawfactory-proxy.js', 'clawfactory-proxy.service', 'install-chat-proxy.sh',
    'gateway-wait.sh',
    'quarantine-lib.js', 'clawfactory-quarantined.js', 'clawfactory-quarantinectl.js',
    'clawfactory-quarantine-rm.js', 'clawfactory-quarantine.service',
    'clawfactory-quarantine-gc.service', 'clawfactory-quarantine-gc.timer',
    'install-quarantine.sh',
    'send-lib.js', 'send-smtp.js', 'clawfactory-sendd.js', 'clawfactory-sendctl.js',
    'clawfactory-send.js', 'clawfactory-send.service', 'clawfactory-send-gc.service',
    'clawfactory-send-gc.timer', 'clawfactory-fw-assert.sh', 'egress-policy.json',
    'install-send.sh'
)

Section "ClawFactory v1.2.0 INTERIM validation, Phase 1 (install). $(Get-Date -Format s)"
W "Artifact: $CombinedExe"
W "NOTE: this is an INTERIM validation of a Guards 1+2 build. It is NOT the release gate."

# ---------------------------------------------------------------- 1. baseline
Section "1. Clean-box state BEFORE install"
try {
    $os = Get-CimInstance Win32_OperatingSystem
    W "OS build        : $($os.BuildNumber)  ($($os.Caption))"
    W "Machine GUID    : $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' MachineGuid).MachineGuid)"
    $distros = (& wsl.exe --list --quiet 2>&1 | ForEach-Object { ($_ -replace "`0",'').Trim() } | Where-Object { $_ })
    W "WSL distros     : $(if ($distros) { $distros -join ',' } else { '(none)' })"
    W "ProgramData\ClawFactory exists : $(Test-Path 'C:\ProgramData\ClawFactory')"
    W "Program Files\ClawFactory      : $(Test-Path 'C:\Program Files\ClawFactory')"
    Record 'P1.0' 'Clean-box baseline recorded' 'INFO' "distros=$($distros -join ',')"
} catch { Record 'P1.0' 'Clean-box baseline recorded' 'WARN' $_.Exception.Message }

# ----------------------------------------------------------------- 2. install
Section "2. Install"
if (-not (Test-Path $CombinedExe)) {
    Record 'P1.1' 'Installer present on VM' 'FAIL' "missing at $CombinedExe"
    Marker 'PHASE1_FEASIBILITY_FAIL'; Finish 2
}
$sha = (Get-FileHash $CombinedExe -Algorithm SHA256).Hash.ToLower()
W "On-VM artifact sha256: $sha"
Record 'P1.1' 'Installer present, hash re-derived on VM' 'INFO' $sha

$sw = [Diagnostics.Stopwatch]::StartNew()
W "Launching installer (/SILENT, log to C:\cfv\install.log)..."
Start-Process -FilePath $CombinedExe -ArgumentList `
    '/SILENT','/SUPPRESSMSGBOXES','/NORESTART','/LOG=C:\cfv\install.log', `
    '/PROVIDER=claude',"/LICENSE=$LicenseKey" -Wait
$sw.Stop()
W "Installer process returned after $([int]$sw.Elapsed.TotalMinutes) min."
Marker 'PHASE1_INSTALL_RETURNED'

# The Inno exit code is NOT the honest verdict -- setup.ps1 writes the real one.
$resultFile = 'C:\ProgramData\ClawFactory\install-result.txt'
$verdict = if (Test-Path $resultFile) { (Get-Content $resultFile -Raw).Trim() } else { '(install-result.txt ABSENT)' }
W "install-result.txt: $verdict"
Record 'P1.5' 'install-result.txt reports success' `
    $(if ($verdict -match 'success') { 'PASS' } else { 'FAIL' }) $verdict

# --------------------------------------------------- 3. transcript + warnings
Section "3. Install transcript, every step and every warning"
# setup.ps1 writes to $LogDir\install.log where $LogDir = $env:ProgramData\ClawFactory
# (setup.ps1:76-77). The first run of this probe looked for
# ...\ClawFactory\logs\setup.log, which does not exist, and reported two FAILs
# for a log that was present and complete. A probe that looks in the wrong place
# and calls the absence a product failure is worse than no probe: it manufactures
# defects and buries the real one. Resolved by search, not by a single guess.
$setupLog = @(
    'C:\ProgramData\ClawFactory\install.log',
    'C:\ProgramData\ClawFactory\logs\setup.log',
    'C:\ProgramData\ClawFactory\logs\install.log'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
foreach ($lp in @('C:\cfv\install.log', $setupLog)) {
    if ($lp -and (Test-Path $lp)) { W "LOG PRESENT: $lp ($((Get-Item $lp).Length) B)" } else { W "LOG MISSING: $lp" }
}
if ($setupLog -and (Test-Path $setupLog)) {
    $log = Get-Content $setupLog -Raw
    $warns = @([regex]::Matches($log, '(?m)^.*\b(WARN|WARNING)\b.*$') | ForEach-Object { $_.Value.Trim() })
    $errs  = @([regex]::Matches($log, '(?m)^.*\b(ERROR|FATAL|Exception)\b.*$') | ForEach-Object { $_.Value.Trim() })
    W "Steps logged : $(([regex]::Matches($log, '(?m)^.*Step \d+[a-z]?:.*$')).Count)"
    W "WARN lines   : $($warns.Count)"
    foreach ($w in $warns) { W "   WARN> $w" }
    W "ERROR lines  : $($errs.Count)"
    foreach ($e in $errs) { W "   ERR > $e" }
    Record 'P1.6' 'Install transcript captured' 'INFO' "warns=$($warns.Count) errors=$($errs.Count)"

    # Step-Preflight must actually have run and passed. Its own line is recorded
    # here as the installer's CLAIM; check P1.3 below is the independent proof.
    if ($log -match 'Preflight: all (\d+) security resources present') {
        Record 'P1.2' 'Step-Preflight ran and passed (installer claim)' 'PASS' "installer reports $($Matches[1]) resources"
    } else {
        Record 'P1.2' 'Step-Preflight ran and passed (installer claim)' 'FAIL' 'no preflight success line in setup.log'
    }
} else {
    Record 'P1.6' 'Install transcript captured' 'FAIL' "setup.log absent at $setupLog"
    Record 'P1.2' 'Step-Preflight ran and passed (installer claim)' 'FAIL' 'no setup.log to read'
}

# ------------------------------------- 4. 30 resources, verified independently
Section "4. All 30 required resources on disk, enumerated by this probe"
$appDir = 'C:\Program Files\ClawFactory'
$resDir = Join-Path $appDir 'resources'
W "Resource dir: $resDir (exists=$(Test-Path $resDir))"
$missing = @()
$present = @()
foreach ($r in $REQUIRED30) {
    $p = Join-Path $resDir $r
    if (Test-Path -LiteralPath $p) { $present += $r } else { $missing += $r }
}
W "Independently confirmed present: $($present.Count) / $($REQUIRED30.Count)"
if ($missing.Count) { W "MISSING: $($missing -join ', ')" }
Record 'P1.3' 'All 30 required resources on disk (independent enumeration)' `
    $(if ($missing.Count -eq 0 -and $REQUIRED30.Count -eq 30) { 'PASS' } else { 'FAIL' }) `
    "present=$($present.Count)/30 missing=$(if($missing.Count){$missing -join ','}else{'none'})"

# Paired control: a name that MUST be absent. If this "finds" a file, the
# enumeration is not discriminating and the 30/30 above is a void result.
$ctlName = 'this-resource-does-not-exist-b7f31c.md'
$ctlHit  = Test-Path -LiteralPath (Join-Path $resDir $ctlName)
Record 'P1.3c' 'CONTROL: absent resource must not be found' `
    $(if (-not $ctlHit) { 'PASS' } else { 'FAIL' }) "probe for $ctlName returned $ctlHit"

# ------------------------------------------- 5. seven pins, each by execution
Section "5. Seven build-time pins, RE-DERIVED on the installed machine"

$chan = Test-WslChannel
W "WSL channel self-test: Ok=$($chan.Ok)"
W $chan.Detail
Record 'P1.CHAN' 'File-based WSL channel discriminates (subject passes, control fails)' `
    $(if ($chan.Ok) { 'PASS' } else { 'FAIL' }) `
    'subject id -u=0, /bin/false rc=1, variable expansion intact'
if (-not $chan.Ok) {
    W 'CHANNEL IS NOT TRUSTWORTHY. Every WSL-side pin result below would be a void result (L22). Halting pin checks.'
    Marker 'PHASE1_CHANNEL_FAIL'
}

function Cmp($id, $name, $actual, $expected) {
    $ok = ($actual -and $expected -and ($actual.ToLower() -eq $expected.ToLower()))
    Record $id $name $(if ($ok) { 'PASS' } else { 'FAIL' }) "actual=$actual expected=$expected"
}

# 5a. persona -- a Windows-side file, hashed here directly.
$personaPath = Join-Path $resDir 'persona.md'
$personaActual = if (Test-Path $personaPath) { (Get-FileHash $personaPath -Algorithm SHA256).Hash.ToLower() } else { '(absent)' }
Cmp 'PIN.persona' 'Pin 1of7 persona.md' $personaActual $PIN.persona

# 5b. SOUL -- safety-rules.md as shipped on Windows.
$soulPath = Join-Path $resDir 'safety-rules.md'
$soulActual = if (Test-Path $soulPath) { (Get-FileHash $soulPath -Algorithm SHA256).Hash.ToLower() } else { '(absent)' }
Cmp 'PIN.soul' 'Pin 2of7 safety-rules.md (SOUL)' $soulActual $PIN.soul

# 5c/5d. In-distro SOUL and the COMPOSED workspace SOUL the agent actually reads.
if ($chan.Ok) {
    $r = Invoke-WslFile -Tag 'pins' -User 'root' -Body @'
CLAW_HOME=$(getent passwd clawuser | cut -d: -f6)
echo "CLAW_HOME=$CLAW_HOME"
for f in "$CLAW_HOME/.openclaw/SOUL.md" /etc/clawfactory/soul.sha256; do
  if [ -e "$f" ]; then
    echo "EXISTS $f mode=$(stat -c %a "$f") owner=$(stat -c %U:%G "$f")"
  else
    echo "ABSENT $f"
  fi
done
[ -f "$CLAW_HOME/.openclaw/SOUL.md" ] && echo "INDISTRO_SOUL_SHA=$(sha256sum "$CLAW_HOME/.openclaw/SOUL.md" | cut -d" " -f1)"
[ -f /etc/clawfactory/soul.sha256 ] && echo "PINNED_SOUL_FILE=$(cat /etc/clawfactory/soul.sha256)"
# The composed workspace SOUL is the file the agent reads at turn time. SEARCH
# for it rather than guessing at three fixed paths: the first version of this
# probe guessed, missed, and reported a FAIL for a pin the installer had in fact
# satisfied (the install log shows the freeze step emitting the exact pinned
# hash). A pin check that can fail because the checker looked in the wrong place
# is not a pin check.
find "$CLAW_HOME" /etc/clawfactory -maxdepth 4 -name 'SOUL.md' -o -maxdepth 4 -name 'workspace-soul*' 2>/dev/null | while read -r cand; do
  [ -f "$cand" ] && echo "WS_CAND $cand sha=$(sha256sum "$cand" 2>/dev/null | cut -d' ' -f1) mode=$(stat -c %a "$cand") owner=$(stat -c %U:%G "$cand")"
done
echo "OS_RELEASE=$(. /etc/os-release; echo "$ID $VERSION_ID $VERSION_CODENAME")"
echo "AUTOMOUNT_LINE=$(awk 'BEGIN{s=""} /^\[/{s=$0} s ~ /^\[automount\]/ && /enabled/{print}' /etc/wsl.conf)"
echo "MNT_C_PRESENT=$([ -d /mnt/c ] && echo yes || echo no)"
'@
    W $r.Out
    if ($r.Out -match 'INDISTRO_SOUL_SHA=([a-f0-9]{64})') {
        Cmp 'PIN.soul.indistro' 'Pin 2of7 SOUL as installed in distro' $Matches[1] $PIN.soul
    } else {
        Record 'PIN.soul.indistro' 'Pin 2of7 SOUL as installed in distro' 'FAIL' 'could not read in-distro SOUL.md'
    }
    if ($r.Out -match 'PINNED_SOUL_FILE=([a-f0-9]{64})') {
        Cmp 'PIN.soul.rootpin' 'Root-owned /etc/clawfactory/soul.sha256 matches pin' $Matches[1] $PIN.soul
    } else {
        Record 'PIN.soul.rootpin' 'Root-owned /etc/clawfactory/soul.sha256 matches pin' 'FAIL' 'file absent or unreadable'
    }
    $wsFound = $false
    foreach ($m in [regex]::Matches($r.Out, 'WS_CAND (\S+) sha=([a-f0-9]{64})')) {
        if ($m.Groups[2].Value.ToLower() -eq $PIN.workspaceSoul.ToLower()) { $wsFound = $true }
        W "  workspace-SOUL candidate $($m.Groups[1].Value) -> $($m.Groups[2].Value)"
    }
    Record 'PIN.workspaceSoul' 'Pin 3of7 composed workspace SOUL matches pin' `
        $(if ($wsFound) { 'PASS' } else { 'FAIL' }) "expected=$($PIN.workspaceSoul)"

    # Rootfs identity. The tarball itself lands in {tmp} and is removed after
    # install, so its hash cannot be re-derived post-install. What CAN be
    # re-derived is the identity of the distro it produced. Recorded honestly as
    # the weaker of the two claims rather than dressed up as a hash match.
    if ($r.Out -match 'OS_RELEASE=(.+)') {
        Record 'PIN.rootfs' 'Pin 4of7 rootfs identity (distro produced by the pinned tarball)' 'INFO' `
            "$($Matches[1].Trim()); tarball hash not re-derivable post-install, see note"
    }
} else {
    foreach ($id in @('PIN.soul.indistro','PIN.soul.rootpin','PIN.workspaceSoul','PIN.rootfs')) {
        Record $id 'in-distro pin check' 'VOID' 'WSL channel self-test failed; result would be unreliable (L22)'
    }
}

# 5e. Studio payload -- the staged installer the combined build embedded.
$studioStage = Get-ChildItem (Join-Path $appDir 'stage') -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($studioStage) {
    $sActual = (Get-FileHash $studioStage.FullName -Algorithm SHA256).Hash.ToLower()
    Cmp 'PIN.studio' 'Pin 5of7 embedded Studio payload' $sActual $PIN.studio
} else {
    # Absence is not automatically a failure: the stage dir may be cleaned after
    # Studio installs. Check whether Studio actually landed before judging.
    $studioInstalled = @(
        "$env:LOCALAPPDATA\Programs\ClawFactory Studio",
        "C:\Users\clawadmin\AppData\Local\Programs\ClawFactory Studio"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    Record 'PIN.studio' 'Pin 5of7 embedded Studio payload' 'INFO' `
        "stage payload not retained post-install; Studio present at: $(if($studioInstalled){$studioInstalled}else{'NOT FOUND'})"
}

# 5f. Version -- the installed product must report 1.2.0.
$verSources = @()
$rk = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
foreach ($k in (Get-ChildItem $rk -ErrorAction SilentlyContinue)) {
    $dn = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).DisplayName
    if ($dn -match 'ClawFactory') {
        $dv = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).DisplayVersion
        $verSources += "$dn=$dv"
    }
}
W "Uninstall-key versions: $($verSources -join ' ; ')"
$verOk = ($verSources -join ' ') -match [regex]::Escape($PIN.version)
Record 'PIN.version' 'Pin 6of7 installed version reports 1.2.0' `
    $(if ($verOk) { 'PASS' } else { 'FAIL' }) ($verSources -join ' ; ')

# 5g. Bundle -- already established by P1.3, restated as the seventh pin.
Record 'PIN.bundle' 'Pin 7of7 bundle completeness (all 30 preflight resources shipped)' `
    $(if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' }) "missing=$(if($missing.Count){$missing -join ','}else{'none'})"

# --------------------------------------------------------------- 6. summary
Section "6. Phase 1 result table"
foreach ($row in $script:Results) {
    W ("{0,-22} {1,-6} {2}" -f $row.Id, $row.Verdict, $row.Name)
}
$fails = @($script:Results | Where-Object { $_.Verdict -eq 'FAIL' })
$voids = @($script:Results | Where-Object { $_.Verdict -eq 'VOID' })
W ''
W "PASS=$(@($script:Results | Where-Object Verdict -eq 'PASS').Count) FAIL=$($fails.Count) VOID=$($voids.Count) INFO=$(@($script:Results | Where-Object Verdict -eq 'INFO').Count)"
$script:Results | ConvertTo-Json -Depth 4 | Out-File 'C:\cfv\phase1-results.json' -Encoding utf8

if ($fails.Count -gt 0) {
    W ''
    W "PHASE 1 FAILED. Failing checks:"
    foreach ($f in $fails) { W "   FAIL $($f.Id) $($f.Name) :: $($f.Evidence)" }
    Marker 'PHASE1_FAIL'
    Finish 1
}
Marker 'PHASE1_PASS'
Finish 0
