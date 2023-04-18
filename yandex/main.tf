locals {
  k8s_version = "1.22"
}

resource "yandex_iam_service_account" "marketdb-tf" {
  name        = "marketdb-tf"
  description = "service account for terraform"
}
