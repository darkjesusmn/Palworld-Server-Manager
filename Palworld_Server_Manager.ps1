# ==========================================================================================
# Palworld Server Manager GUI - Version 1.0
# ==========================================================================================
# This script initializes and launches the full Palworld Server Manager GUI.
# It loads all modules, installs output redirection, initializes subsystems,
# and finally launches the WinForms UI.
#
# This version includes:
#   - Full console/output capture
#   - Rolling log file
#   - Real-time log tailing
#   - DebugMode support
#   - Cleanup integration
#   - Detailed comments for debugging and maintenance
# ==========================================================================================



# ------------------------------------------------------------
# Hide or show the PowerShell console window
# ------------------------------------------------------------
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

$consolePtr = [Win32]::GetConsoleWindow()
$null = [Win32]::ShowWindow($consolePtr, 5)   # 0 = hide, 5 = show

# ------------------------------------------------------------
# Load WinForms and Drawing assemblies
# ------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==========================================================================================
# CONSOLE REDIRECT ENGINE — FULL OUTPUT CAPTURE
# ==========================================================================================
# Captures:
#   Write-Host, Write-Output, Write-Error, Write-Warning,
#   Write-Verbose, Write-Debug, exceptions, stack traces,
#   module load messages, SteamCMD output, REST API logs,
#   RCON logs, backup logs, monitoring logs, crash logs.
# ==========================================================================================
$scriptRoot = $PSScriptRoot
$global:ConsoleLogPath = Join-Path $PSScriptRoot "modules\Logs\Console_Live.log"
$global:ConsoleLogLastLength = 0

function Redirect-PowerShellOutput {
    Write-Host "[DEBUG] Redirect-PowerShellOutput is running" -ForegroundColor Yellow
    try {
        $logDir = Split-Path $global:ConsoleLogPath
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        # Force all streams to output
        $global:VerbosePreference = 'Continue'
        $global:DebugPreference   = 'Continue'
        $global:WarningPreference = 'Continue'
        $global:ErrorActionPreference = 'Continue'

        # Restart transcript cleanly
        try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}

        Start-Transcript -Path $global:ConsoleLogPath -Append | Out-Null

        Write-Host "[CORE] Output redirection enabled → $global:ConsoleLogPath" -ForegroundColor Cyan
    }
    catch {
        Write-Error "[CORE] Failed to enable output redirection: $($_.Exception.Message)"
    }
}

function Get-ConsoleLogTail {
    if (-not (Test-Path $global:ConsoleLogPath)) {
        return @()
    }

    $content = Get-Content -Path $global:ConsoleLogPath -ErrorAction SilentlyContinue
    if ($null -eq $content) { return @() }

    $totalLines = $content.Count

    if ($global:ConsoleLogLastLength -ge $totalLines) {
        return @()
    }

    $newLines = $content[$global:ConsoleLogLastLength..($totalLines - 1)]
    $global:ConsoleLogLastLength = $totalLines

    return $newLines
}

function Stop-ConsoleRedirect {
    try {
        Stop-Transcript | Out-Null
    } catch {
        Write-Host "[CORE] Transcript was not running." -ForegroundColor DarkYellow
    }
    try {
        if (Test-Path $global:ConsoleLogPath) {
            Clear-Content $global:ConsoleLogPath -ErrorAction SilentlyContinue
        }
    } catch {}

}

# Redirect PowerShell output
Redirect-PowerShellOutput

# ------------------------------------------------------------
# DEBUG TEST LINES — Used to verify launcher output capture
# ------------------------------------------------------------
Write-Host "[TEST] Palworld Server Manager starting..."
Write-Host "[TEST] Loading modules..."
Write-Host "[TEST] Debug output test..."

# ==========================================================================================
# MODULE LOADING
# ==========================================================================================

$modulePath = Join-Path $scriptRoot "modules"

Write-Host "Loading modules from: $modulePath" -ForegroundColor Cyan

if (-not (Test-Path $modulePath)) {
    Write-Error "Modules folder not found at: $modulePath"
    exit 1
}

# Load Core.ps1 FIRST
$coreFile = Join-Path $modulePath "Core.ps1"
. $coreFile


# Load remaining modules
$modules = @(
    "ConfigManager.ps1", 
    "RCON.ps1",
    "REST_API.ps1",
    "Backups.ps1",
    "Monitoring.ps1",
    "SteamCMD.ps1",
    "UI.ps1"
)

foreach ($module in $modules) {
    $modulefile = Join-Path $modulePath $module
    if (Test-Path $modulefile) {
        Write-Host "  Loading $module..." -ForegroundColor Cyan
        . $modulefile
    } else {
        Write-Error "Module not found: $modulefile"
        exit 1
    }
}

Write-Host "All modules loaded!" -ForegroundColor Green

# ==========================================================================================
# INITIALIZATION
# ==========================================================================================

try {
    Write-Host "`nInitializing systems..." -ForegroundColor Green
    
    Write-Host "  Core..." -ForegroundColor Cyan
    $null = Initialize-Core
    
    Write-Host "  ConfigManager..." -ForegroundColor Cyan
    $null = Initialize-ConfigManager
    
    Write-Host "  RCON..." -ForegroundColor Cyan
    $null = Initialize-RCON
    
    Write-Host "  REST API..." -ForegroundColor Cyan
    $null = Initialize-RestAPI
    
    Write-Host "  Backups..." -ForegroundColor Cyan
    $null = Initialize-Backups
    
    Write-Host "  Monitoring..." -ForegroundColor Cyan
    $null = Initialize-Monitoring
    
    Write-Host "  UI..." -ForegroundColor Cyan
    $form = @(Initialize-UI)[-1]

    if ($null -eq $form) { throw "Form object is null" }
    if ($form.GetType().Name -ne "Form") {
        throw "Expected Form, got $($form.GetType().Name)"
    }

    Write-Host "`nManager ready! Starting UI..." -ForegroundColor Green

    [System.Windows.Forms.Application]::Run($form)
    
} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.InvocationInfo) {
        Write-Host "Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
        Write-Host "Code: $($_.InvocationInfo.Line)" -ForegroundColor Yellow
    }

    Write-Host "`nStack Trace:" -ForegroundColor Red
    Write-Host $_.Exception.StackTrace -ForegroundColor Red

    [System.Windows.Forms.MessageBox]::Show(
        "Error: $_",
        "Fatal Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    
} finally {
    Write-Host "`nCleaning up..." -ForegroundColor Yellow
    try { Stop-ConsoleRedirect } catch {}
    try { $null = Cleanup-All } catch {}
    Write-Host "Done!" -ForegroundColor Green
}
