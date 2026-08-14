<#
  Why did Step-InstallSend abort with "firewall re-apply failed"?

  Runs in the interactive session through the same file-based WSL channel the
  phases use, because az run-command executes as SYSTEM and WSL refuses to run
  there (WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED).

  Diagnostic only. It changes nothing: nft is invoked in CHECK mode, which
  parses a config without applying it.
#>
param([string]$Transcript = 'C:\cfv\diag-fwapply-out.txt')

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1

function W([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line; $line | Out-File $Transcript -Encoding utf8 -Append
}

W "=== diagnosing the Guard 3 firewall re-apply failure ==="

$r = Invoke-WslFile -Tag 'diag-fw' -User 'root' -Body @'
echo "=== 1. does the shipped config PARSE? check mode applies nothing ==="
/usr/sbin/nft -c -f /etc/nftables.conf 2>&1 | head -25
echo "nft_check_rc=${PIPESTATUS[0]}"
echo
echo "=== 2. CONTROL: a deliberately broken config MUST be rejected by the same check ==="
sed 's/type ipv4_addr/type not_a_real_type/' /etc/nftables.conf > /var/tmp/bad.nft
if /usr/sbin/nft -c -f /var/tmp/bad.nft >/dev/null 2>&1; then echo "CONTROL FAILED (broken config accepted)"; else echo "CONTROL OK (broken config rejected)"; fi
rm -f /var/tmp/bad.nft
echo
echo "=== 3. fw-apply, traced, so the failing command names itself ==="
bash -x /usr/local/sbin/clawfactory-fw-apply.sh 2>&1 | tail -45
echo
echo "=== 4. fw-apply exit code on its own ==="
/usr/local/sbin/clawfactory-fw-apply.sh >/dev/null 2>&1; echo "fw_apply_rc=$?"
echo
echo "=== 5. the Guard 3 lines as they landed in the config ==="
grep -n "read_fetch" /etc/nftables.conf
echo
echo "=== 6. state of the inputs fw-apply reads ==="
for f in /etc/clawfactory/fw-backend /etc/clawfactory/allowed-ips.txt /etc/clawfactory/read-fetch-ips.txt /etc/clawfactory/dns-resolvers.txt; do
  if [ -e "$f" ]; then echo "PRESENT $f ($(wc -l < "$f" | tr -d ' ') lines)"; else echo "ABSENT  $f"; fi
done
echo "backend=$(cat /etc/clawfactory/fw-backend 2>/dev/null)"
echo
echo "=== 7. the resolver helper fw-apply calls FIRST, under set -e ==="
/usr/local/sbin/clawfactory-dns-resolvers.sh; echo "dns_resolvers_rc=$?"
echo
echo "=== 8. is the live table up at all right now? ==="
/usr/sbin/nft list table inet clawfactory >/dev/null 2>&1 && echo "TABLE_LIVE=yes" || echo "TABLE_LIVE=no"
'@
W $r.Out
W "DIAG_COMPLETE rc=0"
exit 0
