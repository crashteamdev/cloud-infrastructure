variable "yc_region" {
  default = "ru-central1-a"
  type    = string
}

variable "yc_profile" {
  default = "marketdb"
  type    = string
}

variable "yc_cloud_id" {
  default = "b1gtojcphtuae1n9siie"
  type    = string
}

variable "yc_folder_id" {
  default = "b1g90io1nf34fov5esm5"
  type    = string
}

variable "cluster_name" {
  default = "marketdb-cluster"
  type    = string
}

variable "k8s_version" {
  description = "Target Managed Kubernetes version. Upgrade one minor version at a time: 1.31, then 1.32, then 1.33."
  type        = string
  default     = "1.33"

  validation {
    condition     = contains(["1.31", "1.32", "1.33"], var.k8s_version)
    error_message = "k8s_version must be one of 1.31, 1.32, or 1.33."
  }
}

variable "yc_debian_image_id" {
  default = "fd8987mnac4uroc0d16s"
  type    = string
}

variable "pg_dbs" {
  description = ""
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
}

variable "db_dev_password" {
  description = "Database developer password"
  type        = string
  sensitive   = true
}

variable "vm_user_nat" {
  type = string
}

variable "nat_ssh_key_path" {
  type = string
}

variable "endmake_image_cdn_provider_cname" {
  description = "Provider CNAME returned by Yandex Cloud CDN for img.endmake.com. Leave null until the CDN resource is created, then set it to cut DNS over from img-origin.endmake.com to the CDN."
  type        = string
  default     = null
  nullable    = true
}

variable "storage_access_key" {
  description = "Object Storage access key used by the Yandex provider default storage client."
  type        = string
  sensitive   = true
}

variable "storage_secret_key" {
  description = "Object Storage secret key used by the Yandex provider default storage client."
  type        = string
  sensitive   = true
}
