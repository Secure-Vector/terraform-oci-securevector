# Changelog

All notable changes to this module are documented here. This project adheres to
[Semantic Versioning](https://semver.org/). The Terraform Registry publishes a
release per `vX.Y.Z` git tag.

## [Unreleased]

### Added
- Initial OCI module: deploys the SecureVector engine to the user's own OCI
  compartment on a **serverless Container Instance** with a public IP, and a
  clean `terraform destroy`. Creates a minimal public VCN (VCN + internet
  gateway + route table + security list + public subnet) by default, or deploys
  into an existing subnet via `create_network = false` + `subnet_id`.
- Engine **outbound** cloud credentials: `securevector_api_key` (`svpk_`/legacy →
  `SECUREVECTOR_API_KEY`, personal cloud mode) and `cloud_connect_token`
  (`svet_*` → `SECUREVECTOR_ENROLL_TOKEN`, fleet + policy sync); plus the inbound
  app-layer gate `ingress_token` → `SECUREVECTOR_INGRESS_TOKEN`.
- Network-layer gate via `allow_unauthenticated` (public vs private IP) +
  `ingress_cidrs` (security-list source allowlist).
- `securevector_runtime` variable that emits a copy-paste SDK/plugin wiring
  snippet as a Terraform output, pre-pointed at the new endpoint. Covers all
  SecureVector clients (SDKs + plugins).
- Shared `runtime.tf` — **byte-identical** with the other
  `terraform-<cloud>-securevector` repos so every cloud exposes the same
  clients/snippets/contract.
- Flex shape support (`shape` / `ocpus` / `memory_in_gbs`), incl. Arm
  (`CI.Standard.A1.Flex`); default 1 OCPU / 4 GB for Guardian-ML headroom.

### Terraform best-practices / DevOps notes (honest divergences)
- **No managed TLS.** Container Instances expose a public IP, not a managed-TLS
  DNS name (unlike Cloud Run / Container Apps), so `base_url` is
  `http://<public-ip>:<port>`. HTTPS needs an OCI Load Balancer + certificate in
  front (roadmap).
- **No durable volume mounts.** Container Instances only support EPHEMERAL
  volumes (EMPTYDIR / CONFIGFILE) — they cannot durably mount File Storage the
  way Cloud Run mounts GCS or Fargate mounts EFS. Consequently:
  - the engine's data dir is always an ephemeral EMPTYDIR;
  - `enable_persistence` **defaults to FALSE** here (unlike the other clouds) and,
    when enabled, provisions a File Storage filesystem + mount target + export as
    BUILDING BLOCKS only — it is NOT auto-mounted. Durable audit-chain
    persistence on OCI is a roadmap item (OKE with a CSI PVC, or a block-volume
    Compute VM variant). This divergence is documented in the README.
- Region + auth come from the OCI provider config (the OCI idiom), not module
  variables; `tenancy_ocid` is used only for AD lookup.
- Input validation on `name`, `container_port` (1–65535).

### Notes
- Hard prerequisites (story #182): a published engine container image whose
  entrypoint binds `0.0.0.0:$PORT`, stores data at the mount path, and enrolls
  from `SECUREVECTOR_ENROLL_TOKEN`; plus engine-side inbound auth. Both are
  implemented in securevector-ai-threat-monitor pending the first ghcr publish.
  The Terraform is correct against the real app interface and will deploy a
  working engine once that image ships.
