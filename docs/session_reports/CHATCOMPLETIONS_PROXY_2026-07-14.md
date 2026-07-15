# chatCompletions gating proxy — Blocker 1 CLOSED (2026-07-14)

**Job:** `CC_CLAWFACTORY_CHATCOMPLETIONS_PROXY_v1` — close Blocker 1 from
`SECFIX_CLOSE_DOORS_2026-07-14.md` §5: ClawChat, the shipped desktop app, drove
every turn through `POST 127.0.0.1:8787/v1/chat/completions`, which the shim never
saw — so those turns had **neither the spend cap nor the SOUL check**.
**Standard:** assume the model is hostile.

**Outcome: Blocker 1 is CLOSED, including the direct-to-gateway bypass.** A
ClawChat-path turn now runs the same SOUL + spend gate the shim runs; a block
comes back as a normal assistant message; a normal turn still works; `/status`
and the cost meter (WebSocket) still pass through; and the agent's UID **cannot**
reach the real gateway to skip the proxy. Suite Tier 6: **5 PASS, 0 FAIL**.

---

## 1. The wire contract (Task 1) — captured, not guessed

**Where the real gateway now listens: `127.0.0.1:8788` (and `[::1]:8788`)** —
private loopback. The ClawFactory proxy owns `127.0.0.1:8787` (and `[::1]:8787`),
the address ClawChat, the CLI, the cost meter and Studio already use.

**How the port was moved (VERIFIED, and it is not what the docs imply).**
OpenClaw's precedence is `--port` > `OPENCLAW_GATEWAY_PORT` > `gateway.port`. The
gateway's own unit hardcodes the flag:
```
ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 8787
```
so a drop-in that only set `OPENCLAW_GATEWAY_PORT=8788` was **silently ignored**
(first attempt: the gateway stayed on 8787; the auto-rollback fired). The working
mechanism is a systemd `--user` drop-in that **clears and replaces** ExecStart,
derived from the live unit rather than hardcoded:
```
[Service]
ExecStart=
ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 8788
Environment=OPENCLAW_GATEWAY_PORT=8788
```
**`gateway.port` in openclaw.json stays 8787 on purpose:** that is what *clients*
resolve, so the CLI/cost meter dial the proxy and get passed through. Only the
server moves.

**Request (ClawChat's exact shape).** From the shipped binary's byte image:
`http://127.0.0.1:8787` · `/v1/chat/completions` · `Authorization: Bearer <token>`
· `x-openclaw-agent-id: main` · `Content-Type: application/json` · body
`{model, messages:[{role,content}], stream}`. The model must be `openclaw` or
`openclaw/<agentId>` — the gateway rejects anything else:
```
{"error":{"message":"Invalid `model`. Use `openclaw` or `openclaw/<agentId>`.","type":"invalid_request_error"}}
```
Auth: no token → **401**.

**Response, non-stream (`stream:false`)** → `200 application/json; charset=utf-8`:
```json
{"id":"chatcmpl_<uuid>","object":"chat.completion","created":<epoch>,"model":"openclaw/main",
 "choices":[{"index":0,"message":{"role":"assistant","content":"WIRE1"},"finish_reason":"stop"}],
 "usage":{"prompt_tokens":3,"completion_tokens":6,"total_tokens":22185}}
```
**Response, stream (`stream:true`)** → `200 text/event-stream; charset=utf-8`,
`Transfer-Encoding: chunked`:
```
data: {…"object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant"}}]}

data: {…"choices":[{"index":0,"delta":{"content":"WIRE2"},"finish_reason":null}]}

data: {…"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```
**Does ClawChat stream? YES (INFERRED from the binary, strongly).** It carries
`choices`, `delta`, `chat-token`, `chat-done`, `Stream error: ` — i.e. it parses
incremental `delta` chunks and emits per-token events. So the proxy **preserves
SSE verbatim** on the allowed path and **speaks SSE on the blocked path**. It also
handles `stream:false` identically, so it is correct either way. (ClawChat itself
was never run — driving a GUI on the operator's desktop is out of bounds; the
contract was reproduced with curl on ClawChat's exact URL/headers.)

---

## 2. The block response, and why ClawChat renders it cleanly

A refusal is **not** an HTTP error. ClawChat's binary contains
`"HTTP error: "` / `"Gateway returned {}: {}"` — any non-2xx renders as a broken
error string. So the proxy returns **HTTP 200** carrying a well-formed
chat-completions payload whose *content* is the human-readable refusal:

- `stream:false` → `chat.completion` with
  `choices[0].message.content = "<refusal>"`, `finish_reason:"stop"`, plus a
  `clawfactory_gate:{blocked:true,state:"…"}` marker for machine callers.
- `stream:true` → the gateway's exact SSE shape: role delta → **content delta
  carrying the refusal** → `finish_reason:"stop"` → `data: [DONE]`. That is
  precisely the sequence ClawChat's `chat-token` / `chat-done` path consumes, so
  the refusal appears as an ordinary assistant message.

Refusal text is the gate's own wording, e.g. *"spend cap reached (today $9.03 /
cap $0; this month $36.10 / cap $0). New turns are blocked until spend falls below
the cap or you raise it."*

**Spend accounting:** an allowed turn is forwarded to the real gateway, which runs
it and records usage natively — so `gateway usage-cost` accounts it exactly as it
does a CLI turn. The proxy adds no accounting of its own.

---

## 3. The direct-to-gateway bypass — **CLOSED** (not a residual)

The proxy runs **as root**, deliberately. That is the whole trick: a different UID
from the agent is what makes a filesystem/network rule able to admit the proxy and
deny the agent — the exact separation Door 2 lacks (there, agent and gateway share
`clawuser`, so nothing can tell them apart).

nft rules added to the `output` chain, **before** the blanket `oifname "lo" accept`
and after `meta skuid != clawuser return` (which exempts root):
```
ip daddr 127.0.0.1 tcp dport 8788 drop
ip6 daddr ::1     tcp dport 8788 drop
```
Both families — the gateway binds `127.0.0.1:8788` **and** `[::1]:8788`; an IPv4-only
rule would have left `::1` wide open.

VERIFIED consumer-side: clawuser → `8788` v4 **000**, v6 **000**; clawuser →
`8787` (proxy) **200**; root (proxy) → `8788` **200**; the CLI's WebSocket cost
meter still works through the proxy.

**Fail-closed by construction:** the real gateway no longer listens on 8787, so if
the proxy dies nothing answers there — ClawChat cannot silently fall through to an
ungated gateway. Losing the proxy blocks chat; it does not reopen the door.

---

## 4. Verbatim evidence

**T6.1 — cap=0, ClawChat's path → blocked as a readable assistant message [PASS]**
```
assistant content: spend cap reached (today $9.025977 / cap $0; this month $36.104741 / cap $0).
                   New turns are blocked until spend falls below the cap or you raise it.
(http=200, object=chat.completion, no "error" key)
```
**T6.2 — tampered SOUL, ClawChat's path → blocked [PASS]**
```
state=soul_mismatch | the factory safety rules no longer match the value pinned at install
time -- they may have been tampered with. No turn will run until they are restored.
```
**T6.3 — CONTROL: a normal turn still works through the proxy [PASS]**
```
{"id":"chatcmpl_75d398fc…","object":"chat.completion",…,"content":"SUITEPROXYOK"…}
```
**T6.4 — pass-through intact [PASS]**
```
status=200   usagecost={ "updated…        (HTTP route + WebSocket control plane)
```
**T6.5 — the agent cannot reach the real gateway directly [PASS]**
```
v4_8788=000   v6_8788=000   proxy_8787=200
```
**Streaming, live through the proxy (blocked + allowed):**
```
BLOCKED stream: HTTP/1.1 200 OK; Content-Type: text/event-stream; chunks=4; [DONE]=1
                content = "spend cap reached (today $8.94 / cap $0 …"
ALLOWED stream: content-type text/event-stream; chunks=4; [DONE]=1; content "STREAMOK"
ALLOWED non-stream: "content":"LIVEPROXYOK"
```
**Re-entrancy (the deadlock that had to be designed around):**
```
blocked cap=0 request completed in  real 0m1.934s   (no deadlock)
```
**The rest of the stack still works after the port move:**
```
CLI agent turn through the shim -> "SHIMSTILLOK";  shim still blocks at cap=0 -> rc=4
/status through proxy 200; proxy active+enabled; gateway active on 8788
factory SOUL hash==pin YES; injected SOUL hash==pin YES; both root:root 444 chattr +i
```

---

## 5. SURPRISES / BLOCKED

**SURPRISES**
1. **The CLI does not speak HTTP — it speaks WebSocket.** `openclaw gateway
   usage-cost` dials `ws://127.0.0.1:<port>`. My first proxy handled HTTP only, so
   the moment the gateway moved, the **spend meter broke** — which fails the gate
   closed and blocks *every* turn. Caught immediately by the verification step and
   fixed with an `upgrade` relay. A proxy in front of this gateway that only
   proxies HTTP is silently catastrophic: it takes out the meter that the entire
   gate depends on.
2. **`--port` in the unit beat the documented env var.** The docs' precedence
   (`--port` > env > config) is real, and OpenClaw's own unit hardcodes
   `--port 8787` — so the "set OPENCLAW_GATEWAY_PORT" approach the design assumed
   is a no-op. The drop-in has to clear and replace ExecStart.
3. **The gateway binds both loopback families.** An IPv4-only nft block would have
   left `[::1]:8788` reachable — the bypass would have looked closed and not been.
4. **The proxy running as root is what closed the bypass.** Door 2 is unclosable
   because agent and gateway share a UID; here we *chose* the proxy's UID, so the
   separation exists. Same problem, different answer, purely because we own the
   process.

**BLOCKED**
- **Clean-install validation** of `Step-InstallChatProxy` (and the Docker removal,
  the injected-SOUL ordering, Tier 2, T1.3b) — Azure. The live box proves the
  mechanism; a fresh install must prove the ordering.
- **ClawChat was not itself driven** (GUI on the operator's desktop is out of
  bounds). The contract was reproduced with curl on its exact URL/headers/body,
  and the streaming shape matches what its binary parses. A human clicking the
  desktop icon is the last mile.

---

## 6. Release-readiness ledger

**CLOSED:** DNS exfil (reduced, labelled) · SOUL integrity unenforced · gate
coverage for CLI/Studio · SOUL delivery · the false Docker claim · Docker itself ·
**Blocker 1: ClawChat's turns are now gated, and the direct gateway bypass is shut.**

**OPEN — ranked. The new #1:**
1. **Door 2 — the full-path bypass.** `node /usr/lib/node_modules/openclaw/openclaw.mjs
   agent …` still runs an **ungated** turn: proven under cap=0 (the shim refuses,
   the full-path call runs). Structural — the agent and the gateway share the
   `clawuser` UID, so no permission can admit one and deny the other. *This is now
   the top blocker for any hostile-model claim.* **Fix:** give the agent a
   different principal — a real container (the Docker (B) design already
   recommended to the Fable review) or a separate UID. Note the proxy just
   demonstrated the principle: the moment a component has its own UID, the
   separation becomes enforceable.
   *Customer impact is narrower than it looks:* the paying user's own path
   (ClawChat) is gated. Door 2 is a hostile/compromised **agent** burning budget or
   running under a tampered SOUL — not the customer's normal usage.
2. **"Four agents" is fiction** — only `main` is registered; orchestrator/scout/
   builder/publisher are files, not invokable agents, while README/docs imply four.
3. **GO-gating is model-dependent** — a prompt rule, not a control. Needs a real
   tool-call interceptor to be a guarantee.
4. **`automount=true` drift** — the headline isolation claim is unproven on a
   correct install. Azure.
5. **DNS exfil reduced, not eliminated** — the permitted resolver still forwards.
6. **Spend is turn-granular** — an in-flight turn can overshoot.
7. **Fresh-install validation owed** (proxy, Docker removal, injected-SOUL
   ordering, Tier 2, T1.3b) — Azure.
8. **The broad dead-code/claims audit** — still owed; items 2 and 3 are what it
   will find more of.

---

## 7. END-OF-SESSION GATE

### Task accounting
| Item | Status |
|---|---|
| Task 1 — wire contract + where the gateway listens | **DONE** (captured verbatim; port move mechanism corrected) |
| Task 2 — build the proxy | **DONE** (gate reused, SSE preserved, pass-through, WS relay, fail-closed) |
| Task 2 — agent cannot reach the real gateway | **DONE — closed** (root proxy + nft, both families) |
| Task 3 — suite checks (5) | **DONE** — Tier 6: 5 PASS, 0 FAIL |
| setup.ps1 / uninstall.ps1 wiring | **DONE** (`Step-InstallChatProxy`; uninstall stops the proxy + restores the port) |
| Clean-install validation | **BLOCKED** (Azure) |

### Resource ledger
- **Real gateway:** `127.0.0.1:8788` + `[::1]:8788` (systemd `--user` drop-in
  `clawfactory-real-port.conf`, ExecStart override). **Proxy:** `127.0.0.1:8787` +
  `[::1]:8787`, `clawfactory-proxy.service`, active **and enabled** (survives reboot).
- **ClawChat's path proven:** same URL/port/auth; blocked → readable message;
  allowed → real reply. **Pass-through proven:** `/status` 200, cost meter (WS) OK.
- **SOULs:** both `root:root` 444 + `chattr +i`; factory and injected **hash==pin YES**.
- **Gateway healthy at exit:** `8787/status` → **200** through the proxy; gateway
  and proxy both `active`. WSL was never `--shutdown`, so the keepalive/`ClawFactory
  WSL Host` task was not disturbed.
- **Mounts:** `/workspaces` count 0. **Mirror:** restored to real caps `{5,50}`.
- **Scratch removed:** `/etc/nftables.conf.pre8788`, `/root/*.bak`, `/tmp/cf_p.json`,
  `/tmp/proxy.log`, `/tmp/snap.txt`. Working scripts live only in the session
  scratchpad (never committed).

### Delta security sweep
- **Nothing weakened to pass.** The one FAIL encountered was the gateway refusing
  to move via the env var — the auto-rollback restored 8787 (200) and I changed the
  *mechanism*, not the test. Tests that need cap=0 or a tampered SOUL restore both.
- **Egress not widened** — the only firewall change is two new **DROP** rules
  (clawuser → the private gateway port, v4 + v6). The DNS restriction and the 443
  allowlist are untouched.
- **Filesystem visibility not widened** — no grants/mounts added; SOULs unchanged
  and still immutable.
- **Fails closed** — the real gateway no longer listens on 8787; no proxy means no
  chat, not ungated chat. The gate itself still fails safe (unreadable meter ⇒ block).
- **No key/token material in any output.** The gateway token is read into a shell
  variable inside WSL and referenced by name only; it is never echoed, logged, or
  written to any report. ClawChat's `Bearer` is quoted as a header *name*.

### Delta bug review
Blocker 1 is closed with consumer evidence (§4). The WebSocket gap and the
`--port` precedence trap were found, fixed, and documented rather than worked
around. The new #1 (Door 2) and every other open item are ranked in §6 — nothing
dropped.
