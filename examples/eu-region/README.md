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

If you later enable Cloud Connect to view your governance posture in the SecureVector cloud, only metadata + hashes (never raw text) are forwarded, and only after you explicitly accept the governance terms. Keeping the deployment in an EU region keeps the resident copy of your data in the EU.

## Connect your agents to this deployment

`terraform output` prints the endpoint URL. Point your agents at it **from the machine where they run** — no local app required. (Default, with no endpoint set, uses a local app.)

**SDK** (LangChain / LangGraph / CrewAI) — lightweight install, adapter only:

```bash
pip install securevector-sdk-langchain --no-deps     # or -langgraph / -crewai
export SECUREVECTOR_SDK_APP_URL=https://<endpoint>    # from `terraform output`
export SECUREVECTOR_API_KEY=<your key>
```

**Plugin** (Claude Code / Codex / GitHub Copilot CLI / OpenClaw) — install where the agent runs, then point the hooks at the endpoint:

```bash
securevector-app --install-plugin claude-code        # installs the hooks (no app server needs to run)
export SV_BASE_URL=https://<endpoint>                 # the hooks forward here at runtime
```

A single unified `SECUREVECTOR_ENDPOINT` variable and a one-step plugin `--endpoint` flag are planned — see [story #190](https://github.com/Secure-Vector/llm-security-engine/issues/190).
