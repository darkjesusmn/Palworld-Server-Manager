# ==========================================================================================
# Core.ps1 - Server Process Management
# ==========================================================================================

# -------------------------
# GLOBAL VARIABLES
# -------------------------
$script:serverProcess       = $null
$script:serverRunning       = $false
$script:serverStarting      = $false
$script:serverStartTime     = $null
$script:lastCrashTime       = $null

$script:uptimeLabel         = $null
$script:uptimeTimer         = $null
$script:crashDetectionTimer = $null

$script:startupArguments    = ""
$script:selectedArguments   = @{}

$script:serverLogsBox       = $null
$script:outputReaderTimer   = $null
$script:lastLogPosition     = 0
$script:logFileFound        = $false

$script:onServerCrash       = $null
$script:onServerStarted     = $null

$script:apiVerificationTimer = $null  # Timer to verify API after server starts

# Determine server root
if ($PSScriptRoot -like "*\modules") {
    $script:serverRoot = Split-Path -Parent $PSScriptRoot
} else {
    $script:serverRoot = $PSScriptRoot
}

$script:serverExePath = Join-Path $script:serverRoot "PalServer.exe"
$script:logDir        = Join-Path $script:serverRoot "Pal\Saved\Logs"

# ==========================================================================================
# Initialize-Core
# ==========================================================================================
function Initialize-Core {
    if (-not $script:uptimeTimer) {
        $script:uptimeTimer = New-Object System.Windows.Forms.Timer
        $script:uptimeTimer.Interval = 1000
        $script:uptimeTimer.Add_Tick({ Update-Uptime })
        $script:uptimeTimer.Start()
    }
}

# ==========================================================================================
# Set-LogOutputBox
# ==========================================================================================
function Set-LogOutputBox {
    param([System.Windows.Forms.TextBox]$textbox)
    $script:serverLogsBox = $textbox
}

# ==========================================================================================
# Build-StartupArguments
# ==========================================================================================
function Build-StartupArguments {
    $args = @()

    foreach ($key in $script:selectedArguments.Keys) {
        $arg = $script:selectedArguments[$key]

        if ($arg.selected) {
            if ($arg.hasValue -and $arg.value) {
                $args += "$($arg.argument)=$($arg.value)"
            } elseif (-not $arg.hasValue) {
                $args += $arg.argument
            }
        }
    }

    $script:startupArguments = $args -join " "
    return $script:startupArguments
}

# ==========================================================================================
# Start-Server
# ==========================================================================================
function Start-Server {

    if ($script:serverRunning -or $script:serverStarting) { return }

    if (-not (Test-Path $script:serverExePath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "PalServer.exe not found.",
            "Error",
            "OK",
            "Error"
        ) | Out-Null
        return
    }

    try {
        $script:serverStarting = $true

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $script:serverExePath
        $psi.WorkingDirectory = $script:serverRoot
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        
        # Redirect STDOUT and STDERR to capture console output
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        if ($script:startupArguments) {
            $psi.Arguments = $script:startupArguments
        }

        $script:serverProcess = [System.Diagnostics.Process]::Start($psi)

        if ($null -eq $script:serverProcess) {
            throw "Process returned null"
        }

        # Start async readers for STDOUT and STDERR
        $script:serverProcess.BeginOutputReadLine() | Out-Null
        $script:serverProcess.BeginErrorReadLine() | Out-Null

        $script:serverRunning  = $true
        $script:serverStarting = $false
        $script:serverStartTime = Get-Date
        $script:lastCrashTime = $null

        # Start crash detection
        if (-not $script:crashDetectionTimer) {
            $script:crashDetectionTimer = New-Object System.Windows.Forms.Timer
            $script:crashDetectionTimer.Interval = 5000
            $script:crashDetectionTimer.Add_Tick({ Detect-ServerCrash })
        }
        $script:crashDetectionTimer.Start()

        # Start API verification timer (20 seconds after server starts)
        if (-not $script:apiVerificationTimer) {
            $script:apiVerificationTimer = New-Object System.Windows.Forms.Timer
            $script:apiVerificationTimer.Interval = 20000  # 20 seconds
            $script:apiVerificationTimer.Add_Tick({
                Write-Host "`n=== Verifying REST API Connection (20s after start) ===" -ForegroundColor Cyan
                if (Get-Command Update-RestAPISettings -ErrorAction SilentlyContinue) {
                    Update-RestAPISettings
                }
                # Only run once, then stop
                $script:apiVerificationTimer.Stop()
            })
            $script:apiVerificationTimer.Start()
        }

        # Restart log reader
        Stop-OutputReader
        Start-OutputReader

        if ($script:onServerStarted) { & $script:onServerStarted }

        return $true

    } catch {
        $script:serverRunning  = $false
        $script:serverStarting = $false
        Write-Error "Start-Server failed: $_"
        return $false
    }
}

# ==========================================================================================
# Start-OutputReader
# ==========================================================================================
function Start-OutputReader {

    if ($null -eq $script:serverLogsBox) { return }

    $script:lastLogPosition = 0
    $script:logFileFound = $false

    $script:serverLogsBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Log reader started`r`n")
    $script:serverLogsBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Searching logs in: $script:logDir`r`n")

    $script:outputReaderTimer = New-Object System.Windows.Forms.Timer
    $script:outputReaderTimer.Interval = 1000

    $script:outputReaderTimer.Add_Tick({
        try {
            if (-not (Test-Path $script:logDir)) {
                if (-not $script:logFileFound) {
                    $script:serverLogsBox.AppendText("Log directory not found.`r`n")
                    $script:logFileFound = $true
                }
                return
            }

            $logFiles = Get-ChildItem $script:logDir -Filter "*.log" -ErrorAction SilentlyContinue
            if ($logFiles.Count -eq 0) {
                if (-not $script:logFileFound) {
                    $script:serverLogsBox.AppendText("No log files found.`r`n")
                    $script:logFileFound = $true
                }
                return
            }

            $logFile = $logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1

            if (-not $script:logFileFound) {
                $script:serverLogsBox.AppendText("Using log file: $($logFile.Name)`r`n")
                $script:logFileFound = $true
            }

            # Read new lines
            $fs = [System.IO.File]::Open($logFile.FullName, 'Open', 'Read', 'ReadWrite')
            $fs.Seek($script:lastLogPosition, 'Begin') | Out-Null

            $reader = New-Object System.IO.StreamReader($fs)
            $newLines = @()

            while ($reader.Peek() -gt -1) {
                $line = $reader.ReadLine()
                if ($line) { $newLines += $line }
            }

            $script:lastLogPosition = $fs.Position

            $reader.Dispose()
            $fs.Dispose()

            foreach ($line in $newLines) {
                $script:serverLogsBox.AppendText("$line`r`n")
            }

            # Trim to last 500 lines
            $lines = $script:serverLogsBox.Lines
            if ($lines.Count -gt 500) {
                $script:serverLogsBox.Lines = $lines[-400..-1]
            }

            $script:serverLogsBox.SelectionStart = $script:serverLogsBox.Text.Length
            $script:serverLogsBox.ScrollToCaret()

            if ($script:serverProcess -and $script:serverProcess.HasExited) {
                $script:outputReaderTimer.Stop()
                $script:serverLogsBox.AppendText("Server stopped.`r`n")
            }

        } catch {}
    })

    $script:outputReaderTimer.Start()
}

# ==========================================================================================
# Stop-OutputReader
# ==========================================================================================
function Stop-OutputReader {
    if ($script:outputReaderTimer) {
        $script:outputReaderTimer.Stop()
        $script:outputReaderTimer.Dispose()
        $script:outputReaderTimer = $null
    }
    $script:lastLogPosition = 0
    $script:logFileFound = $false
}

# ==========================================================================================
# Stop-Server (Graceful Shutdown via API)
# ==========================================================================================
function Stop-Server {

    if (-not $script:serverRunning -and -not $script:serverStarting) { return }

    try {
        Write-Host "`n=== GRACEFUL SERVER SHUTDOWN ===" -ForegroundColor Yellow
        
        # Use REST API for graceful shutdown with 30 second warning
        if (Get-Command Shutdown-ServerREST -ErrorAction SilentlyContinue) {
            Write-Host "Sending graceful shutdown via REST API (30 second warning)..." -ForegroundColor Cyan
            $shutdownResult = Shutdown-ServerREST -WaitTimeSeconds 30 -Message "Server shutting down in 30 seconds. Please save your progress."
            
            if ($shutdownResult) {
                Write-Host "[OK] Shutdown command sent to server" -ForegroundColor Green
                # Wait for server to shut down gracefully (up to 40 seconds for 30 second warning + buffer)
                Write-Host "Waiting for server to shut down gracefully (up to 40 seconds)..." -ForegroundColor Cyan
                $waitTime = 0
                $maxWait = 40
                
                while ($script:serverProcess -and -not $script:serverProcess.HasExited -and $waitTime -lt $maxWait) {
                    Start-Sleep -Milliseconds 500
                    $waitTime += 0.5
                    if ([int]$waitTime % 2 -eq 0) {
                        Write-Host "." -NoNewline -ForegroundColor Gray
                    }
                }
                Write-Host "`n[OK] Server shutdown complete" -ForegroundColor Green
            } else {
                Write-Warning "REST API shutdown failed, attempting process kill..."
            }
        } else {
            Write-Warning "REST API not available, attempting process kill..."
        }

        # Cleanup: Kill process if still running
        if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
            Write-Host "Force killing server process..." -ForegroundColor Yellow
            try { $script:serverProcess.Kill() } catch {}
            try { Stop-Process -Id $script:serverProcess.Id -Force -ErrorAction SilentlyContinue } catch {}
            
            # Wait for process to actually exit (up to 5 seconds)
            $waitTime = 0
            while (-not $script:serverProcess.HasExited -and $waitTime -lt 5) {
                Start-Sleep -Milliseconds 500
                $waitTime++
            }
        }

        try { $script:serverProcess.Dispose() } catch {}

        $script:serverProcess = $null
        $script:serverRunning = $false
        $script:serverStarting = $false
        $script:serverStartTime = $null

        if ($script:crashDetectionTimer) { $script:crashDetectionTimer.Stop() }
        if ($script:apiVerificationTimer) { $script:apiVerificationTimer.Stop() }
        Stop-OutputReader

        Write-Host "=== SHUTDOWN COMPLETE ===" -ForegroundColor Green
        return $true

    } catch {
        Write-Error "Stop-Server failed: $($_.Exception.Message)"
        return $false
    }
}

# ==========================================================================================
# Force-Kill-Server (Immediate shutdown via API, no warning)
# ==========================================================================================
function Force-Kill-Server {

    if (-not $script:serverRunning -and -not $script:serverStarting) { return }

    try {
        Write-Host "`n=== FORCE KILL SERVER (IMMEDIATE) ===" -ForegroundColor Red
        
        # Try REST API force stop first (no countdown)
        if (Get-Command Stop-ServerREST -ErrorAction SilentlyContinue) {
            Write-Host "Sending immediate force stop via REST API..." -ForegroundColor Cyan
            $killResult = Stop-ServerREST
            
            if ($killResult) {
                Write-Host "[OK] Force stop command sent" -ForegroundColor Green
                # Wait briefly for API stop (up to 10 seconds)
                Write-Host "Waiting for server to shut down (up to 10 seconds)..." -ForegroundColor Cyan
                $waitTime = 0
                
                while ($script:serverProcess -and -not $script:serverProcess.HasExited -and $waitTime -lt 10) {
                    Start-Sleep -Milliseconds 500
                    $waitTime += 0.5
                }
            } else {
                Write-Warning "REST API force stop failed, attempting process kill..."
            }
        } else {
            Write-Warning "REST API not available, attempting process kill..."
        }

        # Kill the process if still running
        if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
            Write-Host "Killing server process..." -ForegroundColor Red
            try { $script:serverProcess.Kill() } catch {}
            try { Stop-Process -Id $script:serverProcess.Id -Force -ErrorAction SilentlyContinue } catch {}
            
            # Wait for process to actually exit (up to 5 seconds)
            $waitTime = 0
            while (-not $script:serverProcess.HasExited -and $waitTime -lt 5) {
                Start-Sleep -Milliseconds 500
                $waitTime++
            }
            Write-Host "[OK] Process killed" -ForegroundColor Green
        }

        try { $script:serverProcess.Dispose() } catch {}

        $script:serverProcess = $null
        $script:serverRunning = $false
        $script:serverStarting = $false
        $script:serverStartTime = $null

        if ($script:crashDetectionTimer) { $script:crashDetectionTimer.Stop() }
        if ($script:apiVerificationTimer) { $script:apiVerificationTimer.Stop() }
        Stop-OutputReader

        Write-Host "=== FORCE KILL COMPLETE ===" -ForegroundColor Red
        return $true

    } catch {
        Write-Error "Force-Kill-Server failed: $($_.Exception.Message)"
        return $false
    }
}

# ==========================================================================================
# Detect-ServerCrash
# ==========================================================================================
function Detect-ServerCrash {

    if ($script:serverProcess -and $script:serverProcess.HasExited) {

        if ($script:serverRunning -or $script:serverStarting) {
            $script:serverRunning = $false
            $script:serverStarting = $false
            $script:lastCrashTime = Get-Date

            Stop-OutputReader

            if ($script:onServerCrash) { & $script:onServerCrash }
        }
    }
}

# ==========================================================================================
# Update-Uptime
# ==========================================================================================
function Update-Uptime {

    if ($script:serverRunning -and $script:serverStartTime) {
        $elapsed = (Get-Date) - $script:serverStartTime
        $text = "{0}d {1}h {2}m {3}s" -f $elapsed.Days, $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds

        if ($script:uptimeLabel) {
            $script:uptimeLabel.Text = "Uptime: $text"
        }
    }
}

# ==========================================================================================
# Get-ServerStatus
# ==========================================================================================
function Get-ServerStatus {
    return @{
        Running      = $script:serverRunning
        Starting     = $script:serverStarting
        Process      = $script:serverProcess
        StartTime    = $script:serverStartTime
        LastCrashTime= $script:lastCrashTime
    }
}

# ==========================================================================================
# Cleanup-Core
# ==========================================================================================
function Cleanup-Core {

    if ($script:uptimeTimer) {
        $script:uptimeTimer.Stop()
        $script:uptimeTimer.Dispose()
    }

    if ($script:crashDetectionTimer) {
        $script:crashDetectionTimer.Stop()
        $script:crashDetectionTimer.Dispose()
    }

    if ($script:apiVerificationTimer) {
        $script:apiVerificationTimer.Stop()
        $script:apiVerificationTimer.Dispose()
    }

    Stop-OutputReader

    if ($script:serverRunning -or $script:serverStarting) {
        Stop-Server | Out-Null
    }
}