# WingetUpdater

![Platform](https://img.shields.io/badge/platform-Windows-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

**Version:** 1.0.1

**WingetUpdater** is a graphical Windows tool for checking and updating installed software using Windows Package Manager (`winget`).

The application provides a clean desktop GUI for reviewing available updates, choosing packages to upgrade or skip, managing source agreements, and handing off package upgrade failures to AI CLI tools for diagnosis.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Download](#download)
- [Running the Application](#running-the-application)
- [How to Use](#how-to-use)
- [AppData & Privacy](#appdata--privacy)
- [AI Failure Handoff](#ai-failure-handoff)
- [Mock Mode](#mock-mode)
- [Testing & Verification](#testing--verification)
- [Security Notes](#security-notes)
- [License](#license)

## Features

- **Winget Package Management**: Easy graphical interface for `winget upgrade`.
- **Automatic PowerShell Selection**: `Start.bat` automatically selects PowerShell 7 (`pwsh`) or falls back to Windows PowerShell 5.1.
- **Non-Elevated Execution**: Runs as standard user. Package installers prompt for UAC when machine scope is required.
- **LocalAppData Storage**: Configuration and logs stored securely under `%LOCALAPPDATA%\WingetUpdater`.
- **Source & Package Agreement Consent**: Explicit opt-in consent before applying `--accept-source-agreements` and `--accept-package-agreements`.
- **Queue Cancellation**: Stop running package update queues safely with process tree termination.
- **AI Error Handoff**: Copy diagnostic failure context to clipboard and launch `codex` or `agy` CLI for troubleshooting.
- **User-Facing Mock Mode**: Test full application workflows safely without altering system state.

## Requirements

- Windows 10 (version 1809+) or Windows 11.
- Windows Package Manager (`winget` version 1.4.0 or newer).
- Windows PowerShell 5.1 or PowerShell 7+ (`pwsh`).

Optional for AI CLI feature:
- [Codex CLI](https://github.com/openai/codex) or `agy` CLI installed on PATH.

## Download

Download the latest release archive `WingetUpdater-v1.0.1.zip` and `SHA256SUMS` from the GitHub Releases page.

Expected release archive structure:

```text
WingetUpdater-v1.0.1/
├─ Start.bat
├─ WingetUpdater.ps1
├─ WingetUpdater.Core.psm1
├─ README.md
├─ CHANGELOG.md
└─ LICENSE
```

## Running the Application

Launch the tool by running `Start.bat`:

```cmd
Start.bat
```

Do not run `WingetUpdater.ps1` directly. `Start.bat` ensures execution policy flags and runtime selection are set properly.

## AppData & Privacy

Runtime data is stored under `%LOCALAPPDATA%\WingetUpdater`:
- `settings.json` – Schema-versioned application settings and consent state.
- `skip-list.json` – Saved list of skipped package IDs.
- `logs/` – Per-command execution logs (automatically pruned after 30 days).
- `repair-contexts/` – Generated diagnostic context files for AI handoff (pruned after 30 days).
- `mock/` – Mock state data used during Mock mode.

**Privacy Notice**: Command logs and AI context files contain system details (such as local file paths or environment variables). A warning is shown before copying diagnostic context to the clipboard.

## AI Failure Handoff

When a package update fails or is flagged as a post-verification failure:
1. Click **Kopiuj wiadomość AI** (`Copy message`).
2. Review the privacy prompt and confirm context creation.
3. The application writes a diagnostic file to `%LOCALAPPDATA%\WingetUpdater\repair-contexts` and copies a reference prompt to your clipboard.
4. Click **Otwórz CLI AI** (`Open AI CLI`) to launch `codex` or `agy` in a new console at `%USERPROFILE%`.
5. Paste your clipboard prompt into the CLI.

## Mock Mode

Check **TRYB TESTOWY (Mock)** in the GUI to simulate winget operations safely. Mock mode:
- Uses virtual package data stored in `%LOCALAPPDATA%\WingetUpdater\mock\MockState.json`.
- Simulates successful updates, package errors, Ghost failures, and cancellation.
- Bypasses real winget executable calls and system state modifications.

## Testing & Verification

Run automated tests using Pester:

```powershell
pwsh -Command "Invoke-Pester -Path ./tests"
```

Run static analysis using PSScriptAnalyzer:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

## Security Notes

Security reports should be submitted privately via [GitHub Private Vulnerability Reporting](https://github.com/Zalesny123/WingetUpdater/security/advisories/new). See [SECURITY.md](SECURITY.md) for details.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
