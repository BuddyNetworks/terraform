provider "azurerm" {
  features {}
}

# Resource group for AKS and core networking
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# Resource group for DNS zone (can be same as main)
resource "azurerm_resource_group" "dns" {
  name     = var.dns_resource_group_name
  location = var.location
}

# DNS zone for ingress
resource "azurerm_dns_zone" "main" {
  name                = var.dns_zone_name
  resource_group_name = azurerm_resource_group.dns.name
}

resource "azurerm_virtual_network" "aks_vnet" {
  name                = "${var.cluster_name}-vnet"
  address_space       = ["10.0.0.0/8"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = ["10.240.0.0/16"]
  enforce_private_link_endpoint_network_policies = true
}

resource "azurerm_subnet" "appgw_subnet" {
  name                 = "appgw-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = ["10.241.0.0/16"]
}

resource "azurerm_public_ip" "appgw" {
  name                = "${var.cluster_name}-appgw-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "main" {
  name                = "${var.cluster_name}-appgw"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }
  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw_subnet.id
  }
  frontend_port {
    name = "frontend-port"
    port = 80
  }
  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }
  backend_address_pool {
    name = "default-backend"
  }
  backend_http_settings {
    name                  = "default-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    pick_host_name_from_backend_address = false
    probe_enabled         = false
  }
  http_listener {
    name                           = "default-listener"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "frontend-port"
    protocol                       = "Http"
  }
  request_routing_rule {
    name                       = "default-rule"
    rule_type                  = "Basic"
    http_listener_name         = "default-listener"
    backend_address_pool_name  = "default-backend"
    backend_http_settings_name = "default-http-settings"
  }
}

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${var.cluster_name}-aks-identity"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.cluster_name}-dns"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "system"
    node_count          = 2
    vm_size             = "Standard_DS2_v2"
    os_disk_size_gb     = 60
    vnet_subnet_id      = azurerm_subnet.aks_subnet.id
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 5
    orchestrator_version = var.kubernetes_version
    node_labels = {
      "nodepool-type" = "system"
    }
    node_taints = ["CriticalAddonsOnly=true:NoSchedule"]
  }

  identity {
    type = "UserAssigned"
    user_assigned_identity_id = azurerm_user_assigned_identity.aks.id
  }

  api_server_authorized_ip_ranges = []

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    network_policy    = "azure"
    dns_service_ip    = "10.2.0.10"
    service_cidr      = "10.2.0.0/24"
    docker_bridge_cidr = "172.17.0.1/16"
    outbound_type     = "userDefinedRouting"
  }

  private_cluster_enabled = true
  role_based_access_control_enabled = true
  oidc_issuer_enabled = true
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_DS2_v2"
  node_count            = 2
  os_disk_size_gb       = 60
  vnet_subnet_id        = azurerm_subnet.aks_subnet.id
  orchestrator_version  = var.kubernetes_version
  node_labels = {
    "nodepool-type" = "user"
  }
}

resource "azurerm_role_assignment" "agic" {
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
  role_definition_name = "Contributor"
  scope                = azurerm_application_gateway.main.id
}