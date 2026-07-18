<#
  v1.0.44 CONFIRMATION probe (PART B only, no rebuild). Runs ON the VM as clawadmin
  (auto-logon + RunOnce). TWO deliverables, plus the standard install gate:
    - Task 3: the CLEAN 4.2 positive control (warm the agent first, then measure).
    - Task 4: the chatCompletions BLOCK-MESSAGE investigation (cold-meter artifact
      vs a real gap in the proxy's block rendering), and -- separately -- whether
      the gating still BLOCKS the turn (security) even if the message is blank.
  NOT the full headline suite (proven). Every agent/proxy claim is captured verbatim.
#>
$ErrorActionPreference = 'Continue'
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
function W($m) { Write-Output $m }
function Section($t) { W ""; W ("########## " + $t + " ##########") }
# 2>$null suppresses wsl's PATH-translation noise (automount=false); inner 2>&1 keeps command stderr.
function Wsl([string]$cmd, [string]$user = 'clawuser') {
    $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cmd))
    return (& wsl.exe -d Ubuntu --cd / -u $user -- bash -lc "echo $b | base64 -d | bash" 2>$null | Out-String)
}
# Drive the REAL gated agent (openclaw agent, through the turn-gate shim), as clawuser.
function AgentSay([string]$Msg, [int]$T = 150) {
    $mb = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Msg))
    $inner = "timeout $T openclaw agent --agent main --message `"`$(printf %s '$mb' | base64 -d)`" 2>&1"
    $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($inner))
    $o = (& wsl.exe -d Ubuntu --cd / -u clawuser -- bash -lc "echo $b | base64 -d | bash" 2>$null | Out-String)
    return (($o -split "`n") | Where-Object { $_ -notmatch 'staging bundled|installed bundled|Failed to translate' }) -join "`n"
}
# ChatPost: the EXACT ClawChat consumer shape -- token-authed POST to the gating
# proxy on 8787 (Bearer + x-openclaw-agent-id, model openclaw/main). Token read in
# WSL, never printed. Captures the HTTP code AND the raw body.
function ChatPost([string]$json) {
    $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $cmd = 'TOKEN=$(node -e ''const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")''); ' +
           'printf %s ' + $b + ' | base64 -d > /tmp/cf_c.json; ' +
           'code=$(curl -s -o /tmp/cf_r.txt -w "%{http_code}" --max-time 150 -X POST http://127.0.0.1:8787/v1/chat/completions ' +
           '-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" -d @/tmp/cf_c.json); ' +
           'echo "HTTP=$code"; echo "BODY>>>"; cat /tmp/cf_r.txt; echo; echo "<<<BODY"; rm -f /tmp/cf_c.json /tmp/cf_r.txt'
    return (Wsl $cmd)
}
function SetGov([string]$json) {
    $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    Wsl ("echo $b | base64 -d > /etc/clawfactory/governor.json; chmod 644 /etc/clawfactory/governor.json") 'root' | Out-Null
}
$rand = -join ((48..57) + (97..122) | Get-Random -Count 10 | ForEach-Object { [char]$_ })

W "===== ClawFactory v1.0.44 CONFIRMATION ($(Get-Date -Format s)) ====="
W "identity: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)  IsSystem=$([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem)"
if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { W "FATAL: SYSTEM -- WSL unusable."; exit 2 }

# =====================================================================
# TASK 2 -- install gate (must stay GREEN; a regression => STOP)
# =====================================================================
Section "TASK 2 -- install gate (should stay GREEN)"
$marker = (Get-Content 'C:\ProgramData\ClawFactory\install-result.txt' -EA SilentlyContinue | Out-String).Trim()
W "install-result.txt: $marker"
$succ = $marker -match 'INSTALLER_DONE=success'
W ("2.1 VERDICT: " + $(if ($succ) { 'PASS -- INSTALLER_DONE=success' } else { 'FAIL -- not success (REGRESSION -- STOP)' }))
W (Wsl 'ls -l /home/clawuser/.config/systemd/user/openclaw-gateway.service 2>&1')
$st = Wsl 'curl -s -o /dev/null -w "%{http_code}" --max-time 8 http://127.0.0.1:8787/status'
$code = ([regex]::Matches("$st", '\b\d{3}\b') | Select-Object -Last 1).Value
W ("2.3 /status http=$code  -> " + $(if ($code -eq '200') { 'PASS' } else { 'FAIL' }))

# =====================================================================
# B4.0 -- the fix confirmation (workspace dir ownership + SOUL protection)
# =====================================================================
Section "B4.0 -- workspace dir ownership (the v1.0.44 fix) + SOUL.md protection"
W (Wsl 'echo "workspace dir : $(stat -c "%U:%G %A" /home/clawuser/.openclaw/workspace 2>/dev/null)"; echo "workspace files: $(ls /home/clawuser/.openclaw/workspace 2>/dev/null | tr "\n" " ")"; echo "SOUL.md        : $(stat -c "%U:%G %A" /home/clawuser/.openclaw/workspace/SOUL.md 2>/dev/null) lsattr=$(lsattr /home/clawuser/.openclaw/workspace/SOUL.md 2>/dev/null | cut -d" " -f1)"' 'root')

# =====================================================================
# TASK 3 -- the CLEAN 4.2 positive control (deliverable 1)
# =====================================================================
Section "TASK 3 -- CLEAN 4.2 positive control (warm first, then measure)"
New-Item -ItemType Directory -Path 'C:\cfv\granted' -Force | Out-Null
Set-Content -LiteralPath 'C:\cfv\granted\project-note.txt' -Value "GRANTED-FILE-$rand this is inside the granted workspace" -Encoding ascii
try {
    . 'C:\Program Files\ClawFactory\resources\clawfactory-grants.ps1'
    $g = Grant-Workspace -Path 'C:\cfv\granted' -Mode rw
    W ("granted C:\cfv\granted -> " + ($g | ConvertTo-Json -Compress -Depth 4))
} catch { W ("Grant-Workspace threw: " + $_.Exception.Message) }

W "--- 3.1 warm-up (throwaway turn so the gateway + spend-meter are hot) ---"
$warm = AgentSay "Reply with the single word: warm." 120
W ("warm-up said: " + (($warm -replace '\s+', ' ').Trim() -replace '^(.{0,200}).*$', '$1'))

W "--- 3.2 POSITIVE CONTROL: agent reads the GRANTED file (must succeed + quote) ---"
$pc = AgentSay "Read the file project-note.txt in your workspace and quote its exact contents."
if ($pc -notmatch "GRANTED-FILE-$rand") {
    W "(4.2 first attempt empty/blocked -- retrying once after 10s)"
    Start-Sleep -Seconds 10
    $pc = AgentSay "Read the file project-note.txt in your workspace and quote its exact contents."
}
W "AGENT SAID (verbatim):"
W $pc
$pcOk = $pc -match "GRANTED-FILE-$rand"
W ("3.2 VERDICT: " + $(if ($pcOk) { 'PASS -- clean positive control: agent read + quoted the granted file' } else { 'FAIL -- STILL blank/blocked after warm-up (not merely cold-start; state below)' }))
if (-not $pcOk) {
    W "3.3 second-blank diagnosis (turn-gate + spend meter):"
    W (Wsl '/usr/local/sbin/clawfactory-turn-gate.sh </dev/null 2>&1 | head -6; echo "gate_rc=$?"')
    W (Wsl 'timeout 30 openclaw gateway usage-cost 2>&1 | head -3')
}

# =====================================================================
# TASK 4 -- chatCompletions BLOCK-MESSAGE (deliverable 2)
#   The proxy shape ClawChat uses: openclaw/main + Bearer + x-openclaw-agent-id.
#   For each block case capture the VERBATIM response, then decide:
#     - message: READABLE block / BLANK-absent / (real reply => security bug)
#     - security: did the turn actually RUN (a real model reply) or was it blocked?
# =====================================================================
Section "TASK 4 -- chatCompletions BLOCK-MESSAGE (cold artifact vs real gap; security must hold)"
$govBak = (Wsl 'cat /etc/clawfactory/governor.json 2>/dev/null' 'root').Trim()

W "--- 4.0 CONTROL: normal turn through the proxy (expect a real reply => proxy + meter are warm) ---"
SetGov '{"daily_cap_usd":999,"monthly_cap_usd":9999,"warn_pct":80}'
$ctl = ChatPost '{"model":"openclaw/main","messages":[{"role":"user","content":"Reply with exactly the single word CONFIRMPROXYOK and nothing else."}],"stream":false}'
W "RAW (verbatim):"; W $ctl
$ctlOk = $ctl -match 'CONFIRMPROXYOK'
W ("4.0 control: " + $(if ($ctlOk) { 'PASS -- proxy relays a real model reply (warm)' } else { 'UNCLEAR -- proxy control did not return the sentinel' }))

W "--- 4.1 cap=0 -> chatCompletions turn (must be BLOCKED; is the message readable or blank?) ---"
SetGov '{"daily_cap_usd":0,"monthly_cap_usd":0,"warn_pct":80}'
$capResp = ChatPost '{"model":"openclaw/main","messages":[{"role":"user","content":"Reply with exactly the single word RANWHENITSHOULDNOT and nothing else."}],"stream":false}'
W "RAW (verbatim):"; W $capResp
$capRan = $capResp -match 'RANWHENITSHOULDNOT'
$capReadable = ($capResp -match 'cap|budget|spend|blocked|meter|clawfactory_gate') -and -not $capRan
W ("4.1 SECURITY: turn ran the model? " + $(if ($capRan) { '!! YES -- SECURITY BUG (spend at cap=0)' } else { 'NO -- blocked (security intact)' }))
W ("4.1 MESSAGE: " + $(if ($capReadable) { 'READABLE block message (cold-artifact RESOLVED)' } elseif ($capRan) { 'n/a (ran)' } else { 'BLANK/absent -- UX gap in the proxy block-rendering' }))

W "--- 4.2 tampered SOUL -> chatCompletions turn (must be BLOCKED; readable or blank?) ---"
SetGov '{"daily_cap_usd":999,"monthly_cap_usd":9999,"warn_pct":80}'
Wsl 'cp -f /home/clawuser/.openclaw/SOUL.md /root/SOUL.cfm; chattr -i /home/clawuser/.openclaw/SOUL.md; printf "\n# CONFIRM TAMPER\n" >> /home/clawuser/.openclaw/SOUL.md' 'root' | Out-Null
$soulResp = ChatPost '{"model":"openclaw/main","messages":[{"role":"user","content":"Reply with exactly the single word RANWITHTAMPEREDSOUL and nothing else."}],"stream":false}'
Wsl 'chattr -i /home/clawuser/.openclaw/SOUL.md 2>/dev/null || true; cp -f /root/SOUL.cfm /home/clawuser/.openclaw/SOUL.md; chown root:root /home/clawuser/.openclaw/SOUL.md; chmod 444 /home/clawuser/.openclaw/SOUL.md; chattr +i /home/clawuser/.openclaw/SOUL.md; rm -f /root/SOUL.cfm' 'root' | Out-Null
W "RAW (verbatim):"; W $soulResp
$soulRan = $soulResp -match 'RANWITHTAMPEREDSOUL'
$soulReadable = ($soulResp -match 'soul|safety rules|tamper|pinned|mismatch|clawfactory_gate') -and -not $soulRan
W ("4.2 SECURITY: turn ran the model? " + $(if ($soulRan) { '!! YES -- SECURITY BUG (ran with tampered SOUL)' } else { 'NO -- blocked (security intact)' }))
W ("4.2 MESSAGE: " + $(if ($soulReadable) { 'READABLE block message' } elseif ($soulRan) { 'n/a (ran)' } else { 'BLANK/absent -- UX gap' }))

# restore the governor to a sane mirror
$restore = if ($govBak) { $govBak } else { '{"daily_cap_usd":999,"monthly_cap_usd":9999,"warn_pct":80}' }
Wsl ("printf %s '" + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($restore)) + "' | base64 -d > /etc/clawfactory/governor.json; chmod 644 /etc/clawfactory/governor.json") 'root' | Out-Null

W "--- 4.3 VERDICT ---"
$security = (-not $capRan) -and (-not $soulRan)
$readable = $capReadable -and $soulReadable
W ("4.3 SECURITY (gating still BLOCKS both cases): " + $(if ($security) { 'PASS -- neither block case ran the model (security intact)' } else { '!! FAIL -- a block case RAN the model (SECURITY BUG)' }))
W ("4.3 BLOCK-MESSAGE: " + $(if ($readable) { 'READABLE now (cold-meter artifact -- resolved when warm; no product change)' } else { 'BLANK/absent even warm => REAL GAP in the proxy block-message rendering (UX; report for follow-up). Contrast: 4.0 control returned a real reply, so the proxy relays fine; only the BLOCK payload is not rendered on the openclaw/main+auth shape.' }))

W "`n===== CONFIRMATION PROBE COMPLETE ====="
