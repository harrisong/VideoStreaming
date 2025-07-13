# Hetzner Cloud Module for Video Streaming Service

terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}

# Variables
variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "server_count" {
  description = "Number of servers to create"
  type        = number
  default     = 1
}

variable "server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cpx21"
}

variable "region" {
  description = "Hetzner region"
  type        = string
  default     = "nbg1"
}

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
}

variable "enable_load_balancer" {
  description = "Enable load balancer"
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Enable monitoring"
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Data sources
data "hcloud_image" "ubuntu" {
  name = "ubuntu-22.04"
}

# SSH Key
resource "hcloud_ssh_key" "default" {
  name       = "${var.environment}-video-streaming-key"
  public_key = var.ssh_public_key
  labels     = var.common_tags
}

# Network
resource "hcloud_network" "main" {
  name     = "${var.environment}-video-streaming-network"
  ip_range = "10.0.0.0/16"
  labels   = var.common_tags
}

resource "hcloud_network_subnet" "main" {
  type         = "cloud"
  network_id   = hcloud_network.main.id
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

# Firewall
resource "hcloud_firewall" "web" {
  name   = "${var.environment}-video-streaming-firewall"
  labels = var.common_tags

  rule {
    direction = "in"
    port      = "22"
    protocol  = "tcp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    port      = "80"
    protocol  = "tcp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    port      = "443"
    protocol  = "tcp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # Internal communication
  rule {
    direction = "in"
    port      = "any"
    protocol  = "tcp"
    source_ips = [
      "10.0.0.0/16"
    ]
  }

  rule {
    direction = "in"
    port      = "any"
    protocol  = "udp"
    source_ips = [
      "10.0.0.0/16"
    ]
  }
}

# Cloud-init script for server setup
locals {
  cloud_init = base64encode(templatefile("${path.module}/cloud-init.yml", {
    domain_name = var.domain_name
    environment = var.environment
  }))
}

# Servers
resource "hcloud_server" "app" {
  count       = var.server_count
  name        = "${var.environment}-video-streaming-${count.index + 1}"
  image       = data.hcloud_image.ubuntu.id
  server_type = var.server_type
  location    = var.region
  ssh_keys    = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.web.id]
  user_data   = local.cloud_init
  labels      = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-${count.index + 1}"
    Role = "application"
  })

  network {
    network_id = hcloud_network.main.id
    ip         = "10.0.1.${count.index + 10}"
  }

  depends_on = [
    hcloud_network_subnet.main
  ]
}

# Load Balancer (optional)
resource "hcloud_load_balancer" "main" {
  count              = var.enable_load_balancer ? 1 : 0
  name               = "${var.environment}-video-streaming-lb"
  load_balancer_type = "lb11"
  location           = var.region
  labels             = var.common_tags
}

resource "hcloud_load_balancer_network" "main" {
  count           = var.enable_load_balancer ? 1 : 0
  load_balancer_id = hcloud_load_balancer.main[0].id
  network_id      = hcloud_network.main.id
  ip              = "10.0.1.5"
}

resource "hcloud_load_balancer_target" "app_servers" {
  count            = var.enable_load_balancer ? var.server_count : 0
  type             = "server"
  load_balancer_id = hcloud_load_balancer.main[0].id
  server_id        = hcloud_server.app[count.index].id
  use_private_ip   = true
}

resource "hcloud_load_balancer_service" "web" {
  count            = var.enable_load_balancer ? 1 : 0
  load_balancer_id = hcloud_load_balancer.main[0].id
  protocol         = "http"
  listen_port      = 80
  destination_port = 80

  health_check {
    protocol = "http"
    port     = 80
    interval = 15
    timeout  = 10
    retries  = 3
    http {
      path         = "/health"
      status_codes = ["200"]
    }
  }
}

resource "hcloud_load_balancer_service" "web_ssl" {
  count            = var.enable_load_balancer ? 1 : 0
  load_balancer_id = hcloud_load_balancer.main[0].id
  protocol         = "http"
  listen_port      = 443
  destination_port = 443

  health_check {
    protocol = "http"
    port     = 80
    interval = 15
    timeout  = 10
    retries  = 3
    http {
      path         = "/health"
      status_codes = ["200"]
    }
  }
}

# Volume for persistent storage (optional)
resource "hcloud_volume" "storage" {
  count     = var.server_count
  name      = "${var.environment}-video-streaming-storage-${count.index + 1}"
  size      = 100
  location  = var.region
  labels    = var.common_tags
}

resource "hcloud_volume_attachment" "storage" {
  count     = var.server_count
  volume_id = hcloud_volume.storage[count.index].id
  server_id = hcloud_server.app[count.index].id
  automount = true
}

# Outputs
output "server_ips" {
  description = "Public IP addresses of the servers"
  value       = hcloud_server.app[*].ipv4_address
}

output "server_private_ips" {
  description = "Private IP addresses of the servers"
  value       = hcloud_server.app[*].network[0].ip
}

output "load_balancer_ip" {
  description = "Load balancer public IP"
  value       = var.enable_load_balancer ? hcloud_load_balancer.main[0].ipv4 : null
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to servers"
  value = [
    for i, server in hcloud_server.app : "ssh root@${server.ipv4_address}"
  ]
}

output "server_info" {
  description = "Server information"
  value = {
    for i, server in hcloud_server.app : server.name => {
      id         = server.id
      public_ip  = server.ipv4_address
      private_ip = server.network[0].ip
      type       = server.server_type
      location   = server.location
    }
  }
}
