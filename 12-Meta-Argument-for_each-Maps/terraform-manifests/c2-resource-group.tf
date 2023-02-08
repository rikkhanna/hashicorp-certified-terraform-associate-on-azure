resource "azurerm_resource_group" "myrg" {
  for_each = {
    "dc1apps" = "eastus"
    "dc2apps" = "eastus2"
    "dc3apps" = "westus"
  }
  name = "${each.key}-rg"
  location = each.value
}