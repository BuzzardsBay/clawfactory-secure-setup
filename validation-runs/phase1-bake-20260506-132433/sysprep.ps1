$exe = "C:\Windows\System32\Sysprep\sysprep.exe"
$args = @("/generalize", "/shutdown", "/oobe", "/quiet")
$p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru
"Sysprep exit code: $($p.ExitCode)"
