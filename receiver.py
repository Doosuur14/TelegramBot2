# import json
# import os
# import requests
# from yandex.cloud import message_queue

# TG_TOKEN = os.environ["TG_TOKEN"]
# DOWNLOADER_QUEUE_URL = os.environ["DOWNLOADER_QUEUE_URL"]
# YC_ACCESS_KEY = os.environ["YC_ACCESS_KEY"]
# YC_SECRET_KEY = os.environ["YC_SECRET_KEY"]

# mq_client = message_queue.Client(
#     access_key=YC_ACCESS_KEY,
#     secret_key=YC_SECRET_KEY
# )

import requests
import json
import os

YMQ_ENDPOINT = "https://message-queue.api.cloud.yandex.net"
QUEUE_URL = os.environ["DOWNLOADER_QUEUE_URL"]
TG_TOKEN = os.environ["TG_TOKEN"]
YC_ACCESS_KEY = os.environ["YC_ACCESS_KEY"]
YC_SECRET_KEY = os.environ["YC_SECRET_KEY"]

def send_message(chat_id, text):
    """Send a message to Telegram"""
    requests.post(
        f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage",
        json={"chat_id": chat_id, "text": text}
    )

def publish_message(payload):
    """Publish a message to Yandex Message Queue"""
    requests.post(
        f"{YMQ_ENDPOINT}/?Action=SendMessage&QueueUrl={QUEUE_URL}",
        data={"MessageBody": json.dumps(payload)},
        auth=(YC_ACCESS_KEY, YC_SECRET_KEY)
    )

def handler(event, context):
    # If event is a string, parse it
    if isinstance(event, str):
        event = json.loads(event)

    # Loop through messages
    for msg in event.get("messages", []):
        body = msg.get("details", {}).get("message", {}).get("body")
        if not body:
            continue

        update = json.loads(body)
        message = update.get("message")
        if not message:
            continue

        chat_id = message["chat"]["id"]

        if "video" in message:
            file_id = message["video"]["file_id"]
            send_message(chat_id, "Началась загрузка видео...")
            publish_message({"file_id": file_id, "chat_id": chat_id})
        else:
            send_message(chat_id, "Принимаю только видео.")

    return {"statusCode": 200}

