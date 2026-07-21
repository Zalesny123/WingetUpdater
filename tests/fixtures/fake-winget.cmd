@echo off
setlocal
if /I "%~1"=="streams" goto Streams
if /I "%~1"=="large" goto Large
if /I "%~1"=="side-effect" goto SideEffect
if /I "%~1"=="quiet" goto Quiet
if /I "%~1"=="output-then-quiet" goto OutputThenQuiet
if /I "%~1"=="duplex" goto Duplex
echo Unknown fixture command: %~1 1>&2
exit /b 64

:Streams
echo stdout-one
echo stderr-one 1>&2
echo ARG1=%~2
echo ARG2=%~3
echo stdout-two
echo stderr-two 1>&2
exit /b 23

:Large
for /L %%I in (1,1,4999) do echo LINE-%%I-abcdefghijklmnopqrstuvwxyz
echo LINE-5000-END
exit /b 0

:SideEffect
echo started>"%~2"
exit /b 0

:Quiet
ping.exe 127.0.0.1 -n 3 >nul
exit /b 0

:OutputThenQuiet
echo trigger-read
ping.exe 127.0.0.1 -n 3 >nul
exit /b 0

:Duplex
for /L %%I in (1,1,2999) do (
  echo OUT-%%I-abcdefghijklmnopqrstuvwxyz
  echo ERR-%%I-abcdefghijklmnopqrstuvwxyz 1>&2
)
echo OUT-3000-END
echo ERR-3000-END 1>&2
exit /b 0
