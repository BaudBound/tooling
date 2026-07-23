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
    [ValidateSet("Runner", "RunnerRelease", "Editor", "Website", "GetService", "Contracts", "Checks", "Builds", "Install")]
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
        if ($RunnerAction) {
            if ($RunnerAction -eq "RunnerBuild") {
                if (-not $RunnerBuildPlatform) {
                    throw "RunnerBuild requires -Platform Both, Linux, or Windows."
                }
                Invoke-DevelopmentTask -Task $RunnerAction -RunnerBuildPlatform $RunnerBuildPlatform
            } else {
                Invoke-DevelopmentTask -Task $RunnerAction
            }
            return
        }

        while ($true) {
            $selectedAction = Select-DevelopmentAction
            if (-not $selectedAction) {
                return
            }

            $selectedPlatform = $null
            if ($selectedAction -eq "RunnerBuild") {
                $selectedPlatform = Select-RunnerBuildPlatform
                if (-not $selectedPlatform) {
                    continue
                }
            }

            try {
                if ($selectedAction -eq "RunnerBuild") {
                    Invoke-DevelopmentTask -Task $selectedAction -RunnerBuildPlatform $selectedPlatform
                } else {
                    Invoke-DevelopmentTask -Task $selectedAction
                }
            } catch {
                Write-Host ""
                Write-Host "Development task failed" -ForegroundColor Red
                Write-Host $_.Exception.Message -ForegroundColor Red
            }
            Wait-ForDevelopmentMenu
        }
    } finally {
        Pop-Location
    }
}

function Invoke-RunnerRelease {
    $runnerReleaseTool = Join-Path $PSScriptRoot "release.ps1"
    if (-not (Test-Path -LiteralPath $runnerReleaseTool -PathType Leaf)) {
        throw "Runner release helper was not found at $runnerReleaseTool."
    }
    & $runnerReleaseTool
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
        "RunnerRelease" {
            Invoke-RunnerRelease
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
        [PSCustomObject]@{ Value = "Runner"; Label = "Runner"; Description = "Open the runner-owned development menu." },
        [PSCustomObject]@{ Value = "RunnerRelease"; Label = "Runner release"; Description = "Open the guarded runner release menu." },
        [PSCustomObject]@{ Value = "Editor"; Label = "Editor"; Description = "Start the editor development server." },
        [PSCustomObject]@{ Value = "Website"; Label = "Website"; Description = "Start the website development server." },
        [PSCustomObject]@{ Value = "GetService"; Label = "Get service"; Description = "Build and run get.baudbound.app with Docker Compose." },
        [PSCustomObject]@{ Value = "Contracts"; Label = "Validate contracts"; Description = "Validate all shared JSON contracts." },
        [PSCustomObject]@{ Value = "Checks"; Label = "Workspace checks"; Description = "Run static checks and tests across maintained code repositories." },
        [PSCustomObject]@{ Value = "Builds"; Label = "Workspace builds"; Description = "Build the runner, editor, website, and get service." },
        [PSCustomObject]@{ Value = "Install"; Label = "Install dependencies"; Description = "Install locked runner UI, editor, and website dependencies." },
        [PSCustomObject]@{ Value = $null; Label = "Exit"; Description = "Close the workspace helper." }
    )
    return Select-TerminalMenu -Title "BaudBound workspace development" -Options $options
}

function Wait-ForWorkspaceMenu {
    Write-Host ""
    Write-Host "Press any key to return to the workspace menu." -ForegroundColor DarkGray
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
        try {
            Invoke-WorkspaceAction -SelectedAction $selectedAction
        } catch {
            Write-Host ""
            Write-Host "Workspace task failed" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
        Wait-ForWorkspaceMenu
    }
} finally {
    [Console]::InputEncoding = $previousConsoleInputEncoding
    [Console]::OutputEncoding = $previousConsoleOutputEncoding
    $OutputEncoding = $previousOutputEncoding
}
