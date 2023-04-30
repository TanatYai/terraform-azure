terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "=3.0.0"
        }
    }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
    features {}
}

# resource "azurerm_resource_group" "resource-group" {
#   name     = "rg-tanat-dev"
#   location = "Southeast asia"
# }

variable "resource-group" {
    default = "rg-github-dev"
}

variable "location" {
    default = "Japan east"
}

resource "azurerm_virtual_network" "vnet" {
    name                = "vnet-tan-dev"
    resource_group_name = var.resource-group
    location            = var.location
    address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "frontend" {
    name                 = "snet-public-tan-dev"
    resource_group_name  = var.resource-group
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "backend" {
    name                 = "snet-private-tan-dev"
    resource_group_name  = var.resource-group
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "pip" {
    name                = "pip-tan-dev"
    resource_group_name = var.resource-group
    location            = var.location
    allocation_method   = "Static"
    sku                 = "Standard"
}

locals {
    backend_address_pool_name      = "${azurerm_virtual_network.vnet.name}-beap"
    frontend_port_name             = "${azurerm_virtual_network.vnet.name}-feport"
    frontend_ip_configuration_name = "${azurerm_virtual_network.vnet.name}-feip"
    http_setting_name              = "${azurerm_virtual_network.vnet.name}-be-htst"
    listener_name                  = "${azurerm_virtual_network.vnet.name}-httplstn"
    request_routing_rule_name      = "${azurerm_virtual_network.vnet.name}-rqrt"
    redirect_configuration_name    = "${azurerm_virtual_network.vnet.name}-rdrcfg"
}

resource "azurerm_application_gateway" "network" {
    name                = "agw-tan-dev"
    resource_group_name = var.resource-group
    location            = var.location

    sku {
        name            = "WAF_v2"
        tier            = "WAF_v2"
        capacity        = 1
    }

    gateway_ip_configuration {
        name            = "ip-config-dev"
        subnet_id       = azurerm_subnet.frontend.id
    }

    frontend_port {
        name            = local.frontend_port_name
        port            = 80
    }

    frontend_ip_configuration {
        name                 = local.frontend_ip_configuration_name
        public_ip_address_id = azurerm_public_ip.pip.id
    }

    backend_address_pool {
        name = local.backend_address_pool_name
    }

    backend_http_settings {
        name                  = local.http_setting_name
        cookie_based_affinity = "Disabled"
        port                  = 80
        protocol              = "Http"
        request_timeout       = 60
    }

    http_listener {
        name                           = local.listener_name
        frontend_ip_configuration_name = local.frontend_ip_configuration_name
        frontend_port_name             = local.frontend_port_name
        protocol                       = "Http"
    }

    request_routing_rule {
        name                       = local.request_routing_rule_name
        rule_type                  = "Basic"
        http_listener_name         = local.listener_name
        backend_address_pool_name  = local.backend_address_pool_name
        backend_http_settings_name = local.http_setting_name
    }
}

resource "azurerm_network_security_group" "nsg" {
    name                = "nsg-tan-dev"
    location            = var.location
    resource_group_name = var.resource-group

    security_rule {
        name                       = "sr-tan-dev"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

resource "azurerm_container_registry" "acr" {
    name                = "acrtandev"
    resource_group_name = var.resource-group
    location            = var.location
    sku                 = "Basic"
}

resource "azurerm_service_plan" "asp" {
    name                = "asp-tan-dev"
    resource_group_name = var.resource-group
    location            = var.location
    os_type             = "Linux"
    sku_name            = "B2"
}

resource "azurerm_linux_web_app" "webapp" {
    name                = "ase-tan-web-dev"
    resource_group_name = var.resource-group
    location            = var.location
    service_plan_id     = azurerm_service_plan.asp.id

    site_config {
        always_on = true
        container_registry_use_managed_identity = true
        application_stack {
            docker_image     = "${azurerm_container_registry.acr.name}.azurecr.io/web-dev/web"
            docker_image_tag = "latest"
        }
    }
    app_settings = {
        DOCKER_REGISTRY_SERVER_URL = "https://${azurerm_container_registry.acr.name}.azurecr.io"
    }
}

resource "azurerm_linux_web_app" "webapi" {
    name                = "ase-tan-api-dev"
    resource_group_name = var.resource-group
    location            = var.location
    service_plan_id     = azurerm_service_plan.asp.id

    site_config {
        always_on = true
        container_registry_use_managed_identity = true
        application_stack {
            docker_image     = "${azurerm_container_registry.acr.name}.azurecr.io/api-dev/api"
            docker_image_tag = "latest"
        }
    }
    app_settings = {
        DOCKER_REGISTRY_SERVER_URL = "https://${azurerm_container_registry.acr.name}.azurecr.io"
    }
}

resource "azurerm_storage_account" "staccount" {
    name                     = "sttandev"
    resource_group_name      = var.resource-group
    location                 = var.location
    account_tier             = "Standard"
    account_replication_type = "LRS"
}

resource "azurerm_postgresql_server" "psql" {
    name                             = "psql-tan-dev"
    location                         = var.location
    resource_group_name              = var.resource-group

    administrator_login              = "psqladmin"
    administrator_login_password     = "p2ql@dm!n"

    sku_name                         = "B_Gen5_2"
    version                          = "11"
    storage_mb                       = 5120

    backup_retention_days            = 7
    geo_redundant_backup_enabled     = false
    auto_grow_enabled                = false

    public_network_access_enabled    = true
    ssl_enforcement_enabled          = true
    ssl_minimal_tls_version_enforced = "TLS1_2"
}

resource "azurerm_postgresql_database" "dbpsql" {
    name                = "dbpsql-tan-dev"
    resource_group_name = var.resource-group
    server_name         = azurerm_postgresql_server.psql.name
    charset             = "UTF8"
    collation           = "en-GB"
}

resource "azurerm_api_management" "apim" {
    name                = "apim-tan-dev"
    location            = var.location
    resource_group_name = var.resource-group
    publisher_name      = "api-dev"
    publisher_email     = "tan@manaosoftware.com"

    sku_name            = "Consumption_0"
}