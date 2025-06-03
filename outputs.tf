output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "aks_kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

output "application_gateway_id" {
  value = azurerm_application_gateway.main.id
}

output "dns_zone_id" {
  value = azurerm_dns_zone.main.id
}

output "dns_zone_name_servers" {
  value = azurerm_dns_zone.main.name_servers
}