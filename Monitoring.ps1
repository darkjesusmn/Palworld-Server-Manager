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

# ==========================================================================================
# FUNCTION: Initialize-Monitoring
# ==========================================================================================

function Initialize-Monitoring {
    Write-Verbose "Initializing Unified REST Monitoring..."

    if (-not $script:monitoringTimer) {
        $script:monitoringTimer = New-Object System.Windows.Forms.Timer
        $script:monitoringTimer.Interval = $script:monitoringInterval
        $script:monitoringTimer.Add_Tick({ Update-MetricsREST })
        $script:monitoringTimer.Start()
    }
}

# ==========================================================================================
# FUNCTION: Update-MetricsREST
# ==========================================================================================

function Update-MetricsREST {
    $rest  = Get-ServerMetricsREST
    $local = Get-LocalSystemMetrics

    # ============================================================
    # UPDATE MONITORING TAB LABELS
    # ============================================================
    if ($rest) {
        $script:monitoringLabels.Players.Text = "Players: $($rest.Players)"
        $script:monitoringLabels.FPS.Text     = "FPS: $($rest.FPS)"
        $script:monitoringLabels.Uptime.Text  = "Uptime: $($rest.Uptime)"
    }

    if ($local) {
        $script:monitoringLabels.CpuAvg.Text  = "CPU: $($local.CPU)%"
        $script:monitoringLabels.RamAvg.Text  = "RAM: $($local.RAM) MB"
        $script:monitoringLabels.RamPeak.Text = "Peak RAM: $($local.PeakRAM) MB"
        $script:monitoringLabels.CpuPeak.Text = "Threads: $($local.Threads) | Handles: $($local.Handles)"
    }

    # ============================================================
    # UPDATE TOP UI (MAIN DASHBOARD) — USING YOUR REAL VARIABLES
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
    # COLOR CODING (CPU / RAM / FPS) — MONITORING TAB
    # ============================================================

    # CPU color thresholds
    if ($local.CPU -ge 85) {
        $script:monitoringLabels.CpuAvg.ForeColor = 'Red'
    }
    elseif ($local.CPU -ge 60) {
        $script:monitoringLabels.CpuAvg.ForeColor = 'Orange'
    }
    else {
        $script:monitoringLabels.CpuAvg.ForeColor = 'LimeGreen'
    }

    # RAM color thresholds
    if ($local.RAM -ge 6000) {
        $script:monitoringLabels.RamAvg.ForeColor = 'Red'
    }
    elseif ($local.RAM -ge 4000) {
        $script:monitoringLabels.RamAvg.ForeColor = 'Orange'
    }
    else {
        $script:monitoringLabels.RamAvg.ForeColor = 'LimeGreen'
    }

    # FPS color thresholds
    if ($rest.FPS -le 20) {
        $script:monitoringLabels.FPS.ForeColor = 'Red'
    }
    elseif ($rest.FPS -le 40) {
        $script:monitoringLabels.FPS.ForeColor = 'Orange'
    }
    else {
        $script:monitoringLabels.FPS.ForeColor = 'LimeGreen'
    }

    # ============================================================
    # COLOR CODING — TOP UI (USING YOUR REAL VARIABLES)
    # ============================================================

    # CPU color
    if ($local.CPU -ge 85) {
        $script:cpuLabel.ForeColor = 'Red'
    }
    elseif ($local.CPU -ge 60) {
        $script:cpuLabel.ForeColor = 'Orange'
    }
    else {
        $script:cpuLabel.ForeColor = 'LimeGreen'
    }

    # RAM color
    if ($local.RAM -ge 6000) {
        $script:ramLabel.ForeColor = 'Red'
    }
    elseif ($local.RAM -ge 4000) {
        $script:ramLabel.ForeColor = 'Orange'
    }
    else {
        $script:ramLabel.ForeColor = 'LimeGreen'
    }

    # ============================================================
    # FREEZE DETECTION (FPS = 0)
    # ============================================================

    if ($rest.FPS -eq 0) {
        $script:freezeCounter++
    }
    else {
        $script:freezeCounter = 0
    }

    if ($script:freezeCounter -ge $script:freezeThreshold) {
        $script:freezeCounter = 0

        $result = [System.Windows.Forms.MessageBox]::Show(
            "Server FPS has been 0 for $script:freezeThreshold seconds. Restart server?",
            "Freeze Detected",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Restart-Server
        }
    }

    # ============================================================
    # CHART UPDATES
    # ============================================================
    Add-ChartPoint $script:cpuChart    $local.CPU
    Add-ChartPoint $script:ramChart    $local.RAM
    Add-ChartPoint $script:playerChart $rest.Players
    Add-ChartPoint $script:fpsChart    $rest.FPS

    # ============================================================
    # HEALTH (must be last)
    # ============================================================
    Update-HealthStatus -CPU $local.CPU -RAM $local.RAM -FPS $rest.FPS
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
        return
    }

    # Start with perfect score
    $score = 100

    # CPU impact
    if ($CPU -gt 85) { $score -= 40 }
    elseif ($CPU -gt 70) { $score -= 25 }
    elseif ($CPU -gt 50) { $score -= 10 }

    # RAM impact (adjust thresholds to your server size)
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

    $script:monitoringLabels.Health.Text = "Health: $status"
}


#===========================================================================================
# FUNCTION: Get-Palworldprocess locator
#===========================================================================================   
function Get-PalworldProcess {
    if ($script:palworldProcess -and !$script:palworldProcess.HasExited) {
        return $script:palworldProcess
    }

    # Try all known Palworld server names
    $names = @(
        "Palworld-Win64-Shipping",   # <-- THIS is the real dedicated server
        "Pal",                       # sometimes appears as "Pal.exe"
        "PalServer-Win64-Test-Cmd",
        "PalServer",
        "PalServer-Win64-Shipping"
    )

    foreach ($name in $names) {
        $proc = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($proc) {
            $script:palworldProcess = $proc
            return $proc
        }
    }

    return $null
}




#===========================================================================================
# FUNCTION: Get-LocalSystemMetrics
#===========================================================================================
function Get-LocalSystemMetrics {
    $proc = Get-PalworldProcess
    if (-not $proc) {
        return @{
            CPU     = $null
            RAM     = $null
            Threads = $null
            Handles = $null
            PeakRAM = $null
        }
    }

    # CPU %
    $now = Get-Date
    $cpuTime = $proc.TotalProcessorTime.TotalMilliseconds

    if ($script:lastCpuSample -and $script:lastCpuTime) {
        $deltaTime = ($now - $script:lastCpuSample).TotalMilliseconds
        $deltaCpu  = $cpuTime - $script:lastCpuTime

        # Raw CPU percent across all cores
        $cpuPercent = ($deltaCpu / $deltaTime) * 100

        # Normalize by logical cores
        $logicalCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        if ($logicalCores -gt 0) {
            $cpuPercent = [Math]::Round($cpuPercent / $logicalCores, 1)
        } else {
            $cpuPercent = 0
        }
    }
    else {
        $cpuPercent = 0
    }

    # Update CPU sample history
    $script:lastCpuSample = $now
    $script:lastCpuTime   = $cpuTime

    # RAM MB
    $ramMB = [Math]::Round($proc.WorkingSet64 / 1MB, 0)

    # Peak RAM MB
    $peakMB = [Math]::Round($proc.PeakWorkingSet64 / 1MB, 0)

    return @{
        CPU     = $cpuPercent
        RAM     = $ramMB
        Threads = $proc.Threads.Count
        Handles = $proc.Handles
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
