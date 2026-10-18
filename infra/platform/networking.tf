# ─── NSGs ────────────────────────────────────────────────────────────────────
# Created before VNet modules so they can be referenced inline as subnet props.

resource "azurerm_network_security_group" "aks_system" {
  name                = "nsg-aks-system-${local.suffix}"
  location            = var.location
  resource_group_name = module.spoke_resource_group.name
  tags                = local.default_tags

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "aks_user" {
  name                = "nsg-aks-user-${local.suffix}"
  location            = var.location
  resource_group_name = module.spoke_resource_group.name
  tags                = local.default_tags

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-pe-${local.suffix}"
  location            = var.location
  resource_group_name = module.spoke_resource_group.name
  tags                = local.default_tags
}

# ─── Hub VNet ────────────────────────────────────────────────────────────────
# Contains Azure Firewall and optional Bastion. All egress from the spoke
# flows through the firewall via UDR.

module "hub_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.20.0"

  name          = local.hub_vnet_name
  location      = var.location
  parent_id     = module.hub_resource_group.resource_id
  address_space = [var.hub_vnet_cidr]
  tags          = local.default_tags

  enable_telemetry = var.enable_telemetry

  subnets = merge(
    {
      # Required subnet name for Azure Firewall — must be exactly "AzureFirewallSubnet"
      AzureFirewallSubnet = {
        name             = "AzureFirewallSubnet"
        address_prefixes = [var.firewall_subnet_cidr]
      }
    },
    var.enable_bastion ? {
      # Required subnet name for Azure Bastion — must be exactly "AzureBastionSubnet"
      AzureBastionSubnet = {
        name             = "AzureBastionSubnet"
        address_prefixes = [var.bastion_subnet_cidr]
      }
    } : {},
    var.enable_gateway_subnet ? {
      # Reserved for VPN/ExpressRoute gateway. No gateway resource is deployed here;
      # the subnet is pre-created so adding a gateway later requires no VNet changes.
      # GatewaySubnet cannot have an NSG — Azure blocks it.
      GatewaySubnet = {
        name             = "GatewaySubnet"
        address_prefixes = [var.gateway_subnet_cidr]
      }
    } : {}
  )
}

# ─── Spoke VNet ──────────────────────────────────────────────────────────────
# Hosts AKS node pools and private endpoints. All outbound traffic is forced
# through the hub firewall via route tables defined in routes.tf.

module "spoke_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.20.0"

  name          = local.spoke_vnet_name
  location      = var.location
  parent_id     = module.spoke_resource_group.resource_id
  address_space = [var.spoke_vnet_cidr]
  tags          = local.default_tags

  enable_telemetry = var.enable_telemetry

  subnets = {
    snet-aks-system = {
      name             = "snet-aks-system"
      address_prefixes = [var.aks_system_subnet_cidr]
      network_security_group = {
        id = azurerm_network_security_group.aks_system.id
      }
      # Required for Workload Identity pod identity webhook
      private_endpoint_network_policies = "Disabled"
    }

    snet-aks-user = {
      name             = "snet-aks-user"
      address_prefixes = [var.aks_user_subnet_cidr]
      network_security_group = {
        id = azurerm_network_security_group.aks_user.id
      }
      private_endpoint_network_policies = "Disabled"
    }

    snet-private-endpoints = {
      name             = "snet-private-endpoints"
      address_prefixes = [var.private_endpoint_subnet_cidr]
      network_security_group = {
        id = azurerm_network_security_group.private_endpoints.id
      }
      # Required for private endpoints to work in this subnet
      private_endpoint_network_policies = "Disabled"
    }
  }
}

# ─── VNet Peering ─────────────────────────────────────────────────────────────
# Bidirectional peering lets firewall see spoke traffic and Bastion reach nodes.

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "peer-hub-to-spoke"
  resource_group_name          = module.hub_resource_group.name
  virtual_network_name         = local.hub_vnet_name
  remote_virtual_network_id    = module.spoke_vnet.resource_id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  allow_gateway_transit        = false

  depends_on = [module.hub_vnet, module.spoke_vnet]
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-spoke-to-hub"
  resource_group_name          = module.spoke_resource_group.name
  virtual_network_name         = local.spoke_vnet_name
  remote_virtual_network_id    = module.hub_vnet.resource_id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  use_remote_gateways          = false

  depends_on = [module.hub_vnet, module.spoke_vnet]
}
