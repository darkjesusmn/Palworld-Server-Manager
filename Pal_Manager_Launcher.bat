@echo off
REM ==============================================================================
REM Palworld Server Manager - One-Click Setup & Launcher
REM ==============================================================================
REM This batch file:
REM   - Ensures PowerShell scripts can run without prompts
REM   - Unblocks all .ps1 files in the directory tree
REM   - Launches the Palworld Server Manager with debugging enabled
REM   - Keeps the window open if errors occur
REM   - Writes errors to Logs\error.log (your manager already handles this)
REM ==============================================================================

setlocal enabledelayedexpansion

echo.
echo ============================================================
echo   Palworld Server Manager
echo   Universal Server Host Launcher
echo ============================================================
echo.
echo Preparing your system for first-time setup...
echo.

REM ----------------------------------------------------------------------
REM 1. Check for Administrator privileges
REM ----------------------------------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ERROR: This script must be run as Administrator!
    echo.
    echo Please:
    echo   1. Right-click this file
    echo   2. Select "Run as administrator"
    echo   3. Approve the UAC prompt
    echo.
    pause
    exit /b 1
)

REM ----------------------------------------------------------------------
REM 2. Set PowerShell execution policy
REM ----------------------------------------------------------------------
echo [1/3] Setting PowerShell execution policy...

powershell -NoProfile -Command ^
    "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" >nul 2>&1

if %errorlevel% equ 0 (
    echo      [OK] Execution policy set to RemoteSigned
) else (
    echo      [WARN] Could not set execution policy (may still work)
)

REM ----------------------------------------------------------------------
REM 3. Unblock all PowerShell scripts recursively
REM ----------------------------------------------------------------------
echo.
echo [2/3] Unblocking PowerShell files...

for /R "%~dp0" %%F in (*.ps1) do (
    powershell -NoProfile -Command ^
        "Unblock-File -Path '%%F' -ErrorAction SilentlyContinue" >nul 2>&1
)

echo      [OK] All PowerShell files unblocked

REM ----------------------------------------------------------------------
REM 4. Launch the Palworld Server Manager
REM ----------------------------------------------------------------------
echo.
echo [3/3] Launching Palworld Server Manager...
echo.
echo If the application crashes, error details will appear below.
echo A detailed log will be written to: Logs\error.log
echo.

set SCRIPT_DIR=%~dp0
set MAIN_SCRIPT=%SCRIPT_DIR%Palworld_Server_Manager.ps1

if not exist "%MAIN_SCRIPT%" (
    echo.
    echo FATAL ERROR: Palworld_Server_Manager.ps1 not found!
    echo Expected location:
    echo   %MAIN_SCRIPT%
    echo.
    pause
    exit /b 2
)

REM powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%MAIN_SCRIPT%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%MAIN_SCRIPT%"

REM powershell -NoProfile -NoExit -ExecutionPolicy Bypass -File "%MAIN_SCRIPT%"


REM ----------------------------------------------------------------------
REM 5. Error handling after PowerShell exits
REM ----------------------------------------------------------------------
if %errorlevel% neq 0 (
    echo.
    echo ============================================================
    echo   Application exited with error code: %errorlevel%
    echo.
    echo   Check Logs\error.log for detailed error information.
    echo ============================================================
    echo.
)

endlocal
