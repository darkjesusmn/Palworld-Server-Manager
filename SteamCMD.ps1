# =====================================================================
# SteamCMD Backend (PowerShell 5.1 Safe Version)
# =====================================================================

function Get-SteamCMDPaths {
    $steamcmdFolder = Join-Path $script:rootPath "steamcmd"
    $steamcmdExe    = Join-Path $steamcmdFolder "steamcmd.exe"
    $serverExe      = Join-Path $script:rootPath "PalServer.exe"
    $iniPath        = Join-Path $script:rootPath "Pal\Saved\Config\WindowsServer\PalWorldSettings.ini"

    [PSCustomObject]@{
        SteamCMDFolder = $steamcmdFolder
        SteamCMDExe    = $steamcmdExe
        ServerExe      = $serverExe
        IniPath        = $iniPath
    }
}

function Write-SteamCMDLog {
    param([string]$Message)

    if ($script:steamcmdOutputBox -and $Message -ne $null -and $Message.Trim() -ne "") {
        $timestamp = (Get-Date).ToString("HH:mm:ss")
        $script:steamcmdOutputBox.AppendText("[$timestamp] $Message`r`n")
        $script:steamcmdOutputBox.ScrollToCaret()
    }
}

function Check-RequiredServerFiles {
    $paths = Get-SteamCMDPaths

    $serverExists = Test-Path $paths.ServerExe
    $iniExists    = Test-Path $paths.IniPath

    if ($script:lblSteamCMD_ServerStatus) {
        $script:lblSteamCMD_ServerStatus.Text = "PalServer.exe: " + ($(if ($serverExists) { "Found" } else { "Missing" }))
        $script:lblSteamCMD_ServerStatus.ForeColor = $(if ($serverExists) { [System.Drawing.Color]::LimeGreen } else { [System.Drawing.Color]::Red })
    }

    if ($script:lblSteamCMD_IniStatus) {
        $script:lblSteamCMD_IniStatus.Text = "PalWorldSettings.ini: " + ($(if ($iniExists) { "Found" } else { "Missing" }))
        $script:lblSteamCMD_IniStatus.ForeColor = $(if ($iniExists) { [System.Drawing.Color]::LimeGreen } else { [System.Drawing.Color]::Red })
    }

    Write-SteamCMDLog "Checked required files:"
    Write-SteamCMDLog "  PalServer.exe: " + ($(if ($serverExists) { "FOUND" } else { "MISSING" }))
    Write-SteamCMDLog "  PalWorldSettings.ini: " + ($(if ($iniExists) { "FOUND" } else { "MISSING" }))

    return [PSCustomObject]@{
        ServerExists = $serverExists
        IniExists    = $iniExists
    }
}

function Install-SteamCMD {
    $paths = Get-SteamCMDPaths

    if (-not (Test-Path $paths.SteamCMDFolder)) {
        New-Item -ItemType Directory -Path $paths.SteamCMDFolder | Out-Null
        Write-SteamCMDLog "Created steamcmd folder."
    }

    if (Test-Path $paths.SteamCMDExe) {
        Write-SteamCMDLog "SteamCMD already exists."
        return
    }

    Write-SteamCMDLog "Downloading SteamCMD..."

    $steamcmdUrl = "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip"
    $zipPath     = Join-Path $paths.SteamCMDFolder "steamcmd.zip"

    try {
        Invoke-WebRequest -Uri $steamcmdUrl -OutFile $zipPath -UseBasicParsing
        Write-SteamCMDLog "Downloaded steamcmd.zip"

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $paths.SteamCMDFolder)

        Remove-Item $zipPath -ErrorAction SilentlyContinue
        Write-SteamCMDLog "Extracted SteamCMD."
    }
    catch {
        Write-SteamCMDLog "ERROR downloading or extracting SteamCMD: $($_.Exception.Message)"
        throw
    }
}

function Install-PalworldServer {
    $paths = Get-SteamCMDPaths

    try { Install-SteamCMD } catch { return }

    if (-not (Test-Path $paths.SteamCMDExe)) {
        Write-SteamCMDLog "SteamCMD missing after install."
        return
    }

    Write-SteamCMDLog "Installing Palworld server..."

    $arguments = @(
        "+login", "anonymous",
        "+app_update", "2394010", "validate",
        "+quit"
    )

    try {
        & $paths.SteamCMDExe $arguments 2>&1 | ForEach-Object { Write-SteamCMDLog $_ }
        Write-SteamCMDLog "Install complete."
        Check-RequiredServerFiles | Out-Null
    }
    catch {
        Write-SteamCMDLog "ERROR during install: $($_.Exception.Message)"
    }
}

function Update-PalworldServer {
    $paths = Get-SteamCMDPaths

    if (-not (Test-Path $paths.SteamCMDExe)) {
        Write-SteamCMDLog "SteamCMD missing. Installing..."
        try { Install-SteamCMD } catch { return }
    }

    Write-SteamCMDLog "Stopping server..."
    try { Stop-Server } catch {}

    Write-SteamCMDLog "Updating Palworld server..."

    $arguments = @(
        "+login", "anonymous",
        "+app_update", "2394010", "validate",
        "+quit"
    )

    try {
        & $paths.SteamCMDExe $arguments 2>&1 | ForEach-Object { Write-SteamCMDLog $_ }
        Write-SteamCMDLog "Update complete."
        Check-RequiredServerFiles | Out-Null
    }
    catch {
        Write-SteamCMDLog "ERROR during update: $($_.Exception.Message)"
    }

    if ($script:chkSteamCMD_AutoRestart -and $script:chkSteamCMD_AutoRestart.Checked) {
        Write-SteamCMDLog "Auto-restart enabled. Starting server..."
        try { Start-Server } catch {}
    }
    else {
        Write-SteamCMDLog "Auto-restart disabled."
    }
}

function Get-PalworldInstalledBuildID {
    $manifestPath = Join-Path $script:rootPath "steamapps\appmanifest_2394010.acf"

    if (-not (Test-Path $manifestPath)) {
        return $null
    }

    $content = Get-Content $manifestPath -Raw
    if ($content -match '"buildid"\s+"(\d+)"') {
        return $matches[1]
    }

    return $null
}

function Get-PalworldLatestBuildID {
    $paths = Get-SteamCMDPaths

    $output = & $paths.SteamCMDExe "+login" "anonymous" "+app_info_print" "2394010" "+quit" 2>&1

    foreach ($line in $output) {
        if ($line -match '"buildid"\s+"(\d+)"') {
            return $matches[1]
        }
    }

    return $null
}

function Update-PalworldUpdateStatus {
    $installed = Get-PalworldInstalledBuildID
    $latest    = Get-PalworldLatestBuildID

    if (-not $script:lblSteamCMD_UpdateStatus) { return }

    if (-not $installed) {
        $script:lblSteamCMD_UpdateStatus.Text = "Update Status: No server installed"
        $script:lblSteamCMD_UpdateStatus.ForeColor = [System.Drawing.Color]::Orange
        return
    }

    if ($installed -eq $latest) {
        $script:lblSteamCMD_UpdateStatus.Text = "Update Status: Up to date"
        $script:lblSteamCMD_UpdateStatus.ForeColor = [System.Drawing.Color]::LimeGreen
    }
    else {
        $script:lblSteamCMD_UpdateStatus.Text = "Update Status: Update available"
        $script:lblSteamCMD_UpdateStatus.ForeColor = [System.Drawing.Color]::Red
    }
}


function Check-ForPalworldUpdates {
    $paths = Get-SteamCMDPaths

    if (-not (Test-Path $paths.SteamCMDExe)) {
        Write-SteamCMDLog "SteamCMD missing. Installing..."
        try { Install-SteamCMD } catch { return }
    }

    Write-SteamCMDLog "Checking for updates..."

    $arguments = @(
        "+login", "anonymous",
        "+app_info_print", "2394010",
        "+quit"
    )

    try {
        & $paths.SteamCMDExe $arguments 2>&1 | ForEach-Object { Write-SteamCMDLog $_ }
        Write-SteamCMDLog "Finished checking updates."
    }
    catch {
        Write-SteamCMDLog "ERROR checking updates: $($_.Exception.Message)"
    }
}
