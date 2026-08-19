<#
  v1.3.5 validation: THE SWITCH-PROVIDER GUARD 3 DEFEAT (card #258).

  WHAT IS BEING TESTED, AND WHY IT IS AN A/B ON ONE BOX
  -----------------------------------------------------
  switch-provider.ps1 FLUSHES @allowed_ipv4 and rebuilds it from a host list.
  Until 1.3.5 that list was a stale 16-host mirror of setup.ps1's $baseHosts,
  seven of them toolchain hosts. So one click on the shipped Start Menu item
  "Switch AI Provider" re-seeded the toolchain hosts into the set nothing can
  revoke, persisted them to allowed-ips.txt, and survived reboot. After that the
  toolchain toggle was permanently defeated AND THE PANEL STILL REPORTED IT AS
  OFF.

  The demonstration and the fix are measured on the SAME BOX, in the same run,
  with the toggle held OFF throughout and only the script text differing. Two
  boxes would have introduced a second variable (DNS, timing, provider addresses)
  into the one comparison the session exists to make. It also happens to be
  self-cleaning: the FIXED script's own flush removes the pollution the pre-fix
  arm created, which is why the arms can run in this order at all.

  THE ARMS
    PRE  = validation/sp-prefix-fw.sh, rendered from git commit 9710c5a so it is
           provably the shipped 1.3.4 text rather than a hand-copy.
    POST = rendered ON THIS VM from the INSTALLED
           {app}\resources\switch-provider.ps1, so the fixed arm tests the
           artifact that was actually installed and not a copy of the repo.

  CALIBRATION, IN BOTH DIRECTIONS, PER CARD #257
  -----------------------------------------------
  Every reachability measurement carries BOTH halves in the same run: a
  destination that MUST connect (the provider route, which no switch may affect)
  and a destination that MUST be refused (a site nobody allowlisted). A probe
  proven only against a must-fail target passes whether it is measuring anything
  or not, and that error produced a phantom ship-blocker last session.

  L17: a new probe inherits none of the preconditions of the phases beside it.
#>
param(
    [string]$Transcript = 'C:\cfv\switchprovider-out-probe.txt',
    [string]$AppDir     = 'C:\Program Files\ClawFactory',
    [switch]$PostReboot
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

$tag = if ($PostReboot) { 'POSTREBOOT' } else { 'PRE' }
Start-Phase -Name "ClawFactory v1.3.5 switch-provider / Guard 3 defeat, pass=$tag" `
    -Transcript $Transcript -Sentinel 'SWITCHPROVIDER_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id "SP.CHAN.$tag" -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) {
    W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'
    Complete-Phase -ResultsJson "C:\cfv\switchprovider-results-$tag.json" -MarkerPrefix "SWITCHPROVIDER_$tag"
}

# The seven toolchain hostnames this whole card is about. Held here as the
# probe's OWN copy and compared against what the product reports, per the
# harness rule that an uncompared copy is a second stale list.
$TOOLCHAIN7 = @('api.github.com','github.com','raw.githubusercontent.com','codeload.github.com','clawhub.ai','api.clawhub.ai','registry.npmjs.org')

$ProbeFn = @'
probe() {
  if timeout 10 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then echo "$1:$2 CONNECTED"; else echo "$1:$2 blocked"; fi
}
'@

function Get-AllowState {
    param([string]$Label)
    $r = Invoke-WslFile -Tag "sp-state-$Label" -User 'root' -Body @'
echo "ALLOWED_SET=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' ')"
echo "ALLOWED_FILE=$(sort -u /etc/clawfactory/allowed-ips.txt 2>/dev/null | tr '\n' ' ')"
echo "TOOLCHAIN_SET_N=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)"
echo "POLICY_ENABLED=$(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))' 2>/dev/null || echo unknown)"
echo "--- the toolchain hosts resolved right now, so set membership can be compared by ADDRESS ---"
for h in api.github.com github.com raw.githubusercontent.com codeload.github.com clawhub.ai api.clawhub.ai registry.npmjs.org; do
  for ip in $(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u); do echo "TCADDR=$ip $h"; done
done
'@
    W $r.Out
    $setIps  = @(); $fileIps = @(); $tcAddrs = @{}
    if ($r.Out -match 'ALLOWED_SET=(.*)')  { $setIps  = @(($Matches[1] -split '\s+') | Where-Object { $_ -match '^\d+\.' }) }
    if ($r.Out -match 'ALLOWED_FILE=(.*)') { $fileIps = @(($Matches[1] -split '\s+') | Where-Object { $_ -match '^\d+\.' }) }
    foreach ($ln in ($r.Out -split "`r?`n")) { if ($ln -match '^TCADDR=(\S+)\s+(\S+)') { $tcAddrs[$Matches[1]] = $Matches[2] } }
    return @{
        SetIps = $setIps; FileIps = $fileIps; TcAddrs = $tcAddrs
        TcSetN = $(if ($r.Out -match 'TOOLCHAIN_SET_N=(\d+)') { [int]$Matches[1] } else { -1 })
        Policy = $(if ($r.Out -match 'POLICY_ENABLED=(\w+)') { $Matches[1] } else { 'unknown' })
        # The intersection is the finding: which toolchain ADDRESSES are sitting
        # in the unrevocable set. Address-level, because that is what nft holds.
        SetHits  = @($setIps  | Where-Object { $tcAddrs.ContainsKey($_) })
        FileHits = @($fileIps | Where-Object { $tcAddrs.ContainsKey($_) })
        Raw = $r.Out
    }
}

function Measure-Reach {
    param([string]$Label)
    $r = Invoke-WslFile -Tag "sp-reach-$Label" -User 'clawuser' -Body @"
echo "whoami=`$(id -un) uid=`$(id -u)"
$ProbeFn
echo '--- SUBJECT: the software sources the toggle claims to control ---'
for h in api.github.com registry.npmjs.org raw.githubusercontent.com; do probe `$h 443; done
echo '--- CONTROL A (MUST CONNECT): the provider route, which no switch may affect ---'
probe api.anthropic.com 443
echo '--- CONTROL B (MUST BE REFUSED): a site nobody allowlisted ---'
probe example.org 443
"@
    W $r.Out
    return @{
        Github  = $r.Out -match 'api\.github\.com:443 CONNECTED'
        Npm     = $r.Out -match 'registry\.npmjs\.org:443 CONNECTED'
        Raw2    = $r.Out -match 'raw\.githubusercontent\.com:443 CONNECTED'
        CtlPos  = $r.Out -match 'api\.anthropic\.com:443 CONNECTED'
        CtlNeg  = $r.Out -match 'example\.org:443 blocked'
        Out     = $r.Out
    }
}

function Write-WslScript {
    <# Put a Windows-side script text INTO the distro at a known /var/tmp path.

       NOT via /mnt/c. The installer writes [automount] enabled=false on purpose,
       so /mnt/c is absent by design on a correct install and a probe that used it
       would only work on a BROKEN one. Everything travels the sanctioned 9p file
       channel instead, wrapped in a quoted heredoc so no text reaches a command
       line.

       Verifies by BYTE COUNT rather than assuming the write landed: a truncated
       payload that still parses is the failure mode this exists to catch. #>
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$LinuxPath,
        [Parameter(Mandatory)][string]$Tag
    )
    $lf = ($Text -replace "`r`n", "`n") -replace "`r", "`n"
    if ($lf -split "`n" | Where-Object { $_.TrimEnd() -eq 'CFSCRIPTEOF' }) {
        throw "Write-WslScript: the payload contains the heredoc terminator, so it cannot be delivered intact."
    }
    $expected = ([Text.Encoding]::UTF8.GetByteCount($lf))
    $body = "cat > $LinuxPath <<'CFSCRIPTEOF'`n$lf`nCFSCRIPTEOF`nchmod 700 $LinuxPath`necho `"WROTE=`$(wc -c < $LinuxPath | tr -d ' ') PATH=$LinuxPath`""
    $r = Invoke-WslFile -Tag $Tag -User 'root' -Body $body
    W $r.Out
    # The heredoc adds one trailing newline beyond the source text, so accept
    # either. Anything else is a truncation and is reported as one.
    $landed = if ($r.Out -match 'WROTE=(\d+)') { [int]$Matches[1] } else { -1 }
    return @{ Ok = ($landed -eq $expected -or $landed -eq ($expected + 1)); Landed = $landed; Expected = $expected }
}

# =========================================================================
Section '0. Preconditions and the installed subject. Checked before anything is measured through it.'
$inst = Invoke-WslFile -Tag "sp-inst-$tag" -User 'root' -Body @'
echo "--- the base host seed the fix introduced ---"
if [ -e /etc/clawfactory/base-hosts.seed ]; then stat -c 'PRESENT %n %U:%G %a' /etc/clawfactory/base-hosts.seed; sed 's/^/SEEDHOST=/' /etc/clawfactory/base-hosts.seed; else echo "ABSENT /etc/clawfactory/base-hosts.seed"; fi
echo "--- CONTROL: a path that must be absent ---"
[ -e /etc/clawfactory/not-a-real-seed.seed ] && echo "CONTROL FAILED" || echo "CONTROL OK (absent)"
echo "--- the toolchain resolver, whose list the new guard compares against ---"
if [ -x /usr/local/sbin/clawfactory-toolchain.sh ]; then /usr/local/sbin/clawfactory-toolchain.sh --list-hosts | sed 's/^/TCHOST=/'; else echo "ABSENT resolver"; fi
echo "--- the three sets and their accepts ---"
/usr/local/sbin/clawfactory-fw-assert.sh 2>&1; echo "fw_assert_rc=$?"
'@
W $inst.Out
$ctlSane = $inst.Out -match 'CONTROL OK \(absent\)'
Register-Control -Id "SP.0.CTL.$tag" -Name 'the installation probe tells present from absent' `
    -Fired $ctlSane -Evidence 'a bogus path under /etc/clawfactory was not found' | Out-Null

$seedPresent = $inst.Out -match 'PRESENT /etc/clawfactory/base-hosts\.seed root:root 644'
$seedHosts   = @(([regex]::Matches($inst.Out, 'SEEDHOST=(\S+)') | ForEach-Object { $_.Groups[1].Value }))
Record "SP.0a.$tag" 'setup.ps1 wrote the root-owned base host seed that switch-provider now reads' `
    $(if ($seedPresent) { 'PASS' } else { 'FAIL' }) "expected root:root 644; seed carries $($seedHosts.Count) host(s): $($seedHosts -join ' ')"

# The seed is the input to the set nothing can revoke. A toolchain host in it
# would re-open the whole defect through a different door, so it is checked
# directly rather than inferred from the reachability result.
$seedContam = @($seedHosts | Where-Object { $TOOLCHAIN7 -contains $_ })
Record "SP.0b.$tag" 'The base host seed contains NO toolchain host' `
    $(if ($seedHosts.Count -gt 0 -and $seedContam.Count -eq 0) { 'PASS' } elseif ($seedHosts.Count -eq 0) { 'VOID' } else { 'FAIL' }) `
    $(if ($seedHosts.Count -eq 0) { 'the seed reported no hosts, so there was nothing to check and this is not a product verdict' } else { "toolchain hosts found in the seed: $($seedContam.Count) [$($seedContam -join ' ')]" })

$tcResolverHosts = @(([regex]::Matches($inst.Out, 'TCHOST=(\S+)') | ForEach-Object { $_.Groups[1].Value }))
Compare-Independent -Id "SP.0c.$tag" -Name 'the probe''s held copy of the toolchain hosts agrees with the resolver' `
    -Mine (($TOOLCHAIN7 | Sort-Object) -join ' ') `
    -Reported (($tcResolverHosts | Where-Object { $TOOLCHAIN7 -contains $_ } | Sort-Object -Unique) -join ' ') `
    -MineLabel 'this probe holds' -ReportedLabel 'clawfactory-toolchain.sh --list-hosts reports' | Out-Null

Record "SP.0d.$tag" 'The chain-shape tripwire passes, so all three allowlist accepts are present' `
    $(if ($inst.Out -match 'fw_assert_rc=0') { 'PASS' } else { 'FAIL' }) 'fw-assert names provider, read-fetch and toolchain accepts'

# =========================================================================
Section '1. Hold the toolchain toggle OFF. Every measurement below is taken in this state.'
$off0 = Invoke-WslFile -Tag "sp-off0-$tag" -User 'root' -Body '/usr/local/sbin/clawfactory-fetchctl toolchain off 2>&1 | tail -1'
W $off0.Out
$toggledOff = $off0.Out -match '"ok":true'
Require-Precondition -Id "SP.1.PRE.$tag" -Name 'the toolchain toggle is OFF' -Met $toggledOff `
    -Reason 'the whole card is about a switch that is off being silently re-opened. With the switch ON there is nothing to defeat, so a run that could not turn it off measures nothing' | Out-Null

$base = Get-AllowState -Label "baseline-$tag"
Record "SP.1a.$tag" 'BASELINE: with the toggle OFF, no toolchain address sits in allowed_ipv4' `
    $(if ($base.SetHits.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
    "toolchain addresses in the live unrevocable set: $($base.SetHits.Count) [$($base.SetHits -join ' ')]"
Record "SP.1b.$tag" 'BASELINE: with the toggle OFF, no toolchain address sits in allowed-ips.txt' `
    $(if ($base.FileHits.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
    "toolchain addresses persisted: $($base.FileHits.Count) [$($base.FileHits -join ' ')]"

$r0 = Measure-Reach -Label "baseline-$tag"
Register-Control -Id "SP.1.CTL.$tag" -Name 'the reachability probe both connects and is refused in the same run' `
    -Fired ($r0.CtlPos -and $r0.CtlNeg) `
    -Evidence "provider reachable=$($r0.CtlPos) (must be true); un-allowlisted site refused=$($r0.CtlNeg) (must be true). A probe proven in only one direction passes whether the log rule sits above or below the accepts, which is the cfv-167 error" | Out-Null
Record "SP.1c.$tag" 'BASELINE: with the toggle OFF, GitHub and npm are unreachable for uid 1000' `
    $(if (-not ($r0.Github -or $r0.Npm -or $r0.Raw2)) { 'PASS' } else { 'FAIL' }) `
    "github=$($r0.Github) npm=$($r0.Npm) raw=$($r0.Raw2) (all must be false)"

# =========================================================================
Section '2. THE DEFECT, DEMONSTRATED. The 1.3.4 firewall block, verbatim, with the toggle still OFF.'
# Skipped on the post-reboot pass: the defect is demonstrated once, and re-running
# the defective text after a reboot would re-pollute the box the post-reboot
# measurements are taken on.
if ($PostReboot) {
    Record "SP.2.$tag" 'The pre-fix demonstration is not repeated after the reboot' 'INFO' `
        'demonstrated on the PRE pass; re-running the defective text here would re-pollute the very set the post-reboot rows measure'
} else {
    # The 1.3.4 reference travels the same file channel as everything else.
    $preText = [IO.File]::ReadAllText('C:\cfv\sp-prefix-fw.sh')
    $wPre = Write-WslScript -Text $preText -LinuxPath '/var/tmp/sp-prefix-fw.sh' -Tag "sp-putpre-$tag"
    Register-Control -Id "SP.2.CTL0.$tag" -Name 'the 1.3.4 reference reached the distro intact' `
        -Fired $wPre.Ok -Evidence "landed $($wPre.Landed) bytes, expected $($wPre.Expected). A truncated reference that still parses would demonstrate the wrong thing" | Out-Null

    $pre = Invoke-WslFile -Tag "sp-prefix-$tag" -User 'root' -Body @'
echo "--- reference sha256, compare against the build machine's record in the close-out ---"
sha256sum /var/tmp/sp-prefix-fw.sh 2>/dev/null || echo "MISSING /var/tmp/sp-prefix-fw.sh"
echo "--- it must carry all seven toolchain hosts, or it is not the defective text ---"
echo "REFHOSTS=$(grep -c -E 'api\.github\.com.*registry\.npmjs\.org' /var/tmp/sp-prefix-fw.sh)"
echo "--- running the 1.3.4 firewall block verbatim ---"
bash /var/tmp/sp-prefix-fw.sh 2>&1 | tail -5
echo "prefix_rc=${PIPESTATUS[0]}"
'@
    W $pre.Out
    $preRan = ($pre.Out -match 'switch-provider\] firewall updated') -and ($pre.Out -match 'REFHOSTS=1')
    Register-Control -Id "SP.2.CTL.$tag" -Name 'THE FAULT LANDED: the pre-fix block actually ran and rebuilt the allowlist' `
        -Fired $preRan `
        -Evidence 'a fault injection that does not inject scores a false pass and looks exactly like a working control. This asserts the defective text executed to completion rather than assuming it' | Out-Null

    $afterPre = Get-AllowState -Label "afterprefix-$tag"
    Record "SP.2a.$tag" 'REFERENCE: the 1.3.4 script puts toolchain addresses into allowed_ipv4' `
        $(if ($afterPre.SetHits.Count -gt 0) { 'PASS' } else { 'FAIL' }) `
        "PASS here means THE DEFECT REPRODUCED, which is what test 4 needs as its reference. toolchain addresses now in the unrevocable set: $($afterPre.SetHits.Count) [$($afterPre.SetHits -join ' ')]. Baseline was $($base.SetHits.Count)"
    Record "SP.2b.$tag" 'REFERENCE: the 1.3.4 script PERSISTS them to allowed-ips.txt' `
        $(if ($afterPre.FileHits.Count -gt 0) { 'PASS' } else { 'FAIL' }) `
        "persisted toolchain addresses: $($afterPre.FileHits.Count) [$($afterPre.FileHits -join ' ')]. This is the half that survives reboot"

    $rPre = Measure-Reach -Label "afterprefix-$tag"
    Register-Control -Id "SP.2.CTL2.$tag" -Name 'the post-demonstration reachability probe still discriminates' `
        -Fired ($rPre.CtlPos -and $rPre.CtlNeg) -Evidence "provider=$($rPre.CtlPos) must be true; un-allowlisted=$($rPre.CtlNeg) must be true" | Out-Null
    Record "SP.2c.$tag" 'THE SECURITY FAILURE: with the toggle OFF, GitHub and npm are reachable again after the switch' `
        $(if ($rPre.Github -or $rPre.Npm) { 'PASS' } else { 'FAIL' }) `
        "PASS here means the defect is REAL AND USER-VISIBLE: the toggle is off, the panel says off, and uid 1000 reaches the software sources anyway. github=$($rPre.Github) npm=$($rPre.Npm)"
    Record "SP.2d.$tag" 'The panel still reports the toggle as OFF while the route is open' `
        $(if ($afterPre.Policy -eq 'False') { 'PASS' } else { 'FAIL' }) `
        "policy reports enabled=$($afterPre.Policy) (False = the panel shows OFF). A control that lies to the user is the finding, not merely an open route"
}

# =========================================================================
Section '3. THE FIX. The INSTALLED 1.3.5 switch-provider, rendered on this box and run in the same state.'
# Rendered from the installed file rather than from a copy staged with the probe,
# so this arm tests the artifact that was actually installed.
$renderPs = @"
`$ErrorActionPreference='Stop'
`$p = '$AppDir\resources\switch-provider.ps1'
if (-not (Test-Path `$p)) { 'RENDER_FAIL missing ' + `$p; exit }
`$lines = [IO.File]::ReadAllLines(`$p)
`$start = (`$lines | Select-String -SimpleMatch '`$fwScript = @"' | Select-Object -First 1).LineNumber
`$end = `$null; for (`$i = `$start; `$i -lt `$lines.Count; `$i++) { if (`$lines[`$i].TrimEnd() -eq '"@') { `$end = `$i + 1; break } }
if (-not `$end) { 'RENDER_FAIL could not find the here-string terminator'; exit }
`$providerHostLiteral = 'api.anthropic.com'
`$body = (`$lines[`$start..(`$end-2)] -join "``n")
`$rendered = `$ExecutionContext.InvokeCommand.ExpandString(`$body)
[IO.File]::WriteAllText('C:\cfv\sp-fixed-fw.sh', `$rendered.Replace("``r``n","``n"), (New-Object Text.UTF8Encoding(`$false)))
"RENDER_OK bytes=`$(`$rendered.Length)"
"@
W '--- rendering the installed switch-provider firewall block on the VM ---'
# Via a FILE, never -Command. A multi-line script on argv is the same shape that
# fabricated three confident readings in L22; the fix there was a file channel and
# the same rule applies to the Windows side of this probe.
[IO.File]::WriteAllText('C:\cfv\sp-render.ps1', $renderPs, (New-Object Text.UTF8Encoding($false)))
$rr = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\cfv\sp-render.ps1' 2>&1
W ($rr -join "`n")
$renderOk = ($rr -join "`n") -match 'RENDER_OK'
Register-Control -Id "SP.3.CTL.$tag" -Name 'the installed switch-provider firewall block was rendered from the INSTALLED file' `
    -Fired $renderOk -Evidence 'this arm must test the installed artifact, not a copy staged beside the probe' | Out-Null

if ($renderOk) {
    $fixText = [IO.File]::ReadAllText('C:\cfv\sp-fixed-fw.sh')
    $wFix = Write-WslScript -Text $fixText -LinuxPath '/var/tmp/sp-fixed-fw.sh' -Tag "sp-putfix-$tag"
    Register-Control -Id "SP.3.CTL0.$tag" -Name 'the rendered 1.3.5 block reached the distro intact' `
        -Fired $wFix.Ok -Evidence "landed $($wFix.Landed) bytes, expected $($wFix.Expected)" | Out-Null

    $post = Invoke-WslFile -Tag "sp-fixed-$tag" -User 'root' -Body @'
echo "--- the fixed block must NOT contain a toolchain hostname on any executable line ---"
if grep -nE 'github|npmjs|clawhub' /var/tmp/sp-fixed-fw.sh | grep -vE '^[0-9]+:[[:space:]]*#' | sed 's/^/EXECHIT=/' | grep -q EXECHIT; then
  grep -nE 'github|npmjs|clawhub' /var/tmp/sp-fixed-fw.sh | grep -vE '^[0-9]+:[[:space:]]*#' | sed 's/^/EXECHIT=/'
else
  echo "NO_EXEC_HIT"
fi
echo "--- CALIBRATION of that grep: the same search over a rigged copy MUST report a hit ---"
cp /var/tmp/sp-fixed-fw.sh /var/tmp/sp-canary.sh
echo 'BASE_HOSTS="$BASE_HOSTS github.com"' >> /var/tmp/sp-canary.sh
if grep -nE 'github|npmjs|clawhub' /var/tmp/sp-canary.sh | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q .; then echo "CANARY_FOUND"; else echo "CANARY_MISSED"; fi
rm -f /var/tmp/sp-canary.sh
echo "--- running it ---"
bash /var/tmp/sp-fixed-fw.sh 2>&1 | tail -6
echo "fixed_rc=${PIPESTATUS[0]}"
'@
    W $post.Out
    $fixedRan  = $post.Out -match 'switch-provider\] firewall updated'
    $noExecHit = $post.Out -match 'NO_EXEC_HIT'
    Register-Control -Id "SP.3.CTL2.$tag" -Name 'the fixed block actually ran and rebuilt the allowlist' `
        -Fired $fixedRan -Evidence 'without this, an absent toolchain address would be indistinguishable from a script that never executed' | Out-Null

    Register-Control -Id "SP.3.CTL3.$tag" -Name 'the executable-line grep finds an injected toolchain host' `
        -Fired ($post.Out -match 'CANARY_FOUND') `
        -Evidence 'an audit regex is itself a probe. Before its silence is trusted, the same search over a rigged copy must report the hit it is looking for' | Out-Null
    Record "SP.3a.$tag" 'The fixed script carries no toolchain hostname on any executable line' `
        $(if ($noExecHit) { 'PASS' } else { 'FAIL' }) 'comment lines excluded; the fix documents the seven hosts by name in prose'
    Record "SP.3b.$tag" 'The fixed script reports reading its base hosts from the root-owned seed' `
        $(if ($post.Out -match 'base hosts read from /etc/clawfactory/base-hosts\.seed') { 'PASS' } else { 'FAIL' }) `
        'the fallback path prints a WARNING instead, so this distinguishes "read the seed" from "used the built-in list"'
    Record "SP.3c.$tag" 'The new structural toolchain guard ran and passed' `
        $(if ($post.Out -match 'toolchain guard: no toolchain host in the allowlist rebuild') { 'PASS' } else { 'FAIL' }) `
        'the guard asks clawfactory-toolchain.sh --list-hosts for the live list rather than comparing against another copy'

    $afterFix = Get-AllowState -Label "afterfix-$tag"
    Record "SP.4a.$tag" 'TEST 4: after the FIXED switch, NO toolchain address is in allowed_ipv4' `
        $(if ($afterFix.SetHits.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
        "toolchain addresses in the unrevocable set: $($afterFix.SetHits.Count) [$($afterFix.SetHits -join ' ')]. Pre-fix reference on this same box: see SP.2a"
    Record "SP.4b.$tag" 'TEST 4: after the FIXED switch, NO toolchain address is in allowed-ips.txt' `
        $(if ($afterFix.FileHits.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
        "persisted toolchain addresses: $($afterFix.FileHits.Count) [$($afterFix.FileHits -join ' ')]"
    Record "SP.4c.$tag" 'The provider route SURVIVED the fixed rebuild (the fix narrowed nothing it should not)' `
        $(if ($afterFix.SetIps.Count -gt 0) { 'PASS' } else { 'FAIL' }) `
        "$($afterFix.SetIps.Count) address(es) remain in allowed_ipv4 after the rebuild"

    $rFix = Measure-Reach -Label "afterfix-$tag"
    Register-Control -Id "SP.5.CTL.$tag" -Name 'the reachability probe still discriminates after the fixed switch' `
        -Fired ($rFix.CtlPos -and $rFix.CtlNeg) `
        -Evidence "provider reachable=$($rFix.CtlPos) must be true; un-allowlisted refused=$($rFix.CtlNeg) must be true" | Out-Null
    Record "SP.5a.$tag" 'TEST 5: with the toggle OFF, GitHub and npm remain UNREACHABLE after a provider switch' `
        $(if (-not ($rFix.Github -or $rFix.Npm -or $rFix.Raw2)) { 'PASS' } else { 'FAIL' }) `
        "github=$($rFix.Github) npm=$($rFix.Npm) raw=$($rFix.Raw2) (all must be false). This is the row the card exists for"
}

# =========================================================================
Section '6. TEST 6, the discriminating control: with the toggle ON they must be reachable again.'
# Without this the whole phase could pass on a box where GitHub simply happened
# to be unreachable for an unrelated reason.
$on = Invoke-WslFile -Tag "sp-on-$tag" -User 'root' -Body '/usr/local/sbin/clawfactory-fetchctl toolchain on 2>&1 | tail -1'
W $on.Out
$toggledOn = $on.Out -match '"ok":true'
Register-Control -Id "SP.6.CTL.$tag" -Name 'the toggle could be switched back ON in this run' -Fired $toggledOn `
    -Evidence 'if the toggle cannot be turned on, the negative result above is not attributable to the toggle' | Out-Null
if ($toggledOn) {
    $rOn = Measure-Reach -Label "toggleon-$tag"
    Record "SP.6a.$tag" 'TEST 6: with the toggle ON, GitHub and npm ARE reachable, so the probe discriminates' `
        $(if ($rOn.Github -and $rOn.Npm) { 'PASS' } else { 'FAIL' }) `
        "github=$($rOn.Github) npm=$($rOn.Npm) (both must be true). A FAIL here voids the meaning of SP.5a rather than adding to it"
}

# =========================================================================
Section '7. Fault injection on the new guard, with a control proving the fault landed.'
if (-not $PostReboot) {
    $inj = Invoke-WslFile -Tag "sp-inject-$tag" -User 'root' -Body @'
cp /etc/clawfactory/base-hosts.seed /var/tmp/base-hosts.seed.bak
echo "github.com" >> /etc/clawfactory/base-hosts.seed
echo "INJECTED=$(grep -c '^github.com$' /etc/clawfactory/base-hosts.seed)"
echo "--- the fixed block must now REFUSE ---"
bash /var/tmp/sp-fixed-fw.sh 2>&1 | tail -3
echo "guarded_rc=${PIPESTATUS[0]}"
bash /var/tmp/sp-fixed-fw.sh >/dev/null 2>&1; echo "rerun_rc=$?"
cp /var/tmp/base-hosts.seed.bak /etc/clawfactory/base-hosts.seed
echo "RESTORED=$(grep -c '^github.com$' /etc/clawfactory/base-hosts.seed)"
'@
    W $inj.Out
    $faultLanded = $inj.Out -match 'INJECTED=1'
    Register-Control -Id "SP.7.CTL.$tag" -Name 'THE FAULT LANDED: a toolchain host really was added to the seed' `
        -Fired $faultLanded -Evidence 'a fault injection that does not inject scores a false pass and looks exactly like a working guard' | Out-Null
    Record "SP.7a.$tag" 'A toolchain host in the seed makes the fixed script REFUSE rather than widen the unrevocable set' `
        $(if ($inj.Out -match 'rerun_rc=1' -and $inj.Out -match 'is a toolchain host and would be written into @allowed_ipv4') { 'PASS' } else { 'FAIL' }) `
        'the guard is structural: it denies on the condition rather than warning about it'
    Record "SP.7b.$tag" 'The injected fault was removed again, so later phases start from the real seed' `
        $(if ($inj.Out -match 'RESTORED=0') { 'PASS' } else { 'FAIL' }) 'a probe that leaves its fault behind poisons every phase after it'

    # Input shapes, re-run in situ rather than trusted from the build machine.
    $shapes = Invoke-WslFile -Tag "sp-shapes-$tag" -User 'root' -Body @'
cp /etc/clawfactory/base-hosts.seed /var/tmp/seed.bak
: > /etc/clawfactory/base-hosts.seed
bash /var/tmp/sp-fixed-fw.sh >/var/tmp/empty.out 2>&1; echo "EMPTY_RC=$?"; grep -c 'is empty' /var/tmp/empty.out | sed 's/^/EMPTY_NAMED=/'
printf 'openclaw.ai\n$(id)\n' > /etc/clawfactory/base-hosts.seed
bash /var/tmp/sp-fixed-fw.sh >/var/tmp/mal.out 2>&1; echo "MALFORMED_RC=$?"; grep -c 'is not a hostname' /var/tmp/mal.out | sed 's/^/MALFORMED_NAMED=/'
cp /var/tmp/seed.bak /etc/clawfactory/base-hosts.seed
bash /var/tmp/sp-fixed-fw.sh >/dev/null 2>&1; echo "RESTORED_RC=$?"
'@
    W $shapes.Out
    Record "SP.7c.$tag" 'An EMPTY seed is fatal and the firewall is left untouched' `
        $(if ($shapes.Out -match 'EMPTY_RC=1' -and $shapes.Out -match 'EMPTY_NAMED=[1-9]') { 'PASS' } else { 'FAIL' }) `
        'an empty base list is a truncated or tampered file, and a fault is not a preference'
    Record "SP.7d.$tag" 'A MALFORMED seed line is fatal and is named in the refusal' `
        $(if ($shapes.Out -match 'MALFORMED_RC=1' -and $shapes.Out -match 'MALFORMED_NAMED=[1-9]') { 'PASS' } else { 'FAIL' }) `
        'the hostile line was a command substitution; it must be refused, not resolved, and must never execute'
    Record "SP.7e.$tag" 'The real seed was restored and the script succeeds again' `
        $(if ($shapes.Out -match 'RESTORED_RC=0') { 'PASS' } else { 'FAIL' }) 'proves the two refusals above were caused by the injected shapes and nothing else'
}

# Leave the box in the state the reboot pass expects to find: toggle OFF, which
# is the condition under test. Stated here because a phase that silently changes
# the state the next phase measures is how a reboot pass reports on the wrong box.
$leave = Invoke-WslFile -Tag "sp-leaveoff-$tag" -User 'root' -Body '/usr/local/sbin/clawfactory-fetchctl toolchain off 2>&1 | tail -1'
W $leave.Out
Record "SP.9.$tag" 'The box is left with the toggle OFF for the reboot pass' `
    $(if ($leave.Out -match '"ok":true') { 'PASS' } else { 'FAIL' }) 'the post-reboot pass measures persistence of the OFF state'

Complete-Phase -ResultsJson "C:\cfv\switchprovider-results-$tag.json" -MarkerPrefix "SWITCHPROVIDER_$tag"
