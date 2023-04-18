locals {
  k8s_version = "1.22"
}

resource "yandex_vpc_network" "network-1" {
  name = "analytics"
}
