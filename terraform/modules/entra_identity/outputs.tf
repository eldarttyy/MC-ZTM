output "group_object_ids" {
  description = "Map of group key -> Entra ID object ID."
  value       = { for k, g in azuread_group.this : k => g.object_id }
}

output "group_display_names" {
  description = "Map of group key -> display name as it appears in Entra ID."
  value       = { for k, g in azuread_group.this : k => g.display_name }
}

output "application_client_id" {
  description = "Client (application) ID of the enterprise app."
  value       = azuread_application.portal.client_id
}

output "service_principal_object_id" {
  description = "Object ID of the enterprise application's service principal."
  value       = azuread_service_principal.portal.object_id
}

output "app_role_ids" {
  description = "Map of app role name -> role ID."
  value       = { for k, u in random_uuid.app_role : k => u.result }
}

output "conditional_access_policy_id" {
  description = "ID of the MFA Conditional Access policy, if created."
  value       = try(azuread_conditional_access_policy.require_mfa_admins[0].id, null)
}
