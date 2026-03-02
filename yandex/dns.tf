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

resource "yandex_dns_recordset" "endmake_ru_app_a" {
  zone_id = yandex_dns_zone.endmake_ru.id
  name    = "app.endmake.ru."
  type    = "A"
  ttl     = 600
  data    = [var.endmake_public_ingress_ipv4]
}
