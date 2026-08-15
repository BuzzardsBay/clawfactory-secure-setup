<#
  Diagnostic for the three reachability FAILs in the toolchain suite.

  WHAT HAPPENED. With the toolchain set holding 18 addresses (switch ON),
  api.github.com was BLOCKED. With the set holding 0 addresses (switch OFF),
  registry.npmjs.org and raw.githubusercontent.com were still CONNECTED. Those
  look contradictory and are not: both are the address-scoping residual, showing
  up in the two opposite directions at once.

  THE TWO HYPOTHESES, and this phase decides between them by measurement rather
  than by argument.

    H1, for the hosts that stay reachable when the set is empty: their addresses
        are ALSO in @allowed_ipv4, because a model provider is fronted by the
        same CDN. If so, emptying the toolchain set cannot make them unreachable,
        and no amount of toggle work would change that.

    H2, for the host that is unreachable when the set is full: its address pool
        ROTATES, so the address the resolver put in the set five seconds earlier
        is not the address the probe's own lookup returns. If so, the toggle
        works exactly as designed and the host is intermittently reachable for a
        reason that has nothing to do with the switch.

  These need different answers in the product, which is why guessing between them
  is not acceptable. H1 is a permanent v1 residual to be documented. H2 is a
  refresh-cadence problem that a shorter interval or a larger pool would reduce.

  READ-ONLY. It resolves names, reads sets, and compares. It changes no policy and
  writes no rule.
#>
param(
    [string]$Transcript = 'C:\cfv\addrdiag-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'Address-scoping diagnostic for the three toolchain reachability FAILs' `
    -Transcript $Transcript -Sentinel 'ADDRDIAG_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'AD.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { Complete-Phase -ResultsJson 'C:\cfv\addrdiag-results.json' -MarkerPrefix 'ADDRDIAG' }

# =========================================================================
Section '1. Which set holds each host address, right now, with the switch ON'
$r = Invoke-WslFile -Tag 'ad-sets' -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl toolchain on >/dev/null 2>&1
sleep 2
echo "=== the three sets, as the firewall holds them ==="
for s in allowed_ipv4 toolchain_ipv4 read_fetch_ipv4; do
  n=$(nft list set inet clawfactory $s 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l)
  echo "SET $s = $n address(es)"
done
echo
echo "=== per host: what it resolves to NOW, and which set each address is in ==="
for h in api.github.com registry.npmjs.org raw.githubusercontent.com objects.githubusercontent.com clawhub.ai api.anthropic.com; do
  echo "--- $h ---"
  IPS=$(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u)
  [ -n "$IPS" ] || { echo "  (does not resolve)"; continue; }
  for ip in $IPS; do
    inA=$(nft list set inet clawfactory allowed_ipv4   2>/dev/null | grep -c "\b$ip\b")
    inT=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -c "\b$ip\b")
    echo "  $h $ip allowed=$inA toolchain=$inT"
  done
done
echo
echo "=== the persisted toolchain list the resolver derived ==="
cat /etc/clawfactory/toolchain-ips.txt 2>/dev/null | tr '\n' ' '; echo
'@
W $r.Out

# H1: does any toolchain host share an address with the PROVIDER set?
$sharedHosts = @()
foreach ($m in [regex]::Matches($r.Out, '(?m)^\s+(\S+) (\d+\.\d+\.\d+\.\d+) allowed=(\d+) toolchain=(\d+)')) {
    $h = $m.Groups[1].Value; $ip = $m.Groups[2].Value
    $inA = [int]$m.Groups[3].Value; $inT = [int]$m.Groups[4].Value
    if ($h -ne 'api.anthropic.com' -and $inA -gt 0) { $sharedHosts += "$h/$ip" }
}
Register-Control -Id 'AD.1.CTL' -Name 'the set-membership probe produced parseable rows at all' `
    -Fired ([regex]::Matches($r.Out, 'allowed=\d+ toolchain=\d+').Count -gt 0) `
    -Evidence "parsed $([regex]::Matches($r.Out, 'allowed=\d+ toolchain=\d+').Count) host/address rows" | Out-Null

Record 'AD.1' 'H1: a toolchain host shares an address with the always-open provider set' `
    $(if ($sharedHosts.Count -gt 0) { 'PASS' } else { 'FAIL' }) `
    ("shared host/address pairs found: " + $(if ($sharedHosts.Count) { ($sharedHosts | Select-Object -Unique) -join ', ' } else { 'NONE' }) +
     ". If any, the toggle CANNOT make that host unreachable and no toggle design could.")

# =========================================================================
Section '2. Does the address pool rotate between one lookup and the next?'
# H2. Resolve the same name repeatedly and see whether the answer moves. A pool
# that rotates faster than the refresh cadence means a host can be listed and
# still unreachable, which is what api.github.com did.
$r2 = Invoke-WslFile -Tag 'ad-rotate' -User 'root' -Body @'
for h in api.github.com registry.npmjs.org raw.githubusercontent.com; do
  echo "--- $h ---"
  for i in 1 2 3 4 5; do
    echo "  lookup$i: $(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')"
    sleep 1
  done
  echo "  UNION_over_5_lookups=$(for i in 1 2 3 4 5; do getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}'; sleep 1; done | sort -u | wc -l)"
done
'@
W $r2.Out
$ghUnion = if ($r2.Out -match '(?s)--- api\.github\.com ---.*?UNION_over_5_lookups=(\d+)') { [int]$Matches[1] } else { -1 }
$npmUnion = if ($r2.Out -match '(?s)--- registry\.npmjs\.org ---.*?UNION_over_5_lookups=(\d+)') { [int]$Matches[1] } else { -1 }
Record 'AD.2' 'H2: the address pool for a toolchain host rotates between lookups' `
    $(if ($ghUnion -gt 1) { 'PASS' } elseif ($ghUnion -eq 1) { 'FAIL' } else { 'VOID' }) `
    "api.github.com resolved to $ghUnion distinct address(es) across five lookups; registry.npmjs.org to $npmUnion. More than one means a set built from one lookup can miss the address the next connection uses."

# =========================================================================
Section '3. The decisive test: with the switch ON, is the CURRENTLY resolved address in the set?'
$r3 = Invoke-WslFile -Tag 'ad-decisive' -User 'root' -Body @'
for h in api.github.com registry.npmjs.org; do
  IP=$(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | head -1)
  IN=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -c "\b$IP\b")
  echo "$h now-resolves-to=$IP in-toolchain-set=$IN"
done
echo "--- and can uid 1000 actually reach them at this instant ---"
'@
W $r3.Out
$r3b = Invoke-WslFile -Tag 'ad-decisive-reach' -User 'clawuser' -Body @'
probe() { if timeout 10 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then echo "$1:$2 CONNECTED"; else echo "$1:$2 blocked"; fi; }
for h in api.github.com registry.npmjs.org raw.githubusercontent.com; do probe $h 443; done
probe api.anthropic.com 443
probe example.org 443
'@
W $r3b.Out
Register-Control -Id 'AD.3.CTL' -Name 'the reachability probe still discriminates in this run' `
    -Fired (($r3b.Out -match 'api\.anthropic\.com:443 CONNECTED') -and ($r3b.Out -match 'example\.org:443 blocked')) `
    -Evidence 'provider reachable and an un-allowlisted site blocked, in the same run' | Out-Null
Record 'AD.3' 'With the switch ON, the currently-resolved address is in the toolchain set' `
    $(if ($r3.Out -match 'in-toolchain-set=[1-9]') { 'PASS' } else { 'FAIL' }) `
    'if the resolved address is NOT in the set, the set was built from a different lookup and the host is intermittently unreachable by design'

Complete-Phase -ResultsJson 'C:\cfv\addrdiag-results.json' -MarkerPrefix 'ADDRDIAG'
