# Current Azure client context
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name  # should be "bnnextgen-vnet"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_route_table" "aks" {
  name                = "aks-route-table"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "appgw_subnet" {
  name                 = "appgw-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.2.0/24"]
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_subnet_route_table_association" "aks" {
  subnet_id      = azurerm_subnet.aks_subnet.id
  route_table_id = azurerm_route_table.aks.id
}

# DNS Zone (must be proper, e.g. bnnextgen.local or bnnextgen.com)
resource "azurerm_resource_group" "dns" {
  name     = "rg-bnnextgen-dns"
  location = var.location
}

resource "azurerm_dns_zone" "main" {
  name                = "bnnextgen.local"
  resource_group_name = azurerm_resource_group.dns.name
}

# Public IP for Application Gateway
resource "azurerm_public_ip" "appgw" {
  name                = "appgw-public-ip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Application Gateway
resource "azurerm_application_gateway" "main" {
  name                = "bnnextgen-appgw"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }
  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.appgw_subnet.id
  }
  frontend_port {
    name = "appGatewayFrontendPort"
    port = 80
  }
  frontend_ip_configuration {
    name                 = "appGatewayFrontendIP"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }
  backend_address_pool {
    name  = "appGatewayBackendPool"
    # addresses can be dynamically added by AGIC
  }
  backend_http_settings {
    name                  = "appGatewayBackendHttpSettings"
    port                  = 80
    protocol              = "Http"
    cookie_based_affinity = "Disabled"
  }
  http_listener {
    name                           = "appGatewayHttpListener"
    frontend_ip_configuration_name = "appGatewayFrontendIP"
    frontend_port_name             = "appGatewayFrontendPort"
    protocol                       = "Http"
  }
  request_routing_rule {
    name                       = "default-rule"
    rule_type                  = "Basic"
    http_listener_name         = "appGatewayHttpListener"
    backend_address_pool_name  = "appGatewayBackendPool"
    backend_http_settings_name = "appGatewayBackendHttpSettings"
    priority                   = 100
  }
}

# Azure Container Registry
data "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.acr_resource_group_name
}

#Azure Key Vault
resource "azurerm_key_vault" "main" {
  name                        = "${var.key_vault_name}${random_string.unique.result}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  purge_protection_enabled    = true
  soft_delete_retention_days  = 7

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = ["Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"]
  }
}

resource "azurerm_key_vault_access_policy" "aks" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_kubernetes_cluster.aks.identity[0].tenant_id
  object_id    = azurerm_kubernetes_cluster.aks.identity[0].principal_id
  secret_permissions = ["Get", "List"]
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "bnnextgen"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "bnnextgen"
  kubernetes_version  = "1.33.0"

  default_node_pool {
    name       = "system"
    vm_size    = "Standard_DS2_v2"
    node_count = 1
    vnet_subnet_id  = azurerm_subnet.aks_subnet.id
  }

  # Enable system-assigned identity
  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    load_balancer_sku  = "standard"
    network_policy     = "azure"
    dns_service_ip     = "10.2.0.10"
    service_cidr       = "10.2.0.0/24"
    outbound_type      = "loadBalancer"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  role_based_access_control_enabled = true
  oidc_issuer_enabled              = true

  # AGIC Addon Profile (correct block)
  ingress_application_gateway {
    gateway_id = azurerm_application_gateway.main.id
  }
}

# Grant AKS Kubelet Identity ACR Pull permissions
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = data.azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# Key Vault with unique name using random_string
resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

#add second node pool
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_DS2_v2"
  node_count            = 1
  vnet_subnet_id        = azurerm_subnet.aks_subnet.id
  mode                  = "User"
  orchestrator_version  = azurerm_kubernetes_cluster.aks.kubernetes_version
  node_labels = {
    "role" = "user"
  }
}

