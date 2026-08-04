variable "group_prefix" {
  description = "Optional prefix for group display names, e.g. \"MCZTM-\"."
  type        = string
  default     = ""
}

variable "application_display_name" {
  description = "Display name of the enterprise application."
  type        = string
  default     = "MC-ZTM Multi-Cloud Portal"
}

variable "group_members" {
  description = <<-EOT
    Map of group key -> list of user principal names to enrol. Valid keys are
    cloud_admins, audit_team and copilot_early_access. Every UPN must already
    exist in the tenant; this module does not create users.
  EOT
  type        = map(list(string))
  default     = {}

  validation {
    condition = alltrue([
      for k in keys(var.group_members) :
      contains(["cloud_admins", "audit_team", "copilot_early_access"], k)
    ])
    error_message = "group_members keys must be cloud_admins, audit_team or copilot_early_access."
  }
}

variable "enable_conditional_access" {
  description = <<-EOT
    Create the Conditional Access policy. Requires Entra ID P1/P2 (included in
    the M365 Developer tenant) and Conditional Access Administrator rights on
    the service principal running Terraform.
  EOT
  type        = bool
  default     = false
}

variable "conditional_access_state" {
  description = "State of the CA policy: report-only until you have verified impact."
  type        = string
  default     = "enabledForReportingButNotEnforced"

  validation {
    condition = contains(
      ["enabled", "disabled", "enabledForReportingButNotEnforced"],
      var.conditional_access_state
    )
    error_message = "Must be enabled, disabled or enabledForReportingButNotEnforced."
  }
}

variable "break_glass_user_object_ids" {
  description = <<-EOT
    Object IDs of emergency-access accounts excluded from the MFA policy. Leaving
    this empty while enforcing the policy is how tenants get locked out.
  EOT
  type        = list(string)
  default     = []
}
