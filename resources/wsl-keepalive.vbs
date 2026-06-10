' wsl-keepalive.vbs (v1.0.33)
' Hidden launcher for the ClawFactory WSL Host scheduled task.
'
' Why this file exists: the task action originally invoked wsl.exe directly,
' which under an interactive LogonTrigger on Win11 opens a Windows Terminal
' window (or a console flash) at every logon. Wrapping the call in wscript
' with intWindowStyle=0 (vbHide) guarantees no visible window across Win10
' and Win11, default-terminal=conhost OR Windows Terminal. The wsl.exe
' process detaches and outlives wscript -- the WSL session persists.
'
' Args: 0 = distro name, 1 = WSL user (e.g. "Ubuntu" "clawuser")

Set sh = CreateObject("WScript.Shell")
cmd = "wsl.exe -d " & WScript.Arguments(0) & " -u " & WScript.Arguments(1) & " -- sleep infinity"
sh.Run cmd, 0, False
