# ---------------------------------------------------------------------------
# Naming and tagging
# ---------------------------------------------------------------------------

variable "project_name" {
  description = "Short project slug used in every resource name."
  type        = string
  default     = "mcztm"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.project_name))
    error_message = "project_name must be 2-16 lowercase alphanumeric/hyphen characters starting with a letter."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test or prod."
  }
}

variable "additional_tags" {
  description = "Extra tags merged into the standard tag set."
  type        = map(string)
  default     = {}
}

variable "admin_cidrs" {
  description = <<-EOT
    Source CIDRs allowed break-glass HTTPS access in all three clouds. Keep this
    tight — a single office range or VPN egress IP. 0.0.0.0/0 is rejected.
  EOT
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Cloud toggles
# ---------------------------------------------------------------------------

variable "enable_aws" {
  description = "Deploy the AWS landing zone."
  type        = bool
  default     = true
}

variable "enable_azure" {
  description = "Deploy the Azure landing zone."
  type        = bool
  default     = true
}

variable "enable_gcp" {
  description = "Deploy the GCP landing zone."
  type        = bool
  default     = true
}

variable "enable_entra" {
  description = "Deploy Entra ID groups, enterprise app and RBAC bindings."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable network flow logging where it is billable (currently AWS)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# AWS
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for the landing zone."
  type        = string
  default     = "us-east-1"
}

variable "aws_vpc_cidr" {
  description = "CIDR block for the AWS VPC."
  type        = string
  default     = "10.100.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.aws_vpc_cidr)) && tonumber(split("/", var.aws_vpc_cidr)[1]) <= 24
    error_message = "aws_vpc_cidr must be a valid IPv4 CIDR of /24 or larger."
  }
}

# ---------------------------------------------------------------------------
# Azure / Entra ID
# ---------------------------------------------------------------------------

variable "azure_subscription_id" {
  description = "Azure subscription ID. Required by the azurerm provider."
  type        = string
  default     = null
}

variable "entra_tenant_id" {
  description = "Entra ID tenant ID (the M365 Developer tenant)."
  type        = string
  default     = null
}

variable "azure_location" {
  description = "Azure region for the landing zone."
  type        = string
  default     = "eastus"
}

variable "azure_vnet_cidr" {
  description = "CIDR block for the Azure VNet."
  type        = string
  default     = "10.200.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.azure_vnet_cidr)) && tonumber(split("/", var.azure_vnet_cidr)[1]) <= 24
    error_message = "azure_vnet_cidr must be a valid IPv4 CIDR of /24 or larger."
  }
}

variable "entra_group_prefix" {
  description = "Optional prefix for Entra ID group display names."
  type        = string
  default     = ""
}

variable "entra_application_display_name" {
  description = "Display name of the enterprise application."
  type        = string
  default     = "MC-ZTM Multi-Cloud Portal"
}

variable "entra_group_members" {
  description = "Map of group key (cloud_admins | audit_team | copilot_early_access) -> list of UPNs."
  type        = map(list(string))
  default     = {}
}

variable "enable_conditional_access" {
  description = "Create the Conditional Access policy requiring MFA for Cloud-Admins."
  type        = bool
  default     = false
}

variable "conditional_access_state" {
  description = "CA policy state. Start report-only, promote to enabled once impact is understood."
  type        = string
  default     = "enabledForReportingButNotEnforced"
}

variable "break_glass_user_object_ids" {
  description = "Object IDs of emergency-access accounts excluded from the CA policy."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# GCP
# ---------------------------------------------------------------------------

variable "gcp_project_id" {
  description = "GCP project ID that owns the network."
  type        = string
  default     = null
}

variable "gcp_region" {
  description = "GCP region for the subnets."
  type        = string
  default     = "us-central1"
}

variable "gcp_vpc_cidr" {
  description = <<-EOT
    Aggregate CIDR for the GCP subnets. Note: the original design called for
    10.300.0.0/16, which is not a valid IPv4 range (octets stop at 255).
  EOT
  type        = string
  default     = "10.30.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.gcp_vpc_cidr)) && tonumber(split("/", var.gcp_vpc_cidr)[1]) <= 24
    error_message = "gcp_vpc_cidr must be a valid IPv4 CIDR of /24 or larger."
  }
}
