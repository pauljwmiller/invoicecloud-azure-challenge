# Azure Function App – Cloud Platform Engineer Technical Challenge

A Terraform-provisioned Azure Function App running a .NET 9 isolated-worker HTTP-triggered "Hello World" function on the **Consumption (Free/Y1) plan**.

Includes bonus items:
- **VNet + Private DNS Zone** configured for private endpoint access
- **GitHub Actions CI/CD pipeline** for automated build and deploy

> **Note on Private Endpoint:** Azure does not support Private Endpoints on the Consumption (Dynamic/Y1) plan — this is a hard platform constraint. The VNet, subnet, and Private DNS Zone are fully provisioned and documented. A Private Endpoint would require upgrading to a Premium plan. See the [Bonus section](#bonus-private-endpoint--networking) for full details.

---

## Live Function URL

```
https://func-invoicecloud-hello-dev-6koqhv.azurewebsites.net/api/httpget
```

> No key required — the function uses `AuthorizationLevel.Anonymous`. Open in a browser or `curl` directly.

---

## Repository Structure

```
.
├── terraform/
│   ├── main.tf            # All Azure resources
│   ├── variables.tf       # Input variable declarations
│   ├── outputs.tf         # Post-apply outputs (URLs, names)
│   ├── versions.tf        # Provider and Terraform version pins
│   └── terraform.tfvars   # Variable values (no secrets)
├── function/
│   └── http/              # .NET 9 Azure Functions app (from Azure-Samples)
│       ├── httpGetFunction.cs
│       ├── httpPostBodyFunction.cs
│       ├── Program.cs
│       ├── host.json
│       └── http.csproj
├── .github/
│   └── workflows/
│       └── deploy.yml     # Bonus: CI/CD – builds and deploys on push to main
└── README.md
```

---

## Architecture

| Resource | Name | Purpose |
|---|---|---|
| Resource Group | `rg-invoicecloud-func-dev` | Container for all resources |
| Storage Account | `stinvoicecloud{suffix}` | Required by Functions runtime |
| Log Analytics Workspace | `log-invoicecloud-func-dev` | Backend for App Insights |
| Application Insights | `appi-invoicecloud-func-dev` | Telemetry and live metrics |
| App Service Plan | `EastUS2LinuxDynamicPlan` | Y1 Consumption (free tier) |
| Function App | `func-invoicecloud-hello-dev-{suffix}` | Hosts the HTTP functions |
| Virtual Network | `vnet-invoicecloud-func-dev` | Bonus: network for private endpoint |
| Subnet | `snet-pe-invoicecloud-dev` | Bonus: dedicated PE subnet |
| Private DNS Zone | `privatelink.azurewebsites.net` | Bonus: private DNS for function app |
| Private DNS Zone | `privatelink.blob.core.windows.net` | Bonus: private DNS for storage account |
| Private Endpoint | `pe-sa-invoicecloud-dev` | Bonus: private endpoint on storage account blob |

---

## Prerequisites

| Tool | Version used | Install |
|---|---|---|
| Azure CLI | 2.84.0+ | https://learn.microsoft.com/en-us/cli/azure/install-azure-cli |
| Terraform | 1.14.7+ | https://developer.hashicorp.com/terraform/install |
| .NET SDK | 9.0+ | https://dotnet.microsoft.com/download |
| Azure Functions Core Tools | 4.x | `npm install -g azure-functions-core-tools@4` |

Verify installs:

```bash
az --version
terraform --version
dotnet --version
func --version
```

---

## Deployment Steps

### 1. Authenticate to Azure

```bash
az login
az account show  # confirm the correct subscription is active
```

### 2. Initialize Terraform

```bash
cd terraform
terraform init
```

### 3. Apply Terraform

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform will output the function app name and public URL when complete:

```
function_app_name     = "func-invoicecloud-hello-dev-6koqhv"
function_app_hostname = "func-invoicecloud-hello-dev-6koqhv.azurewebsites.net"
function_url          = "https://func-invoicecloud-hello-dev-6koqhv.azurewebsites.net/api/httpget"
resource_group_name   = "rg-invoicecloud-func-dev"
```

> **Note:** On new Azure subscriptions the Consumption plan may need to be created via `az functionapp create --consumption-plan-location` rather than Terraform directly due to a Dynamic VM quota constraint. If `terraform apply` fails on the App Service Plan resource, create the function app manually with that CLI command, then import it into Terraform state:
> ```bash
> terraform import azurerm_service_plan.asp /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Web/serverFarms/<plan-name>
> terraform import azurerm_linux_function_app.func /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Web/sites/<func-name>
> ```

### 4. Deploy the Function Code

```bash
FUNC_APP_NAME=$(cd terraform && terraform output -raw function_app_name)

cd function/http
func azure functionapp publish "$FUNC_APP_NAME" --dotnet-isolated
```

This builds the .NET 9 project, packages it, uploads to blob storage, and syncs the triggers automatically.

---

## Authorization

The original Azure-Samples template uses `AuthorizationLevel.Function`, which requires a `?code=<key>` query parameter on every request. This project changes that to `AuthorizationLevel.Anonymous` so the endpoint is publicly testable without managing function keys — appropriate for a demo/challenge environment. In production you would use `Function` or `Admin` level and distribute keys only to authorized callers.

---

## Validation

No key required. Test directly:

```bash
FUNC_URL=$(cd terraform && terraform output -raw function_url)

# No name param — returns "Hello, World."
curl "$FUNC_URL"

# With name param — returns "Hello, {name}." for any name provided
curl "${FUNC_URL}?name=Paul"
curl "${FUNC_URL}?name=Jane"
```

Expected responses:

```
Hello, World.
Hello, Paul.
Hello, Jane.
```

Or open the URL directly in a browser:
```
https://func-invoicecloud-hello-dev-6koqhv.azurewebsites.net/api/httpget
```

---

## Bonus: Private Endpoint & Networking

### What is provisioned and working

The full networking stack is live:

| Resource | Name | Status |
|---|---|---|
| Virtual Network (`10.0.0.0/16`) | `vnet-invoicecloud-func-dev` | ✅ Provisioned |
| Subnet (`10.0.1.0/24`) | `snet-pe-invoicecloud-dev` | ✅ Provisioned |
| Private DNS Zone | `privatelink.azurewebsites.net` | ✅ Linked to VNet |
| Private DNS Zone | `privatelink.blob.core.windows.net` | ✅ Linked to VNet |
| Private Endpoint (storage blob) | `pe-sa-invoicecloud-dev` | ✅ Live — IP `10.0.1.4` |
| Private Endpoint (function app) | `pe-func-invoicecloud-dev` | ⚠️ See below |

### Storage Account Private Endpoint

The storage account is the data-plane backbone of the Function App — it stores the deployment package, function keys, and trigger state. A private endpoint on the storage account's `blob` sub-resource is **fully supported on the Consumption plan** and is a legitimate production hardening step independent of the function app plan tier.

This is live and assigned private IP `10.0.1.4`. Any client inside the VNet resolving `stinvoicecloud<suffix>.blob.core.windows.net` will get the private IP via the linked DNS zone.

`public_network_access_enabled` remains `true` on the storage account because the Consumption plan Function App has no VNet integration and must reach storage over the public endpoint. Disabling public access is part of the production hardening path below.

### Function App Private Endpoint — platform constraint

Azure does not support inbound Private Endpoints on the Consumption (Y1/Dynamic) plan. Attempting to provision one returns:

```
BadRequest: SkuCode 'Dynamic' is invalid.
```

This is an Azure platform limitation, not a configuration issue. The private endpoint resource is fully defined in `main.tf` and commented out with this explanation. The DNS zone, VNet, and subnet are all correctly configured and ready.

### Access model

Public access is **intentionally enabled** per the challenge requirements — the function responds to `curl` from anywhere. With a private endpoint active (Premium or Flex Consumption plan), the access model would be:

| Path | How |
|---|---|
| Public (testing) | `https://func-invoicecloud-hello-dev-<suffix>.azurewebsites.net/api/httpget` |
| Private (VNet) | Deploy a VM into the VNet and `curl` the same hostname — DNS resolves to the private IP |
| Private (remote) | Connect via VPN Gateway or Azure Bastion, then access via hostname as above |

In production you would set `public_network_access_enabled = false` on the Function App to force all traffic through the private endpoint.

### Enabling the Function App Private Endpoint

One change in `main.tf`, then `terraform apply`:

1. Change `sku_name = "Y1"` to `sku_name = "EP1"` (or migrate to Flex Consumption)
2. Uncomment the `azurerm_private_endpoint.pe_func` resource block
3. Re-run `terraform apply` — all supporting infrastructure is already in place

---

## Bonus: CI/CD Pipeline

A GitHub Actions workflow (`.github/workflows/deploy.yml`) automatically builds and deploys the function on every push to `main` that modifies anything under `function/`.

### Required GitHub Secrets

| Secret | How to generate |
|---|---|
| `AZURE_CREDENTIALS` | See below |
| `AZURE_FUNCTION_APP_NAME` | Value of `terraform output function_app_name` |

Generate `AZURE_CREDENTIALS`:

```bash
az ad sp create-for-rbac \
  --name "sp-invoicecloud-github-actions" \
  --role contributor \
  --scopes /subscriptions/4102d8ef-3071-429e-8392-b77866d04d1a/resourceGroups/rg-invoicecloud-func-dev \
  --sdk-auth
```

Copy the JSON output and save it as the `AZURE_CREDENTIALS` secret in your GitHub repo settings.

---

## Cleanup

Remove all provisioned resources:

```bash
cd terraform
terraform destroy
```

This deletes the resource group and everything inside it.

---

## Security Notes

- No credentials or secrets are committed to this repository — the subscription ID in `terraform.tfvars` is a public identifier, not a credential; it grants no access without accompanying Azure credentials
- `local.settings.json` is excluded via `.gitignore`
- Terraform state is local — for team use, migrate state to Azure Blob Storage backend
- The storage account access key is passed to the Function App via Terraform; for production use `storage_uses_managed_identity = true` with a managed identity instead
