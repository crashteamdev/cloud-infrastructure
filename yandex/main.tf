locals {
  k8s_version = "1.22"
}

resource "yandex_vpc_network" "network-1" { name = "analytics" }

resource "yandex_vpc_subnet" "subnet-1" {
  v4_cidr_blocks = ["10.1.2.0/24"]
  name           = "analytics-subnet"
  zone           = var.yc_region
  network_id     = yandex_vpc_network.network-1.id
}

resource "yandex_iam_service_account" "marketdb-tf" {
  name        = "marketdb-tf"
  description = "service account for terraform"
}

resource "yandex_resourcemanager_folder_iam_member" "editor" {
  folder_id = var.yc_folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.marketdb-tf.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s-clusters-agent" {
  folder_id = var.yc_folder_id
  role      = "k8s.clusters.agent"
  member    = "serviceAccount:${yandex_iam_service_account.marketdb-tf.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "vpc-public-admin" {
  folder_id = var.yc_folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.marketdb-tf.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "images-puller" {
  folder_id = var.yc_folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.marketdb-tf.id}"
}

resource "yandex_kms_symmetric_key" "kms-key" {
  name              = "kms-key"
  default_algorithm = "AES_128"
  rotation_period   = "8760h"
}

resource "yandex_vpc_subnet" "pg-a" {
  name           = "pgnet-a"
  zone           = var.yc_region
  network_id     = yandex_vpc_network.network-1.id
  v4_cidr_blocks = ["10.1.0.0/24"]
}

resource "yandex_vpc_subnet" "redis-a" {
  name           = "redisnet-a"
  zone           = var.yc_region
  network_id     = yandex_vpc_network.network-1.id
  v4_cidr_blocks = ["10.2.0.0/24"]
}

resource "yandex_vpc_subnet" "mongo-a" {
  name           = "mongonet-a"
  zone           = var.yc_region
  network_id     = yandex_vpc_network.network-1.id
  v4_cidr_blocks = ["10.3.0.0/24"]
}

resource "yandex_kms_symmetric_key_iam_binding" "viewer" {
  symmetric_key_id = yandex_kms_symmetric_key.kms-key.id
  role             = "viewer"
  members = [
    "serviceAccount:${yandex_iam_service_account.marketdb-tf.id}",
  ]
}

resource "yandex_vpc_security_group" "k8s-public-services" {
  name        = "k8s-public-services"
  description = "Правила группы разрешают подключение к сервисам из интернета"
  network_id  = yandex_vpc_network.network-1.id
  ingress {
    protocol          = "TCP"
    description       = "Правило разрешает проверки доступности с диапазона адресов балансировщика нагрузки. Нужно для работы отказоустойчивого кластера и сервисов балансировщика."
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol          = "ANY"
    description       = "Правило разрешает взаимодействие мастер-узел и узел-узел внутри группы безопасности."
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol       = "ANY"
    description    = "Правило разрешает взаимодействие под-под и сервис-сервис. Укажите подсети вашего кластера и сервисов."
    v4_cidr_blocks = concat(yandex_vpc_subnet.subnet-1.v4_cidr_blocks, yandex_vpc_subnet.subnet-1.v4_cidr_blocks, yandex_vpc_subnet.subnet-1.v4_cidr_blocks)
    from_port      = 0
    to_port        = 65535
  }
  ingress {
    protocol       = "ICMP"
    description    = "Правило разрешает отладочные ICMP-пакеты из внутренних подсетей."
    v4_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }
  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает входящий трафик из интернета на диапазон портов NodePort. Добавьте или измените порты на нужные вам."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }
  egress {
    protocol       = "ANY"
    description    = "Правило разрешает весь исходящий трафик. Узлы могут связаться с Yandex Container Registry, Yandex Object Storage, Docker Hub и т. д."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_kubernetes_cluster" "prod_cluster" {
  network_id = yandex_vpc_network.network-1.id
  master {
    version = local.k8s_version
    zonal {
      zone      = yandex_vpc_subnet.subnet-1.zone
      subnet_id = yandex_vpc_subnet.subnet-1.id
    }
    security_group_ids = [yandex_vpc_security_group.k8s-public-services.id]
  }
  service_account_id      = yandex_iam_service_account.marketdb-tf.id
  node_service_account_id = yandex_iam_service_account.marketdb-tf.id
  depends_on = [
    yandex_resourcemanager_folder_iam_member.editor,
    yandex_resourcemanager_folder_iam_member.images-puller
  ]
  kms_provider {
    key_id = yandex_kms_symmetric_key.kms-key.id
  }
}

resource "yandex_kubernetes_node_group" "prod-marketdb-group" {
  cluster_id = yandex_kubernetes_cluster.prod_cluster.id
  name       = "analytics"
  version    = "1.20"

  instance_template {
    platform_id = "standard-v1"

    network_interface {
      nat        = true
      subnet_ids = [yandex_vpc_subnet.subnet-1.id]
    }

    resources {
      memory = 8
      cores  = 4
    }

    boot_disk {
      type = "network-hdd"
      size = 30
    }
  }

  scale_policy {
    auto_scale {
      min     = 1
      max     = 2
      initial = 1
    }
  }

  allocation_policy {
    location {
      zone = var.yc_region
    }
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true

    maintenance_window {
      day        = "monday"
      start_time = "15:00"
      duration   = "3h"
    }

    maintenance_window {
      day        = "friday"
      start_time = "10:00"
      duration   = "4h30m"
    }
  }
}

resource "yandex_mdb_postgresql_cluster" "pg_cluster" {
  name        = "pg_prod"
  description = "main database"
  environment = "PRODUCTION"
  network_id  = yandex_vpc_network.network-1.id
  folder_id   = var.yc_folder_id

  config {
    version = "14"
    resources {
      resource_preset_id = "s2.micro"
      disk_size          = 10
      disk_type_id       = "network-ssd"
    }

    postgresql_config = {
      max_connections                   = 400
      enable_parallel_hash              = true
      vacuum_cleanup_index_scale_factor = 0.2
      autovacuum_vacuum_scale_factor    = 0.32
      default_transaction_isolation     = "TRANSACTION_ISOLATION_READ_UNCOMMITTED"
      shared_preload_libraries          = "SHARED_PRELOAD_LIBRARIES_AUTO_EXPLAIN,SHARED_PRELOAD_LIBRARIES_PG_HINT_PLAN"
    }

    pooler_config {
      pool_discard = true
      pooling_mode = "SESSION"
    }
  }

  host {
    zone      = var.yc_region
    subnet_id = yandex_vpc_subnet.pg-a.id
  }
}

resource "yandex_mdb_postgresql_user" "pg_user" {
  cluster_id = yandex_mdb_postgresql_cluster.pg_cluster.id
  name       = "dbuser"
  password   = var.db_password
  conn_limit = 50
  settings = {
    default_transaction_isolation = "read committed"
    log_min_duration_statement    = 5000
  }
}

resource "yandex_mdb_postgresql_database" "pb_database" {
  for_each   = toset(var.pg_dbs)
  cluster_id = yandex_mdb_postgresql_cluster.pg_cluster.id
  name       = each.key
  owner      = yandex_mdb_postgresql_user.pg_user.name
  lc_collate = "en_US.UTF-8"
  lc_type    = "en_US.UTF-8"
  extension {
    name = "uuid-ossp"
  }
  extension {
    name = "xml2"
  }
  extension {
    name = "pg_trgm"
  }
}

resource "yandex_mdb_redis_cluster" "redis_database" {
  name        = "redis_prod"
  environment = "PRODUCTION"
  network_id  = yandex_vpc_network.network-1.id
  folder_id   = var.yc_folder_id

  config {
    password = var.db_password
    version  = "7.0"
  }

  resources {
    resource_preset_id = "hm1.nano"
    disk_size          = 8
  }

  host {
    zone      = var.yc_region
    subnet_id = yandex_vpc_subnet.redis-a.id
  }

  maintenance_window {
    type = "ANYTIME"
  }
}

resource "yandex_mdb_mongodb_cluster" "mongodb_database" {
  name        = "marketdb"
  environment = "PRODUCTION"
  network_id  = yandex_vpc_network.network-1.id

  cluster_config {
    version = "6.0"
  }

  dynamic "database" {
    for_each = var.mongo_dbs
    content {
      name = database.value
    }
  }

  user {
    name     = "dbuser"
    password = var.db_password
    dynamic "permission" {
      for_each = var.mongo_dbs
      content {
        database_name = permission.value
      }
    }
  }

  resources {
    resource_preset_id = "m3-c2-m16"
    disk_type_id       = "network-ssd"
    disk_size          = 200
  }

  host {
    zone_id   = "ru-central1-a"
    subnet_id = yandex_vpc_subnet.mongo-a.id
  }

  maintenance_window {
    type = "ANYTIME"
  }
}
