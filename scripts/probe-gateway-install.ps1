<#
.SYNOPSIS
  PROBE: why does `openclaw gateway install --force --port 8787` fail, so that
  /home/clawuser/.config/systemd/user/openclaw-gateway.service is never created?

.DESCRIPTION
  Runs AS clawadmin, in the SAME session and boot as the failed install.
  See GATEWAY_8C_AZURE_DIAGNOSIS_2026-07-15.md: the unit is absent, and the rc of
  the command that creates it is swallowed by a WARN at setup.ps1:1921-1923.

  PREDICTION UNDER TEST (openclaw/openclaw#33512, #33633, closed by PR #33634):
    on a FRESH install the CLI preflights `systemctl --user is-enabled
    openclaw-gateway.service`, which returns exit 4 (not-found) because the unit
    does not exist yet; openclaw misreads 4 as "systemctl unavailable" and ABORTS
    BEFORE WRITING THE UNIT -- a chicken-and-egg that can only ever bite a clean
    machine. Expected error:
      "Gateway service check failed: Error: systemctl is-enabled unavailable:
       Command failed: systemctl --user is-enabled openclaw-gateway.service"
  If that is what we see, the egress-firewall suspect is DEAD and Task 3 is
  skipped. The prediction is a hypothesis; the VM decides.

  TRANSPORT: bundle passed as base64 (automount=false -> /mnt/c does not exist).
  Output is pulled via blob by the harness (run-command's message truncates at
  ~4 KB, keeping only the tail).

  Task 3 (firewall A/B) is CONDITIONAL and runs ONLY if 2.2's error looks
  network-ish. It is a reversible diagnostic on a VM that is destroyed at end of
  session -- NOT a validation. It restores the ruleset unconditionally, via a
  trap, even if the probe dies.
#>
$ErrorActionPreference = 'Continue'
$env:WSL_UTF8 = 1

# NB: not `H` -- PowerShell ships `h` as an alias for Get-History and aliases
# outrank functions, so `H "..."` silently becomes Get-History and throws.
function Section($t) { Write-Output ""; Write-Output "########## $t ##########" }

Section "0. CONTEXT"
Write-Output "--- date ---"; Get-Date -Format 'u'
Write-Output "--- whoami (must NOT be SYSTEM) ---"; whoami
Write-Output "--- INSTALLER_DONE ---"; Get-Content C:\cfv\INSTALLER_DONE.txt -ErrorAction SilentlyContinue
Write-Output "--- checkpoint (expect: ends at OpenClawConfigured) ---"
Get-Content C:\ProgramData\ClawFactory\checkpoint.json -Raw -ErrorAction SilentlyContinue

Section "2.3 setup.ps1's OWN log -- REAL PATH (confirmed setup.ps1:66-67)"
# setup.ps1 defines $LogDir = Join-Path $env:ProgramData 'ClawFactory' and
# $LogFile = "$LogDir\install.log". So the GW-JOURNAL/GW-STATUS/GW-PORT/GW-TMPLOG
# dump lands in C:\ProgramData\ClawFactory\install.log -- NOT under Program Files
# (both earlier guesses -- '...\ClawFactory Secure Setup\' and '...\ClawFactory\'
# under Program Files -- were wrong, which is why the dump was never read back).
$log = 'C:\ProgramData\ClawFactory\install.log'
Write-Output "--- path exists? $(Test-Path $log) : $log ---"
if (Test-Path $log) {
    Write-Output "--- GW-* diagnostic dump (the markers setup.ps1:1987-1990 writes) ---"
    Get-Content $log | Select-String -Pattern 'GW-JOURNAL|GW-STATUS|GW-PORT|GW-TMPLOG|gateway install|Gateway did not respond|returned' | Select-Object -Last 25
    Write-Output ""
    Write-Output "--- tail 150 ---"
    Get-Content $log -Tail 150
} else {
    Write-Output "NOT FOUND -- enumerating *.log under C:\ProgramData\ClawFactory:"
    Get-ChildItem 'C:\ProgramData\ClawFactory' -Filter *.log -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
}

# ---------------------------------------------------------------------------
$bash = @'
set +e

echo "########## 2.4 VERSION / SUBCOMMAND SANITY (rules out a mismatch cheaply) ##########"
echo "--- which openclaw (as clawuser) ---"
su clawuser -s /bin/bash -c 'command -v openclaw' 2>&1
echo "--- openclaw --version ---"
su clawuser -s /bin/bash -c 'openclaw --version' 2>&1
echo "--- does 'gateway' list an 'install' subcommand? ---"
su clawuser -s /bin/bash -c 'openclaw gateway --help' 2>&1 | head -30
echo "--- node/npm as clawuser ---"
su clawuser -s /bin/bash -c 'node --version; npm --version' 2>&1

echo ""
echo "########## 2.1 /tmp/openclaw-install.log -- written by setup.ps1:1913, never read back ##########"
ls -la /tmp/openclaw-install.log 2>&1
echo "--- contents ---"
cat /tmp/openclaw-install.log 2>&1

echo ""
echo "########## FIREWALL STATE AT PROBE TIME (the 'before' side of any A/B) ##########"
echo "--- is the clawfactory table even present? ---"
/usr/sbin/nft list table inet clawfactory >/dev/null 2>&1 && echo "  table inet clawfactory: PRESENT" || echo "  table inet clawfactory: ABSENT"
echo "--- the chain (clawuser is the only UID it applies to: 'meta skuid != clawuser return') ---"
/usr/sbin/nft list table inet clawfactory 2>&1 | head -40
echo "--- can clawuser reach the network AT ALL right now? ---"
su clawuser -s /bin/bash -c 'curl -s -o /dev/null -w "  curl https://registry.npmjs.org -> http=%{http_code} exit=" --max-time 8 https://registry.npmjs.org/ ; echo $?' 2>&1
su clawuser -s /bin/bash -c 'getent hosts registry.npmjs.org >/dev/null 2>&1; echo "  dns registry.npmjs.org rc=$?"' 2>&1

echo ""
echo "########## 2.2 *** THE ANSWER *** the exact failing command, as clawuser ##########"
echo "--- unit BEFORE (expect: absent) ---"
ls -l /home/clawuser/.config/systemd/user/openclaw-gateway.service 2>&1
echo ""
echo "--- RUNNING: su clawuser -s /bin/bash -c 'openclaw gateway install --force --port 8787; echo rc=\$?' ---"
OUT=$(su clawuser -s /bin/bash -c 'openclaw gateway install --force --port 8787; echo "rc=$?"' 2>&1)
echo "$OUT"
echo ""
echo "--- unit AFTER (did the manual re-run create it?) ---"
ls -l /home/clawuser/.config/systemd/user/openclaw-gateway.service 2>&1
echo "--- systemctl --user is-enabled (THE preflight openclaw runs; exit 4 = not-found) ---"
su clawuser -s /bin/bash -c 'systemctl --user is-enabled openclaw-gateway.service; echo "is-enabled rc=$?"' 2>&1
echo "--- systemctl --user is-active ---"
su clawuser -s /bin/bash -c 'systemctl --user is-active openclaw-gateway.service; echo "is-active rc=$?"' 2>&1

echo ""
echo "########## TASK 3 DECISION -- is 2.2's error network-ish? ##########"
# Decision rule, applied mechanically to 2.2's captured output. Network-ish =>
# run the firewall A/B. Anything else => the firewall is not implicated and the
# A/B would be theatre.
if echo "$OUT" | grep -qiE 'connection refused|ECONNREFUSED|timed out|ETIMEDOUT|could not reach|unable to fetch|fetch failed|getaddrinfo|EAI_AGAIN|ENOTFOUND|network|registry\.npmjs|download failed|dns'; then
  echo "  VERDICT: NETWORK-ISH -> running the A/B (Task 3)."
  DO_AB=1
else
  echo "  VERDICT: NOT network-ish -> SKIPPING Task 3 per the job's decision rule."
  echo "  (An A/B here would prove nothing: the firewall only scopes clawuser's"
  echo "   egress, and this failure is not an egress failure.)"
  DO_AB=0
fi

if [ "$DO_AB" = "1" ]; then
  echo ""
  echo "########## 3. FIREWALL A/B -- reversible, throwaway VM, differential diagnosis ##########"
  # ALWAYS restore, even if this script dies partway.
  RESTORED=0
  restore() {
    if [ "$RESTORED" = "0" ] && [ -f /tmp/nft-before.rules ]; then
      /usr/sbin/nft flush ruleset 2>&1
      /usr/sbin/nft -f /tmp/nft-before.rules 2>&1
      RESTORED=1
      echo "[restore] ruleset reloaded from /tmp/nft-before.rules"
    fi
  }
  trap restore EXIT INT TERM

  echo "--- 3.1 BEFORE: saving exact ruleset ---"
  /usr/sbin/nft list ruleset > /tmp/nft-before.rules 2>&1
  wc -l /tmp/nft-before.rules
  /usr/sbin/nft -a list chain inet clawfactory output 2>&1 | head -30

  echo ""
  echo "--- 3.2 RELAX: insert ONE rule accepting clawuser egress at the top of the chain ---"
  echo "    exact rule: nft insert rule inet clawfactory output meta skuid clawuser accept"
  /usr/sbin/nft insert rule inet clawfactory output meta skuid clawuser accept 2>&1
  echo "    rc=$?"
  /usr/sbin/nft -a list chain inet clawfactory output 2>&1 | head -12
  echo "    clawuser egress now?"
  su clawuser -s /bin/bash -c 'curl -s -o /dev/null -w "      curl npmjs -> http=%{http_code}\n" --max-time 8 https://registry.npmjs.org/' 2>&1

  echo ""
  echo "--- 3.3 RE-RUN the exact command with clawuser egress OPEN ---"
  rm -f /home/clawuser/.config/systemd/user/openclaw-gateway.service 2>/dev/null
  su clawuser -s /bin/bash -c 'openclaw gateway install --force --port 8787; echo "rc=$?"' 2>&1
  echo "    unit now?"
  ls -l /home/clawuser/.config/systemd/user/openclaw-gateway.service 2>&1

  echo ""
  echo "--- 3.4 RESTORE ---"
  restore
  trap - EXIT INT TERM
  echo "    verify restored (diff vs saved; empty = identical modulo counters/handles):"
  /usr/sbin/nft list ruleset > /tmp/nft-after.rules 2>&1
  diff <(sed -E 's/counter packets [0-9]+ bytes [0-9]+//g; s/# handle [0-9]+//g' /tmp/nft-before.rules) \
       <(sed -E 's/counter packets [0-9]+ bytes [0-9]+//g; s/# handle [0-9]+//g' /tmp/nft-after.rules) \
       && echo "    RESTORED: identical to the saved ruleset."
  echo "    clawuser egress after restore (expect blocked again):"
  su clawuser -s /bin/bash -c 'curl -s -o /dev/null -w "      curl npmjs -> http=%{http_code}\n" --max-time 8 https://registry.npmjs.org/' 2>&1
fi

echo ""
echo "########## PROBE COMPLETE ##########"
'@

Section "1-3. LINUX SIDE -- one wsl invocation"
# One invocation: per the v1.0.2 lineage the LAST wsl.exe session exiting triggers
# a distro shutdown, so N invocations would perturb the state N times.
$lf  = ($bash -replace "`r`n", "`n")
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($lf))
Write-Output "(bundle: $($lf.Length) bytes -> $($b64.Length) b64 chars, inline; /mnt/c intentionally absent)"
wsl -d Ubuntu -u root -- bash -c "echo $b64 | base64 -d | bash" 2>&1

Section "PROBE DONE"
