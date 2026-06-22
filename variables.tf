###############################################################################
# Required — identity / placement
#
# NOTE: the OCI region + auth come from the OCI provider configuration
# (provider "oci" { region = ... }), not module variables.
###############################################################################

variable "compartment_ocid" {
  description = "OCID of the compartment to deploy the SecureVector engine into. The container instance, network, and storage all live in *your* compartment — data stays in your tenancy."
  type        = string
}

variable "tenancy_ocid" {
  description = "Tenancy OCID, used only to list availability domains. Empty = use compartment_ocid (works when it can list ADs; set the tenancy OCID if AD lookup fails)."
  type        = string
  default     = ""
}

variable "availability_domain" {
  description = "Availability domain name to place resources in (e.g. \"Uocm:PHX-AD-1\"). Empty = the first AD in the tenancy/compartment."
  type        = string
  default     = ""
}

###############################################################################
# Naming
###############################################################################

variable "name" {
  description = "Base name for the container instance and derived resources. Lowercase, alphanumeric + hyphens."
  type        = string
  default     = "securevector"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name)) && length(var.name) <= 49
    error_message = "name must be lowercase, start with a letter, contain only letters/digits/hyphens, and be <= 49 chars."
  }
}

variable "freeform_tags" {
  description = "OCI freeform tags applied to created resources."
  type        = map(string)
  default     = {}
}

###############################################################################
# Networking — a module-managed public VCN, or bring your own subnet
###############################################################################

variable "create_network" {
  description = "Create a minimal public VCN (VCN + internet gateway + route table + security list + public subnet). Set false to deploy into an existing subnet (provide subnet_id)."
  type        = bool
  default     = true
}

variable "subnet_id" {
  description = "OCID of an existing PUBLIC subnet to deploy into (used when create_network = false). Must allow public IPs and permit ingress on container_port."
  type        = string
  default     = ""
}

variable "vcn_cidr" {
  description = "CIDR for the module-managed VCN (when create_network = true). Also the source range allowed for NFS to the File Storage mount target."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR for the module-managed public subnet (when create_network = true)."
  type        = string
  default     = "10.0.1.0/24"
}

###############################################################################
# Container image
###############################################################################

variable "image" {
  description = "Container image for the SecureVector engine. Defaults to the public ghcr.io image published from securevector-ai-threat-monitor. Pin to a version tag for production."
  type        = string
  default     = "ghcr.io/secure-vector/securevector-ai-threat-monitor:latest"
}

variable "container_port" {
  description = "Port the engine listens on inside the container. The public IP serves on this port. The image/command must bind this port on 0.0.0.0."
  type        = number
  default     = 8741

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "container_command" {
  description = "Override the container entrypoint. Empty (default) defers to the image ENTRYPOINT. The app takes host/port as CLI args (NOT env), so a working override looks like [\"securevector-app\", \"--web\", \"--host\", \"0.0.0.0\", \"--port\", \"8741\"]. (Enrollment from SECUREVECTOR_ENROLL_TOKEN must be handled by the image entrypoint, not this command.)"
  type        = list(string)
  default     = []
}

###############################################################################
# Shape & resources
###############################################################################

variable "shape" {
  description = "Container Instance shape. Flex shapes (e.g. CI.Standard.E4.Flex, CI.Standard.A1.Flex for Arm) let you set ocpus/memory."
  type        = string
  default     = "CI.Standard.E4.Flex"
}

variable "ocpus" {
  description = "Number of OCPUs for the container instance (Flex shape)."
  type        = number
  default     = 1
}

variable "memory_in_gbs" {
  description = "Memory in GB for the container instance (Flex shape). Default 4 gives the Guardian ML model headroom."
  type        = number
  default     = 4
}

###############################################################################
# Access & auth
#
# Two independent layers:
#   - ingress_token  -> SECUREVECTOR_INGRESS_TOKEN: APP-LAYER inbound gate. When
#     set, the engine requires the credential on every request (Authorization:
#     Bearer or X-Api-Key); /health stays open. Validated by the ingress_auth
#     middleware in securevector-ai-threat-monitor (pending release).
#   - allow_unauthenticated / ingress_cidrs -> public IP + security list:
#     NETWORK layer (public vs private IP; which CIDRs may reach container_port).
# securevector_api_key below is the engine's OUTBOUND cloud key, NOT an inbound
# gate — don't confuse the two.
###############################################################################

variable "allow_unauthenticated" {
  description = "Assign a PUBLIC IP and open container_port to the internet (or to ingress_cidrs). Set FALSE for a private-IP-only instance (reachable from within the VCN / via bastion)."
  type        = bool
  default     = true
}

variable "ingress_cidrs" {
  description = "CIDR blocks allowed to reach container_port when allow_unauthenticated = false. Ignored when allow_unauthenticated = true (which opens 0.0.0.0/0). Only applies to the module-managed security list (create_network = true)."
  type        = list(string)
  default     = []
}

variable "ingress_token" {
  description = "App-layer inbound credential -> SECUREVECTOR_INGRESS_TOKEN. When set, the engine requires it on every request (Authorization: Bearer <token> or X-Api-Key: <token>); /health stays open. Header-capable clients (OpenClaw, curl) can pass it today; SDK/JS-hook client-side forwarding is rolling out (#182). Empty = no app-layer gate."
  type        = string
  default     = ""
  sensitive   = true
}

variable "securevector_api_key" {
  description = "OUTBOUND cloud credential: a personal API key (svpk_* / legacy) the engine presents to the SecureVector cloud (sent as X-Api-Key by cloud_sync) for personal cloud mode / enhanced detection. NOT an inbound gate. Empty = no cloud key."
  type        = string
  default     = ""
  sensitive   = true
}

variable "securevector_api_url" {
  description = "Optional override for the SecureVector cloud API base URL (SECUREVECTOR_API_URL). Empty = the app's built-in default."
  type        = string
  default     = ""
}

###############################################################################
# Cloud Connect bridge (optional) — turns this self-hosted node into a member
# of the SecureVector managed fleet (the OSS-self-host -> paid Pro/Enterprise
# on-ramp). Leave empty to stay fully self-hosted.
###############################################################################

variable "cloud_connect_token" {
  description = "Optional svet_* org ENROLLMENT token (passed as SECUREVECTOR_ENROLL_TOKEN). Enrolls the node into the org FLEET view AND receives signed policy bundles (Policy Sync ON). NOTE: only the svet_* enroll path enables policy sync; a personal key (svpk_*) goes in securevector_api_key instead. Requires the image entrypoint to run `securevector-app enroll` before serving (see README / #182). Empty = pure self-host."
  type        = string
  default     = ""
  sensitive   = true
}

# NOTE: variable "securevector_runtime" lives in the shared runtime.tf (kept
# identical across all terraform-<cloud>-securevector repos).

###############################################################################
# Persistence — OCI CAVEAT: Container Instances cannot durably mount File
# Storage; these are opt-in building blocks only (default OFF). See README.
###############################################################################

variable "enable_persistence" {
  description = "Provision a File Storage filesystem + mount target + export as building blocks. DEFAULT FALSE: unlike Cloud Run/Fargate/Container Apps, OCI Container Instances cannot auto-mount durable storage, so the engine's data dir is an ephemeral EMPTYDIR regardless. Enable only if you intend to NFS-mount the export yourself (custom image) or are wiring a durable setup; see README 'Persistence'."
  type        = bool
  default     = false
}

variable "persistence_mount_path" {
  description = "Path the (ephemeral EMPTYDIR) data volume mounts at inside the container. The app has NO data-dir env override — it stores its SQLite DB / audit chain at $HOME/.local/share/securevector/threat-monitor — so this MUST match that path in the published image. Default assumes HOME=/home/securevector."
  type        = string
  default     = "/home/securevector/.local/share/securevector/threat-monitor"
}

###############################################################################
# Operational
###############################################################################

variable "extra_env" {
  description = "Additional environment variables to pass to the engine container (advanced / forward-compat with future server-mode flags)."
  type        = map(string)
  default     = {}
}
