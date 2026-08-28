<#
  BOX D: THE HELD BEFORE-STATE, AND THE READ-BACK AGAINST IT.

  WHY THIS EXISTS RATHER THAN interim-v141-uninstall.ps1 -Mode AfterKeepLinux
  ---------------------------------------------------------------------------
  That probe reads eighteen NAMED subjects and it was written for v1.4.1. The
  v1.4.2 change set is about COMPLETENESS -- it enlarged the uninstaller's unit
  list from five names to eleven and its /usr/local/sbin list from twelve to
  seventeen -- so a probe that names a subset of those files can report a clean
  sweep over the wrong set. The whole defect class v1.4.2 fixed is "the list was
  short", and a short list in the instrument reproduces it exactly.

  So this probe ENUMERATES. It lists what is actually there, prints the raw
  listing, and only then compares against a derived expectation. Both directions
  of the set difference are reported, because an extra file and a missing file
  are different defects.

  CLAUSE 1, SHARPENED: DISCOVER THE VALUE, NOT JUST THE NAME.
  Boxes B and C lost three probes to assumptions one level below the identifier.
  Every list below is read off the box with `ls` and PRINTED VERBATIM before any
  verdict is taken, so a reader can see the set the counts were taken over. A
  count with no listing beside it cannot be distinguished from a count over the
  wrong set -- which is exactly how #261's first revision measured one host out
  of eight and reported a clean PASS with every summary number self-consistent.

  WHERE THE DERIVED EXPECTATION COMES FROM, so it is auditable rather than
  remembered: resources/uninstall.ps1. The eleven units are its CF_UNITS
  assignment; the seventeen helpers are its explicit rm list; the drop-in
  directory and /usr/local/bin/clawfactory-send are named on their own lines.
  Those are quoted here as a CROSS-CHECK on the enumeration, never as a
  substitute for it.

  THE READER IS THE INSTRUMENT, SO THE READER IS CONTROLLED IN BOTH MODES.
  An all-absent result from a reader that always answers absent is not evidence.
  Mode After therefore re-asserts, AFTER the uninstall, that the same reader can
  still see things that ARE present. The job card calls for this explicitly and
  it is the single most likely way this probe could lie.

  MODES
    Before   enumerate, prove the reader sees what is there, write the snapshot
    After    enumerate again, prove the reader STILL sees what is there, and
             compare every held subject
#>
param(
    [ValidateSet('Before','After')][string]$Mode = 'Before',
    [string]$Transcript  = '',
    [string]$Snapshot    = 'C:\cfv\uninstate-before.json',
    [string]$ResultsJson = '',
    [string]$LibDir      = 'C:\cfv',
    # DRY-RUN SEAM ONLY. Load the Windows half from a rigged JSON instead of
    # reading this machine. Without it a dry-run on the build machine reads the
    # build machine's own ClawFactory install, which is both a meaningless
    # measurement and a read of a box no validation run may touch. Never passed
    # on a VM.
    [string]$WinRigJson  = ''
)

$ErrorActionPreference = 'Continue'
if (-not $Transcript)  { $Transcript  = "C:\cfv\uninstate-$($Mode.ToLower())-out-probe.txt" }
if (-not $ResultsJson) { $ResultsJson = "C:\cfv\uninstate-$($Mode.ToLower())-results.json" }

. (Join-Path $LibDir 'interim-v120-wslchan.ps1')
. (Join-Path $LibDir 'interim-v120-phaselib.ps1')

Start-Phase -Name "ClawFactory v1.4.4 box D: keep-Linux uninstall state, mode=$Mode" `
    -Transcript $Transcript -Sentinel 'UNINSTATE_PROBE_COMPLETE'

function Finish($code) { W ''; W "UNINSTATE_PROBE_COMPLETE rc=$code"; exit $code }

function Val([string]$text, [string]$key) {
    if ($text -match "(?m)^$([regex]::Escape($key))=(.*)$") { return $Matches[1].Trim() }
    return '(not reported)'
}

# Parse a fenced list out of the reader's output. Fences rather than a regex over
# the whole blob: a list that came back EMPTY and a list that was never emitted
# are different facts, and only the fence tells them apart.
function Lines([string]$text, [string]$begin, [string]$end) {
    $o = @(); $on = $false; $sawBegin = $false
    foreach ($ln in ($text -split "`r?`n")) {
        $s = $ln.Trim()
        if ($s -eq $begin) { $on = $true; $sawBegin = $true; continue }
        if ($s -eq $end)   { $on = $false; continue }
        if ($on -and $s)   { $o += $s }
    }
    return [pscustomobject]@{ Items = @($o); Fenced = $sawBegin }
}

# --------------------------------------------------------------------------
# The DERIVED expectation, quoted from resources/uninstall.ps1: the eleven of
# CF_UNITS and the seventeen of the explicit rm list. Used only to CROSS-CHECK
# the enumeration; the enumeration is the measurement.
# --------------------------------------------------------------------------
$EXPECT_UNITS = @(
    'clawfactory-allow-providers.timer','clawfactory-allow-providers.service',
    'clawfactory-egress-refresh.service','clawfactory-fw.service',
    'clawfactory-proxy.service','clawfactory-quarantine.service',
    'clawfactory-quarantine-gc.timer','clawfactory-quarantine-gc.service',
    'clawfactory-send.service','clawfactory-send-gc.timer','clawfactory-send-gc.service'
)
$EXPECT_SBIN = @(
    'clawfactory-allow-providers.sh','clawfactory-dns-resolvers.sh','clawfactory-egress-refresh.sh',
    'clawfactory-fetchctl','clawfactory-fetchctl.js','clawfactory-fw-apply.sh',
    'clawfactory-fw-assert.sh','clawfactory-proxy.js','clawfactory-quarantinectl.js',
    'clawfactory-quarantined.js','clawfactory-read-fetch.sh','clawfactory-sendctl',
    'clawfactory-sendctl.js','clawfactory-sendd.js','clawfactory-spend-check.js',
    'clawfactory-toolchain.sh','clawfactory-turn-gate.sh'
)

# --------------------------------------------------------------------------
# THE DISTRO READER. Every list is emitted between named BEGIN/END fences so it
# can be parsed as a SET, and the raw lines are echoed into the transcript. The
# last three lines are the reader's own control: two paths present on any live
# Ubuntu, and one that has never existed.
# --------------------------------------------------------------------------
$DISTRO_BODY = @'
echo "DISTRO_ALIVE=yes"
echo "BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
echo "--UNITS--"
ls -1 /etc/systemd/system/clawfactory-*.service /etc/systemd/system/clawfactory-*.timer 2>/dev/null | xargs -r -n1 basename
echo "--END-UNITS--"
echo "--ENABLED--"
ls -1d /etc/systemd/system/*.wants/clawfactory-* 2>/dev/null
echo "--END-ENABLED--"
echo "--SBIN--"
ls -1 /usr/local/sbin/clawfactory-* 2>/dev/null | xargs -r -n1 basename
echo "--END-SBIN--"
echo "--MAPS--"
ls -1 /etc/clawfactory/*-ips.map 2>/dev/null
echo "--END-MAPS--"
echo "USRLOCALBIN_SEND=$( [ -e /usr/local/bin/clawfactory-send ] && echo present || echo absent )"
echo "DROPIN_DIR=$( [ -d /etc/systemd/system/clawfactory-allow-providers.service.d ] && echo present || echo absent )"
echo "ETC_CLAWFACTORY=$( [ -d /etc/clawfactory ] && echo present || echo absent )"
echo "OPENCLAW_BIN=$( [ -e /usr/bin/openclaw ] && echo present || echo absent )"
echo "OPENCLAW_MOD=$( [ -d /usr/lib/node_modules/openclaw ] && echo present || echo absent )"
echo "VARLIB_CF=$( [ -d /var/lib/clawfactory ] && echo present || echo absent )"
echo "USRLOCALLIB_CF=$( [ -d /usr/local/lib/clawfactory ] && echo present || echo absent )"
echo "CLAWUSER=$( id -u clawuser >/dev/null 2>&1 && echo present || echo absent )"
echo "CLAWUSER_HOME=$( [ -d /home/clawuser ] && echo present || echo absent )"
if /usr/sbin/nft list table inet clawfactory >/dev/null 2>&1; then echo "NFT_TABLE=present"; else echo "NFT_TABLE=absent"; fi
echo "NFT_CHAINS=$(/usr/sbin/nft list table inet clawfactory 2>/dev/null | grep -c 'chain ')"
echo "READER_CTL_ETC=$( [ -d /etc ] && echo present || echo absent )"
echo "READER_CTL_BASH=$( [ -x /bin/bash ] && echo present || echo absent )"
echo "READER_CTL_NEVER=$( [ -e /etc/clawfactory-b7f31c-never-existed ] && echo present || echo absent )"
'@

function Read-Distro {
    $r = Invoke-WslFile -Tag "uninstate-$Mode" -User 'root' -Body $DISTRO_BODY
    W '   --- RAW DISTRO READING, printed in full BEFORE any verdict is taken ---'
    foreach ($ln in @($r.Out -split "`r?`n" | Where-Object { $_.Trim() })) { W "   DISTRO> $ln" }
    return $r
}

function Get-WinState {
    if ($WinRigJson) {
        W "   WIN> RIGGED from $WinRigJson (dry-run seam; this machine was not read)"
        # THROW rather than carry on. A rig that fails to parse yields an empty
        # state, and an empty state is scored as "nothing is installed" -- which
        # is a PASS on every after-row and a FAIL on every before-row, for a
        # reason that has nothing to do with the product. A silently empty reader
        # is the exact failure this probe exists to make impossible, so the seam
        # must not be able to introduce one. (Found by a dry-run: a malformed
        # rig produced appDir= with no value and a FAIL that read like a finding.)
        $r = $null
        try { $r = Get-Content -LiteralPath $WinRigJson -Raw | ConvertFrom-Json } catch {
            throw "WinRigJson '$WinRigJson' did not parse: $($_.Exception.Message). Refusing to run with an empty Windows state."
        }
        $s = [ordered]@{}
        foreach ($p in $r.PSObject.Properties) { $s[$p.Name] = $p.Value }
        if ($s.Count -lt 5) { throw "WinRigJson '$WinRigJson' yielded only $($s.Count) field(s). Refusing to run with a state this thin." }
        return $s
    }
    $s = [ordered]@{}
    $s.appDir = [bool](Test-Path -LiteralPath 'C:\Program Files\ClawFactory')
    $keys = @()
    foreach ($h in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                     'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path $h)) { continue }
        foreach ($k in (Get-ChildItem $h -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -like '*ClawFactory*') { $keys += "$($k.PSChildName)|$($p.DisplayName)|$($p.DisplayVersion)" }
        }
    }
    $s.regKeys      = @($keys)
    $s.regKeyCount  = @($keys).Count
    $s.hklmProduct  = [bool](Test-Path 'HKLM:\SOFTWARE\ClawFactory')
    $s.programData  = [bool](Test-Path -LiteralPath (Join-Path $env:ProgramData 'ClawFactory'))
    $tasks = @()
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
                   Where-Object { $_.TaskName -like '*ClawFactory*' -or $_.TaskName -like '*ClawAgent*' } |
                   ForEach-Object { "$($_.TaskPath)$($_.TaskName)" })
    } catch {}
    $s.tasks     = @($tasks)
    $s.taskCount = @($tasks).Count
    # cmdkey /list prints TARGET NAMES only. No credential VALUE is read, stored
    # or printed anywhere in this probe.
    $creds = @()
    try {
        $creds = @((cmdkey /list 2>$null) | Where-Object { $_ -match 'Target:' -and $_ -match 'ClawFactory' } |
                   ForEach-Object { $_.Trim() })
    } catch {}
    $s.credTargets = @($creds)
    $s.credCount   = @($creds).Count
    $lxss = @()
    try {
        $lxss = @(Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue |
                  ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DistributionName } |
                  Where-Object { $_ })
    } catch {}
    $s.lxssDistros   = @($lxss)
    $s.distroPresent = [bool](@($lxss) -contains 'Ubuntu')
    return $s
}

# ==========================================================================
$chan = Test-WslChannel
Register-Control -Id "UST.CHAN.$Mode" -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) {
    W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'
    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UNINSTATE'
    Finish 2
}

Section "1. Enumerate the distro side. The listing is printed BEFORE any count is taken."
$d = Read-Distro
$t = $d.Out

$u = Lines $t '--UNITS--'   '--END-UNITS--'
$e = Lines $t '--ENABLED--' '--END-ENABLED--'
$s = Lines $t '--SBIN--'    '--END-SBIN--'
$m = Lines $t '--MAPS--'    '--END-MAPS--'
$units = $u.Items; $enabled = $e.Items; $sbin = $s.Items; $maps = $m.Items

W ''
W "DISCOVERED_UNITS   fenced=$($u.Fenced) count=$($units.Count)   [$($units -join ' ')]"
W "DISCOVERED_ENABLED fenced=$($e.Fenced) count=$($enabled.Count) [$($enabled -join ' ')]"
W "DISCOVERED_SBIN    fenced=$($s.Fenced) count=$($sbin.Count)    [$($sbin -join ' ')]"
W "DISCOVERED_MAPS    fenced=$($m.Fenced) count=$($maps.Count)    [$($maps -join ' ')]"

# A list that came back EMPTY and a list that was never emitted are different
# facts. Without this, a reader that died before the first fence would report
# "nothing installed" and "nothing left behind" identically.
$fencedOk = $u.Fenced -and $e.Fenced -and $s.Fenced -and $m.Fenced
Register-Control -Id "UST.CTL.FENCE.$Mode" -Name 'every list the reader was asked for was actually emitted' `
    -Fired $fencedOk `
    -Evidence "units=$($u.Fenced) enabled=$($e.Fenced) sbin=$($s.Fenced) maps=$($m.Fenced). An empty list and a list that never ran are different facts; only the fence separates them." | Out-Null

$readerOk  = ((Val $t 'READER_CTL_ETC') -eq 'present') -and ((Val $t 'READER_CTL_BASH') -eq 'present')
$readerNeg = ((Val $t 'READER_CTL_NEVER') -eq 'absent')

$win = Get-WinState
W ''
foreach ($k in $win.Keys) { W ("   WIN> {0} = {1}" -f $k, (($win[$k] | Out-String).Trim() -replace "`r?`n", ' | ')) }

# ==========================================================================
if ($Mode -eq 'Before') {
    Section "2. The reader is proven able to SEE what is present, in both directions"
    Register-Control -Id 'UST.CTL.READER' -Name 'the distro reader answers present for things that ARE present' `
        -Fired $readerOk `
        -Evidence "READER_CTL_ETC=$(Val $t 'READER_CTL_ETC') READER_CTL_BASH=$(Val $t 'READER_CTL_BASH'). Without this, every 'absent' recorded after the uninstall is an artefact of a broken reader rather than a property of the product." | Out-Null
    Record 'UST.CTL.NEG' 'NEGATIVE CONTROL: a path that has never existed reads absent' `
        $(if ($readerNeg) { 'PASS' } else { 'FAIL' }) `
        "/etc/clawfactory-b7f31c-never-existed = $(Val $t 'READER_CTL_NEVER'). A reader answering 'present' to everything would pass every before-row and fail every after-row."

    Section "3. The install this box actually carries, measured against the derived expectation"
    $unitsMissing = @($EXPECT_UNITS | Where-Object { $units -notcontains $_ })
    $unitsExtra   = @($units        | Where-Object { $EXPECT_UNITS -notcontains $_ })
    $sbinMissing  = @($EXPECT_SBIN  | Where-Object { $sbin -notcontains $_ })
    $sbinExtra    = @($sbin         | Where-Object { $EXPECT_SBIN -notcontains $_ })

    # INFO rather than FAIL when the sets merely differ: this row's job is to make
    # a difference VISIBLE, not to fail an install for shipping a unit the
    # uninstaller's list happens not to name. A difference in the onBoxNotDerived
    # direction IS the v1.4.2 class recurring and is called out by name.
    Record 'UST.1a' 'the eleven unit files the uninstaller names are the units this install placed' `
        $(if ($units.Count -eq 0) { 'FAIL' } elseif ($unitsMissing.Count -eq 0 -and $unitsExtra.Count -eq 0) { 'PASS' } else { 'INFO' }) `
        "onBox=$($units.Count) derived=$($EXPECT_UNITS.Count); derivedNotOnBox=[$($unitsMissing -join ' ')]; onBoxNotDerived=[$($unitsExtra -join ' ')]. A unit on the box that CF_UNITS does not name is the v1.4.2 defect class recurring: the drift backstop deletes the FILE and leaves the ENABLEMENT."
    Record 'UST.1b' 'the seventeen /usr/local/sbin helpers the uninstaller names are the helpers this install placed' `
        $(if ($sbin.Count -eq 0) { 'FAIL' } elseif ($sbinMissing.Count -eq 0 -and $sbinExtra.Count -eq 0) { 'PASS' } else { 'INFO' }) `
        "onBox=$($sbin.Count) derived=$($EXPECT_SBIN.Count); derivedNotOnBox=[$($sbinMissing -join ' ')]; onBoxNotDerived=[$($sbinExtra -join ' ')]"

    $complete = ($units.Count -ge 1) -and ($sbin.Count -ge 1) -and ($enabled.Count -ge 1) -and
                ((Val $t 'ETC_CLAWFACTORY') -eq 'present') -and ((Val $t 'CLAWUSER') -eq 'present') -and
                ((Val $t 'OPENCLAW_BIN') -eq 'present') -and ((Val $t 'NFT_TABLE') -eq 'present') -and
                $win.appDir -and ($win.regKeyCount -ge 1)
    Record 'UST.1' 'THE BEFORE-STATE: a complete v1.4.4 install is present on this box' `
        $(if ($complete) { 'PASS' } else { 'FAIL' }) `
        "units=$($units.Count) enabled=$($enabled.Count) sbin=$($sbin.Count) maps=$($maps.Count) /etc/clawfactory=$(Val $t 'ETC_CLAWFACTORY') clawuser=$(Val $t 'CLAWUSER') openclaw=$(Val $t 'OPENCLAW_BIN') nft=$(Val $t 'NFT_TABLE') with $(Val $t 'NFT_CHAINS') chain(s) usrlocalbin-send=$(Val $t 'USRLOCALBIN_SEND') dropin=$(Val $t 'DROPIN_DIR') | Windows appDir=$($win.appDir) uninstallKeys=$($win.regKeyCount) hklm=$($win.hklmProduct) tasks=$($win.taskCount) credTargets=$($win.credCount) distro=$($win.distroPresent). The after-state means nothing without this row."

    $snap = [ordered]@{
        mode = 'Before'; takenAt = (Get-Date -Format s)
        units = @($units); enabled = @($enabled); sbin = @($sbin); maps = @($maps)
        bootId          = (Val $t 'BOOT_ID')
        etcClawfactory  = (Val $t 'ETC_CLAWFACTORY')
        openclawBin     = (Val $t 'OPENCLAW_BIN')
        openclawMod     = (Val $t 'OPENCLAW_MOD')
        varLibCf        = (Val $t 'VARLIB_CF')
        usrLocalLibCf   = (Val $t 'USRLOCALLIB_CF')
        clawuser        = (Val $t 'CLAWUSER')
        clawuserHome    = (Val $t 'CLAWUSER_HOME')
        nftTable        = (Val $t 'NFT_TABLE')
        nftChains       = (Val $t 'NFT_CHAINS')
        usrLocalBinSend = (Val $t 'USRLOCALBIN_SEND')
        dropinDir       = (Val $t 'DROPIN_DIR')
        win             = $win
    }
    $snap | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Snapshot -Encoding UTF8
    $sz = (Get-Item $Snapshot).Length
    W "held snapshot written to $Snapshot ($sz bytes)"
    # The snapshot is an INSTRUMENT and can fail in its own way: on cfv-176 an
    # uncast Get-Content -Raw dragged a provider object graph into ConvertTo-Json
    # and produced 100,420,570 bytes from a box whose largest captured file was
    # 108 bytes. Bound it in BOTH directions and fail loudly rather than quietly.
    Record 'UST.1z' 'the held snapshot is a plausible size for what it captured' `
        $(if ($sz -gt 200 -and $sz -lt 262144) { 'PASS' } else { 'FAIL' }) `
        "snapshot=$sz bytes, floor=200 ceiling=262144. Near a megabyte means an object graph was serialised instead of a value; under the floor means it captured nothing."

    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UNINSTATE'
    Finish 0
}

# ==========================================================================
Section "2. THE AFTER-CONTROL: the same reader can still see things that ARE present"
Register-Control -Id 'UST.CTL.AFTER' -Name 'the reader still answers present for things that ARE present, AFTER the uninstall' `
    -Fired $readerOk `
    -Evidence "READER_CTL_ETC=$(Val $t 'READER_CTL_ETC') READER_CTL_BASH=$(Val $t 'READER_CTL_BASH'). This is the row that makes every absence below evidence rather than an artefact. A reader stuck on 'absent' fails here and voids the phase." | Out-Null
Record 'UST.CTL.NEG2' 'NEGATIVE CONTROL: a path that has never existed still reads absent' `
    $(if ($readerNeg) { 'PASS' } else { 'FAIL' }) `
    "/etc/clawfactory-b7f31c-never-existed = $(Val $t 'READER_CTL_NEVER')"

$have = Require-Precondition -Id 'UST.PRE.SNAP' -Name 'the held BEFORE snapshot exists' `
    -Met (Test-Path -LiteralPath $Snapshot) `
    -Reason 'without the enumeration taken before the uninstall there is nothing to compare against, and an all-absent reading proves nothing at all'
if (-not $have) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UNINSTATE'; Finish 4 }
$b = Get-Content -LiteralPath $Snapshot -Raw | ConvertFrom-Json

Compare-Independent -Id 'UST.3z' -Name 'the snapshot being compared against is a BEFORE snapshot' `
    -Mine 'Before' -Reported "$($b.mode)" `
    -MineLabel 'the mode this probe requires' -ReportedLabel 'the mode recorded in the snapshot' | Out-Null

$beforeComplete = (@($b.units).Count -ge 1) -and (@($b.sbin).Count -ge 1) -and ($b.clawuser -eq 'present')
$ok2 = Require-Precondition -Id 'UST.PRE.COMPLETE' -Name 'the held snapshot recorded a COMPLETE install' `
    -Met $beforeComplete `
    -Reason 'comparing against a snapshot of a box that had nothing on it would score every absence as a removal'
if (-not $ok2) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UNINSTATE'; Finish 4 }

Section "3. Every held subject, read back and reported as measured"
$rows = @(
    @{ id='UST.3a'; n='the eleven unit FILES are gone';                             v=($units.Count -eq 0);   e="units on box after = $($units.Count) [$($units -join ' ')] (before: $(@($b.units).Count) [$(@($b.units) -join ' ')])" },
    @{ id='UST.3b'; n='every ENABLEMENT symlink is gone, not just the files';       v=($enabled.Count -eq 0); e="*.wants/clawfactory-* after = $($enabled.Count) [$($enabled -join ' ')] (before: $(@($b.enabled).Count) [$(@($b.enabled) -join ' ')]). An enabled unit pointing at a deleted script is a failed unit in the journal at every future boot of a machine that no longer has ClawFactory on it. This is the row v1.4.2 card #285 exists for." },
    @{ id='UST.3c'; n='the seventeen /usr/local/sbin helpers are gone';             v=($sbin.Count -eq 0);    e="/usr/local/sbin/clawfactory-* after = $($sbin.Count) [$($sbin -join ' ')] (before: $(@($b.sbin).Count) [$(@($b.sbin) -join ' ')])" },
    @{ id='UST.3d'; n='/usr/local/bin/clawfactory-send is gone';                    v=((Val $t 'USRLOCALBIN_SEND') -eq 'absent'); e="/usr/local/bin/clawfactory-send = $(Val $t 'USRLOCALBIN_SEND') (before: $($b.usrLocalBinSend)). One of the five files v1.4.2 added to the removal list." },
    @{ id='UST.3e'; n='the allow-providers drop-in DIRECTORY is gone';              v=((Val $t 'DROPIN_DIR') -eq 'absent'); e="/etc/systemd/system/clawfactory-allow-providers.service.d = $(Val $t 'DROPIN_DIR') (before: $($b.dropinDir))" },
    @{ id='UST.3f'; n='/etc/clawfactory is gone, and the retention maps with it';   v=(((Val $t 'ETC_CLAWFACTORY') -eq 'absent') -and ($maps.Count -eq 0)); e="/etc/clawfactory = $(Val $t 'ETC_CLAWFACTORY') (before: $($b.etcClawfactory)); *-ips.map after = $($maps.Count) (before: $(@($b.maps).Count) [$(@($b.maps) -join ' ')])" },
    @{ id='UST.3g'; n='THE FIREWALL TABLE IS GONE';                                 v=((Val $t 'NFT_TABLE') -eq 'absent'); e="nft list table inet clawfactory = $(Val $t 'NFT_TABLE'), chains=$(Val $t 'NFT_CHAINS') (before: $($b.nftTable) with $($b.nftChains) chain(s)). A firewall rule surviving an uninstall is not a defensible leftover." },
    @{ id='UST.3h'; n='the openclaw runtime is gone, binary and module tree';       v=(((Val $t 'OPENCLAW_BIN') -eq 'absent') -and ((Val $t 'OPENCLAW_MOD') -eq 'absent')); e="/usr/bin/openclaw = $(Val $t 'OPENCLAW_BIN') (before: $($b.openclawBin)); /usr/lib/node_modules/openclaw = $(Val $t 'OPENCLAW_MOD') (before: $($b.openclawMod))" },
    @{ id='UST.3i'; n='CLAWUSER IS GONE, and its home with it';                     v=(((Val $t 'CLAWUSER') -eq 'absent') -and ((Val $t 'CLAWUSER_HOME') -eq 'absent')); e="id clawuser = $(Val $t 'CLAWUSER') (before: $($b.clawuser)); /home/clawuser = $(Val $t 'CLAWUSER_HOME') (before: $($b.clawuserHome)). THIS IS THE ROW THE REINSTALL DEPENDS ON: on v1.4.1 a surviving clawuser aborted the next install at 'Failed to create clawuser (exit=1)'." },
    @{ id='UST.3j'; n='the state directories are gone';                             v=(((Val $t 'VARLIB_CF') -eq 'absent') -and ((Val $t 'USRLOCALLIB_CF') -eq 'absent')); e="/var/lib/clawfactory = $(Val $t 'VARLIB_CF') (before: $($b.varLibCf)); /usr/local/lib/clawfactory = $(Val $t 'USRLOCALLIB_CF') (before: $($b.usrLocalLibCf))" },
    @{ id='UST.4a'; n='the Windows application directory is gone';                  v=(-not $win.appDir); e="C:\Program Files\ClawFactory = $($win.appDir) (before: $($b.win.appDir)). Keeping the Linux environment must not keep the product." },
    @{ id='UST.4b'; n='the uninstall registry entry is gone';                       v=($win.regKeyCount -eq 0); e="uninstall keys matching ClawFactory after = $($win.regKeyCount) [$(@($win.regKeys) -join '; ')] (before: $($b.win.regKeyCount) [$(@($b.win.regKeys) -join '; ')]). A stale entry leaves a dead Uninstall button in Settings." },
    @{ id='UST.4c'; n='HKLM\SOFTWARE\ClawFactory is gone';                          v=(-not $win.hklmProduct); e="HKLM:\SOFTWARE\ClawFactory = $($win.hklmProduct) (before: $($b.win.hklmProduct))" },
    @{ id='UST.4d'; n='ProgramData\ClawFactory is gone';                            v=(-not $win.programData); e="C:\ProgramData\ClawFactory = $($win.programData) (before: $($b.win.programData))" },
    @{ id='UST.4e'; n='the scheduled tasks are gone';                               v=($win.taskCount -eq 0); e="ClawFactory scheduled tasks after = $($win.taskCount) [$(@($win.tasks) -join ', ')] (before: $($b.win.taskCount) [$(@($b.win.tasks) -join ', ')])" },
    @{ id='UST.5';  n='the distro is STILL REGISTERED, which is what this branch promises'; v=($win.distroPresent); e="Lxss distros = [$(@($win.lxssDistros) -join ', ')] (before: [$(@($b.win.lxssDistros) -join ', ')]). Choosing NO must leave the Ubuntu registration in place; this row is what separates the keep-Linux branch from RemoveAll." }
)
foreach ($r in $rows) { Record $r.id $r.n $(if ($r.v) { 'PASS' } else { 'FAIL' }) $r.e }

Section "4. Reported as facts rather than asserted"
Record 'UST.6a' 'Credential Manager targets, target NAMES only' 'INFO' `
    "ClawFactory credential targets after = $($win.credCount) [$(@($win.credTargets) -join '; ')] (before: $($b.win.credCount) [$(@($b.win.credTargets) -join '; ')]). No credential value is read or printed by this probe."

Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UNINSTATE'
Finish 0
