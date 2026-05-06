Start-Process -FilePath "C:\Windows\System32\Sysprep\sysprep.exe" -ArgumentList @("/generalize", "/shutdown", "/oobe", "/quiet", "/mode:vm") -Wait
"SYSPREP_LAUNCHED"
