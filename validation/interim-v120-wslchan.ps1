<#
  The file-based WSL channel, and the paired-control discipline, for the v1.2.0
  interim validation. Dot-sourced by every on-VM job.

  WHY NOT THE USUAL CHANNEL
  -------------------------
  L22 (ClawFactory_Install_Lessons_Learned.md): an inline nested
  `wsl.exe -- bash -c '<script>'` FABRICATES PASSES. It silently dropped whole
  echo lines, returned $? = 0 for a command that had just printed "Connection
  refused", and expanded $ip to empty so `grep -q "$ip"` became `grep -q ""`,
  which matches every line. That produced three confident, entirely invented
  readings about firewall allowlist contents, and very nearly filed a false
  ship-blocking hole against a firewall that was working correctly. MSYS path
  conversion was tested and REFUTED as the cause.

  The JOB 3 probe worked around this with base64-over-`bash -lc`, which is
  safer (single token, no quoting to corrupt) but is still the forbidden shape.
  This job's channel rule is unconditional, so this is a true file channel.

  WHY \\wsl$ AND NOT /mnt/c
  --------------------------
  The obvious file channel is to drop the script on the Windows side and run
  `bash /mnt/c/...`. That does not work here: the installer deliberately writes
  `[automount] enabled=false` into /etc/wsl.conf (setup.ps1:1145) and verifies
  it section-aware (setup.ps1:1123), because the whole P0 file-isolation guard
  depends on the agent having no automatic view of the Windows filesystem.
  /mnt/c is therefore absent by design on a correct install, and a probe that
  needed it would only work on a BROKEN install. That is the wrong dependency
  for a security harness.

  So the payload goes the other way, over the 9p server that exposes the distro
  to Windows: write LF-only bytes to \\wsl$\<distro>\tmp\..., then execute it by
  its Linux path. The 9p path is independent of automount (cfv-151 used it for
  exactly this reason), and no script text ever appears on a command line.

  L21: the payload MUST reach bash as LF. A .ps1 carrying multi-line bash into
  WSL with CRLF intact fails in ways that read as product faults.
#>

$script:CfDistro = 'Ubuntu'

function Invoke-WslFile {
    <#
      Run a bash script inside the distro through the file channel.
      Returns a hashtable: Out (combined stdout+stderr), Rc (exit code).

      No -c, no inline script, no nested quoting. The only things on the command
      line are fixed literal paths.
    #>
    param(
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][string]$Tag,
        [string]$User = 'root'
    )
    $lf   = ($Body -replace "`r`n", "`n") -replace "`r", "`n"
    # /var/tmp, NOT /tmp.
    #
    # The distro runs systemd, which mounts /tmp as tmpfs. Writing the script
    # over the 9p share starts the distro if it is down, and if the distro then
    # restarts between the write and the run, tmpfs is wiped and bash reports
    # "No such file or directory" for a file that was genuinely written. That is
    # a race, so it fails intermittently and looks like a product fault.
    # Observed for real on cfv-154 right after the distro was restarted.
    # /var/tmp is on the ext4 disk and survives a restart.
    $unc  = "\\wsl$\$script:CfDistro\var\tmp\cfprobe-$Tag.sh"
    $lin  = "/var/tmp/cfprobe-$Tag.sh"
    $out  = "C:\cfv\wsl\$Tag.out"
    New-Item -ItemType Directory -Path 'C:\cfv\wsl' -Force | Out-Null

    # Write, run, and if the script was not there, write again and retry ONCE.
    # The retry exists only for the distro-restart race described above; a
    # genuinely broken script fails the same way twice and is reported.
    $rc = 0; $text = ''
    foreach ($attempt in 1..2) {
        # UTF8 without BOM. A BOM at the head of a shell script is a syntax error
        # on line 1, and the failure looks like the script's fault rather than
        # the writer's (same family as the PS 5.1 BOM bug that broke the signtool
        # dlib, and as the stdin BOM found in setup.ps1 this session).
        [IO.File]::WriteAllText($unc, $lf, (New-Object Text.UTF8Encoding($false)))

        # Redirect on the Windows side so the output is a file too, never parsed
        # from a pipe. cmd /c owns the redirect; wsl.exe gets a bare path.
        #
        # stdin is bound to NUL. Without it the probe inherits the caller's
        # stdin, and any command inside the script that reads stdin blocks
        # forever on a handle that never reaches EOF. Not hypothetical: the
        # first Phase 2 run wedged for 25 minutes on a `node -e` reading stdin,
        # and a wedged probe looks exactly like a slow one from outside.
        cmd.exe /c "wsl.exe -d $script:CfDistro -u $User -- /bin/bash $lin < NUL > `"$out`" 2>&1"
        $rc = $LASTEXITCODE
        $text = if (Test-Path $out) { Get-Content $out -Raw } else { '' }
        if ($text -notmatch 'No such file or directory') { break }
        Start-Sleep -Seconds 3
    }
    return @{ Out = $text; Rc = $rc }
}

function Test-WslChannel {
    <#
      Channel self-test. Runs BEFORE any measurement in every job.

      This is the guard L22 rule 2 demands, applied to the channel itself: a
      subject that must succeed and a control that must fail, in one run. If the
      control "passes", the channel is lying and every result behind it is void.
      Returns $true only if the channel discriminates.
    #>
    $r = Invoke-WslFile -Tag 'chanselftest' -User 'root' -Body @'
echo "SUBJECT_MARKER=$(id -u)"
# Control: a command that MUST fail. If this prints CONTROL_RC=0 the channel is
# not reporting real exit codes and nothing measured through it can be trusted.
/bin/false
echo "CONTROL_RC=$?"
# Second control: a variable that must expand. L22 saw positional/variable
# expansion silently empty, which turned grep -q "$x" into grep -q "" (matches
# anything). If this prints EXPAND= with nothing after it, expansion is broken.
x="expanded-ok"
echo "EXPAND=$x"
'@
    $ok = ($r.Out -match 'SUBJECT_MARKER=0') -and
          ($r.Out -match 'CONTROL_RC=1')     -and
          ($r.Out -match 'EXPAND=expanded-ok')
    return @{ Ok = $ok; Detail = $r.Out }
}
