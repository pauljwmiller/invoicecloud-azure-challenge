output "resource_group_name" {
  description = "Name of the provisioned resource group"
  value       = azurerm_resource_group.rg.name
}

output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.func.name
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.func.default_hostname
}

output "function_url" {
  description = "Public URL for the Hello World HTTP GET function"
  value       = "https://${azurerm_linux_function_app.func.default_hostname}/api/httpget"
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.appi.connection_string
  sensitive   = true
}

# Private endpoint IP output is omitted — the Consumption (Y1) plan does not
# support Private Endpoints. Uncomment when upgrading to EP1 and enabling the
# azurerm_private_endpoint resource in main.tf.
#
# output "private_endpoint_ip" {
#   description = "Private IP assigned to the Function App private endpoint"
#   value       = azurerm_private_endpoint.pe_func.private_service_connection[0].private_ip_address
# }
