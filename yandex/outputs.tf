output "endmake_s3_endpoint" {
  value = "https://storage.yandexcloud.net"
}

output "endmake_ingress_ipv4" {
  value = yandex_vpc_address.endmake_ingress.external_ipv4_address[0].address
}

output "postgresql_host" {
  value = yandex_mdb_postgresql_cluster.pg_cluster.host[0].fqdn
}

output "postgresql_user" {
  value = yandex_mdb_postgresql_user.pg_user.name
}

output "redis_host" {
  value = yandex_mdb_redis_cluster.redis_mdb_database.host[0].fqdn
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
  value = coalesce(var.endmake_image_cdn_provider_cname, "img-origin.endmake.com")
}

output "endmake_image_cdn_resource_id" {
  value = yandex_cdn_resource.endmake_img.id
}

output "endroom_www_bucket" {
  value = yandex_storage_bucket.endroom_www.bucket
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
