# Route Tables
# Force all outbound traffic from AKS node subnets through Azure Firewall.
# AKS uses outbound_type = "userDefinedRouting" so it never manages these routes.

resource "azurerm_route_table" "aks_system" {
  name                          = "rt-aks-system-${local.suffix}"
  location                      = var.location
  resource_group_name           = module.spoke_resource_group.name
  bgp_route_propagation_enabled = false
  tags                          = local.default_tags
}

resource "azurerm_route" "aks_system_default" {
  name                   = "udr-default"
  resource_group_name    = module.spoke_resource_group.name
  route_table_name       = azurerm_route_table.aks_system.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.main.ip_configuration[0].private_ip_address
}

resource "azurerm_route_table" "aks_user" {
  name                          = "rt-aks-user-${local.suffix}"
  location                      = var.location
  resource_group_name           = module.spoke_resource_group.name
  bgp_route_propagation_enabled = false
  tags                          = local.default_tags
}

resource "azurerm_route" "aks_user_default" {
  name                   = "udr-default"
  resource_group_name    = module.spoke_resource_group.name
  route_table_name       = azurerm_route_table.aks_user.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.main.ip_configuration[0].private_ip_address
}

# Route Table Associations

resource "azurerm_subnet_route_table_association" "aks_system" {
  subnet_id      = module.spoke_vnet.subnets["snet-aks-system"].resource_id
  route_table_id = azurerm_route_table.aks_system.id
}

resource "azurerm_subnet_route_table_association" "aks_user" {
  subnet_id      = module.spoke_vnet.subnets["snet-aks-user"].resource_id
  route_table_id = azurerm_route_table.aks_user.id
}
