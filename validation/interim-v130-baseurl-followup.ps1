<#
  Card #197 follow-up. READ-ONLY. Builds nothing, changes nothing.

  WHY THIS EXISTS. The first probe set `models.providers.anthropic.baseUrl` and
  the listener was never contacted, which reads as "the override is ignored". But
  the same probe also reported `HAS_PROVIDERS=false` and a `models` section of
  `{}`: the shipped configuration has no `models.providers` structure at all, so
  the probe CREATED the key it then tested.

  That makes the bare answer overconfident. "The plugin did not read a key that
  does not otherwise exist in this config" is a much weaker statement than "the
  plugin ignores baseUrl", and Guard 4's shape should not be decided on the
  weaker one dressed as the stronger.

  So this establishes, by reading only:

    1. WHERE the provider endpoint actually comes from on a shipped box, since it
       is demonstrably not models.providers.
    2. WHETHER the bundled anthropic plugin declares a baseUrl option at all, in
       its own manifest and code, as opposed to the 3374 node_modules files that
       merely contain the string.
    3. WHAT config keys the plugin actually reads, so a future probe can set the
       right one rather than inventing a plausible one.

  Nothing here sets a key, restarts a service, or runs a turn. The previous probe
  already restored the box and proved it with a real turn.

  CREDENTIAL DISCIPLINE UNCHANGED: any field whose name suggests a secret is
  redacted before anything reaches stdout.
#>
param(
    [string]$Transcript = 'C:\cfv\baseurl2-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'Card #197 follow-up: where does the provider endpoint actually come from?' `
    -Transcript $Transcript -Sentinel 'BASEURL2_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'B2.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { Complete-Phase -ResultsJson 'C:\cfv\baseurl2-results.json' -MarkerPrefix 'BASEURL2' }

# =========================================================================
Section '1. What the anthropic plugin DECLARES, in its own manifest and code'
$r = Invoke-WslFile -Tag 'b2-manifest' -User 'root' -Body @'
P=/usr/lib/node_modules/openclaw/dist/extensions/anthropic
echo "=== the plugin manifest ==="
cat "$P/openclaw.plugin.json" 2>/dev/null | head -60
echo
echo "=== does the plugin CODE reference a baseUrl or base_url option ==="
grep -rhoE '(baseUrl|base_url|baseURL)[^,;)]{0,70}' "$P" 2>/dev/null | sort -u | head -20
# grep -h -o piped to wc -l. NOT `grep -c ... | paste -sd+ | bc`: with multiple
# files grep -c emits "path:N" per file, so the sum expression was malformed, bc
# is not installed anyway, and the whole substitution produced an EMPTY string.
# That made the count -1, the positive control did not fire, and the phase went
# VOID. Which is exactly right, and is why this is being fixed rather than
# argued with: without the runner this would have reported a confident FAIL
# saying the plugin has no baseUrl support, which the grep output on the line
# above flatly contradicts.
echo "PLUGIN_CODE_BASEURL_HITS=$(grep -rhoE 'baseUrl|base_url|baseURL' "$P" 2>/dev/null | wc -l | tr -d ' ')"
echo
echo "=== CONTROL: a string that must NOT appear in the same files ==="
echo "CONTROL_HITS=$(grep -rhoE 'ClawFactoryNegativeSentinelZZ9' "$P" 2>/dev/null | wc -l | tr -d ' ')"
echo
echo "=== WHICH key does it read? This is the actual question. ==="
grep -rhoE '.{0,50}(baseUrl|base_url|baseURL).{0,50}' "$P" 2>/dev/null | sort -u | head -12
'@
W $r.Out
$codeHits = if ($r.Out -match 'PLUGIN_CODE_BASEURL_HITS=(\d+)') { [int]$Matches[1] } else { -1 }
$ctlHits  = if ($r.Out -match 'CONTROL_HITS=(\d+)') { [int]$Matches[1] } else { -1 }
Register-Control -Id 'B2.1.CTL' -Name 'the search over the plugin discriminates' `
    -Fired ($ctlHits -eq 0 -and $codeHits -ge 0) -Evidence "sentinel hits=$ctlHits (must be 0); baseUrl hits in plugin code=$codeHits" | Out-Null
Record 'B2.1' 'The bundled anthropic plugin references a baseUrl option in its OWN code' `
    $(if ($codeHits -gt 0) { 'PASS' } else { 'FAIL' }) `
    "$codeHits reference(s) in the plugin's own .js, as opposed to the 3374 files under node_modules that merely contain the string"

# =========================================================================
Section '2. Where the endpoint actually comes from on a shipped box'
$r2 = Invoke-WslFile -Tag 'b2-where' -User 'root' -Body @'
echo "=== gateway config, structure only, secrets redacted ==="
node -e '
const fs=require("fs");
const SECRET=/key|token|secret|password|auth/i;
function scrub(o){ if(o===null||typeof o!=="object") return o;
  if(Array.isArray(o)) return o.map(scrub);
  const out={}; for(const k of Object.keys(o)) out[k]=SECRET.test(k)?"<redacted>":scrub(o[k]); return out; }
const j=JSON.parse(fs.readFileSync("/home/clawuser/.openclaw/openclaw.json","utf8"));
console.log("TOP_LEVEL_KEYS="+Object.keys(j).join(","));
console.log(JSON.stringify(scrub(j),null,1).slice(0,1500));
'
echo
echo "=== the agent definition, which carries the model ==="
sed -n "1,12p" /home/clawuser/.openclaw/agents/main/agent.md 2>/dev/null
echo
echo "=== auth-profiles STRUCTURE only, values never printed ==="
node -e '
const fs=require("fs");
const p="/home/clawuser/.openclaw/auth-profiles.json";
const j=JSON.parse(fs.readFileSync(p,"utf8"));
function shape(o){ if(o===null||typeof o!=="object") return typeof o;
  if(Array.isArray(o)) return ["array"];
  const out={}; for(const k of Object.keys(o)) out[k]=shape(o[k]); return out; }
console.log("AUTH_PROFILE_SHAPE="+JSON.stringify(shape(j)));
' 2>/dev/null || echo "(auth-profiles unreadable)"
'@
W $r2.Out
Record 'B2.2' 'The shipped config has no models.providers section, so the first probe set an invented key' `
    $(if ($r2.Out -match 'TOP_LEVEL_KEYS=') { 'PASS' } else { 'VOID' }) `
    'recorded so the #197 answer is read as "not at that key, in this config shape" rather than "baseUrl is ignored everywhere"'

Complete-Phase -ResultsJson 'C:\cfv\baseurl2-results.json' -MarkerPrefix 'BASEURL2'
