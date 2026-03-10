resource "yandex_iam_service_account" "endmake_storage" {
  name        = "endmake-storage"
  description = "Service account for endmake object storage"
}

resource "yandex_resourcemanager_folder_iam_member" "endmake_storage_editor" {
  folder_id = var.yc_folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.endmake_storage.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "endmake_storage_admin" {
  folder_id = var.yc_folder_id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.endmake_storage.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "github_deploy_storage_admin" {
  folder_id = var.yc_folder_id
  role      = "storage.admin"
  member    = "serviceAccount:ajevao7t27aim25olhi1"
}

resource "yandex_iam_service_account_static_access_key" "endmake_storage" {
  service_account_id = yandex_iam_service_account.endmake_storage.id
  description        = "Static access key for endmake object storage"
}

resource "yandex_storage_bucket" "endmake" {
  depends_on = [
    yandex_resourcemanager_folder_iam_member.endmake_storage_editor,
    yandex_resourcemanager_folder_iam_member.endmake_storage_admin
  ]

  access_key    = yandex_iam_service_account_static_access_key.endmake_storage.access_key
  secret_key    = yandex_iam_service_account_static_access_key.endmake_storage.secret_key
  bucket        = "endmake-${var.yc_folder_id}"
  acl           = "private"
  force_destroy = false

  tags = {
    service    = "endmake"
    managed-by = "terraform"
  }
}
