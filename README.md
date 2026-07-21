# WingetUpdater

![Platform](https://img.shields.io/badge/platform-Windows-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

**Version:** 1.1.0

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
- **Non-Elevated Execution**: Runs `winget` as the standard user. A package installer may request its own Windows UAC elevation when required.
- **LocalAppData Storage**: Configuration and logs are kept under the current user's `%LOCALAPPDATA%\WingetUpdater` directory.
- **Source & Package Agreement Consent**: Explicit opt-in consent before applying `--accept-source-agreements` and `--accept-package-agreements`.
- **Queue Cancellation**: Stop running package update queues safely with process tree termination.
- **AI Error Handoff**: Copy diagnostic failure context to clipboard and launch `codex` or `agy` CLI for troubleshooting.
- **User-Facing Mock Mode**: Test full application workflows safely without altering system state.

## Requirements

- Windows 10 (version 1809+). The v1.1.0 manual release matrix is validated on Windows 10 22H2 (build 19045).
- Windows 11 is not currently supported.
- Windows Package Manager (`winget` version 1.4.0 or newer).
- Windows PowerShell 5.1 or PowerShell 7+ (`pwsh`).

Optional for AI CLI feature:
- [Codex CLI](https://github.com/openai/codex) or `agy` CLI installed on PATH.

## Download

Download the latest release archive `WingetUpdater-v1.1.0.zip` and `SHA256SUMS` from the GitHub Releases page.

Verify the downloaded archive before extracting it:

```powershell
$expected = (Get-Content .\SHA256SUMS | Select-String 'WingetUpdater-v1.1.0.zip').Line.Split()[0]
$actual = (Get-FileHash .\WingetUpdater-v1.1.0.zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw 'SHA-256 checksum mismatch.' }
```

Expected release archive structure:

```cmd
Start.bat
WingetUpdater.ps1
WingetUpdater.Core.psm1
README.md
CHANGELOG.md
LICENSE
```

## Running the Application

Launch the tool by running `Start.bat`:

```cmd
Start.bat
```

Do not run `WingetUpdater.ps1` directly. `Start.bat` ensures execution policy flags and runtime selection are set properly.

## How to Use

1. Start the application with `Start.bat` and continue past the informational MIT notice.
2. On the first real refresh, review the source-agreement explanation. Declining keeps Mock mode available and does not persist the refusal.
3. Select **Refresh** to update winget sources and load available package upgrades.
4. Choose packages and optional interactive, silent, or include-unknown behavior, then select **Update selected**.
5. Confirm the package-agreement notice. Use **Cancel** to stop the active winget process and remaining queue; an already-independent installer may need to be closed separately.
6. For unresolved package failures, select failed rows or leave the selection empty to use all session failures, then use **Copy message** and optionally **Open AI CLI**.

## AppData & Privacy

Runtime data is stored under `%LOCALAPPDATA%\WingetUpdater`:
- `settings.json` – Schema-versioned application settings and consent state.
- `skip-list.json` – Saved list of skipped package IDs.
- `logs/` – Per-command execution logs (automatically pruned after 30 days).
- `repair-contexts/` – Generated diagnostic context files for AI handoff (pruned after 30 days).
- `mock/` – Mock state data used during Mock mode.

**Privacy Notice**: LocalAppData is ordinary per-user storage, not a confidentiality boundary from other processes running as that user. Command logs and AI context files can contain local paths or other system details. A warning is shown before context creation and clipboard copy.

## AI Failure Handoff

When a package update fails or is flagged as a post-verification failure:
1. Click **Kopiuj wiadomość AI** (`Copy message`).
2. Review the privacy prompt and confirm context creation.
3. The application writes a diagnostic file to `%LOCALAPPDATA%\WingetUpdater\repair-contexts` and copies a reference prompt to your clipboard.
4. Click **Otwórz CLI AI** (`Open AI CLI`) to launch `codex` or `agy` in a new console at `%USERPROFILE%`.
5. Paste your clipboard prompt into the CLI.

Codex and agy are external tools. Their own configuration controls sandboxing, approvals, filesystem access, network use, telemetry, and retention. Review the generated context file and your CLI configuration before pasting or submitting any data.

## Mock Mode

Check **TRYB TESTOWY (Mock)** in the GUI to simulate winget operations safely. Mock mode:
- Uses virtual package data stored in `%LOCALAPPDATA%\WingetUpdater\mock\MockState.json`.
- Simulates successful updates, package errors, Ghost failures, and cancellation.
- Includes a deterministic repeated-failure scenario that succeeds on a later retry.
- Bypasses real winget executable calls and system state modifications.

## Testing & Verification

Run automated tests using Pester:

```powershell
Install-Module Pester -RequiredVersion 6.0.1 -Scope CurrentUser -Force -SkipPublisherCheck
Import-Module Pester -RequiredVersion 6.0.1 -Force
Invoke-Pester -Path ./tests
```

Run static analysis using PSScriptAnalyzer:

```powershell
Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force -SkipPublisherCheck
Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Force
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

## Security Notes

Security reports should be submitted privately via [GitHub Private Vulnerability Reporting](https://github.com/Zalesny123/WingetUpdater/security/advisories/new). See [SECURITY.md](SECURITY.md) for details.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
