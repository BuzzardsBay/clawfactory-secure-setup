<#
  Submit a phase script to the on-VM runner and bring its evidence back.

  This is the driver half of the runner contract described in
  interim-v120-runner.ps1. It exists so Phases 2, 3 and 4 can be driven one at a
  time against a LIVE VM, with a human checkpoint between them, instead of the
  fire-and-forget single-sentinel shape JOB 3 used.

  Sequence, and why each step is here:
    1. upload the phase script to blob, verifying the byte count AT THE SERVICE.
       The first run of this harness printed "uploaded" four times for uploads
       that never happened, because an az failure does not stop the script (L6)
       and the container did not exist. Never trust the absence of an error.
    2. have the VM fetch it, and confirm the fetch by size.
    3. drop a tiny .job.ps1 that invokes it. The runner picks it up, captures
       output, and writes .done LAST as the read barrier.
    4. poll for .done, distinguishing "runner alive, job slow" from "runner
       dead" via the heartbeat, because those need different responses.
    5. retrieve the runner's captured output AND the phase script's own
       transcript. Two independent channels, then gate on the producer sentinel.

  A phase whose sentinel never appears is reported as EVIDENCE_MISSING rather
  than as a pass or a product failure. A missing measurement is not a result.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PhaseScript,
    [Parameter(Mandatory)][string]$JobName,
    [Parameter(Mandatory)][string]$Sentinel,
    [string]$ScriptArgs    = '',
    [string]$VmName        = 'cfv-153',
    [string]$ResourceGroup = 'clawfactory-validation',
    [string]$StorageAcct   = 'clawfactoryvalc467',
    [string]$Container     = 'validation',
    [string[]]$ExtraFiles  = @(),
    [int]$TimeoutMinutes   = 45,
    [string]$OutDir        = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'validation-runs' }
$dir = Join-Path $OutDir "$VmName-$JobName-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $dir -Force | Out-Null

function Say($m, $c = 'Cyan') { Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $m" -ForegroundColor $c }

function Invoke-Rc {
    param([string]$Script, [string]$Label = 'run-command')
    $f = Join-Path ([IO.Path]::GetTempPath()) ("cfv-rc-{0}.ps1" -f [Guid]::NewGuid())
    try {
        [IO.File]::WriteAllText($f, $Script, (New-Object Text.UTF8Encoding($false)))
        $out = az vm run-command invoke -g $ResourceGroup -n $VmName `
                 --command-id RunPowerShellScript --scripts "@$f" `
                 --query "value[].message" -o tsv
        if ($LASTEXITCODE -ne 0) { throw "$Label : az run-command exited $LASTEXITCODE" }
        return ($out -join "`n")
    } finally { Remove-Item $f -Force -ErrorAction SilentlyContinue }
}

$key = az storage account keys list -g $ResourceGroup -n $StorageAcct --query "[0].value" -o tsv
if ($LASTEXITCODE -ne 0 -or -not $key) { throw "Could not read a storage key for $StorageAcct." }
$exp = (Get-Date).ToUniversalTime().AddHours(4).ToString('yyyy-MM-ddTHH:mmZ')

function Push-File([string]$LocalPath) {
    $name = Split-Path $LocalPath -Leaf
    if (-not (Test-Path $LocalPath)) { throw "Cannot stage '$LocalPath' -- not found." }
    az storage blob upload --account-name $StorageAcct --account-key $key --container-name $Container `
        --name $name --file $LocalPath --overwrite --output none
    if ($LASTEXITCODE -ne 0) { throw "Upload of $name failed (az exit $LASTEXITCODE)." }
    $remote = az storage blob show --account-name $StorageAcct --account-key $key --container-name $Container `
                --name $name --query "properties.contentLength" -o tsv
    $localLen = (Get-Item $LocalPath).Length
    if ("$remote" -ne "$localLen") { throw "Upload of $name landed $remote bytes, expected $localLen." }
    $sas = az storage blob generate-sas --account-name $StorageAcct --account-key $key `
             --container-name $Container --name $name --permissions r --expiry $exp -o tsv
    Say "  staged $name ($localLen bytes, confirmed at the service)" DarkGray
    return @{ Name = $name; Url = "https://$StorageAcct.blob.core.windows.net/$Container/$name`?$sas"; Len = $localLen }
}

function Retrieve-VmFile {
    param([string]$VmPath, [string]$BlobName, [string]$LocalPath)
    $sas = az storage blob generate-sas --account-name $StorageAcct --account-key $key `
             --container-name $Container --name $BlobName --permissions cw --expiry $exp -o tsv
    $url = "https://$StorageAcct.blob.core.windows.net/$Container/$BlobName`?$sas"
    $put = Invoke-Rc ("if (-not (Test-Path '$VmPath')) { 'MISSING_ON_VM' } else { Invoke-WebRequest -Uri '$url' -Method Put -Headers @{'x-ms-blob-type'='BlockBlob'} -InFile '$VmPath' -UseBasicParsing | Out-Null; `"UPLOADED=`$((Get-Item '$VmPath').Length)`" }") "pull $BlobName"
    if ($put -notmatch 'UPLOADED=\d+') { Say "  $VmPath not retrieved: $put" Yellow; return $null }
    az storage blob download --account-name $StorageAcct --account-key $key --container-name $Container `
        --name $BlobName --file $LocalPath --overwrite --output none
    return $LocalPath
}

# ---- 1/2. stage the phase script (and any extras) and fetch them on the VM ----
Say "Staging $JobName..."
$all = @($PhaseScript) + $ExtraFiles
$staged = @($all | ForEach-Object { Push-File $_ })
$fetch = "`$ErrorActionPreference='Stop'; New-Item -ItemType Directory -Path C:\cfv\jobs -Force | Out-Null; "
foreach ($s in $staged) {
    $fetch += "Invoke-WebRequest -Uri '$($s.Url)' -OutFile 'C:\cfv\$($s.Name)' -UseBasicParsing; "
    $fetch += "if ((Get-Item 'C:\cfv\$($s.Name)').Length -ne $($s.Len)) { throw 'SIZE MISMATCH $($s.Name)' }; "
}
$fetch += "'FETCH_OK'"
$r = Invoke-Rc $fetch 'fetch'
if ($r -notmatch 'FETCH_OK') { throw "VM did not confirm the fetch: $r" }
Say "  VM fetched and size-checked $($staged.Count) file(s)" Green

# ---- 3. drop the job file ----------------------------------------------------
$leaf = Split-Path $PhaseScript -Leaf
$jobBody = "& 'C:\cfv\$leaf' $ScriptArgs"
$jobB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($jobBody))
$drop = "`$ErrorActionPreference='Stop'; " +
        "Remove-Item 'C:\cfv\jobs\$JobName.done','C:\cfv\jobs\$JobName.out' -Force -EA SilentlyContinue; " +
        "[IO.File]::WriteAllBytes('C:\cfv\jobs\$JobName.job.ps1', [Convert]::FromBase64String('$jobB64')); " +
        "'DROPPED'"
$r = Invoke-Rc $drop 'drop'
if ($r -notmatch 'DROPPED') { throw "Could not drop the job file: $r" }
Say "Job '$JobName' queued to the on-VM runner." Green

# ---- 4. poll -----------------------------------------------------------------
$iters = [int]($TimeoutMinutes * 60 / 30)
$done = $false
foreach ($i in 1..$iters) {
    Start-Sleep -Seconds 30
    $p = Invoke-Rc ("if (Test-Path 'C:\cfv\jobs\$JobName.done') { 'JOB_DONE ' + (Get-Content 'C:\cfv\jobs\$JobName.done' -Raw) } else { " +
                    "`$hb = if (Test-Path 'C:\cfv\jobs\_runner.heartbeat') { Get-Content 'C:\cfv\jobs\_runner.heartbeat' -Raw } else { 'NO_HEARTBEAT' }; " +
                    "`$sz = if (Test-Path 'C:\cfv\jobs\$JobName.out') { (Get-Item 'C:\cfv\jobs\$JobName.out').Length } else { 0 }; " +
                    "`"PENDING heartbeat=`$hb outBytes=`$sz`" }") 'poll'
    if ($p -match 'JOB_DONE') { $done = $true; Say "Job '$JobName' finished: $p" Green; break }
    if ($p -match 'NO_HEARTBEAT') { Say "  WARNING: runner heartbeat absent. The runner may be dead, which is different from a slow job." Yellow }
    if ($i % 4 -eq 0) { Say "  ...($i/$iters, ~$([int]($i*0.5))min) $p" DarkGray }
}
if (-not $done) { Say "Job '$JobName' did not complete within $TimeoutMinutes min. Retrieving whatever exists." Yellow }

# ---- 5. retrieve both channels + gate ---------------------------------------
$outFile   = Retrieve-VmFile "C:\cfv\jobs\$JobName.out" "$JobName-out-$VmName.txt"        (Join-Path $dir "$JobName.out.txt")
$probeName = ($leaf -replace '\.ps1$', '') -replace '^interim-v120-', ''
$transcript = Retrieve-VmFile "C:\cfv\$probeName-out-probe.txt" "$JobName-probe-$VmName.txt" (Join-Path $dir "$JobName-probe.txt")
$resJson    = Retrieve-VmFile "C:\cfv\$probeName-results.json"  "$JobName-results-$VmName.json" (Join-Path $dir "$JobName-results.json")

$haveEvidence = $false
foreach ($f in @($outFile, $transcript)) {
    if ($f -and (Test-Path $f) -and (Get-Item $f).Length -ge 512 -and (Get-Content $f -Raw) -match $Sentinel) { $haveEvidence = $true }
}
if (-not $haveEvidence) {
    Write-Host "`n===== EVIDENCE_MISSING for $JobName =====" -ForegroundColor Red
    Say "No channel carries '$Sentinel' above 512 B. This is a missing measurement, not a verdict." Red
    Say "  VM left running for salvage. Evidence dir: $dir" Red
    exit 3
}
Say "Evidence gate PASSED for $JobName." Green
Write-Host "`n===== $JobName EVIDENCE =====" -ForegroundColor Cyan
if ($transcript) { Get-Content $transcript } elseif ($outFile) { Get-Content $outFile }
Say "Evidence in $dir" Green
