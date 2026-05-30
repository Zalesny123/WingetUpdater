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
- `Start.bat` launcher as the only recommended way to start the program.
- Automatic detection of the available runtime environment: CMD, Windows PowerShell 5.1, or PowerShell 7+.
- Support for running the program with administrator privileges.
- Support for repairing packages with an unknown version through the "Repair Unknown" feature.
- Generation of diagnostic context for an AI agent when repairing Unknown packages.
- MIT license support.
- Other features not listed above that are present in the program GUI.

### Notes

- The program enforces startup through `Start.bat` to reduce accidental execution of the main script outside the intended mode.
- The launcher displays the license text before the first run and saves a local acceptance marker.
- The diagnostic context for the AI agent assumes safe research and no changes without explicit user confirmation.
- The program is intended for Windows.
- The program requires Windows Package Manager (`winget`) to be installed.
