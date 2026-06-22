###############################################################################
# SecureVector engine on Oracle Cloud Infrastructure (OCI) Container Instances
#
# One `terraform apply` stands up the SecureVector threat-monitor engine in YOUR
# OCI compartment: a serverless Container Instance with a public IP, optionally
# in a module-managed VCN.
#
# PERSISTENCE CAVEAT (read before relying on it): OCI Container Instances only
# support EPHEMERAL volumes (EMPTYDIR / CONFIGFILE) — they CANNOT durably mount
# File Storage the way Cloud Run mounts GCS or Fargate mounts EFS. So the engine
# always gets a writable EMPTYDIR at its data dir, and `enable_persistence`
# (default FALSE here, unlike the other clouds) provisions a File Storage
# filesystem + mount target + export as BUILDING BLOCKS only — Container
# Instances will not auto-mount them. Durable audit-chain persistence on OCI is a
# roadmap item (OKE with a CSI-driven PVC, or a block-volume Compute VM variant).
# See README "Persistence".
###############################################################################

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid != "" ? var.tenancy_ocid : var.compartment_ocid
}

locals {
  availability_domain = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.ads.availability_domains[0].name

  subnet_id = var.create_network ? oci_core_subnet.this[0].id : var.subnet_id

  # Container Instances expose a public IP, not a managed-TLS DNS name (unlike
  # Cloud Run / Container Apps). base_url is therefore http://<public-ip>:<port>.
  # For HTTPS, front it with an OCI Load Balancer + certificate (roadmap).
  public_ip = var.allow_unauthenticated ? data.oci_core_vnic.this[0].public_ip_address : data.oci_core_vnic.this[0].private_ip_address
  base_url  = "http://${local.public_ip}:${var.container_port}"

  # Engine container env. Only vars the app actually reads (verified against
  # securevector-ai-threat-monitor). Host/port are NOT env — CLI args on the
  # launch command. Empty optional values are filtered out.
  #
  #   SECUREVECTOR_INGRESS_TOKEN — INBOUND gate (Authorization: Bearer / X-Api-Key);
  #                             /health stays open. ingress_auth middleware.
  #   SECUREVECTOR_API_KEY    — engine's OUTBOUND cloud key (X-Api-Key via cloud_sync).
  #   SECUREVECTOR_API_URL    — override the SecureVector cloud API base URL.
  #   SECUREVECTOR_ENROLL_TOKEN — svet_* org enroll (entrypoint runs `enroll`).
  container_env = merge(
    var.ingress_token != "" ? { SECUREVECTOR_INGRESS_TOKEN = var.ingress_token } : {},
    var.securevector_api_key != "" ? { SECUREVECTOR_API_KEY = var.securevector_api_key } : {},
    var.securevector_api_url != "" ? { SECUREVECTOR_API_URL = var.securevector_api_url } : {},
    var.cloud_connect_token != "" ? { SECUREVECTOR_ENROLL_TOKEN = var.cloud_connect_token } : {},
    var.extra_env,
  )

  ingress_source_cidrs = var.allow_unauthenticated ? ["0.0.0.0/0"] : var.ingress_cidrs
}

###############################################################################
# Networking — a minimal public VCN (create_network = true) or bring your own
###############################################################################

resource "oci_core_vcn" "this" {
  count = var.create_network ? 1 : 0

  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.name}-vcn"
  dns_label      = "sv"
  freeform_tags  = var.freeform_tags
}

resource "oci_core_internet_gateway" "this" {
  count = var.create_network ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this[0].id
  display_name   = "${var.name}-igw"
  enabled        = true
  freeform_tags  = var.freeform_tags
}

resource "oci_core_route_table" "this" {
  count = var.create_network ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this[0].id
  display_name   = "${var.name}-rt"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.this[0].id
  }
}

resource "oci_core_security_list" "this" {
  count = var.create_network ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this[0].id
  display_name   = "${var.name}-sl"
  freeform_tags  = var.freeform_tags

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # Engine port from the allowed source(s).
  dynamic "ingress_security_rules" {
    for_each = local.ingress_source_cidrs
    content {
      protocol = "6" # TCP
      source   = ingress_security_rules.value
      tcp_options {
        min = var.container_port
        max = var.container_port
      }
    }
  }

  # NFS (mount target) from within the VCN, only when persistence resources exist.
  dynamic "ingress_security_rules" {
    for_each = var.enable_persistence ? [2049, 111] : []
    content {
      protocol = "6" # TCP
      source   = var.vcn_cidr
      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }
}

resource "oci_core_subnet" "this" {
  count = var.create_network ? 1 : 0

  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this[0].id
  cidr_block                 = var.subnet_cidr
  display_name               = "${var.name}-subnet"
  route_table_id             = oci_core_route_table.this[0].id
  security_list_ids          = [oci_core_security_list.this[0].id]
  prohibit_public_ip_on_vnic = false
  dns_label                  = "svsubnet"
  freeform_tags              = var.freeform_tags
}

###############################################################################
# Persistence building blocks (opt-in; NOT auto-mounted — see file header)
###############################################################################

resource "oci_file_storage_file_system" "data" {
  count = var.enable_persistence ? 1 : 0

  availability_domain = local.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "${var.name}-data"
  freeform_tags       = var.freeform_tags
}

resource "oci_file_storage_mount_target" "data" {
  count = var.enable_persistence ? 1 : 0

  availability_domain = local.availability_domain
  compartment_id      = var.compartment_ocid
  subnet_id           = local.subnet_id
  display_name        = "${var.name}-mt"
  freeform_tags       = var.freeform_tags
}

resource "oci_file_storage_export" "data" {
  count = var.enable_persistence ? 1 : 0

  export_set_id  = oci_file_storage_mount_target.data[0].export_set_id
  file_system_id = oci_file_storage_file_system.data[0].id
  path           = "/securevector"
}

###############################################################################
# Container Instance — the engine
###############################################################################

resource "oci_container_instances_container_instance" "this" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = var.name
  shape               = var.shape
  freeform_tags       = var.freeform_tags

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  vnics {
    subnet_id             = local.subnet_id
    is_public_ip_assigned = var.allow_unauthenticated
    display_name          = "${var.name}-vnic"
  }

  containers {
    display_name = var.name
    image_url    = var.image

    # The app binds host/port from CLI args (--host/--port), NOT env. Empty
    # command (default) defers to the image ENTRYPOINT, which per the #182 image
    # contract binds 0.0.0.0:container_port and enrolls from
    # SECUREVECTOR_ENROLL_TOKEN (when set) before serving.
    command = length(var.container_command) > 0 ? var.container_command : null

    environment_variables = local.container_env

    # Writable data dir. EMPTYDIR is ephemeral to the instance lifecycle — see
    # the persistence caveat in the file header / README.
    volume_mounts {
      mount_path  = var.persistence_mount_path
      volume_name = "data"
    }
  }

  volumes {
    name          = "data"
    volume_type   = "EMPTYDIR"
    backing_store = "EPHEMERAL_STORAGE"
  }
}

# Resolve the instance's primary VNIC to read its public/private IP for base_url.
data "oci_core_vnic" "this" {
  count = 1

  vnic_id = oci_container_instances_container_instance.this.vnics[0].vnic_id
}
