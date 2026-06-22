# Free-tier "try it" — SecureVector engine on OCI Container Instances

The cheapest way to stand up the SecureVector engine on Oracle Cloud: a
serverless Container Instance with a public IP, in a module-managed minimal VCN.

```bash
terraform init
terraform apply -var="compartment_ocid=ocid1.compartment.oc1..xxxx"
terraform output dashboard_url      # http://<public-ip>:8741 — local engine, device-level detection
terraform output -raw runtime_snippet
terraform destroy                   # clean teardown
```

> **Ephemeral storage.** OCI Container Instances can't durably mount File Storage,
> so the audit hash-chain lives on ephemeral storage and resets if the instance
> is recreated. See the module README "Persistence" for the durable-storage
> roadmap (OKE / block-volume VM). Fine for a trial.

> **HTTP + open by default.** Container Instances have no managed TLS — the
> endpoint is `http://<public-ip>:<port>` and open. For anything internet-facing,
> set `ingress_token` (app-layer auth), restrict with `allow_unauthenticated =
> false` / `ingress_cidrs`, and front with an OCI Load Balancer + cert for HTTPS.

See the [module README](../../README.md) for all inputs and the Option 1 vs
Option 2 (fleet + advanced cloud ML) paths.
