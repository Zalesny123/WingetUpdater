@echo off
:: WingetUpdater Launcher
:: Author: Zalesny123
:: Copyright (c) 2026 Zalesny123. Udostepniane na licencji MIT.

setlocal EnableExtensions EnableDelayedExpansion

set "LICENSE_FLAG=%~dp0.license-accepted"
set "LICENSE_FILE=%~dp0LICENSE"

if not exist "!LICENSE_FLAG!" (
    cls
    echo ========================================================
    echo             WINGETUPDATER - UMOWA LICENCYJNA
    echo ========================================================
    if exist "!LICENSE_FILE!" (
        type "!LICENSE_FILE!"
    ) else (
        echo Brak pliku LICENSE. Program objety licencja MIT.
        echo Copyright ^(c^) 2026 Zalesny123
    )
    echo ========================================================
    echo.
    choice /C TN /M "Czy akceptujesz powyzsze warunki licencji? (T - Tak, N - Nie)"
    if errorlevel 2 (
        echo.
        echo Odmowiono akceptacji licencji. Program zostanie zamkniety.
        pause
        exit /b 1
    )
    echo Akceptacja > "!LICENSE_FLAG!"
    echo.
)

set "WINGET_UPDATER_LAUNCHER_OK=1"

set "APP=%~dp0WingetUpdater.ps1"
if not exist "%APP%" (
  echo Nie znaleziono pliku programu:
  echo "%APP%"
  pause
  exit /b 1
)

set "PS5="
set "PS7="
set "CMD="
if exist "%ComSpec%" set "CMD=cmd.exe"
where powershell.exe >nul 2>nul && set "PS5=powershell.exe"
where pwsh.exe >nul 2>nul && set "PS7=pwsh.exe"

set "COUNT=0"
set "KEYS="

if defined CMD (
  if defined PS5 (
    call :AddChoice "CMD" "cmd"
  ) else (
    if defined PS7 call :AddChoice "CMD" "cmd"
  )
)

if defined PS5 (
  call :AddChoice "PowerShell 5" "ps5"
)

if defined PS7 (
  call :AddChoice "PowerShell 7" "ps7"
)

if "%COUNT%"=="0" (
  echo Nie znaleziono PowerShell 5 ani PowerShell 7. Program wymaga jednego z nich.
  pause
  exit /b 1
)

if "%COUNT%"=="1" (
  set "SELECTED=!CHOICE1!"
  echo Dostepna jest tylko jedna opcja: !LABEL1!
  goto Launch
)

echo Wybierz sposob uruchomienia programu:
for /L %%I in (1,1,%COUNT%) do (
  echo %%I. !LABEL%%I!
)
echo.
choice /C %KEYS% /N /M "Wybor: "
set "SELECTED=!CHOICE%ERRORLEVEL%!"

:Launch
set "ELEVATOR="
if defined PS5 set "ELEVATOR=%PS5%"
if not defined ELEVATOR if defined PS7 set "ELEVATOR=%PS7%"

if /I "%SELECTED%"=="cmd" (
  set "CMD_RUNTIME=%PS5%"
  if not defined CMD_RUNTIME set "CMD_RUNTIME=%PS7%"
  "!ELEVATOR!" -NoProfile -ExecutionPolicy Bypass -Command "$app = '%APP%'; $runtime = '!CMD_RUNTIME!'; $q = [char]34; $cmd = ('{0} -NoProfile -ExecutionPolicy Bypass -STA -File {1}{2}{1} -LauncherSecret StartBat123' -f $runtime, $q, $app); Start-Process -FilePath 'cmd.exe' -WorkingDirectory $env:USERPROFILE -ArgumentList @('/c', $cmd)"
  exit /b !ERRORLEVEL!
)

if /I "%SELECTED%"=="ps7" (
  "!ELEVATOR!" -NoProfile -ExecutionPolicy Bypass -Command "$app = '%APP%'; Start-Process -FilePath 'pwsh.exe' -WorkingDirectory $env:USERPROFILE -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',$app,'-LauncherSecret','StartBat123')"
  exit /b !ERRORLEVEL!
)

if /I "%SELECTED%"=="ps5" (
  "!ELEVATOR!" -NoProfile -ExecutionPolicy Bypass -Command "$app = '%APP%'; Start-Process -FilePath 'powershell.exe' -WorkingDirectory $env:USERPROFILE -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',$app,'-LauncherSecret','StartBat123')"
  exit /b !ERRORLEVEL!
)

echo Nieprawidlowy wybor.
pause
exit /b 1

:AddChoice
set /a COUNT+=1
set "LABEL%COUNT%=%~1"
set "CHOICE%COUNT%=%~2"
set "KEYS=%KEYS%%COUNT%"
exit /b 0
