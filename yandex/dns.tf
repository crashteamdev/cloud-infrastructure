resource "yandex_dns_zone" "endmake_com" {
  name   = "endmake-com"
  zone   = "endmake.com."
  public = true
}

resource "yandex_dns_zone" "endmake_ru" {
  name   = "endmake-ru"
  zone   = "endmake.ru."
  public = true
}

resource "yandex_dns_recordset" "endmake_com_app_a" {
  zone_id = yandex_dns_zone.endmake_com.id
  name    = "app.endmake.com."
  type    = "A"
  ttl     = 600
  data    = [var.endmake_public_ingress_ipv4]
}

resource "yandex_dns_recordset" "endmake_com_apex_a" {
  zone_id = yandex_dns_zone.endmake_com.id
  name    = "endmake.com."
  type    = "A"
  ttl     = 600
  data    = [var.endmake_public_ingress_ipv4]
}

resource "yandex_dns_recordset" "endmake_com_img_origin_a" {
  zone_id = yandex_dns_zone.endmake_com.id
  name    = "img-origin.endmake.com."
  type    = "A"
  ttl     = 600
  data    = [var.endmake_public_ingress_ipv4]
}

resource "yandex_dns_recordset" "endmake_com_img_cname" {
  zone_id = yandex_dns_zone.endmake_com.id
  name    = "img.endmake.com."
  type    = "CNAME"
  ttl     = 600
  data = [
    var.endmake_image_cdn_provider_cname != null
    ? format("%s.", trimsuffix(var.endmake_image_cdn_provider_cname, "."))
    : "img-origin.endmake.com."
  ]
}
resource "yandex_dns_recordset" "endmake_ru_app_a" {
  zone_id = yandex_dns_zone.endmake_ru.id
  name    = "app.endmake.ru."
  type    = "A"
  ttl     = 600
  data    = [var.endmake_public_ingress_ipv4]
}

resource "yandex_dns_recordset" "endmake_ru_apex_a" {
  zone_id = yandex_dns_zone.endmake_ru.id
  name    = "endmake.ru."
  type    = "A"
  ttl     = 600
  data    = [var.endmake_public_ingress_ipv4]
}
