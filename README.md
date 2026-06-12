# UsageReporter

Small Windows tool that sends Codex `ccusage` data to a configured JSON API target.

## Prerequisites

- Python
- Node.js (provides `npx`, used to run `ccusage` on demand)

## Install

```powershell
.\install.ps1
```

One-line GitHub install:

```powershell
irm https://raw.githubusercontent.com/JanVychodilTFS/UsageReporter/main/install.ps1 | iex
```

## Update

Re-download all files and re-sync scheduled tasks without touching your config:

```powershell
.\install.ps1 -Update
```

## Config

Jobs live in `Automation.Jobs` in `config.json`. Each enabled job becomes a scheduled task `UsageReporter-<Id>` running `run.py <Id>`. Stale tasks are removed on re-install.

```jsonc
"Automation": {
  "Jobs": [
    {
      "Id": "weekly-summary",
      "Enabled": true,
      "ReadArchivedSessions": false,
      "Schedule": "0 6 * * 1",
      "TargetURL": "https://your-target-url-here",
      "Data": [ { "Agent": "codex", "QueryType": "lastWeek" } ]
    }
  ]
}
```

- Schedules: daily (`0 7 * * *`) or weekly (`0 6 * * 1`).
- Query types: `lastWeek`, `lastWorkWeekDaily`, `yesterday`, `yesterdaySessions`.

## Run / Test

```powershell
python run.py weekly-summary                  # send one job
python run.py weekly-summary daily-summary    # send several jobs
python test.py                                # print all jobs without sending
python test.py weekly-summary                 # print specific job
```

## Uninstall

```powershell
.\uninstall.ps1
```

One-line GitHub uninstall:

```powershell
irm https://raw.githubusercontent.com/JanVychodilTFS/UsageReporter/main/uninstall.ps1 | iex
```
