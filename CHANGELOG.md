# Changelog

## [1.0.1] - 2026-07-21

### Security
- Removed custom `RunAs` elevated script generation and code interpolation. Package updates run as non-elevated user, triggering native Windows installer UAC prompts when required.
- Implemented robust `Join-CommandLineArguments` escaping in `WingetUpdater.Core.psm1` adhering to Windows CLI escaping rules.
- Launched AI CLI tools (`codex`, `agy`) non-elevated at `%USERPROFILE%`.
- Added explicit Privacy Warning dialog before writing diagnostic context files and copying prompts.
- Updated `Start.bat` launcher to pass direct `-File` arguments instead of inline `-Command` string execution.

### Added
- Core logic module `WingetUpdater.Core.psm1` for non-UI functions, command argument building, and output parsing.
- Comprehensive automated Pester test suite (118 tests) and static analysis configuration (`PSScriptAnalyzerSettings.psd1`).
- GitHub Actions CI workflow (`ci.yml`) for Windows PowerShell 5.1 and PowerShell 7.
- GitHub Actions automated release packaging workflow (`release.yml`) with `SHA256SUMS` generation.

### Changed
- Refactored `Start.bat` to detect and launch PowerShell 7 (`pwsh`) with fallback to Windows PowerShell 5.1 using secure `-File` parameter passing.

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
