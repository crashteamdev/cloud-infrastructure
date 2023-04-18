locals {
  k8s_version = "1.22"
}

resource "yandex_vpc_network" "network-1" { name = "analytics" }

resource "yandex_vpc_subnet" "subnet-1" {
  v4_cidr_blocks = ["10.1.2.0/24"]
  name           = "analytics-subnet"
  zone           = var.yc_region
  network_id     = yandex_vpc_network.network-1.id
}

resource "yandex_iam_service_account" "marketdb-tf" {
  name        = "marketdb-tf"
  description = "service account for terraform"
}

