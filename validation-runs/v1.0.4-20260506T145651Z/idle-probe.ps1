$ErrorActionPreference = 'Continue'
function Probe([string]$label) {
    try {
        $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8787/health' -UseBasicParsing -TimeoutSec 5
        "$label`: $($r.StatusCode)"
    } catch {
        "$label`: FAIL - $_"
    }
}
Write-Output (Probe 'PROBE1')
Start-Sleep -Seconds 300
Write-Output (Probe 'PROBE2')
