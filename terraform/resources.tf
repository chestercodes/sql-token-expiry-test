
data "azuread_client_config" "current" {}

resource "random_string" "name_part" {
  length  = 10
  special = false
  min_lower = 10
}

resource "random_password" "db_password" {
  length  = 30
  special = true
}

locals {
  res_name = "chesterbtest${random_string.name_part.result}"
}

resource "azurerm_resource_group" "rg" {
  name     = local.res_name
  location = "uksouth"
}

resource "azurerm_mssql_server" "dbserver" {
  name                = local.res_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  version             = "12.0"

  administrator_login          = "chesterb"
  administrator_login_password = random_password.db_password.result

  azuread_administrator {
    login_username              = azuread_group.dbadmin.display_name
    object_id                   = azuread_group.dbadmin.object_id
    #azuread_authentication_only = true
  }
}

# allows anything in azure to connect
resource "azurerm_mssql_firewall_rule" "allow_app_service_rule" {
  name                = "allow-app-service"
  server_id         = azurerm_mssql_server.dbserver.id
  start_ip_address    = "0.0.0.0"
  #end_ip_address      = "0.0.0.0"
  end_ip_address      = "255.255.255.255"
}

# Create an Azure SQL Database
resource "azurerm_mssql_database" "database" {
  name      = "TheDb"
  server_id = azurerm_mssql_server.dbserver.id
  collation = "SQL_Latin1_General_CP1_CI_AS"
  sku_name  = "S0"
}

# Create an Azure AD group
resource "azuread_group" "dbadmin" {
  display_name     = local.res_name
  owners           = [data.azuread_client_config.current.object_id]
  security_enabled = true
}

# Create the Linux App Service Plan
resource "azurerm_service_plan" "appserviceplan" {
  name                = local.res_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "B1"
}

# Create the web app, pass in the App Service Plan ID
resource "azurerm_linux_web_app" "webapp" {
  name                = local.res_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.appserviceplan.id
  https_only          = true

  site_config {
    minimum_tls_version = "1.2"
  }

  app_settings = {
    ConnectionStrings__TheDb = "Server=tcp:${azurerm_mssql_server.dbserver.fully_qualified_domain_name},1433;Database=TheDb;Authentication=Active Directory Managed Identity;User ID=${azurerm_user_assigned_identity.user_mi.client_id}"
    ApplicationInsights__ConnectionString = azurerm_application_insights.application_insights.connection_string
    # WEBSITE_ENABLE_SYNC_UPDATE_SITE = true
  }
  
  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.user_mi.id
    ]
  }
}

resource "azurerm_user_assigned_identity" "user_mi" {
  location            = azurerm_resource_group.rg.location
  name                = local.res_name
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azuread_group_member" "add_app_mi" {
  group_object_id  = azuread_group.dbadmin.id
  member_object_id = azurerm_user_assigned_identity.user_mi.principal_id
}

resource "azurerm_application_insights" "application_insights" {
  name                = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "other"
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  # lowest number allowed
  retention_in_days = 30
}