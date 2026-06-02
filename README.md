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

## Test

Print configured data without sending:

```powershell
python test.py
```

Send data to the configured target:

```powershell
python run.py
```
