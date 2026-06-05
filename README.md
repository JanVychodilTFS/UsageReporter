# UsageReporter

Small Windows tool that sends Codex `ccusage` data to a configured JSON API target.

## Prerequisites

- Python
- `ccusage`

## Install

From a local checkout:

```powershell
.\install.ps1
```

One-line GitHub install:

```powershell
irm https://raw.githubusercontent.com/JanVychodilTFS/UsageReporter/main/install.ps1 | iex
```

The installer asks for email, target URL, install path, schedule, and default job flags when no jobs exist yet. It writes a config with `Automation.Jobs`, creates one Windows Scheduled Task per enabled job, and writes logs to:

```text
%LOCALAPPDATA%\UsageReporter\logs\run-<job-id>.log
```

The selected install path is stored in the user environment variable `USAGE_REPORTER_INSTALL_PATH` so uninstall can find custom install locations.

## Automation Jobs

Each enabled entry in `Automation.Jobs` becomes one scheduled task named `UsageReporter-<Id>`. The task runs `run.py --job-id <Id>`, so the script knows which job triggered it. Disabled jobs stay in config, but their scheduled tasks are removed on install.

Set a job's `ReadArchivedSessions` to `true` to include archived Codex sessions for that job. The reporter then sets `CODEX_HOME` only for that job's `ccusage` subprocess, using `CodexSettingsPath` and its `archived_sessions` folder.

```jsonc
"Automation": {
  "Jobs": [
    {
      "Id": "weekly-summary",
      "Enabled": true,
      "ReadArchivedSessions": false,
      "Schedule": "0 6 * * 1",
      "TargetURL": "https://your-target-url-here",
      "Data": [
        { "Agent": "codex", "QueryType": "lastWeek" }
      ]
    },
    {
      "Id": "daily-sessions",
      "Enabled": true,
      "ReadArchivedSessions": false,
      "Schedule": "0 7 * * *",
      "TargetURL": "https://your-target-url-here",
      "Data": [
        { "Agent": "codex", "QueryType": "yesterdaySessions" }
      ]
    }
  ]
}
```

Job IDs may contain letters, numbers, underscores, and hyphens. Supported cron schedules are daily (`0 7 * * *`) or weekly (`0 6 * * 1`).

Payloads are sent as:

```json
{
  "jobId": "weekly-summary",
  "data": []
}
```

## Query Types

- `lastWeek`: one weekly summary row for the previous Monday through Sunday.
- `lastWorkWeekDaily`: five daily rows for the previous Monday through Friday, with Saturday and Sunday usage added to Friday.
- `yesterday`: one daily summary row for yesterday.
- `yesterdaySessions`: one row for each session from yesterday.

## Test

Print the configured JSON payload without sending:

```powershell
python test.py --job-id weekly-summary
```

Send data to the configured target:

```powershell
python run.py --job-id weekly-summary
```

## Uninstall

From a local checkout:

```powershell
.\uninstall.ps1
```

One-line GitHub uninstall:

```powershell
irm https://raw.githubusercontent.com/JanVychodilTFS/UsageReporter/main/uninstall.ps1 | iex
```
