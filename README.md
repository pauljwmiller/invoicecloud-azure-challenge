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

> Requires a function key (`?code=<key>`). See [Validation](#validation) below.

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
| Private DNS Zone | `privatelink.azurewebsites.net` | Bonus: private DNS resolution |

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

## Validation

Get the function key:

```bash
FUNC_APP_NAME=$(cd terraform && terraform output -raw function_app_name)

az functionapp keys list \
  --resource-group rg-invoicecloud-func-dev \
  --name "$FUNC_APP_NAME" \
  --query "functionKeys.default" -o tsv
```

Test the endpoint:

```bash
FUNC_KEY=<your-function-key>
FUNC_URL=$(cd terraform && terraform output -raw function_url)

# Returns "Hello, World."
curl "${FUNC_URL}?code=${FUNC_KEY}"

# Returns "Hello, Paul."
curl "${FUNC_URL}?code=${FUNC_KEY}&name=Paul"
```

Expected responses:

```
Hello, World.
Hello, Paul.
```

---

## Bonus: Private Endpoint & Networking

### What was provisioned

The Terraform configuration provisions a full networking stack ready for private endpoint connectivity:

- **VNet** (`10.0.0.0/16`) in `eastus2`
- **Subnet** (`10.0.1.0/24`) dedicated for private endpoints
- **Private DNS Zone** (`privatelink.azurewebsites.net`) linked to the VNet

### Azure platform constraint

Private Endpoints on Azure Function Apps require a **Premium (EP1+) or Dedicated plan**. The Consumption (Y1/Dynamic) plan does not support them — this is an Azure platform limitation, not a configuration issue. Attempting to create a private endpoint against a Dynamic-plan function app returns:

```
BadRequest: SkuCode 'Dynamic' is invalid.
```

### What this means in practice

The networking infrastructure is in place. To enable a private endpoint:
1. Upgrade the App Service Plan from `Y1` to `EP1` (Elastic Premium) in `main.tf`
2. Re-run `terraform apply` — the private endpoint resource is already defined and will provision successfully

### Access model (with Premium plan)

Public access would be **intentionally left enabled** per the challenge requirements to allow testing with `curl`. In production you would set `public_network_access_enabled = false` and route all access through a VM, VPN gateway, or Azure Bastion in the same VNet.

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

- No credentials or secrets are committed to this repository
- `local.settings.json` is excluded via `.gitignore`
- Terraform state is local — for team use, migrate state to Azure Blob Storage backend
- The storage account access key is passed to the Function App via Terraform; for production use `storage_uses_managed_identity = true` with a managed identity instead
