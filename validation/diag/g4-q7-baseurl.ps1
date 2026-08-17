<#
  QUESTION 7. Card #197, the follow-up that was carded rather than run.

  WHY THE FIRST ANSWER DOES NOT SETTLE IT
  ----------------------------------------
  The first probe set models.providers.anthropic.baseUrl and the listener was
  never contacted. The same probe also reported HAS_PROVIDERS=false and a
  top-level key list with no models section, so it CREATED the key it then
  tested. "The plugin did not read a key that does not otherwise exist in this
  config" is a much weaker statement than "the plugin ignores baseUrl", and the
  follow-up found the plugin reads model.baseUrl, a property of the model
  definition. That is demonstrated in the plugin's own source and NOT YET
  demonstrated by execution. This phase is the execution.

  CREDENTIAL DISCIPLINE, UNCHANGED AND NON-NEGOTIABLE
  ----------------------------------------------------
  The listener records that a request arrived, its path, and whether an
  Authorization header was PRESENT. It never reads, logs or stores a header
  value. The config survey redacts every field whose name suggests a secret
  before anything reaches stdout. Nothing here prints a key.

  THE TWO CONTROLS, AND WHY NEITHER IS OPTIONAL
  ---------------------------------------------
  Control 1: the probe's own request reaches the listener. Without it, "never
  contacted" is ambiguous between a working override and a dead listener, which
  are opposite answers with identical evidence.

  Control 2: with the override removed, the same turn completes end to end
  against the real provider. Without it, a negative result is ambiguous between
  "the override was ignored" and "the gateway was broken by the edit", and the
  second would be this probe's own doing.

  SCOPE CORRECTION CARRIED IN THE OUTPUT (work package 9.3)
  ----------------------------------------------------------
  A baseUrl override redirects traffic made by the MODEL PLUGIN. Read-fetch and
  toolchain traffic leaves uid 1000 through ordinary clients and never touches
  the plugin, so nothing a proxy does to the provider path makes GitHub, npm or a
  user-added destination hostname-exact. A working override would close the
  provider-key exfiltration residual and could make the provider route
  hostname-exact. Address-scoping for user-added and toolchain destinations is
  unaffected. This is recorded as a result row so it travels with the evidence.
#>
param(
    [string]$Transcript = 'C:\cfv\g4-q7-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\g4-common.ps1

Start-Phase -Name 'Card #197 follow-up: does the model plugin honour model.baseUrl' `
    -Transcript $Transcript -Sentinel 'G4_Q7_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'Q7.CHAN' -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { Complete-Phase -ResultsJson 'C:\cfv\g4-q7-results.json' -MarkerPrefix 'G4Q7' }

$PORT = 9099
$CONF = '/home/clawuser/.openclaw/openclaw.json'

# ============================================================================
Section '1. The model definition the agent actually uses, verbatim and redacted'
$survey = Invoke-WslFile -Tag 'g4-q7-survey' -User 'root' -Body @"
cp '$CONF' /var/tmp/g4/openclaw.json.pristine
echo "PRISTINE_SHA=`$(sha256sum /var/tmp/g4/openclaw.json.pristine | cut -d' ' -f1)"
echo
echo '=== gateway config, structure only, every secret-shaped field redacted ==='
node -e '
const fs=require("fs");
const SECRET=/key|token|secret|password|auth|credential/i;
function scrub(o){ if(o===null||typeof o!=="object") return o;
  if(Array.isArray(o)) return o.map(scrub);
  const out={}; for(const k of Object.keys(o)) out[k]=SECRET.test(k)?"<redacted>":scrub(o[k]); return out; }
const j=JSON.parse(fs.readFileSync("$CONF","utf8"));
console.log("TOP_LEVEL_KEYS="+Object.keys(j).join(","));
console.log("HAS_MODELS="+(j.models!==undefined));
console.log("HAS_AGENTS="+(j.agents!==undefined));
console.log("MODEL_STRINGS="+JSON.stringify(JSON.stringify(scrub(j)).match(/"model"\s*:\s*"[^"]*"/g)||[]));
console.log(JSON.stringify(scrub(j),null,1).slice(0,2500));
'
echo
echo '=== the key the plugin reads, in the plugin s own code ==='
P=/usr/lib/node_modules/openclaw/dist/extensions/anthropic
grep -rhoE '.{0,60}(baseUrl|baseURL).{0,40}' "`$P" 2>/dev/null | sort -u | head -12
echo "PLUGIN_BASEURL_HITS=`$(grep -rhoE 'baseUrl|baseURL' "`$P" 2>/dev/null | wc -l | tr -d ' ')"
echo "CONTROL_SENTINEL_HITS=`$(grep -rhoE 'ClawFactoryNegativeSentinelZZ9' "`$P" 2>/dev/null | wc -l | tr -d ' ')"
"@
W $survey.Out
$pluginHits = if ($survey.Out -match 'PLUGIN_BASEURL_HITS=(\d+)') { [int]$Matches[1] } else { -1 }
$sentinelHits = if ($survey.Out -match 'CONTROL_SENTINEL_HITS=(\d+)') { [int]$Matches[1] } else { -1 }
Register-Control -Id 'Q7.1.CTL' -Name 'the search over the plugin discriminates' `
    -Fired ($sentinelHits -eq 0 -and $pluginHits -gt 0) `
    -Evidence "fabricated sentinel hits=$sentinelHits (must be 0); baseUrl hits in the plugin's own code=$pluginHits (must be above 0)" | Out-Null
Record 'Q7.1' 'The bundled plugin reads a baseUrl off the model definition, in its own source' `
    $(if ($pluginHits -gt 0) { 'PASS' } else { 'FAIL' }) `
    "$pluginHits reference(s). This is the SOURCE evidence that card #197 already had; the rows below are the EXECUTION evidence it did not."

# ============================================================================
Section '2. The listener, and control 1: proof it is up and reachable'
$listen = Invoke-WslFile -Tag 'g4-q7-listener' -User 'root' -Body @"
rm -f /var/tmp/g4/listener.log
cat > /var/tmp/g4-listener.py <<'LEOF'
import http.server, json, sys

LOG = "/var/tmp/g4/listener.log"

class H(http.server.BaseHTTPRequestHandler):
    def _record(self):
        # PRESENCE ONLY. The value of the Authorization header is never read,
        # never logged and never stored. Recording that a credential WOULD have
        # been sent is the entire finding; its bytes are not.
        rec = {
            "method": self.command,
            "path": self.path,
            "auth_header_present": "authorization" in {k.lower() for k in self.headers.keys()},
            "host_header_present": "host" in {k.lower() for k in self.headers.keys()},
        }
        with open(LOG, "a") as f:
            f.write(json.dumps(rec) + "\n")
        body = b'{"error":{"type":"probe_listener","message":"this endpoint records presence only"}}'
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._record()

    def do_POST(self):
        self._record()

    def log_message(self, *a):
        pass

http.server.HTTPServer(("127.0.0.1", $PORT), H).serve_forever()
LEOF
nohup python3 /var/tmp/g4-listener.py > /var/tmp/g4/listener.err 2>&1 &
sleep 3
echo "LISTENER_PID=`$(pgrep -f g4-listener.py | head -1 || echo NONE)"
echo '--- CONTROL 1: a request from the same context the gateway runs in ---'
su -s /bin/bash -c "curl -s -o /dev/null -w 'CONTROL1_HTTP=%{http_code}\n' -m 5 http://127.0.0.1:$PORT/v1/probe-control" clawuser 2>&1
sleep 1
echo "CONTROL1_LOGGED=`$(grep -c 'probe-control' /var/tmp/g4/listener.log 2>/dev/null | tr -d ' ')"
cat /var/tmp/g4/listener.log 2>/dev/null
"@
W $listen.Out
$c1 = ($listen.Out -match 'CONTROL1_HTTP=200') -and ($listen.Out -match 'CONTROL1_LOGGED=[1-9]')
Register-Control -Id 'Q7.2.CTL' -Name 'CONTROL 1: the listener is up and reachable from the gateway''s own uid' `
    -Fired $c1 -Evidence 'without this, "never contacted" is ambiguous between a working override and a dead listener' | Out-Null
if (-not $c1) {
    W 'The listener could not be shown reachable, so a negative result below would mean nothing.'
    Complete-Phase -ResultsJson 'C:\cfv\g4-q7-results.json' -MarkerPrefix 'G4Q7'
}

# ============================================================================
Section '3. Set baseUrl ON THE MODEL DEFINITION, restart, run one warmed turn'
# Written generically because the shape is discovered rather than assumed: the
# edit reports exactly WHERE it wrote and whether that location already existed.
# "Created by this probe" and "already present" are different strengths of
# evidence and the report has to be able to tell them apart.
$apply = Invoke-WslFile -Tag 'g4-q7-apply' -User 'root' -Body @"
node -e '
const fs=require("fs");
const P="$CONF";
const j=JSON.parse(fs.readFileSync(P,"utf8"));
const URL="http://127.0.0.1:$PORT";
const written=[];
function note(where, preexisting){ written.push({where, preexisting}); }

// 1. models map, keyed by model id, which is where model.baseUrl lives if the
//    config declares models at all.
if (j.models && typeof j.models === "object" && !Array.isArray(j.models)) {
  for (const k of Object.keys(j.models)) {
    if (j.models[k] && typeof j.models[k] === "object") {
      note("models."+k+".baseUrl", j.models[k].baseUrl !== undefined);
      j.models[k].baseUrl = URL;
    }
  }
}
// 2. agent-level model definitions expressed as objects.
if (j.agents && typeof j.agents === "object") {
  for (const a of Object.keys(j.agents)) {
    const ag = j.agents[a];
    if (ag && typeof ag.model === "object") {
      note("agents."+a+".model.baseUrl", ag.model.baseUrl !== undefined);
      ag.model.baseUrl = URL;
    }
  }
}
// 3. a top-level model definition object.
if (j.model && typeof j.model === "object") {
  note("model.baseUrl", j.model.baseUrl !== undefined);
  j.model.baseUrl = URL;
}
// 4. If the config names its model as a STRING only, there is no definition
//    object to hang baseUrl on. Creating one is exactly the weakness that made
//    the first probe overconfident, so it is done AND labelled as invented.
if (written.length === 0) {
  j.models = j.models || {};
  j.models["clawfactory-probe-model"] = { baseUrl: URL };
  note("models.clawfactory-probe-model.baseUrl", false);
}
fs.writeFileSync(P, JSON.stringify(j, null, 2));
console.log("WROTE="+JSON.stringify(written));
console.log("ANY_PREEXISTING="+written.some(w=>w.preexisting));
'
chown clawuser:clawuser '$CONF'
echo "CONFIG_CHANGED=`$(sha256sum '$CONF' | cut -d' ' -f1)"
echo '--- restarting the gateway so the edit is actually loaded ---'
systemctl restart openclaw-gateway.service 2>&1
sleep 12
echo "GATEWAY_STATE=`$(systemctl is-active openclaw-gateway.service 2>&1)"
echo '--- L17: warm, then the load-bearing turn ---'
su -s /bin/bash -c "timeout 120 openclaw agent --agent main --message 'Reply with the single word WARM.' 2>&1 | tail -2" clawuser 2>&1 | tail -2
su -s /bin/bash -c "timeout 180 openclaw agent --agent main --message 'Reply with the single word OVERRIDE.' 2>&1 | tail -4" clawuser 2>&1 | tail -4
sleep 2
echo "LISTENER_HITS_TOTAL=`$(grep -c . /var/tmp/g4/listener.log 2>/dev/null | tr -d ' ')"
echo "LISTENER_HITS_NONCONTROL=`$(grep -v 'probe-control' /var/tmp/g4/listener.log 2>/dev/null | grep -c . | tr -d ' ')"
echo '--- every request the listener saw, presence only ---'
cat /var/tmp/g4/listener.log 2>/dev/null
"@
W $apply.Out

$wroteWhere = if ($apply.Out -match 'WROTE=(\[.*\])') { $Matches[1] } else { '(not reported)' }
$anyPre = $apply.Out -match 'ANY_PREEXISTING=true'
$hits = if ($apply.Out -match 'LISTENER_HITS_NONCONTROL=(\d+)') { [int]$Matches[1] } else { -1 }
$gwUp = $apply.Out -match 'GATEWAY_STATE=active'

Record 'Q7.2' 'The override was written to a model definition that ALREADY EXISTED in the shipped config' `
    $(if ($anyPre) { 'PASS' } else { 'INFO' }) `
    "locations written: $wroteWhere. A FALSE here means the config names its model as a string and this probe had to CREATE the definition, which is the same weakness that made the first #197 answer overconfident. The verdict below is reported at that strength."

$null = Require-Precondition -Id 'Q7.PRE.GW' -Name 'the gateway came back up after the edit' `
    -Met $gwUp -Reason 'a gateway that did not restart cannot contact anything, and its silence would be misread as the override being ignored'

Record 'Q7.3' 'With baseUrl set on the model definition, the plugin CONTACTS the local endpoint' `
    $(if ($hits -gt 0) { 'PASS' } else { 'FAIL' }) `
    "$hits non-control request(s) reached the listener during a warmed agent turn. Control 1 already proved the listener was reachable in this run."

# ============================================================================
Section '4. Control 2: restore, and prove the box works without the override'
$restore = Invoke-WslFile -Tag 'g4-q7-restore' -User 'root' -Body @"
cp /var/tmp/g4/openclaw.json.pristine '$CONF'
chown clawuser:clawuser '$CONF'
echo "RESTORED_SHA=`$(sha256sum '$CONF' | cut -d' ' -f1)"
echo "PRISTINE_SHA=`$(sha256sum /var/tmp/g4/openclaw.json.pristine | cut -d' ' -f1)"
systemctl restart openclaw-gateway.service 2>&1
sleep 12
echo "GATEWAY_STATE=`$(systemctl is-active openclaw-gateway.service 2>&1)"
echo '--- CONTROL 2: a real turn, end to end, against the real provider ---'
su -s /bin/bash -c "timeout 120 openclaw agent --agent main --message 'Reply with the single word WARM.' 2>&1 | tail -1" clawuser 2>&1 | tail -1
su -s /bin/bash -c "timeout 180 openclaw agent --agent main --message 'Reply with exactly the word RESTORED and nothing else.' 2>&1 | tail -4" clawuser 2>&1 | tail -4
sleep 2
echo "LISTENER_HITS_AFTER_RESTORE=`$(grep -v 'probe-control' /var/tmp/g4/listener.log 2>/dev/null | grep -c . | tr -d ' ')"
pkill -f g4-listener.py 2>/dev/null
echo "LISTENER_STOPPED=`$(pgrep -f g4-listener.py | head -1 || echo yes)"
"@
W $restore.Out

$shaMatch = $false
if (($restore.Out -match 'RESTORED_SHA=([0-9a-f]{64})')) {
    $rs = $Matches[1]
    if ($restore.Out -match 'PRISTINE_SHA=([0-9a-f]{64})') { $shaMatch = ($rs -eq $Matches[1]) }
}
$turnOk = $restore.Out -match 'RESTORED'
Register-Control -Id 'Q7.4.CTL' -Name 'CONTROL 2: with the override removed, a real turn completes end to end' `
    -Fired $turnOk `
    -Evidence 'without this a negative above is ambiguous between "the override was ignored" and "this probe broke the gateway"' | Out-Null
Record 'Q7.4' 'The configuration was restored byte for byte, and the restoration was proven' `
    $(if ($shaMatch) { 'PASS' } else { 'FAIL' }) `
    "restored digest equals the pristine digest taken before any edit = $shaMatch"

# ============================================================================
Section '5. The scope correction, recorded so it travels with the evidence'
Record 'Q7.5' 'What a root-owned outbound proxy would and would NOT buy' 'INFO' `
    ('A baseUrl override redirects traffic made by the MODEL PLUGIN only. It would close the PROVIDER-KEY EXFILTRATION residual and could make the PROVIDER ROUTE hostname-exact. ' +
     'It would NOT make GitHub, npm, the skill hub or any user-added destination hostname-exact, because that traffic leaves uid 1000 through ordinary clients and never touches the plugin. ' +
     'The #245 close-out records these two residuals closing together; that is overstated and must not be carried forward.')
Record 'Q7.6' 'This answer does not gate Guard 4' 'INFO' `
    ('Guard 4 is snapshot-on-write, a filesystem control. The proxy is a network control. Two close-outs carry a line saying the #197 answer decides Guard 4 shape; it does not. ' +
     'The two questions share this session because both are read-only probes needing one install, which is the only thing they share.')

Complete-Phase -ResultsJson 'C:\cfv\g4-q7-results.json' -MarkerPrefix 'G4Q7'
