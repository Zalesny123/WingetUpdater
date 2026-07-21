# Contributing to WingetUpdater

Thank you for your interest in contributing to WingetUpdater!

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How to Contribute

### Reporting Bugs
Before creating a bug report, please check existing issues. Use the [Bug Report Template](.github/ISSUE_TEMPLATE/bug_report.yml) and include:
- Windows version, PowerShell version, and winget version
- Application logs (sanitized of sensitive information)
- Exact steps to reproduce

### Feature Requests
Submit feature requests using the [Feature Request Template](.github/ISSUE_TEMPLATE/feature_request.yml).

### Submitting Pull Requests
1. Fork the repository and create a feature branch off `main`.
2. Ensure code follows existing formatting guidelines (UTF-8 with BOM and CRLF for PowerShell files).
3. Run Pester tests locally:
   ```powershell
   Import-Module Pester -RequiredVersion 6.0.1 -Force
   Invoke-Pester -Path ./tests
   ```
4. Run PSScriptAnalyzer:
   ```powershell
   Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Force
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
   ```
5. Submit a Pull Request targeting `main`.

Development and manual integration testing require Windows 10 1809+, winget 1.4.0+, Windows PowerShell 5.1, and PowerShell 7. Windows 11 is not currently supported. Run the Pester suite in both engines. Use the GUI's Mock mode for safe workflow testing that must not alter installed packages.

```powershell
powershell.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 6.0.1; Invoke-Pester -Path ./tests"
pwsh.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 6.0.1; Invoke-Pester -Path ./tests"
```

## Review Criteria for Security & Runtime Behavior
PRs modifying process execution, UAC boundaries, CLI arguments, or AI context handling require extra review scrutiny.
They must document privacy impact, manual Windows coverage, release-package impact, and any change to executable resolution or trust boundaries.
