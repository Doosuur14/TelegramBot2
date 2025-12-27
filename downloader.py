import json
import os
import uuid
import logging
import requests
import boto3

# Setup logging
logging.basicConfig(level=logging.INFO)

# Environment variables
TG_TOKEN = os.environ["TG_TOKEN"]
API_GW_DOMAIN = os.environ["API_GW_DOMAIN"]
BUCKET = "vvot23-tg-video-new"  # Make sure this bucket exists
YC_ACCESS_KEY = os.environ["YC_ACCESS_KEY"]
YC_SECRET_KEY = os.environ["YC_SECRET_KEY"]

# Setup Yandex Object Storage client
s3 = boto3.client(
    "s3",
    endpoint_url="https://storage.yandexcloud.net",
    aws_access_key_id=YC_ACCESS_KEY,
    aws_secret_access_key=YC_SECRET_KEY,
    region_name="ru-central1"
)

def send_telegram_message(chat_id, text):
    """Helper to send message to Telegram."""
    requests.post(
        f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage",
        json={"chat_id": chat_id, "text": text}
    )

def handler(event, context):
    logging.info(f"Received event: {event}")
    
    for msg in event.get("messages", []):
        try:
            body = msg["details"]["message"]["body"]
            task = json.loads(body)
            logging.info(f"Processing task: {task}")

            file_id = task.get("file_id")
            chat_id = task.get("chat_id")

            if not file_id or not chat_id:
                logging.warning("Task missing file_id or chat_id. Skipping.")
                continue

            # Get file info from Telegram
            file_info_resp = requests.get(
                f"https://api.telegram.org/bot{TG_TOKEN}/getFile",
                params={"file_id": file_id}
            ).json()
            
            if not file_info_resp.get("ok"):
                logging.error(f"Failed to get file info: {file_info_resp}")
                send_telegram_message(chat_id, "Failed to fetch your video from Telegram.")
                continue

            file_path = file_info_resp["result"]["file_path"]
            video_resp = requests.get(f"https://api.telegram.org/file/bot{TG_TOKEN}/{file_path}")

            if video_resp.status_code != 200:
                logging.error(f"Failed to download video: {video_resp.status_code}")
                send_telegram_message(chat_id, "Failed to download your video.")
                continue

            video_data = video_resp.content
            key = f"videos/{uuid.uuid4()}.mp4"

            # Upload to Yandex Object Storage
            s3.put_object(Bucket=BUCKET, Key=key, Body=video_data)
            logging.info(f"Uploaded video to bucket {BUCKET} with key {key}")

            # Generate public URL
            url = f"https://{API_GW_DOMAIN}/video/{key}"
            send_telegram_message(chat_id, f"Your video is available here: {url}")

        except Exception as e:
            logging.exception(f"Error processing message: {e}")
            if chat_id:
                send_telegram_message(chat_id, "An error occurred while processing your video.")

    return {"statusCode": 200}




