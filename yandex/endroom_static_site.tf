variable "endroom_existing_cm_certificate_id" {
  description = "Existing Yandex Certificate Manager certificate ID for endroom.dev and www.endroom.dev. Leave null to let Terraform request a managed certificate."
  type        = string
  default     = null
  nullable    = true
}

variable "endroom_enable_cdn_resources" {
  description = "Create the Yandex Cloud CDN origin group and resource for www.endroom.dev."
  type        = bool
  default     = false
}

variable "endroom_enable_www_cutover" {
  description = "Point www.endroom.dev to the CDN provider CNAME instead of the current Object Storage website endpoint."
  type        = bool
  default     = false
}

variable "endroom_enable_apex_redirect" {
  description = "Switch the imported endroom.dev bucket from website hosting to a permanent redirect toward https://www.endroom.dev."
  type        = bool
  default     = false
}

variable "endroom_cdn_provider_cname" {
  description = "Provider CNAME returned by Yandex Cloud CDN for www.endroom.dev. Required only when enabling the www cutover with the pinned provider version."
  type        = string
  default     = null
  nullable    = true
}

variable "endroom_enable_origin_lockdown" {
  description = "Apply the restrictive origin bucket policy only after CDN and DNS cutover are complete."
  type        = bool
  default     = false
}

locals {
  endroom_zone_name           = "endroom-dev"
  endroom_root_domain         = "endroom.dev"
  endroom_www_domain          = "www.endroom.dev"
  endroom_certificate_domains = [local.endroom_root_domain, local.endroom_www_domain]
  endroom_root_bucket_name    = local.endroom_root_domain
  endroom_www_bucket_name     = local.endroom_www_domain
  endroom_bucket_max_size     = 10737418240
  endroom_root_website_host   = "${local.endroom_root_bucket_name}.website.yandexcloud.net"
  endroom_root_website_target = "${local.endroom_root_website_host}."
  endroom_www_website_host    = "${local.endroom_www_bucket_name}.website.yandexcloud.net"
  endroom_www_website_target  = "${local.endroom_www_website_host}."

  endroom_certificate_id = coalesce(
    var.endroom_existing_cm_certificate_id,
    try(yandex_cm_certificate.endroom[0].id, null)
  )

  endroom_cdn_public_nets = distinct(concat(
    try(jsondecode(data.http.endroom_cdn_public_nets.response_body).addresses, []),
    try(jsondecode(data.http.endroom_cdn_public_nets.response_body).addresses_v6, [])
  ))
}

import {
  to = yandex_storage_bucket.endroom_root
  id = "endroom.dev"
}

data "http" "endroom_cdn_public_nets" {
  url = "https://api.edgecenter.ru/cdn/public_net_list"

  request_headers = {
    Accept = "application/json"
  }
}

resource "yandex_dns_zone" "endroom_dev" {
  name   = local.endroom_zone_name
  zone   = "${local.endroom_root_domain}."
  public = true
}

resource "yandex_cm_certificate" "endroom" {
  count = var.endroom_existing_cm_certificate_id == null ? 1 : 0

  name    = "endroom-dev-cdn"
  domains = local.endroom_certificate_domains

  managed {
    challenge_type  = "DNS_CNAME"
    challenge_count = length(local.endroom_certificate_domains)
  }
}

resource "yandex_dns_recordset" "endroom_certificate_validation" {
  count = var.endroom_existing_cm_certificate_id == null ? length(local.endroom_certificate_domains) : 0

  zone_id = yandex_dns_zone.endroom_dev.id
  name    = yandex_cm_certificate.endroom[0].challenges[count.index].dns_name
  type    = yandex_cm_certificate.endroom[0].challenges[count.index].dns_type
  ttl     = 60
  data    = [yandex_cm_certificate.endroom[0].challenges[count.index].dns_value]
}

resource "yandex_storage_bucket" "endroom_root" {
  bucket        = local.endroom_root_bucket_name
  force_destroy = false
  max_size      = local.endroom_bucket_max_size

  anonymous_access_flags {
    read        = true
    list        = false
    config_read = false
  }

  dynamic "website" {
    for_each = var.endroom_enable_apex_redirect ? [] : [1]

    content {
      index_document = "index.html"
      error_document = "404.html"
    }
  }

  dynamic "website" {
    for_each = var.endroom_enable_apex_redirect ? [1] : []

    content {
      redirect_all_requests_to = "https://${local.endroom_www_domain}"
    }
  }

  dynamic "https" {
    for_each = var.endroom_enable_apex_redirect && local.endroom_certificate_id != null ? [1] : []

    content {
      certificate_id = local.endroom_certificate_id
    }
  }

  lifecycle {
    precondition {
      condition     = !var.endroom_enable_apex_redirect || local.endroom_certificate_id != null
      error_message = "Enable apex redirect only after a Yandex Certificate Manager certificate is available."
    }
  }
}

resource "yandex_storage_bucket" "endroom_www" {
  bucket        = local.endroom_www_bucket_name
  force_destroy = false
  max_size      = local.endroom_bucket_max_size
  policy = var.endroom_enable_origin_lockdown ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowGetObjectFromCloudCDN"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = ["arn:aws:s3:::${local.endroom_www_bucket_name}/*"]
        Condition = {
          IpAddress = {
            "aws:SourceIp" = local.endroom_cdn_public_nets
          }
        }
      }
    ]
  }) : null

  anonymous_access_flags {
    read        = !var.endroom_enable_origin_lockdown
    list        = false
    config_read = false
  }

  website {
    index_document = "index.html"
    error_document = "404.html"
  }
}

resource "yandex_cdn_origin_group" "endroom_www" {
  count = var.endroom_enable_cdn_resources ? 1 : 0

  name = "endroom-www"

  origin {
    source  = local.endroom_www_website_host
    enabled = true
  }
}

resource "yandex_cdn_resource" "endroom_www" {
  count = var.endroom_enable_cdn_resources ? 1 : 0

  cname           = local.endroom_www_domain
  active          = true
  origin_group_id = yandex_cdn_origin_group.endroom_www[0].id
  origin_protocol = "http"

  ssl_certificate {
    type                   = "certificate_manager"
    certificate_manager_id = local.endroom_certificate_id
  }

  options {
    browser_cache_settings = 600
    custom_host_header     = local.endroom_www_website_host
    edge_cache_settings    = 3600
    gzip_on                = true
    redirect_http_to_https = true
  }

  depends_on = [yandex_dns_recordset.endroom_certificate_validation]

  lifecycle {
    precondition {
      condition     = local.endroom_certificate_id != null
      error_message = "Create or provide a certificate before enabling the CDN resource."
    }
  }
}

resource "yandex_dns_recordset" "endroom_dev_apex_aname" {
  zone_id = yandex_dns_zone.endroom_dev.id
  name    = "${local.endroom_root_domain}."
  type    = "ANAME"
  ttl     = 600
  data    = [local.endroom_root_website_target]
}

resource "yandex_dns_recordset" "endroom_dev_www_cname" {
  zone_id = yandex_dns_zone.endroom_dev.id
  name    = "${local.endroom_www_domain}."
  type    = "CNAME"
  ttl     = 600
  data = [
    var.endroom_enable_www_cutover
    ? format("%s.", trimsuffix(var.endroom_cdn_provider_cname, "."))
    : local.endroom_root_website_target
  ]

  lifecycle {
    precondition {
      condition     = !var.endroom_enable_www_cutover || var.endroom_enable_cdn_resources
      error_message = "Enable CDN resources before cutting www.endroom.dev over to the CDN provider CNAME."
    }

    precondition {
      condition     = !var.endroom_enable_www_cutover || var.endroom_cdn_provider_cname != null
      error_message = "Set endroom_cdn_provider_cname to the CDN target returned by Yandex Cloud before enabling the www DNS cutover."
    }
  }
}
