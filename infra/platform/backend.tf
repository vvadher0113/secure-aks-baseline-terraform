# Partial backend — all values are supplied at init time via -backend-config.
# Example:
#   terraform init -backend-config=../../backends/platform.hcl
#
# See backends/platform.hcl.example for the required keys.
terraform {
  backend "azurerm" {
    use_azuread_auth = true
  }
}
