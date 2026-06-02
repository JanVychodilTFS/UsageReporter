param(
    [string]$TaskName = 'UsageReporter',
    [string]$InstallPath = "$env:LOCALAPPDATA\UsageReporter"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $false
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

function Main {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Scheduled task '$TaskName' removed."
    }
    else {
        Write-Host "Scheduled task '$TaskName' was not found."
    }

    $expandedInstallPath = [Environment]::ExpandEnvironmentVariables($InstallPath)
    if (-not (Test-Path -LiteralPath $expandedInstallPath)) {
        Write-Host "Install folder not found: $expandedInstallPath"
        return
    }

    $removeFiles = Read-YesNo `
        -Prompt "Remove installed files at '$expandedInstallPath'?" `
        -Default $false

    if ($removeFiles) {
        Remove-Item -LiteralPath $expandedInstallPath -Recurse -Force
        Write-Host "Install folder removed: $expandedInstallPath"
    }
    else {
        Write-Host "Installed files kept: $expandedInstallPath"
    }
}

Main
