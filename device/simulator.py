"""Simulated IoT device: sends telemetry (D2C) and handles cloud-to-device control.

Control channels (all over the same MQTT connection):
- direct methods `reboot` and `setInterval` (synchronous RPC, device must be online)
- device twin `desired.sendInterval` (desired state, applied even if set while offline)
- C2D messages (fire-and-forget notifications, queued by the hub up to their TTL)
"""
import json
import os
import random
import threading

from azure.iot.device import IoTHubDeviceClient, Message, MethodResponse

SEND_INTERVAL_DEFAULT_S = 5
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


class Device:
    def __init__(self, client: IoTHubDeviceClient, level: str) -> None:
        self.client = client
        self.level = level
        self.interval_s = SEND_INTERVAL_DEFAULT_S
        # Set by handlers to cut the current sleep short (new interval, reboot, Ctrl+C).
        self.wake = threading.Event()
        self.reboot_requested = False

    # --- control handlers (called on SDK threads) ---

    def set_interval(self, seconds: object) -> bool:
        if not isinstance(seconds, (int, float)) or not 1 <= seconds <= 3600:
            return False
        self.interval_s = int(seconds)
        # Reported properties are the device's acknowledgement of the desired state.
        self.client.patch_twin_reported_properties({"sendInterval": self.interval_s})
        print(f"Send interval is now {self.interval_s}s")
        self.wake.set()
        return True

    def on_method(self, request) -> None:
        if request.name == "setInterval":
            ok = self.set_interval(request.payload)
            status, payload = (200, {"sendInterval": self.interval_s}) if ok else (400, {"error": "expected 1-3600"})
        elif request.name == "reboot":
            status, payload = 200, {"status": "rebooting"}
        else:
            status, payload = 404, {"error": f"unknown method {request.name}"}
        print(f"Direct method {request.name}({request.payload}) -> {status}")
        self.client.send_method_response(MethodResponse.create_from_method_request(request, status, payload))
        # Only after responding: the reboot drops the connection the response travels on.
        if request.name == "reboot":
            self.reboot_requested = True
            self.wake.set()

    def on_desired_patch(self, patch: dict) -> None:
        print(f"Twin desired patch: {patch}")
        if "sendInterval" in patch:
            self.set_interval(patch["sendInterval"])

    def on_c2d(self, message: Message) -> None:
        print(f"C2D message: {message.data.decode('utf-8')} properties={message.custom_properties}")

    # --- main loop ---

    def start(self) -> None:
        self.client.on_method_request_received = self.on_method
        self.client.on_twin_desired_properties_patch_received = self.on_desired_patch
        self.client.on_message_received = self.on_c2d
        self.client.connect()  # MQTT over TLS (port 8883)
        # Desired properties set while the device was offline are applied at startup.
        desired = self.client.get_twin()["desired"]
        if "sendInterval" in desired:
            self.set_interval(desired["sendInterval"])
        print(f"Connected (level={self.level}, interval={self.interval_s}s). Ctrl+C to stop.")

    def run(self) -> None:
        while True:
            payload = {
                "temperature": round(random.uniform(18, 35), 1),
                "humidity": round(random.uniform(30, 70), 1),
            }
            msg = Message(json.dumps(payload))
            msg.content_type = "application/json"
            msg.content_encoding = "utf-8"
            # Custom application property, evaluated by the route condition `level = 'storage'`.
            msg.custom_properties["level"] = self.level
            self.client.send_message(msg)
            print(f"Sent: {payload}")

            self.wake.wait(self.interval_s)
            self.wake.clear()
            if self.reboot_requested:
                self.reboot_requested = False
                print("Rebooting (disconnect + reconnect)...")
                self.client.disconnect()
                self.client.connect()


def main() -> None:
    load_env()
    client = IoTHubDeviceClient.create_from_connection_string(os.environ["DEVICE_CONNECTION_STRING"])
    device = Device(client, os.environ.get("MESSAGE_LEVEL", MESSAGE_LEVEL_DEFAULT))
    try:
        device.start()
        device.run()
    except KeyboardInterrupt:
        pass
    finally:
        client.shutdown()


if __name__ == "__main__":
    main()
