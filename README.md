# Azure Function App – Cloud Platform Engineer Technical Challenge

A Terraform-provisioned Azure Function App running a .NET 9 isolated-worker HTTP-triggered "Hello World" function on the **Consumption (Free/Y1) plan**.

Includes the bonus: a **Private Endpoint** with Private DNS configuration for the Function App data plane, while keeping public access enabled for testing.

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

| Resource | Name pattern | Purpose |
|---|---|---|
| Resource Group | `rg-invoicecloud-func-dev` | Container for all resources |
| Storage Account | `stinvoicecloud{suffix}` | Required by Functions runtime |
| Log Analytics Workspace | `log-invoicecloud-func-dev` | Backend for App Insights |
| Application Insights | `appi-invoicecloud-func-dev` | Telemetry and live metrics |
| App Service Plan | `asp-invoicecloud-func-dev` | Y1 Consumption (free tier) |
| Function App | `func-invoicecloud-hello-dev-{suffix}` | Hosts the HTTP functions |
| Virtual Network | `vnet-invoicecloud-func-dev` | Bonus: network for private endpoint |
| Subnet | `snet-pe-invoicecloud-dev` | Bonus: dedicated PE subnet |
| Private DNS Zone | `privatelink.azurewebsites.net` | Bonus: private DNS resolution |
| Private Endpoint | `pe-func-invoicecloud-dev` | Bonus: private data-plane access |

---

## Prerequisites

| Tool | Version used | Install |
|---|---|---|
| Azure CLI | 2.84.0+ | https://learn.microsoft.com/en-us/cli/azure/install-azure-cli |
| Terraform | 1.14.7+ | https://developer.hashicorp.com/terraform/install |
| .NET SDK | 9.0+ | https://dotnet.microsoft.com/download |

Verify installs:

```bash
az --version
terraform --version
dotnet --version
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
function_app_name    = "func-invoicecloud-hello-dev-abc123"
function_url         = "https://func-invoicecloud-hello-dev-abc123.azurewebsites.net/api/httpget"
private_endpoint_ip  = "10.0.1.4"
```

### 4. Deploy the Function Code

Retrieve the function app name from Terraform output, then build and deploy:

```bash
# From the repo root
FUNC_APP_NAME=$(cd terraform && terraform output -raw function_app_name)

dotnet publish function/http --configuration Release --output ./publish

az functionapp deployment source config-zip \
  --resource-group rg-invoicecloud-func-dev \
  --name "$FUNC_APP_NAME" \
  --src <(cd publish && zip -r - .)
```

Or using the Azure Functions Core Tools:

```bash
cd function/http
func azure functionapp publish "$FUNC_APP_NAME" --dotnet-isolated
```

---

## Validation

Retrieve the function key and invoke the endpoint:

```bash
FUNC_APP_NAME=$(cd terraform && terraform output -raw function_url)

# Simple GET – returns "Hello, World."
curl "$FUNC_APP_NAME"

# GET with name param – returns "Hello, Paul."
curl "${FUNC_APP_NAME}?name=Paul"
```

Expected responses:

```
Hello, World.
Hello, Paul.
```

You can also open the URL directly in a browser.

---

## Bonus: Private Endpoint

### What was deployed

A **Private Endpoint** (`sites` sub-resource) is provisioned inside a dedicated subnet (`10.0.1.0/24`) within a VNet (`10.0.0.0/16`). A Private DNS Zone (`privatelink.azurewebsites.net`) is linked to the VNet so that resources inside the VNet resolve the function's hostname to the private IP instead of the public one.

### Access model

Public access is **intentionally left enabled** per the challenge requirements to allow straightforward testing with `curl`. In a real production scenario you would:

1. Set `public_network_access_enabled = false` on the Function App
2. Access the function from a VM, VPN gateway, or Azure Bastion connected to the same VNet

### Testing from within the VNet

From a VM in the same VNet:

```bash
# Resolves to the private IP via the private DNS zone
curl https://<function-app-name>.azurewebsites.net/api/httpget
```

The private endpoint IP is exposed as a Terraform output:

```bash
cd terraform && terraform output private_endpoint_ip
```

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
- The storage account access key is passed to the Function App via Terraform; consider using a managed identity and `storage_uses_managed_identity = true` for production workloads
