output "resource_group_name" {
  description = "Name of the resource group."
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "vnet_cidr" {
  description = "Address space of the virtual network."
  value       = one(azurerm_virtual_network.this.address_space)
}

output "public_subnet_id" {
  description = "ID of the public subnet."
  value       = azurerm_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet."
  value       = azurerm_subnet.private.id
}

output "workload_identity_client_id" {
  description = "Client ID of the workload user-assigned managed identity."
  value       = azurerm_user_assigned_identity.workload.client_id
}

output "workload_identity_principal_id" {
  description = "Object ID of the workload user-assigned managed identity."
  value       = azurerm_user_assigned_identity.workload.principal_id
}
