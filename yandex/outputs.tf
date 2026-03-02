output "endmake_s3_endpoint" {
  value = "https://storage.yandexcloud.net"
}

output "endmake_s3_region" {
  value = "ru-central1"
}

output "endmake_s3_bucket" {
  value = yandex_storage_bucket.endmake.bucket
}

output "endmake_s3_access_key_id" {
  value = yandex_iam_service_account_static_access_key.endmake_storage.access_key
}

output "endmake_s3_secret_access_key" {
  value     = yandex_iam_service_account_static_access_key.endmake_storage.secret_key
  sensitive = true
}
