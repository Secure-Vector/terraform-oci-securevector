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

> **Important — cloud ML analysis.** If you turn on **Cloud Mode** (cloud ML threat analysis), the engine sends the **prompt text** to SecureVector's cloud scan service (`scan.securevector.io`, processed in the **US**). That content is **not stored or logged** by the cloud (metadata-only retention), but it **is transmitted to and processed in the US** — so it leaves your region. A setting to keep all prompt analysis local ("EU data residency" mode) is planned for v4.8.0; until it ships, **leave Cloud Mode off for strict EU data residency** (local detection — bundled rules + the on-device model — still runs).

**Persistence caveat:** OCI Container Instances use ephemeral storage and have no managed TLS (see the module README "honest divergences"). The residency guarantee is about *region placement*; production durability still requires addressing the persistence caveat.

If you later enable Cloud Connect to view your governance posture in the SecureVector cloud, only metadata + hashes (never raw text) are forwarded, and only after you explicitly accept the governance terms. Keeping the deployment in an EU region keeps the resident copy of your data in the EU.
