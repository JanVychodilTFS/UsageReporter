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

The installer asks for email, target URL, install path, and schedule. It creates a Windows Scheduled Task and writes logs to:

```text
%LOCALAPPDATA%\UsageReporter\logs\run.log
```

The selected install path is stored in the user environment variable `USAGE_REPORTER_INSTALL_PATH` so uninstall can find custom install locations.

Set `ReadArchivedSessions` to `true` in `config.json` to include archived Codex sessions. The reporter then sets `CODEX_HOME` only for the `ccusage` subprocess, using `CodexSettingsPath` and its `archived_sessions` folder.

## Query Types

- `lastWeek`: one weekly summary row for the previous Monday through Sunday.
- `lastWorkWeekDaily`: five daily rows for the previous Monday through Friday, with Saturday and Sunday usage added to Friday.
- `yesterday`: one daily summary row for yesterday.
- `yesterdaySessions`: one row for each session from yesterday.

## Test

Print the configured JSON payload without sending:

```powershell
python test.py
```

Send data to the configured target:

```powershell
python run.py
```

## Uninstall

From a local checkout:

```powershell
.\uninstall.ps1
```

From the install folder:

```powershell
.\uninstall.ps1
```

One-line GitHub uninstall:

```powershell
irm https://raw.githubusercontent.com/JanVychodilTFS/UsageReporter/main/uninstall.ps1 | iex
```
