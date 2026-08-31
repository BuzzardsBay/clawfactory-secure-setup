<#
  interim-v146-runner.ps1 -- the BUILD-MACHINE side of the reboot-persistence
  measurement. Run from C:\Users\bmcki\ClawFactory-Secure-Setup.

  It does not provision. Provisioning sets the admin password and that is the
  operator's, once, at creation.

  WHY THE JOB-FILE MECHANISM AND NOT run-command DIRECTLY
  -------------------------------------------------------
  `az vm run-command invoke` runs as NT AUTHORITY\SYSTEM, and `wsl.exe` refuses
  LocalSystem by name. Every WSL-level step -- including the INSTALL, because
  setup.ps1 reads `wsl --status` and would take the reboot-and-resume branch on
  a -1 exit -- must execute inside the interactive clawadmin session. So
  run-command is used ONLY to drop job files into C:\cfv\jobs and to read the
  .out and .done files back, exactly as interim-v120-runner.ps1's header
  requires. The operator starts that runner once, from an elevated PowerShell,
  and again after the reboot, because auto-logon is a one-shot.

  ONE az vm run-command invoke AT A TIME. They queue and interfere, and a
  TaskStop does NOT cancel one in flight -- the next dispatch dies with
  (Conflict). Every -Step below is one dispatch, or one dispatch plus a poll.

  ORDER IS LOAD-BEARING:

    step        what it does                             why here
    ----------  ---------------------------------------  -----------------------
    install     the SHIPPED v1.4.5 installer, digest-     nothing measured yet
                gated, in the interactive session
    pre         census + guards, BEFORE any restart      the baseline. Without
                                                         it, "does not survive"
                                                         and "never held" are
                                                         the same reading
    wslcycle    wsl --shutdown, distro back, re-census   systemd half alone
    reboot      az vm restart                            the control boundary
    post        census + guards after the real reboot    THE measurement
    inject      TASK 2, the calibrated fault             LAST, so it cannot
                                                         pollute the subject
    fetch       pull every transcript and results file   before teardown
    teardown    NIC first, then unfiltered residual      the ledger
#>
param(
    [string]$Vm  = 'cfv-191',
    [string]$Rg  = 'clawfactory-validation',
    [Parameter(Mandatory)]
    [ValidateSet('runnerstatus','install','pre','wslcycle','reboot','post','inject','fetch','teardown','deallocate','start')]
    [string]$Step,
    [string]$OutDir = 'C:\Users\bmcki\ClawFactory-Secure-Setup\validation\diag',
    [int]$TimeoutMinutes = 60
)

$ErrorActionPreference = 'Continue'
$scratch = Join-Path $env:TEMP 'cfv146'
foreach ($d in @($scratch, $OutDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

function Invoke-Box {
    <# ONE dispatch. Payload goes to a file and is passed as @file, because az on
       Windows is az.cmd and cmd.exe re-parses an inline --scripts argument.
       Reads BOTH streams and checks the exit code. #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Body)
    $f = Join-Path $scratch "$Name.ps1"
    [IO.File]::WriteAllText($f, $Body, (New-Object Text.UTF8Encoding($false)))
    Write-Host "---- dispatch: $Name ----" -ForegroundColor Cyan
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $res = az vm run-command invoke -g $Rg -n $Vm --command-id RunPowerShellScript --scripts "@$f" -o json
    $rc = $LASTEXITCODE
    Write-Host "az exit=$rc elapsed=$([int]$sw.Elapsed.TotalSeconds)s"
    if ($rc -ne 0) { Write-Host "DISPATCH FAILED -- do not run the next step until this is understood." -ForegroundColor Red; return $null }
    $o = $res | ConvertFrom-Json
    foreach ($m in $o.value) { Write-Host "== $($m.code) =="; Write-Host $m.message }
    return $o
}

function Start-Job-And-Wait {
    <# Drop a job file for the on-VM runner, then poll for its .done barrier.
       The runner writes .out first and .done LAST, so .done is the read barrier
       and a partial .out can never be read as a complete one.

       The runner's heartbeat STALLS while a job runs -- it ticks at the top of
       the poll loop and the job executes inside it -- so a stale heartbeat
       during a long install is expected and is not a dead runner. #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$JobBody, [int]$Minutes = 60)

    $drop = @"
`$ErrorActionPreference='Continue'
New-Item -ItemType Directory -Path C:\cfv\jobs -Force | Out-Null
Remove-Item 'C:\cfv\jobs\$Name.done','C:\cfv\jobs\$Name.out' -Force -ErrorAction SilentlyContinue
`$b = [Convert]::FromBase64String('$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($JobBody)))')
[IO.File]::WriteAllBytes('C:\cfv\jobs\$Name.job.ps1', `$b)
Write-Output "job dropped: `$((Get-Item 'C:\cfv\jobs\$Name.job.ps1').Length) bytes"
Write-Output "runner heartbeat: `$(if (Test-Path 'C:\cfv\jobs\_runner.heartbeat') { Get-Content 'C:\cfv\jobs\_runner.heartbeat' -Raw } else { 'NO HEARTBEAT FILE -- the runner is not started' })"
"@
    if (-not (Invoke-Box -Name "drop-$Name" -Body $drop)) { return $null }

    $poll = @"
`$ErrorActionPreference='Continue'
if (Test-Path 'C:\cfv\jobs\$Name.done') {
    Write-Output 'JOB_DONE=yes'
    Write-Output ('---- ' + '$Name' + '.out ----')
    Get-Content 'C:\cfv\jobs\$Name.out' -Raw
} else {
    Write-Output 'JOB_DONE=no'
    Write-Output "heartbeat: `$(if (Test-Path 'C:\cfv\jobs\_runner.heartbeat') { Get-Content 'C:\cfv\jobs\_runner.heartbeat' -Raw } else { 'ABSENT' })"
    Write-Output "out so far: `$(if (Test-Path 'C:\cfv\jobs\$Name.out') { (Get-Item 'C:\cfv\jobs\$Name.out').Length } else { 0 }) bytes"
}
"@
    $deadline = (Get-Date).AddMinutes($Minutes)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 60
        $o = Invoke-Box -Name "poll-$Name" -Body $poll
        if ($null -eq $o) { continue }
        $txt = ($o.value | ForEach-Object { $_.message }) -join "`n"
        if ($txt -match 'JOB_DONE=yes') {
            [IO.File]::WriteAllText((Join-Path $OutDir "v146-$Name.out.txt"), $txt, (New-Object Text.UTF8Encoding($false)))
            Write-Host "job $Name complete; saved to $OutDir\v146-$Name.out.txt" -ForegroundColor Green
            return $txt
        }
    }
    Write-Host "job $Name did NOT complete within $Minutes minutes. Read the .out before concluding anything -- a probe that dies early is invisible in the transcript by construction." -ForegroundColor Red
    return $null
}

function Stage-Job([string]$stage) {
    return "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\cfv\interim-v146-unitpersist.ps1 -Stage $stage 2>&1 | Out-String | Write-Output"
}

switch ($Step) {

'runnerstatus' {
    Invoke-Box -Name 'runnerstatus' -Body @'
$ErrorActionPreference='Continue'
Write-Output "C:\cfv contents:"
Get-ChildItem C:\cfv -File -ErrorAction SilentlyContinue | ForEach-Object { "  {0}  {1} bytes" -f $_.Name, $_.Length }
Write-Output "jobs dir:"
Get-ChildItem C:\cfv\jobs -ErrorAction SilentlyContinue | ForEach-Object { "  {0}  {1} bytes  {2}" -f $_.Name, $_.Length, $_.LastWriteTime }
Write-Output "heartbeat: $(if (Test-Path 'C:\cfv\jobs\_runner.heartbeat') { Get-Content 'C:\cfv\jobs\_runner.heartbeat' -Raw } else { 'ABSENT -- the runner has not been started in the interactive session' })"
Write-Output "interactive sessions:"
& query.exe session 2>&1 | Out-String | Write-Output
'@
}

'install'  { Start-Job-And-Wait -Name 'install'  -JobBody (Stage-Job 'Install')  -Minutes $TimeoutMinutes }
'pre'      { Start-Job-And-Wait -Name 'pre'      -JobBody (Stage-Job 'Pre')      -Minutes 30 }
'wslcycle' { Start-Job-And-Wait -Name 'wslcycle' -JobBody (Stage-Job 'WslCycle') -Minutes 30 }
'post'     { Start-Job-And-Wait -Name 'post'     -JobBody (Stage-Job 'Post')     -Minutes 30 }
'inject'   { Start-Job-And-Wait -Name 'inject'   -JobBody (Stage-Job 'Inject')   -Minutes 30 }

'reboot' {
    az vm restart -g $Rg -n $Vm -o none
    Write-Host "az vm restart exit=$LASTEXITCODE"
}

'deallocate' {
    az vm deallocate -g $Rg -n $Vm -o none
    Write-Host "az vm deallocate exit=$LASTEXITCODE"
    az vm get-instance-view -g $Rg -n $Vm --query "instanceView.statuses[].code" -o tsv
}

'start' {
    az vm start -g $Rg -n $Vm -o none
    Write-Host "az vm start exit=$LASTEXITCODE"
    az vm get-instance-view -g $Rg -n $Vm --query "instanceView.statuses[].code" -o tsv
    az network public-ip show -g $Rg -n "$Vm-pip" --query ipAddress -o tsv
}

'fetch' {
    $o = Invoke-Box -Name 'fetch' -Body @'
$ErrorActionPreference='Continue'
foreach ($f in @('v146-Install-out.txt','v146-Pre-out.txt','v146-WslCycle-out.txt','v146-Post-out.txt','v146-Inject-out.txt','v146-Install-results.json','v146-Pre-results.json','v146-WslCycle-results.json','v146-Post-results.json','v146-Inject-results.json')) {
    $p = "C:\cfv\$f"
    Write-Output "=============== $f ==============="
    if (Test-Path $p) { Get-Content $p -Raw } else { Write-Output "(absent)" }
}
Write-Output "=============== install.log tail ==============="
if (Test-Path 'C:\ProgramData\ClawFactory\install.log') { Get-Content 'C:\ProgramData\ClawFactory\install.log' -Tail 60 } else { Write-Output '(absent)' }
'@
    if ($o) {
        $txt = ($o.value | ForEach-Object { $_.message }) -join "`n"
        [IO.File]::WriteAllText((Join-Path $OutDir 'v146-all-transcripts.txt'), $txt, (New-Object Text.UTF8Encoding($false)))
        Write-Host "saved to $OutDir\v146-all-transcripts.txt"
    }
}

'teardown' {
    # NIC FIRST -- it references the pip and the nsg.
    az vm delete -g $Rg -n $Vm --yes -o none;                     Write-Host "vm delete exit=$LASTEXITCODE"
    az network nic delete -g $Rg -n "${Vm}VMNic" -o none;          Write-Host "nic delete exit=$LASTEXITCODE"
    az network public-ip delete -g $Rg -n "$Vm-pip" -o none;       Write-Host "pip delete exit=$LASTEXITCODE"
    az network nsg delete -g $Rg -n "$Vm-nsg" -o none;             Write-Host "nsg delete exit=$LASTEXITCODE"
    $disks = az disk list -g $Rg --query "[?starts_with(name,'$Vm')].name" -o tsv
    foreach ($d in ($disks -split "`n" | Where-Object { $_ })) { az disk delete -g $Rg -n $d.Trim() --yes -o none; Write-Host "disk $($d.Trim()) delete exit=$LASTEXITCODE" }
    Write-Host '--- UNFILTERED residual, which is the claim that matters ---'
    az resource list -g $Rg --query "[].[name,type]" -o tsv
    Write-Host '--- re-check, because "it said deleted" is not the same claim as "it is gone" ---'
    Start-Sleep -Seconds 20
    az resource list -g $Rg --query "[].[name,type]" -o tsv
}

}
