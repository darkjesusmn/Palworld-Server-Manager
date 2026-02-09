# ==========================================================================================
# Palworld Server Manager GUI - Version 1.0
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

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptRoot = $PSScriptRoot
$modulePath = Join-Path $scriptRoot "modules"

Write-Host "Loading modules from: $modulePath" -ForegroundColor Cyan

if (-not (Test-Path $modulePath)) {
    Write-Error "Modules folder not found at: $modulePath"
    exit 1
}

# ⭐ Load ONLY Core.ps1 first (because it contains Redirect-PowerShellOutput)
$coreFile = Join-Path $modulePath "Core.ps1"
. $coreFile

# ⭐ Install redirect BEFORE loading any other modules
Redirect-PowerShellOutput

# ⭐ Now load the rest of the modules
$modules = @(
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
    [void]$form.ShowDialog()
    
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
    try { $null = Cleanup-All } catch {}
    Write-Host "Done!" -ForegroundColor Green
}
