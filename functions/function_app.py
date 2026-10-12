"""Hot-path consumer: reacts to high-temperature telemetry routed by IoT Hub to Event Hubs."""
import json
import logging
from typing import List

import azure.functions as func

app = func.FunctionApp()


@app.event_hub_message_trigger(
    arg_name="events",
    event_hub_name="%ALERTS_EVENTHUB_NAME%",
    connection="EventHubConnection",  # identity-based: EventHubConnection__fullyQualifiedNamespace
    cardinality="many",
)
# typing.List, not list[...]: the Functions worker rejects builtin generics for bindings.
def temperature_alert(events: List[func.EventHubEvent]) -> None:
    for event in events:
        # IoT Hub stamps system properties on every routed message (device id, enqueue time, ...).
        device_id = event.iothub_metadata.get("connection-device-id", "unknown")
        payload = json.loads(event.get_body().decode("utf-8"))
        # A real system would page someone or call an API; logging is enough to see it in App Insights.
        logging.warning("ALERT device=%s temperature=%s", device_id, payload.get("temperature"))
