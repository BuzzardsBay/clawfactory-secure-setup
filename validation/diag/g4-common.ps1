<#
  Shared bootstrap for every Guard 4 probe phase.

  Dot-sources the WSL file channel and the phase runner, then provides the two
  things every phase needs before it can measure anything: the syscall payload
  on the box, and proof that the interpreter running it works.

  WHY THE INTERPRETER GETS ITS OWN CONTROL
  ----------------------------------------
  Every question here is answered by a python3 process reporting what a syscall
  returned. If python3 is absent, or present but cannot reach libc, the phase
  gets no output and the natural reading of no output is "the kernel refused".
  Those are opposite answers with the same shape, and the expensive one to get
  wrong is the kernel's. So Install-G4Py registers a positive control that
  asserts the interpreter is working WITHOUT asserting anything about fanotify
  permission mode, which is the thing under test.
#>

. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1
. C:\cfv\g4-py.ps1

function Install-G4Py {
    <#
      Writes the payload to /var/tmp/g4-probe.py and self-tests the interpreter.
      Returns a hashtable with Ok, Python, Detail.

      /var/tmp deliberately, not /tmp: the distro runs systemd and mounts /tmp as
      tmpfs, so a payload written there does not survive the restart cycle that
      question 2 exists to test.
    #>
    $body = @"
mkdir -p /var/tmp/g4
cat > /var/tmp/g4-probe.py <<'G4PYEOF'
$G4Py
G4PYEOF
chmod 0755 /var/tmp/g4-probe.py
echo "PY_BYTES=`$(wc -c < /var/tmp/g4-probe.py | tr -d ' ')"
echo "PY3_PATH=`$(command -v python3 || echo ABSENT)"
if command -v python3 >/dev/null 2>&1; then
  echo "PY3_VERSION=`$(python3 --version 2>&1)"
  echo "--- interpreter self-test (says nothing about fanotify permission mode) ---"
  python3 /var/tmp/g4-probe.py selftest 2>&1
  echo "SELFTEST_RC=`$?"
else
  echo "SELFTEST_RC=127"
fi
echo "--- CONTROL: a subcommand that must be rejected ---"
if command -v python3 >/dev/null 2>&1; then
  python3 /var/tmp/g4-probe.py definitely-not-a-subcommand 2>&1 | head -2
  echo "CONTROL_RC=`${PIPESTATUS[0]}"
fi
"@
    $r = Invoke-WslFile -Tag 'g4-py-install' -User 'root' -Body $body
    W $r.Out
    $pyPresent = ($r.Out -match 'PY3_PATH=(/\S+)')
    $selfOk = ($r.Out -match '"libc_reachable": true') -and ($r.Out -match 'SELFTEST_RC=0')
    # The control must be REJECTED. If an unknown subcommand exits 0, the
    # interpreter is not running this file at all and every later result is
    # reading someone else's output.
    $ctlOk = ($r.Out -match 'CONTROL_RC=2')
    return @{
        Ok      = ($pyPresent -and $selfOk -and $ctlOk)
        Python  = $(if ($r.Out -match 'PY3_VERSION=(.+)') { $Matches[1].Trim() } else { 'ABSENT' })
        Present = $pyPresent
        Detail  = "python3=$(if($pyPresent){$Matches[1]}else{'ABSENT'}) selftest_ok=$selfOk unknown_subcommand_rejected=$ctlOk"
        Raw     = $r.Out
    }
}

function Get-G4Json {
    <#
      Pulls the G4JSON lines out of a transcript and returns them as objects.
      The payload prefixes its machine-readable output for exactly this reason:
      a phase that regex-scrapes free text finds whatever it hoped to find.
    #>
    param([Parameter(Mandatory)][string]$Text)
    $objs = @()
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^G4JSON\s+(\{.*\})\s*$') {
            try { $objs += ($Matches[1] | ConvertFrom-Json) } catch { }
        }
    }
    return $objs
}
