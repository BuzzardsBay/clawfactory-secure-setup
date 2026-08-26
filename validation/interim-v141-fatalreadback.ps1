<#
  v1.4.1 release-closure probe: THE INSTALL-TIME FATAL READ-BACK, EXERCISED.

  WHAT IS BEING TESTED
  --------------------
  resources/install-read-fetch.sh lines 379-388:

      systemctl enable clawfactory-egress-refresh.service >/dev/null 2>&1 || true
      # READ BACK. `systemctl enable` is routinely written here with `|| true`,
      # which means a unit that failed to install looks identical to one that did.
      EGRESS_ENABLED="$(systemctl is-enabled clawfactory-egress-refresh.service 2>&1 || true)"
      if [ "$EGRESS_ENABLED" != "enabled" ]; then
          fatal "clawfactory-egress-refresh.service did not enable ..."
      fi

  That fatal has never fired in any run of this product, and an unproven fatal
  may be a no-op. It is the only thing standing between a silently unregistered
  boot unit and a user whose Web access panel reports a live address count after
  a reboot while the addresses it names are stale -- the precise failure card
  #276 exists to prevent.

  WHY THE INJECTION HAS THE SHAPE IT HAS
  ---------------------------------------
  The REAL failure this read-back was written for is not "the unit file failed
  to write" and not "systemd is dead" -- either of those kills the install
  ninety steps earlier and never reaches line 384. The real failure is narrow
  and specific: `systemctl enable` returns nonzero, `|| true` swallows it, and
  the unit is left NOT ENABLED while every preceding line reports success. That
  is the shape reproduced here.

  The mechanism used to reproduce it is a DIRECTORY sitting at the path the
  enable needs to create its symlink at:

      /etc/systemd/system/multi-user.target.wants/clawfactory-egress-refresh.service

  `systemctl enable` cannot replace a directory with a symlink, so it fails;
  `|| true` swallows the failure exactly as it would in the field; and
  `is-enabled` answers something that is not "enabled". The mechanism is
  injected and is stated as injected. The OBSERVABLE FAILURE is the real one,
  and it is targeted at one unit: every other ClawFactory unit enables normally
  in the same directory, which mode Calibrate proves rather than assumes.

  CALIBRATE BEFORE MEASURING. Mode Calibrate runs the whole injection against a
  THROWAWAY unit whose answers are known in advance, and asserts them, before an
  install is spent on the real one. A probe that cannot produce a known-correct
  result on a rigged input is not permitted to report a result on a real one.

  MODES
    Calibrate   rig a scratch unit, prove the injection produces exactly
                "enable fails, is-enabled is not enabled", prove it does NOT
                affect a second unit, then remove every trace of the scratch
    Inject      place the block on the real unit path, read it back
    RunInstall  run the v1.4.1 installer and require it to ABORT, with both
                named messages quoted verbatim, then measure the state it left
#>
param(
    [ValidateSet('Calibrate','Inject','RunInstall')][string]$Mode = 'Calibrate',
    [string]$CombinedExe = 'C:\cfv\combined-setup.exe',
    [ValidateSet('grok','openai','claude','gemini','ollama','later')][string]$Provider = 'claude',
    [string]$Transcript  = 'C:\cfv\fatal-out-probe.txt',
    [string]$ResultsJson = 'C:\cfv\fatal-results.json'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name "ClawFactory v1.4.1 install-time fatal read-back, mode=$Mode" `
    -Transcript $Transcript -Sentinel 'FATAL_PROBE_COMPLETE'

function Finish($code) { W ''; W "FATAL_PROBE_COMPLETE rc=$code"; exit $code }

function Val([string]$text, [string]$key) {
    if ($text -match "(?m)^$([regex]::Escape($key))=(.*)$") { return $Matches[1].Trim() }
    return '(not reported)'
}

$WANTS = '/etc/systemd/system/multi-user.target.wants/clawfactory-egress-refresh.service'

# The two messages this probe must find VERBATIM. Held here as literals so the
# assertion is a comparison against the shipped text, not a loose pattern that
# would match a paraphrase.
$FATAL_INNER = "[install-read-fetch] FATAL: clawfactory-egress-refresh.service did not enable (systemctl is-enabled said "
$FATAL_TAIL  = "The firewall itself is unaffected and still denies, so this is an honesty failure rather than an exposure, but it is not shippable."
$FATAL_OUTER = "Failed to install the read-fetch allowlist and the toolchain toggle (Guard 3). Refusing to finish: the product would offer a Web access panel with nothing behind it, and a control that is absent is worse than one that was never claimed."

# =============================================================================
if ($Mode -eq 'Calibrate') {
    Section '1. Rig a scratch unit and run the injection against a known answer'

    # Two scratch units. A is the subject, B is the collateral control: B must
    # enable normally IN THE SAME DIRECTORY while A is blocked, or the injection
    # is a blunt instrument that breaks the whole install rather than one unit.
    $body = @'
set +e
mk() {
  cat > /etc/systemd/system/$1 <<UNIT
[Unit]
Description=cfv calibration unit $1
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
[Install]
WantedBy=multi-user.target
UNIT
}
mk cfv-calib-a.service
mk cfv-calib-b.service
systemctl daemon-reload 2>/dev/null

# ---- CONTROL HALF: with NO block, the enable must take and must read back
rm -rf /etc/systemd/system/multi-user.target.wants/cfv-calib-a.service
out=$(systemctl enable cfv-calib-a.service 2>&1); rc=$?
echo "CTL_ENABLE_RC=$rc"
echo "CTL_ISENABLED=$(systemctl is-enabled cfv-calib-a.service 2>&1 | head -1)"
systemctl disable cfv-calib-a.service >/dev/null 2>&1

# ---- SUBJECT HALF: block the wants path with a DIRECTORY, then enable
rm -f /etc/systemd/system/multi-user.target.wants/cfv-calib-a.service
mkdir -p /etc/systemd/system/multi-user.target.wants/cfv-calib-a.service
echo "BLOCK_IS_DIR=$( [ -d /etc/systemd/system/multi-user.target.wants/cfv-calib-a.service ] && echo yes || echo no )"
out=$(systemctl enable cfv-calib-a.service 2>&1); rc=$?
echo "SUBJ_ENABLE_RC=$rc"
echo "SUBJ_ENABLE_OUT=$(echo "$out" | tr '\n' ' ' | cut -c1-300)"
echo "SUBJ_ISENABLED=$(systemctl is-enabled cfv-calib-a.service 2>&1 | head -1)"

# ---- COLLATERAL CONTROL: a DIFFERENT unit must still enable in that same dir
out=$(systemctl enable cfv-calib-b.service 2>&1); rc=$?
echo "COLL_ENABLE_RC=$rc"
echo "COLL_ISENABLED=$(systemctl is-enabled cfv-calib-b.service 2>&1 | head -1)"

# ---- clean up every trace of the calibration
systemctl disable cfv-calib-b.service >/dev/null 2>&1
rm -rf /etc/systemd/system/multi-user.target.wants/cfv-calib-a.service
rm -f /etc/systemd/system/multi-user.target.wants/cfv-calib-b.service
rm -f /etc/systemd/system/cfv-calib-a.service /etc/systemd/system/cfv-calib-b.service
systemctl daemon-reload 2>/dev/null
echo "CLEANUP_UNITS_LEFT=$(ls -1 /etc/systemd/system/cfv-calib-* 2>/dev/null | wc -l | tr -d ' ')"
echo "CLEANUP_WANTS_LEFT=$(ls -1d /etc/systemd/system/multi-user.target.wants/cfv-calib-* 2>/dev/null | wc -l | tr -d ' ')"
'@
    $r = Invoke-WslFile -Tag 'fatalcal' -User 'root' -Body $body
    foreach ($ln in @($r.Out -split "`r?`n" | Where-Object { $_ -match '=' })) { W "   CAL> $ln" }
    $t = $r.Out

    $ctlRc  = (Val $t 'CTL_ENABLE_RC')
    $ctlEn  = (Val $t 'CTL_ISENABLED')
    Register-Control -Id 'FR.CTL.KNOWN' -Name 'the calibration can produce a known-correct ENABLED result' `
        -Fired (($ctlRc -eq '0') -and ($ctlEn -eq 'enabled')) `
        -Evidence "with no block: systemctl enable rc=$ctlRc, is-enabled='$ctlEn' (must be 0 and 'enabled'). If this half cannot pass, the subject half below proves nothing -- the rig would simply be broken." | Out-Null

    $subjRc = (Val $t 'SUBJ_ENABLE_RC')
    $subjEn = (Val $t 'SUBJ_ISENABLED')
    Record 'FR.C1' 'INJECTION SHAPE: the enable FAILS and the unit is left NOT enabled' `
        $(if (($subjRc -ne '0') -and ($subjEn -ne 'enabled')) { 'PASS' } else { 'FAIL' }) `
        "with the block: systemctl enable rc=$subjRc (must be nonzero), enable said '$(Val $t 'SUBJ_ENABLE_OUT')', is-enabled='$subjEn' (must not be 'enabled'). This is exactly the field failure the read-back was written for: enable returns nonzero, the shipped or-true swallows it, and the unit is not enabled."

    Record 'FR.C2' 'the block is a directory, which is what makes the symlink impossible' `
        $(if ((Val $t 'BLOCK_IS_DIR') -eq 'yes') { 'PASS' } else { 'FAIL' }) `
        "BLOCK_IS_DIR=$(Val $t 'BLOCK_IS_DIR')"

    Record 'FR.C3' 'COLLATERAL CONTROL: a different unit still enables in the same directory' `
        $(if (((Val $t 'COLL_ENABLE_RC') -eq '0') -and ((Val $t 'COLL_ISENABLED') -eq 'enabled')) { 'PASS' } else { 'FAIL' }) `
        "second unit with the block in place: enable rc=$(Val $t 'COLL_ENABLE_RC'), is-enabled='$(Val $t 'COLL_ISENABLED')'. The injection must be targeted at ONE unit; an injection that breaks every enable would abort the install somewhere else and prove nothing about this fatal."

    Record 'FR.C4' 'the calibration left no trace of itself' `
        $(if (((Val $t 'CLEANUP_UNITS_LEFT') -eq '0') -and ((Val $t 'CLEANUP_WANTS_LEFT') -eq '0')) { 'PASS' } else { 'FAIL' }) `
        "scratch unit files left = $(Val $t 'CLEANUP_UNITS_LEFT'), scratch wants entries left = $(Val $t 'CLEANUP_WANTS_LEFT'). Both must be 0 or the box under test is no longer clean."

    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'FATAL'
    Finish 0
}

# =============================================================================
if ($Mode -eq 'Inject') {
    Section '1. Place the block on the real unit path, and read it back'

    $body = @"
set +e
echo "PRE_WANTS_EXISTS=`$( [ -e $WANTS ] && echo yes || echo no )"
echo "PRE_WANTS_ISLINK=`$( [ -L $WANTS ] && echo yes || echo no )"
echo "PRE_UNIT_FILE=`$( [ -f /etc/systemd/system/clawfactory-egress-refresh.service ] && echo present || echo absent )"
echo "PRE_ISENABLED=`$(systemctl is-enabled clawfactory-egress-refresh.service 2>&1 | head -1)"
echo "PRE_OTHER_CF_WANTS=`$(ls -1 /etc/systemd/system/multi-user.target.wants/clawfactory-* 2>/dev/null | wc -l | tr -d ' ')"
rm -f $WANTS
mkdir -p $WANTS
echo "POST_WANTS_ISDIR=`$( [ -d $WANTS ] && echo yes || echo no )"
echo "POST_WANTS_ISLINK=`$( [ -L $WANTS ] && echo yes || echo no )"
echo "POST_WANTS_LS=`$(ls -ld $WANTS 2>&1 | tr -s ' ' | cut -c1-160)"
echo "READER_CTL=`$( [ -d /etc/systemd/system/multi-user.target.wants ] && echo present || echo absent )"
"@
    $r = Invoke-WslFile -Tag 'fatalinj' -User 'root' -Body $body
    foreach ($ln in @($r.Out -split "`r?`n" | Where-Object { $_ -match '=' })) { W "   INJ> $ln" }
    $t = $r.Out

    Register-Control -Id 'FR.I.CTL' -Name 'the distro reader can see a directory that IS present' `
        -Fired ((Val $t 'READER_CTL') -eq 'present') `
        -Evidence "multi-user.target.wants itself reads as $(Val $t 'READER_CTL'). A reader that cannot see that directory cannot be trusted about what is inside it." | Out-Null

    Record 'FR.I1' 'THE FAULT LANDED: a directory now occupies the enable target path' `
        $(if (((Val $t 'POST_WANTS_ISDIR') -eq 'yes') -and ((Val $t 'POST_WANTS_ISLINK') -eq 'no')) { 'PASS' } else { 'FAIL' }) `
        "$WANTS is now a directory=$(Val $t 'POST_WANTS_ISDIR'), symlink=$(Val $t 'POST_WANTS_ISLINK'). ls: $(Val $t 'POST_WANTS_LS'). A fault injection that does not inject scores a false pass and looks exactly like a working control."

    Record 'FR.I2' 'the starting state was a machine with no ClawFactory installed' 'INFO' `
        "before injection: wants entry existed=$(Val $t 'PRE_WANTS_EXISTS') (link=$(Val $t 'PRE_WANTS_ISLINK')), unit file=$(Val $t 'PRE_UNIT_FILE'), is-enabled='$(Val $t 'PRE_ISENABLED')', other clawfactory-* wants entries=$(Val $t 'PRE_OTHER_CF_WANTS'). The keep-Linux uninstall removed the unit; the distro and clawuser remain, which is the documented state of that branch and a realistic machine to re-install onto."

    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'FATAL'
    Finish 0
}

# =============================================================================
if ($Mode -eq 'RunInstall') {
    Section '1. Confirm the fault is still in place immediately before the install'
    $pre = Invoke-WslFile -Tag 'fatalpre' -User 'root' -Body @"
set +e
echo "WANTS_ISDIR=`$( [ -d $WANTS ] && echo yes || echo no )"
echo "READER_CTL=`$( [ -d /etc/systemd/system/multi-user.target.wants ] && echo present || echo absent )"
"@
    foreach ($ln in @($pre.Out -split "`r?`n" | Where-Object { $_ -match '=' })) { W "   PRE> $ln" }
    $armed = Require-Precondition -Id 'FR.PRE' -Name 'the injected fault is in place at install time' `
        -Met ((Val $pre.Out 'WANTS_ISDIR') -eq 'yes') `
        -Reason 'an install run without the fault would simply succeed, and a passing install is not evidence about a fatal that never had a reason to fire'
    if (-not $armed) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'FATAL'; Finish 4 }

    Register-Control -Id 'FR.R.CTL.READER' -Name 'the distro reader answers present for something that IS present' `
        -Fired ((Val $pre.Out 'READER_CTL') -eq 'present') `
        -Evidence "multi-user.target.wants = $(Val $pre.Out 'READER_CTL')" | Out-Null

    Section '2. Run the v1.4.1 installer'
    if (-not (Test-Path $CombinedExe)) {
        Record 'FR.R0' 'the artifact is on the box' 'FAIL' "missing at $CombinedExe"
        Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'FATAL'; Finish 2
    }
    W "artifact sha256: $((Get-FileHash $CombinedExe -Algorithm SHA256).Hash.ToLower())"
    Remove-Item -LiteralPath 'C:\ProgramData\ClawFactory\install-result.txt' -Force -ErrorAction SilentlyContinue

    $sw = [Diagnostics.Stopwatch]::StartNew()
    Start-Process -FilePath $CombinedExe -ArgumentList `
        '/SILENT','/SUPPRESSMSGBOXES','/NORESTART','/LOG=C:\cfv\fatal-inno.log',"/PROVIDER=$Provider" -Wait
    $sw.Stop()
    W "installer returned after $([int]$sw.Elapsed.TotalMinutes) min ($([int]$sw.Elapsed.TotalSeconds)s)"

    Section '3. The install ABORTED, and it aborted with its own named message'
    $resultFile = 'C:\ProgramData\ClawFactory\install-result.txt'
    $verdict = if (Test-Path $resultFile) { (Get-Content $resultFile -Raw).Trim() } else { '(install-result.txt ABSENT)' }
    W "install-result.txt: $verdict"

    $logPath = 'C:\ProgramData\ClawFactory\install.log'
    $log = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { '' }
    W "install.log length: $($log.Length) chars"

    Assert-Searchable -Id 'FR.R.CTL.LOG' -Name 'the install log' `
        -PositiveMarkerFound ($log -match 'Step 15g \[Guard 3\]') `
        -MarkerDescription 'the Guard 3 step banner, proving the install reached the step under test and that this log is readable' | Out-Null

    Record 'FR.R1' 'ROW: the install ABORTED rather than finishing' `
        $(if ($verdict -match 'failure') { 'PASS' } else { 'FAIL' }) `
        "install-result.txt='$verdict'. This is setup.ps1's own honest verdict; the Inno exit code is not (the .iss has no RaiseException on setup.ps1's exit, which is why install-result.txt exists)."

    # VERBATIM. Two literals, both quoted from the shipped files, matched with
    # Contains rather than a regex so no pattern can be loose enough to match a
    # paraphrase of the message.
    $innerHit = $log.Contains($FATAL_INNER)
    $tailHit  = $log.Contains($FATAL_TAIL)
    $outerHit = $log.Contains($FATAL_OUTER)

    foreach ($ln in @($log -split "`r?`n" | Where-Object { $_ -match 'install-read-fetch\] FATAL|Failed to install the read-fetch|is-enabled|INSTALLER_DONE' })) { W "   LOG> $ln" }

    Record 'FR.R2' 'the inner fatal from install-read-fetch.sh appears VERBATIM' `
        $(if ($innerHit -and $tailHit) { 'PASS' } else { 'FAIL' }) `
        "opening literal present=$innerHit, closing literal present=$tailHit. Matched with String.Contains against text copied from resources/install-read-fetch.sh line 386, not with a regex."

    Record 'FR.R3' "setup.ps1's own refusal appears VERBATIM" `
        $(if ($outerHit) { 'PASS' } else { 'FAIL' }) `
        "literal present=$outerHit. Copied from setup.ps1's Step-InstallReadFetch throw."

    Record 'FR.R4' 'the reason travelled from the shell into the Windows-side verdict' `
        $(if ($verdict -match 'read-fetch|Guard 3') { 'PASS' } else { 'INFO' }) `
        "install-result.txt='$verdict'. A fatal that aborts but reports no reason leaves the user with a failed install and nothing to act on."

    Section '4. The state the abort left behind'
    $post = Invoke-WslFile -Tag 'fatalpost' -User 'root' -Body @'
set +e
echo "UNIT_FILE=$( [ -f /etc/systemd/system/clawfactory-egress-refresh.service ] && echo present || echo absent )"
echo "UNIT_ISENABLED=$(systemctl is-enabled clawfactory-egress-refresh.service 2>&1 | head -1)"
if nft list table inet clawfactory >/dev/null 2>&1; then echo "NFT_TABLE=present"; else echo "NFT_TABLE=absent"; fi
echo "NFT_TERMINAL_DROP=$(nft list table inet clawfactory 2>/dev/null | grep -cE 'drop$|policy drop')"
echo "CF_UNITS_ENABLED=$(systemctl list-unit-files 'clawfactory-*' --state=enabled --no-legend 2>/dev/null | wc -l | tr -d ' ')"
echo "CF_UNITS_ENABLED_LIST=$(systemctl list-unit-files 'clawfactory-*' --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
echo "ETC_CLAWFACTORY=$( [ -d /etc/clawfactory ] && echo present || echo absent )"
echo "FETCHCTL=$( [ -f /usr/local/sbin/clawfactory-fetchctl.js ] && echo present || echo absent )"
# Is the machine left FAIL-CLOSED or FAIL-OPEN? Six attempts as uid 1000, and a
# root control that must succeed, so "everything is unreachable" cannot be
# mistaken for "the agent is denied".
b=0; for i in 1 2 3 4 5 6; do
  if runuser -u clawuser -- timeout 6 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' 2>/dev/null; then :; else b=$((b+1)); fi
done
echo "AGENT_BLOCKED=$b of 6"
r=0; for i in 1 2 3; do
  if timeout 6 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' 2>/dev/null; then r=$((r+1)); fi
done
echo "ROOT_REACHED=$r of 3"
echo "READER_CTL=$( [ -d /etc ] && echo present || echo absent )"
'@
    foreach ($ln in @($post.Out -split "`r?`n" | Where-Object { $_ -match '=' })) { W "   POST> $ln" }
    $p = $post.Out

    Register-Control -Id 'FR.R.CTL.ROOT' -Name 'the reachability instrument can reach the network at all' `
        -Fired ((Val $p 'ROOT_REACHED') -match '^[1-3] of 3') `
        -Evidence "root reached 1.1.1.1:443 on $(Val $p 'ROOT_REACHED') attempts. Without this, 'the agent is blocked' and 'the box has no network' are the same reading." | Out-Null

    Record 'FR.R5' 'the boot refresh unit is NOT enabled, which is the whole point' `
        $(if ((Val $p 'UNIT_ISENABLED') -ne 'enabled') { 'PASS' } else { 'FAIL' }) `
        "unit file=$(Val $p 'UNIT_FILE'), is-enabled='$(Val $p 'UNIT_ISENABLED')'. The install refused to finish precisely because this is not 'enabled'."

    Record 'FR.R6' 'THE ABORT IS FAIL-CLOSED: the agent has no route out' `
        $(if ((Val $p 'AGENT_BLOCKED') -eq '6 of 6') { 'PASS' } else { 'FAIL' }) `
        "uid 1000 blocked on $(Val $p 'AGENT_BLOCKED') attempts to 1.1.1.1:443, while root reached it on $(Val $p 'ROOT_REACHED'). nft table=$(Val $p 'NFT_TABLE') with $(Val $p 'NFT_TERMINAL_DROP') terminal-drop line(s). An install that fails loudly but leaves the agent with an open route would be a worse outcome than the false panel this fatal exists to prevent."

    Record 'FR.R7' 'what the aborted install left configured, stated rather than implied' 'INFO' `
        "clawfactory-* units enabled = $(Val $p 'CF_UNITS_ENABLED') [$(Val $p 'CF_UNITS_ENABLED_LIST')]; /etc/clawfactory=$(Val $p 'ETC_CLAWFACTORY'); fetchctl.js=$(Val $p 'FETCHCTL'). Guard 3's control tool is the thing the user would have driven from the Web access panel."

    Section '5. The Windows side after the abort'
    $studio = [bool](Test-Path -LiteralPath "$env:LOCALAPPDATA\Programs\ClawFactory Studio")
    $studioLog = if (Test-Path 'C:\cfv\fatal-inno.log') { Get-Content 'C:\cfv\fatal-inno.log' -Raw } else { '' }
    foreach ($ln in @($studioLog -split "`r?`n" | Where-Object { $_ -match 'Studio:' })) { W "   INNO> $ln" }

    Record 'FR.R8' 'Studio was NOT installed on top of a failed core' `
        $(if ($studioLog -match 'core install did not report success') { 'PASS' } else { 'FAIL' }) `
        "the Inno log records its own gate decision: $((@($studioLog -split "`r?`n" | Where-Object { $_ -match 'core install did not report success' })) -join ' '). Studio directory present=$studio (a directory left from an earlier install would still read present here, so the LOG LINE is the assertion and this is context)."

    $regs = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
              ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue) } |
              Where-Object { $_.DisplayName -like '*ClawFactory*' })
    Record 'FR.R9' 'the failed install is still uninstallable from Settings' `
        $(if (@($regs).Count -ge 1) { 'INFO' } else { 'INFO' }) `
        "uninstall registry entries after the aborted install = $(@($regs).Count) [$(@($regs | ForEach-Object { $_.DisplayName }) -join '; ')]. Inno copies files and writes its registry entry BEFORE [Run] executes setup.ps1, and the .iss raises no exception on setup.ps1's exit code, so a failed core leaves an installed-looking entry whose install-result.txt says failure. The user can reach Uninstall, which is the good half; the entry is the honest cost of Inno's ordering and is recorded here rather than discovered later."

    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'FATAL'
    Finish 0
}
