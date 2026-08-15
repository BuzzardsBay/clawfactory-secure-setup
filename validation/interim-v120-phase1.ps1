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
# W, Section, Marker, Record, Register-Control, Require-Precondition,
# Assert-Searchable, Compare-Independent and Complete-Phase all live here now.
# The VOID rules are properties of that runner rather than habits of this file:
# see its header for why four wrong results shipped while every habit was in
# place. Two independent channels are still kept -- the producer transcript and
# the wrapper's redirect -- because cfv-149 lost 100 percent of its evidence
# relying on one.
. C:\cfv\interim-v120-phaselib.ps1

function Finish($code) {
    W ''
    W "PHASE1_PROBE_COMPLETE rc=$code"
    exit $code
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

    # THE STUDIO PIN, REPLACED 2026-08-15, and the reason matters more than the value.
    #
    # This used to be the digest of the STAGED Studio INSTALLER in
    # <app>\stage\*.exe. That check was VACUOUS on the happy path: the installer
    # de-elevates and runs the staged payload at ssPostInstall and the stage is
    # not retained afterwards, so on any SUCCESSFUL install the file was already
    # gone and the check recorded INFO. It could only ever derive a digest when
    # the install had ALREADY failed early enough to leave the stage behind,
    # which is precisely when nobody needs a payload pin. A check that cannot
    # detect the drift it exists to detect is not coverage, and leaving it in
    # place to be counted as coverage is worse than not having it.
    #
    # What replaces it is the digest of the INSTALLED app.asar, which is where
    # the shipped Studio payload actually lands:
    #     %LOCALAPPDATA%\Programs\ClawFactory Studio\resources\app.asar
    # That file exists on every successful install, so the check fires on the
    # happy path, which is the whole point.
    #
    # On derivability, checked rather than assumed: the electron-builder NSIS
    # installer carries exactly ONE embedded archive (a 7z payload, signature
    # found at a single offset in the 1.2.0 artifact), and 7z is lossless, so the
    # installed app.asar is the same bytes as the one this digest is taken from
    # in desktop\release\win-unpacked\resources\app.asar. If the VM ever reports
    # a mismatch here on an otherwise-clean install, that is a HARNESS finding to
    # diagnose, not a product failure to report.
    studioAsar    = 'dc24d41618545f6043d3160e7d4d3d93dd28eb90e620da0c44eb62fac2b6d7dd'

    version       = '1.3.3'
}

# The names are transcribed from setup.ps1 Step-Preflight $required. Held here as
# an independent copy ON PURPOSE: if the installer's list and this list ever
# disagree, that disagreement is itself the finding.
#
# 2026-08-14: it disagreed, and this file did not notice. The run reported "all
# 30 present" while the installer reported 33, because this probe only ever
# enumerates its own copy and nothing compared the two counts. An independent
# copy that is never reconciled is not independence, it is a second stale list.
# The three Guard 3 resources are added below and the counts are now compared
# explicitly rather than left for a reader to spot.
#
# 2026-08-15: renamed from $REQUIRED30. The name carried a count, the count moved
# to 33 and then 34, and a name that states a stale number is the same defect as
# a label that states one (see PIN.bundle below). The count is now only ever read
# from the list itself.
$REQUIRED = @(
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
    'install-send.sh',
    # v1 Guard 3
    'clawfactory-read-fetch.sh', 'clawfactory-fetchctl.js', 'install-read-fetch.sh',
    # v1 Guard 3, the toolchain access toggle
    'clawfactory-toolchain.sh'
)

Start-Phase -Name "ClawFactory v$($PIN.version) INTERIM validation, Phase 1 (install)" `
    -Transcript $Transcript -Sentinel 'PHASE1_PROBE_COMPLETE'
W "Artifact: $CombinedExe"
W "NOTE: this is an INTERIM validation. It is NOT the release gate."

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
        $script:InstallerResourceCount = [int]$Matches[1]
        Record 'P1.2' 'Step-Preflight ran and passed (installer claim)' 'PASS' "installer reports $($Matches[1]) resources"
    } else {
        Record 'P1.2' 'Step-Preflight ran and passed (installer claim)' 'FAIL' 'no preflight success line in setup.log'
    }
} else {
    Record 'P1.6' 'Install transcript captured' 'FAIL' "setup.log absent at $setupLog"
    Record 'P1.2' 'Step-Preflight ran and passed (installer claim)' 'FAIL' 'no setup.log to read'
}

# --------------------------- 4. every required resource, verified independently
Section "4. All $($REQUIRED.Count) required resources on disk, enumerated by this probe"
$appDir = 'C:\Program Files\ClawFactory'
$resDir = Join-Path $appDir 'resources'
W "Resource dir: $resDir (exists=$(Test-Path $resDir))"
$missing = @()
$present = @()
foreach ($r in $REQUIRED) {
    $p = Join-Path $resDir $r
    if (Test-Path -LiteralPath $p) { $present += $r } else { $missing += $r }
}
W "Independently confirmed present: $($present.Count) / $($REQUIRED.Count)"
if ($missing.Count) { W "MISSING: $($missing -join ', ')" }

# The enumeration means nothing unless this probe can tell present from absent.
# Registered as a POSITIVE CONTROL rather than recorded as an ordinary check: if
# a real resource cannot be found, the whole phase is measuring a broken
# Test-Path and every result below it is void.
$sentinelReal = 'safety-rules.md'
$canSeePresent = Test-Path -LiteralPath (Join-Path $resDir $sentinelReal)
Register-Control -Id 'P1.3.CTL' -Name "the enumeration can see a resource that IS there ($sentinelReal)" `
    -Fired $canSeePresent -Evidence "Test-Path on $sentinelReal returned $canSeePresent" | Out-Null

Record 'P1.3' "All $($REQUIRED.Count) required resources on disk (independent enumeration)" `
    $(if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
    "present=$($present.Count)/$($REQUIRED.Count) missing=$(if($missing.Count){$missing -join ','}else{'none'})"

# THE CHECK THIS FILE CLAIMED TO BE AND WAS NOT. Holding an independent copy of
# the list is only independence if the two copies are actually compared. On
# 2026-08-14 this probe reported "all 30 present" while the installer reported
# 33, and nothing noticed, because each side only ever counted itself. A guard
# resource could therefore be added to the product and silently never checked
# here, which is precisely the drift the copy exists to catch.
#
# Now a runner-level call, so the comparison cannot be dropped by a future edit
# and an absent installer count records VOID rather than reading as agreement.
Compare-Independent -Id 'P1.3b' -Name 'Installer resource count and this probe agree (the copies are reconciled)' `
    -Mine $REQUIRED.Count -Reported $script:InstallerResourceCount `
    -MineLabel 'this probe enumerates' -ReportedLabel 'the installer claims' | Out-Null

# Paired NEGATIVE control: a name that MUST be absent. If this "finds" a file,
# the enumeration is not discriminating and the count above is a void result.
$ctlName = 'this-resource-does-not-exist-b7f31c.md'
$ctlHit  = Test-Path -LiteralPath (Join-Path $resDir $ctlName)
Record 'P1.3c' 'CONTROL: absent resource must not be found' `
    $(if (-not $ctlHit) { 'PASS' } else { 'FAIL' }) "probe for $ctlName returned $ctlHit"

# ------------------------------------------- 5. the pins, each by execution
Section "5. Build-time pins, RE-DERIVED on the installed machine"

$chan = Test-WslChannel
W "WSL channel self-test: Ok=$($chan.Ok)"
W $chan.Detail
# The channel IS the instrument for every in-distro pin below, so it is a
# positive control rather than an ordinary check. L22: an inline probe once
# reported that clawuser had connected to smtp.gmail.com on two ports, which the
# channel had fabricated, and it would have been filed as a ship-blocking hole in
# a firewall that was working correctly.
Register-Control -Id 'P1.CHAN' -Name 'the file-based WSL channel discriminates (subject passes, control fails)' `
    -Fired $chan.Ok -Evidence 'subject id -u=0, /bin/false rc=1, variable expansion intact' | Out-Null
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

# 5e. The Studio payload, checked where it ACTUALLY LANDS.
#
# The old check hashed the staged Studio INSTALLER in <app>\stage and was vacuous
# on every successful install, because the stage is not retained past
# ssPostInstall. It has been deleted rather than left in place: an INFO row that
# reads like coverage is worse than an absent check, because it gets counted.
#
# The installed app.asar is the shipped payload. It exists on every successful
# install, so this fires on the happy path, which is the entire point.
$asarPaths = @(
    "$env:LOCALAPPDATA\Programs\ClawFactory Studio\resources\app.asar",
    'C:\Users\clawadmin\AppData\Local\Programs\ClawFactory Studio\resources\app.asar'
)
$asar = $asarPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($asar) {
    $asarActual = (Get-FileHash -LiteralPath $asar -Algorithm SHA256).Hash.ToLower()
    W "Installed app.asar: $asar ($((Get-Item -LiteralPath $asar).Length) B)"
    Cmp 'PIN.studio.asar' 'Studio pin: the INSTALLED app.asar matches the build-time digest' $asarActual $PIN.studioAsar
} else {
    # Studio absent is a real failure of the combined installer's de-elevated
    # post-install step, not a harness gap, so it is a FAIL and it says which.
    Record 'PIN.studio.asar' 'Studio pin: the INSTALLED app.asar matches the build-time digest' 'FAIL' `
        ("no app.asar under any of: " + ($asarPaths -join ' ; ') +
         ". Studio did not land, so the combined installer's ExecAsOriginalUser post-install step did not complete.")
}

# 5f. Version -- the installed product must report the pinned version.
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
# The version is read from $PIN rather than written into the label, for the same
# reason PIN.bundle's count now is: a label that states a number the check does
# not read is a label that goes stale silently.
Record 'PIN.version' "Installed version reports $($PIN.version)" `
    $(if ($verOk) { 'PASS' } else { 'FAIL' }) ($verSources -join ' ; ')

# 5g. Bundle -- already established by P1.3, restated as a pin.
#
# The label used to say 30 while the check counted 33. Both numbers now come from
# $REQUIRED.Count, so the sentence a reader sees and the number the code compares
# cannot drift apart. That was the whole defect: nothing was wrong with the
# check, only with the sentence describing it, and a wrong sentence is what a
# reader carries away.
Record 'PIN.bundle' "Bundle completeness (all $($REQUIRED.Count) preflight resources shipped)" `
    $(if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
    "expected $($REQUIRED.Count), found $($present.Count), missing=$(if($missing.Count){$missing -join ','}else{'none'})"

# --------------------------------------------------------------- 6. summary
# Complete-Phase owns the verdict now. It voids the phase if no positive control
# was registered, if one did not fire, or if a precondition was unmet, and it
# exits 4 for VOID so a driver cannot read a missing measurement as a pass.
Complete-Phase -ResultsJson 'C:\cfv\phase1-results.json' -MarkerPrefix 'PHASE1'
