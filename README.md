# AKS Private Cluster Terraform Package

This Terraform package provisions a fully private Azure Kubernetes Service (AKS) cluster with:

- Private API server and networking
- System and user node pools
- Application Gateway Ingress Controller (AGIC) enabled as an AKS Add-on
- Application Gateway provisioned and integrated
- DNS zone for ingress and workload domain management
- Azure Container Registry (ACR) integration for image pulls
- Azure Key Vault integration for Kubernetes secret management

---

## Prerequisites

- [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html) >= 1.1.0
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Sufficient Azure permissions to create resource groups, AKS, ACR, Key Vault, and DNS resources

---

## Configuration

Set the following variables (in `terraform.tfvars`, CLI, or environment):

- `resource_group_name` — Name for main Azure resource group
- `cluster_name` — Name for AKS cluster
- `dns_resource_group_name` — Resource group for DNS zone
- `dns_zone_name` — DNS zone (e.g., `mydomain.com`)
- `acr_name` — Name of your Azure Container Registry
- `acr_resource_group_name` — Resource group for your ACR
- `key_vault_name` — Name for your Azure Key Vault

Example `terraform.tfvars`:
```hcl
resource_group_name      = "my-aks-rg"
cluster_name             = "my-aks"
dns_resource_group_name  = "my-dns-rg"
dns_zone_name            = "mydomain.com"
acr_name                 = "myacr"
acr_resource_group_name  = "my-acr-rg"
key_vault_name           = "my-keyvault"
```

---

## **Deployment**
terraform init
terraform apply
---

## **Post-Deployment Steps**

### 1. **Get kubectl Credentials**
az aks get-credentials --resource-group <resource_group_name> --name <cluster_name>
---

### 2. **Verify AGIC Add-on**

The Application Gateway Ingress Controller (AGIC) is automatically enabled as an AKS add-on and integrated with the provisioned Application Gateway. You do **not** need to install AGIC manually via Helm.

To verify AGIC is enabled:
az aks show --resource-group <resource_group_name> --name <cluster_name> --query "addonProfiles.ingressApplicationGateway"
You should see `enabled: true` and the Application Gateway resource ID.

---

### 3. **Install cert-manager**
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
---

### 4. **Create LetsEncrypt ClusterIssuer**

Create a file named `cluster-issuer.yaml`:
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: <your-email>
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: azure/application-gateway
Apply it:
kubectl apply -f cluster-issuer.yaml
---

### 5. **Annotate Your Ingress Resources**
metadata:
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    cert-manager.io/cluster-issuer: letsencrypt-prod
---

### 6. **Create SecretProviderClass for Azure Key Vault (optional)**

See [Azure docs](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver) for details.

---

## **Outputs**

- AKS kubeconfig (raw string)
- Application Gateway ID
- DNS zone ID and nameservers (for DNS delegation)
- ACR and Key Vault integration ready

---

## **Notes**

- You must delegate your domain to the Azure DNS zone nameservers output by Terraform.
- Firewall, private endpoint, and DNS resolver configuration may be needed for fully private networking.
- For full documentation, see the Azure AKS, AGIC, and Key Vault CSI documentation.

---
