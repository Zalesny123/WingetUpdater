# Release Process

WingetUpdater releases are published only after automated and manual safety gates pass. Do not create a release tag to bypass a failed branch or manual gate.

## 1. Prepare The Candidate

1. Work on a feature branch and update the application version, `README.md`, and `CHANGELOG.md` consistently. Keep the target CHANGELOG section marked `Unreleased` during development, then replace it with the `YYYY-MM-DD` release date in the final audited candidate before creating the tag.
2. Confirm that the release whitelist contains only `Start.bat`, `WingetUpdater.ps1`, `WingetUpdater.Core.psm1`, `README.md`, `CHANGELOG.md`, and `LICENSE`.
3. Run PSScriptAnalyzer and all Pester tests under both Windows PowerShell 5.1 and PowerShell 7.
4. Require a green pull request CI run before merging to `main`.

## 2. Complete The Manual Windows Matrix

Record package IDs and pass/fail outcomes outside the repository; never commit private logs. Validate:

- Windows 10 22H2 with both Windows PowerShell 5.1 and PowerShell 7. Windows 11 is outside the supported v1.1.0 matrix.
- An application path containing spaces, an apostrophe, and `&`.
- A user-scope package update.
- A machine-scope installer launched by non-elevated winget that requests its own UAC and completes.
- Refusal of that installer UAC prompt.
- Queue cancellation and deferred form close.
- Migration behavior is covered by automated read-only and cleanup-failure tests; a manual migration smoke test is optional for v1.1.0.
- Codex and agy present and absent.
- The complete Mock matrix is covered by automated tests; a manual Mock smoke test is optional for v1.1.0.

Publication is blocked until the installer-controlled UAC scenario succeeds from a non-elevated WingetUpdater process.

## 3. Run The Final Audit

On the merged `main` commit:

```powershell
Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Force
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Import-Module Pester -RequiredVersion 6.0.1 -Force
Invoke-Pester -Path ./tests
git diff --check
git fsck --strict
```

Also scan the current tree and reachable Git history for secrets, private e-mail addresses, absolute local paths, generated logs, and diagnostic contexts. Build the release ZIP locally, reject any unexpected entry, validate `SHA256SUMS`, and confirm the expected UTF-8 BOM/CRLF policy.

## 4. Verify Repository Controls

Before tagging, confirm that:

- Private Vulnerability Reporting is enabled.
- Secret scanning and push protection are enabled.
- Dependabot vulnerability alerts and security updates are enabled.
- The `main` ruleset requires a pull request and the passing CI check, blocks deletion and force-push, requires no second reviewer, and retains an administrator emergency bypass.
- Release tags matching `v*` are protected against update and deletion, with only the administrator emergency bypass.
- Immutable releases are enabled for the repository.

## 5. Create The Release

Create an annotated Semantic Version tag at the audited `main` commit:

```bash
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0
```

The release workflow independently re-runs PSScriptAnalyzer and Pester in Windows PowerShell 5.1 and PowerShell 7, verifies the annotated tag, its ancestry from `main`, and version consistency, builds the exact whitelist ZIP, generates `SHA256SUMS`, and creates build provenance. It creates a draft, uploads all assets, and only then publishes the immutable GitHub Release.

## 6. Verify The Published Release

1. Download the ZIP and `SHA256SUMS` from the release page and verify the SHA-256 value.
2. Inspect every ZIP entry and confirm the six-file whitelist and root layout.
3. Verify the GitHub artifact and release attestations, confirm that v1.1.0 is marked Immutable, and confirm that it is Latest.
4. Smoke-test the downloaded archive, not the source checkout.
5. Only after v1.1.0 is verified, mark the previous v1.0.x release unsupported/do-not-use while retaining its tag and assets and linking to v1.1.0.
