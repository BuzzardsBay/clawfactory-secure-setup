$ErrorActionPreference = 'Continue'
$paths = @(
    'C:\Program Files\ClawFactory\resources\smoke-test.ps1',
    'C:\Program Files\ClawFactory\smoke-test.ps1',
    'C:\ProgramData\ClawFactory\smoke-test.ps1'
)
$found = $null
foreach ($p in $paths) {
    if (Test-Path $p) { $found = $p; break }
}
if ($found) {
    Write-Output "FOUND: $found"
    Write-Output "=== smoke-test stdout/stderr begin ==="
    & powershell.exe -ExecutionPolicy Bypass -File "$found" 2>&1
    Write-Output "=== smoke-test end ==="
} else {
    Write-Output "smoke-test.ps1 not found"
    foreach ($p in $paths) { Write-Output "  checked: $p" }
}
