# Hostname write census

Every site in this tree where a hostname is written into an allowlist, a persisted file,
or an nft set. Built 2026-08-19 for card #258, after card #245 fixed two of three seeding
sites and card #257 found a fourth that nobody had enumerated.

This file exists because the previous enumeration lived in a code comment, the comment said
THREE, and the true answer was FOUR. A census that is not written down and not compared is
the same failure with a longer fuse.

## How this was built, and what it cannot see

A regex over every tracked file, calibrated BEFORE use against a canary carrying the shapes
feared missing rather than the shapes already known: hyphenated labels, uncommon TLDs, a
bare host on its own line, a host inside a JSON array, an Inno `#define`, a host inside a
bash for-list, and a host embedded in a URL with a path. The pattern found all seven.

Its one honest limit: a hostname ASSEMBLED at runtime from parts is invisible to any text
search, and the canary proved it (only the literal tail was found). That class is covered
instead by tracing every variable that reaches a write sink, which is how the table below
is organised. Sinks were enumerated first, sources traced back to them second.

Sinks searched: `nft add element`, `nft flush set`, iptables `-A OUTPUT` / `-I OUTPUT`,
writes to `/etc/clawfactory/*.txt`, and writes to `egress-policy.json`.

## The four sets, and which ones can take a host back

| Set | Rebuild discipline | Can a host be revoked? |
| --- | --- | --- |
| `allowed_ipv4` | additive, elements carry a timeout, refreshed every 5h | **No.** Anything written here can never be taken away. |
| `toolchain_ipv4` | flushed and rebuilt from root-owned policy on every run | Yes |
| `read_fetch_ipv4` | flushed and rebuilt from root-owned policy on every run | Yes |
| `send_actions` (policy file, not an nft set) | overwritten by the broker | Yes, and it is broker-enforced rather than firewall-enforced |

## The census

| # | Site | Host list | Class | Writes into | Revocable |
| --- | --- | --- | --- | --- | --- |
| 1 | `setup.ps1:100-140` | `$ProviderConfig.*.AllowlistHosts` (1-2 per provider) | provider | `allowed_ipv4`, `allowed-ips.txt` | No, by design |
| 2 | `setup.ps1:1394-1455` | `$baseHosts` (9: openclaw.ai, docs.openclaw.ai, nodejs.org, deb.nodesource.com, 5 Ubuntu apt) | other / infra | `allowed_ipv4`, `allowed-ips.txt` | No |
| 3 | `setup.ps1:1479-1487` | `$toolchainHosts` (8) | toolchain | `toolchain_ipv4`, `toolchain-ips.txt` | Yes |
| 4 | `setup.ps1:2144` | `AUX_HOSTS` (5, install-time) | provider | `allowed_ipv4`; persisted on iptables only | No |
| 5 | `setup.ps1:2230` | `AUX_HOSTS` (5, 5-hourly refresh) | provider | `allowed_ipv4`; persisted on iptables only | No |
| 6 | `setup.ps1:1738-1767` | none: reads the persisted IP files | derived | all three nft sets at boot | n/a |
| 7 | `switch-provider.ps1:163` | `PROVIDER_HOST` (1) | provider | `allowed_ipv4`, `allowed-ips.txt` | No, by design |
| 8 | `switch-provider.ps1:170` | `BASE_HOSTS` (16 = 9 infra + **7 toolchain**) | **MIXED** | `allowed_ipv4`, `allowed-ips.txt` | No |
| 9 | `clawfactory-toolchain.sh:74` | `TOOLCHAIN_HOSTS` (8) | toolchain | `toolchain_ipv4`, `toolchain-ips.txt` | Yes |
| 10 | `clawfactory-read-fetch.sh:67-96` | read from `egress-policy.json` `read_fetch.allow` | read-fetch | `read_fetch_ipv4`, `read-fetch-ips.txt` | Yes |
| 11 | `clawfactory-fetchctl.js:368` | one host per `add`, from Studio | read-fetch | `egress-policy.json` | Yes |
| 12 | `send-lib.js:283` (via `clawfactory-sendctl.js:144-152`) | the user's SMTP host | send | `egress-policy.json` `send_actions` | Yes, broker-enforced |
| 13 | `resources/egress-policy.json` | shipped default | read-fetch, send | ships EMPTY for both | n/a |

## Findings

**Row 8 is the defect.** `switch-provider.ps1` seeds 7 toolchain hostnames into the set
nothing can revoke, and persists them, through the shipped Start Menu item "Switch AI
Provider". After one click the toolchain toggle is permanently defeated and the panel still
reports it as off. Those hosts are there because the script's own comment tells it to stay
in sync with `setup.ps1`'s `$baseHosts`, which is where they lived before card #245 moved
them. Nothing in the switch path needs GitHub or npm: `openclaw config set`,
`openclaw models set` and the gateway restart are all local, and the only remote fetch, the
ollama branch, runs as root and runs before the firewall step.

**Exactly four sites write into `allowed_ipv4`: rows 1, 2, 4/5 and 7/8.** There is no fifth.

**The comment at `setup.ps1:1414` said THREE and named them.** That is the audit trail of a
security product, it was wrong, and a reader who trusted it would have stopped looking one
site early. Corrected in the same commit as this file.

## The rule this census exists to enforce

Provider hosts go in `allowed_ipv4`. Everything the user is told they can switch off goes in
a set that is flushed and rebuilt from root-owned policy. **Anything written to
`allowed_ipv4` can never be taken away**, so a host belongs there only when the product is
willing to say it is permanent.

Any new site added to this table is a change to the security model and needs the same
scrutiny as a change to the chain itself.
