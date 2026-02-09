# ==========================================================================================
# Backups.ps1 - REST-based Save Management (Simplified & Safe)
# ==========================================================================================
# New model:
# - No filesystem world copying
# - No world folder assumptions
# - Uses REST API "save" endpoint only
# - Optional auto-save timer
# - Manual "Force Save" hook for UI
# ==========================================================================================

# ==========================================================================================
# GLOBAL VARIABLES
# ==========================================================================================

# Auto-save every X minutes (used by UI + settings)
if (-not $script:autoBackupInterval) {
    $script:autoBackupInterval = 30  # minutes (default)
}

$script:autoBackupTimer = $null
$script:lastBackupTime  = $null

# ==========================================================================================
# HELPER: Invoke-WorldSaveREST
# ==========================================================================================
function Invoke-WorldSaveREST {
    param(
        [string]$Reason = "manual"
    )

    if (-not $script:serverRunning) {
        Write-Warning "Cannot perform REST save: server is not running."
        return $false
    }

    if (-not (Get-Command Invoke-RestAPIRequest-SafeRetry -ErrorAction SilentlyContinue)) {
        Write-Warning "REST API module not available. Cannot perform REST save."
        return $false
    }

    Write-Host "=== REST SAVE REQUEST ($Reason) ===" -ForegroundColor Cyan

    try {
        $body = @{ reason = $Reason }

        $response = Invoke-RestAPIRequest-SafeRetry `
            -Endpoint "save" `
            -Method "POST" `
            -Body $body `
            -TimeoutSeconds $script:restApiTimeout `
            -WaitForSeconds 10

        if ($null -eq $response) {
            Write-Warning "REST save request returned no response."
            return $false
        }

        Write-Host "[OK] REST save completed ($Reason)" -ForegroundColor Green
        $script:lastBackupTime = Get-Date
        return $true

    } catch {
        Write-Warning "REST save failed: $($_.Exception.Message)"
        return $false
    }
}

# ==========================================================================================
# Initialize-Backups
# ==========================================================================================
function Initialize-Backups {
    Write-Verbose "Initializing REST-based backups..."

    # Auto-save timer (optional)
    if (-not $script:autoBackupTimer) {
        $script:autoBackupTimer = New-Object System.Windows.Forms.Timer
        $script:autoBackupTimer.Interval = [int]($script:autoBackupInterval * 60000)

        $script:autoBackupTimer.Add_Tick({
            if ($script:serverRunning) {
                Invoke-WorldSaveREST -Reason "auto"
            }
        })

        $script:autoBackupTimer.Start()
        Write-Verbose "Auto-save timer started (every $($script:autoBackupInterval) minutes)."
    }
}

# ==========================================================================================
# Perform-ManualBackup  (now: REST "Force Save")
# ==========================================================================================
function Perform-ManualBackup {
    param([string]$description = "")

    $reason = if ([string]::IsNullOrWhiteSpace($description)) { "manual" } else { $description }
    Write-Host "Creating REST save ($reason)..." -ForegroundColor Cyan

    $ok = Invoke-WorldSaveREST -Reason $reason
    if ($ok) {
        Write-Host "REST save completed ($reason)." -ForegroundColor Green
        return $true
    } else {
        Write-Warning "REST save failed ($reason)."
        return $false
    }
}

# ==========================================================================================
# Get-BackupList  (compat shim for UI - no filesystem backups)
# ==========================================================================================
function Get-BackupList {
    # We no longer manage filesystem backups.
    # Return a simple synthetic view based on lastBackupTime.
    $list = @()

    if ($script:lastBackupTime) {
        $list += [pscustomobject]@{
            Name        = "Last REST Save"
            Created     = $script:lastBackupTime
            SizeMB      = 0
            Description = "REST API save only (no file backup)"
        }
    }

    return $list
}

# ==========================================================================================
# Restore-Backup / Delete-Backup (no-op stubs for compatibility)
# ==========================================================================================
function Restore-Backup {
    param([string]$backupName)

    Write-Warning "Restore-Backup is no longer supported. Backups are now REST saves only."
    return $false
}

function Delete-Backup {
    param([string]$backupName)

    Write-Warning "Delete-Backup is no longer supported. Backups are now REST saves only."
    return $false
}

# ==========================================================================================
# Cleanup-Backups
# ==========================================================================================
function Cleanup-Backups {
    if ($script:autoBackupTimer) {
        try {
            $script:autoBackupTimer.Stop()
            $script:autoBackupTimer.Dispose()
        } catch {}
        $script:autoBackupTimer = $null
    }
}
