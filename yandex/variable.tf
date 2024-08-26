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

variable "yc_debian_image_id" {
  default = "fd8987mnac4uroc0d16s"
  type = string
}

variable "pg_dbs" {
  description = ""
}

variable "clickhouse_dbs" {
  description = ""
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
}
