"""Run configured usage report automation and print results."""

from __future__ import annotations

import json

from run import build_payload
from usage_reporter import Agent
from usage_reporter import QueryType
from usage_reporter import get_data
from usage_reporter import load_config


def main() -> None:
    """Run the test automation script."""
    test_automation()


def test_automation() -> None:
    """Run report calls defined in config.json Automation."""
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

    print(json.dumps(build_payload(results), indent=2))


if __name__ == "__main__":
    main()
