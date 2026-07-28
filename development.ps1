<#
.SYNOPSIS
Launches development tasks across the BaudBound repositories.

.EXAMPLE
./development.ps1

.EXAMPLE
./development.ps1 -Action Editor

.EXAMPLE
./development.ps1 -Action Checks
#>
[CmdletBinding()]
param(
    [ValidateSet("Runner", "Editor", "Website", "GetService", "Contracts", "Checks", "Builds", "Install")]
    [string]$Action,

    [ValidateSet("Desktop", "DesktopUi", "Service", "Status", "Install", "Checks", "Tests", "Build", "RunnerBuild")]
    [string]$RunnerAction,

    [ValidateSet("Both", "Linux", "Windows")]
    [string]$Platform
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$previousConsoleInputEncoding = [Console]::InputEncoding
$previousConsoleOutputEncoding = [Console]::OutputEncoding
$previousOutputEncoding = $OutputEncoding
$utf8Encoding = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8Encoding
[Console]::OutputEncoding = $utf8Encoding
$OutputEncoding = $utf8Encoding

$script:WorkspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$toolingLibrary = Join-Path $PSScriptRoot "lib"
. (Join-Path $toolingLibrary "terminal-menu.ps1")
. (Join-Path $toolingLibrary "runner-development-menu.ps1")
. (Join-Path $toolingLibrary "runner-development-tasks.ps1")
. (Join-Path $toolingLibrary "runner-build.ps1")

function Get-WorkspaceRepositoryPath {
    param([Parameter(Mandatory)][string]$Name)

    $path = [IO.Path]::GetFullPath((Join-Path $script:WorkspaceRoot $Name))
    if (-not $path.StartsWith($script:WorkspaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Repository path escaped the BaudBound workspace: $Name"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "Required sibling repository '$Name' was not found at $path."
    }
    return $path
}

function Require-WorkspaceCommand {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Invoke-WorkspaceCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter()][string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$Repository
    )

    Require-WorkspaceCommand $Command
    $workingDirectory = Get-WorkspaceRepositoryPath $Repository
    Write-Host "`n==> [$Repository] $Command $($Arguments -join ' ')" -ForegroundColor Cyan
    Push-Location $workingDirectory
    try {
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command '$Command $($Arguments -join ' ')' failed in $Repository with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
}

function Invoke-RunnerDevelopment {
    param(
        [string]$RunnerAction,
        [string]$RunnerBuildPlatform
    )

    $runnerRoot = Get-WorkspaceRepositoryPath "baudbound"
    Push-Location $runnerRoot
    try {
        if (-not $RunnerAction) {
            throw "Runner actions require -RunnerAction."
        }

        if ($RunnerAction -eq "RunnerBuild") {
            if (-not $RunnerBuildPlatform) {
                throw "RunnerBuild requires -Platform Both, Linux, or Windows."
            }
            Invoke-DevelopmentTask -Task $RunnerAction -RunnerBuildPlatform $RunnerBuildPlatform
        } else {
            Invoke-DevelopmentTask -Task $RunnerAction
        }
    } finally {
        Pop-Location
    }
}

function Invoke-WorkspaceAction {
    param(
        [Parameter(Mandatory)][string]$SelectedAction,
        [string]$SelectedRunnerAction,
        [string]$SelectedPlatform
    )

    switch ($SelectedAction) {
        "Runner" {
            Invoke-RunnerDevelopment -RunnerAction $SelectedRunnerAction -RunnerBuildPlatform $SelectedPlatform
        }
        "Editor" {
            Invoke-WorkspaceCommand "pnpm" @("dev") -Repository "editor"
        }
        "Website" {
            Invoke-WorkspaceCommand "pnpm" @("dev") -Repository "website"
        }
        "GetService" {
            Invoke-WorkspaceCommand "docker" @("compose", "up", "--build") -Repository "get"
        }
        "Contracts" {
            Invoke-WorkspaceCommand "node" @("scripts/validate.mjs") -Repository "contracts"
        }
        "Checks" {
            Invoke-RunnerDevelopment -RunnerAction "Checks"
            Invoke-WorkspaceCommand "node" @("scripts/validate.mjs") -Repository "contracts"
            Invoke-WorkspaceCommand "pnpm" @("lint") -Repository "editor"
            Invoke-WorkspaceCommand "pnpm" @("typecheck") -Repository "editor"
            Invoke-WorkspaceCommand "pnpm" @("schemas:check") -Repository "editor"
            Invoke-WorkspaceCommand "pnpm" @("test") -Repository "editor"
            Invoke-WorkspaceCommand "pnpm" @("lint") -Repository "website"
            Invoke-WorkspaceCommand "pnpm" @("typecheck") -Repository "website"
        }
        "Builds" {
            Invoke-RunnerDevelopment -RunnerAction "Build"
            Invoke-WorkspaceCommand "pnpm" @("build") -Repository "editor"
            Invoke-WorkspaceCommand "pnpm" @("build") -Repository "website"
            Invoke-WorkspaceCommand "docker" @("compose", "build") -Repository "get"
        }
        "Install" {
            Invoke-RunnerDevelopment -RunnerAction "Install"
            Invoke-WorkspaceCommand "pnpm" @("install", "--frozen-lockfile") -Repository "editor"
            Invoke-WorkspaceCommand "pnpm" @("install", "--frozen-lockfile") -Repository "website"
        }
        default {
            throw "Unknown workspace action: $SelectedAction"
        }
    }
}

function Select-WorkspaceAction {
    $options = @(
        [PSCustomObject]@{ Selectable = $false; Label = "RUNNER"; Description = "" },
        [PSCustomObject]@{ Value = "RunnerDesktop"; Label = "Start desktop app"; Description = "Launch Tauri, Vite, and the Rust desktop runner." },
        [PSCustomObject]@{ Value = "RunnerDesktopUi"; Label = "Start desktop UI only"; Description = "Start the Vite frontend at http://127.0.0.1:1420." },
        [PSCustomObject]@{ Value = "RunnerService"; Label = "Run trigger service"; Description = "Run long-lived trigger listeners in the foreground." },
        [PSCustomObject]@{ Value = "RunnerStatus"; Label = "Show runner status"; Description = "Print current runner and background-service health." },
        [PSCustomObject]@{ Value = "RunnerInstall"; Label = "Install dependencies"; Description = "Install exact locked desktop UI packages." },
        [PSCustomObject]@{ Value = "RunnerChecks"; Label = "Run checks"; Description = "Run Rust and desktop UI static checks." },
        [PSCustomObject]@{ Value = "RunnerTests"; Label = "Run tests"; Description = "Run Rust and desktop UI tests." },
        [PSCustomObject]@{ Value = "RunnerBuild"; Label = "Build runner"; Description = "Build the desktop UI and runner application." },
        [PSCustomObject]@{ Value = "RunnerPackages"; Label = "Build runner packages"; Description = "Build local Windows, Linux, or both runner packages." },
        [PSCustomObject]@{ Selectable = $false; Label = "EDITOR"; Description = "" },
        [PSCustomObject]@{ Value = "Editor"; Label = "Start editor"; Description = "Start the editor development server." },
        [PSCustomObject]@{ Selectable = $false; Label = "WEBSITE"; Description = "" },
        [PSCustomObject]@{ Value = "Website"; Label = "Start website"; Description = "Start the website development server." },
        [PSCustomObject]@{ Selectable = $false; Label = "GET SERVICE"; Description = "" },
        [PSCustomObject]@{ Value = "GetService"; Label = "Start get service"; Description = "Build and run get.baudbound.app with Docker Compose." },
        [PSCustomObject]@{ Selectable = $false; Label = "CONTRACTS"; Description = "" },
        [PSCustomObject]@{ Value = "Contracts"; Label = "Validate contracts"; Description = "Validate all shared JSON contracts." },
        [PSCustomObject]@{ Selectable = $false; Label = "WORKSPACE"; Description = "" },
        [PSCustomObject]@{ Value = "Install"; Label = "Install dependencies"; Description = "Install locked runner UI, editor, and website dependencies." },
        [PSCustomObject]@{ Value = "Checks"; Label = "Run checks"; Description = "Run static checks and tests across maintained code repositories." },
        [PSCustomObject]@{ Value = "Builds"; Label = "Build all projects"; Description = "Build the runner, editor, website, and get service." },
        [PSCustomObject]@{ Value = $null; Label = "Exit"; Description = "Close the workspace helper." }
    )
    return Select-TerminalMenu -Title "BaudBound development" -Options $options
}

function Wait-ForCompletedWorkspaceAction {
    Write-Host ""
    Write-Host "Press any key to return to the development menu." -ForegroundColor DarkGray
    [Console]::ReadKey($true) | Out-Null
}

try {
    if ($RunnerAction -and $Action -ne "Runner") {
        throw "-RunnerAction can only be used with -Action Runner."
    }
    if ($Platform -and ($Action -ne "Runner" -or $RunnerAction -ne "RunnerBuild")) {
        throw "-Platform can only be used with -Action Runner -RunnerAction RunnerBuild."
    }
    if ($Action) {
        Invoke-WorkspaceAction -SelectedAction $Action -SelectedRunnerAction $RunnerAction -SelectedPlatform $Platform
        return
    }

    while ($true) {
        $selectedAction = Select-WorkspaceAction
        if (-not $selectedAction) {
            Write-Host "Workspace helper closed."
            return
        }
        $actionAttempted = $false
        try {
            switch ($selectedAction) {
                "RunnerDesktop" {
                    $actionAttempted = $true
                    Invoke-WorkspaceAction -SelectedAction "Runner" -SelectedRunnerAction "Desktop"
                }
                "RunnerDesktopUi" {
                    $actionAttempted = $true
                    Invoke-WorkspaceAction -SelectedAction "Runner" -SelectedRunnerAction "DesktopUi"
                }
                "RunnerService" {
                    $actionAttempted = $true
                    Invoke-WorkspaceAction -SelectedAction "Runner" -SelectedRunnerAction "Service"
                }
                "RunnerStatus" {
                    $actionAttempted = $true
                    Invoke-WorkspaceAction -SelectedAction "Runner" -SelectedRunnerAction "Status"
                }
                "RunnerInstall" {
                    $actionAttempted = $true
                    Invoke-WorkspaceAction -SelectedAction "Runner" -SelectedRunnerAction "Install"
                }
                "RunnerChecks" {
                    $actionAttempted = $true
                    Invoke-WorkspaceAction -SelectedAction "Runner" -SelectedRunnerAction "Checks"
                }
                "RunnerTests" {
                    $actionAttempted = $true
                    Invoke-WorkspaceAction -SelectedAction "Runner" -SelectedRunnerAction "Tests"
                }
                "RunnerBuild" {
                    $actionAttempted = $true
                    Invoke-WorkspaceAction -SelectedAction "Runner" -SelectedRunnerAction "Build"
                }
                "RunnerPackages" {
                    $selectedPlatform = Select-RunnerBuildPlatform
                    if ($selectedPlatform) {
                        $actionAttempted = $true
                        Invoke-WorkspaceAction -SelectedAction "Runner" -SelectedRunnerAction "RunnerBuild" -SelectedPlatform $selectedPlatform
                    }
                }
                default {
                    $actionAttempted = $true
                    Invoke-WorkspaceAction -SelectedAction $selectedAction
                }
            }
        } catch {
            Write-Host ""
            Write-Host "Workspace task failed" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
        if ($actionAttempted) {
            Wait-ForCompletedWorkspaceAction
        }
    }
} finally {
    [Console]::InputEncoding = $previousConsoleInputEncoding
    [Console]::OutputEncoding = $previousConsoleOutputEncoding
    $OutputEncoding = $previousOutputEncoding
}
