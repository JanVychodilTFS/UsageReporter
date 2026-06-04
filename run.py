"""Run configured usage report automation and send results to an API target."""

from __future__ import annotations

from collections.abc import Callable
import json
from typing import Any
from urllib import request

from usage_reporter import Agent
from usage_reporter import QueryType
from usage_reporter import get_data
from usage_reporter import load_config

ReportPayload = dict[str, list[dict[str, Any]]]
ReportOutputHandler = Callable[[str, ReportPayload], str]


def main() -> None:
    """Run automation script and send results to the configured target URL."""
    run_configured_report(send_to_target)


def run_configured_report(output_handler: ReportOutputHandler) -> None:
    """Collect configured report data and pass the payload to an output handler."""
    config = load_config()
    automation = config["Automation"]

    if not automation["Enabled"]:
        print("Automation is disabled.")
        return

    payload = build_payload(collect_report_data(automation))
    output_text = output_handler(automation["TargetURL"], payload)
    print(output_text)


def collect_report_data(automation: dict[str, Any]) -> list[dict[str, Any]]:
    """Collect usage rows for every configured automation data request."""
    results = []
    for data_request in automation["Data"]:
        agent = Agent(data_request["Agent"])
        query_type = QueryType(data_request["QueryType"])
        result = get_data(agent, query_type)
        results.extend(result)

    return results


def build_payload(data: list[dict[str, Any]]) -> ReportPayload:
    """Wrap report rows in the object shape expected by the target flow."""
    return {"data": data}


def send_to_target(target_url: str, payload: ReportPayload) -> str:
    """Send a usage report payload to any target that accepts JSON POST requests."""
    body = json.dumps(payload).encode("utf-8")
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
