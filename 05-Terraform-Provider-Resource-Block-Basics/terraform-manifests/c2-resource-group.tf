# Resource Block
# Create a resource group
resource "azurerm_resource_group" "myrg" {
  name = "myrg-1"
  location = "East US"
}
resource "azurerm_resource_group" "myrg-2" {
  name = "myrg-2"
  location = "East US"
}