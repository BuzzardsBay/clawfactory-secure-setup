<#
  cfv-autologon-proof.ps1 -- prove persistent auto-logon carries the WSL runner across
  reboots, and prove it MATTERS by breaking it. Follows cfv-provision.ps1.

  IT MEASURES NO PRODUCT ROW. The subject is the transport (and, for OM-1, one owed
  surface). The v1.4.5 install in step `install` exists to give OM-1 a subject and to
  give the WSL runner real WSL work; its verdict is recorded, never scored as a
  release row.

  Every WSL job goes through the runner's OWN execution path -- Start-CfvJob -Wsl drops
  a file, CFV-Runner-User picks it up in the auto-logon session -- never a wsl.exe
  invocation typed by this session.

  Steps (order is load-bearing, see docs/session_reports/2026-09-19_persistent_autologon_runplan.md):
    status  reboot  w1  install  w2  disable  noal  enable  restored  om1  teardown  deallocate
#>
param(
    [Parameter(Mandatory)][string]$Vm,
    [Parameter(Mandatory)]
    [ValidateSet('status','reboot','w1','install','w2','disable','noal','enable','restored','om1','teardown','deallocate')]
    [string]$Step,
    [string]$Rg = 'clawfactory-validation',
    [string]$Tag = ''
)

$ErrorActionPreference = 'Continue'
$env:MSYS_NO_PATHCONV = '1'
$here = Split-Path -Parent $PSCommandPath
. (Join-Path $here 'cfv-driverlib.ps1')

$RunIdFile = Join-Path $here "diag\$Vm-runid.txt"
if (-not (Test-Path $RunIdFile)) { throw "no run identity at $RunIdFile -- run cfv-provision.ps1 first" }
$Run = Get-Content $RunIdFile -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $Run.OutDir, $Run.Scratch -Force | Out-Null

function Save-Result($name, $res) {
    $p = Join-Path $Run.OutDir "$name.txt"
    $txt = "CONDITION=$($res.Condition)`nAZEXIT=$($res.AzExit)`nBYTES=$($res.Bytes)`nELAPSED=$($res.ElapsedS)`nSTDERR=$($res.Stderr)`n---- TEXT ----`n$($res.Text)"
    [IO.File]::WriteAllText($p, $txt, (New-Object Text.UTF8Encoding($false)))
    Write-Host "  saved -> $p" -ForegroundColor DarkGray
}

# The state facts every step wants beside its verdict: boot time, sessions, both
# runners' liveness, and the Winlogon arming -- values NEVER echoed, lengths only.
function Get-StateBody { @"
Write-Output "S_BOOT=`$((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('s'))Z"
Write-Output "S_NOW=`$((Get-Date).ToUniversalTime().ToString('s'))Z"
Write-Output "S_QUSER=`$((& query.exe user 2>&1 | Out-String) -replace '\s+',' ')"
`$wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Write-Output "S_AUTOADMINLOGON=`$(`$wl.AutoAdminLogon)"
Write-Output "S_DEFAULTPASSWORD_LEN=`$("`$(`$wl.DefaultPassword)".Length)"
Write-Output "S_AUTOLOGONCOUNT_ABSENT=`$(`$null -eq `$wl.PSObject.Properties['AutoLogonCount'])"
foreach (`$q in @('jobs','wsljobs')) {
    `$hb = '$($Run.RunDir)\'+`$q+'\_runner.heartbeat'
    Write-Output "S_HB_`$q=`$(if (Test-Path `$hb) { (Get-Content `$hb -Raw).Trim() } else { 'ABSENT' })"
}
foreach (`$t in @('CFV-Runner-System','CFV-Runner-User')) {
    Write-Output "S_TASK_`$t=`$(try { (Get-ScheduledTask -TaskName `$t -ErrorAction Stop).State } catch { 'NO-TASK' })"
}
"@ }

# A WSL job. Asserts its own context, then measures with a control that MUST fail.
function Get-WslProbeBody([string]$tag, [switch]$Distro) {
@"
`$env:WSL_UTF8 = '1'
`$id = [Security.Principal.WindowsIdentity]::GetCurrent()
Write-Output "W_TAG=$tag"
Write-Output "W_WHOAMI=`$(`$id.Name)"
Write-Output "W_SESSION=`$([Diagnostics.Process]::GetCurrentProcess().SessionId)"
Write-Output "W_USERINTERACTIVE=`$([Environment]::UserInteractive)"
Write-Output "W_ELEVATED=`$((New-Object Security.Principal.WindowsPrincipal(`$id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
Write-Output "W_BOOT=`$((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('s'))Z"
Write-Output "W_NOW=`$((Get-Date).ToUniversalTime().ToString('s'))Z"
`$wsl = Join-Path `$env:SystemRoot 'System32\wsl.exe'
& `$wsl --status *> `$null
Write-Output "W_STATUS_EXIT=`$LASTEXITCODE"
& `$wsl -d CfvNoSuchDistro-ctl -- /bin/true *> `$null
Write-Output "W_CTL_NOSUCHDISTRO_EXIT=`$LASTEXITCODE"
"@ + $(if ($Distro) { @"

`$o = (& `$wsl -d Ubuntu -u root -- /bin/sh -c 'echo CFV_DISTRO_ALIVE; ps -p 1 -o comm=; exit 0' 2>&1 | Out-String)
Write-Output "W_DISTRO_EXIT=`$LASTEXITCODE"
Write-Output "W_DISTRO_ALIVE=`$(`$o -match 'CFV_DISTRO_ALIVE')"
Write-Output "W_DISTRO_PID1=`$((`$o -split "``r?``n" | Select-Object -Skip 1 -First 1).Trim())"
& `$wsl -d Ubuntu -u root -- /bin/sh -c 'exit 33' *> `$null
Write-Output "W_CTL_DISTRO_EXIT33=`$LASTEXITCODE"
"@ } else { '' })
}

function Read-Kv([string]$text, [string]$key) {
    if ($text -match "(?m)^$([regex]::Escape($key))=(.*)$") { return $Matches[1].Trim() } else { return '(absent)' }
}

function Invoke-WslJob([string]$name, [string]$body, [int]$Minutes = 15) {
    $j = Start-CfvJob -Run $Run -Name $name -JobBody $body -Wsl; Save-Result "$name-drop" $j
    $w = Wait-CfvJob -Run $Run -Name $name -Minutes $Minutes -IntervalSeconds 30 -Wsl; Save-Result "$name-wait" $w
    Write-Host "  WSL job '$name' -> $($w.Condition)" -ForegroundColor $(if ($w.Condition -eq 'JobDone') { 'Green' } else { 'Yellow' })
    $out = $null
    if ($w.Condition -eq 'JobDone') { $out = Receive-CfvJobOutput -Run $Run -Name $name -Wsl; Save-Result "$name-out" $out }
    return @{ Wait = $w; Out = $out }
}

function Judge-Wsl($r, [string]$label) {
    if (-not $r.Out) { Write-Host "  $label : NO OUTPUT ($($r.Wait.Condition))" -ForegroundColor Red; return $false }
    $t = $r.Out.Text
    $who = Read-Kv $t 'W_WHOAMI'; $ses = Read-Kv $t 'W_SESSION'; $st = Read-Kv $t 'W_STATUS_EXIT'; $ctl = Read-Kv $t 'W_CTL_NOSUCHDISTRO_EXIT'
    $notSys = ($who -notmatch 'nt authority\\system') -and ($ses -ne '0') -and ((Read-Kv $t 'W_USERINTERACTIVE') -eq 'True')
    $ok = $notSys -and ($st -eq '0') -and ($ctl -ne '0') -and ($ctl -ne '(absent)')
    Write-Host "  $label : who=$who session=$ses status_exit=$st control(no-such-distro)_exit=$ctl -> $(if ($ok) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    return $ok
}

switch ($Step) {

'status' {
    $r = Invoke-CfvBox -Run $Run -Name 'status' -Body (Get-StateBody); Save-Result 'status' $r
}

'reboot' {
    $r = Restart-CfvBox -Run $Run -WaitMinutes 20 -RunnerGraceSeconds 420 -WaitWslRunner
    Save-Result "reboot-$Tag" $r
    Write-Host "reboot ($Tag) -> $($r.Condition)  $($r.Stderr)" -ForegroundColor $(if ($r.Condition -eq 'Ok') { 'Green' } else { 'Red' })
    $s = Invoke-CfvBox -Run $Run -Name "status-after-reboot-$Tag" -Body (Get-StateBody); Save-Result "state-after-reboot-$Tag" $s
}

'w1' { $r = Invoke-WslJob 'w1' (Get-WslProbeBody 'post-reboot-1'); [void](Judge-Wsl $r 'w1') }

'install' {
    $body = @'
$ProgressPreference = 'SilentlyContinue'
$exe = 'C:\cfv\v145-shipped.exe'
$url = 'https://github.com/BuzzardsBay/clawfactory-secure-setup/releases/download/v1.4.5/ClawFactory-Secure-Setup.exe'
$want = '2fe7dad18c9eab8c005e8ee4bf9a25a6ca08bb761c11d9baf111e3eac0145e87'
Write-Output "INSTALL_WHOAMI=$((& whoami.exe) -join '') SESSION=$([Diagnostics.Process]::GetCurrentProcess().SessionId)"
Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
$got = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
Write-Output "INSTALL_SHA256_MATCH=$($got -eq $want) BYTES=$((Get-Item $exe).Length)"
if ($got -ne $want) { Write-Output 'INSTALL_ABORT_DIGEST_MISMATCH'; exit 2 }
Remove-Item 'C:\ProgramData\ClawFactory\install-result.txt' -Force -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $exe -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/LOG=C:\cfv\autologon-inno.log','/PROVIDER=claude' -PassThru -Wait
$null = $p.Handle
Write-Output "INSTALL_EXIT=$($p.ExitCode)"
$rf = 'C:\ProgramData\ClawFactory\install-result.txt'
Write-Output "INSTALL_RESULT=$(if (Test-Path $rf) { (Get-Content $rf -Raw).Trim() } else { '(ABSENT)' })"
'@
    $r = Invoke-WslJob 'install' $body 60
    if ($r.Out) { Write-Host "  INSTALL_EXIT=$(Read-Kv $r.Out.Text 'INSTALL_EXIT')  INSTALL_RESULT=$(Read-Kv $r.Out.Text 'INSTALL_RESULT')" }
}

'w2' { $r = Invoke-WslJob 'w2' (Get-WslProbeBody 'post-reboot-2' -Distro); [void](Judge-Wsl $r 'w2')
       if ($r.Out) { Write-Host "  distro exec: alive=$(Read-Kv $r.Out.Text 'W_DISTRO_ALIVE') pid1=$(Read-Kv $r.Out.Text 'W_DISTRO_PID1') ctl_exit33=$(Read-Kv $r.Out.Text 'W_CTL_DISTRO_EXIT33')" } }

'disable' {
    # AutoAdminLogon=0 only. DefaultPassword stays, so re-enabling needs NO password --
    # this session no longer holds it.
    $r = Invoke-CfvBox -Run $Run -Name 'disable' -Body @'
$wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $wl -Name AutoAdminLogon -Value '0' -Type String
$p = Get-ItemProperty $wl
Write-Output "DIS_AUTOADMINLOGON=$($p.AutoAdminLogon)"
Write-Output "DIS_DEFAULTPASSWORD_LEN=$("$($p.DefaultPassword)".Length)"
'@
    Save-Result 'disable' $r
}

'noal' {
    # Reboot with auto-logon OFF. The SYSTEM runner must still come back (card #259);
    # the WSL runner must NOT, and that must be VISIBLE.
    $r = Restart-CfvBox -Run $Run -WaitMinutes 20 -RunnerGraceSeconds 240
    Save-Result 'reboot-noal' $r
    Write-Host "reboot (auto-logon OFF) -> $($r.Condition)  (SYSTEM runner: $(if ($r.Condition -eq 'Ok') { 'came back' } else { 'DID NOT' }))" -ForegroundColor Cyan
    Start-Sleep -Seconds 90    # a fair window for a session that is NOT going to appear
    $s = Invoke-CfvBox -Run $Run -Name 'status-noal' -Body (Get-StateBody); Save-Result 'state-noal' $s
    # A WSL job dropped now. It must be visibly unserviced, by NAME.
    $j = Start-CfvJob -Run $Run -Name 'wnoal' -JobBody (Get-WslProbeBody 'auto-logon-OFF' -Distro) -Wsl; Save-Result 'wnoal-drop' $j
    $w = Wait-CfvJob -Run $Run -Name 'wnoal' -Minutes 4 -IntervalSeconds 30 -StaleSeconds 90 -Wsl; Save-Result 'wnoal-wait' $w
    Write-Host "  WSL job with auto-logon OFF -> $($w.Condition)" -ForegroundColor $(if ($w.Condition -in @('RunnerAbsent','RunnerDead')) { 'Green' } else { 'Red' })
    Write-Host "  (a named unserviced condition is the PASS here; JobDone would mean auto-logon was not what made it run)" -ForegroundColor DarkGray
    # CONTROL: a Windows-side job on the SYSTEM queue must still RUN in the same state.
    $sysBody = 'Write-Output ("SYS_WHOAMI=" + ((& whoami.exe) -join ""))'
    $j2 = Start-CfvJob -Run $Run -Name 'sysnoal' -JobBody $sysBody; Save-Result 'sysnoal-drop' $j2
    $w2 = Wait-CfvJob -Run $Run -Name 'sysnoal' -Minutes 6 -IntervalSeconds 20; Save-Result 'sysnoal-wait' $w2
    if ($w2.Condition -eq 'JobDone') { $o = Receive-CfvJobOutput -Run $Run -Name 'sysnoal'; Save-Result 'sysnoal-out' $o; Write-Host "  SYSTEM-queue control ran: $(Read-Kv $o.Text 'SYS_WHOAMI')" -ForegroundColor Green }
    else { Write-Host "  SYSTEM-queue control -> $($w2.Condition)" -ForegroundColor Red }
}

'enable' {
    $r = Invoke-CfvBox -Run $Run -Name 'enable' -Body @'
$wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $wl -Name AutoAdminLogon -Value '1' -Type String
$p = Get-ItemProperty $wl
Write-Output "ENA_AUTOADMINLOGON=$($p.AutoAdminLogon)"
Write-Output "ENA_DEFAULTPASSWORD_LEN=$("$($p.DefaultPassword)".Length)"
Write-Output "ENA_AUTOLOGONCOUNT_ABSENT=$($null -eq $p.PSObject.Properties['AutoLogonCount'])"
'@
    Save-Result 'enable' $r
}

'restored' {
    # The SAME job that sat unserviced ('wnoal') should now be picked up, because the
    # runner exists again. Then a fresh one, so "it drained a backlog" is not the claim.
    $w = Wait-CfvJob -Run $Run -Name 'wnoal' -Minutes 8 -IntervalSeconds 30 -Wsl; Save-Result 'wnoal-wait2' $w
    if ($w.Condition -eq 'JobDone') { $o = Receive-CfvJobOutput -Run $Run -Name 'wnoal' -Wsl; Save-Result 'wnoal-out2' $o; [void](Judge-Wsl @{ Wait = $w; Out = $o } 'wnoal (the job that was unserviced)') }
    $r = Invoke-WslJob 'w3' (Get-WslProbeBody 'auto-logon-RESTORED' -Distro); [void](Judge-Wsl $r 'w3')
}

'om1' { throw 'OM-1 is driven by cfv-om1.ps1 after the plan record is committed' }

'teardown' {
    # Enumerate rather than guess names, NIC first.
    $ids = (& cmd.exe /c "az resource list -g $Rg --query `"[?contains(name,'$Vm')].[id,type]`" -o tsv") | Where-Object { $_ }
    $ids | ForEach-Object { Write-Host "  will delete: $_" -ForegroundColor DarkGray }
    & cmd.exe /c "az vm delete -g $Rg -n $Vm --yes -o none" | Out-Null; Write-Host "vm delete exit=$LASTEXITCODE"
    foreach ($kind in @('networkInterfaces', 'publicIPAddresses', 'networkSecurityGroups', 'disks')) {
        $names = @(& cmd.exe /c "az resource list -g $Rg --resource-type Microsoft.$(if ($kind -eq 'disks') { 'Compute' } else { 'Network' })/$kind --query `"[?contains(name,'$Vm')].name`" -o tsv") | Where-Object { $_ }
        foreach ($n in $names) {
            $cmd = if ($kind -eq 'disks') { "az disk delete -g $Rg -n $n --yes -o none" }
                   elseif ($kind -eq 'networkInterfaces') { "az network nic delete -g $Rg -n $n -o none" }
                   elseif ($kind -eq 'publicIPAddresses') { "az network public-ip delete -g $Rg -n $n -o none" }
                   else { "az network nsg delete -g $Rg -n $n -o none" }
            & cmd.exe /c $cmd | Out-Null; Write-Host "$kind $n delete exit=$LASTEXITCODE"
        }
    }
    Start-Sleep -Seconds 25
    Write-Host '---- unfiltered residual ----'
    & cmd.exe /c "az resource list -g $Rg --query `"[].[name,type]`" -o tsv"
}

'deallocate' { & cmd.exe /c "az vm deallocate -g $Rg -n $Vm -o none"; Write-Host "deallocate exit=$LASTEXITCODE" }
}
