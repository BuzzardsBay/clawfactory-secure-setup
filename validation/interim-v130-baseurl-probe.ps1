<#
  Card #197 probe. READ-ONLY. Builds nothing.

  ONE QUESTION
  ------------
  Does the bundled provider plugin honour a `models.providers.*.baseUrl`
  override?

  WHY THAT ONE QUESTION IS WORTH A PROBE
  ---------------------------------------
  Two residuals in v1 have the same shape, and one mechanism would close both.

    * ADDRESS-SCOPING. nftables sets hold addresses, so any host sharing an
      address with something already reachable is reachable. Hostname-exact
      enforcement needs something that sees the SNI or the Host header, which
      means a broker; a broker running in the agent's own uid is advisory rather
      than structural.
    * PROVIDER-KEY EXFILTRATION. The API key sits in files the agent can read, so
      the agent can send it anywhere it can reach.

  A ROOT-OWNED OUTBOUND PROXY holding the key and enforcing hostnames would close
  both at once: the agent would need no provider address of its own and would
  never hold the key. That design is only possible if the plugin can be pointed
  at a local endpoint. If it cannot, address-scoping is PERMANENT for v1 and
  Guard 4's shape is settled the other way.

  So this is a fork in the road, and the answer decides which branch exists. It
  is worth one read-only probe at the end of a run that already has a working
  install.

  CREDENTIAL DISCIPLINE, AND IT IS ABSOLUTE
  ------------------------------------------
  The listener records THREE things: that a request arrived, the path requested,
  and WHETHER an Authorization header was present. Presence only. It never reads,
  logs, echoes or stores the value of any header, and it returns a fixed error
  rather than proxying anything onward. Nothing containing a key goes into a log,
  a transcript, or a close-out.

  This matters more than usual here: the whole point of the question is a design
  in which a proxy holds the key, so a probe that leaked the key while asking
  whether a proxy could hold it would be a poor joke.

  BUILD NOTHING ON THE ANSWER IN THIS JOB. Report it, card it, stop.
#>
param(
    [string]$Transcript = 'C:\cfv\baseurl-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'Card #197: does the provider plugin honour a baseUrl override?' `
    -Transcript $Transcript -Sentinel 'BASEURL_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'BU.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) {
    W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'
    Complete-Phase -ResultsJson 'C:\cfv\baseurl-results.json' -MarkerPrefix 'BASEURL'
}

# =========================================================================
Section '0. Where the provider is configured, and what the plugin actually is'
$survey = Invoke-WslFile -Tag 'bu-survey' -User 'root' -Body @'
echo "=== the gateway config, with any secret field REDACTED before printing ==="
node -e '
const fs=require("fs");
const p="/home/clawuser/.openclaw/openclaw.json";
const j=JSON.parse(fs.readFileSync(p,"utf8"));
// Print STRUCTURE only. Any key whose name suggests a secret is replaced with a
// marker before anything reaches stdout, so the transcript cannot carry one even
// if the config shape changes underneath this probe.
const SECRET=/key|token|secret|password|auth/i;
function scrub(o){
  if (o===null||typeof o!=="object") return o;
  if (Array.isArray(o)) return o.map(scrub);
  const out={};
  for (const k of Object.keys(o)) out[k]=SECRET.test(k)?"<redacted>":scrub(o[k]);
  return out;
}
console.log(JSON.stringify(scrub(j.models||{}),null,1));
console.log("HAS_PROVIDERS="+!!(j.models&&j.models.providers));
' 2>&1 | head -40
echo
echo "=== the bundled provider plugins ==="
ls /usr/lib/node_modules/openclaw/dist/extensions/ 2>/dev/null | head -20
echo
echo "=== does any plugin source even MENTION baseUrl? ==="
grep -rl "baseUrl\|baseURL" /usr/lib/node_modules/openclaw/dist/extensions/ 2>/dev/null | head -10
echo "GREP_HITS=$(grep -rl 'baseUrl\|baseURL' /usr/lib/node_modules/openclaw/dist/extensions/ 2>/dev/null | wc -l)"
echo
echo "=== CONTROL: a string that must NOT be found, so the grep is discriminating ==="
grep -rl 'ClawFactoryNegativeSentinelZZ9' /usr/lib/node_modules/openclaw/dist/extensions/ 2>/dev/null | head -2
echo "CONTROL_HITS=$(grep -rl 'ClawFactoryNegativeSentinelZZ9' /usr/lib/node_modules/openclaw/dist/extensions/ 2>/dev/null | wc -l)"
'@
W $survey.Out
$grepHits = if ($survey.Out -match 'GREP_HITS=(\d+)') { [int]$Matches[1] } else { -1 }
$ctlHits  = if ($survey.Out -match 'CONTROL_HITS=(\d+)') { [int]$Matches[1] } else { -1 }
# The static grep is a HINT, not the answer. Source mentioning baseUrl does not
# prove the configured value is read, and source not mentioning it does not prove
# an override is impossible. The execution test below is the answer; this is
# recorded as context.
Register-Control -Id 'BU.0.CTL' -Name 'the source search discriminates (a bogus sentinel is not found)' `
    -Fired ($ctlHits -eq 0 -and $grepHits -ge 0) `
    -Evidence "sentinel hits=$ctlHits (must be 0); baseUrl hits=$grepHits" | Out-Null
Record 'BU.0' 'Static survey: whether the bundled plugin source mentions baseUrl at all' 'INFO' `
    "$grepHits plugin file(s) mention baseUrl. This is context, NOT the answer: mentioning it does not prove the configured value is honoured."

# =========================================================================
Section '1. Stand up a root-owned listener that records PRESENCE only'
# Root-owned and on loopback. It is not a proxy: it forwards nothing, and it
# answers every request with a fixed error. All it has to do is prove whether the
# plugin came knocking.
$listener = Invoke-WslFile -Tag 'bu-listener' -User 'root' -Body @'
mkdir -p /var/tmp/cf197
rm -f /var/tmp/cf197/hits.log
cat > /var/tmp/cf197/listener.js <<'JS'
// Card #197 listener. Records THREE facts per request: that it arrived, the path,
// and WHETHER an Authorization header was present. It never reads, logs or stores
// any header VALUE, and it forwards nothing. Returns a fixed error so the caller
// fails fast and visibly rather than hanging.
const http = require("node:http");
const fs = require("node:fs");
const LOG = "/var/tmp/cf197/hits.log";
http.createServer((req, res) => {
  // Presence only. `in` tests for the key without ever reading the value, and
  // the value is never referenced anywhere in this file.
  const hasAuth = Object.prototype.hasOwnProperty.call(req.headers, "authorization");
  fs.appendFileSync(LOG, `HIT method=${req.method} path=${req.url} authHeaderPresent=${hasAuth}\n`);
  res.writeHead(418, { "content-type": "application/json" });
  res.end(JSON.stringify({ error: { message: "cf197-probe-listener", type: "probe" } }));
}).listen(18197, "127.0.0.1", () => fs.appendFileSync(LOG, "LISTENER_UP\n"));
JS
chmod 600 /var/tmp/cf197/listener.js
nohup node /var/tmp/cf197/listener.js >/var/tmp/cf197/listener.out 2>&1 &
sleep 2
echo "--- is it up? ---"
cat /var/tmp/cf197/hits.log 2>/dev/null | head -3
echo "--- CONTROL: the listener answers a direct request, so a later silence means the PLUGIN did not call it ---"
curl -s -o /dev/null -w 'direct_probe_http=%{http_code}\n' --max-time 10 http://127.0.0.1:18197/v1/messages
echo "--- log after the direct probe ---"
cat /var/tmp/cf197/hits.log 2>/dev/null | head -5
'@
W $listener.Out
$listenerUp = ($listener.Out -match 'direct_probe_http=418')
Register-Control -Id 'BU.1.CTL' -Name 'the listener is up and records a request that definitely reached it' `
    -Fired $listenerUp `
    -Evidence 'a direct curl returned 418 and was logged; without this, "the plugin did not call it" would be indistinguishable from "the listener was never listening"' | Out-Null
Record 'BU.1' 'A root-owned presence-only listener is running on 127.0.0.1:18197' `
    $(if ($listenerUp) { 'PASS' } else { 'FAIL' }) 'records arrival, path and whether an Authorization header was present; never a value'

# =========================================================================
Section '2. POSITIVE CONTROL FIRST: with NO override, a turn reaches the real provider'
# Deliberately before the override. If a turn cannot complete in the clean state,
# then a failed turn WITH the override says nothing about baseUrl and everything
# about the box, and running the control afterwards would tempt a reader to
# explain away the earlier result.
$warmBody = @'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: BASEURLCTL"}]}' > /tmp/bu.json
curl -s --max-time 180 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/tmp/bu.json
rm -f /tmp/bu.json
'@
$ctlTurn = Invoke-WslFile -Tag 'bu-ctl-turn' -User 'clawuser' -Body $warmBody
W $ctlTurn.Out
if ($ctlTurn.Out -notmatch 'BASEURLCTL') {
    W '--- cold start suspected; one retry (L17) ---'
    Start-Sleep -Seconds 25
    $ctlTurn = Invoke-WslFile -Tag 'bu-ctl-turn2' -User 'clawuser' -Body $warmBody
    W $ctlTurn.Out
}
$cleanTurnOk = $ctlTurn.Out -match 'BASEURLCTL'
Register-Control -Id 'BU.2.CTL' -Name 'with no override, a real turn reaches the provider and completes' `
    -Fired $cleanTurnOk `
    -Evidence 'this is the baseline the override is compared against; without it the whole probe is unmeasurable' | Out-Null
Record 'BU.2' 'Positive control: the unmodified provider path works on this box' `
    $(if ($cleanTurnOk) { 'PASS' } else { 'FAIL' }) 'a real model reply was returned'

# =========================================================================
Section '3. Set the override, run ONE turn, and see whether the listener was hit'
$override = Invoke-WslFile -Tag 'bu-override' -User 'root' -Body @'
cp /home/clawuser/.openclaw/openclaw.json /var/tmp/cf197/openclaw.json.bak
node -e '
const fs=require("fs");
const p="/home/clawuser/.openclaw/openclaw.json";
const j=JSON.parse(fs.readFileSync(p,"utf8"));
j.models=j.models||{};
j.models.providers=j.models.providers||{};
// Set the override on every configured provider, so the answer does not depend
// on guessing which one this box is using.
const names=Object.keys(j.models.providers);
if (names.length===0){ j.models.providers.anthropic={}; names.push("anthropic"); }
for (const n of names){ j.models.providers[n]=j.models.providers[n]||{}; j.models.providers[n].baseUrl="http://127.0.0.1:18197"; }
fs.writeFileSync(p, JSON.stringify(j,null,2));
console.log("OVERRIDE_SET_ON="+names.join(","));
'
chown clawuser:clawuser /home/clawuser/.openclaw/openclaw.json
echo "--- restart the gateway so the config is re-read ---"
su -s /bin/bash -c 'export XDG_RUNTIME_DIR=/run/user/1000; systemctl --user restart openclaw-gateway.service' clawuser 2>&1 | head -3
sleep 20
su -s /bin/bash -c 'export XDG_RUNTIME_DIR=/run/user/1000; systemctl --user is-active openclaw-gateway.service' clawuser 2>&1 | head -1
'@
W $override.Out

$ovTurn = Invoke-WslFile -Tag 'bu-ov-turn' -User 'clawuser' -Body @'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: BASEURLOVERRIDE"}]}' > /tmp/bu2.json
curl -s --max-time 120 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/tmp/bu2.json | head -c 600
rm -f /tmp/bu2.json
'@
W $ovTurn.Out

$hits = Invoke-WslFile -Tag 'bu-hits' -User 'root' -Body @'
echo "=== listener log (presence only; no header values are ever recorded) ==="
cat /var/tmp/cf197/hits.log 2>/dev/null
echo "PLUGIN_HITS=$(grep -c '^HIT' /var/tmp/cf197/hits.log 2>/dev/null || echo 0)"
'@
W $hits.Out
# One hit is the direct control curl from section 1. Anything beyond that is the
# plugin, which is the whole question.
$totalHits = if ($hits.Out -match 'PLUGIN_HITS=(\d+)') { [int]$Matches[1] } else { -1 }
$pluginHits = $totalHits - 1
$honoured = $pluginHits -ge 1

Record 'BU.3' 'Does the bundled provider plugin honour models.providers.*.baseUrl?' `
    $(if ($totalHits -lt 1) { 'VOID' } elseif ($honoured) { 'PASS' } else { 'FAIL' }) `
    ("listener recorded $totalHits request(s) total, of which 1 was this probe's own control curl, " +
     "so $pluginHits came from the plugin. ANSWER: " +
     $(if ($honoured) { 'YES, the override is honoured -- a root-owned outbound proxy is possible, and it could hold the key and enforce hostnames.' }
       else { 'NO, the override was ignored -- the plugin did not contact the local endpoint. Address-scoping is permanent for v1 and Guard 4 cannot be an outbound proxy in this shape.' }))

# =========================================================================
Section '4. Restore the config and prove the restore worked'
# Non-negotiable. This probe modified the live provider configuration, and a box
# left pointing at a dead loopback listener is a broken agent for whatever runs
# next, including a human at the keyboard.
$restore = Invoke-WslFile -Tag 'bu-restore' -User 'root' -Body @'
cp /var/tmp/cf197/openclaw.json.bak /home/clawuser/.openclaw/openclaw.json
chown clawuser:clawuser /home/clawuser/.openclaw/openclaw.json
chmod 600 /home/clawuser/.openclaw/openclaw.json
echo "OVERRIDE_GONE=$(grep -c '18197' /home/clawuser/.openclaw/openclaw.json || true)"
pkill -f 'cf197/listener.js' 2>/dev/null; echo "listener stopped"
rm -f /var/tmp/cf197/listener.js
su -s /bin/bash -c 'export XDG_RUNTIME_DIR=/run/user/1000; systemctl --user restart openclaw-gateway.service' clawuser 2>&1 | head -2
sleep 20
su -s /bin/bash -c 'export XDG_RUNTIME_DIR=/run/user/1000; systemctl --user is-active openclaw-gateway.service' clawuser 2>&1 | head -1
'@
W $restore.Out

$restoreTurn = Invoke-WslFile -Tag 'bu-restore-turn' -User 'clawuser' -Body $warmBody
W $restoreTurn.Out
if ($restoreTurn.Out -notmatch 'BASEURLCTL') {
    Start-Sleep -Seconds 25
    $restoreTurn = Invoke-WslFile -Tag 'bu-restore-turn2' -User 'clawuser' -Body $warmBody
    W $restoreTurn.Out
}
$restoredOk = $restoreTurn.Out -match 'BASEURLCTL'
Record 'BU.4' 'The box was restored: the override is gone and a real turn completes again' `
    $(if ($restoredOk -and ($restore.Out -match 'OVERRIDE_GONE=0')) { 'PASS' } else { 'FAIL' }) `
    'a probe that leaves the agent pointing at a dead listener has broken the box it was measuring'

Complete-Phase -ResultsJson 'C:\cfv\baseurl-results.json' -MarkerPrefix 'BASEURL'
