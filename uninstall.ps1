param(
    [string]$TaskName = 'UsageReporter',
    [string]$InstallPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$InstallPathEnvVarName = 'USAGE_REPORTER_INSTALL_PATH'
$DefaultInstallPath = Join-Path $env:LOCALAPPDATA 'UsageReporter'

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

function Resolve-InstallPath {
    param(
        [string]$InstallPath,
        [string]$EnvVarName
    )

    if (-not [string]::IsNullOrWhiteSpace($InstallPath)) {
        return [System.IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables($InstallPath)
        )
    }

    $storedInstallPath = [Environment]::GetEnvironmentVariable($EnvVarName, 'User')
    if ([string]::IsNullOrWhiteSpace($storedInstallPath)) {
        $storedInstallPath = [Environment]::GetEnvironmentVariable($EnvVarName, 'Process')
    }

    if (-not [string]::IsNullOrWhiteSpace($storedInstallPath)) {
        return [System.IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables($storedInstallPath)
        )
    }

    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($DefaultInstallPath)
    )
}

function Remove-InstallPathEnvironmentVariable {
    param([string]$Name)

    if ($null -ne [Environment]::GetEnvironmentVariable($Name, 'User')) {
        [Environment]::SetEnvironmentVariable($Name, $null, 'User')
    }

    if (Test-Path -LiteralPath "Env:$Name") {
        Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue
    }
}

function Test-PathIsInDirectory {
    param(
        [string]$Path,
        [string]$Directory
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $fullDirectory = [System.IO.Path]::GetFullPath($Directory).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )

    return $fullPath.Equals($fullDirectory, [System.StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith(
            $fullDirectory + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase
        )
}

function Move-OutOfInstallPath {
    param([string]$InstallPath)

    $currentPath = (Get-Location).ProviderPath
    if ($currentPath -and (Test-PathIsInDirectory -Path $currentPath -Directory $InstallPath)) {
        Set-Location -LiteralPath ([System.IO.Path]::GetTempPath())
    }
}

function Remove-ReporterTasks {
    param([string]$TaskName)

    $legacyTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($legacyTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Scheduled task '$TaskName' removed."
    }

    $jobTasks = @(Get-ScheduledTask -TaskName "$TaskName-*" -ErrorAction SilentlyContinue)
    foreach ($task in $jobTasks) {
        Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false
        Write-Host "Scheduled task '$($task.TaskName)' removed."
    }

    if (-not $legacyTask -and $jobTasks.Count -eq 0) {
        Write-Host "Scheduled task '$TaskName' was not found."
    }
}

function Main {
    Remove-ReporterTasks -TaskName $TaskName

    $expandedInstallPath = Resolve-InstallPath `
        -InstallPath $InstallPath `
        -EnvVarName $InstallPathEnvVarName

    if (-not (Test-Path -LiteralPath $expandedInstallPath)) {
        Write-Host "Install folder not found: $expandedInstallPath"
        Remove-InstallPathEnvironmentVariable -Name $InstallPathEnvVarName
        Write-Host "Install path environment variable '$InstallPathEnvVarName' removed."
        return
    }

    $removeFiles = Read-YesNo `
        -Prompt "Remove installed files at '$expandedInstallPath'?" `
        -Default $false

    if ($removeFiles) {
        Move-OutOfInstallPath -InstallPath $expandedInstallPath
        Remove-Item -LiteralPath $expandedInstallPath -Recurse -Force
        Write-Host "Install folder removed: $expandedInstallPath"
    }
    else {
        Write-Host "Installed files kept: $expandedInstallPath"
    }

    Remove-InstallPathEnvironmentVariable -Name $InstallPathEnvVarName
    Write-Host "Install path environment variable '$InstallPathEnvVarName' removed."
}

Main
