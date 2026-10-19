# Partial backend; all values supplied at init time via -backend-config.
# CI passes them as -backend-config="key=value" from repository variables.
# For local use, copy backends/platform.hcl.example to backends/platform.hcl
# and run: terraform init -backend-config=../../backends/platform.hcl
terraform {
  backend "azurerm" {
    use_azuread_auth = true
  }
}
