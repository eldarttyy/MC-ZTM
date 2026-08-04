variable "name_prefix" {
  description = "Prefix applied to every resource name (e.g. mcztm-dev)."
  type        = string
}

variable "project_id" {
  description = "GCP project ID that owns the network."
  type        = string
}

variable "region" {
  description = "GCP region for the subnets."
  type        = string
  default     = "us-central1"
}

variable "vpc_cidr" {
  description = <<-EOT
    Supernet covering every subnet in this VPC. Used as the source range for the
    internal allow rule. GCP has no VPC-level CIDR, so this is a Terraform-side
    aggregate rather than a real API field.
  EOT
  type        = string
  default     = "10.30.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.30.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet."
  type        = string
  default     = "10.30.2.0/24"
}

variable "admin_cidrs" {
  description = "Source CIDRs allowed break-glass HTTPS access to tagged instances."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must not contain 0.0.0.0/0; scope it to known networks."
  }
}
