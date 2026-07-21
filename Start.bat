@echo off
:: WingetUpdater Launcher
:: Author: Zalesny123
:: Copyright (c) 2026 Zalesny123. Udostepniane na licencji MIT.

setlocal EnableExtensions

if not defined LOCALAPPDATA (
    echo Nie znaleziono katalogu LocalAppData.
    pause
    exit /b 1
)

set "APP=%~dp0WingetUpdater.ps1"
set "LICENSE_FILE=%~dp0LICENSE"
set "NOTICE_DIRECTORY=%LOCALAPPDATA%\WingetUpdater"
set "NOTICE_MARKER=%LOCALAPPDATA%\WingetUpdater\.license-notice-shown"
set "LEGACY_NOTICE_MARKER=%~dp0.license-accepted"

if not exist "%APP%" (
    echo Nie znaleziono pliku programu:
    echo "%APP%"
    pause
    exit /b 1
)

if exist "%NOTICE_MARKER%" goto NoticeComplete
if exist "%LEGACY_NOTICE_MARKER%" (
    call :WriteNoticeMarker
    if errorlevel 1 exit /b 1
    goto NoticeComplete
)

cls
echo ========================================================
echo              WINGETUPDATER - MIT LICENSE NOTICE
echo ========================================================
echo This program is distributed under the MIT License.
echo Copyright ^(c^) 2026 Zalesny123
echo The complete license text is available at:
echo "%LICENSE_FILE%"
echo ========================================================
echo Continue starts the program. Exit closes this launcher.
echo.
choice /C CE /N /M "Continue (C) or Exit (E)? "
if errorlevel 2 exit /b 1
call :WriteNoticeMarker
if errorlevel 1 exit /b 1

:NoticeComplete
set "POWERSHELL_EXE="
for %%D in (".\pwsh.exe") do set "CURRENT_DIRECTORY_PWSH=%%~fsD"
for /f "usebackq delims=" %%P in (`^""%SystemRoot%\System32\where.exe" "$PATH:pwsh.exe" 2^>nul^"`) do if not defined POWERSHELL_EXE if /I not "%%~fsP"=="%CURRENT_DIRECTORY_PWSH%" set "POWERSHELL_EXE=%%~fP"
set "CURRENT_DIRECTORY_PWSH="
if not defined POWERSHELL_EXE if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not defined POWERSHELL_EXE (
    echo Nie znaleziono PowerShell 7 ani Windows PowerShell 5.1.
    pause
    exit /b 1
)

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -STA -File "%APP%" -LaunchedFromStartBat
exit /b %ERRORLEVEL%

:WriteNoticeMarker
if not exist "%NOTICE_DIRECTORY%\" mkdir "%NOTICE_DIRECTORY%" 2>nul
if not exist "%NOTICE_DIRECTORY%\" (
    echo Nie udalo sie utworzyc katalogu danych programu:
    echo "%NOTICE_DIRECTORY%"
    pause
    exit /b 1
)

> "%NOTICE_MARKER%" echo MIT license notice shown.
if not exist "%NOTICE_MARKER%" (
    echo Nie udalo sie zapisac informacji o wyswietleniu licencji.
    pause
    exit /b 1
)
exit /b 0
