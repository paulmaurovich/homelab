data "sops_file" "provider-secrets" {
  source_file = "provider-secrets.enc.yaml"
}

data "sops_file" "network-secrets" {
  source_file = "network-secrets.enc.yaml"
}

terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc9"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.3.0"
    }
  }
}

provider "sops" {}

provider "proxmox" {
    pm_api_url = data.sops_file.provider-secrets.data["proxmox.host"]
    pm_api_token_id = data.sops_file.provider-secrets.data["proxmox.api_token_id"]
    pm_api_token_secret = data.sops_file.provider-secrets.data["proxmox.api_token_secret"]
}
