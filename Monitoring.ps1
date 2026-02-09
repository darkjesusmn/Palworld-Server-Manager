# ==========================================================================================
# Monitoring.ps1 - Unified REST API Monitoring + History + Charts
# ==========================================================================================
# Uses Palworld REST API only. Tracks:
# - CPU, RAM, Players, FPS, Uptime
# - History for CPU/RAM/Players/FPS
# - Simple health evaluation
# ==========================================================================================

$script:monitoringTimer        = $null
$script:monitoringInterval     = 30000   # 30 seconds
$script:lastMetrics            = $null

$script:cpuHistory             = @()
$script:ramHistory             = @()
$script:playerHistory          = @()
$script:fpsHistory             = @()
$script:maxHistoryPoints       = 100

# Chart references (set from UI)
$script:cpuChart               = $null
$script:ramChart               = $null
$script:playerChart            = $null
$script:fpsChart               = $null

$script:lastCpuSample = $null
$script:lastCpuTime   = $null

$script:freezeCounter = 0 
$script:freezeThreshold = 3 # seconds of FPS=0 before popup

# Auto‑Restart Timer Logic
$script:autoRestartEnabled = $false
$script:autoRestartTimer = $null
$script:autoRestartInterval = 6 * 60 * 60 * 1000   # 6 hours in ms

# ==========================================================================================
# FUNCTION: Initialize-Monitoring
# ==========================================================================================

function Initialize-Monitoring {
    Write-Verbose "Initializing Unified REST Monitoring..."

    if (-not $script:monitoringTimer) {
        $script:monitoringTimer = New-Object System.Windows.Forms.Timer
        $script:monitoringTimer.Interval = $script:monitoringInterval
        $script:monitoringTimer.Add_Tick({
            if ($script:serverRunning) {
                Update-MetricsREST
            }
        })
    }
}


# ==========================================================================================
# FUNCTION: Update-MetricsREST (FULLY MERGED VERSION)
# ==========================================================================================

function Update-MetricsREST {

    if ($script:disableMonitoring -eq $true) { return }
    if (-not $script:uiReady) { return }
    if (-not $script:serverRunning) { return }

    $rest  = Get-ServerMetricsREST
    $local = Get-LocalSystemMetrics

    # ============================================================
    # UPDATE CHART TITLES (COMPACT LAYOUT)
    # ============================================================

    if ($rest -and $local) {

        # CPU chart title
        $script:cpuChart.Titles[0].Text = (
            "CPU: {0}%   |   Threads: {1}   |   Handles: {2}" -f `
            $local.CPU, $local.Threads, $local.Handles
        )

        # RAM chart title
        $script:ramChart.Titles[0].Text = (
            "RAM: {0} MB   |   Peak: {1} MB" -f `
            $local.RAM, $local.PeakRAM
        )

        # FPS chart title
        $script:fpsChart.Titles[0].Text = (
            "FPS: {0}" -f $rest.FPS
        )

        # Players chart title
        $script:playerChart.Titles[0].Text = (
            "Players: {0}" -f $rest.Players
        )
    }

    # ============================================================
    # UPDATE TOP UI (MAIN DASHBOARD)
    # ============================================================

    if ($local) {
        $script:cpuLabel.Text = "CPU: $($local.CPU)%"
        $script:ramLabel.Text = "RAM: $($local.RAM) MB"
    }

    if ($rest) {
        $script:playerCountLabel.Text = "Players: $($rest.Players)"
        $script:uptimeLabel.Text      = "Uptime: $($rest.Uptime)"
    }

    # ============================================================
    # UPDATE CHART DATA
    # ============================================================

    if ($local) {
        $script:cpuChart.Series["CPU"].Points.AddY($local.CPU)
        $script:ramChart.Series["RAM"].Points.AddY($local.RAM)
    }

    if ($rest) {
        $script:fpsChart.Series["FPS"].Points.AddY($rest.FPS)
        $script:playerChart.Series["Players"].Points.AddY($rest.Players)
    }

    # Trim chart history to last 60 points
    foreach ($chart in @($script:cpuChart, $script:ramChart, $script:fpsChart, $script:playerChart)) {
        foreach ($series in $chart.Series) {
            if ($series.Points.Count -gt 60) {
                $series.Points.RemoveAt(0)
            }
        }
    }

    # ============================================================
    # AUTO-RESTART COUNTDOWN (Option B: Sync to REST uptime)
    # ============================================================

    if ($script:nextRestartLabel -ne $null) {

        if ($script:autoRestartEnabled -and $rest) {

            # REST uptime in seconds
            $uptimeSeconds = [int]$rest.Uptime

            # 6 hours in seconds
            $totalSeconds = 6 * 3600

            # Remaining time based on REST uptime
            $remainingSeconds = $totalSeconds - $uptimeSeconds

            # ====================================================
            # IN-GAME COUNTDOWN ANNOUNCEMENTS
            # ====================================================

            # Milestone warnings (1h, 30m, 15m, 10m, 9m...1m)
            foreach ($key in $script:restartWarningsSent.Keys) {

                $threshold = [int]$key

                if ($remainingSeconds -le $threshold -and -not $script:restartWarningsSent[$key]) {

                    $minutes = [int]($threshold / 60)

                    if ($minutes -ge 1) {
                        Send-RestartWarning "$minutes minute(s) until server restart!"
                    }

                    $script:restartWarningsSent[$key] = $true
                }
            }

            # Final 60-second countdown (every second)
            if ($remainingSeconds -le 60) {

            }

            # ====================================================
            # HANDLE RESTART TRIGGER
            # ====================================================

            if ($remainingSeconds -le 30) {

                $script:nextRestartLabel.Text = "Next Restart: NOW"

                Restart-Server

                # Reset next restart time (real system time)
                $script:nextRestartTime = (Get-Date).AddHours(6)
                return
            }

            # ====================================================
            # COLOR-CODED COUNTDOWN + NORMALIZED TIMESPAN
            # ====================================================

            $ts = [TimeSpan]::FromSeconds($remainingSeconds)

            if ($remainingSeconds -le 60) {
                $script:nextRestartLabel.ForeColor = [System.Drawing.Color]::Red
            }
            elseif ($remainingSeconds -le 600) {
                $script:nextRestartLabel.ForeColor = [System.Drawing.Color]::Yellow
            }
            else {
                $script:nextRestartLabel.ForeColor = $colorText
            }

            $script:nextRestartLabel.Text =
                "Next Restart: {0:00}:{1:00}:{2:00}" -f `
                $ts.Hours, $ts.Minutes, $ts.Seconds
        }
        else {
            $script:nextRestartLabel.Text = "Next Restart: --"
        }
    }
}



# =======================================================================================
# FUNCTION: Update-HealthStatus
# =======================================================================================
function Update-HealthStatus {
    param(
        [double]$CPU,
        [double]$RAM,
        [double]$FPS
    )

    # If any metric is missing, show placeholder
    if ($CPU -eq $null -or $RAM -eq $null -or $FPS -eq $null) {
        $script:monitoringLabels.Health.Text = "Health: --"
        $script:monitoringLabels.Health.ForeColor = 'Gray'
        return
    }

    # Start with perfect score
    $score = 100

    # CPU impact
    if ($CPU -gt 85) { $score -= 40 }
    elseif ($CPU -gt 70) { $score -= 25 }
    elseif ($CPU -gt 50) { $score -= 10 }

    # RAM impact
    if ($RAM -gt 6500) { $score -= 40 }
    elseif ($RAM -gt 5000) { $score -= 25 }
    elseif ($RAM -gt 3500) { $score -= 10 }

    # FPS impact
    if ($FPS -lt 20) { $score -= 40 }
    elseif ($FPS -lt 40) { $score -= 20 }

    # Determine status
    if ($score -ge 70) {
        $status = "Good"
    }
    elseif ($score -ge 40) {
        $status = "Moderate"
    }
    else {
        $status = "Critical"
    }

    # Update label text
    $script:monitoringLabels.Health.Text = "Health: $status"

    # Update label color
    switch ($status) {
        "Good"     { $script:monitoringLabels.Health.ForeColor = 'Green' }
        "Moderate" { $script:monitoringLabels.Health.ForeColor = 'Yellow' }
        "Critical" { $script:monitoringLabels.Health.ForeColor = 'Red' }
    }
}

#===========================================================================================
# FUNCTION: Get-PalworldProcess locator (multi-process aware)
#===========================================================================================   
function Get-PalworldProcess {
    # All possible Palworld server-related processes
    $names = @(
        "PalServer-Win64-Shipping-Cmd",
        "PalServer"
    )

    # Get ALL matching processes
    $procs = Get-Process -Name $names -ErrorAction SilentlyContinue

    if ($procs.Count -eq 0) {
        return $null
    }

    return $procs   # return ARRAY
}

#===========================================================================================
# FUNCTION: Get-LocalSystemMetrics (sum across all Palworld processes)
#===========================================================================================
function Get-LocalSystemMetrics {
    $procs = Get-PalworldProcess
    if (-not $procs) {
        return @{
            CPU     = $null
            RAM     = $null
            Threads = $null
            Handles = $null
            PeakRAM = $null
        }
    }

    # SUM CPU + RAM across ALL processes
    $totalCpuTime = 0
    $totalRam     = 0
    $totalPeakRam = 0
    $totalThreads = 0
    $totalHandles = 0

    foreach ($p in $procs) {
        $totalCpuTime += $p.TotalProcessorTime.TotalMilliseconds
        $totalRam     += $p.WorkingSet64
        $totalPeakRam += $p.PeakWorkingSet64
        $totalThreads += $p.Threads.Count
        $totalHandles += $p.Handles
    }

    # CPU %
    $now = Get-Date

    if ($script:lastCpuSample -and $script:lastCpuTime) {
        $deltaTime = ($now - $script:lastCpuSample).TotalMilliseconds
        $deltaCpu  = $totalCpuTime - $script:lastCpuTime

        # Raw CPU percent across all cores
        $cpuPercent = ($deltaCpu / $deltaTime) * 100

        # Normalize by logical cores
        $logicalCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        if ($logicalCores -gt 0) {
            $cpuPercent = [Math]::Round($cpuPercent / $logicalCores, 1)
        }
        else {
            $cpuPercent = 0
        }
    }
    else {
        $cpuPercent = 0
    }

    # Update CPU sample history
    $script:lastCpuSample = $now
    $script:lastCpuTime   = $totalCpuTime

    # RAM MB
    $ramMB  = [Math]::Round($totalRam / 1MB, 0)
    $peakMB = [Math]::Round($totalPeakRam / 1MB, 0)

    return @{
        CPU     = $cpuPercent
        RAM     = $ramMB
        Threads = $totalThreads
        Handles = $totalHandles
        PeakRAM = $peakMB
    }
}

# ==========================================================================================
# FUNCTION: Get-CurrentRESTMetrics
# ==========================================================================================

function Get-CurrentRESTMetrics {
    return $script:lastMetrics
}

# ==========================================================================================
# FUNCTION: Get-RESTMetricsHistory
# ==========================================================================================

function Get-RESTMetricsHistory {
    return @{
        CPU     = $script:cpuHistory
        RAM     = $script:ramHistory
        Players = $script:playerHistory
        FPS     = $script:fpsHistory
    }
}

# ==========================================================================================
# FUNCTION: Get-ServerHealthREST
# ==========================================================================================

function Get-ServerHealthREST {
    param($metrics)

    if ($null -eq $metrics) {
        return @{ Status="Unknown"; Color=[System.Drawing.Color]::Gray }
    }

    $cpu = [double]$metrics.CPU
    $ram = [double]$metrics.RAM

    if ($cpu -gt 90 -or $ram -gt 12000) {
        return @{ Status="Critical"; Color=[System.Drawing.Color]::Red }
    }
    elseif ($cpu -gt 70 -or $ram -gt 8000) {
        return @{ Status="Warning"; Color=[System.Drawing.Color]::Yellow }
    }
    else {
        return @{ Status="Good"; Color=[System.Drawing.Color]::Green }
    }
}

# ==========================================================================================
# FUNCTION: Update-MonitoringCharts
# ==========================================================================================

function Update-MonitoringCharts {
    $history = Get-RESTMetricsHistory

    if ($script:cpuChart -and $script:cpuChart.Series.Count -gt 0) {
        $series = $script:cpuChart.Series[0]
        $series.Points.Clear()
        $i = 0
        foreach ($v in $history.CPU) {
            [void]$series.Points.AddXY($i, $v)
            $i++
        }
    }

    if ($script:ramChart -and $script:ramChart.Series.Count -gt 0) {
        $series = $script:ramChart.Series[0]
        $series.Points.Clear()
        $i = 0
        foreach ($v in $history.RAM) {
            [void]$series.Points.AddXY($i, $v)
            $i++
        }
    }

    if ($script:playerChart -and $script:playerChart.Series.Count -gt 0) {
        $series = $script:playerChart.Series[0]
        $series.Points.Clear()
        $i = 0
        foreach ($v in $history.Players) {
            [void]$series.Points.AddXY($i, $v)
            $i++
        }
    }

    if ($script:fpsChart -and $script:fpsChart.Series.Count -gt 0) {
        $series = $script:fpsChart.Series[0]
        $series.Points.Clear()
        $i = 0
        foreach ($v in $history.FPS) {
            [void]$series.Points.AddXY($i, $v)
            $i++
        }
    }
}

#=================================================================================================
# FUNCTION: Add-ChartPoint  
#=================================================================================================
function Add-ChartPoint {
    param(
        [Parameter(Mandatory=$true)]
        $chart,
        
        [Parameter(Mandatory=$true)]
        $value
    )

    # Ignore null values
    if ($null -eq $value) { return }

    # Add point
    $chart.Series[0].Points.AddY($value)

    # Limit history to 60 points (1 minute at 1-second refresh)
    if ($chart.Series[0].Points.Count -gt 60) {
        $chart.Series[0].Points.RemoveAt(0)
    }
}

# ==========================================================================================
# FUNCTION: Reset-MonitoringUI
# ==========================================================================================
function Reset-MonitoringUI {

    # === RESET TOP BAR LABELS ======================================================
    if ($script:cpuLabel)         { $script:cpuLabel.Text         = "CPU: --" }
    if ($script:ramLabel)         { $script:ramLabel.Text         = "RAM: --" }
    if ($script:playerCountLabel) { $script:playerCountLabel.Text = "Players: --" }
    if ($script:uptimeLabel)      { $script:uptimeLabel.Text      = "Uptime: --" }

    # === RESET CHART TITLES (COMPACT LAYOUT) ======================================
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

    # === CLEAR CHART DATA ==========================================================
    if ($script:cpuChart)    { $script:cpuChart.Series["CPU"].Points.Clear() }
    if ($script:ramChart)    { $script:ramChart.Series["RAM"].Points.Clear() }
    if ($script:fpsChart)    { $script:fpsChart.Series["FPS"].Points.Clear() }
    if ($script:playerChart) { $script:playerChart.Series["Players"].Points.Clear() }

    # === RESET DATA ARRAYS (IF USED) ===============================================
    $script:cpuData    = @()
    $script:ramData    = @()
    $script:fpsData    = @()
    $script:playerData = @()

    # === OPTIONAL: RESET NEXT RESTART LABEL ========================================
    if ($script:nextRestartLabel) {
        $script:nextRestartLabel.Text = "Next Restart: --"
    }
}



# ==========================================================================================
# FUNCTION: Initialize-AutoRestart
# ==========================================================================================
function Initialize-AutoRestart {

    # Enable auto‑restart by default
    $script:autoRestartEnabled = $true

    if (-not $script:autoRestartTimer) {
        $script:autoRestartTimer = New-Object System.Windows.Forms.Timer
        $script:autoRestartTimer.Interval = $script:autoRestartInterval
        $script:autoRestartTimer.Add_Tick({
            if ($script:autoRestartEnabled -and $script:serverRunning) {
                Restart-Server
            }
        })
    }
}

# ==========================================================================================
# FUNCTION: Cleanup-Monitoring
# ==========================================================================================

function Cleanup-Monitoring {
    if ($script:monitoringTimer) {
        try {
            $script:monitoringTimer.Stop()
            $script:monitoringTimer.Dispose()
        } catch {}
        $script:monitoringTimer = $null
    }
}
