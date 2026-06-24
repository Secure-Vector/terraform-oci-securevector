###############################################################################
# EU-region example — SecureVector engine on OCI Container Instances, in the EU
#
# Same shape as ../free-tier, but pinned to an EU region for data residency.
# The OCI region comes from the provider; resources are compartment-scoped and
# created in the provider's region, so setting an EU region keeps all
# governance/runtime data inside the EU. Nothing in this module replicates data
# to another region.
#
# Data residency: the engine processes and stores agent/governance data only in
# the OCI tenancy/compartment and region you deploy into. SecureVector never
# receives it. See the module README for the residency posture.
#
# Default region here is eu-frankfurt-1; eu-amsterdam-1 / eu-zurich-1 also work
# — just change the provider `region` below.
#
# PERSISTENCE CAVEAT: OCI Container Instances use ephemeral storage and have no
# managed TLS (see the module README "honest divergences"). The residency
# guarantee is about region placement; durability still requires the persistence
# caveat to be addressed for production.
#
# Usage:
#   terraform init
#   terraform apply -var="compartment_ocid=ocid1.compartment.oc1..xxxx"
#   terraform output dashboard_url      # http://<public-ip>:8741
#   terraform output -raw runtime_snippet
#   terraform destroy   # clean teardown
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0, < 8.0"
    }
  }
}

variable "compartment_ocid" {
  type = string
}

variable "securevector_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

# Auth + region come from the OCI provider config (~/.oci/config, env, or
# instance principals). Pinned to an EU region for data residency.
provider "oci" {
  region = "eu-frankfurt-1"
}

module "securevector" {
  source = "../../"

  compartment_ocid     = var.compartment_ocid
  name                 = "securevector"
  securevector_runtime = "langchain"

  securevector_api_key = var.securevector_api_key
}

output "dashboard_url" {
  value = module.securevector.dashboard_url
}

output "runtime_snippet" {
  value = module.securevector.runtime_snippet
}
