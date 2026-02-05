# ==========================================================================================
# Palworld Server Manager GUI - Version 1.0
# ==========================================================================================
# Modular PowerShell Windows Forms GUI for managing Palworld servers
#
# IMPORTANT NOTES:
# - Must be run with Windows PowerShell (not PowerShell Core)
# - Script should be placed in the PalServer root directory
# ==========================================================================================

# ==========================================================================================
# NATIVE WINDOWS API IMPORTS (Hide console window)
# ==========================================================================================

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
$null = [Win32]::ShowWindow($consolePtr, 0)

# ==========================================================================================
# .NET ASSEMBLY LOADING
# ==========================================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==========================================================================================
# LOAD MODULES IN DEPENDENCY ORDER (DOT-SOURCING)
# ==========================================================================================

$scriptRoot = $PSScriptRoot
$modulePath = Join-Path $scriptRoot "modules"

Write-Host "Loading modules from: $modulePath" -ForegroundColor Cyan

if (-not (Test-Path $modulePath)) {
    Write-Error "Modules folder not found at: $modulePath"
    exit 1
}

# Dot-source each module file
$modules = @(
    "Core.ps1",
    "ConfigManager.ps1", 
    "RCON.ps1",
    "REST_API.ps1",
    "Backups.ps1",
    "Monitoring.ps1",
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
    # Suppress all output from Initialize-UI and capture ONLY the form object
    $form = @(Initialize-UI)[-1]  # Get last item (the form)
    
    # Verify form object
    if ($null -eq $form) {
        throw "Form object is null"
    }
    
    $formType = $form.GetType().Name
    if ($formType -ne "Form") {
        throw "Expected Form, got $formType"
    }
    
    Write-Host "`nManager ready! Starting UI..." -ForegroundColor Green
    
    # Show the form
    [void]$form.ShowDialog()
    
} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    Write-Host $_.Exception.StackTrace -ForegroundColor Red
    
    [System.Windows.Forms.MessageBox]::Show(
        "Error: $_",
        "Fatal Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    
} finally {
    Write-Host "`nCleaning up..." -ForegroundColor Yellow
    try { $null = Cleanup-All } catch {}
    Write-Host "Done!" -ForegroundColor Green
}