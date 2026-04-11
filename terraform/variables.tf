variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "location" {
  type        = string
  description = "Azure region for all resources"
  default     = "eastus"
}

variable "environment" {
  type        = string
  description = "Deployment environment label (e.g. dev, prod)"
  default     = "dev"
}

variable "owner" {
  type        = string
  description = "Owner tag value"
  default     = "pauljwmiller"
}

variable "project" {
  type        = string
  description = "Short project identifier used in resource names"
  default     = "invoicecloud"
}
