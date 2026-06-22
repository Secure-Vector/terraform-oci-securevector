# terraform-oci-securevector

[![License](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)
[![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.5-7B42BC)](https://www.terraform.io/)
[![OCI Container Instances](https://img.shields.io/badge/Oracle%20Cloud-Container%20Instances-F80000)](https://www.oracle.com/cloud/cloud-native/container-instances/)

> **One `terraform apply` → a live SecureVector engine in your own OCI
> compartment, in ~5 minutes.** The turnkey *server* companion to the
> SecureVector Guard SDKs ([langchain](https://pypi.org/project/securevector-sdk-langchain/) ·
> [langgraph](https://pypi.org/project/securevector-sdk-langgraph/) ·
> [crewai](https://pypi.org/project/securevector-sdk-crewai/)). The SDKs secure
> one agent on one laptop; this stands up the shared engine your whole team's
> agents, CI runners, and prod services point at.

This is **bring-your-own-cloud (BYOC) self-hosting**: the engine and all scanned
data live in *your* compartment, in *your* tenancy — nothing leaves.

> ✅ **Status: live.** The engine image is published and **public** —
> `ghcr.io/secure-vector/securevector-ai-threat-monitor` (tags `latest` and
> `4.7.1`), multi-arch (amd64/arm64). `var.image` pulls it with no extra setup.
>
> One caveat: the current image runs **device-level (Option 1) detection**;
> engine-side **inbound auth** (`ingress_token` → `SECUREVECTOR_INGRESS_TOKEN`)
> is not yet enforced and ships in a later release. Until then, gate
> internet-facing deployments at the **network layer**
> (`allow_unauthenticated = false`, `ingress_cidrs`, or cloud IAM) rather than
> relying on `ingress_token` alone.

---

## Why Container Instances (and two honest caveats)

OCI **Container Instances** are the serverless-container primitive on Oracle
Cloud — no node pool to manage. This module gives you one with a public IP in a
minimal managed VCN. Two differences from the Cloud Run / Container Apps modules
you should know up front:

- **No managed TLS.** The endpoint is `http://<public-ip>:<port>`. For HTTPS,
  front it with an OCI Load Balancer + certificate (roadmap).
- **No durable volume mounts.** Container Instances support only *ephemeral*
  volumes, so the audit hash-chain is not durable across instance recreation —
  see [Persistence](#persistence). For a durable engine today, OKE (Kubernetes
  with a CSI PVC) or a block-volume Compute VM is the path; that variant is on
  the roadmap.

```
terraform apply -var="compartment_ocid=ocid1.compartment.oc1..xxxx"
#
# Outputs:
#   dashboard_url   = "http://203.0.113.10:8741"
#   runtime_snippet = "point any SecureVector SDK/plugin at the URL above"
```

## Quick start

### Prerequisites
- An OCI tenancy + compartment, and the OCI provider authenticated
  (`~/.oci/config`, env, or instance principals) with a region set.
- Terraform `>= 1.5` (or OpenTofu).
- Permission to create Container Instances, VCN/networking, and (optionally)
  File Storage in the compartment.

There are two ways to run it. **Option 1** is the standalone self-host engine;
**Option 2** adds the SecureVector cloud on top.

| | **Option 1 — Device-level engine** (default) | **Option 2 — + Fleet & advanced cloud ML** |
|---|---|---|
| What you get | Your own engine doing **local, device-level** detection — local rules + the **Guardian ML** model — running entirely in your compartment. | Everything in Option 1, **plus** the SecureVector cloud: org **fleet** management, **policy sync**, and the cloud's **advanced ML / enhanced `/analyze`**. |
| Needs | Just an OCI compartment. No SecureVector account. | **Requires a SecureVector account (sign up).** An `svet_*` enrollment token (and/or `svpk_*` key); cloud tiers/billing apply. |
| Set | nothing extra | `cloud_connect_token` (svet\_) and/or `securevector_api_key` (svpk\_) |

#### Option 1 — Device-level engine (default, one command)

A compartment OCID: a Container Instance with a public IP, local detection, and
a clean `terraform destroy`. This is the [`examples/free-tier`](examples/free-tier) example.

```bash
terraform apply -var="compartment_ocid=ocid1.compartment.oc1..xxxx"
terraform output dashboard_url      # http://<public-ip>:8741 — local engine, device-level detection
terraform destroy                   # clean teardown
```

> Keyless = the endpoint is open HTTP. Fine for a quick trial or a
> network-restricted box. For anything internet-facing, gate it with
> `ingress_token` (app-layer auth) and/or `allow_unauthenticated = false` +
> `ingress_cidrs` (network layer).

#### Option 2 — Add fleet management + advanced cloud ML

> **Requires a SecureVector account — sign up first.** Option 2 connects the
> engine to the SecureVector cloud, so you must create an account and obtain a
> token: an `svet_*` enrollment token (→ fleet + policy sync) and/or an `svpk_*`
> key (→ personal cloud mode). Sign up at [app.securevector.io/signup](https://app.securevector.io/signup).
> Cloud tiers / billing apply. **Option 1 needs none of this.**

Same engine, now bridged to the SecureVector cloud: set `cloud_connect_token`
(an `svet_*` org token → **fleet view + policy sync**) and/or
`securevector_api_key` (a personal `svpk_*`/legacy key → personal cloud mode +
**enhanced ML `/analyze`**). Those are the engine's *outbound* cloud credentials.
Add `ingress_token` to authenticate inbound clients. See
[Tokens](#tokens--which-credential-enables-what).

```hcl
module "securevector" {
  source  = "Secure-Vector/securevector/oci"
  version = "~> 0.1"   # once published to the Terraform Registry

  compartment_ocid     = "ocid1.compartment.oc1..xxxx"
  name                 = "securevector"
  securevector_runtime = "langchain"            # emits a wired client snippet
  ingress_token        = var.ingress_token      # app-layer inbound auth
  cloud_connect_token  = var.svet_token         # → fleet + policy sync (advanced)
  # securevector_api_key = var.svpk_key         # → personal cloud mode + enhanced ML
  # allow_unauthenticated = false               # private IP only
}

output "dashboard_url"   { value = module.securevector.dashboard_url }
output "runtime_snippet" { value = module.securevector.runtime_snippet }
```

Until the Registry listing is live, point `source` at the repo:
`source = "github.com/Secure-Vector/terraform-oci-securevector"`.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `compartment_ocid` | string | — (required) | Compartment to deploy into. |
| `tenancy_ocid` | string | `""` | Tenancy OCID for AD lookup (defaults to compartment). |
| `availability_domain` | string | `""` | AD name (default = first AD). |
| `name` | string | `securevector` | Resource base name. |
| `create_network` | bool | `true` | Create a minimal public VCN, or BYO `subnet_id`. |
| `subnet_id` | string | `""` | Existing public subnet (when `create_network = false`). |
| `vcn_cidr` / `subnet_cidr` | string | `10.0.0.0/16` / `10.0.1.0/24` | Managed-VCN CIDRs. |
| `image` | string | `ghcr.io/secure-vector/securevector-ai-threat-monitor:latest` | Engine container image. Pin a tag for prod. |
| `container_port` | number | `8741` | Port the engine listens on. |
| `shape` | string | `CI.Standard.E4.Flex` | Container Instance shape (Arm: `CI.Standard.A1.Flex`). |
| `ocpus` / `memory_in_gbs` | number | `1` / `4` | Flex shape sizing. |
| `container_command` | list(string) | `[]` | Override the image entrypoint. App takes host/port as CLI args. |
| `allow_unauthenticated` | bool | `true` | Public IP + open `container_port`. `false` = private IP / restrict to `ingress_cidrs`. |
| `ingress_cidrs` | list(string) | `[]` | Allowed source CIDRs when `allow_unauthenticated = false`. |
| `ingress_token` | string (sensitive) | `""` | App-layer inbound gate → `SECUREVECTOR_INGRESS_TOKEN`. |
| `securevector_api_key` | string (sensitive) | `""` | **Outbound** cloud key (`svpk_`/legacy) → `SECUREVECTOR_API_KEY`. Not an inbound gate. |
| `securevector_api_url` | string | `""` | Override the SecureVector cloud API base URL. |
| `cloud_connect_token` | string (sensitive) | `""` | **Outbound** `svet_*` org enroll token → `SECUREVECTOR_ENROLL_TOKEN` (fleet + policy sync). |
| `securevector_runtime` | string | `none` | Client to emit a wiring snippet for. SDKs/plugins or `none`. |
| `enable_persistence` | bool | `false` | Provision File Storage **building blocks** (see Persistence). Not auto-mounted. |
| `persistence_mount_path` | string | `…/securevector/threat-monitor` | Where the (ephemeral) data volume mounts; must equal the app data dir in the image. |
| `freeform_tags` | map(string) | `{}` | OCI freeform tags. |
| `extra_env` | map(string) | `{}` | Extra container env vars. |

## Outputs

| Name | Description |
|---|---|
| `dashboard_url` | Engine dashboard URL (`http://<public-ip>:<port>`). |
| `health_url` | Health endpoint for probes. |
| `public_ip` | Instance IP (public when `allow_unauthenticated`). |
| `container_instance_id` / `availability_domain` | Deployed identity. |
| `persistence_file_system_id` / `persistence_export_path` | File Storage building blocks (null if persistence off). |
| `runtime_snippet` | Copy-paste snippet wiring the chosen SDK/plugin to this engine. |

## Clients — point any SDK or plugin at this engine

`securevector_runtime` makes the module emit a ready-to-paste wiring snippet
(`terraform output -raw runtime_snippet`). All SecureVector clients are
supported. **The base-URL env var (how a client targets the engine) differs by
family** and is the part that works today:

| Client | `securevector_runtime` value | Base-URL env var (targets the engine) |
|---|---|---|
| LangChain / LangGraph / CrewAI SDK | `langchain` / `langgraph` / `crewai` | `SECUREVECTOR_SDK_APP_URL` (+ `SECUREVECTOR_SDK_MODE`) |
| Claude Code plugin | `claude-code` | `SV_BASE_URL` (hooks) · `SECUREVECTOR_URL` (statusline) |
| Cursor plugin | `cursor` | `SV_BASE_URL` · `SECUREVECTOR_URL` |
| Codex plugin | `codex` | `SV_BASE_URL` · `SECUREVECTOR_URL` |
| GitHub Copilot CLI plugin | `copilot-cli` | `SV_BASE_URL` · `SECUREVECTOR_URL` |
| OpenClaw guard | `openclaw` | `SECUREVECTOR_URL` |

When the module sets `ingress_token`, the engine **requires** a credential
(`Authorization: Bearer` / `X-Api-Key`). A client forwards it via
`SECUREVECTOR_API_KEY` — **OpenClaw (and any header-capable client like curl)
works today**; SDK / JS-hook client-side forwarding is rolling out (#182), so for
those leave `ingress_token` unset or restrict at the network layer. (Plugin list
mirrors `securevector-ai-threat-monitor/src/securevector/plugins/`.)

## Tokens — which credential enables what

Two distinct, **outbound** engine credentials (engine → SecureVector cloud), plus
the inbound story:

| Capability | Direction | Credential | Notes |
|---|---|---|---|
| **Remote analyze** (client → engine) | inbound | `ingress_token` → `SECUREVECTOR_INGRESS_TOKEN` | Engine requires `Authorization: Bearer`/`X-Api-Key` when set (fail-open when unset). Header-capable clients (OpenClaw, curl) work today; SDK/JS-hook forwarding rolling out (#182). Or restrict via `ingress_cidrs`. |
| **Personal cloud mode** (enhanced detection) | outbound | `securevector_api_key` (`svpk_`/legacy) → `SECUREVECTOR_API_KEY` | Engine presents it to the cloud as `X-Api-Key` (`cloud_sync.py`). No policy sync. |
| **Forward to fleet** (org visibility) | outbound | `cloud_connect_token` (`svet_*`) → `SECUREVECTOR_ENROLL_TOKEN` | Org enrollment. Needs the image entrypoint to run `securevector-app enroll`. |
| **Sync policies to local** (signed bundles) | outbound→in | `cloud_connect_token` (`svet_*` **only**) | `svpk_`/legacy/none ⇒ Policy Sync OFF — no partial mode (`device_admin.py`). |

> For production, source `securevector_api_key` / `cloud_connect_token` from OCI
> Vault rather than tfvars (roadmap; see wiki open questions).

## Persistence

**Important OCI limitation.** Container Instances support only *ephemeral*
volumes (EMPTYDIR / CONFIGFILE); they cannot durably mount File Storage the way
Cloud Run mounts GCS or Fargate mounts EFS. So:

- The engine's data dir (`$HOME/.local/share/securevector/threat-monitor`) is
  always an ephemeral EMPTYDIR — the tamper-evident audit hash-chain **does not
  survive instance recreation**.
- `enable_persistence = true` (default **false**) provisions a File Storage
  filesystem + mount target + export as **building blocks only**, surfaced via
  the `persistence_*` outputs. It is **not** auto-mounted into the container; use
  it if you bake an NFS mount into a custom image, or as the storage for a future
  durable setup.
- For a durable engine today, run it on **OKE** (Kubernetes, with a File Storage
  CSI PVC) or a **block-volume Compute VM**. A durable OCI variant is on the
  roadmap.

The `persistence_mount_path` must still equal the app's data dir in the published
image (the app has no data-dir env override).

## Cloud Connect (optional)

Set `cloud_connect_token` (an `svet_*` org enrollment token) to enroll this
self-hosted node into the SecureVector managed fleet view and receive signed
policy bundles — the OSS-self-host → paid Pro/Enterprise on-ramp. It is passed
as `SECUREVECTOR_ENROLL_TOKEN`; the published image's entrypoint must run
`securevector-app enroll` (then serve) for it to take effect. Leave empty to stay
fully self-hosted with no outbound enrollment.

## Teardown

```bash
terraform destroy
```

Removes the container instance, the managed VCN (when created), and any File
Storage building blocks. No leftover billable resources.

## Related

- **Client SDKs:** [`securevector-sdk-langchain`](https://github.com/Secure-Vector/securevector-sdk-langchain) · [`-langgraph`](https://github.com/Secure-Vector/securevector-sdk-langgraph) · [`-crewai`](https://github.com/Secure-Vector/securevector-sdk-crewai)
- **Other clouds:** `terraform-google-securevector` · `terraform-aws-securevector` · `terraform-azurerm-securevector` — each ships the **identical** [`runtime.tf`](runtime.tf) (same supported clients, same env-var contract, same auth caveat). That file is the single source of truth for the client list and is kept byte-identical across all four cloud repos.
- **Engine source / container:** [`securevector-ai-threat-monitor`](https://github.com/Secure-Vector/securevector-ai-threat-monitor)

## License

[Apache-2.0](LICENSE). See [NOTICE](NOTICE) for trademark attributions.
