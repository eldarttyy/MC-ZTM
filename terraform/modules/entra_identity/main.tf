/**
 * Microsoft Entra ID — the single source of truth for identity across all three
 * clouds.
 *
 * What this module builds:
 *   - Three security groups (Cloud-Admins, Audit-Team, Copilot-Early-Access).
 *     Cloud-Admins is role-assignable so directory roles can target the group
 *     rather than named individuals.
 *   - An enterprise application exposing app roles, with each group assigned to
 *     exactly one role. This is the RBAC binding federated clouds consume.
 *   - An optional Conditional Access policy requiring MFA for privileged access,
 *     shipped in report-only mode by default so nobody locks themselves out.
 */

data "azuread_client_config" "current" {}

locals {
  groups = {
    cloud_admins = {
      display_name    = "Cloud-Admins"
      description     = "Privileged operators of the AWS, Azure and GCP landing zones"
      app_role        = "CloudAdmin"
      role_assignable = true
    }
    audit_team = {
      display_name    = "Audit-Team"
      description     = "Read-only compliance and security review across the estate"
      app_role        = "Auditor"
      role_assignable = false
    }
    copilot_early_access = {
      display_name    = "Copilot-Early-Access"
      description     = "Pilot cohort licensed for M365 Copilot once DLP controls pass"
      app_role        = "CopilotPilot"
      role_assignable = false
    }
  }

  app_roles = {
    CloudAdmin   = "Full administrative control of multi-cloud infrastructure"
    Auditor      = "Read-only access to configuration and audit evidence"
    CopilotPilot = "Access to M365 Copilot pilot surfaces and telemetry"
  }

  # UPN -> group key, flattened so a user can appear in several groups.
  memberships = merge([
    for group_key, upns in var.group_members : {
      for upn in upns : "${group_key}:${upn}" => {
        group_key = group_key
        upn       = upn
      }
    }
  ]...)

  member_upns = toset(flatten(values(var.group_members)))
}

resource "random_uuid" "app_role" {
  for_each = local.app_roles
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------

resource "azuread_group" "this" {
  for_each = local.groups

  display_name            = "${var.group_prefix}${each.value.display_name}"
  description             = each.value.description
  security_enabled        = true
  mail_enabled            = false
  assignable_to_role      = each.value.role_assignable
  prevent_duplicate_names = true

  owners = [data.azuread_client_config.current.object_id]

  lifecycle {
    # Membership is managed by azuread_group_member below (and, in production,
    # by dynamic rules or Entra ID Governance), not by inline member lists.
    ignore_changes = [members]
  }
}

data "azuread_user" "members" {
  for_each = local.member_upns

  user_principal_name = each.value
}

resource "azuread_group_member" "this" {
  for_each = local.memberships

  group_object_id  = azuread_group.this[each.value.group_key].object_id
  member_object_id = data.azuread_user.members[each.value.upn].object_id
}

# ---------------------------------------------------------------------------
# Enterprise application + app-role RBAC bindings
# ---------------------------------------------------------------------------

resource "azuread_application" "portal" {
  display_name     = var.application_display_name
  description      = "Federated access surface for the MC-ZTM multi-cloud estate"
  owners           = [data.azuread_client_config.current.object_id]
  sign_in_audience = "AzureADMyOrg"

  dynamic "app_role" {
    for_each = local.app_roles

    content {
      id                   = random_uuid.app_role[app_role.key].result
      display_name         = app_role.key
      description          = app_role.value
      value                = app_role.key
      allowed_member_types = ["User"]
      enabled              = true
    }
  }

  # Least privilege: the app itself reads its own directory profile, nothing more.
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read (delegated)
      type = "Scope"
    }
  }

  web {
    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = false
    }
  }
}

resource "azuread_service_principal" "portal" {
  client_id                    = azuread_application.portal.client_id
  owners                       = [data.azuread_client_config.current.object_id]
  app_role_assignment_required = true

  feature_tags {
    enterprise = true
  }
}

resource "azuread_app_role_assignment" "group_to_role" {
  for_each = local.groups

  app_role_id         = random_uuid.app_role[each.value.app_role].result
  principal_object_id = azuread_group.this[each.key].object_id
  resource_object_id  = azuread_service_principal.portal.object_id
}

# ---------------------------------------------------------------------------
# Conditional Access — MFA for privileged operators
# ---------------------------------------------------------------------------

resource "azuread_conditional_access_policy" "require_mfa_admins" {
  count = var.enable_conditional_access ? 1 : 0

  display_name = "MC-ZTM :: Require MFA for Cloud-Admins"
  state        = var.conditional_access_state

  conditions {
    client_app_types = ["all"]

    applications {
      included_applications = ["All"]
    }

    users {
      included_groups = [azuread_group.this["cloud_admins"].object_id]
      excluded_users  = var.break_glass_user_object_ids
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["mfa"]
  }

  lifecycle {
    precondition {
      condition = (
        var.conditional_access_state != "enabled" ||
        length(var.break_glass_user_object_ids) > 0
      )
      error_message = "Enforcing this policy without a break-glass exclusion risks locking every admin out of the tenant. Set break_glass_user_object_ids."
    }
  }
}
