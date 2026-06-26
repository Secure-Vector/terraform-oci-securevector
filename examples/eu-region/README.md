# EU-region example (OCI)

Deploys the SecureVector engine into an **EU OCI region** for data residency. Identical to [`../free-tier`](../free-tier) except the provider region is set to `eu-frankfurt-1`.

```bash
terraform init
terraform apply -var="compartment_ocid=ocid1.compartment.oc1..xxxx"
terraform output dashboard_url
terraform destroy
```

Change the provider `region` in `main.tf` to another EU region (e.g. `eu-amsterdam-1`, `eu-zurich-1`) if you prefer. If you set an explicit `availability_domain`, make sure it belongs to the EU region you chose.

## Data residency

Resources this module creates are compartment-scoped and placed in the provider's region (set above) — the Container Instance, its public VCN, and networking. The engine processes and stores agent activity, threats, tool-audit, and governance data **only in your own OCI tenancy/compartment and region**. This module does not replicate it to another region.

> **EU data residency is enforced in this example.** It sets `extra_env = { SV_DATA_RESIDENCY = "eu" }`, which the **v4.8+ engine** honors by keeping **all prompt analysis local**: even with Cloud Mode on, prompts are **not** sent to SecureVector's cloud scan service (`scan.securevector.io`, US) — the local-only analysis toggle is locked on and cannot be disabled. No prompt text leaves your region. (The module pulls the `:latest` engine image; ensure it is **v4.8 or newer** for this enforcement. On older images the flag is a harmless no-op — leave Cloud Mode off for strict residency until you're on v4.8+.)

**Persistence caveat:** OCI Container Instances use ephemeral storage and have no managed TLS (see the module README "honest divergences"). The residency guarantee is about *region placement*; production durability still requires addressing the persistence caveat.

If you later enable Cloud Connect to view your governance posture in the SecureVector cloud, only metadata + hashes (never raw text) are forwarded, and only after you explicitly accept the governance terms. Keeping the deployment in an EU region keeps the resident copy of your data in the EU. Forwarded metadata can include identifiers (device, agent, and session IDs) that may be personal data under GDPR and is processed by SecureVector in the US — treat its use as your DPO's assessment.


## Endpoint exposure (who can reach your engine)

By default this example opens the load balancer to the public internet (`allow_unauthenticated = true`). For data residency **and** the least friction, keep the endpoint **private**:

- Set `allow_unauthenticated = false` and restrict network access to your own ranges (`ingress_cidrs` on AWS / Azure / OCI; Cloud Run ingress controls on GCP). Agents running **inside your own VPC / network reach the engine with no app-layer auth** — the SDK or plugin needs nothing beyond the endpoint URL.

If you must expose the endpoint **publicly**, gate it at the app layer with `ingress_token` (the engine then requires `Authorization: Bearer <token>` or `X-Api-Key: <token>` on every request; `/health` stays open for the load-balancer probe). Recommended: use a **free SecureVector cloud account API key** or an **SVET enrollment token** as that value — it gates inbound access only and **forwards no agent data to SecureVector**; your prompts and outputs still never leave your deployment.

> `securevector_api_key` is a *separate* credential — the engine's **outbound** key for Cloud Connect (talking to the SecureVector cloud), not the inbound gate. Don't reuse one for the other.
