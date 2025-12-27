terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
    }
    telegram = {
      source  = "yi-jiayu/telegram"
    }
  }
}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = "b1gdjscug7mlgo3ggsf5"  
  zone      = var.zone
}

provider "telegram" {
  bot_token = var.tg_bot_key
}

variable "cloud_id" { type = string }
variable "zone" {
  type    = string
  default = "ru-central1-d"
}
variable "yc_token" {
  type = string
}

variable "tg_bot_key" { type = string }

# -----------------------------
# Service Account & IAM
# -----------------------------
resource "yandex_iam_service_account" "sa" {
  name      = "vvot23-sa"
  folder_id = "b1gdjscug7mlgo3ggsf5"  
}

resource "yandex_resourcemanager_folder_iam_member" "roles" {
  for_each  = toset(["editor", "serverless.functions.invoker"])
  folder_id = "b1gdjscug7mlgo3ggsf5"  
  role      = each.key
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "ymq_admin" {
  folder_id = "b1gdjscug7mlgo3ggsf5"  
  role      = "ymq.admin"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "ymq_writer" {
  folder_id = "b1gdjscug7mlgo3ggsf5"
  role      = "ymq.writer"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}


# -----------------------------
# Static Access Key
# -----------------------------
resource "yandex_iam_service_account_static_access_key" "sa_key" {
  service_account_id = yandex_iam_service_account.sa.id
}

# -----------------------------
# Message Queues - BUT USE DATA SOURCE FOR EXISTING QUEUE
# -----------------------------
# Create NEW queues in YOUR folder with DIFFERENT names
resource "yandex_message_queue" "receiver" {
  name       = "vvot23-queue-receiver-new" 
  access_key = yandex_iam_service_account_static_access_key.sa_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa_key.secret_key
}

resource "yandex_message_queue" "downloader" {
  name       = "vvot23-queue-downloader"
  access_key = yandex_iam_service_account_static_access_key.sa_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa_key.secret_key
}

# -----------------------------
# Cloud Functions
# -----------------------------
resource "yandex_function" "receiver_func" {
  name              = "vvot23-func-receiver"
  folder_id         = "b1gdjscug7mlgo3ggsf5"  
  runtime           = "python312"
  entrypoint        = "receiver.handler"
  memory            = 128
  execution_timeout = 30
  user_hash         = "v1.0-receiver-20251225"

  content { zip_filename = "vvot23-receiver.zip" }

  service_account_id = yandex_iam_service_account.sa.id

  environment = {
    TG_TOKEN             = var.tg_bot_key
    DOWNLOADER_QUEUE_URL = yandex_message_queue.downloader.arn
    YC_ACCESS_KEY        = yandex_iam_service_account_static_access_key.sa_key.access_key
    YC_SECRET_KEY        = yandex_iam_service_account_static_access_key.sa_key.secret_key
  }
}

resource "yandex_function" "downloader_func" {
  name              = "vvot23-func-downloader"
  folder_id         = "b1gdjscug7mlgo3ggsf5"
  runtime           = "python312"
  entrypoint        = "downloader.handler"
  memory            = 128
  execution_timeout = 30

  user_hash = "v1.0-downloader-20251226b"

  content {
    zip_filename = "vvot23-downloader.zip"
  }

  service_account_id = yandex_iam_service_account.sa.id

  environment = {
    TG_TOKEN      = var.tg_bot_key
    API_GW_DOMAIN = yandex_api_gateway.main.domain
    YC_ACCESS_KEY = yandex_iam_service_account_static_access_key.sa_key.access_key
    YC_SECRET_KEY = yandex_iam_service_account_static_access_key.sa_key.secret_key
  }
}



 
# -----------------------------
# Function Triggers
# -----------------------------
resource "yandex_function_trigger" "receiver_trigger" {
  name = "vvot23-receiver-trigger"

  message_queue {
    queue_id           = yandex_message_queue.receiver.arn
    service_account_id = yandex_iam_service_account.sa.id
    batch_size         = 1
    batch_cutoff       = "10"
  }

  function {
    id                 = yandex_function.receiver_func.id
    service_account_id = yandex_iam_service_account.sa.id
  }
}

resource "yandex_function_trigger" "downloader_trigger" {
  name = "vvot23-downloader-trigger"

  message_queue {
    queue_id           = yandex_message_queue.downloader.arn
    service_account_id = yandex_iam_service_account.sa.id
    batch_size         = 1
    batch_cutoff       = "10"
  }

  function {
    id                 = yandex_function.downloader_func.id
    service_account_id = yandex_iam_service_account.sa.id
  }
}

# -----------------------------
# Object Storage - Create NEW bucket
# -----------------------------
resource "yandex_storage_bucket" "tg_video" {
  bucket    = "vvot23-tg-video-new" 
  folder_id = "b1gdjscug7mlgo3ggsf5" 
}

# -----------------------------
# API Gateway
# -----------------------------
resource "yandex_api_gateway" "main" {
  name      = "vvot23-apigw"
  folder_id = "b1gdjscug7mlgo3ggsf5"  

  spec = <<-EOT
openapi: 3.0.0
info:
  title: Vvot23 Telegram Video Bot
  version: 1.0.0

paths:
  /webhook:
    post:
      x-yc-apigateway-integration:
        type: cloud_ymq
        folder_id: b1gdjscug7mlgo3ggsf5  
        queue_url: https://message-queue.api.cloud.yandex.net/b1g71e95h51okii30p25/dj60000000agbgtu02mk/vvot23-queue-receiver-new
        action: SendMessage
        service_account_id: ${yandex_iam_service_account.sa.id}

  /video/{key+}:
    get:
      parameters:
        - name: key
          in: path
          required: true
          schema:
            type: string
      x-yc-apigateway-integration:
        type: object_storage
        bucket: vvot23-tg-video-new  
        object: '{key}'
EOT
}

# -----------------------------
# Telegram Webhook
# -----------------------------
resource "telegram_bot_webhook" "bot" {
  url        = "https://${yandex_api_gateway.main.domain}/webhook"
  depends_on = [yandex_api_gateway.main]
}

