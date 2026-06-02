param(
    [string]$SourceBaseUrl = 'https://raw.githubusercontent.com/OWNER/REPO/main',
    [string]$TaskName = 'UsageReporter'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DefaultInstallPath = Join-Path $env:LOCALAPPDATA 'UsageReporter'
$ProjectFiles = @('usage_reporter.py', 'run.py', 'test.py')

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
        [string]$SourceBaseUrl
    )

    $destination = Join-Path $InstallPath $FileName
    $localSource = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $null
    }
    else {
        Join-Path $PSScriptRoot $FileName
    }

    if ($localSource -and (Test-Path -LiteralPath $localSource)) {
        if ((Test-Path -LiteralPath $destination) -and
            ((Resolve-Path -LiteralPath $localSource).Path -eq (Resolve-Path -LiteralPath $destination).Path)) {
            return
        }

        Copy-Item -LiteralPath $localSource -Destination $destination -Force
        return
    }

    if ($SourceBaseUrl -match 'OWNER/REPO') {
        throw 'SourceBaseUrl still contains OWNER/REPO placeholder. Update install.ps1 before one-line GitHub installation.'
    }

    $sourceUrl = $SourceBaseUrl.TrimEnd('/') + '/' + $FileName
    Invoke-WebRequest -Uri $sourceUrl -OutFile $destination
}

function Get-DefaultAutomationData {
    param($SourceConfig)

    $automation = Get-ObjectPropertyValue -Object $SourceConfig -Name 'Automation'
    $data = Get-ObjectPropertyValue -Object $automation -Name 'Data'
    if ($data) {
        return $data
    }

    return @(
        [ordered]@{
            Agent = 'codex'
            QueryType = 'lastWeek'
        },
        [ordered]@{
            Agent = 'codex'
            QueryType = 'yesterdaySessions'
        }
    )
}

function Write-ReporterConfig {
    param(
        [string]$ConfigPath,
        [string]$UserEmail,
        [string]$InstallationPath,
        [bool]$AutomationEnabled,
        [string]$Schedule,
        [string]$TargetUrl,
        $Data
    )

    $config = [ordered]@{
        UserEmail = $UserEmail
        InstallationPath = $InstallationPath
        Automation = [ordered]@{
            Enabled = $AutomationEnabled
            Schedule = $Schedule
            TargetURL = $TargetUrl
            Data = $Data
        }
    }

    $config |
        ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Register-ReporterTask {
    param(
        [string]$TaskName,
        [string]$InstallPath,
        [string]$Schedule
    )

    $trigger = New-TriggerFromCronSchedule -Schedule $Schedule
    $logPath = Join-Path $InstallPath 'logs\run.log'
    $runScriptPath = Join-Path $InstallPath 'run.py'
    $installPathLiteral = ConvertTo-PowerShellStringLiteral -Value $InstallPath
    $runScriptLiteral = ConvertTo-PowerShellStringLiteral -Value $runScriptPath
    $logPathLiteral = ConvertTo-PowerShellStringLiteral -Value $logPath
    $taskCommand = "& { Set-Location -LiteralPath $installPathLiteral; python $runScriptLiteral *>> $logPathLiteral }"
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
        -RunLevel LeastPrivilege

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description 'Runs AI usage reporting and sends JSON data to the configured target URL.' `
        -Force | Out-Null
}

function Main {
    Write-Host 'Checking prerequisites...'
    Assert-CommandExists -Name 'python'
    Assert-CommandExists -Name 'ccusage'

    $sourceConfigPath = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $null
    }
    else {
        Join-Path $PSScriptRoot 'config.json'
    }
    $sourceConfig = if ($sourceConfigPath) { Read-JsonFile -Path $sourceConfigPath } else { $null }

    $sourceAutomation = Get-ObjectPropertyValue -Object $sourceConfig -Name 'Automation'
    $defaultEmail = Get-ObjectPropertyValue `
        -Object $sourceConfig `
        -Name 'UserEmail' `
        -Default ''
    $defaultInstallationPath = Get-ObjectPropertyValue `
        -Object $sourceConfig `
        -Name 'InstallationPath'
    $defaultInstallPath = if ($defaultInstallationPath) {
        Expand-InstallPath -Path $defaultInstallationPath
    }
    else {
        $DefaultInstallPath
    }
    $defaultSchedule = Get-ObjectPropertyValue `
        -Object $sourceAutomation `
        -Name 'Schedule' `
        -Default '0 6 * * 1'
    $defaultTargetUrl = Get-ObjectPropertyValue `
        -Object $sourceAutomation `
        -Name 'TargetURL' `
        -Default ''
    $defaultAutomationEnabled = [bool](Get-ObjectPropertyValue `
        -Object $sourceAutomation `
        -Name 'Enabled' `
        -Default $true)

    Write-Host ''
    Write-Host 'Configuration'
    $userEmail = Read-Value -Prompt 'User email' -Default $defaultEmail
    $targetUrl = Read-TargetUrl -Default $defaultTargetUrl
    $installPathInput = Read-Value -Prompt 'Installation path' -Default $defaultInstallPath
    $installPath = Expand-InstallPath -Path $installPathInput
    $automationEnabled = Read-YesNo -Prompt 'Enable scheduled automation' -Default $defaultAutomationEnabled
    $schedule = Read-Value -Prompt 'Schedule cron expression' -Default $defaultSchedule
    $automationData = Get-DefaultAutomationData -SourceConfig $sourceConfig

    New-TriggerFromCronSchedule -Schedule $schedule | Out-Null

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
        -AutomationEnabled $automationEnabled `
        -Schedule $schedule `
        -TargetUrl $targetUrl `
        -Data $automationData

    if ($automationEnabled) {
        Register-ReporterTask `
            -TaskName $TaskName `
            -InstallPath $installPath `
            -Schedule $schedule
        Write-Host "Scheduled task '$TaskName' has been registered."
    }
    else {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "Scheduled task '$TaskName' was removed because automation is disabled."
        }
    }

    Write-Host ''
    Write-Host 'Installation complete.'
    Write-Host "Install path: $installPath"
    Write-Host "Config path: $configPath"
    Write-Host "Log path: $(Join-Path $installPath 'logs\run.log')"
    Write-Host "Manual run: python `"$((Join-Path $installPath 'run.py'))`""
    Write-Host "Task check: Get-ScheduledTask -TaskName $TaskName"
}

Main
