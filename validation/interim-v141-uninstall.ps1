<#
  v1.4.1 release-closure probe: A CLEAN UNINSTALL, VERIFIED BY READ-BACK.

  WHY THIS EXISTS
  ---------------
  uninstall.ps1 changed in v1.4.1 and no uninstall had been run on this build.
  The v1.4.1 close-out named that as the single reason its fitness verdict was
  NO. On a free public release the uninstaller is the first thing an unhappy
  user reaches for, and it is the one changed shipped file with no measurement
  behind it at all.

  WHAT THE CHANGED CODE ACTUALLY IS, because it decides this probe's shape.
  The v1.4.1 diff to resources/uninstall.ps1 lives ENTIRELY inside the `else`
  branch of the DoRemoveAll decision -- the KEEP-LINUX path. On the RemoveAll
  path `wsl --unregister Ubuntu` deletes the whole distro and every one of the
  new lines is dead code that never executes. A single RemoveAll uninstall
  would therefore report a beautifully clean box while exercising NONE of what
  changed. Both branches are measured, in two passes, on one box.

  THE READER IS THE INSTRUMENT, SO THE READER IS CONTROLLED
  ---------------------------------------------------------
  An all-absent result from a reader that always returns absent is not
  evidence, and it is the single most likely way this probe could lie. Three
  controls, all required to fire in the same run:

    UN.CTL.BEFORE       the SAME enumeration, run before the uninstall, found
                        these things PRESENT. Held on disk and compared.
    UN.CTL.AFTER        the same enumeration, run AFTER, still finds objects
                        that are genuinely present. A reader stuck on "absent"
                        fails this and voids the phase.
    UN.CTL.DISTROREADER the distro-side reader answers "present" for /etc and
                        /bin/bash, which exist on any live Ubuntu.

  MODES
    Before          enumerate, write the held snapshot, prove the reader sees
                    what is there
    RemoveAll       run the uninstaller through the supported path, enumerate
                    again, compare against the held snapshot
    AfterKeepLinux  enumerate the DISTRO INTERNALS after a keep-Linux
                    uninstall, which is the only pass in which the v1.4.1
                    changes execute at all
#>
param(
    [ValidateSet('Before','RemoveAll','AfterKeepLinux')][string]$Mode = 'Before',
    [string]$Transcript  = 'C:\cfv\uninstall-out-probe.txt',
    [string]$Snapshot    = 'C:\cfv\uninstall-before.json',
    [string]$ResultsJson = 'C:\cfv\uninstall-results.json'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name "ClawFactory v1.4.1 uninstall, mode=$Mode" `
    -Transcript $Transcript -Sentinel 'UNINSTALL_PROBE_COMPLETE'

function Finish($code) { W ''; W "UNINSTALL_PROBE_COMPLETE rc=$code"; exit $code }

$APPDIR = 'C:\Program Files\ClawFactory'
$PDDIR  = 'C:\ProgramData\ClawFactory'

# The 34 preflight resources, copied from interim-v120-phase1.ps1 so this probe
# does not depend on that one being staged. A HELD COPY, and it is compared
# against the directory rather than trusted: an uncompared copy is a second
# stale list, not independence.
$REQUIRED = @(
    'safety-rules.md','persona.md','openclaw-shim.sh','clawfactory-turn-gate.sh',
    'clawfactory-spend-check.js','install-turn-gate.sh','freeze-injected-soul.sh',
    'clawfactory-proxy.js','clawfactory-proxy.service','install-chat-proxy.sh',
    'gateway-wait.sh',
    'quarantine-lib.js','clawfactory-quarantined.js','clawfactory-quarantinectl.js',
    'clawfactory-quarantine-rm.js','clawfactory-quarantine.service',
    'clawfactory-quarantine-gc.service','clawfactory-quarantine-gc.timer',
    'install-quarantine.sh',
    'send-lib.js','send-smtp.js','clawfactory-sendd.js','clawfactory-sendctl.js',
    'clawfactory-send.js','clawfactory-send.service','clawfactory-send-gc.service',
    'clawfactory-send-gc.timer','clawfactory-fw-assert.sh','egress-policy.json',
    'install-send.sh',
    'clawfactory-read-fetch.sh','clawfactory-fetchctl.js','install-read-fetch.sh',
    'clawfactory-toolchain.sh'
)

function Get-UninstallRegKeys {
    $hives = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $hits = @()
    foreach ($h in $hives) {
        if (-not (Test-Path $h)) { continue }
        foreach ($k in (Get-ChildItem $h -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -like '*ClawFactory*') {
                $hits += [pscustomobject]@{
                    Key = $k.PSChildName; Hive = $h
                    DisplayName = $p.DisplayName; DisplayVersion = $p.DisplayVersion
                    UninstallString = $p.UninstallString
                }
            }
        }
    }
    return @($hits)
}

function Get-WinInventory {
    $inv = [ordered]@{}
    $inv.appDir          = [bool](Test-Path -LiteralPath $APPDIR)
    $resDir              = Join-Path $APPDIR 'resources'
    $inv.resourcesFound  = if (Test-Path -LiteralPath $resDir) {
                               @($REQUIRED | Where-Object { Test-Path -LiteralPath (Join-Path $resDir $_) }).Count
                           } else { 0 }
    $inv.uninsExe        = [bool](Test-Path -LiteralPath (Join-Path $APPDIR 'unins000.exe'))
    $inv.programData     = [bool](Test-Path -LiteralPath $PDDIR)
    # [string] IS LOAD-BEARING, NOT DECORATION. Get-Content -Raw returns a string
    # carrying the provider's PSPath/PSDrive/Provider NoteProperties, and
    # ConvertTo-Json -Depth 6 serialises that whole object graph. Measured on
    # cfv-176: a 108-byte .wslconfig produced a 100,420,570-byte snapshot, which
    # the comparison pass would then have had to parse back. Cast at the point of
    # capture so the snapshot holds text and nothing else.
    $inv.installResult   = if (Test-Path -LiteralPath (Join-Path $PDDIR 'install-result.txt')) {
                               [string]((Get-Content -LiteralPath (Join-Path $PDDIR 'install-result.txt') -Raw).Trim())
                           } else { '(absent)' }
    $keys                = @(Get-UninstallRegKeys)
    $inv.regKeys         = $keys
    $inv.regKeyCount     = $keys.Count
    $inv.startMenu       = @(@(
        'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\ClawFactory',
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\ClawFactory"
    ) | Where-Object { Test-Path -LiteralPath $_ })
    $inv.startMenuCount  = @($inv.startMenu).Count
    $inv.desktopIcons    = @(@(
        'C:\Users\Public\Desktop\ClawFactory.lnk',
        "$env:USERPROFILE\Desktop\ClawFactory.lnk"
    ) | Where-Object { Test-Path -LiteralPath $_ })
    $inv.desktopCount    = @($inv.desktopIcons).Count
    $inv.studioDir       = [bool](Test-Path -LiteralPath "$env:LOCALAPPDATA\Programs\ClawFactory Studio")
    $inv.wslConfig       = [bool](Test-Path -LiteralPath "$env:USERPROFILE\.wslconfig")
    $inv.wslConfigText   = if ($inv.wslConfig) { [string](Get-Content -LiteralPath "$env:USERPROFILE\.wslconfig" -Raw) } else { '(absent)' }

    $tasks = @()
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
                   Where-Object { $_.TaskName -like '*ClawFactory*' -or $_.TaskName -like '*ClawAgent*' } |
                   ForEach-Object { "$($_.TaskPath)$($_.TaskName)" })
    } catch {}
    $inv.tasks      = $tasks
    $inv.taskCount  = $tasks.Count

    # cmdkey /list prints TARGET NAMES only here. No credential VALUE is read,
    # stored or printed anywhere in this probe.
    $creds = @()
    try {
        $creds = @((cmdkey /list 2>$null) | Where-Object { $_ -match 'Target:' -and $_ -match 'ClawFactory' } |
                   ForEach-Object { $_.Trim() })
    } catch {}
    $inv.credTargets = $creds
    $inv.credCount   = $creds.Count

    # The distro registration, read from the Lxss hive AND from wsl.exe, so a
    # UTF-16 parsing accident in one cannot be the whole answer.
    $lxss = @()
    try {
        $lxss = @(Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue |
                  ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DistributionName } |
                  Where-Object { $_ })
    } catch {}
    $inv.lxssDistros = $lxss
    $wslList = @()
    try { $wslList = @((wsl.exe --list --quiet 2>$null) -replace "`0","" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } catch {}
    $inv.wslList       = $wslList
    $inv.distroPresent = ([bool](@($lxss) -contains 'Ubuntu')) -or ([bool](@($wslList) -contains 'Ubuntu'))
    return $inv
}

# The distro-internal reader. Every line is a NAMED subject, and the last two
# lines are the reader's own control: paths that MUST exist on any live Ubuntu.
$DISTRO_BODY = @'
echo "DISTRO_ALIVE=yes"
echo "UNIT_FILE=$( [ -f /etc/systemd/system/clawfactory-egress-refresh.service ] && echo present || echo absent )"
echo "UNIT_WANTS=$( [ -e /etc/systemd/system/multi-user.target.wants/clawfactory-egress-refresh.service ] && echo present || echo absent )"
echo "UNIT_ISENABLED=$(systemctl is-enabled clawfactory-egress-refresh.service 2>&1 | head -1)"
echo "BOOT_SCRIPT=$( [ -f /usr/local/sbin/clawfactory-egress-refresh.sh ] && echo present || echo absent )"
echo "TOOLCHAIN_SH=$( [ -f /usr/local/sbin/clawfactory-toolchain.sh ] && echo present || echo absent )"
echo "READFETCH_SH=$( [ -f /usr/local/sbin/clawfactory-read-fetch.sh ] && echo present || echo absent )"
echo "FETCHCTL=$( [ -f /usr/local/sbin/clawfactory-fetchctl.js ] && echo present || echo absent )"
echo "TURNGATE=$( [ -f /usr/local/sbin/clawfactory-turn-gate.sh ] && echo present || echo absent )"
echo "PROXY_JS=$( [ -f /usr/local/sbin/clawfactory-proxy.js ] && echo present || echo absent )"
echo "SBIN_CLAWFACTORY_COUNT=$(ls -1 /usr/local/sbin/clawfactory-* 2>/dev/null | wc -l | tr -d ' ')"
echo "ETC_CLAWFACTORY=$( [ -d /etc/clawfactory ] && echo present || echo absent )"
echo "IPS_MAPS=$(ls -1 /etc/clawfactory/*-ips.map 2>/dev/null | wc -l | tr -d ' ')"
echo "UNIT_FILES_CLAWFACTORY=$(ls -1 /etc/systemd/system/clawfactory-* 2>/dev/null | wc -l | tr -d ' ')"
if nft list table inet clawfactory >/dev/null 2>&1; then echo "NFT_TABLE=present"; else echo "NFT_TABLE=absent"; fi
echo "NFT_CHAINS=$(nft list table inet clawfactory 2>/dev/null | grep -c 'chain ')"
echo "CLAWUSER=$( id -u clawuser >/dev/null 2>&1 && echo present || echo absent )"
echo "CLAWUSER_HOME=$( [ -d /home/clawuser ] && echo present || echo absent )"
echo "OPENCLAW_BIN=$( [ -e /usr/bin/openclaw ] && echo present || echo absent )"
echo "READER_CTL_ETC=$( [ -d /etc ] && echo present || echo absent )"
echo "READER_CTL_BASH=$( [ -x /bin/bash ] && echo present || echo absent )"
'@

function Read-Distro {
    $r = Invoke-WslFile -Tag "uninv-$Mode" -User 'root' -Body $DISTRO_BODY
    foreach ($ln in @($r.Out -split "`r?`n" | Where-Object { $_ -match '=' })) { W "   DISTRO> $ln" }
    return $r
}

function Val([string]$text, [string]$key) {
    if ($text -match "(?m)^$([regex]::Escape($key))=(.*)$") { return $Matches[1].Trim() }
    return '(not reported)'
}

function Dump-Inventory($inv, $tag) {
    foreach ($k in $inv.Keys) {
        if ($k -in @('regKeys','wslConfigText')) { continue }
        W ("   {0}> {1} = {2}" -f $tag, $k, (($inv[$k] | Out-String).Trim() -replace "`r?`n", ' | '))
    }
    foreach ($rk in $inv.regKeys) { W "   REG> $($rk.Hive)\$($rk.Key)  '$($rk.DisplayName)' v$($rk.DisplayVersion)" }
}

# =============================================================================
if ($Mode -eq 'Before') {
    Section '1. Enumerate what a machine with v1.4.1 installed actually has'
    $inv = Get-WinInventory
    Dump-Inventory $inv 'WIN'

    Section '2. The reader is proven able to SEE resources that ARE present'
    $sees = ($inv.appDir -and $inv.resourcesFound -eq $REQUIRED.Count -and $inv.regKeyCount -ge 1 -and $inv.uninsExe)
    Register-Control -Id 'UN.CTL.BEFORE' -Name 'the enumeration finds the install that IS on this box' `
        -Fired $sees `
        -Evidence "appDir=$($inv.appDir) resources=$($inv.resourcesFound)/$($REQUIRED.Count) uninstaller=$($inv.uninsExe) uninstall-registry-keys=$($inv.regKeyCount). An all-absent result after the uninstall means nothing without this." | Out-Null

    $bogus = [bool](Test-Path -LiteralPath 'C:\Program Files\ClawFactory-b7f31c-does-not-exist')
    Record 'UN.0b' 'NEGATIVE CONTROL: the reader does not report an absent path as present' `
        $(if (-not $bogus) { 'PASS' } else { 'FAIL' }) `
        "Test-Path on a path that has never existed returned $bogus (must be False)."

    Section '3. The distro side, before'
    $d = Read-Distro
    $dtext = $d.Out
    $readerOk = ((Val $dtext 'READER_CTL_ETC') -eq 'present') -and ((Val $dtext 'READER_CTL_BASH') -eq 'present')
    Register-Control -Id 'UN.CTL.DISTROREADER' -Name 'the distro reader answers present for things that ARE present' `
        -Fired $readerOk -Evidence "READER_CTL_ETC=$(Val $dtext 'READER_CTL_ETC') READER_CTL_BASH=$(Val $dtext 'READER_CTL_BASH')" | Out-Null

    $distro = [ordered]@{}
    foreach ($key in @('DISTRO_ALIVE','UNIT_FILE','UNIT_WANTS','UNIT_ISENABLED','BOOT_SCRIPT','TOOLCHAIN_SH',
                       'READFETCH_SH','FETCHCTL','TURNGATE','PROXY_JS','SBIN_CLAWFACTORY_COUNT','ETC_CLAWFACTORY',
                       'IPS_MAPS','UNIT_FILES_CLAWFACTORY','NFT_TABLE','NFT_CHAINS','CLAWUSER','CLAWUSER_HOME',
                       'OPENCLAW_BIN')) {
        $distro[$key] = (Val $dtext $key)
    }
    $inv.distro = $distro

    Record 'UN.1' 'v1.4.1 is installed and its boot refresh unit IS registered' `
        $(if ($sees -and $distro.UNIT_ISENABLED -eq 'enabled') { 'PASS' } else { 'FAIL' }) `
        "registry=$($inv.regKeyCount) key(s) '$(@($inv.regKeys | ForEach-Object { $_.DisplayName }) -join '; ')', resources=$($inv.resourcesFound)/$($REQUIRED.Count), clawfactory-egress-refresh.service is-enabled='$($distro.UNIT_ISENABLED)', nft table=$($distro.NFT_TABLE) with $($distro.NFT_CHAINS) chain(s), /usr/local/sbin/clawfactory-* count=$($distro.SBIN_CLAWFACTORY_COUNT)."

    $inv | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Snapshot -Encoding UTF8
    $snapBytes = (Get-Item $Snapshot).Length
    W "held snapshot written to $Snapshot ($snapBytes bytes)"
    # The snapshot is an INSTRUMENT and can fail in its own way. First run on
    # cfv-176 wrote 100,420,570 bytes from a box whose largest captured file is
    # 108 bytes, because an uncast Get-Content -Raw dragged the provider object
    # graph into ConvertTo-Json. It would have been parsed straight back in the
    # comparison pass. Bound it, and fail loudly rather than quietly.
    Record 'UN.1b' 'the held snapshot is a plausible size for what it captured' `
        $(if ($snapBytes -lt 262144) { 'PASS' } else { 'FAIL' }) `
        "snapshot=$snapBytes bytes, ceiling=262144. This box's captured text totals a few kilobytes; anything near a megabyte means an object graph was serialised instead of a value, and the comparison pass would have to parse it back."
    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UNINSTALL'
    Finish 0
}

# =============================================================================
if ($Mode -eq 'RemoveAll') {
    Section '1. The supported path: the uninstaller Windows itself would launch'

    $before = $null
    $haveBefore = Require-Precondition -Id 'UN.PRE.SNAP' -Name 'the held BEFORE snapshot exists' `
        -Met (Test-Path -LiteralPath $Snapshot) `
        -Reason 'without the enumeration taken before the uninstall there is nothing to compare against, and an all-absent reading proves nothing'
    if (-not $haveBefore) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UNINSTALL'; Finish 4 }
    $before = Get-Content -LiteralPath $Snapshot -Raw | ConvertFrom-Json

    # The path a user actually takes is Settings > Apps > Installed apps >
    # Uninstall, which launches the binary named in the registry's
    # UninstallString. Read it and use THAT, rather than assuming the path.
    $keys = @(Get-UninstallRegKeys)
    $us   = if ($keys.Count -ge 1) { $keys[0].UninstallString } else { '' }
    W "registry UninstallString: $us"
    $exe = ($us -replace '^"','' -replace '".*$','').Trim()
    if (-not $exe) { $exe = Join-Path $APPDIR 'unins000.exe' }
    W "resolved uninstaller binary: $exe"

    $canRun = Require-Precondition -Id 'UN.PRE.EXE' -Name 'the uninstaller named by the registry exists on disk' `
        -Met (Test-Path -LiteralPath $exe) `
        -Reason 'the supported path launches exactly this binary; if it is absent the user has no uninstall at all'
    if (-not $canRun) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UNINSTALL'; Finish 4 }

    Record 'UN.2a' 'The Settings > Apps entry points at the shipped uninstaller' `
        $(if ($exe -like "$APPDIR*") { 'PASS' } else { 'FAIL' }) `
        "UninstallString resolves to '$exe', inside the application directory. This is the binary a user reaches from Settings; running it with /SILENT takes the same CurUninstallStepChanged path and the same DoRemoveAll=true branch that the interactive dialog's DEFAULT button (Yes) selects. The only thing not exercised here is the MessageBox render itself, and the keep-Linux branch is measured separately in mode AfterKeepLinux."

    $sw = [Diagnostics.Stopwatch]::StartNew()
    Start-Process -FilePath $exe -ArgumentList '/SILENT','/SUPPRESSMSGBOXES','/NORESTART' -Wait
    $sw.Stop()
    W "uninstaller returned after $([int]$sw.Elapsed.TotalSeconds)s"
    # Inno's unins000.exe copies itself to %TEMP% and relaunches, so the process
    # we waited on can return before the copy has finished. Wait on STATE.
    foreach ($i in 1..40) {
        if (-not (Test-Path -LiteralPath (Join-Path $APPDIR 'unins000.exe'))) { break }
        Start-Sleep -Seconds 15
    }
    W "waited on state, not on a sleep: appDir present after wait = $([bool](Test-Path -LiteralPath $APPDIR))"

    $ulog = Join-Path $env:TEMP 'ClawFactory-Uninstall.log'
    $ulogText = if (Test-Path -LiteralPath $ulog) { Get-Content -LiteralPath $ulog -Raw } else { '' }
    foreach ($ln in @($ulogText -split "`r?`n" | Where-Object { $_ -match 'DoRemoveAll|Step \d|unregister|WARN|ERROR' })) { W "   ULOG> $ln" }

    Assert-Searchable -Id 'UN.CTL.ULOG' -Name 'the uninstall log' `
        -PositiveMarkerFound ($ulogText -match 'ClawFactory uninstall starting') `
        -MarkerDescription "the uninstaller's own opening line" | Out-Null

    Record 'UN.2b' 'The uninstaller took the RemoveAll branch and said so in its own log' `
        $(if ($ulogText -match 'Resolved DoRemoveAll = True') { 'PASS' } else { 'FAIL' }) `
        "it records its own branch decision rather than leaving it to be inferred: $((@($ulogText -split "`r?`n" | Where-Object { $_ -match 'Resolved DoRemoveAll' })) -join ' ')"

    Section '2. Read back: what is left'
    $after = Get-WinInventory
    Dump-Inventory $after 'AFTER'

    # THE AFTER-CONTROL. A reader that has broken and now answers absent to
    # everything would pass every row below. C:\cfv is on this box and is not
    # something the uninstaller touches.
    $cfv = [bool](Test-Path -LiteralPath 'C:\cfv')
    $cmd = [bool](Test-Path -LiteralPath 'C:\Windows\System32\cmd.exe')
    Register-Control -Id 'UN.CTL.AFTER' -Name 'the enumeration still sees objects that ARE present after the uninstall' `
        -Fired ($cfv -and $cmd) `
        -Evidence "C:\cfv present=$cfv, C:\Windows\System32\cmd.exe present=$cmd. Both must be True or every absence below is an artefact of a broken reader rather than a property of the product." | Out-Null

    Compare-Independent -Id 'UN.3z' -Name 'the held BEFORE snapshot recorded a complete install' `
        -Mine "$($REQUIRED.Count)" -Reported "$($before.resourcesFound)" `
        -MineLabel 'this probe''s held resource list' -ReportedLabel 'the snapshot taken before the uninstall' | Out-Null

    $rows = @(
        @{ id='UN.3a'; n='the application directory is gone';                v=(-not $after.appDir);          e="Test-Path '$APPDIR' = $($after.appDir) (before: $($before.appDir))" },
        @{ id='UN.3b'; n='none of the 34 security resources survive';        v=($after.resourcesFound -eq 0); e="resources found after = $($after.resourcesFound) of $($REQUIRED.Count) (before: $($before.resourcesFound))" },
        @{ id='UN.3c'; n='the uninstall registry entry is gone';             v=($after.regKeyCount -eq 0);    e="uninstall keys matching ClawFactory after = $($after.regKeyCount) (before: $($before.regKeyCount)). A stale entry leaves a dead Uninstall button in Settings." },
        @{ id='UN.3d'; n='ProgramData\ClawFactory is gone';                  v=(-not $after.programData);     e="Test-Path '$PDDIR' = $($after.programData) (before: $($before.programData)). This held install-result.txt, checkpoint.json and the install log." },
        @{ id='UN.3e'; n='Start Menu entries are gone';                      v=($after.startMenuCount -eq 0); e="Start Menu ClawFactory groups after = $($after.startMenuCount) (before: $($before.startMenuCount))" },
        @{ id='UN.3f'; n='desktop icons are gone';                           v=($after.desktopCount -eq 0);   e="desktop .lnk after = $($after.desktopCount) (before: $($before.desktopCount))" },
        @{ id='UN.3g'; n='scheduled tasks are gone';                         v=($after.taskCount -eq 0);      e="ClawFactory scheduled tasks after = $($after.taskCount) [$(@($after.tasks) -join ', ')] (before: $($before.taskCount) [$(@($before.tasks) -join ', ')])" },
        @{ id='UN.3h'; n='the WSL distro is unregistered';                   v=(-not $after.distroPresent);   e="Lxss hive distros after = [$(@($after.lxssDistros) -join ', ')]; wsl --list --quiet = [$(@($after.wslList) -join ', ')] (before Lxss: [$(@($before.lxssDistros) -join ', ')]). Two independent reads of the same fact." }
    )
    foreach ($r in $rows) { Record $r.id $r.n $(if ($r.v) { 'PASS' } else { 'FAIL' }) $r.e }

    Section '3. What is deliberately left behind, named rather than discovered'
    Record 'UN.4a' 'Credential Manager targets, reported as a fact rather than asserted' 'INFO' `
        "ClawFactory credential targets after = $($after.credCount) [$(@($after.credTargets) -join '; ')] (before: $($before.credCount)). Target NAMES only; no credential value is read or printed by this probe."
    Record 'UN.4b' 'ClawFactory Studio is a per-user app with its own uninstaller' 'INFO' `
        "%LOCALAPPDATA%\Programs\ClawFactory Studio present after = $($after.studioDir) (before: $($before.studioDir))."
    Record 'UN.4c' '.wslconfig is edited surgically rather than deleted' 'INFO' `
        "%USERPROFILE%\.wslconfig present after = $($after.wslConfig). Content: $(($after.wslConfigText -replace "`r?`n",' | ').Trim())"

    Section '4. The distro is gone, so its internals are gone with it'
    $d = Read-Distro
    Record 'UN.5' 'the distro reader can no longer reach a ClawFactory distro' `
        $(if ($d.Out -notmatch 'DISTRO_ALIVE=yes') { 'PASS' } else { 'FAIL' }) `
        "the same reader that answered DISTRO_ALIVE=yes before the uninstall now returns: $(((@($d.Out -split "`r?`n" | Where-Object { $_ })) | Select-Object -First 3) -join ' / '). rc=$($d.Rc)"

    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UNINSTALL'
    Finish 0
}

# =============================================================================
if ($Mode -eq 'AfterKeepLinux') {
    Section '1. The keep-Linux branch is the ONLY branch in which the v1.4.1 changes run'
    W 'The v1.4.1 diff to uninstall.ps1 sits entirely inside the else of the DoRemoveAll'
    W 'decision. On RemoveAll, wsl --unregister deletes the distro and none of it executes.'

    $ulog = Join-Path $env:TEMP 'ClawFactory-Uninstall.log'
    $ulogText = if (Test-Path -LiteralPath $ulog) { Get-Content -LiteralPath $ulog -Raw } else { '' }
    foreach ($ln in @($ulogText -split "`r?`n" | Where-Object { $_ -match 'DoRemoveAll|Step 6|quarantine|WARN|ERROR' })) { W "   ULOG> $ln" }

    Assert-Searchable -Id 'UN.K.CTL.ULOG' -Name 'the uninstall log' `
        -PositiveMarkerFound ($ulogText -match 'ClawFactory uninstall starting') `
        -MarkerDescription "the uninstaller's own opening line" | Out-Null

    $keptBranch = [bool]($ulogText -match 'Resolved DoRemoveAll = False')
    $ok = Require-Precondition -Id 'UN.K.PRE' -Name 'the uninstaller actually took the KEEP-LINUX branch' `
        -Met $keptBranch `
        -Reason 'if it took RemoveAll instead, the distro is gone, the changed lines never ran, and everything below would be measuring the wrong thing'

    $win = Get-WinInventory
    Dump-Inventory $win 'AFTERK'

    Record 'UN.K.1' 'the Windows side is removed on this branch too' `
        $(if ((-not $win.appDir) -and $win.regKeyCount -eq 0) { 'PASS' } else { 'FAIL' }) `
        "appDir=$($win.appDir) uninstall-registry-keys=$($win.regKeyCount). Keeping the Linux environment must not keep the product."

    Record 'UN.K.2' 'the distro is STILL registered, which is what this branch promises' `
        $(if ($win.distroPresent) { 'PASS' } else { 'FAIL' }) `
        "Lxss=[$(@($win.lxssDistros) -join ', ')] wsl=[$(@($win.wslList) -join ', ')]. The dialog says: 'Selecting NO leaves the Ubuntu distro registered.'"

    Section '2. Inside the kept distro: what the v1.4.1 lines were supposed to remove'
    $d = Read-Distro
    $t = $d.Out
    $readerOk = ((Val $t 'READER_CTL_ETC') -eq 'present') -and ((Val $t 'READER_CTL_BASH') -eq 'present')
    Register-Control -Id 'UN.K.CTL.READER' -Name 'the distro reader answers present for things that ARE present' `
        -Fired $readerOk -Evidence "READER_CTL_ETC=$(Val $t 'READER_CTL_ETC') READER_CTL_BASH=$(Val $t 'READER_CTL_BASH'). Without this, every absent below is an artefact." | Out-Null

    $krows = @(
        @{ id='UN.K.3a'; n='the v1.4.1 boot refresh UNIT FILE is removed';        v=((Val $t 'UNIT_FILE') -eq 'absent');    e="/etc/systemd/system/clawfactory-egress-refresh.service = $(Val $t 'UNIT_FILE')" },
        @{ id='UN.K.3b'; n='its ENABLEMENT is removed, not just the file';        v=((Val $t 'UNIT_WANTS') -eq 'absent');   e="multi-user.target.wants symlink = $(Val $t 'UNIT_WANTS'); systemctl is-enabled says '$(Val $t 'UNIT_ISENABLED')'. An enabled unit pointing at nothing is a failed unit in the journal of a machine that no longer has ClawFactory on it." },
        @{ id='UN.K.3c'; n='the boot refresh SCRIPT is removed';                  v=((Val $t 'BOOT_SCRIPT') -eq 'absent');  e="/usr/local/sbin/clawfactory-egress-refresh.sh = $(Val $t 'BOOT_SCRIPT')" },
        @{ id='UN.K.3d'; n='clawfactory-toolchain.sh is removed (the v1.4.1 fix)'; v=((Val $t 'TOOLCHAIN_SH') -eq 'absent'); e="/usr/local/sbin/clawfactory-toolchain.sh = $(Val $t 'TOOLCHAIN_SH'). This was the pre-existing leftover v1.4.1 added to the rm list." },
        @{ id='UN.K.3e'; n='the read-fetch resolver and control tool are removed'; v=(((Val $t 'READFETCH_SH') -eq 'absent') -and ((Val $t 'FETCHCTL') -eq 'absent')); e="read-fetch.sh=$(Val $t 'READFETCH_SH') fetchctl.js=$(Val $t 'FETCHCTL')" },
        @{ id='UN.K.3f'; n='no clawfactory-* helper survives in /usr/local/sbin'; v=((Val $t 'SBIN_CLAWFACTORY_COUNT') -eq '0'); e="ls /usr/local/sbin/clawfactory-* counted $(Val $t 'SBIN_CLAWFACTORY_COUNT')" },
        @{ id='UN.K.3g'; n='/etc/clawfactory is removed, and the v1.4.1 retention maps with it'; v=((Val $t 'ETC_CLAWFACTORY') -eq 'absent'); e="/etc/clawfactory = $(Val $t 'ETC_CLAWFACTORY'); *-ips.map files counted $(Val $t 'IPS_MAPS')" },
        @{ id='UN.K.3h'; n='no clawfactory-* systemd unit file survives';         v=((Val $t 'UNIT_FILES_CLAWFACTORY') -eq '0'); e="ls /etc/systemd/system/clawfactory-* counted $(Val $t 'UNIT_FILES_CLAWFACTORY')" },
        @{ id='UN.K.3i'; n='THE FIREWALL TABLE IS GONE';                          v=((Val $t 'NFT_TABLE') -eq 'absent');    e="nft list table inet clawfactory = $(Val $t 'NFT_TABLE'), chains counted $(Val $t 'NFT_CHAINS'). A firewall rule that survives an uninstall is not a defensible leftover." },
        @{ id='UN.K.3j'; n='the openclaw binary is removed';                      v=((Val $t 'OPENCLAW_BIN') -eq 'absent'); e="/usr/bin/openclaw = $(Val $t 'OPENCLAW_BIN')" }
    )
    foreach ($r in $krows) { Record $r.id $r.n $(if ($r.v) { 'PASS' } else { 'FAIL' }) $r.e }

    Section '3. What this branch deliberately keeps, and whether keeping it is right'
    Record 'UN.K.4a' 'clawuser and its home are USER DATA on this branch' 'INFO' `
        "clawuser=$(Val $t 'CLAWUSER') /home/clawuser=$(Val $t 'CLAWUSER_HOME'). The dialog promises exactly this: 'Your conversation history and agent configs stay on disk. You can re-install ClawFactory later and reuse the existing distro.' User data surviving is correct here. A firewall rule or a systemd unit surviving would NOT be, and UN.K.3b and UN.K.3i are the two rows that decide that."

    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UNINSTALL'
    Finish 0
}
