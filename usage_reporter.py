"""Utilities for reading usage data from ccusage."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from datetime import date, timedelta
from enum import Enum
from numbers import Number
from pathlib import Path
from typing import Any


class QueryType(str, Enum):
    """Supported usage report queries."""

    LAST_WEEK = "lastWeek"
    LAST_WORK_WEEK_DAILY = "lastWorkWeekDaily"
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


class UsageReporter:
    """Read and summarize agent usage data from ccusage."""

    def __init__(self, config: dict[str, Any]) -> None:
        """Initialize the reporter with the provided configuration."""
        self.config = config

    def get_data(self, agent: Agent, query_type: QueryType) -> list[dict[str, Any]]:
        """Return usage data for the requested agent and query type."""
        if query_type == QueryType.LAST_WEEK:
            return [self._get_last_week_data(agent)]
        if query_type == QueryType.LAST_WORK_WEEK_DAILY:
            return self._get_last_work_week_daily_data(agent)
        if query_type == QueryType.YESTERDAY:
            return [self._get_yesterday_data(agent)]
        if query_type == QueryType.YESTERDAY_SESSIONS:
            return self._get_yesterday_sessions_data(agent)

        raise ValueError(f"Unsupported query type: {query_type}")

    def _call_ccusage(self, *args: str) -> dict[str, Any]:
        """Run ccusage with the provided arguments and return parsed JSON output."""
        executable = shutil.which("ccusage")
        if executable is None:
            raise FileNotFoundError("Could not find ccusage on PATH.")

        command = [executable, *args, "--json"]
        result = subprocess.run(
            command,
            check=True,
            capture_output=True,
            env=self._build_ccusage_environment(),
            text=True,
        )

        return json.loads(result.stdout)

    def _build_ccusage_environment(self) -> dict[str, str]:
        """Return a subprocess environment for ccusage."""
        env = os.environ.copy()
        if not self.config.get("ReadArchivedSessions", False):
            return env

        raw_path = os.path.expandvars(os.path.expanduser(self.config.get("CodexSettingsPath")))
        codex_settings_path = Path(raw_path).resolve()
        env["CODEX_HOME"] = f"{codex_settings_path},{codex_settings_path / 'archived_sessions'}"
        return env

    def _get_last_week_data(self, agent: Agent) -> dict[str, Any]:
        """Return one summarized Codex usage row for last week."""
        since_date, until_date = self._get_last_week_date_range()
        since = since_date.isoformat()
        until = until_date.isoformat()

        raw_data = self._call_ccusage(agent.value, "daily", "--since", since, "--until", until)
        totals = dict(raw_data.get("totals", {}))
        self._normalize_cost(totals)

        return {
            "user": self.config["UserEmail"],
            "agent": agent.value,
            "sample": SampleType.WEEKLY.value,
            "since": since,
            "until": until,
            "models": self._extract_models(raw_data.get("daily", [])),
            **totals,
        }

    def _get_yesterday_data(self, agent: Agent) -> dict[str, Any]:
        """Return one summarized Codex usage row for yesterday."""
        yesterday = (date.today() - timedelta(days=1)).isoformat()
        raw_data = self._call_ccusage(agent.value, "daily", "--since", yesterday, "--until", yesterday)

        totals = dict(raw_data.get("totals", {}))
        self._normalize_cost(totals)

        return {
            "user": self.config["UserEmail"],
            "agent": agent.value,
            "sample": SampleType.DAILY.value,
            "date": yesterday,
            "models": self._extract_models(raw_data.get("daily", [])),
            **totals,
        }

    def _get_yesterday_sessions_data(self, agent: Agent) -> list[dict[str, Any]]:
        """Return one summarized usage row for each Codex session yesterday."""
        since = (date.today() - timedelta(days=1)).isoformat()
        raw_data = self._call_ccusage(agent.value, "session", "--since", since, "--until", since)
        rows = []

        for session in raw_data.get("sessions", []):
            session_data = dict(session)
            self._normalize_cost(session_data)
            session_data.pop("directory", None)
            session_data.pop("sessionFile", None)
            rows.append(
                {
                    "user": self.config["UserEmail"],
                    "agent": agent.value,
                    "sample": SampleType.SESSION.value,
                    "date": since,
                    **session_data,
                    "models": self._extract_models([session]),
                }
            )

        return rows
    
    def _get_last_work_week_daily_data(self, agent: Agent) -> list[dict[str, Any]]:
        """Return five daily rows for last week, folding weekend usage into Friday."""
        since_date, until_date = self._get_last_week_date_range()
        friday = since_date + timedelta(days=4)
        work_days = [since_date + timedelta(days=offset) for offset in range(5)]

        raw_data = self._call_ccusage(
            agent.value, "daily", "--since", since_date.isoformat(), "--until", until_date.isoformat()
        )

        rows_by_date: dict[str, dict[str, Any]] = {
            work_day.isoformat(): {
                "user": self.config["UserEmail"],
                "agent": agent.value,
                "sample": SampleType.DAILY.value,
                "date": work_day.isoformat(),
            }
            for work_day in work_days
        }
        models_by_date: dict[str, set[str]] = {
            work_day.isoformat(): set() for work_day in work_days
        }
        numeric_fields = self._get_numeric_fields(raw_data.get("totals", {}))

        for row in raw_data.get("daily", []):
            row_date = date.fromisoformat(row["date"])
            if row_date < since_date or row_date > until_date:
                continue

            target_date = row_date if row_date.weekday() < 5 else friday
            target_key = target_date.isoformat()
            target_row = rows_by_date[target_key]

            row_models = row.get("models", {})
            if isinstance(row_models, dict):
                models_by_date[target_key].update(row_models)

            for key, value in row.items():
                if key in {"date", "models"} or not isinstance(value, Number) or isinstance(value, bool):
                    continue

                numeric_fields.add(key)
                target_row[key] = target_row.get(key, 0) + value

        results = []
        for work_day in work_days:
            row = rows_by_date[work_day.isoformat()]
            for field in sorted(numeric_fields):
                row.setdefault(field, 0)

            row["models"] = sorted(models_by_date[work_day.isoformat()])
            self._normalize_cost(row)
            results.append(row)

        return results

    @staticmethod
    def _get_last_week_date_range() -> tuple[date, date]:
        """Return Monday-to-Sunday date bounds for the previous calendar week."""
        today = date.today()
        current_week_start = today - timedelta(days=today.weekday())
        return (
            current_week_start - timedelta(days=7),
            current_week_start - timedelta(days=1),
        )

    @staticmethod
    def _get_numeric_fields(data: Any) -> set[str]:
        """Return numeric metric field names from a ccusage row-like object."""
        if not isinstance(data, dict):
            return set()

        return {key for key, value in data.items() if isinstance(value, Number) and not isinstance(value, bool)}

    @staticmethod
    def _extract_models(rows: list[dict[str, Any]]) -> list[str]:
        """Return a sorted list of unique model names from a list of ccusage rows."""
        models: set[str] = set()
        for row in rows:
            row_models = row.get("models", {})
            if isinstance(row_models, dict):
                models.update(row_models)
        return sorted(models)

    @staticmethod
    def _normalize_cost(data: dict[str, Any]) -> None:
        """Normalize ccusage cost field in-place for API payload compatibility."""
        if "costUSD" in data:
            data["cost"] = round(data.pop("costUSD"), 2)
