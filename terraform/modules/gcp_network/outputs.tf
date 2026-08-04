output "network_id" {
  description = "ID of the VPC network."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "Name of the VPC network."
  value       = google_compute_network.this.name
}

output "vpc_cidr" {
  description = "Aggregate CIDR covering the VPC subnets."
  value       = var.vpc_cidr
}

output "public_subnet_id" {
  description = "Self link of the public subnet."
  value       = google_compute_subnetwork.public.id
}

output "private_subnet_id" {
  description = "Self link of the private subnet."
  value       = google_compute_subnetwork.private.id
}

output "workload_service_account_email" {
  description = "Email of the workload service account."
  value       = google_service_account.workload.email
}
