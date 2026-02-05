# ==========================================================================================
# Backups.ps1 - Backup and Restore Management (Improved)
# ==========================================================================================
# Handles: Manual/automatic backups, restore, backup rotation, compression
# Dependencies: ConfigManager, RCON
# ==========================================================================================

# ==========================================================================================
# GLOBAL VARIABLES
# ==========================================================================================

# Dynamically detect world folder
$saveRoot = Join-Path $script:serverRoot "Pal\Saved\SaveGames\0"
$worldFolder = $null

if (Test-Path $saveRoot) {
    $worldFolder = Get-ChildItem $saveRoot -Directory | Select-Object -First 1
}

if ($null -eq $worldFolder) {
    Write-Warning "No world folder detected. Backups may not function."
    $script:backupBaseDir = $saveRoot
} else {
    $script:backupBaseDir = $worldFolder.FullName
}

# Backups stored OUTSIDE world folder
$script:backupMetadataDir = Join-Path $script:serverRoot "backups"

$script:autoBackupTimer = $null
$script:autoBackupInterval = 15  # minutes
$script:maxBackups = 10
$script:lastBackupTime = $null

# ==========================================================================================
# Initialize-Backups
# ==========================================================================================

function Initialize-Backups {
    Write-Verbose "Initializing Backups..."

    if (-not (Test-Path $script:backupMetadataDir)) {
        New-Item -ItemType Directory -Path $script:backupMetadataDir | Out-Null
    }

    Load-BackupMetadata

    # Start auto-backup timer
    $script:autoBackupTimer = New-Object System.Windows.Forms.Timer
    $script:autoBackupTimer.Interval = $script:autoBackupInterval * 60000
    $script:autoBackupTimer.Add_Tick({ Perform-ManualBackup "auto" })
    $script:autoBackupTimer.Start()
}

# ==========================================================================================
# Perform-ManualBackup
# ==========================================================================================

function Perform-ManualBackup {
    param([string]$description = "")

    Write-Output "Creating manual backup..."

    try {
        # Trigger RCON save if enabled
        if ((Get-ConfigValue "RCONEnabled") -eq "True") {
            try { Save-World | Out-Null } catch {}
        }

        Start-Sleep -Milliseconds 500

        # Create backup folder
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $safeDesc = ($description -replace '[^\w\-]', '')
        $backupName = if ($safeDesc) { "backup_${timestamp}_$safeDesc" } else { "backup_$timestamp" }

        $backupPath = Join-Path $script:backupMetadataDir $backupName
        New-Item -ItemType Directory -Path $backupPath | Out-Null

        # Validate world folder
        $worldPath = Join-Path $script:backupBaseDir "world"
        if (-not (Test-Path $worldPath)) {
            Write-Error "World folder not found: $worldPath"
            return $false
        }

        # Use robocopy for fast, safe copying
        $dest = Join-Path $backupPath "world"
        New-Item -ItemType Directory -Path $dest | Out-Null

        robocopy $worldPath $dest /MIR /R:1 /W:1 | Out-Null

        # Metadata
        $metadata = @{
            Timestamp = Get-Date
            Description = $description
            SizeMB = Get-FolderSize $backupPath
            WorldFolder = $script:backupBaseDir
            GameVersion = (Get-ConfigValue "ServerVersion")
        }

        $metadata | ConvertTo-Json | Set-Content (Join-Path $backupPath "metadata.json")

        $script:lastBackupTime = Get-Date

        Cleanup-OldBackups

        Write-Output "Backup created: $backupName"
        return $true

    } catch {
        Write-Error "Backup failed: $_"
        return $false
    }
}

# ==========================================================================================
# Get-BackupList
# ==========================================================================================

function Get-BackupList {
    if (-not (Test-Path $script:backupMetadataDir)) { return @() }

    $backups = @()

    Get-ChildItem $script:backupMetadataDir -Directory |
        Sort-Object CreationTime -Descending |
        ForEach-Object {

            $metaPath = Join-Path $_.FullName "metadata.json"
            $meta = @{
                Name = $_.Name
                Created = $_.CreationTime
                SizeMB = Get-FolderSize $_.FullName
                Description = ""
            }

            if (Test-Path $metaPath) {
                try {
                    $json = Get-Content $metaPath -Raw | ConvertFrom-Json
                    $meta.Description = $json.Description
                } catch {}
            }

            $backups += $meta
        }

    return $backups
}

# ==========================================================================================
# Restore-Backup
# ==========================================================================================

function Restore-Backup {
    param([string]$backupName)

    if ($script:serverRunning) {
        Write-Error "Stop the server before restoring a backup."
        return $false
    }

    $backupPath = Join-Path $script:backupMetadataDir $backupName
    if (-not (Test-Path $backupPath)) {
        Write-Error "Backup not found: $backupPath"
        return $false
    }

    # Validate backup
    if (-not (Test-Path (Join-Path $backupPath "world"))) {
        Write-Error "Backup is missing world folder. Restore aborted."
        return $false
    }

    $worldPath = Join-Path $script:backupBaseDir "world"

    try {
        # Safety backup
        if (Test-Path $worldPath) {
            $safety = Join-Path $script:backupMetadataDir "safety_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
            New-Item -ItemType Directory -Path $safety | Out-Null
            robocopy $worldPath (Join-Path $safety "world") /MIR /R:1 /W:1 | Out-Null
        }

        # Restore
        Remove-Item $worldPath -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $worldPath | Out-Null

        robocopy (Join-Path $backupPath "world") $worldPath /MIR /R:1 /W:1 | Out-Null

        Write-Output "Backup restored successfully."
        return $true

    } catch {
        Write-Error "Restore failed: $_"
        return $false
    }
}

# ==========================================================================================
# Delete-Backup
# ==========================================================================================

function Delete-Backup {
    param([string]$backupName)

    $backupPath = Join-Path $script:backupMetadataDir $backupName

    if (-not (Test-Path $backupPath)) { return $false }

    try {
        Remove-Item $backupPath -Recurse -Force
        Write-Output "Backup deleted: $backupName"
        return $true
    } catch {
        Write-Error "Delete failed: $_"
        return $false
    }
}

# ==========================================================================================
# Cleanup-OldBackups
# ==========================================================================================

function Cleanup-OldBackups {

    $backups = Get-ChildItem $script:backupMetadataDir -Directory |
               Sort-Object CreationTime -Descending

    if ($backups.Count -le $script:maxBackups) { return }

    $toDelete = $backups[$script:maxBackups..($backups.Count - 1)]

    foreach ($b in $toDelete) {
        try {
            Remove-Item $b.FullName -Recurse -Force
            Write-Output "Removed old backup: $($b.Name)"
        } catch {
            Write-Warning "Failed to delete backup: $($b.Name)"
        }
    }
}

# ==========================================================================================
# Get-FolderSize
# ==========================================================================================

function Get-FolderSize {
    param([string]$path)

    if (-not (Test-Path $path)) { return 0 }

    try {
        $size = (Get-ChildItem $path -Recurse -Force |
                 Measure-Object Length -Sum).Sum / 1MB
        return [math]::Round($size, 2)
    } catch {
        return 0
    }
}

# ==========================================================================================
# Load-BackupMetadata / Save-BackupMetadata
# ==========================================================================================

function Load-BackupMetadata {
    $file = Join-Path $script:backupMetadataDir "last_backup.txt"
    if (Test-Path $file) {
        try { $script:lastBackupTime = [datetime](Get-Content $file) } catch {}
    }
}

function Save-BackupMetadata {
    if ($script:lastBackupTime) {
        $script:lastBackupTime | Out-File (Join-Path $script:backupMetadataDir "last_backup.txt")
    }
}

# ==========================================================================================
# Cleanup-Backups
# ==========================================================================================

function Cleanup-Backups {
    Save-BackupMetadata
    if ($script:autoBackupTimer) {
        $script:autoBackupTimer.Stop()
        $script:autoBackupTimer.Dispose()
    }
}
