"""Run configured usage report automation and send results to an API target."""

from __future__ import annotations

import json
from typing import Any
from urllib import request

from usage_reporter import Agent
from usage_reporter import QueryType
from usage_reporter import get_data
from usage_reporter import load_config


def main() -> None:
    """Run automation script and send results to the configured target URL."""
    config = load_config()
    automation = config["Automation"]

    if not automation["Enabled"]:
        print("Automation is disabled.")
        return

    results = []
    for data_request in automation["Data"]:
        agent = Agent(data_request["Agent"])
        query_type = QueryType(data_request["QueryType"])
        result = get_data(agent, query_type)
        results.extend(result)

    response_text = send_to_target(automation["TargetURL"], results)
    print(response_text)


def build_payload(data: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    """Wrap report rows in the object shape expected by the target flow."""
    return {"data": data}


def send_to_target(target_url: str, data: list[dict[str, Any]]) -> str:
    """Send usage report data to any target that accepts JSON POST requests."""
    body = json.dumps(build_payload(data)).encode("utf-8")
    target_request = request.Request(
        target_url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with request.urlopen(target_request) as response:
        return response.read().decode("utf-8")


if __name__ == "__main__":
    main()
