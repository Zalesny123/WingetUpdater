# Changelog

## [1.1.0] - 2026-07-22

### Added
- Deterministic Mock retry scenario that fails twice and succeeds on the next attempt.
- Deterministic release ZIP generation, SHA-256 verification, and GitHub build provenance attestations.
- Real Windows integration fixture for launching `.cmd` AI CLI shims without elevation or agent-control flags.

### Improved
- Expanded `WingetUpdater.Core.psm1` persistence, migration, process execution, failure tracking, and testable lifecycle APIs introduced in v1.0.1.
- Hardened the LocalAppData migration with validated merge semantics, collision-safe context copies, atomic JSON replacement, recovery files, and 30-day log/context pruning.
- Refined source and package agreement handling with non-persistent refusal, immediate in-session consent state, and capability-gated flags.
- Strengthened the per-user mutex, busy-state guards, deferred form close, process-tree cancellation, and cleanup guarantees.
- Reworked session failure AI handoff to retain exact commands, timestamps, stdout/stderr, attempt counts, selected-failure scope, and Ghost evidence.
- Expanded Mock mode to cover success, ordinary and repeated errors, later success, Ghost, cancellation, and AI context generation without real winget calls.
- Increased automated coverage from the 118-test v1.0.1 baseline to the full parser, persistence, launcher, process, lifecycle, Mock, AI, metadata, and release matrix in Windows PowerShell 5.1 and PowerShell 7.
- Hardened CI and release workflows with explicit pinned module imports, full-SHA actions, exact archive manifests, annotated-tag/version checks, and least-privilege jobs.
- Expanded public documentation, contribution guidance, security reporting, issue forms, and release instructions.

### Fixed
- Completed the v1.0.2 source-agreement hotfix by updating the real application script scope immediately after persistence, preventing repeated prompts or omitted acceptance flags in the same session.
- Preserved ordinary package failure status after post-update refresh and prevented Ghost attempt counts from increasing on refresh alone.
- Corrected AI context command/timestamp capture and validated absolute `.exe`/`.cmd` resolution for Codex and agy.
- Rejected nonzero package-list results without replacing the previous table and retained a clear warning when source update fails but cached listing can continue.
- Removed the upgrade-only `--accept-source-agreements` flag from `winget source update`, fixing repeated `0x8A150002` refresh failures with winget 1.29 while retaining consent flags for list and package operations.

### Security
- Further hardened the v1.0.1 non-elevated process model by requiring validated absolute winget and AI CLI paths and removing executable-by-name starts.
- Bounded GUI log output while preserving complete per-command logs and full AI diagnostic context outside the UI buffer.
- Added explicit external-AI privacy guidance, secret scanning, push protection, Private Vulnerability Reporting, and reproducible release provenance.
- Required release tags to originate from `main`, protected version tags against updates/deletion, and enabled immutable releases published only after all assets are attached to a draft.

### Compatibility
- Windows 10 version 1809 or newer; manually validated on Windows 10 22H2 (build 19045).
- Windows 11 is not supported in v1.1.0.
- Windows PowerShell 5.1 and current PowerShell 7.
- winget 1.4.0 or newer, with optional flags detected from the installed client.

## [1.0.2] - 2026-07-21

### Fixed
- Bound `$settingsFile` in the source-agreement persistence closure to prevent the `Settings path is empty.` error. v1.1.0 further corrects immediate in-session consent propagation.

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
