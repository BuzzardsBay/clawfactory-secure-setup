<#
  interim-v145-runner.ps1 -- the BUILD-MACHINE side of the pending-reboot
  reproduction. Run this from C:\Users\bmcki\ClawFactory-Secure-Setup.

  It does not provision. Provisioning sets the admin password and that is the
  operator's, once, at creation. Card 1 in the session close-out carries the
  exact az vm create line. This script picks up from a VM that already exists.

  ONE az vm run-command invoke AT A TIME. They queue and interfere, and a
  TaskStop does NOT cancel one in flight -- the next dispatch dies with
  (Conflict). Each -Step below is exactly one dispatch. Run them in order and
  read each result before running the next.

  ORDER IS LOAD-BEARING:

    stage      what it does                                    why this order
    ---------  ----------------------------------------------  ---------------------------
    prep       upload phaselib + probe + the v1.4.4 exe         nothing measured yet
    A          census, construct pending-reboot state, PR.C1    must run on a virgin box
    install    run the REAL v1.4.4 installer, /VERYSILENT       must precede A2: A2 claims
                                                                the distro name 'Ubuntu'
    fetchA     pull install.log, then MOVE IT ASIDE             the log APPENDS
    A2         PR.C3 / PR.C4 / PR.C5 micro-probes               pollutes 'Ubuntu' on purpose
    reboot     az vm restart, nothing else changed              the control boundary
    B          post-reboot census, PR.CTL2, PR.C1b              proves the reboot landed
    B2         the same micro-probes, post-reboot               the SYSTEM-context control
    cleanA     unregister Ubuntu, clear ProgramData             stage B's installer run must
                                                                start from a clean log
    install2   run the SAME installer again, /VERYSILENT        2.4: did it then succeed
    fetchB     pull the second install.log                      the comparison
#>
param(
    [string]$Vm    = 'cfv-183',
    [string]$Rg    = 'clawfactory-validation',
    [string]$Sa    = 'clawfactoryvalc467',
    [Parameter(Mandatory)]
    [ValidateSet('prep','A','install','fetchA','A2','reboot','B','B2','cleanA','install2','fetchB','teardown')]
    [string]$Step,
    [string]$OutDir = 'C:\Users\bmcki\ClawFactory-Secure-Setup\validation\diag'
)

$ErrorActionPreference = 'Continue'
$SHIPPED_SHA = '6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1'
$scratch = Join-Path $env:TEMP 'cfv145'
if (-not (Test-Path $scratch)) { New-Item -ItemType Directory -Path $scratch -Force | Out-Null }
if (-not (Test-Path $OutDir))  { New-Item -ItemType Directory -Path $OutDir  -Force | Out-Null }

function Get-SaKey {
    $k = az storage account keys list -g $Rg -n $Sa --query "[0].value" -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $k) { throw "could not read storage key (exit $LASTEXITCODE)" }
    return $k
}

function Invoke-Box {
    <# ONE dispatch. Writes the payload to a file and passes it as @file, because
       az on Windows is az.cmd and cmd.exe re-parses inline --scripts arguments.
       Reads BOTH streams and checks the exit code, because an unchecked az call
       once hung an extension for an hour. #>
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
    $o | ConvertTo-Json -Depth 8 | Out-File (Join-Path $OutDir "v145-$Name.json") -Encoding utf8
    return $o
}

switch ($Step) {

'prep' {
    $key = Get-SaKey
    # The artefact is identified by DIGEST, not by filename. combined-cfv-179
    # through -182 are all 440,610,608 bytes and only one thing distinguishes
    # them from each other with certainty.
    $exe = 'C:\Users\bmcki\ClawFactory-Secure-Setup\Output\ClawFactory-Secure-Setup.exe'
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash.ToLower()
    if ($h -ne $SHIPPED_SHA) { throw "REFUSING: $exe hashes to $h, not the shipped v1.4.4 $SHIPPED_SHA. Reproducing against the wrong bytes would answer every question wrongly and fluently." }
    Write-Host "artefact verified: $h" -ForegroundColor Green
    az storage blob upload --account-name $Sa --account-key $key -c validation -n 'v144-shipped.exe' -f $exe --overwrite --only-show-errors | Out-Null
    Write-Host "upload exe exit=$LASTEXITCODE"
    foreach ($n in @('interim-v120-phaselib.ps1','interim-v145-pendingreboot.ps1')) {
        az storage blob upload --account-name $Sa --account-key $key -c validation -n $n `
            -f "C:\Users\bmcki\ClawFactory-Secure-Setup\validation\$n" --overwrite --only-show-errors | Out-Null
        Write-Host "upload $n exit=$LASTEXITCODE"
    }
    $sas = az storage container generate-sas --account-name $Sa --account-key $key -n validation `
        --permissions rwl --expiry (Get-Date).AddHours(12).ToString('yyyy-MM-ddTHH:mmZ') -o tsv
    Write-Host "SAS minted, length=$($sas.Length). Pass it to the next steps via -Env CFV_SAS."
    [Environment]::SetEnvironmentVariable('CFV_SAS', $sas, 'Process')
    $sas | Out-File (Join-Path $scratch 'sas.txt') -Encoding ascii -NoNewline
    Invoke-Box -Name 'prep' -Body @"
`$ErrorActionPreference='Continue'
New-Item -ItemType Directory -Path C:\cfv -Force | Out-Null
`$sas = '$sas'
foreach (`$n in @('interim-v120-phaselib.ps1','interim-v145-pendingreboot.ps1','v144-shipped.exe')) {
    `$u = "https://$Sa.blob.core.windows.net/validation/`$n`?`$sas"
    Invoke-WebRequest -Uri `$u -OutFile "C:\cfv\`$n" -UseBasicParsing
    Write-Output "downloaded `$n -> `$((Get-Item "C:\cfv\`$n").Length) bytes"
}
# GATE. The reproduction is worthless against the wrong bytes.
`$h = (Get-FileHash -Algorithm SHA256 -LiteralPath 'C:\cfv\v144-shipped.exe').Hash.ToLower()
Write-Output "ON-BOX artefact sha256 = `$h"
Write-Output "EXPECTED shipped v1.4.4 = $SHIPPED_SHA"
Write-Output "ARTEFACT_MATCH = `$(`$h -eq '$SHIPPED_SHA')"
"@
}

'A'  { Invoke-Box -Name 'A'  -Body 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\cfv\interim-v145-pendingreboot.ps1 -Stage A  2>&1 | Out-String | Write-Output' }
'A2' { Invoke-Box -Name 'A2' -Body 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\cfv\interim-v145-pendingreboot.ps1 -Stage A2 2>&1 | Out-String | Write-Output' }
'B'  { Invoke-Box -Name 'B'  -Body 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\cfv\interim-v145-pendingreboot.ps1 -Stage B  2>&1 | Out-String | Write-Output' }
'B2' { Invoke-Box -Name 'B2' -Body 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\cfv\interim-v145-pendingreboot.ps1 -Stage B2 2>&1 | Out-String | Write-Output' }

'install' {
    # /VERYSILENT reaches setup.ps1 as -Silent via GetSilentFlag in the .iss, so
    # Confirm-Or-Default auto-answers and the rollback prompt defaults to 'n'.
    # provider=openai to match the external run.
    Invoke-Box -Name 'install' -Body @'
$ErrorActionPreference='Continue'
Write-Output "=== VMP state immediately before the install ==="
& dism.exe /online /get-featureinfo /featurename:VirtualMachinePlatform | Select-String '^State'
Write-Output "=== launching the shipped v1.4.4 installer ==="
$p = Start-Process -FilePath 'C:\cfv\v144-shipped.exe' -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/PROVIDER=openai' -PassThru -Wait
Write-Output "installer exit code = $($p.ExitCode)"
Write-Output "=== install.log tail ==="
if (Test-Path 'C:\ProgramData\ClawFactory\install.log') {
    Get-Content 'C:\ProgramData\ClawFactory\install.log' -Tail 80
} else { Write-Output 'NO install.log -- the installer never reached setup.ps1' }
'@
}

'install2' {
    Invoke-Box -Name 'install2' -Body @'
$ErrorActionPreference='Continue'
Write-Output "=== VMP state immediately before the second install ==="
& dism.exe /online /get-featureinfo /featurename:VirtualMachinePlatform | Select-String '^State'
Write-Output "=== install.log must be absent or empty before this run ==="
if (Test-Path 'C:\ProgramData\ClawFactory\install.log') { Write-Output "PRESENT -- $(((Get-Content 'C:\ProgramData\ClawFactory\install.log') | Measure-Object -Line).Lines) lines. The cleanA step did not run." }
else { Write-Output 'ABSENT -- clean' }
$p = Start-Process -FilePath 'C:\cfv\v144-shipped.exe' -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/PROVIDER=openai' -PassThru -Wait
Write-Output "installer exit code = $($p.ExitCode)"
Write-Output "=== did it get PAST Step-EnsureWsl? ==="
if (Test-Path 'C:\ProgramData\ClawFactory\install.log') {
    $l = Get-Content 'C:\ProgramData\ClawFactory\install.log'
    Write-Output "clawuser-stub failure present: $([bool]($l -match 'Failed to pre-create clawuser stub'))"
    Write-Output "reached Step 3 (.wslconfig): $([bool]($l -match 'Step 3'))"
    $l | Select-Object -Last 120
} else { Write-Output 'NO install.log' }
'@
}

'fetchA' {
    # Pull the log, THEN move it aside. It appends; stage B must not read it.
    $sas = Get-Content (Join-Path $scratch 'sas.txt') -Raw
    Invoke-Box -Name 'fetchA' -Body @"
`$ErrorActionPreference='Continue'
`$sas='$sas'
Write-Output '=== FULL install.log, verbatim ==='
Get-Content 'C:\ProgramData\ClawFactory\install.log' -ErrorAction SilentlyContinue
foreach (`$pair in @(@('C:\ProgramData\ClawFactory\install.log','v145-installlog-A.txt'),
                     @('C:\cfv\pendingreboot-A-out-probe.txt','v145-pendingreboot-A-out.txt'),
                     @('C:\cfv\pendingreboot-A-results.json','v145-pendingreboot-A-results.json'))) {
    if (Test-Path `$pair[0]) {
        `$u = "https://$Sa.blob.core.windows.net/validation/`$(`$pair[1])`?`$sas"
        Invoke-WebRequest -Uri `$u -Method Put -InFile `$pair[0] -Headers @{ 'x-ms-blob-type'='BlockBlob' } -UseBasicParsing | Out-Null
        Write-Output "uploaded `$(`$pair[1])"
    }
}
if (Test-Path 'C:\ProgramData\ClawFactory\install.log') {
    Move-Item 'C:\ProgramData\ClawFactory\install.log' 'C:\cfv\install-log-stageA.txt' -Force
    Write-Output 'install.log MOVED ASIDE -- stage B starts from a clean file'
}
"@
}

'fetchB' {
    $sas = Get-Content (Join-Path $scratch 'sas.txt') -Raw
    Invoke-Box -Name 'fetchB' -Body @"
`$ErrorActionPreference='Continue'
`$sas='$sas'
Write-Output '=== FULL post-reboot install.log, verbatim ==='
Get-Content 'C:\ProgramData\ClawFactory\install.log' -ErrorAction SilentlyContinue
foreach (`$pair in @(@('C:\ProgramData\ClawFactory\install.log','v145-installlog-B.txt'),
                     @('C:\cfv\pendingreboot-B-out-probe.txt','v145-pendingreboot-B-out.txt'),
                     @('C:\cfv\pendingreboot-A2-out-probe.txt','v145-pendingreboot-A2-out.txt'),
                     @('C:\cfv\pendingreboot-B2-out-probe.txt','v145-pendingreboot-B2-out.txt'))) {
    if (Test-Path `$pair[0]) {
        `$u = "https://$Sa.blob.core.windows.net/validation/`$(`$pair[1])`?`$sas"
        Invoke-WebRequest -Uri `$u -Method Put -InFile `$pair[0] -Headers @{ 'x-ms-blob-type'='BlockBlob' } -UseBasicParsing | Out-Null
        Write-Output "uploaded `$(`$pair[1])"
    }
}
"@
}

'cleanA' {
    Invoke-Box -Name 'cleanA' -Body @'
$ErrorActionPreference='Continue'
Write-Output "distros before clean:"; & wsl.exe --list --quiet
foreach ($d in @('Ubuntu')) { & wsl.exe --unregister $d 2>&1 | Out-String | Write-Output }
Write-Output "distros after clean:"; & wsl.exe --list --quiet
Remove-Item 'C:\ProgramData\ClawFactory\install.log'    -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\ProgramData\ClawFactory\checkpoint.json' -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\ProgramData\ClawFactory\resume-after-restart.flag' -Force -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'ClawFactory-Resume' -Confirm:$false -ErrorAction SilentlyContinue
Write-Output "ProgramData now: $((Get-ChildItem 'C:\ProgramData\ClawFactory' -ErrorAction SilentlyContinue).Name -join ', ')"
'@
}

'reboot' {
    az vm restart -g $Rg -n $Vm -o none
    Write-Host "az vm restart exit=$LASTEXITCODE"
}

'teardown' {
    # NIC FIRST -- it references the pip and the nsg.
    az vm delete -g $Rg -n $Vm --yes -o none;                       Write-Host "vm delete exit=$LASTEXITCODE"
    az network nic delete -g $Rg -n "${Vm}VMNic" -o none;            Write-Host "nic delete exit=$LASTEXITCODE"
    az network public-ip delete -g $Rg -n "${Vm}PublicIP" -o none;   Write-Host "pip delete exit=$LASTEXITCODE"
    az network nsg delete -g $Rg -n "${Vm}NSG" -o none;              Write-Host "nsg delete exit=$LASTEXITCODE"
    $disks = az disk list -g $Rg --query "[?starts_with(name,'$Vm')].name" -o tsv
    foreach ($d in ($disks -split "`n" | Where-Object { $_ })) { az disk delete -g $Rg -n $d.Trim() --yes -o none; Write-Host "disk $d delete exit=$LASTEXITCODE" }
    Write-Host '--- UNFILTERED residual, which is the claim that matters ---'
    az resource list -g $Rg --query "[].[name,type]" -o tsv
}

}
