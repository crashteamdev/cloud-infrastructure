locals {
  k8s_version = "1.28"
}

resource "yandex_vpc_network" "network-1" { name = "analytics" }

resource "yandex_vpc_subnet" "subnet-microservices" {
  v4_cidr_blocks = ["10.1.1.0/24"]
  name           = "microservices-subnet"
  zone           = var.yc_region
  network_id     = yandex_vpc_network.network-1.id
  route_table_id = yandex_vpc_route_table.nat-instance-route.id
}

resource "yandex_vpc_subnet" "subnet-nat" {
  v4_cidr_blocks = ["10.1.100.0/24"]
  name           = "nat-subnet"
  zone           = var.yc_region
  network_id     = yandex_vpc_network.network-1.id
}

resource "yandex_vpc_subnet" "subnet-service" {
  v4_cidr_blocks = ["10.1.2.0/24"]
  name           = "service-subnet"
  zone           = var.yc_region
  network_id     = yandex_vpc_network.network-1.id
}

resource "yandex_vpc_subnet" "subnet-mng" {
  v4_cidr_blocks = ["10.1.3.0/24"]
  name           = "k8s-cluster"
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

resource "yandex_vpc_subnet" "clickhouse-a" {
  name           = "clickhousenet-a"
  zone           = var.yc_region
  network_id     = yandex_vpc_network.network-1.id
  v4_cidr_blocks = ["10.4.0.0/24"]
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
    v4_cidr_blocks = concat(
      yandex_vpc_subnet.subnet-microservices.v4_cidr_blocks,
      yandex_vpc_subnet.subnet-service.v4_cidr_blocks,
      yandex_vpc_subnet.subnet-mng.v4_cidr_blocks,
    )
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
    description    = "Правило разрешает входящий трафик из интернета на диапазон портов NodePort."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }
  ingress {
    protocol = "TCP"
    description = "Правило для доступа в кластер Kubernetes"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port = 443
    to_port = 443
  }
  ingress {
    protocol = "TCP"
    description = "Правило для доступа в кластер Kubernetes"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port = 6443
    to_port = 6443
  }
  ingress {
    description    = "HTTPS (secure)"
    port           = 8443
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description    = "clickhouse-client (secure)"
    port           = 9440
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol       = "ANY"
    description    = "Правило разрешает весь исходящий трафик. Узлы могут связаться с Yandex Container Registry, Yandex Object Storage, Docker Hub и т. д."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_compute_image" "nat-instance-ubuntu" {
  source_family = "nat-instance-ubuntu"
}

resource "yandex_vpc_security_group" "nat-instance-sg" {
  name       = "nat-instance-sg"
  network_id = yandex_vpc_network.network-1.id

  egress {
    protocol       = "ANY"
    description    = "any"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    description    = "ssh"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "ext-http"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "ext-https"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }
}

resource "yandex_compute_disk" "boot-disk-nat" {
  name     = "boot-disk-nat"
  type     = "network-hdd"
  zone     = "ru-central1-a"
  size     = "20"
  image_id = yandex_compute_image.nat-instance-ubuntu.id
}

resource "yandex_compute_instance" "nat-instance" {
  name        = "nat-instance"
  platform_id = "standard-v3"
  zone        = var.yc_region

  resources {
    core_fraction = 20
    cores         = 2
    memory        = 2
  }

  boot_disk {
    disk_id = yandex_compute_disk.boot-disk-nat.id
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet-nat.id
    security_group_ids = [yandex_vpc_security_group.nat-instance-sg.id]
    nat                = true
  }

  metadata = {
    user-data = "#cloud-config\nusers:\n  - name: ${var.vm_user_nat}\n    groups: sudo\n    shell: /bin/bash\n    sudo: 'ALL=(ALL) NOPASSWD:ALL'\n    ssh-authorized-keys:\n      - ${file("${var.nat_ssh_key_path}")}"
  }
}

resource "yandex_vpc_route_table" "nat-instance-route" {
  name       = "nat-instance-route"
  network_id = yandex_vpc_network.network-1.id
  static_route {
    destination_prefix = "0.0.0.0/0"
    next_hop_address   = yandex_compute_instance.nat-instance.network_interface.0.ip_address
  }
}

resource "yandex_kubernetes_cluster" "prod_cluster" {
  network_id = yandex_vpc_network.network-1.id
  name = var.cluster_name
  master {
    version = local.k8s_version
    public_ip = true
    zonal {
      zone      = yandex_vpc_subnet.subnet-mng.zone
      subnet_id = yandex_vpc_subnet.subnet-mng.id
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

resource "yandex_kubernetes_node_group" "mdb-spot-group" {
  cluster_id = yandex_kubernetes_cluster.prod_cluster.id
  name = "mdb-service-spot"
  version = local.k8s_version
  node_labels = {
    mdb-service = "true"
  }
  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat        = true
      subnet_ids = [yandex_vpc_subnet.subnet-service.id]
    }

    resources {
      memory = 12
      cores  = 4
    }

    boot_disk {
      type = "network-hdd"
      size = 50
    }

    scheduling_policy {
      preemptible = true
    }
  }
  scale_policy {
    fixed_scale {
      size = 3
    }
  }
  deploy_policy {
    max_unavailable = 1
    max_expansion   = 1
  }
  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true

    maintenance_window {
      day        = "monday"
      start_time = "05:00"
      duration   = "2h"
    }
  }
}

resource "yandex_kubernetes_node_group" "mdb-spot-node-group" {
  cluster_id = yandex_kubernetes_cluster.prod_cluster.id
  name = "mdb-spot-group"
  version = local.k8s_version
  node_labels = {
    spot-node = "true"
  }
  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat        = false
      subnet_ids = [yandex_vpc_subnet.subnet-microservices.id]
    }

    resources {
      memory = 12
      cores  = 4
    }

    boot_disk {
      type = "network-hdd"
      size = 30
    }

    scheduling_policy {
      preemptible = true
    }
  }
  scale_policy {
    fixed_scale {
      size = 2
    }
  }
  deploy_policy {
    max_unavailable = 1
    max_expansion   = 1
  }
  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true

    maintenance_window {
      day        = "monday"
      start_time = "05:00"
      duration   = "2h"
    }
  }
}

resource "yandex_kubernetes_node_group" "mdb-sup-service" {
  cluster_id = yandex_kubernetes_cluster.prod_cluster.id
  name       = "mdb-sup-service"
  version    = local.k8s_version

  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat        = true
      subnet_ids = [yandex_vpc_subnet.subnet-service.id]
    }

    resources {
      memory = 2
      cores  = 2
      core_fraction = 20
    }

    boot_disk {
      type = "network-hdd"
      size = 50
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  node_labels = {
    monitoring = "true"
    ingress = "true"
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

resource "yandex_vpc_security_group" "pg_sg" {
  name       = "pg-security-group"
  network_id = yandex_vpc_network.network-1.id

  ingress {
    protocol       = "ANY"
    description    = "Allow PostgreSQL access from service subnet"
    v4_cidr_blocks = [yandex_vpc_subnet.subnet-service.v4_cidr_blocks[0]]
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow PostgreSQL access from any external IP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 6432
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_mdb_postgresql_cluster" "pg_cluster" {
  name        = "pg_prod"
  description = "main database"
  environment = "PRODUCTION"
  network_id  = yandex_vpc_network.network-1.id
  folder_id   = var.yc_folder_id
  security_group_ids = [yandex_vpc_security_group.pg_sg.id]

  config {
    version = "14"
    resources {
      resource_preset_id = "b2.medium"
      disk_size          = 10
      disk_type_id       = "network-ssd"
    }

    postgresql_config = {
      max_connections                   = 200
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
    assign_public_ip = true
  }
}

resource "yandex_mdb_postgresql_user" "pg_user" {
  cluster_id = yandex_mdb_postgresql_cluster.pg_cluster.id
  name       = "dbuser"
  password   = var.db_password
  conn_limit = 100
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

resource "yandex_vpc_security_group" "redis_sg" {
  name       = "redis-security-group"
  network_id = yandex_vpc_network.network-1.id

  ingress {
    protocol       = "ANY"
    description    = "Allow Redis access from service subnet"
    v4_cidr_blocks = [yandex_vpc_subnet.subnet-service.v4_cidr_blocks[0]]
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow Redis access from any external IP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 6380
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_mdb_redis_cluster" "redis_mdb_database" {
  name        = "redis_mdb"
  environment = "PRODUCTION"
  network_id  = yandex_vpc_network.network-1.id
  folder_id   = var.yc_folder_id
  tls_enabled = true
  security_group_ids = [yandex_vpc_security_group.redis_sg.id]

  config {
    password = var.db_password
    version  = "7.2"
  }

  resources {
    resource_preset_id = "b3-c1-m4"
    disk_size          = 16
  }

  host {
    zone      = var.yc_region
    subnet_id = yandex_vpc_subnet.redis-a.id
    assign_public_ip = true
  }

  maintenance_window {
    day  = "SUN"
    hour = 2
    type = "WEEKLY"
  }
}

resource "yandex_vpc_security_group" "clickhouse_sg" {
  name       = "clickhouse-security-group"
  network_id = yandex_vpc_network.network-1.id

  ingress {
    protocol       = "ANY"
    description    = "Allow ClickHouse access from service subnet"
    v4_cidr_blocks = [yandex_vpc_subnet.subnet-service.v4_cidr_blocks[0]]
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow ClickHouse access from any external IP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 8443
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_mdb_clickhouse_cluster" "clickhouse-analytics" {
  name               = "marketdb-clickhouse"
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.network-1.id
  version = "23.8"
  security_group_ids = [yandex_vpc_security_group.clickhouse_sg.id]
  #  security_group_ids = [yandex_vpc_security_group.k8s-public-services.id]

  clickhouse {
    resources {
      resource_preset_id = "s3-c4-m16"
      disk_type_id       = "network-ssd"
      disk_size          = 200
    }
  }

  host {
    type      = "CLICKHOUSE"
    zone      = "ru-central1-a"
    subnet_id = yandex_vpc_subnet.clickhouse-a.id
    assign_public_ip = true
  }

  access {
    data_lens = true
  }

  dynamic "database" {
    for_each = var.clickhouse_dbs
    content {
      name = database.value
    }
  }

  user {
    name     = "dbuser"
    password = var.db_password
    dynamic "permission" {
      for_each = var.clickhouse_dbs
      content {
        database_name = permission.value
      }
    }
  }

  user {
    name     = "support"
    password = var.db_password
    dynamic "permission" {
      for_each = var.clickhouse_dbs
      content {
        database_name = permission.value
      }
    }
  }
}

