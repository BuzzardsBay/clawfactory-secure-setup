Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
wsl --install --no-distribution --web-download
Add-MpPreference -ExclusionPath "C:\Program Files\ClawFactory"
Add-MpPreference -ExclusionPath "C:\ProgramData\ClawFactory"
Add-MpPreference -ExclusionPath "C:\Users\Public\Desktop\ClawFactory.lnk"
winget install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements
winget install Microsoft.VCRedist.2015+.x64 --silent --accept-package-agreements --accept-source-agreements
$wsl = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State
$vmp = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State
"RESULT: WSL=$wsl VMP=$vmp"
