terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
      version = "0.88.0"
    }
  }

  backend "s3" {
    endpoint = "storage.yandexcloud.net"
    bucket = "marketdb-tf-state"
    region = "ru-central1"

    skip_region_validation = true
    skip_credentials_validation = true
  }
}

provider "yandex" {
  zone = var.ya_region
  cloud_id = var.ya_cloud_id
  folder_id = var.ya_folder_id
}
