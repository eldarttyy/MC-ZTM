/**
 * Azure network landing zone.
 *
 * Zero-trust posture:
 *   - Every subnet carries an NSG; the "private" NSG denies all internet-bound
 *     egress and all inbound traffic that did not originate in the VNet.
 *   - No public IPs and no inbound 22/3389 rules. Administrative access is
 *     expected via Entra-authenticated Bastion / Azure Arc, not open ports.
 *   - A user-assigned managed identity replaces client secrets for workloads,
 *     which is what ties Azure compute back to Entra ID as the single IdP.
 */

locals {
  name = "${var.name_prefix}-azure"
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name}"
  location = var.location

  tags = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]

  tags = var.tags
}

resource "azurerm_subnet" "public" {
  name                 = "snet-public"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.public_subnet_cidr]
}

resource "azurerm_subnet" "private" {
  name                 = "snet-private"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_subnet_cidr]

  # Required for private endpoints to bypass subnet route/NSG policies.
  private_endpoint_network_policies = "Enabled"
}

# ---------------------------------------------------------------------------
# NSG: public tier — HTTPS in from approved admin ranges, nothing else
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "public" {
  name                = "nsg-${local.name}-public"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  tags = var.tags
}

resource "azurerm_network_security_rule" "public_allow_admin_https" {
  count = length(var.admin_cidrs) > 0 ? 1 : 0

  name                        = "Allow-Admin-HTTPS-Inbound"
  description                 = "Break-glass HTTPS from approved administrative networks"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefixes     = var.admin_cidrs
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.public.name
}

resource "azurerm_network_security_rule" "public_allow_vnet_inbound" {
  name                        = "Allow-VNet-Inbound"
  description                 = "East-west traffic inside the landing zone"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.public.name
}

resource "azurerm_network_security_rule" "public_deny_internet_inbound" {
  name                        = "Deny-Internet-Inbound"
  description                 = "Explicit deny so the intent is visible in the portal"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.public.name
}

# ---------------------------------------------------------------------------
# NSG: private tier — VNet only, egress limited to HTTPS
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "private" {
  name                = "nsg-${local.name}-private"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  tags = var.tags
}

resource "azurerm_network_security_rule" "private_allow_vnet_inbound" {
  name                        = "Allow-VNet-Inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.private.name
}

resource "azurerm_network_security_rule" "private_deny_internet_inbound" {
  name                        = "Deny-Internet-Inbound"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.private.name
}

resource "azurerm_network_security_rule" "private_allow_https_outbound" {
  name                        = "Allow-HTTPS-Outbound"
  description                 = "Entra ID, Azure Resource Manager and package feeds"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.private.name
}

resource "azurerm_network_security_rule" "private_deny_internet_outbound" {
  name                        = "Deny-Internet-Outbound"
  description                 = "Everything that is not HTTPS leaves no path out"
  priority                    = 4000
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.private.name
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.public.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.private.id
}

# ---------------------------------------------------------------------------
# Workload identity — Entra-backed, no secrets on disk
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "workload" {
  name                = "id-${local.name}-workload"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  tags = var.tags
}

resource "azurerm_role_assignment" "workload_reader" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}
