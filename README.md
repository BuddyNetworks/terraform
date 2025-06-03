# AKS Private Cluster Terraform Package

This Terraform package provisions a fully private Azure Kubernetes Service (AKS) cluster with:

- Private API server and networking
- System and user node pools
- Application Gateway Ingress Controller (AGIC) enabled as an AKS Add-on
- Application Gateway provisioned and integrated
- Azure DNS zone for ingress and workload domain management
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

## Deployment

```sh
terraform init
terraform apply
```

---

## Post-Deployment Steps

### 1. Get AKS Credentials

```sh
az aks get-credentials --resource-group <resource_group_name> --name <cluster_name>
```

---

### 2. Verify AGIC Add-on

AGIC (Application Gateway Ingress Controller) is enabled as an AKS add-on and integrated with the provisioned Application Gateway.  
No manual Helm installation is required.

To verify AGIC is enabled:
```sh
az aks show --resource-group <resource_group_name> --name <cluster_name> --query "addonProfiles.ingressApplicationGateway"
```
You should see `enabled: true` and the Application Gateway resource ID.

---

### 3. Install cert-manager

```sh
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
```

---

### 4. Create Let’s Encrypt ClusterIssuer

Create a file named `cluster-issuer.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: <your-email@example.com>
    privateKeySecretRef:
      name: letsencrypt-production
    solvers:
      - http01:
          ingress:
            class: azure/application-gateway
```

Apply it:

```sh
kubectl apply -f cluster-issuer.yaml
```

---

### 5. Create a Certificate Resource

Create a file named `certificate.yaml` (update the namespace if your Ingress is not in `apps`):

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: tls-secret
  namespace: apps
spec:
  secretName: tls-secret
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  commonName: test.architect4hire.com
  dnsNames:
    - test.architect4hire.com
```

Apply it:

```sh
kubectl apply -f certificate.yaml
```

cert-manager will automatically create the `tls-secret` in the `apps` namespace after the certificate is issued.

---

### 6. Configure Your Ingress Resource

Your Ingress should reference the correct `secretName`, `host`, and annotations. Example:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aspnetapp-dev
  namespace: apps
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    cert-manager.io/cluster-issuer: letsencrypt-production
    cert-manager.io/acme-challenge-type: http01
spec:
  tls:
    - hosts:
        - "test.architect4hire.com"
      secretName: tls-secret
  rules:
    - host: "test.architect4hire.com"
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: sample-aks-app-service
                port:
                  number: 4000
```

Apply your Ingress:

```sh
kubectl apply -f ingress.yaml
```

---

### 7. (Optional) Create SecretProviderClass for Azure Key Vault

See [Azure docs](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver) for details.

---

## Outputs

- AKS kubeconfig (raw string)
- Application Gateway ID
- DNS zone ID and nameservers (for DNS delegation)
- ACR and Key Vault integration ready

---

## Notes

- **DNS Delegation:**  
  You must delegate your domain to the Azure DNS zone nameservers output by Terraform.  
  Update your domain registrar’s nameserver records to point to the Azure DNS zone nameservers.

- **Networking:**  
  Firewall, private endpoint, and DNS resolver configuration may be needed for fully private networking.

- **Documentation:**  
  For full documentation, see the Azure AKS, AGIC, cert-manager, and Key Vault CSI documentation.

---
