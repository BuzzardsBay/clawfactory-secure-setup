# Phase 1 Bake Log — 2026-05-06T13:04:28

STORAGE ACCOUNT NAME: clawfactoryvalc467
IMAGE NAME: clawfactory-win11-baseline (NOT CREATED — stopped at Task 3)

---

## RESULT: FAIL

**Failed at:** Task 3 — Provision bake-vm

---

## Task 1 — Preflight PASS (13:04:28)

| Check | Result |
|---|---|
| Subscription | 43010359-5b4c-4d16-af11-10f6544b2978 ✓ |
| Resource group | clawfactory-validation / westus2 ✓ |
| Creds file | admin_user + admin_password present ✓ |
| vCPU headroom | standardDSv5Family: 0/4 used → 4 vCPU free ✓ |

## Task 2 — Storage Account PASS (13:06:00)

- Storage account **clawfactoryvalc467** created (Standard_LRS, StorageV2, westus2)
- Container **installers** created (private, auth-mode login)

## Task 3 — Provision bake-vm FAIL (13:06:39–13:07:19)

**Error code:** `BadRequest`

**Error message:**
> The value 'Standard' is not available for property 'securityType' until the feature
> `Microsoft.Compute/UseStandardSecurityType` OR
> `Microsoft.Compute/StandardSecurityTypeAsFirstClassEnum`
> is registered on subscription 43010359-5b4c-4d16-af11-10f6544b2978.
> Please register the feature and retry.
> https://aka.ms/TrustedLaunch-FAQ

**Command attempted:**
```
az vm create \
  --resource-group clawfactory-validation \
  --name bake-vm \
  --image MicrosoftWindowsDesktop:Windows-11:win11-24h2-pro:latest \
  --size Standard_D2s_v5 \
  --admin-username clawadmin \
  --security-type Standard \
  --public-ip-sku Standard \
  --nsg-rule RDP \
  --license-type Windows_Client
```

**Why stopped:** Per spec HARD RULES — "On any failure: write what failed to log, stop, do not attempt fixes."
`--security-type Standard` is also a HARD RULE — TrustedLaunch cannot be substituted.

---

## Required fix before retry

Register the Azure feature flag on subscription 43010359-5b4c-4d16-af11-10f6544b2978:

```bash
az feature register \
  --namespace Microsoft.Compute \
  --name UseStandardSecurityType

# Then wait for state == Registered (usually 1–5 min):
az feature show \
  --namespace Microsoft.Compute \
  --name UseStandardSecurityType \
  --query "properties.state" -o tsv

# Finally propagate:
az provider register --namespace Microsoft.Compute
```

Once `UseStandardSecurityType` state == `Registered`, re-run this session from Task 3.

---

## Tasks 4–10: NOT STARTED

Total elapsed: ~3 min (stopped at Task 3 failure)
