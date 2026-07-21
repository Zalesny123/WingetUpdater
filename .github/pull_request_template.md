## Description
Provide a brief summary of the changes introduced by this pull request.

## Related Issues
Closes # (issue number)

## Type of Change
- [ ] Bug fix (non-breaking change fixing an issue)
- [ ] New feature (non-breaking change adding functionality)
- [ ] Breaking change (fix or feature causing existing behavior to change)
- [ ] Documentation update

## Checklist
- [ ] Code follows existing project style and file encodings (UTF-8 BOM + CRLF for PowerShell).
- [ ] All Pester tests pass locally (`pwsh -Command "Invoke-Pester -Path ./tests"`).
- [ ] PSScriptAnalyzer passes with no warnings or errors (`Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`).
- [ ] Documentation (README.md, CHANGELOG.md) updated if applicable.
- [ ] Privacy and private-data impact reviewed; no local logs, contexts, session files, or secrets are included.
- [ ] Release ZIP contents and version impact reviewed when packaging or public behavior changes.
- [ ] Relevant manual Windows tests were completed under PowerShell 5.1 and PowerShell 7, or the remaining gate is documented.
- [ ] Changes to process execution, arguments, elevation boundaries, executable resolution, or AI context received heightened review.
