$ErrorActionPreference = 'Continue'
Write-Output "=== Inno Setup tmp log hunt ==="
Get-ChildItem -Path "$env:TEMP","$env:LOCALAPPDATA\Temp","C:\Windows\Temp" -Filter 'Setup Log*.txt' -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName,Length,LastWriteTime | Format-List
Write-Output "=== is-*.tmp dirs ==="
Get-ChildItem -Path "$env:TEMP","C:\Windows\Temp" -Filter 'is-*.tmp' -Directory -ErrorAction SilentlyContinue |
    Select-Object FullName,LastWriteTime | Format-List
Write-Output "=== ClawFactory artifacts ==="
foreach ($p in @('C:\Program Files\ClawFactory','C:\ProgramData\ClawFactory','C:\install-stdout.log')) {
    if (Test-Path $p) { Write-Output "EXISTS: $p" } else { Write-Output "MISSING: $p" }
}
Write-Output "=== Application event log: ClawFactory / Inno Setup last 1h ==="
$since = (Get-Date).AddHours(-1)
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$since} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match 'Setup|Claw|Inno|MSI' -or $_.Message -match 'ClawFactory|Setup' } |
    Select-Object -First 15 TimeCreated,Id,LevelDisplayName,ProviderName,Message | Format-List
Write-Output "=== Recent App-error / unhandled exception last 1h ==="
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$since; ProviderName='Application Error','.NET Runtime','Windows Error Reporting'} -ErrorAction SilentlyContinue |
    Select-Object -First 10 TimeCreated,Id,LevelDisplayName,ProviderName,Message | Format-List
Write-Output "=== END ==="
