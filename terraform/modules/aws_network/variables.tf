variable "name_prefix" {
  description = "Prefix applied to every resource name (e.g. mcztm-dev)."
  type        = string
}

variable "region" {
  description = "AWS region. Used to build interface endpoint service names."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.100.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.100.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet."
  type        = string
  default     = "10.100.2.0/24"
}

variable "admin_cidrs" {
  description = "Source CIDRs allowed break-glass HTTPS access to workloads."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must not contain 0.0.0.0/0; scope it to known networks."
  }
}

variable "enable_flow_logs" {
  description = "Ship VPC flow logs to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch Logs retention for VPC flow logs."
  type        = number
  default     = 14
}

variable "enable_ssm_endpoints" {
  description = <<-EOT
    Create ssm/ssmmessages/ec2messages interface endpoints so private instances
    reach Session Manager without a NAT gateway. Interface endpoints are NOT
    free tier (~$7/mo each); leave off unless you are actually launching hosts.
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}
