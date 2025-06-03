## AKS Fully Private Cluster with AGIC & LetsEncrypt - Single Terraform Package

This Terraform package provisions:

- Resource groups (for AKS/networking and DNS)
- Azure DNS zone for ingress
- Fully private AKS cluster with:
  - System and user node pools
  - Managed identity
- Azure Application Gateway (for AGIC)
- All networking and identity plumbing

---

### Usage

1. **Set variables**  
   Edit `terraform.tfvars` or use `-var` CLI switches for at least:
   - `resource_group_name`
   - `cluster_name`
   - `dns_resource_group_name`
   - `dns_zone_name`

2. **Run Terraform**
   ```sh
   terraform init
   terraform apply
   ```

3. **Post-deploy steps**

   - **Get kubeconfig**
     ```sh
     az aks get-credentials --resource-group <resource_group_name> --name <cluster_name>
     ```

   - **Install AGIC via Helm**
     ```sh
     helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
     helm repo update

     helm install ingress-azure application-gateway-kubernetes-ingress/ingress-azure \
       --set appgw.name=<appgw-name> \
       --set appgw.resourceGroup=<resource_group_name> \
       --set appgw.subscriptionId=<sub-id> \
       --set appgw.shared=false \
       --set armAuth.type=aadPodIdentity \
       --set armAuth.identityClientID=<aks-identity-client-id>
     ```

   - **Install cert-manager**
     ```sh
     kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
     ```

   - **Create a ClusterIssuer for LetsEncrypt**
     ```yaml
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
     ```
     Apply with:
     ```sh
     kubectl apply -f cluster-issuer.yaml
     ```

   - **Annotate your ingress**
     ```yaml
     kubernetes.io/ingress.class: azure/application-gateway
     cert-manager.io/cluster-issuer: letsencrypt-prod
     ```

---

**Outputs:**
- AKS kubeconfig (raw)
- Application Gateway ID
- DNS zone ID and nameservers

---

**Note:**  
- You must delegate your DNS zone to the Azure DNS nameservers output by this package.
- You may need to configure firewall rules and private endpoint DNS for full cluster privacy.
- See [Azure AKS private cluster docs](https://learn.microsoft.com/en-us/azure/aks/private-clusters) for advanced networking and DNS setup.
