# Task 1: the provider route, read from source, no VM

Session 2026-08-18. Dispatch card #257. Input artifact 1.3.4, signed
`ee6a5cd0232d7eb039182fe45e967cf2407e4ccd70f2e06540e06c93b89b5214`, 440,607,456
bytes, Authenticode Valid, verified byte for byte on disk before anything was read.

This is the zero-cost half of the job. It answers questions 1 to 6 of section 3 with
file and line for every claim, and it states plainly which of the four candidates it
kills, which it weakens, and which survives.

**Headline: the source read does NOT close the question, and it eliminates the
leading hypothesis rather than confirming it.** Candidates A, B and D are refuted or
strongly weakened by source plus one free measurement. Candidate C survives without
a named mechanism. The VM run in task 2 is therefore warranted, and its first
measurement is now a single discriminating question rather than a survey.

---

## 1. Every place a provider hostname is seeded or refreshed, tree-wide

Five sites. Four resolve; the fifth replays a persisted file. Counts are per call
site, and each was reached by execution of the grep over the whole tree rather than
by reading the files I expected to matter.

| # | Site | What it resolves | Passes | Applies to | Persists to `allowed-ips.txt` |
| --- | --- | --- | --- | --- | --- |
| 1 | `setup.ps1:1596` (`HOSTS=$hostList`), resolved `setup.ps1:1598-1603` | `$baseHosts` + `$providerHosts` (`setup.ps1:1456-1457`) | **1** | `setup.ps1:1634` nft / `setup.ps1:1673` iptables | **yes**, `setup.ps1:1680` |
| 2 | `setup.ps1:2144` `AUX_HOSTS`, install-time, inside `Step-PreinstallGatewayRuntime` | the 5 hard-coded provider hosts | **1** | `setup.ps1:2148` nft / `setup.ps1:2163-2165` iptables | **nft branch: NO.** iptables branch only, `setup.ps1:2166` |
| 3 | `setup.ps1:2230` `AUX_HOSTS`, inside `/usr/local/sbin/clawfactory-allow-providers.sh` | the same 5 hosts | **1** | `setup.ps1:2236` nft / `setup.ps1:2245-2247` iptables | **nft branch: NO.** iptables branch only, `setup.ps1:2248` |
| 4 | `clawfactory-fw-apply.sh`, `setup.ps1:1735-1740` | nothing; replays `/etc/clawfactory/allowed-ips.txt` after `nft -f` flushes the ruleset | n/a | nft / iptables | reads it |
| 5 | `resources/switch-provider.ps1:170-171`, resolved `:175-179` | its own `BASE_HOSTS` copy + `PROVIDER_HOST` | **1** | `:211-214` | **yes**, `:224` |

Two things fall out of the table that are worth stating on their own.

**Finding 1.1, reported not fixed: on the nftables backend the `AUX_HOSTS`
addresses are never persisted.** Sites 2 and 3 append to `allowed-ips.txt` only in
the `iptables-legacy` branch. On nftables, which is the normal backend, the
`AUX_HOSTS` addresses exist only in the live set. `/etc/nftables.conf` opens with
`flush ruleset` (`setup.ps1:1525`), so any re-apply empties `@allowed_ipv4`, and
site 4 restores it from a file those addresses were never written to. The provider
route then depends entirely on the address also being present via site 1, which is
true only when a provider was selected at install. With `-Provider later`
(`setup.ps1:136-143`, `AllowlistHosts = @()`) the provider route survives no
re-apply at all and waits for the timer.

**Finding 1.2, reported not fixed: `switch-provider.ps1`'s `BASE_HOSTS` is stale
against the 1.3.2 split.** Line 170 still carries all seven toolchain hostnames
(`api.github.com github.com raw.githubusercontent.com codeload.github.com
clawhub.ai api.clawhub.ai registry.npmjs.org`) that `$baseHosts` deliberately gave
up, and line 224 writes them into `allowed-ips.txt`. Running the shipped Start Menu
item "Switch AI Provider" therefore re-seeds the toolchain hosts into
`@allowed_ipv4`, where nothing removes them, and persists that across reboot. That
silently and permanently defeats Guard 3's toggle. It is exactly the hazard the
comment at `clawfactory-toolchain.sh:67-72` warns about, in the third place nobody
looked. It is not the cause of this ship-blocker and is not fixed here.

## 2. Which list each provider host is in, after the 1.3.2 split

Named explicitly, host by host.

**`AUX_HOSTS`, the provider half, `setup.ps1:2144` and `setup.ps1:2230`, identical
strings:**

- `api.anthropic.com`
- `console.anthropic.com`
- `api.openai.com`
- `auth.openai.com`
- `api.x.ai`

**`TOOLCHAIN_HOSTS`, `clawfactory-toolchain.sh:74`:** `clawhub.ai`,
`api.clawhub.ai`, `api.github.com`, `github.com`, `raw.githubusercontent.com`,
`objects.githubusercontent.com`, `codeload.github.com`, `registry.npmjs.org`.
**No provider host appears in it.**

**`$baseHosts`, `setup.ps1:1394-1454`:** `openclaw.ai`, `docs.openclaw.ai`,
`nodejs.org`, `deb.nodesource.com`, `archive.ubuntu.com`, `security.ubuntu.com`,
`ports.ubuntu.com`, `esm.ubuntu.com`, `ppa.launchpad.net`. **No provider host.**

**`$providerHosts`, `setup.ps1:1456`,** is `$ThisProvider.AllowlistHosts`, so for
the provider actually installed: claude gives `api.anthropic.com`
(`setup.ps1:116`), grok `api.x.ai`, openai `api.openai.com`, gemini
`generativelanguage.googleapis.com`, ollama `ollama.com registry.ollama.ai`,
later nothing.

**So candidate B is REFUTED for `api.anthropic.com`.** It is not lost in the split.
It is in the provider list twice over: in `AUX_HOSTS` at both install and refresh,
and in `$providerHosts` whenever `-Provider claude` was passed, which the validation
harness does (`validation/interim-v120-phase1.ps1:164`, `/PROVIDER=claude`, mapped
to the label `claude` at `ClawFactory-Secure-Setup.iss:709`).

**A related asymmetry, found while answering this and reported because it is the
same class of hazard.** `AUX_HOSTS` covers three of the five providers. Gemini's
`generativelanguage.googleapis.com` and Ollama's two hosts are NOT in it, by
deliberate decision for Gemini (`setup.ps1:2204-2213`, the Guard 2 Gmail
front-end residual). A Gemini customer's provider route therefore exists only via
site 1 and site 5, so finding 1.1 does not bite them, and finding 1.1 plus
`-Provider later` does. Neither is the failure under investigation, but a reader
should not infer that `AUX_HOSTS` is a complete provider list, because it is not.

## 3. Does the provider path resolve once or several times, and does it union

**Once, at every one of the four resolving sites, and it does not union.** The
toolchain path resolves three times and unions. Both quoted verbatim.

Provider, `setup.ps1:1598-1603`:

```
for h in $HOSTS; do
    for ip in $(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u); do
        ALLOWED_IPS="$ALLOWED_IPS $ip"
    done
done
```

Provider refresh, `setup.ps1:2234-2238`, the same shape:

```
for h in $AUX_HOSTS; do
    for ip in $(getent ahostsv4 "$h" | awk '{print $1}' | sort -u); do
        nft add element inet clawfactory allowed_ipv4 "{ $ip }" 2>/dev/null || true
    done
done
```

Toolchain, `clawfactory-toolchain.sh:206-214`:

```
GOT=""
p=0
while [ "$p" -lt "$RESOLVE_PASSES" ]; do
    GOT="$GOT $(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}')"
    p=$((p + 1))
done
GOT="$(printf '%s\n' $GOT | sed '/^$/d' | sort -u)"
```

with `RESOLVE_PASSES=3` at `clawfactory-toolchain.sh:95`. The toolchain hosts are
also seeded three times at firewall time, `setup.ps1:1612-1617`, so the install-time
copy matches the resolver.

`clawfactory-read-fetch.sh:117` resolves once, and is out of scope here.

**The asymmetry is real and it is documented in the product's own source.**
`clawfactory-toolchain.sh:84-88`:

> The provider set does not have this problem, but only by accident: it is
> refreshed ADDITIVELY with element timeouts, so it accumulates a pool over hours.

That is the prompt's own account of why a fresh box would differ from an old one,
already written down, which is what makes candidate A attractive. **It is
nevertheless not supported by measurement, see section 7.**

## 4. What hostname the gateway dials, from the shipped configuration

`api.anthropic.com`, and it is a default rather than a written setting.

`Step-ConfigureOpenClaw` writes the auth profile at `setup.ps1:2599` as
`auth.profiles.'anthropic:default'` with `provider = anthropic`
(`setup.ps1:2542`), and the default model as `anthropic/claude-sonnet-4-6`
(`setup.ps1:2581-2582`). **No base-URL override is written anywhere.** The
`Endpoint` field in the provider registry (`setup.ps1:118`,
`https://api.anthropic.com/v1`) is defined for all six providers and referenced by
nothing: a tree-wide grep for `Endpoint` returns six hits, all of them the
definitions at `setup.ps1:102,110,118,126,134,142`, and zero uses. So the dialled
host is whatever OpenClaw's built-in `anthropic` provider defaults to, and the
shipped configuration does not name it.

**That dead field is itself worth a line**, because it reads like the thing that
configures the dial target and is not, so a future reader changing it would change
nothing and believe otherwise.

**Candidate D is answered by forward resolution, which is what the job asked for.**
`api.anthropic.com` was resolved eight times against the local resolver and once
each against `8.8.8.8`, `1.1.1.1` and `9.9.9.9`. Every one of the eleven lookups
returned exactly one address:

```
160.79.104.10
```

That is the address the kernel logged as dropped. Forward resolution and the
reverse resolution in the previous session agree, so the identification is not an
artefact of a reverse lookup. `anthropic.com` is served by Cloudflare nameservers
(`randy.ns.cloudflare.com`, `isla.ns.cloudflare.com`), and the A record for this
name is a single address rather than a rotating pool.

**This is the measurement that hurts candidate A**, and it is stated as a limit
rather than a proof: eleven lookups from ONE network is not the same claim as
"the pool has one member everywhere". The equivalent measurement from inside WSL on
a clean box is measurement 2 of task 2, and it is the one that settles it.

## 5. When the provider set is first populated, against the first moment a turn can
be requested

Install order is `setup.ps1:3504-3552`.

| Position | Step | Effect on `@allowed_ipv4` |
| --- | --- | --- |
| 3528 | `Step-EgressFirewall` | site 1: resolves and seeds, and writes `allowed-ips.txt` |
| 3538 | `Step-PreinstallGatewayRuntime` | site 2 at `setup.ps1:2146`: seeds `AUX_HOSTS` into the live set only. Then `setup.ps1:2283` enables the timer `--now` |
| 3538, later in the same step | gateway installed and started | **first moment a turn can be requested** |
| 3550 | `Step-InstallSend` | `install-send.sh:161` rewrites `/etc/nftables.conf` for the Guard 2 SMTP drop, calls `clawfactory-fw-apply.sh` (which runs `nft -f`, so `flush ruleset`), then `install-send.sh:164` calls `clawfactory-allow-providers.sh` to repopulate. The order is deliberate and the comment at `install-send.sh:158-160` says so |
| 3551 | `Step-InstallReadFetch` | on nftables, touches only `@read_fetch_ipv4` and `@toolchain_ipv4`. `clawfactory-read-fetch.sh:145-152` and `clawfactory-toolchain.sh:246-254` call `fw-apply` **only on the iptables-legacy backend**, so on nftables there is no further ruleset flush |
| 3552 onward | proxy, tasks, smoke | no firewall writes found |

The timer, `setup.ps1:2187-2196`, is `OnBootSec=30s` `OnUnitActiveSec=5h`. It is
enabled with `--now` at `setup.ps1:2283`, **and that enable is `2>/dev/null || true`**,
so a failure to enable it is silent. Because the box has been up far longer than
30s by the time the timer starts, the `OnBootSec` condition is already satisfied and
the service fires immediately, then not again for five hours.

**So on the shipped nftables path the set is populated before the first turn is
possible, twice, and repaired once more at 3550.** The install sequence does not
leave a window that explains the observation. That is why candidate C survives only
as "something failed", with no mechanism identified from source.

## 6. Does the install verify the agent can actually reach its model

**No. There is no provider-reachability check anywhere in the install.**

What exists and what it actually proves:

- **The final gateway gate, `setup.ps1:3586`.** Polls
  `http://127.0.0.1:8787/status` for a 200 and throws if it does not appear within
  120 seconds. That is a loopback call to the gating proxy. It makes no outbound
  request and would pass on a machine with the provider route completely closed.
- **The key wizard's models GET, `ClawFactory-Secure-Setup.iss:378-390`.** A free
  `v1/models` request used to confirm a key authenticates. It runs from **Windows**,
  in Inno's `[Code]`, outside WSL and outside the clawuser-scoped chain, so it
  cannot see this defect even in principle. It is also **skipped entirely on silent
  installs** (`ClawFactory-Secure-Setup.iss:700-703` and the `ShouldSkipPage` note
  at `:735-739`), which is every validation run.
- **`smoke-test.ps1` checks 20 to 26.** These do launch real agent turns, and they
  would catch it. They run from a post-install scheduled task, not as an install
  gate, and their own header (`smoke-test.ps1:11`) records that they need a valid
  provider key, so on a keyless box their failure is expected and carries no signal.

**Contrast with the precedent the job names.** `install-read-fetch.sh:213-217`
refuses to finish the install when the Guard 3 set or its 443-scoped accept is
absent, on the stated grounds that a set nothing enforces is a list rather than a
control. The same principle applied to the provider route would have converted this
ship-blocker into a loud install failure on the first clean box. Recommendation in
section 8.

## 7. Which candidates survive

| Candidate | Verdict from source | Why |
| --- | --- | --- |
| **A**, single-pass resolution against a rotating pool | **Weakened to the point of refutation, pending the on-box repeat** | The provider path does resolve once and does not union, which is the premise. But `api.anthropic.com` returned one address on 11 of 11 lookups across four resolvers. A pool of one cannot be missed by a single lookup. The premise is true and the consequence does not follow |
| **B**, a provider host lost in the `AUX_HOSTS` split | **Refuted** | `api.anthropic.com` is in `AUX_HOSTS` at both install and refresh, and in `$providerHosts` under `/PROVIDER=claude`. It is in no toolchain list. The split did leave a defect, finding 1.2, but in the opposite direction and in a third file |
| **C**, the set was never populated, or the first turn raced it | **SURVIVES, mechanism unidentified** | Every seed site precedes the first possible turn and the sequence contains no post-seed flush that is not repaired. So source says it should be populated. The observation says a packet to that address fell through to the terminal drop. One of those is wrong and only the box can say which |
| **D**, the gateway dials a name that is not in the seed list | **Refuted for the identification, open on one narrow point** | Forward resolution of the seeded name yields exactly the dropped address. The shipped config writes no base URL, so the dialled host is OpenClaw's `anthropic` default, which is not stated in ClawFactory's own configuration. That last part is an inference from an absence and is confirmed on-box by measurement 3 |

**Stated plainly, because the job asked for it: the evidence currently fits more
than one candidate only in the weak sense that A cannot be fully killed without the
in-WSL resolution, and C has no mechanism.** The honest position is that the source
read has removed the tidy answer rather than supplied one.

## 8. Two candidate fixes, reported and not built

Per section 5 of the job, neither is written without reporting first.

**An install-time reachability check. Recommended, regardless of which candidate is
confirmed.** The installer already refuses to finish when Guard 3's set or accept is
missing (`install-read-fetch.sh:213-217`) and when the gateway does not answer on
loopback (`setup.ps1:3586`). The provider route is the one thing whose absence
bricks the product outright, and it is the only one of the three with no gate. The
check must run **as clawuser, inside WSL, after the last firewall write**, because
every existing check fails that test: the Windows-side models GET is on the wrong
side of the chain, and the loopback gate never leaves the box. A TCP connect to the
provider host on 443 as uid 1000 is sufficient and costs no tokens. It converts a
silent brick into a loud install failure, and it is the durable fix whichever
candidate is right, because it fails the install on the symptom rather than on any
one cause.

**A failure-triggered re-resolve.** Assessed as asked, from the code rather than
from expectation. The host list the refresh resolves is `AUX_HOSTS`, a literal
inside `/usr/local/sbin/clawfactory-allow-providers.sh`, which is written by root at
`setup.ps1:2200` and `chmod +x` at `setup.ps1:2281`; the file is root-owned in
`/usr/local/sbin`, and the agent runs as clawuser. So a trigger that re-runs that
script gives the agent **no influence over what gets resolved**: it can at most
cause the same five root-owned names to be looked up again. The trigger itself would
have to be root-owned too, or it becomes a clawuser-writable path into a root
action, which is a different and worse problem. Reported, not built.

## 9. What task 2 must measure, now that this read has narrowed it

The first measurement is no longer a survey. It is one discriminating question:
**is `160.79.104.10` in `@allowed_ipv4` immediately after a clean install, before
any refresh cycle?**

- **If YES**, then every candidate in section 2 of the job is wrong, the set was
  right and the packet was dropped for another reason: a port other than 443, an
  address family other than the one the accept covers, or an instrument that
  attributed the drop wrongly. The probe must therefore log the **destination port
  and protocol**, not only the address.
- **If NO**, the install log names which of the three seed sites did not take, and
  the answer is C with a mechanism.

Everything else in the job's list of six measurements stays, and measurement 2 (the
multi-pass in-WSL resolution) is what converts section 4's eleven-lookup result from
"strongly suggests" to "settled".
