# Cloud-specific outputs. The runtime/client snippet (output "runtime_snippet")
# lives in the shared runtime.tf. local.base_url is defined in main.tf.

output "dashboard_url" {
  description = "The URL of the SecureVector engine dashboard (http://<public-ip>:<port>; OCI Container Instances have no managed TLS — front with a Load Balancer + cert for HTTPS)."
  value       = local.base_url
}

output "health_url" {
  description = "Health endpoint for probes / uptime checks."
  value       = "${local.base_url}/health"
}

output "public_ip" {
  description = "The container instance's IP (public when allow_unauthenticated, else private)."
  value       = local.public_ip
}

output "container_instance_id" {
  description = "OCID of the deployed container instance."
  value       = oci_container_instances_container_instance.this.id
}

output "availability_domain" {
  description = "Availability domain the instance was placed in."
  value       = local.availability_domain
}

output "persistence_file_system_id" {
  description = "OCID of the File Storage filesystem building block (null when enable_persistence is false). NOTE: not auto-mounted by Container Instances — see README 'Persistence'."
  value       = var.enable_persistence ? oci_file_storage_file_system.data[0].id : null
}

output "persistence_export_path" {
  description = "NFS export path of the File Storage building block (null when persistence off)."
  value       = var.enable_persistence ? oci_file_storage_export.data[0].path : null
}
