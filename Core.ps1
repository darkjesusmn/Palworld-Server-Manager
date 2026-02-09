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
# Append-ServerConsole
# ==========================================================================================
function Append-ServerConsole {
    param([string]$text)

    if (-not $script:serverLogsBox) { return }

    if ($script:serverLogsBox.InvokeRequired) {
        $script:serverLogsBox.Invoke([Action]{
            $script:serverLogsBox.AppendText("$text`r`n")
            $script:serverLogsBox.SelectionStart = $script:serverLogsBox.Text.Length
            $script:serverLogsBox.ScrollToCaret()
        })
    }
    else {
        $script:serverLogsBox.AppendText("$text`r`n")
        $script:serverLogsBox.SelectionStart = $script:serverLogsBox.Text.Length
        $script:serverLogsBox.ScrollToCaret()
    }
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

        # --- PROCESS STARTUP -------------------------------------------------------
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $script:serverExePath
        $psi.WorkingDirectory = $script:serverRoot
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true

        if ($script:startupArguments) {
            $psi.Arguments = $script:startupArguments
        }

        $script:serverProcess = [System.Diagnostics.Process]::Start($psi)

        if ($null -eq $script:serverProcess) {
            throw "Process returned null"
        }

        $script:serverProcess.BeginOutputReadLine() | Out-Null
        $script:serverProcess.BeginErrorReadLine()  | Out-Null

        # --- STATE FLAGS -----------------------------------------------------------
        $script:serverRunning   = $true
        $script:serverStarting  = $false
        $script:serverStartTime = Get-Date
        $script:lastCrashTime   = $null

        # --- CRASH DETECTION TIMER -------------------------------------------------
        if (-not $script:crashDetectionTimer) {
            $script:crashDetectionTimer = New-Object System.Windows.Forms.Timer
            $script:crashDetectionTimer.Interval = 5000
            $script:crashDetectionTimer.Add_Tick({ Detect-ServerCrash })
        }
        $script:crashDetectionTimer.Start()

        # --- LOG OUTPUT ROUTING ----------------------------------------------------
        Set-LogOutputBox $serverConsoleTextBox

        # --- API VERIFICATION TIMER ------------------------------------------------
        if (-not $script:apiVerificationTimer) {
            $script:apiVerificationTimer = New-Object System.Windows.Forms.Timer
            $script:apiVerificationTimer.Interval = 20000
            $script:apiVerificationTimer.Add_Tick({
                Write-Host "`n=== Verifying REST API Connection (20s after start) ===" -ForegroundColor Cyan
                if (Get-Command Update-RestAPISettings -ErrorAction SilentlyContinue) {
                    Update-RestAPISettings
                }
                $script:apiVerificationTimer.Stop()
            })
        }
        $script:apiVerificationTimer.Start()

        # --- CALLBACK --------------------------------------------------------------
        if ($script:onServerStarted) { & $script:onServerStarted }

        # --- AUTO-RESTART TIMER ----------------------------------------------------
        if ($script:autoRestartTimer) { $script:autoRestartTimer.Start() }

        # --- RESET NEXT RESTART COUNTDOWN ------------------------------------------
        if ($script:autoRestartEnabled) {
            $script:nextRestartTime = (Get-Date).AddHours(6)

            if ($script:nextRestartLabel) {
                $script:nextRestartLabel.Text = "Next Restart: 06:00:00"
            }
        }

        # --- RESTART MONITORING TIMER ----------------------------------------------
        if ($script:monitoringTimer) {
            $script:monitoringTimer.Start()
        }

        # --- UI READY --------------------------------------------------------------
        $script:uiReady = $true

        # --- INITIALIZE COMPACT CHART TITLES ---------------------------------------
        if ($script:cpuChart) {
            $script:cpuChart.Titles[0].Text = "CPU: --   |   Threads: --   |   Handles: --"
        }
        if ($script:ramChart) {
            $script:ramChart.Titles[0].Text = "RAM: --   |   Peak: --"
        }
        if ($script:fpsChart) {
            $script:fpsChart.Titles[0].Text = "FPS: --"
        }
        if ($script:playerChart) {
            $script:playerChart.Titles[0].Text = "Players: --"
        }

        return $true

    } catch {
        $script:serverRunning  = $false
        $script:serverStarting = $false
        Write-Error "Start-Server failed: $_"
        return $false
    }
}





# ==========================================================================================
# Stop-Server (Graceful Shutdown via API)
# ==========================================================================================
function Stop-Server {

    if (-not $script:serverRunning -and -not $script:serverStarting) { return }

    try {
        Write-Host "`n=== GRACEFUL SERVER SHUTDOWN ===" -ForegroundColor Yellow
        
        if (Get-Command Shutdown-ServerREST -ErrorAction SilentlyContinue) {
            Write-Host "Sending graceful shutdown via REST API (30 second warning)..." -ForegroundColor Cyan
            $shutdownResult = Shutdown-ServerREST -WaitTimeSeconds 30 -Message "Server shutting down in 30 seconds. Please save your progress."
            
            if ($shutdownResult) {
                Write-Host "[OK] Shutdown command sent to server" -ForegroundColor Green
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

        if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
            Write-Host "Force killing server process..." -ForegroundColor Yellow
            try { $script:serverProcess.Kill() } catch {}
            try { Stop-Process -Id $script:serverProcess.Id -Force -ErrorAction SilentlyContinue } catch {}

            $waitTime = 0
            while (-not $script:serverProcess.HasExited -and $waitTime -lt 5) {
                Start-Sleep -Milliseconds 500
                $waitTime++
            }
        }

        try { $script:serverProcess.Dispose() } catch {}

        $script:serverProcess   = $null
        $script:serverRunning   = $false
        $script:serverStarting  = $false
        $script:serverStartTime = $null

        if ($script:crashDetectionTimer)   { $script:crashDetectionTimer.Stop() }
        if ($script:apiVerificationTimer)  { $script:apiVerificationTimer.Stop() }
        if ($script:monitoringTimer)       { $script:monitoringTimer.Stop() }

        if ($script:autoRestartTimer)      { $script:autoRestartTimer.Stop() }   # ← NEW LINE

        Reset-MonitoringUI      

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

#=========================================================================================
# Redirect-PowerShellOutput
#=========================================================================================
function Redirect-PowerShellOutput {

    # Remove any existing overrides so ours take effect
    Remove-Item function:Write-Host -ErrorAction SilentlyContinue
    Remove-Item function:Write-Warning -ErrorAction SilentlyContinue
    Remove-Item function:Write-Error -ErrorAction SilentlyContinue
    Remove-Item function:Write-Verbose -ErrorAction SilentlyContinue
    Remove-Item function:Write-Debug -ErrorAction SilentlyContinue
    Remove-Item function:Write-Information -ErrorAction SilentlyContinue
    Remove-Item function:Out-Default -ErrorAction SilentlyContinue

    # Override Write-* functions (join all args)
    Set-Item function:Write-Host -Value {
        param([Parameter(ValueFromRemainingArguments = $true)] $Message)
        $text = ($Message -join ' ')
        Append-ServerConsole "[HOST] $text"
    }

    Set-Item function:Write-Warning -Value {
        param([Parameter(ValueFromRemainingArguments = $true)] $Message)
        $text = ($Message -join ' ')
        Append-ServerConsole "[WARN] $text"
    }

    Set-Item function:Write-Error -Value {
        param([Parameter(ValueFromRemainingArguments = $true)] $Message)
        $text = ($Message -join ' ')
        Append-ServerConsole "[ERROR] $text"
    }

    Set-Item function:Write-Verbose -Value {
        param([Parameter(ValueFromRemainingArguments = $true)] $Message)
        $text = ($Message -join ' ')
        Append-ServerConsole "[VERBOSE] $text"
    }

    Set-Item function:Write-Debug -Value {
        param([Parameter(ValueFromRemainingArguments = $true)] $Message)
        $text = ($Message -join ' ')
        Append-ServerConsole "[DEBUG] $text"
    }

    Set-Item function:Write-Information -Value {
        param([Parameter(ValueFromRemainingArguments = $true)] $Message)
        $text = ($Message -join ' ')
        Append-ServerConsole "[INFO] $text"
    }

    # ⭐ GLOBAL OUTPUT INTERCEPTOR (captures EVERYTHING from ALL runspaces)
    Set-Item function:Out-Default -Value {
        param([Parameter(ValueFromRemainingArguments = $true)] $InputObject)
        foreach ($line in $InputObject) {
            Append-ServerConsole "[OUT] $line"
        }
    }

    # Hook native PowerShell streams
    $global:WarningPreference        = 'Continue'
    $global:VerbosePreference        = 'Continue'
    $global:DebugPreference          = 'Continue'
    $global:InformationPreference    = 'Continue'
    $global:ErrorActionPreference    = 'Continue'

    # Capture ALL errors (native stream 2)
    Register-EngineEvent PowerShell.OnError -Action {
        $items = $Event.SourceArgs
        if (-not $items -or $items.Count -eq 0) {
            if ($global:Error.Count -gt 0) {
                $msg = $global:Error[0].Exception.Message
                Append-ServerConsole "[ERROR] $msg"
            } else {
                Append-ServerConsole "[ERROR] (no message)"
            }
            return
        }

        foreach ($item in $items) {
            if ($item -is [System.Management.Automation.ErrorRecord]) {
                Append-ServerConsole "[ERROR] $($item.Exception.Message)"
            } elseif ($item) {
                Append-ServerConsole "[ERROR] $item"
            } else {
                Append-ServerConsole "[ERROR] (no message)"
            }
        }
    }

    # Capture ALL warnings (native stream 3)
    Register-EngineEvent PowerShell.OnWarning -Action {
        $items = $Event.SourceArgs
        if (-not $items -or $items.Count -eq 0) {
            Append-ServerConsole "[WARN] (no message)"
            return
        }

        foreach ($item in $items) {
            Append-ServerConsole "[WARN] $item"
        }
    }

    # Capture ALL information messages
    Register-EngineEvent PowerShell.OnInformation -Action {
        $items = $Event.SourceArgs
        if (-not $items -or $items.Count -eq 0) {
            Append-ServerConsole "[INFO] (no message)"
            return
        }

        foreach ($item in $items) {
            Append-ServerConsole "[INFO] $item"
        }
    }

    # Capture CommandNotFound exceptions
    $ExecutionContext.InvokeCommand.CommandNotFoundAction = {
        param($commandName, $exception)
        Append-ServerConsole "[ERROR] $($exception.Message)"
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


    if ($script:serverRunning -or $script:serverStarting) {
        Stop-Server | Out-Null
    }
}