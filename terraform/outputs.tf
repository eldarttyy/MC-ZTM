output "landing_zones" {
  description = "Network identifiers for every deployed cloud, keyed by provider."
  value = {
    aws = var.enable_aws ? {
      vpc_id         = module.aws_network[0].vpc_id
      cidr           = module.aws_network[0].vpc_cidr
      public_subnet  = module.aws_network[0].public_subnet_id
      private_subnet = module.aws_network[0].private_subnet_id
      region         = var.aws_region
    } : null

    azure = var.enable_azure ? {
      vnet_id        = module.azure_network[0].vnet_id
      cidr           = module.azure_network[0].vnet_cidr
      public_subnet  = module.azure_network[0].public_subnet_id
      private_subnet = module.azure_network[0].private_subnet_id
      region         = var.azure_location
    } : null

    gcp = var.enable_gcp ? {
      network_id     = module.gcp_network[0].network_id
      cidr           = module.gcp_network[0].vpc_cidr
      public_subnet  = module.gcp_network[0].public_subnet_id
      private_subnet = module.gcp_network[0].private_subnet_id
      region         = var.gcp_region
    } : null
  }
}

output "workload_identities" {
  description = "Per-cloud workload identity principals. No static keys anywhere."
  value = {
    aws_role_arn                  = try(module.aws_network[0].workload_role_arn, null)
    azure_managed_identity_client = try(module.azure_network[0].workload_identity_client_id, null)
    gcp_service_account           = try(module.gcp_network[0].workload_service_account_email, null)
  }
}

output "entra_groups" {
  description = "Entra ID security groups backing multi-cloud RBAC."
  value       = try(module.entra_identity[0].group_object_ids, {})
}

output "entra_application_client_id" {
  description = "Client ID of the MC-ZTM enterprise application."
  value       = try(module.entra_identity[0].application_client_id, null)
}

output "entra_app_role_ids" {
  description = "App role IDs exposed by the enterprise application."
  value       = try(module.entra_identity[0].app_role_ids, {})
}
