variable "name_prefix" {
  description = "Prefix applied to every resource name (e.g. mcztm-dev)."
  type        = string
}

variable "location" {
  description = "Azure region for the resource group and VNet."
  type        = string
  default     = "eastus"
}

variable "vnet_cidr" {
  description = "CIDR block for the virtual network."
  type        = string
  default     = "10.200.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vnet_cidr))
    error_message = "vnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.200.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet."
  type        = string
  default     = "10.200.2.0/24"
}

variable "admin_cidrs" {
  description = "Source CIDRs allowed break-glass HTTPS access. Empty means none."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must not contain 0.0.0.0/0; scope it to known networks."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
