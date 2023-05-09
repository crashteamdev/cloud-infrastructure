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

variable "pg_dbs" {
  description = ""
}

variable "mongo_dbs" {
  description = ""
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
}

variable "cf_api_token" {
  type      = string
  sensitive = true
}
