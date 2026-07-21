@echo off
setlocal
if not defined WINGETUPDATER_AI_FIXTURE_OUTPUT exit /b 2
>"%WINGETUPDATER_AI_FIXTURE_OUTPUT%" (
    echo CWD=%CD%
    echo ARGS=%*
)
exit 0
