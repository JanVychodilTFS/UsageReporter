"""Utilities for reading usage data from ccusage."""

from __future__ import annotations

from datetime import date
from datetime import timedelta
from enum import Enum
import json
from pathlib import Path
import shutil
import subprocess
from typing import Any


class QueryType(str, Enum):
    """Supported usage report queries."""

    LAST_WEEK = "lastWeek"
    YESTERDAY = "yesterday"
    YESTERDAY_SESSIONS = "yesterdaySessions"


class Agent(str, Enum):
    """Supported usage report agents."""

    CODEX = "codex"


class SampleType(str, Enum):
    """Supported reporting sample types."""

    DAILY = "daily"
    SESSION = "session"
    WEEKLY = "weekly"


CONFIG_PATH = Path(__file__).with_name("config.json")


def call_ccusage(*args: str) -> dict[str, Any]:
    """Run ccusage with the provided arguments and return parsed JSON output."""
    executable = shutil.which("ccusage")
    if executable is None:
        raise FileNotFoundError("Could not find ccusage on PATH.")

    command = [executable, *args, "--json"]
    result = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    )

    return json.loads(result.stdout)


def load_config() -> dict[str, Any]:
    """Load reporter configuration from config.json."""
    with CONFIG_PATH.open(encoding="utf-8-sig") as config_file:
        return json.load(config_file)


def get_last_week_data(agent: Agent) -> dict[str, Any]:
    """Return one summarized Codex usage row for last week."""
    today = date.today()
    current_week_start = today - timedelta(days=today.weekday())
    since = (current_week_start - timedelta(days=7)).isoformat()
    until = (current_week_start - timedelta(days=1)).isoformat()

    raw_data = call_ccusage(agent.value, "daily", "--since", since, "--until", until)
    config = load_config()
    models: set[str] = set()

    for row in raw_data.get("daily", []):
        row_models = row.get("models", {})
        if isinstance(row_models, dict):
            models.update(row_models)

    totals = dict(raw_data.get("totals", {}))
    round_cost(totals)

    return {
        "user": config["UserEmail"],
        "agent": agent.value,
        "sample": SampleType.WEEKLY.value,
        "since": since,
        "until": until,
        "models": sorted(models),
        **totals,
    }


def get_yesterday_data(agent: Agent) -> dict[str, Any]:
    """Return one summarized Codex usage row for yesterday."""
    yesterday = (date.today() - timedelta(days=1)).isoformat()
    raw_data = call_ccusage(
        agent.value,
        "daily",
        "--since",
        yesterday,
        "--until",
        yesterday,
    )
    config = load_config()
    models: set[str] = set()

    for row in raw_data.get("daily", []):
        row_models = row.get("models", {})
        if isinstance(row_models, dict):
            models.update(row_models)

    totals = dict(raw_data.get("totals", {}))
    round_cost(totals)

    return {
        "user": config["UserEmail"],
        "agent": agent.value,
        "sample": SampleType.DAILY.value,
        "date": yesterday,
        "models": sorted(models),
        **totals,
    }


def get_yesterday_sessions_data(agent: Agent) -> list[dict[str, Any]]:
    """Return one summarized usage row for each Codex session yesterday."""
    since = (date.today() - timedelta(days=1)).isoformat()

    raw_data = call_ccusage(agent.value, "session", "--since", since, "--until", since)
    config = load_config()
    rows = []

    for session in raw_data.get("sessions", []):
        session_data = dict(session)
        round_cost(session_data)
        session_data.pop("directory", None)
        session_data.pop("sessionFile", None)
        session_models = session.get("models", {})
        models = sorted(session_models) if isinstance(session_models, dict) else []
        rows.append(
            {
                "user": config["UserEmail"],
                "agent": agent.value,
                "sample": SampleType.SESSION.value,
                "date": since,
                **session_data,
                "models": models,
            }
        )

    return rows


def round_cost(data: dict[str, Any]) -> None:
    """Round cost value in-place and normalize its field name."""
    if "costUSD" in data:
        data["cost"] = round(data.pop("costUSD"), 2)


def get_data(agent: Agent, query_type: QueryType) -> list[dict[str, Any]]:
    """Return usage data for the requested agent and query type."""
    if query_type == QueryType.LAST_WEEK:
        return [get_last_week_data(agent)]
    if query_type == QueryType.YESTERDAY:
        return [get_yesterday_data(agent)]
    if query_type == QueryType.YESTERDAY_SESSIONS:
        return get_yesterday_sessions_data(agent)

    raise ValueError(f"Unsupported query type: {query_type}")
