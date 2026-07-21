# Changelog

## [1.0.1] - 2026-07-21

### Security & Minimal Publication Gate Fixes
- **Argument Safety**: Removed custom RunAs elevated script generation and code interpolation. Package updates run as non-elevated user; machine-scope package installers trigger native Windows UAC prompts.
- **Quoting Engine**: Implemented `Join-CommandLineArguments` in `WingetUpdater.Core.psm1` adhering to Windows command line escaping rules (handling `'`, `"`, `;`, spaces, trailing backslashes).
- **AI CLI Safety & Privacy**: Launched AI CLI (`codex`, `agy`) non-elevated at `%USERPROFILE%`. Added explicit Privacy Warning dialog before writing diagnostic context files and copying prompts.
- **Launcher Security**: Updated `Start.bat` to pass direct `-File` arguments instead of interpolated `-Command` string execution.
- **Automated Testing & Static Analysis**: Added Pester test suite (118 tests) and `PSScriptAnalyzerSettings.psd1` for code quality and security verification.
- **CI & Release Packaging**: Added GitHub Actions CI (`ci.yml`) and tag-triggered release packaging workflow (`release.yml`) generating `SHA256SUMS`.

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
