resource "yandex_cm_certificate" "endmake_img" {
  name        = "endmake-img-endmake-com"
  description = "Managed certificate for Endmake image CDN"
  domains     = ["img.endmake.com"]

  managed {
    challenge_type = "DNS_CNAME"
  }
}

resource "yandex_dns_recordset" "endmake_com_img_cert_validation" {
  zone_id = yandex_dns_zone.endmake_com.id
  name    = format("%s.", trimsuffix(yandex_cm_certificate.endmake_img.challenges[0].dns_name, "."))
  type    = yandex_cm_certificate.endmake_img.challenges[0].dns_type
  ttl     = 60
  data    = [yandex_cm_certificate.endmake_img.challenges[0].dns_value]
}

data "yandex_cm_certificate" "endmake_img_validated" {
  depends_on      = [yandex_dns_recordset.endmake_com_img_cert_validation]
  certificate_id  = yandex_cm_certificate.endmake_img.id
  wait_validation = true
}

resource "yandex_cdn_origin_group" "endmake_img" {
  name     = "endmake-img-origin"
  use_next = true

  origin {
    source  = "img-origin.endmake.com"
    enabled = true
  }
}

resource "yandex_cdn_resource" "endmake_img" {
  active          = true
  origin_group_id = yandex_cdn_origin_group.endmake_img.id
  origin_protocol = "https"

  secondary_hostnames = [
    "img.endmake.com"
  ]

  options {
    browser_cache_settings = 3600
    edge_cache_settings    = 86400
    fetched_compressed     = true
    forward_host_header    = false
    gzip_on                = true
    ignore_cookie          = true
    ignore_query_params    = false
    custom_host_header     = "img-origin.endmake.com"
    custom_server_name     = "img-origin.endmake.com"
  }

  ssl_certificate {
    type                   = "certificate_manager"
    certificate_manager_id = data.yandex_cm_certificate.endmake_img_validated.id
  }
}
