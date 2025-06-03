variable "resource_group_name" {
  description = "Resource group name for AKS and networking"
  type        = string
}

variable "dns_resource_group_name" {
  description = "Resource group name for DNS zone"
  type        = string
}

variable "dns_zone_name" {
  description = "The name of the DNS zone to create (e.g., example.com)"
  type        = string
}

variable "location" {
  description = "Azure location"
  default     = "eastus"
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version"
  type        = string
  default     = "1.29.2"
}