resource "azurerm_resource_group" "My_RG" {
  name     = var.RG_name
  location = var.RG_location
}

resource "azurerm_virtual_network" "My_Vnet" {
  name                = var.Vnet_name
  resource_group_name = var.RG_name
  location            = var.RG_location
  address_space       = ["10.250.0.0/16"]
}

resource "azurerm_subnet" "frontend" {
  name                 = "subnet"
  resource_group_name  = var.RG_name
  virtual_network_name = var.Vnet_name
  address_prefixes     = ["10.250.2.0/24"]
}

resource "azurerm_subnet" "VM_subnet" {
  name                 = "VM_subnet"
  resource_group_name  = var.RG_name
  virtual_network_name = var.Vnet_name
  address_prefixes     = ["10.250.3.0/24"]
}

resource "azurerm_network_interface" "VM_interface" {
  name                = "VM_interface"
  location            = var.RG_location
  resource_group_name = var.RG_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.VM_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "Virtual_Machine" {
  name                = "Virtual_Machine"
  resource_group_name = var.RG_name
  location            = var.RG_location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.VM_interface.id,
  ]
  admin_password = "adminpass"
 
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  connection {
    type = "ssh"
    user = "adminuser"
    password = "adminpass"
    host = azurerm_lb.TestLoadBalancer.private_ip_address
  }
  provisioner "remote-exec" {
    inline = [ "$ docker run -P -d nginxdemos/hello" ]
  }

}




################## Application Gateway ####################


resource "azurerm_subnet" "appgtw_subnet" {
  name                 = "Azurefirewallsubnet"
  resource_group_name  = var.RG_name
  virtual_network_name = var.Vnet_name
  address_prefixes     = ["10.250.1.0/24"]
}

resource "azurerm_public_ip" "Appgtw_public_ip" {
  name                = "Apgw_public_ip"
  resource_group_name = var.RG_name
  location            = var.RG_location
  allocation_method   = "Dynamic"
}

resource "azurerm_web_application_firewall_policy" "wafpolicy" {
  name                = "wafpolicy"
  resource_group_name = var.RG_name
  location            = var.RG_location

  policy_settings {
    enabled = true
    mode = "Prevention"
    request_body_check = true
    file_upload_limit_in_mb = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type = "OWASP"
      version = "3.2"
    }
  }
}

resource "azurerm_application_gateway" "My_Appgtw" {
  name                = "My_Appgtw"
  resource_group_name = var.RG_name
  location            = var.RG_location

  sku {
    name     = "Standard_Small"
    tier     = "Standard"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.frontend.id
  }

  frontend_port {
    name = "frontend_port_name"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend_ip_configuration_name"
    public_ip_address_id = azurerm_public_ip.Appgtw_public_ip.id
  }

  backend_address_pool {
    name = "backend_address_pool_name"
    ip_addresses = azurerm_lb.TestLoadBalancer.frontend_ip_configuration.address1
  }



  backend_http_settings {
    name                  = "http_setting_name"
    cookie_based_affinity = "Disabled"
    path                  = "/path1/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "listener_name"
    frontend_ip_configuration_name = "frontend_ip_configuration_name"
    frontend_port_name             = "frontend_port_name"
    protocol                       = "Http"
    firewall_policy_id = azurerm_web_application_firewall_policy.wafpolicy.id
  }

  request_routing_rule {
    name                       = "request_routing_rule_name"
    rule_type                  = "Basic"
    http_listener_name         = "listener_name"
    backend_address_pool_name  = "backend_address_pool_name"
    backend_http_settings_name = "http_setting_name"
  }
}

####################### Internal LB ###############



resource "azurerm_lb" "TestLoadBalancer" {
  name                = "TestLoadBalancer"
  location            = var.RG_location
  resource_group_name = var.RG_name

  frontend_ip_configuration {
    name                 = "PrivateIPAddress"
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_backend_address_pool" "BackEndAddressPool" {
  loadbalancer_id = azurerm_lb.TestLoadBalancer.id
  name            = "BackEndAddressPool"
}

resource "azurerm_lb_backend_address_pool_address" "address1" {
  name                                = "address1"
  backend_address_pool_id             = azurerm_lb_backend_address_pool.BackEndAddressPool.id
  backend_address_ip_configuration_id = azurerm_linux_virtual_machine.Virtual_Machine.id
}

resource "azurerm_lb_probe" "probe1" {
  loadbalancer_id = azurerm_lb.TestLoadBalancer.id
  name            = "probe1"
  port            = 22
}

resource "azurerm_lb_probe" "probe2" {
  loadbalancer_id = azurerm_lb.TestLoadBalancer.id
  name            = "probe2"
  port            = 80
}

resource "azurerm_lb_rule" "LBRule1" {
  loadbalancer_id                = azurerm_lb.TestLoadBalancer.id
  name                           = "LBRule1"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PrivateIPAddress"
  probe_id                       = azurerm_lb_probe.probe2
}

resource "azurerm_lb_rule" "LBRule2" {
  loadbalancer_id                = azurerm_lb.TestLoadBalancer.id
  name                           = "LBRule2"
  protocol                       = "Tcp"
  frontend_port                  = 22
  backend_port                   = 22
  frontend_ip_configuration_name = "PrivateIPAddress"
  probe_id                       = azurerm_lb_probe.probe1
}
