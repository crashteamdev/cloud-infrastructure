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

output "endmake_image_cdn_cname" {
  value = yandex_cdn_resource.endmake_img.cname
}

output "endroom_www_bucket" {
  value = "www.endroom.dev"
}

output "endroom_certificate_id" {
  value = coalesce(
    var.endroom_existing_cm_certificate_id,
    try(yandex_cm_certificate.endroom[0].id, null)
  )
}

output "endroom_cdn_resource_id" {
  value = try(yandex_cdn_resource.endroom_www[0].id, null)
}

output "endroom_cdn_provider_cname" {
  value = var.endroom_cdn_provider_cname
}
