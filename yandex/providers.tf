terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.99.1"
    }
  }

  backend "s3" {
    endpoint = "https://storage.yandexcloud.net"
    bucket   = "marketdb-tf-state"
    region   = "ru-central1"
    key      = "marketdb-tf.tfstate"

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
  }
}

provider "yandex" {
  zone      = var.yc_region
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
}
