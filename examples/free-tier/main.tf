###############################################################################
# Free-tier "try it" example — SecureVector engine on OCI Container Instances
#
# Cheapest possible SecureVector engine on OCI:
#   - a serverless Container Instance (1 OCPU / 4 GB) with a public IP
#   - a module-managed minimal public VCN (no networking to set up)
#   - ephemeral storage (see the persistence caveat in the module README)
#   - emits a wired LangChain snippet on apply
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
# instance principals). Set region to taste.
provider "oci" {
  region = "us-phoenix-1"
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
