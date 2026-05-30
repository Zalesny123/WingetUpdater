# Changelog

## [1.0.0] - 2026-05-30

### Added

- First stable release of the **WingetUpdater** project.
- Graphical user interface for checking and updating packages through `winget`.
- Automatic check for available updates when the program starts.
- Support for packages with an unknown version through the `--include-unknown` option.
- Ability to select specific packages for update.
- Ability to skip selected packages.
- Persistent skipped-package list saved in the `skip-list.json` file.
- `Start.bat` launcher as the intended way to start the program.
- Automatic detection of the available runtime environment: CMD, Windows PowerShell 5.1, or PowerShell 7+.
- Support for elevated operations when required by package updates.
- Support for refreshing the winget source database before checking for updates.
- Support for silent mode and interactive installer mode where supported by `winget`.
- Support for repairing packages with an unknown version through the **Repair Unknown** feature.
- Generation of diagnostic context for an AI agent when repairing Unknown packages.
- MIT license support.

### Requirements

- Windows.
- Windows Package Manager (`winget`).
- Windows PowerShell 5.1 or PowerShell 7+.

### Safety notes

- The program should be started through `Start.bat`.
- The launcher displays the license text before the first run and saves a local acceptance marker.
- The diagnostic context for the AI agent is designed for safe research and does not assume changes without explicit user confirmation.
