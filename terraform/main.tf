/**
 * MC-ZTM root module.
 *
 * Three clouds, one topology: each landing zone gets a /16, a public subnet, a
 * private subnet and a default-deny edge. Identity is not replicated per cloud —
 * Entra ID owns it, and each cloud consumes it.
 *
 * Modules are independently toggleable so you can stand up (and tear down) one
 * cloud at a time while staying inside free-tier limits.
 */

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "MC-ZTM"
    },
    var.additional_tags,
  )

  # Non-overlapping ranges are what make future VPN / peering / Cloud WAN
  # attachment possible. Asserted below rather than left to convention.
  cidrs = {
    aws   = var.aws_vpc_cidr
    azure = var.azure_vnet_cidr
    gcp   = var.gcp_vpc_cidr
  }

  # Terraform has no "does CIDR a overlap CIDR b" function, so reduce each range
  # to [start, end) integers and compare those.
  cidr_bounds = {
    for cloud, cidr in local.cidrs : cloud => {
      start = sum([
        for i, octet in split(".", cidrhost(cidr, 0)) :
        parseint(octet, 10) * pow(256, 3 - i)
      ])
      size = pow(2, 32 - tonumber(split("/", cidr)[1]))
    }
  }
}

check "cidr_ranges_do_not_overlap" {
  assert {
    condition = alltrue([
      for pair in [["aws", "azure"], ["aws", "gcp"], ["azure", "gcp"]] :
      (
        local.cidr_bounds[pair[0]].start >=
        local.cidr_bounds[pair[1]].start + local.cidr_bounds[pair[1]].size
        ||
        local.cidr_bounds[pair[1]].start >=
        local.cidr_bounds[pair[0]].start + local.cidr_bounds[pair[0]].size
      )
    ])
    error_message = "AWS, Azure and GCP CIDR ranges overlap. Overlapping ranges cannot be peered or routed between later."
  }
}

module "aws_network" {
  source = "./modules/aws_network"
  count  = var.enable_aws ? 1 : 0

  name_prefix         = local.name_prefix
  region              = var.aws_region
  vpc_cidr            = var.aws_vpc_cidr
  public_subnet_cidr  = cidrsubnet(var.aws_vpc_cidr, 8, 1)
  private_subnet_cidr = cidrsubnet(var.aws_vpc_cidr, 8, 2)
  admin_cidrs         = var.admin_cidrs
  enable_flow_logs    = var.enable_flow_logs
  tags                = local.tags
}

module "azure_network" {
  source = "./modules/azure_network"
  count  = var.enable_azure ? 1 : 0

  name_prefix         = local.name_prefix
  location            = var.azure_location
  vnet_cidr           = var.azure_vnet_cidr
  public_subnet_cidr  = cidrsubnet(var.azure_vnet_cidr, 8, 1)
  private_subnet_cidr = cidrsubnet(var.azure_vnet_cidr, 8, 2)
  admin_cidrs         = var.admin_cidrs
  tags                = local.tags
}

module "gcp_network" {
  source = "./modules/gcp_network"
  count  = var.enable_gcp ? 1 : 0

  name_prefix         = local.name_prefix
  project_id          = var.gcp_project_id
  region              = var.gcp_region
  vpc_cidr            = var.gcp_vpc_cidr
  public_subnet_cidr  = cidrsubnet(var.gcp_vpc_cidr, 8, 1)
  private_subnet_cidr = cidrsubnet(var.gcp_vpc_cidr, 8, 2)
  admin_cidrs         = var.admin_cidrs
}

module "entra_identity" {
  source = "./modules/entra_identity"
  count  = var.enable_entra ? 1 : 0

  group_prefix                = var.entra_group_prefix
  application_display_name    = var.entra_application_display_name
  group_members               = var.entra_group_members
  enable_conditional_access   = var.enable_conditional_access
  conditional_access_state    = var.conditional_access_state
  break_glass_user_object_ids = var.break_glass_user_object_ids
}
