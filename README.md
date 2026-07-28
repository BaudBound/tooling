# BaudBound Tooling

Cross-repository development commands for the BaudBound project.

## Workspace layout

Clone this repository beside the other BaudBound repositories:

```text
BaudBound/
  baudbound/
  contracts/
  documentation/
  editor/
  get/
  repository/
  tooling/
  website/
```

Runner development, local build, and release helpers live in this repository. They operate on the sibling `baudbound` repository. The development helper coordinates tasks that span multiple repositories. Releases are handled separately by `release.ps1`.

## Usage

Open the interactive menu from the tooling repository:

```powershell
./development.ps1
```

Run one action without the menu:

```powershell
./development.ps1 -Action Checks
```

Supported actions are `Runner`, `Editor`, `Website`, `GetService`, `Contracts`, `Checks`, `Builds`, and `Install`.

Runner-only commands can also be started directly:

```powershell
./release.ps1
./development.ps1 -Action Runner -RunnerAction Checks
./development.ps1 -Action Runner -RunnerAction RunnerBuild -Platform Both
```

The helper requires Windows PowerShell or PowerShell 7. Individual actions also require the tools used by their repositories, including Rust, Node.js, pnpm, and Docker.
