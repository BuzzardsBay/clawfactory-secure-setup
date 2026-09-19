<#
  cfv-arm-autologon.ps1 -- PERSISTENT auto-logon for the validation runner's WSL queue.

  RUNS ON THE VM, dispatched through az vm run-command, so it executes as
  NT AUTHORITY\SYSTEM. Receives the admin password as the run-command PARAMETER
  -Pw. The value is handed over by validation/cfv-provision.ps1, which generated it
  and used it for `az vm create --admin-password` in the SAME process, so there is
  exactly one generation path and one password (card #259 §6.1; docs/VALIDATION_PREAMBLE.md
  THE ADMIN PASSWORD IS THE SESSION'S). This file NEVER prints, logs or returns it.

  WHAT IT WRITES  (HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon)
    AutoAdminLogon    1
    DefaultUserName   <AdminUser>
    DefaultDomainName <this computer>
    DefaultPassword   <the password>           <- cleartext in the registry, see below
    AutoLogonCount    ABSENT  -- deliberately. Present, Windows decrements it on every
                      logon and disarms auto-logon at zero, which is the one-shot
                      behaviour that cost cfv-191 54 minutes. Absent, it persists.

  THE EXPOSURE, STATED PLAINLY
  ----------------------------
  The password sits in the registry in plaintext-recoverable form for as long as the VM
  exists -- readable by any local administrator or SYSTEM process, and present in any
  snapshot or image captured from the VM. That is the trade for a session that exists
  at every boot. It is accepted ONLY because the box is a validation VM in
  clawfactory-validation created --nsg-rule NONE (no inbound path), holds nothing, and
  is deleted with its disk within hours. NEVER capture an image from a validation VM.
  It is not a licence to arm auto-logon anywhere else, and nothing in this file is
  bundled into the product (validation/ is in no [Files] entry of the .iss).

  THE run-command PARAMETER IS ITSELF A SECOND ON-VM COPY. The guest extension keeps
  the settings it was dispatched with under C:\Packages. This script counts the
  files there that contain the value and reports the COUNT, so the second copy is
  measured rather than assumed absent. Same exposure class as the registry value.

  VERIFICATION IS END TO END, not a registry read-back: the value written is checked
  against the ACCOUNT with ValidateCredentials, so "the password in the registry is the
  one the account actually has" is measured. The positive result is only believable
  beside its control (a wrong value must be rejected), which runs in the same pass.
#>
param(
    [Parameter(Mandatory)][string]$AdminUser,
    [Parameter(Mandatory)][string]$Pw
)

$ErrorActionPreference = 'Continue'
function Out-Kv([string]$k, $v) { Write-Output ("{0}={1}" -f $k, $v) }

Out-Kv 'AL_WHOAMI' ((& whoami.exe) -join '')
Out-Kv 'AL_PW_LEN' $Pw.Length

$wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

# Confirm the account exists and the value we were handed is its password BEFORE
# writing it anywhere. A wrong value written to Winlogon does not fail loudly: the
# box just boots to a logon screen and the WSL queue reports RunnerAbsent.
Add-Type -AssemblyName System.DirectoryServices.AccountManagement
$ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Machine)
$valid   = $false
$control = $true
try { $valid   = $ctx.ValidateCredentials($AdminUser, $Pw) } catch { Out-Kv 'AL_VALIDATE_ERROR' ($_.Exception.GetType().Name) }
try { $control = $ctx.ValidateCredentials($AdminUser, ($Pw + 'x-not-the-password')) } catch { $control = $false }
Out-Kv 'AL_CRED_VALID_FOR_ACCOUNT' $valid
Out-Kv 'AL_CTL_WRONG_VALUE_REJECTED' (-not $control)

if (-not ($valid -and -not $control)) {
    Out-Kv 'AL_RESULT' 'FAIL'
    Out-Kv 'AL_REASON' 'the supplied value is not the account password, or the validator cannot tell right from wrong; nothing was written to Winlogon'
    exit 3
}

Set-ItemProperty -Path $wl -Name 'AutoAdminLogon'    -Value '1'                 -Type String
Set-ItemProperty -Path $wl -Name 'DefaultUserName'   -Value $AdminUser          -Type String
Set-ItemProperty -Path $wl -Name 'DefaultDomainName' -Value $env:COMPUTERNAME   -Type String
Set-ItemProperty -Path $wl -Name 'DefaultPassword'   -Value $Pw                 -Type String
Remove-ItemProperty -Path $wl -Name 'AutoLogonCount' -ErrorAction SilentlyContinue

# READ-BACK, by name, values never echoed.
$p = Get-ItemProperty $wl
Out-Kv 'AL_AUTOADMINLOGON'   "$($p.AutoAdminLogon)"
Out-Kv 'AL_DEFAULTUSERNAME'  "$($p.DefaultUserName)"
Out-Kv 'AL_DEFAULTDOMAIN'    "$($p.DefaultDomainName)"
Out-Kv 'AL_DEFAULTPASSWORD_LEN' "$("$($p.DefaultPassword)".Length)"
Out-Kv 'AL_DEFAULTPASSWORD_EQUALS_INPUT' ("$($p.DefaultPassword)" -ceq $Pw)
Out-Kv 'AL_AUTOLOGONCOUNT_ABSENT' ($null -eq $p.PSObject.Properties['AutoLogonCount'])

# Control for the read-back: a name that was never written must read as absent, so
# the two "absent"/"equals" lines above are not echoing a constant.
Out-Kv 'AL_CTL_NEVER_WRITTEN_IS_ABSENT' ($null -eq $p.PSObject.Properties['CfvNeverWrittenValue'])

# The second on-VM copy (see header). COUNT ONLY -- the matching paths are not
# printed because a path is not the point and a path list is noise in a transcript.
$copies = 0; $scanned = 0
try {
    foreach ($f in (Get-ChildItem 'C:\Packages\Plugins' -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        if ($f.Length -gt 5MB) { continue }
        $scanned++
        try { if ([IO.File]::ReadAllText($f.FullName).Contains($Pw)) { $copies++ } } catch { }
    }
} catch { }
Out-Kv 'AL_EXT_SETTINGS_FILES_SCANNED' $scanned
Out-Kv 'AL_EXT_SETTINGS_COPIES_OF_PASSWORD' $copies

$ok = ($p.AutoAdminLogon -eq '1') -and ($p.DefaultUserName -eq $AdminUser) -and ("$($p.DefaultPassword)" -ceq $Pw) -and
      ($null -eq $p.PSObject.Properties['AutoLogonCount'])
Out-Kv 'AL_RESULT' $(if ($ok) { 'PASS' } else { 'FAIL' })
Remove-Variable Pw -ErrorAction SilentlyContinue
if ($ok) { exit 0 } else { exit 3 }
