@echo off
REM ==============================================================================
REM Palworld Server Manager - One-Click Installer
REM ==============================================================================
REM This batch file handles PowerShell execution policy so you don't get
REM the security prompt every single time.
REM
REM Run this ONCE to set things up, then you can run the manager directly.
REM ==============================================================================

setlocal enabledelayedexpansion

echo.
echo ============================================================
echo Palworld Server Manager - Setup
echo ============================================================
echo.
echo This will set up your system to run the manager without
echo security prompts every time.
echo.
pause

REM Check if running as admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ERROR: This script must be run as Administrator!
    echo.
    echo Please:
    echo  1. Right-click this file
    echo  2. Select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo [1/2] Setting PowerShell execution policy...
echo.

REM Set execution policy for current user
powershell -NoProfile -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" >nul 2>&1

if %errorlevel% equ 0 (
    echo OK - Execution policy set
) else (
    echo WARNING - Could not set execution policy
    echo You may still see security prompts
)

echo.
echo [2/2] Unblocking PowerShell files...
echo.

REM Unblock all PS1 files in the directory
for /R "%~dp0" %%F in (*.ps1) do (
    powershell -NoProfile -Command "Unblock-File -Path '%%F' -ErrorAction SilentlyContinue" >nul 2>&1
)

echo OK - Files unblocked
echo.
echo ============================================================
echo Setup complete!
echo ============================================================
echo.
echo You can now run the manager without security prompts.
echo.
echo Next time, just double-click:
echo   Palworld_Server_Manager.ps1
echo.
pause
