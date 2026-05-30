# WingetUpdater

![Platform](https://img.shields.io/badge/platform-Windows-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

**Version:** 1.0.0

**WingetUpdater** is a graphical Windows tool that helps you check and update installed packages using Windows Package Manager (`winget`).

The application provides a simple GUI for reviewing available updates, selecting which packages should be updated, skipping selected packages, and diagnosing packages reported by `winget` with an unknown installed version.

## Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Download](#download)
- [Running the application](#running-the-application)
- [How to use](#how-to-use)
- [Skipped packages](#skipped-packages)
- [Updates and administrator privileges](#updates-and-administrator-privileges)
- [Repair Unknown packages](#repair-unknown-packages)
- [Mock test mode](#mock-test-mode)
- [Files created locally](#files-created-locally)
- [Important notice](#important-notice)
- [Security notes](#security-notes)
- [Known limitations](#known-limitations)
- [Reporting issues](#reporting-issues)
- [Changelog](#changelog)
- [License](#license)
- [Maintainers](#maintainers)

## Features

- Graphical user interface for `winget upgrade`.
- Automatic update check when the application starts.
- Support for packages with an unknown installed version through `--include-unknown`.
- Ability to select specific packages for update.
- Ability to mark selected packages as skipped.
- Persistent skipped-package list saved in `skip-list.json`.
- Automatic loading of previously skipped packages on startup.
- Optional `winget source update` before checking for updates.
- Support for silent mode through `--silent`, when supported by the installed `winget` version.
- Support for interactive installer mode through `--interactive`, when supported by the installed `winget` version.
- Detection of packages that may require administrator privileges.
- UAC elevation only for update operations that require it.
- **Repair Unknown** feature that generates diagnostic context for a CLI AI agent.
- **Mock** test mode for safe simulation without modifying the system.

## Requirements

- Windows.
- Windows Package Manager (`winget`).
- Windows PowerShell 5.1 or PowerShell 7+.
- `Start.bat` and `WingetUpdater.ps1` must be located in the same directory.

Optional, only for the **Repair Unknown** feature:

- Codex CLI or Gemini CLI available in `PATH`.

## Download

Download the latest release from the **Releases** section.

Recommended release archive:

```text
WingetUpdater-v1.0.0.zip
```

After downloading, extract the archive to a directory of your choice.

Expected archive contents:

```text
WingetUpdater-v1.0.0/
├─ Start.bat
├─ WingetUpdater.ps1
├─ README.md
├─ CHANGELOG.md
└─ LICENSE
```

## Running the application

Start the application by running:

```text
Start.bat
```

Do not run `WingetUpdater.ps1` directly.

`Start.bat` is the application launcher. It checks which runtime environments are available, including CMD, Windows PowerShell 5.1, and PowerShell 7, and then starts the main application script.

The GUI itself does not need to be started as administrator from the beginning. Update operations that require elevated privileges are handled separately through UAC.

## How to use

1. Run `Start.bat`.
2. The application automatically checks available updates using `winget upgrade`.
3. By default, packages with an unknown installed version are also included through `--include-unknown`.
4. Select the packages you want to update.
5. Mark packages you do not want to update as **Skip**.
6. Click **Save skipped** to store the skipped-package list.
7. Click **Update selected** to start updating the selected packages.
8. Confirm the package list before the update begins.

## Skipped packages

WingetUpdater stores skipped packages in:

```text
skip-list.json
```

This file is created locally next to the application script.

On the next launch, packages saved in this file are automatically marked as **Skip**.

`skip-list.json` is not included in the release archive because it is a user-specific local file.

## Updates and administrator privileges

WingetUpdater uses `winget` to check and update packages.

Before updating, the application attempts to group packages by the type of privileges they require:

- user-scoped packages, which usually do not require administrator privileges,
- machine-scoped packages, which may require UAC confirmation.

This means the entire GUI does not need to run as administrator all the time. Elevated privileges are requested only for operations that require them.

## Repair Unknown packages

The **Repair Unknown** feature helps diagnose packages that `winget` reports with the installed version shown as `Unknown`.

To use this feature:

1. Make sure Codex CLI or Gemini CLI is installed.
2. Make sure the selected CLI is available in `PATH`.
3. Select the terminal:
   - PowerShell 7 admin,
   - PowerShell 5 admin,
   - CMD admin.
4. Select the agent:
   - Codex CLI,
   - Gemini CLI.
5. Click **Repair Unknown**.

The application creates a diagnostic context file in:

```text
repair-contexts/
```

It then opens the selected terminal with administrator privileges and passes the diagnostic instructions to the selected CLI agent.

The generated context is designed for a safe workflow: research and diagnosis first, then any changes only after explicit user confirmation.

## Mock test mode

WingetUpdater includes a **Mock** test mode that simulates `winget` behavior.

Mock test mode:

- does not update real packages,
- does not modify the system,
- creates a local test file at `Tests/MockState.json`,
- is useful for testing the interface and application logic safely.

This mode is intended mainly for diagnostics and development.

## Files created locally

The application may create the following local files and directories:

```text
skip-list.json
.license-accepted
repair-contexts/
Tests/
```

Meaning:

- `skip-list.json` — packages marked as skipped by the user.
- `.license-accepted` — local marker indicating that the license was accepted.
- `repair-contexts/` — diagnostic files generated by the **Repair Unknown** feature.
- `Tests/` — data used by Mock test mode.

These files should not be included in the release archive.

## Important notice

WingetUpdater is a GUI wrapper around `winget` operations. Package metadata, installers, update behavior, and installation results depend on Windows Package Manager and the package manifests available from its configured sources.

Before updating packages, review the package name, package ID, source, and update target.

Installers are provided by their respective publishers. Some installers may show their own dialogs, require manual interaction, request elevation, ignore silent mode, or fail independently of WingetUpdater.

You are responsible for the software updates you choose to run.

## Security notes

- Run the application through `Start.bat`.
- The launcher displays the license text before the first run.
- UAC may be requested for update operations that require administrator privileges.
- The **Repair Unknown** feature generates diagnostic context for an external CLI agent.
- The diagnostic workflow is intended to avoid changes without explicit user confirmation.
- Be careful when updating software from any package manager source.
- Only update software from sources and publishers you trust.

## Known limitations

- WingetUpdater is intended for Windows only.
- The application requires `winget` to be available.
- Some installers may ignore silent mode.
- Some installers may require manual user interaction.
- Some packages may require UAC confirmation.
- The **Repair Unknown** feature requires Codex CLI or Gemini CLI.
- Update results depend on the installed `winget` version, configured sources, and available package manifests.

## Reporting issues

When reporting a problem, include:

- Windows version.
- `winget` version.
- PowerShell version.
- WingetUpdater version.
- Steps to reproduce the issue.
- Error message or relevant log output from the application.
- Package ID, if the issue affects a specific package.

Do not publish private data, personal paths, access tokens, API keys, or any other sensitive information in issue reports or logs.

## Changelog

See:

```text
CHANGELOG.md
```

## License

This project is licensed under the MIT License.

See:

```text
LICENSE
```

## Maintainers

- **Zalesny123**
