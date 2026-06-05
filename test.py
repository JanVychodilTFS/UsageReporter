"""Run configured usage report automation and print results."""

from __future__ import annotations

import json
from argparse import ArgumentParser

from run import ReportPayload
from run import get_automation_jobs
from run import load_config
from run import run_configured_report


def main() -> None:
    """Run the test automation script for the given jobs or all configured jobs."""
    job_ids = parse_optional_job_ids()

    if not job_ids:
        job_ids = [job["Id"] for job in get_automation_jobs(load_config()["Automation"])]

    for job_id in job_ids:
        print(f"=== Job: {job_id} ===")
        run_configured_report(format_payload, job_id=job_id)


def parse_optional_job_ids() -> list[str]:
    """Parse optional positional automation job IDs; empty means test all jobs."""
    parser = ArgumentParser(description=__doc__)
    parser.add_argument(
        "job_ids",
        nargs="*",
        metavar="JOB_ID",
        help="Automation job IDs to test. Omit to test all configured jobs.",
    )
    return parser.parse_args().job_ids


def format_payload(_target_url: str, payload: ReportPayload) -> str:
    """Format a report payload without sending it anywhere."""
    return json.dumps(payload, indent=2)


if __name__ == "__main__":
    main()
