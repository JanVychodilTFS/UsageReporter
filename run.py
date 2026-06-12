"""Run configured usage report automation and send results to an API target."""

from __future__ import annotations

import json
import logging
from argparse import ArgumentParser
from collections.abc import Callable
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any
from urllib import request

from usage_reporter import Agent, QueryType, UsageReporter

ReportPayload = dict[str, Any]
ReportOutputHandler = Callable[[str, ReportPayload], str]

CONFIG_PATH = Path(__file__).with_name("config.json")
LOG_DIR = Path(__file__).with_name("logs")
LOG_PATH = LOG_DIR / "run.log"

logger = logging.getLogger("usage_reporter.run")


def configure_logging() -> None:
    """Configure logging to both the console and a rotating log file."""
    root_logger = logging.getLogger()
    if root_logger.handlers:
        return

    root_logger.setLevel(logging.INFO)
    formatter = logging.Formatter(
        "%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    root_logger.addHandler(console_handler)

    LOG_DIR.mkdir(parents=True, exist_ok=True)
    file_handler = RotatingFileHandler(
        LOG_PATH,
        maxBytes=1_000_000,
        backupCount=3,
        encoding="utf-8",
    )
    file_handler.setFormatter(formatter)
    root_logger.addHandler(file_handler)


def load_config() -> dict[str, Any]:
    """Load reporter configuration from config.json."""
    with CONFIG_PATH.open(encoding="utf-8-sig") as config_file:
        return json.load(config_file)


def main() -> None:
    """Run automation script and send results to the configured target URL."""
    configure_logging()
    job_ids = parse_job_ids()
    logger.info("Starting usage report run for jobs: %s", ", ".join(job_ids))
    for job_id in job_ids:
        try:
            run_configured_report(send_to_target, job_id=job_id)
        except Exception:
            logger.exception("Automation job '%s' failed.", job_id)
            raise
    logger.info("Completed usage report run.")


def parse_job_ids(description: str | None = None) -> list[str]:
    """Parse one or more automation job IDs from positional command-line arguments."""
    parser = ArgumentParser(description=description or __doc__)
    parser.add_argument(
        "job_ids",
        nargs="+",
        metavar="JOB_ID",
        help="One or more automation job IDs to run from Automation.Jobs.",
    )
    return parser.parse_args().job_ids


def run_configured_report(output_handler: ReportOutputHandler,job_id: str,) -> None:
    """Collect configured report data and pass the payload to an output handler."""
    config = load_config()
    automation = config["Automation"]
    job = select_automation_job(automation, job_id)

    if not job["Enabled"]:
        logger.info("Automation job '%s' is disabled.", job["Id"])
        return

    logger.info("Running automation job '%s'.", job["Id"])
    data = collect_report_data(config, job)
    logger.info("Collected %d report row(s) for job '%s'.", len(data), job["Id"])
    payload = build_payload(job["Id"], data)
    logger.info("Sending report for job '%s' to target.", job["Id"])
    output_text = output_handler(job["TargetURL"], payload)
    logger.info("Target response for job '%s': %s", job["Id"], output_text)


def select_automation_job(automation: dict[str, Any],job_id: str,) -> dict[str, Any]:
    """Return the configured automation job selected by ID."""
    jobs = get_automation_jobs(automation)

    for job in jobs:
        if job["Id"] == job_id:
            return job

    available_jobs = ", ".join(job["Id"] for job in jobs)
    raise ValueError(f"Unknown automation job '{job_id}'. Available jobs: {available_jobs}.")


def get_automation_jobs(automation: dict[str, Any]) -> list[dict[str, Any]]:
    """Return normalized automation jobs from config."""
    configured_jobs = automation.get("Jobs")
    if not isinstance(configured_jobs, list) or not configured_jobs:
        raise ValueError("Automation.Jobs must define at least one automation job.")

    return [normalize_automation_job(job) for job in configured_jobs]


def normalize_automation_job(job: dict[str, Any]) -> dict[str, Any]:
    """Validate and normalize one automation job config entry."""
    job_id = job.get("Id")
    enabled = job.get("Enabled")
    read_archived_sessions = job.get("ReadArchivedSessions")
    target_url = job.get("TargetURL")
    data = job.get("Data")

    if not isinstance(job_id, str) or not job_id.strip():
        raise ValueError("Automation job is missing a non-empty Id.")
    if not isinstance(enabled, bool):
        raise ValueError(f"Automation job '{job_id}' is missing boolean Enabled.")
    if not isinstance(read_archived_sessions, bool):
        raise ValueError(f"Automation job '{job_id}' is missing boolean ReadArchivedSessions.")
    if not isinstance(target_url, str) or not target_url.strip():
        raise ValueError(f"Automation job '{job_id}' is missing TargetURL.")
    if not isinstance(data, list) or not data:
        raise ValueError(f"Automation job '{job_id}' must define at least one Data entry.")

    return {
        "Id": job_id,
        "Enabled": enabled,
        "ReadArchivedSessions": read_archived_sessions,
        "TargetURL": target_url,
        "Data": data,
    }


def collect_report_data(
    config: dict[str, Any],
    job: dict[str, Any],
) -> list[dict[str, Any]]:
    """Collect usage rows for every configured automation data request."""
    reporter_config = {
        **config,
        "ReadArchivedSessions": job["ReadArchivedSessions"],
    }
    reporter = UsageReporter(reporter_config)
    results = []
    for data_request in job["Data"]:
        agent = Agent(data_request["Agent"])
        query_type = QueryType(data_request["QueryType"])
        result = reporter.get_data(agent, query_type)
        results.extend(result)

    return results


def build_payload(job_id: str, data: list[dict[str, Any]]) -> ReportPayload:
    """Wrap report rows in the object shape expected by the target flow."""
    return {"jobId": job_id, "data": data}


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
