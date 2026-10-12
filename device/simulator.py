"""Simulated IoT device: sends temperature/humidity telemetry (D2C) to Azure IoT Hub."""
import json
import os
import random
import time

from azure.iot.device import IoTHubDeviceClient, Message

SEND_INTERVAL_S = 5
# Routing property: 'storage' matches the cold-path route; any other value only reaches the built-in endpoint.
MESSAGE_LEVEL_DEFAULT = "storage"


def load_env(path: str = ".env") -> None:
    """Minimal .env loader (KEY=VALUE lines) to avoid an extra dependency."""
    if not os.path.exists(path):
        return
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ.setdefault(key, value.strip('"'))


def main() -> None:
    load_env()
    client = IoTHubDeviceClient.create_from_connection_string(os.environ["DEVICE_CONNECTION_STRING"])
    level = os.environ.get("MESSAGE_LEVEL", MESSAGE_LEVEL_DEFAULT)
    client.connect()  # MQTT over TLS (port 8883)
    print(f"Connected (level={level}). Ctrl+C to stop.")
    try:
        while True:
            payload = {
                "temperature": round(random.uniform(18, 35), 1),
                "humidity": round(random.uniform(30, 70), 1),
            }
            msg = Message(json.dumps(payload))
            msg.content_type = "application/json"
            msg.content_encoding = "utf-8"
            # Custom application property, evaluated by the route condition `level = 'storage'`.
            msg.custom_properties["level"] = level
            client.send_message(msg)
            print(f"Sent: {payload}")
            time.sleep(SEND_INTERVAL_S)
    except KeyboardInterrupt:
        pass
    finally:
        client.shutdown()


if __name__ == "__main__":
    main()
