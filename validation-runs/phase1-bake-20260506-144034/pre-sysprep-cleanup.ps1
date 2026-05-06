Remove-Item -Path "C:\Windows\Panther" -Recurse -Force -ErrorAction SilentlyContinue
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Set-Service -Name wuauserv -StartupType Disabled -ErrorAction SilentlyContinue
Get-AppxPackage -AllUsers | Where-Object {
    $_.NonRemovable -eq $false
} | ForEach-Object {
    Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
}
"PRE_SYSPREP_CLEANUP_DONE"
