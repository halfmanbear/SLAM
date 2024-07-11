@echo off
setlocal

REM Get the path to the current script's directory
set scriptDir=%~dp0

REM Define the path to the PowerShell script
set psScript=%scriptDir%create-shortcut.ps1

REM Check for administrative privileges
openfiles >nul 2>nul
if %errorlevel% neq 0 (
    echo Requesting administrative privileges...
    powershell.exe -Command "Start-Process cmd -ArgumentList '/c ""%~f0""' -Verb RunAs"
    exit /b
)

REM Run the PowerShell script with the appropriate execution policy
powershell.exe -ExecutionPolicy Bypass -File "%psScript%" -ArgumentList "-elevated"

pause
endlocal
