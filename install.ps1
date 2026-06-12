param(
    [string]$SourceBaseUrl = 'https://raw.githubusercontent.com/JanVychodilTFS/UsageReporter/main',
    [string]$TaskName = 'UsageReporter',
    [switch]$Update
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DefaultInstallPath = Join-Path $env:LOCALAPPDATA 'UsageReporter'
$DefaultCodexSettingsPath = '%USERPROFILE%\.codex'
$InstallPathEnvVarName = 'USAGE_REPORTER_INSTALL_PATH'
$ProjectFiles = @('usage_reporter.py', 'run.py', 'test.py', 'uninstall.ps1', 'install.ps1')

function Assert-CommandExists {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Install it and run this installer again."
    }
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-ObjectPropertyValue {
    param(
        $Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }

        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Read-Value {
    param(
        [string]$Prompt,
        [string]$Default = '',
        [bool]$Required = $true
    )

    while ($true) {
        if ([string]::IsNullOrWhiteSpace($Default)) {
            $value = Read-Host $Prompt
        }
        else {
            $value = Read-Host "$Prompt [$Default]"
        }

        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = $Default
        }

        if (-not $Required -or -not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }

        Write-Host 'Value is required.'
    }
}

function Read-TargetUrl {
    param([string]$Default = '')

    while ($true) {
        if ([string]::IsNullOrWhiteSpace($Default)) {
            $value = Read-Host 'Target URL'
        }
        else {
            $value = Read-Host 'Target URL [press Enter to keep current]'
        }

        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = $Default
        }

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }

        Write-Host 'Target URL is required.'
    }
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )

    $defaultText = if ($Default) { 'Y/n' } else { 'y/N' }

    while ($true) {
        $value = Read-Host "$Prompt [$defaultText]"

        if ([string]::IsNullOrWhiteSpace($value)) {
            return $Default
        }

        switch ($value.Trim().ToLowerInvariant()) {
            'y' { return $true }
            'yes' { return $true }
            'n' { return $false }
            'no' { return $false }
            default { Write-Host 'Enter yes or no.' }
        }
    }
}

function Expand-InstallPath {
    param([string]$Path)

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
    return [System.IO.Path]::GetFullPath($expandedPath)
}

function ConvertTo-DayOfWeek {
    param([string]$Value)

    switch ($Value.ToLowerInvariant()) {
        '0' { return 'Sunday' }
        '7' { return 'Sunday' }
        'sun' { return 'Sunday' }
        'sunday' { return 'Sunday' }
        '1' { return 'Monday' }
        'mon' { return 'Monday' }
        'monday' { return 'Monday' }
        '2' { return 'Tuesday' }
        'tue' { return 'Tuesday' }
        'tuesday' { return 'Tuesday' }
        '3' { return 'Wednesday' }
        'wed' { return 'Wednesday' }
        'wednesday' { return 'Wednesday' }
        '4' { return 'Thursday' }
        'thu' { return 'Thursday' }
        'thursday' { return 'Thursday' }
        '5' { return 'Friday' }
        'fri' { return 'Friday' }
        'friday' { return 'Friday' }
        '6' { return 'Saturday' }
        'sat' { return 'Saturday' }
        'saturday' { return 'Saturday' }
        default { throw "Unsupported day-of-week value '$Value'." }
    }
}

function New-TriggerFromCronSchedule {
    param([string]$Schedule)

    $parts = $Schedule.Trim() -split '\s+'
    if ($parts.Count -ne 5) {
        throw "Unsupported schedule '$Schedule'. Use cron format like '0 6 * * 1'."
    }

    $minute = [int]$parts[0]
    $hour = [int]$parts[1]
    $dayOfMonth = $parts[2]
    $month = $parts[3]
    $dayOfWeek = $parts[4]

    if ($minute -lt 0 -or $minute -gt 59 -or $hour -lt 0 -or $hour -gt 23) {
        throw "Unsupported schedule '$Schedule'. Hour/minute is outside valid range."
    }

    if ($dayOfMonth -ne '*' -or $month -ne '*') {
        throw "Unsupported schedule '$Schedule'. Only daily or weekly schedules are supported."
    }

    $runAt = Get-Date -Hour $hour -Minute $minute -Second 0

    if ($dayOfWeek -eq '*') {
        return New-ScheduledTaskTrigger -Daily -At $runAt
    }

    $taskDayOfWeek = ConvertTo-DayOfWeek -Value $dayOfWeek
    return New-ScheduledTaskTrigger -Weekly -DaysOfWeek $taskDayOfWeek -At $runAt
}

function ConvertTo-PowerShellStringLiteral {
    param([string]$Value)

    return "'" + $Value.Replace("'", "''") + "'"
}

function Install-ProjectFile {
    param(
        [string]$FileName,
        [string]$InstallPath,
        [string]$SourceBaseUrl,
        [switch]$ForceRemote
    )

    $destination = Join-Path $InstallPath $FileName
    $localSource = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $null
    }
    else {
        Join-Path $PSScriptRoot $FileName
    }

    if (-not $ForceRemote -and $localSource -and (Test-Path -LiteralPath $localSource)) {
        if ((Test-Path -LiteralPath $destination) -and
            ((Resolve-Path -LiteralPath $localSource).Path -eq (Resolve-Path -LiteralPath $destination).Path)) {
            return
        }

        Copy-Item -LiteralPath $localSource -Destination $destination -Force
        return
    }

    $sourceUrl = $SourceBaseUrl.TrimEnd('/') + '/' + $FileName
    Invoke-WebRequest -Uri $sourceUrl -OutFile $destination
}

function Set-InstallPathEnvironmentVariable {
    param(
        [string]$Name,
        [string]$InstallPath
    )

    [Environment]::SetEnvironmentVariable($Name, $InstallPath, 'User')
    Set-Item -Path "Env:$Name" -Value $InstallPath
}

function Get-DefaultAutomationData {
    return @(
        [ordered]@{
            Agent = 'codex'
            QueryType = 'yesterdayWorkWeek'
        }
    )
}

function Test-HasAutomationJobs {
    param($Config)

    $automation = Get-ObjectPropertyValue -Object $Config -Name 'Automation'
    $jobs = Get-ObjectPropertyValue -Object $automation -Name 'Jobs'
    return $null -ne $jobs -and @($jobs).Count -gt 0
}

function Get-AutomationJobsFromConfig {
    param($Config)

    $automation = Get-ObjectPropertyValue -Object $Config -Name 'Automation'
    $jobs = Get-ObjectPropertyValue -Object $automation -Name 'Jobs'
    if ($null -eq $jobs -or @($jobs).Count -eq 0) {
        throw 'Automation.Jobs must define at least one job.'
    }

    return @($jobs)
}

function New-DefaultAutomationJob {
    param(
        [bool]$Enabled,
        [bool]$ReadArchivedSessions,
        [string]$Schedule,
        [string]$TargetUrl,
        $Data
    )

    return [ordered]@{
        Id = 'daily_report'
        Enabled = $Enabled
        ReadArchivedSessions = $ReadArchivedSessions
        Schedule = $Schedule
        TargetURL = $TargetUrl
        Data = @($Data)
    }
}

function Assert-AutomationJob {
    param($Job)

    $jobId = Get-ObjectPropertyValue -Object $Job -Name 'Id'
    $enabled = Get-ObjectPropertyValue -Object $Job -Name 'Enabled'
    $readArchivedSessions = Get-ObjectPropertyValue -Object $Job -Name 'ReadArchivedSessions'
    $schedule = Get-ObjectPropertyValue -Object $Job -Name 'Schedule'
    $targetUrl = Get-ObjectPropertyValue -Object $Job -Name 'TargetURL'
    $data = Get-ObjectPropertyValue -Object $Job -Name 'Data'

    if ([string]::IsNullOrWhiteSpace($jobId)) {
        throw 'Automation job is missing Id.'
    }

    if ($jobId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
        throw "Automation job '$jobId' has an invalid Id. Use letters, numbers, underscores, or hyphens."
    }

    if ($enabled -isnot [bool]) {
        throw "Automation job '$jobId' is missing boolean Enabled."
    }

    if ($readArchivedSessions -isnot [bool]) {
        throw "Automation job '$jobId' is missing boolean ReadArchivedSessions."
    }

    if ([string]::IsNullOrWhiteSpace($schedule)) {
        throw "Automation job '$jobId' is missing Schedule."
    }

    if ([string]::IsNullOrWhiteSpace($targetUrl)) {
        throw "Automation job '$jobId' is missing TargetURL."
    }

    if ($null -eq $data -or @($data).Count -eq 0) {
        throw "Automation job '$jobId' must define at least one Data entry."
    }

    New-TriggerFromCronSchedule -Schedule $schedule | Out-Null
}

function Write-ReporterConfig {
    param(
        [string]$ConfigPath,
        [string]$UserEmail,
        [string]$InstallationPath,
        [string]$CodexSettingsPath,
        $Jobs
    )

    $config = [ordered]@{
        UserEmail = $UserEmail
        InstallationPath = $InstallationPath
        CodexSettingsPath = $CodexSettingsPath
        Automation = [ordered]@{
            Jobs = @($Jobs)
        }
    }

    $config |
        ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Register-ReporterTask {
    param(
        [string]$TaskName,
        [string]$JobId,
        [string]$InstallPath,
        [string]$Schedule
    )

    $trigger = New-TriggerFromCronSchedule -Schedule $Schedule
    $runScriptPath = Join-Path $InstallPath 'run.py'
    $installPathLiteral = ConvertTo-PowerShellStringLiteral -Value $InstallPath
    $runScriptLiteral = ConvertTo-PowerShellStringLiteral -Value $runScriptPath
    $jobIdLiteral = ConvertTo-PowerShellStringLiteral -Value $JobId
    $taskCommand = "& { Set-Location -LiteralPath $installPathLiteral; python $runScriptLiteral $jobIdLiteral }"
    $action = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$taskCommand`""
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal `
        -UserId $currentUser `
        -LogonType Interactive `
        -RunLevel Limited

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description 'Runs AI usage reporting and sends JSON data to the configured target URL.' `
        -Force | Out-Null
}

function Get-ReporterTaskName {
    param(
        [string]$TaskName,
        [string]$JobId
    )

    return "$TaskName-$JobId"
}

function Sync-ReporterTasks {
    param(
        [string]$TaskName,
        [string]$InstallPath,
        $Jobs
    )

    $expectedTaskNames = @{}

    foreach ($job in @($Jobs)) {
        $jobId = Get-ObjectPropertyValue -Object $job -Name 'Id'
        $enabled = Get-ObjectPropertyValue -Object $job -Name 'Enabled'
        $schedule = Get-ObjectPropertyValue -Object $job -Name 'Schedule'
        $jobTaskName = Get-ReporterTaskName -TaskName $TaskName -JobId $jobId

        if (-not $enabled) {
            Write-Host "Scheduled task '$jobTaskName' skipped because the job is disabled."
            continue
        }

        $expectedTaskNames[$jobTaskName] = $true

        Register-ReporterTask `
            -TaskName $jobTaskName `
            -JobId $jobId `
            -InstallPath $InstallPath `
            -Schedule $schedule
        Write-Host "Scheduled task '$jobTaskName' has been registered."
    }

    $legacyTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($legacyTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Old scheduled task '$TaskName' removed."
    }

    foreach ($task in @(Get-ScheduledTask -TaskName "$TaskName-*" -ErrorAction SilentlyContinue)) {
        if (-not $expectedTaskNames.ContainsKey($task.TaskName)) {
            Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false
            Write-Host "Stale scheduled task '$($task.TaskName)' removed."
        }
    }
}

function Main {
    if ($Update) {
        Write-Host 'Updating UsageReporter...'

        $storedPath = [Environment]::GetEnvironmentVariable($InstallPathEnvVarName, 'User')
        $installPath = if (-not [string]::IsNullOrWhiteSpace($storedPath)) {
            Expand-InstallPath -Path $storedPath
        }
        else {
            $DefaultInstallPath
        }

        $installedConfigPath = Join-Path $installPath 'config.json'
        $installedConfig = Read-JsonFile -Path $installedConfigPath
        if ($null -eq $installedConfig) {
            throw "No existing installation found at '$installPath'. Run without -Update to install."
        }

        # Always fetch fresh files from the source URL so an in-place update
        # (run from the install folder) does not skip files as no-ops.
        foreach ($fileName in $ProjectFiles) {
            Install-ProjectFile `
                -FileName $fileName `
                -InstallPath $installPath `
                -SourceBaseUrl $SourceBaseUrl `
                -ForceRemote
        }

        $automationJobs = Get-AutomationJobsFromConfig -Config $installedConfig
        Sync-ReporterTasks `
            -TaskName $TaskName `
            -InstallPath $installPath `
            -Jobs $automationJobs

        Write-Host ''
        Write-Host 'Update complete.'
        Write-Host "Install path: $installPath"
        return
    }

    Write-Host 'Checking prerequisites...'
    Assert-CommandExists -Name 'python'
    Assert-CommandExists -Name 'npx'

    $sourceConfigPath = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $null
    }
    else {
        Join-Path $PSScriptRoot 'config.json'
    }
    $sourceConfig = if ($sourceConfigPath) { Read-JsonFile -Path $sourceConfigPath } else { $null }

    # Detect an existing installation via the stored env var so a one-line install
    # (no config.json beside the script) can still reuse the previous config.
    $storedInstallPath = [Environment]::GetEnvironmentVariable($InstallPathEnvVarName, 'User')
    $existingInstallConfig = $null
    if (-not [string]::IsNullOrWhiteSpace($storedInstallPath)) {
        $existingInstallPath = Expand-InstallPath -Path $storedInstallPath
        $existingInstallConfig = Read-JsonFile -Path (Join-Path $existingInstallPath 'config.json')
    }

    $defaultInstallationPath = Get-ObjectPropertyValue `
        -Object $sourceConfig `
        -Name 'InstallationPath' `
        -Default (Get-ObjectPropertyValue -Object $existingInstallConfig -Name 'InstallationPath')
    $defaultInstallPath = if ($defaultInstallationPath) {
        Expand-InstallPath -Path $defaultInstallationPath
    }
    elseif (-not [string]::IsNullOrWhiteSpace($storedInstallPath)) {
        Expand-InstallPath -Path $storedInstallPath
    }
    else {
        $DefaultInstallPath
    }

    Write-Host ''
    Write-Host 'Configuration'
    $installPathInput = Read-Value -Prompt 'Installation path' -Default $defaultInstallPath
    $installPath = Expand-InstallPath -Path $installPathInput
    $installedConfigPath = Join-Path $installPath 'config.json'
    $installedConfig = Read-JsonFile -Path $installedConfigPath
    $defaultConfig = if ($sourceConfig) {
        $sourceConfig
    }
    elseif ($installedConfig) {
        $installedConfig
    }
    elseif ($existingInstallConfig) {
        $existingInstallConfig
    }
    else {
        $null
    }

    $defaultEmail = Get-ObjectPropertyValue `
        -Object $defaultConfig `
        -Name 'UserEmail' `
        -Default ''
    $defaultTargetUrl = ''
    $codexSettingsPath = Get-ObjectPropertyValue `
        -Object $defaultConfig `
        -Name 'CodexSettingsPath' `
        -Default $DefaultCodexSettingsPath

    $userEmail = Read-Value -Prompt 'User email' -Default $defaultEmail

    if (Test-HasAutomationJobs -Config $defaultConfig) {
        $automationJobs = Get-AutomationJobsFromConfig -Config $defaultConfig
        Write-Host "Using $(@($automationJobs).Count) automation job(s) from config."
    }
    else {
        $setupDefaultJob = Read-YesNo `
            -Prompt "Set up the default 'daily_report' job (runs every day at 06:00 and reports the previous work day's usage)" `
            -Default $true
        $readArchivedSessions = Read-YesNo `
            -Prompt 'Read archived Codex sessions for default job' `
            -Default $false
        $targetUrl = Read-TargetUrl -Default $defaultTargetUrl
        $automationData = Get-DefaultAutomationData
        $automationJobs = @(
            New-DefaultAutomationJob `
                -Enabled $setupDefaultJob `
                -ReadArchivedSessions $readArchivedSessions `
                -Schedule '0 6 * * *' `
                -TargetUrl $targetUrl `
                -Data $automationData
        )
        Write-Host ''
        Write-Host 'For more automation jobs or advanced configuration, edit the config file after installation.'
    }

    foreach ($job in @($automationJobs)) {
        Assert-AutomationJob -Job $job
    }

    New-Item -ItemType Directory -Path $installPath -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $installPath 'logs') -Force | Out-Null

    foreach ($fileName in $ProjectFiles) {
        Install-ProjectFile `
            -FileName $fileName `
            -InstallPath $installPath `
            -SourceBaseUrl $SourceBaseUrl
    }

    $configPath = Join-Path $installPath 'config.json'
    Write-ReporterConfig `
        -ConfigPath $configPath `
        -UserEmail $userEmail `
        -InstallationPath $installPath `
        -CodexSettingsPath $codexSettingsPath `
        -Jobs $automationJobs

    Sync-ReporterTasks `
        -TaskName $TaskName `
        -InstallPath $installPath `
        -Jobs $automationJobs

    Set-InstallPathEnvironmentVariable `
        -Name $InstallPathEnvVarName `
        -InstallPath $installPath

    Write-Host ''
    Write-Host 'Installation complete.'
    Write-Host "Install path: $installPath"
    Write-Host "Install path env var: $InstallPathEnvVarName"
    Write-Host "Config path: $configPath"
    Write-Host "Log path: $(Join-Path $installPath 'logs\run.log')"
    Write-Host "Manual run: python `"$((Join-Path $installPath 'run.py'))`" <job-id> [<job-id> ...]"
    Write-Host "Task check: Get-ScheduledTask -TaskName '$TaskName-*'"
}

Main
