function Select-RunnerBuildPlatform {
    $options = @(
        [PSCustomObject]@{ Value = "Both"; Label = "Both"; Description = "Build the Windows installer and all Linux packages." },
        [PSCustomObject]@{ Value = "Linux"; Label = "Linux"; Description = "Build the Linux AppImage, Debian package, and RPM package." },
        [PSCustomObject]@{ Value = "Windows"; Label = "Windows"; Description = "Build the Windows NSIS installer." },
        [PSCustomObject]@{ Value = $null; Label = "Back"; Description = "Return to the development menu." }
    )
    return Select-TerminalMenu -Title "Runner build platform" -Options $options
}
