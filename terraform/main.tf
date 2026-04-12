# Random suffix to ensure globally unique names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result
  tags = {
    environment = var.environment
    owner       = var.owner
    project     = var.project
  }
}

# ── Resource Group ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project}-func-${var.environment}"
  location = var.location
  tags     = local.tags
}

# ── Storage Account ───────────────────────────────────────────────────────────
# Required by Azure Functions for internal state (triggers, logs, etc.)
resource "azurerm_storage_account" "sa" {
  name                     = "st${var.project}${local.suffix}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.tags
}

# ── Log Analytics Workspace ───────────────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "law" {
  name                = "log-${var.project}-func-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# ── Application Insights ──────────────────────────────────────────────────────
resource "azurerm_application_insights" "appi" {
  name                = "appi-${var.project}-func-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.law.id
  application_type    = "web"
  tags                = local.tags
}

# ── Consumption (Y1 / Free Tier) App Service Plan ────────────────────────────
resource "azurerm_service_plan" "asp" {
  name                = "EastUS2LinuxDynamicPlan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = local.tags
}

# ── Function App ──────────────────────────────────────────────────────────────
resource "azurerm_linux_function_app" "func" {
  name                       = "func-${var.project}-hello-${var.environment}-${local.suffix}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  service_plan_id            = azurerm_service_plan.asp.id
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key

  site_config {
    application_stack {
      dotnet_version              = "9.0"
      use_dotnet_isolated_runtime = true
    }
  }

  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.appi.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.appi.connection_string
    "WEBSITE_RUN_FROM_PACKAGE"              = "1"
  }

  tags = local.tags
}

# ── Bonus: Networking for Private Endpoint ────────────────────────────────────
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.project}-func-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "snet_pe" {
  name                 = "snet-pe-${var.project}-${var.environment}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ── Bonus: Private DNS Zone (azurewebsites.net) ───────────────────────────────
resource "azurerm_private_dns_zone" "dns_func" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "dns_vnet_link" {
  name                  = "vnetlink-${var.project}-func-${var.environment}"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.dns_func.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = local.tags
}

# ── Bonus: Private Endpoint for Function App (data plane) ─────────────────────
# NOTE: Azure does not support Private Endpoints on the Consumption (Y1/Dynamic)
# plan. Attempting to provision one returns:
#   BadRequest: SkuCode 'Dynamic' is invalid.
#
# The VNet, subnet, and Private DNS Zone above are fully provisioned and ready.
# To enable the private endpoint, upgrade the App Service Plan sku_name from
# "Y1" to "EP1" (Elastic Premium) and uncomment the resource block below.
#
# resource "azurerm_private_endpoint" "pe_func" {
#   name                = "pe-func-${var.project}-${var.environment}"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   subnet_id           = azurerm_subnet.snet_pe.id
#
#   private_service_connection {
#     name                           = "psc-func-${var.project}-${var.environment}"
#     private_connection_resource_id = azurerm_linux_function_app.func.id
#     subresource_names              = ["sites"]
#     is_manual_connection           = false
#   }
#
#   private_dns_zone_group {
#     name                 = "dns-zone-group-func"
#     private_dns_zone_ids = [azurerm_private_dns_zone.dns_func.id]
#   }
#
#   tags = local.tags
# }
