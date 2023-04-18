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

variable "pg_dbs" {
  description = ""
}

variable "mongo_dbs" {
  description = ""
}
