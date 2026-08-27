<#
  v1.4.4 validation: EXECUTE THE SHIPPED POWERSHELL WRAPPERS, not their payloads.

  WHY THIS FILE EXISTS
  --------------------
  Until 2026-08-27 the suite tested the bash the Windows scripts BUILD and never
  the Windows scripts that build it. validation/interim-v135-switchprovider.ps1
  extracts the firewall block of resources/switch-provider.ps1 as rendered bash
  and runs that; validation/sp-prefix-fw.sh says so in its own first line. So a
  defect in a wrapper's string handling was invisible to the suite BY
  CONSTRUCTION, and the first run that executed the wrappers found two
  ship-blockers in the same hour:

    * clawfactory-stop.ps1 -- both WSL lines died on a quoting fault, the script
      exited 0, and it told the user the gateway was stopped. True on every
      release from v1.0.
    * switch-provider.ps1 -- four unescaped $baseHosts inside comments inside an
      expandable here-string, under StrictMode, killing it for every provider.

  Neither is exotic. Both are what happens when a script is parsed and never run.

  A SHARPER VERSION OF THE SAME LESSON, RECORDED SO IT IS NOT REPEATED HERE
  -------------------------------------------------------------------------
  The retired v1.0.x probes DID execute the kill switch:
    scripts/probe-v1039-validation.ps1:237 and probe-v1047-validation.ps1:250
    `& powershell -File $ks 2>&1 | Select-Object -Last 8 | Out-String`
  They kept the LAST EIGHT LINES and asserted nothing. The kill switch printed
  its bash syntax errors early and its false success banner last, so the tail
  those probes preserved was exactly the part that was untrue. Executing a script
  is necessary and is not sufficient: every row below asserts on a NAMED string or
  a MEASURED state, and never on "it ran".

  WHAT IS AND IS NOT COVERED, STATED SO THE PASS LINE IS NOT READ AS MORE
  -----------------------------------------------------------------------
    EXECUTED HERE : smoke-test, launcher, clawfactory-stop (plus a fault-injected
                    negative control), switch-provider (ollama, the only provider
                    needing no credential) plus its fail-closed toolchain guard,
                    post-install (-Provider later, the branch that reads no
                    credential), bootstrap (documented idempotent), and
                    clawfactory-grants by dot-source, the way launcher.ps1 loads it.
    NOT EXECUTED  : rename-agent.ps1, which blocks on a modal MessageBox and cannot
                    complete unattended -- substitute named in WR.10.
                    uninstall.ps1, whose execution is destructive by definition and
                    is the subject of its own box -- see WR.11.
  Both are recorded as INFO rows carrying their reason. A wrapper that was skipped
  and a wrapper that passed must never look the same in a results file.
#>
param(
    [string]$Transcript = 'C:\cfv\wrappers-out.txt',
    [string]$AppDir     = 'C:\Program Files\ClawFactory',
    [string]$WorkDir    = 'C:\cfv\wrappers',
    # switch-provider -Provider ollama REPLACES the active provider and is not
    # undone by this phase. Left opt-in so it cannot silently reconfigure a box
    # that later phases still need. See WR.5.
    [switch]$RunProviderSwitch
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'ClawFactory v1.4.4 shipped-wrapper execution' `
    -Transcript $Transcript -Sentinel 'WRAPPERS_COMPLETE'

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

$chan = Test-WslChannel
Register-Control -Id 'WR.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) {
    W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'
    Complete-Phase -ResultsJson 'C:\cfv\wrappers-results.json' -MarkerPrefix 'WRAPPERS'
}

# --- readers -----------------------------------------------------------------
# Payloads handed to wsl.exe carry NO double quotes. PowerShell 5.1 wraps a native
# argument containing spaces in double quotes and does not escape the ones already
# inside it, which is the defect this phase exists to catch; the instrument must
# not commit it.
function Wsl([string]$b) { (& wsl.exe -d Ubuntu -u root -- bash -lc $b 2>&1 | Out-String).Trim() }
function WslScript([string]$s) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s.Replace("`r`n", "`n").Replace("`r", "`n")))
    return ((& wsl.exe -d Ubuntu -u root -- bash -lc "echo $b64 | base64 -d | bash" 2>&1 | Out-String).Trim())
}
# Only 2xx counts as UP: 8787 is the root-owned gating proxy and answers 502 while
# the gateway behind it is dead. Any-HTTP-response-means-up voided a phase on
# 2026-08-27 and is the reason this phase requires two readers to agree.
function GwHttp {
    try { return [int](Invoke-WebRequest -Uri 'http://127.0.0.1:8787/' -TimeoutSec 6 -UseBasicParsing -ErrorAction Stop).StatusCode }
    catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }; return 0 }
}
function GwProcs {
    $m = [regex]::Match((Wsl 'pgrep -u clawuser -c -f ''[o]penclaw'' 2>/dev/null; true'), '(?m)^\s*(\d+)\s*$')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return -1
}
function GwState { "http=$(GwHttp) procs=$(GwProcs)" }
function GwUp    { $h = GwHttp; $p = GwProcs; return (($h -ge 200 -and $h -lt 300) -and $p -gt 0) }
function GwDown  { $h = GwHttp; $p = GwProcs; return ((-not ($h -ge 200 -and $h -lt 300)) -and $p -eq 0) }
function WaitUp([int]$sec = 240) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $sec) { if (GwUp) { return $true }; Start-Sleep -Seconds 5 }
    return $false
}
function RunPs([string]$path, [string[]]$argv) {
    $o = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path @argv 2>&1
    $rc = $LASTEXITCODE
    return [pscustomobject]@{ Code = $rc; Text = ($o | Out-String) }
}

# --- WR.1 smoke-test.ps1 -----------------------------------------------------
Section 'WR.1  smoke-test.ps1'
$smoke = RunPs "$AppDir\resources\smoke-test.ps1" @()
W $smoke.Text.Trim()
$smokeSummary = [regex]::Match($smoke.Text, '(\d+)\s+pass,\s*(\d+)\s+fail,\s*(\d+)\s+skip')
Register-Control -Id 'WR.1.CTL' -Name 'smoke-test.ps1 printed its own summary line, so a silent death is distinguishable from a clean run' `
    -Fired $smokeSummary.Success -Evidence $smokeSummary.Value | Out-Null
Record 'WR.1' 'smoke-test.ps1 executes from its installed form and reports zero failures' `
    $(if ($smokeSummary.Success -and [int]$smokeSummary.Groups[2].Value -eq 0) { 'PASS' }
      elseif ($smokeSummary.Success) { 'FAIL' } else { 'VOID' }) `
    ("exit=$($smoke.Code) summary=$($smokeSummary.Value). NOTE: a lone check-9 nft FAIL is the documented clawuser-cannot-read-nft false positive and needs a root-context nft verify before it counts.")

# --- WR.2 / WR.3 the kill switch, and the launcher that undoes it -------------
Section 'WR.2/WR.3  clawfactory-stop.ps1 and launcher.ps1'
if (-not (GwUp)) { $null = RunPs "$AppDir\resources\launcher.ps1" @(); $null = WaitUp }
$upBefore = GwUp
W "WR.3 before: $(GwState)"
Register-Control -Id 'WR.3.CTL' -Name 'the gateway was UP before the kill switch ran, by BOTH readers' `
    -Fired $upBefore -Evidence (GwState) | Out-Null
if (Require-Precondition -Id 'WR.3.PRE' -Name 'a running gateway to stop' -Met $upBefore `
        -Reason 'the kill switch cannot be shown to stop anything against a box where nothing was running; that reads as a pass and proves nothing') {
    $stop = RunPs "$AppDir\resources\clawfactory-stop.ps1" @()
    W $stop.Text.Trim()
    Start-Sleep -Seconds 5
    $down = GwDown
    W "WR.3 after: $(GwState)"
    Record 'WR.3' 'clawfactory-stop.ps1 actually stops the gateway and any agent turn' `
        $(if ($down) { 'PASS' } else { 'FAIL' }) `
        "exit=$($stop.Code) after=$(GwState) claimed-stopped=$($stop.Text -match 'Everything is stopped') syntax-error-present=$($stop.Text -match 'syntax error')"

    # WR.2: the launcher is the only supported way back up, and this is the only
    # point in a run where a genuinely down gateway exists to test it against.
    $lau = RunPs "$AppDir\resources\launcher.ps1" @()
    W $lau.Text.Trim()
    $backUp = WaitUp
    Record 'WR.2' 'launcher.ps1 STARTS a stopped gateway rather than reporting ALREADY_RUNNING' `
        $(if ($backUp) { 'PASS' } else { 'FAIL' }) `
        "exit=$($lau.Code) after=$(GwState); the log at C:\ProgramData\ClawFactory\launcher.log must show [STARTED], not [ALREADY_RUNNING]"
    $llog = 'C:\ProgramData\ClawFactory\launcher.log'
    if (Test-Path $llog) { W ((Get-Content $llog -Tail 4) -join ' | ') }
}

# --- WR.4 the kill switch must not be able to claim a success it did not earn -
Section 'WR.4  clawfactory-stop.ps1 fault injection'
# Point every WSL call at a distro that does not exist. The FIX is not only that
# the script stops things, it is that it reports what it actually stopped. The
# fault-landed control is the COULD NOT RUN THIS STEP text, which the pre-v1.4.4
# script had no code path able to produce.
$broken = Join-Path $WorkDir 'clawfactory-stop.BROKEN.ps1'
$srcTxt = Get-Content -Raw "$AppDir\resources\clawfactory-stop.ps1"
$brkTxt = $srcTxt.Replace("`$Distro = 'Ubuntu'", "`$Distro = 'Ubuntu-NO-SUCH-DISTRO'")
[IO.File]::WriteAllText($broken, $brkTxt, (New-Object Text.UTF8Encoding($false)))
Register-Control -Id 'WR.4.CTL' -Name 'the fault was actually injected (the copy names a distro that does not exist)' `
    -Fired (($brkTxt -ne $srcTxt) -and ($brkTxt -match 'Ubuntu-NO-SUCH-DISTRO')) `
    -Evidence 'a fault injection that does not inject scores a false pass and looks exactly like a working control' | Out-Null
$bk = RunPs $broken @()
W $bk.Text.Trim()
Record 'WR.4' 'with every sandbox call failing, clawfactory-stop.ps1 refuses to claim success' `
    $(if (($bk.Text -match 'COULD NOT RUN THIS STEP') -and ($bk.Text -notmatch 'Everything is stopped') -and ($bk.Code -ne 0)) { 'PASS' } else { 'FAIL' }) `
    "exit=$($bk.Code) (expected non-zero) reported-failure=$($bk.Text -match 'COULD NOT RUN THIS STEP') claimed-success=$($bk.Text -match 'Everything is stopped')"

# --- WR.5 / WR.6 switch-provider.ps1 -----------------------------------------
Section 'WR.5/WR.6  switch-provider.ps1'
$FwProbe = @'
echo FW_TABLE=$(nft list tables 2>/dev/null | grep -c clawfactory)
echo FW_ALLOWED_V4=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)
echo FW_TOOLCHAIN_V4=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)
echo FW_SEED_HOSTS=$(wc -w < /etc/clawfactory/base-hosts.seed 2>/dev/null || echo NA)
if nft list set inet clawfactory this_set_cannot_exist >/dev/null 2>&1; then echo FW_CTL_FAKESET=FOUND_BAD; else echo FW_CTL_FAKESET=ok_fake_set_not_found; fi
'@
if (-not $RunProviderSwitch) {
    Record 'WR.5' 'switch-provider.ps1 NOT EXECUTED in this run' 'INFO' `
        'Run this phase with -RunProviderSwitch to execute it. Ollama is the only provider needing no credential, and switching to it REPLACES the active provider, which would confound any later phase on this box. Recorded as INFO rather than omitted, because a wrapper that was skipped and a wrapper that passed must not look the same.'
    Record 'WR.6' 'the fail-closed toolchain guard NOT EXERCISED in this run' 'INFO' 'rides WR.5; see above'
} else {
    $fwBefore = WslScript $FwProbe
    W "WR.5 firewall before: $($fwBefore -replace "`n", ' ')"
    Register-Control -Id 'WR.5.CTL' -Name 'the firewall reader discriminates (a set that cannot exist is not found)' `
        -Fired ($fwBefore -match 'ok_fake_set_not_found') -Evidence 'an uncontrolled nft read cannot tell an absent rule from a failed listing' | Out-Null
    $sp = RunPs "$AppDir\resources\switch-provider.ps1" @('-Provider', 'ollama')
    W $sp.Text.Trim()
    $fwAfter = WslScript $FwProbe
    W "WR.5 firewall after:  $($fwAfter -replace "`n", ' ')"
    Record 'WR.5' 'switch-provider.ps1 builds its firewall payload and completes, for a provider needing no credential' `
        $(if (($sp.Text -notmatch 'VariableIsUndefined') -and ($sp.Text -match 'toolchain guard') -and ($fwAfter -match 'FW_TABLE=1')) { 'PASS' } else { 'FAIL' }) `
        "exit=$($sp.Code) strictmode-death=$($sp.Text -match 'VariableIsUndefined') guard-ran=$($sp.Text -match 'toolchain guard')"
    Record 'WR.5b' 'switch-provider.ps1 does not print an earned-looking Ollama success line when Ollama is absent' `
        $(if ($sp.Text -match 'command not found|Ollama is NOT installed|is not present') {
              $(if ($sp.Text -match '\[x\] Ollama running') { 'FAIL' } else { 'PASS' })
          } else { 'INFO' }) `
        'the pre-v1.4.4 script printed "[x] Ollama running with model ..." on the line after the shell said ollama: command not found'

    # WR.6: without this the guard being silent and the guard being absent are
    # indistinguishable. Make a BASE host look like a toolchain host and require
    # a refusal.
    W (WslScript @'
set -e
TS=/usr/local/sbin/clawfactory-toolchain.sh
if [ ! -x $TS ]; then echo WR6_PRECONDITION_ABSENT; exit 0; fi
cp -a $TS /root/toolchain.real
printf '#!/bin/bash\nif [ x$1 = x--list-hosts ]; then echo openclaw.ai; exit 0; fi\nexec /root/toolchain.real $@\n' > $TS
chmod 0755 $TS
echo WR6_SHADOW_SAYS=$($TS --list-hosts)
'@)
    $sp2 = RunPs "$AppDir\resources\switch-provider.ps1" @('-Provider', 'ollama')
    W $sp2.Text.Trim()
    $fwGuard = WslScript $FwProbe
    Record 'WR.6' 'the fail-closed toolchain guard refuses to write a toolchain host into the unrevocable allowlist' `
        $(if ($sp2.Text -match 'is a toolchain host and would be written') { 'PASS' } else { 'FAIL' }) `
        "exit=$($sp2.Code) firewall-after-refusal: $($fwGuard -replace "`n", ' ')"
    W (WslScript @'
TS=/usr/local/sbin/clawfactory-toolchain.sh
if [ -f /root/toolchain.real ]; then cp -a /root/toolchain.real $TS; rm -f /root/toolchain.real; echo WR6_SHADOW_REMOVED; else echo WR6_NOTHING_TO_RESTORE; fi
echo WR6_RESTORED_SAYS=$($TS --list-hosts 2>/dev/null | head -3 | tr '\n' ' ')
'@)
}

# --- WR.7 post-install.ps1 ---------------------------------------------------
Section 'WR.7  post-install.ps1'
# -Provider later is the branch that reads no credential and sets no model, so it
# executes the wrapper without reconfiguring the box. That is the substitute, and
# it is a narrower test than the real path: it does not exercise the stdin key
# hand-off, and this row does not claim it does.
$pi = RunPs "$AppDir\resources\post-install.ps1" @('-Provider', 'later')
W $pi.Text.Trim()
Record 'WR.7' 'post-install.ps1 executes from its installed form (-Provider later, the no-credential branch)' `
    $(if ($pi.Code -eq 0 -and $pi.Text -notmatch 'VariableIsUndefined|syntax error') { 'PASS' } else { 'FAIL' }) `
    "exit=$($pi.Code). Does NOT cover the credential branch, which needs a provider key."

# --- WR.8 bootstrap.ps1 ------------------------------------------------------
Section 'WR.8  bootstrap.ps1'
# Safe to re-run: the file documents itself idempotent (agent.md overwritten
# atomically, agent-name.txt not overwritten once present, checkpoint guarded).
$bs = RunPs "$AppDir\resources\bootstrap.ps1" @()
W $bs.Text.Trim()
Record 'WR.8' 'bootstrap.ps1 executes from its installed form and is re-runnable' `
    $(if ($bs.Code -eq 0 -and $bs.Text -notmatch 'VariableIsUndefined|syntax error') { 'PASS' } else { 'FAIL' }) `
    "exit=$($bs.Code)"

# --- WR.9 clawfactory-grants.ps1 --------------------------------------------
Section 'WR.9  clawfactory-grants.ps1 (dot-source, the way launcher.ps1 loads it)'
$grantProbe = Join-Path $WorkDir 'grantprobe.ps1'
[IO.File]::WriteAllText($grantProbe, @"
`$ErrorActionPreference = 'Stop'
try { . '$AppDir\resources\clawfactory-grants.ps1'; "GRANTS_OK=`$((Get-Command -CommandType Function | Measure-Object).Count)" } catch { "GRANTS_FAIL=`$(`$_.Exception.Message)" }
"@, (New-Object Text.UTF8Encoding($false)))
$gp = RunPs $grantProbe @()
W $gp.Text.Trim()
$badLib = Join-Path $WorkDir 'grants-malformed.ps1'
[IO.File]::WriteAllText($badLib, "function Broken { if (`$true) { `n", (New-Object Text.UTF8Encoding($false)))
$badProbe = Join-Path $WorkDir 'grantprobe-bad.ps1'
[IO.File]::WriteAllText($badProbe, @"
`$ErrorActionPreference = 'Stop'
try { . '$badLib'; 'CTL_BAD_DOTSOURCE_OK=True_control_did_NOT_fire' } catch { 'CTL_BAD_DOTSOURCE_OK=False_control_fired' }
"@, (New-Object Text.UTF8Encoding($false)))
$bp = RunPs $badProbe @()
W $bp.Text.Trim()
Register-Control -Id 'WR.9.CTL' -Name 'a deliberately malformed library refuses to dot-source, so a clean load means the file is sound' `
    -Fired ($bp.Text -match 'control_fired') -Evidence $bp.Text.Trim() | Out-Null
Record 'WR.9' 'clawfactory-grants.ps1 dot-sources cleanly and defines its functions' `
    $(if ($gp.Text -match 'GRANTS_OK=(\d+)' -and [int]$Matches[1] -gt 20) { 'PASS' } else { 'FAIL' }) `
    $gp.Text.Trim()

# --- WR.10 / WR.11 the two that are not executed, and why --------------------
Section 'WR.10/WR.11  wrappers not executable in an unattended phase'
Record 'WR.10' 'rename-agent.ps1 NOT EXECUTED: it blocks on a modal MessageBox' 'INFO' `
    'It calls [System.Windows.Forms.MessageBox]::Show and does not return until a human clicks OK, so an unattended phase that ran it would hang rather than fail. It also builds NO payload for another interpreter, so it is outside the defect class this phase exists for. SUBSTITUTE: an AST parse plus an assertion on the message text, and one by-hand click in the operator checklist.'
Record 'WR.11' 'uninstall.ps1 NOT EXECUTED here: running it is the destruction it performs' 'INFO' `
    'Its execution ends the install this phase is measuring. It is covered on its own box by interim-v141-uninstall.ps1, through the real dialog, against a held before-state. Named here so that its absence from this phase is a decision on the record rather than a gap.'

Complete-Phase -ResultsJson 'C:\cfv\wrappers-results.json' -MarkerPrefix 'WRAPPERS'
