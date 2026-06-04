"""Run configured usage report automation and print results."""

from __future__ import annotations

import json

from run import ReportPayload
from run import run_configured_report


def main() -> None:
    """Run the test automation script."""
    run_configured_report(format_payload)


def format_payload(_target_url: str, payload: ReportPayload) -> str:
    """Format a report payload without sending it anywhere."""
    return json.dumps(payload, indent=2)


if __name__ == "__main__":
    main()
