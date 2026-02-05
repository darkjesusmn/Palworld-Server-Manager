# ==========================================================================================
# UI.ps1 - Windows Forms GUI Interface
# ==========================================================================================
# Handles: All user interface elements, layouts, event handlers
# Dependencies: Core, ConfigManager, RCON, Backups, Monitoring
# ==========================================================================================
Add-Type -AssemblyName Microsoft.VisualBasic
# ==========================================================================================
# COLOR SCHEME
# ==========================================================================================

$colorBg = [System.Drawing.Color]::FromArgb(30, 30, 30)
$colorPanelBg = [System.Drawing.Color]::FromArgb(45, 45, 45)
$colorText = [System.Drawing.Color]::FromArgb(220, 220, 220)
$colorTextDim = [System.Drawing.Color]::FromArgb(150, 150, 150)
$colorButtonBg = [System.Drawing.Color]::FromArgb(0, 120, 215)
$colorButtonText = [System.Drawing.Color]::White
$colorButtonHover = [System.Drawing.Color]::FromArgb(0, 140, 235)
$colorDanger = [System.Drawing.Color]::FromArgb(220, 53, 69)
$colorSuccess = [System.Drawing.Color]::FromArgb(40, 167, 69)
$colorWarning = [System.Drawing.Color]::FromArgb(255, 193, 7)
$colorTextboxBg = [System.Drawing.Color]::FromArgb(60, 60, 60)
$colorTextboxText = [System.Drawing.Color]::FromArgb(200, 200, 200)

# ==========================================================================================
# STARTUP ARGUMENT DEFINITIONS
# ==========================================================================================

$script:startupArgsDefinitions = @(
    @{ Name="publiclobby"; Display="Public Lobby (Community Server)"; Description="Setup server as a community server"; Argument="-publiclobby"; HasValue=$false },
    @{ Name="useperfthreads"; Display="Use Performance Threads"; Description="Improves performance in multi-threaded CPU environments"; Argument="-useperfthreads"; HasValue=$false },
    @{ Name="NoAsyncLoadingThread"; Display="No Async Loading Thread"; Description="Disable async loading threads"; Argument="-NoAsyncLoadingThread"; HasValue=$false },
    @{ Name="UseMultithreadForDS"; Display="Use Multithread For Dedicated Server"; Description="Use multithreading for dedicated server"; Argument="-UseMultithreadForDS"; HasValue=$false },
    @{ Name="log"; Display="Enable Logging"; Description="Enable detailed server logging to console"; Argument="-log"; HasValue=$false },
    @{ Name="port"; Display="Custom Port"; Description="Change the port number"; Argument="-port"; HasValue=$true; DefaultValue="8211" },
    @{ Name="players"; Display="Max Players"; Description="Maximum number of players"; Argument="-players"; HasValue=$true; DefaultValue="32" },
    @{ Name="publicip"; Display="Public IP"; Description="Manually specify global IP address"; Argument="-publicip"; HasValue=$true; DefaultValue="" },
    @{ Name="publicport"; Display="Public Port"; Description="Manually specify port for community servers"; Argument="-publicport"; HasValue=$true; DefaultValue="" },
    @{ Name="servername"; Display="Server Name"; Description="Custom server name"; Argument="-servername"; HasValue=$true; DefaultValue="PalServer" },
    @{ Name="serverpassword"; Display="Server Password"; Description="Password for private servers"; Argument="-serverpassword"; HasValue=$true; DefaultValue="" }
)


# ==========================================================================================
# GLOBAL UI VARIABLES
# ==========================================================================================

$script:form = $null
$script:statusLabel = $null
$script:uptimeLabel = $null
$script:cpuLabel = $null
$script:ramLabel = $null
$script:playerCountLabel = $null
$script:settingsPath = Join-Path $script:serverRoot "psm_settings.json"

# ==========================================================================================
# FUNCTION: Initialize-UI
# ==========================================================================================

function Initialize-UI {
    $script:form = New-ServerManagerForm
    Setup-EventCallbacks
    Load-UISettings
    Restore-StartupArguments

    # Hook monitoring callback AFTER UI is built
    $script:onMetricsUpdate = { Update-MetricsDisplay }

    return $script:form
}

# ==========================================================================================
# FUNCTION: Restore-StartupArguments
# ==========================================================================================
# Updates checkboxes and textboxes to match saved settings

function Restore-StartupArguments {
    Write-Host "=== RESTORE-STARTUPARGUMENTS DEBUG ===" -ForegroundColor Yellow
    Write-Host "argumentCheckboxes count: $($script:argumentCheckboxes.Count)" -ForegroundColor Yellow
    Write-Host "selectedArguments count: $($script:selectedArguments.Count)" -ForegroundColor Yellow
    
    if ($null -eq $script:argumentCheckboxes -or $script:argumentCheckboxes.Count -eq 0) {
        Write-Host "ERROR: argumentCheckboxes is empty or null!" -ForegroundColor Red
        return
    }

    foreach ($argDef in $script:startupArgsDefinitions) {
        $saved = $script:selectedArguments[$argDef.Name]
        
        Write-Host "Processing: $($argDef.Name)" -ForegroundColor Cyan
        Write-Host "  Saved value: $saved" -ForegroundColor Cyan
        
        # ALWAYS restore checkbox state, whether it's saved or not
        if ($script:argumentCheckboxes.ContainsKey($argDef.Name)) {
            $chkbox = $script:argumentCheckboxes[$argDef.Name]
            Write-Host "  Checkbox found: $($chkbox.GetType())" -ForegroundColor Green
            
            if ($null -ne $saved) {
                # Saved setting exists - use it
                $selectedValue = $saved.selected
                Write-Host "  Setting to: $selectedValue (from saved)" -ForegroundColor Green
                $chkbox.Checked = [bool]$selectedValue
                Write-Host "  Checkbox.Checked is now: $($chkbox.Checked)" -ForegroundColor Green
            } else {
                # No saved setting - default to unchecked
                Write-Host "  No saved value, setting to FALSE" -ForegroundColor Yellow
                $chkbox.Checked = $false
                Write-Host "  Checkbox.Checked is now: $($chkbox.Checked)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ERROR: Checkbox not found in dictionary!" -ForegroundColor Red
        }
        
        # Restore textbox value
        if ($argDef.HasValue -and $script:argumentTextboxes.ContainsKey($argDef.Name)) {
            if ($null -ne $saved -and $null -ne $saved.value) {
                $script:argumentTextboxes[$argDef.Name].Text = $saved.value
                Write-Host "  Textbox set to: $($saved.value)" -ForegroundColor Green
            } else {
                # Use default value
                $script:argumentTextboxes[$argDef.Name].Text = $argDef.DefaultValue
                Write-Host "  Textbox set to default: $($argDef.DefaultValue)" -ForegroundColor Yellow
            }
        }
    }

    # Rebuild the startup arguments string
    Write-Host "Building startup arguments..." -ForegroundColor Cyan
    Build-StartupArguments
    if ($script:currentArgsDisplay) {
        $script:currentArgsDisplay.Text = $script:startupArguments
        Write-Host "Current args display updated" -ForegroundColor Green
    }
    
    Write-Host "=== RESTORE-STARTUPARGUMENTS COMPLETE ===" -ForegroundColor Yellow
}

# ==========================================================================================
# FUNCTION: Setup-EventCallbacks
# ==========================================================================================

function Setup-EventCallbacks {
    $script:onServerCrash = { Update-StatusDisplay }
    $script:onMetricsUpdate = { Update-MetricsDisplay }
}

# ==========================================================================================
# FUNCTION: New-ServerManagerForm
# ==========================================================================================

function New-ServerManagerForm {

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Palworld Server Manager"
    $form.Size = New-Object System.Drawing.Size(1100, 750)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = $colorBg
    $form.ForeColor = $colorText
    $form.Font = New-Object System.Drawing.Font("Arial", 9)
    $form.MinimizeBox = $true
    $form.MaximizeBox = $true
    $form.FormBorderStyle = "Sizable"

    $toolTip = New-Object System.Windows.Forms.ToolTip

    # ====================
    # TOP STATUS BAR
    # ====================

    $statusPanel = New-Object System.Windows.Forms.Panel
    $statusPanel.BackColor = $colorPanelBg
    $statusPanel.Size = New-Object System.Drawing.Size(1100, 100)
    $statusPanel.Location = New-Object System.Drawing.Point(0, 0)

    # Server Status
    $script:statusLabel = New-Object System.Windows.Forms.Label
    $script:statusLabel.Text = " STOPPED"
    $script:statusLabel.Location = New-Object System.Drawing.Point(15, 15)
    $script:statusLabel.Size = New-Object System.Drawing.Size(150, 25)
    $script:statusLabel.ForeColor = $colorDanger
    $script:statusLabel.Font = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)
    $statusPanel.Controls.Add($script:statusLabel)

    # Uptime
    $script:uptimeLabel = New-Object System.Windows.Forms.Label
    $script:uptimeLabel.Text = "Uptime: --"
    $script:uptimeLabel.Location = New-Object System.Drawing.Point(15, 45)
    $script:uptimeLabel.Size = New-Object System.Drawing.Size(200, 20)
    $script:uptimeLabel.ForeColor = $colorTextDim
    $statusPanel.Controls.Add($script:uptimeLabel)

    # CPU
    $script:cpuLabel = New-Object System.Windows.Forms.Label
    $script:cpuLabel.Text = "CPU: 0.0%"
    $script:cpuLabel.Location = New-Object System.Drawing.Point(220, 15)
    $script:cpuLabel.Size = New-Object System.Drawing.Size(120, 20)
    $script:cpuLabel.ForeColor = $colorTextDim
    $statusPanel.Controls.Add($script:cpuLabel)

    # RAM
    $script:ramLabel = New-Object System.Windows.Forms.Label
    $script:ramLabel.Text = "RAM: 0.0 MB"
    $script:ramLabel.Location = New-Object System.Drawing.Point(350, 15)
    $script:ramLabel.Size = New-Object System.Drawing.Size(120, 20)
    $script:ramLabel.ForeColor = $colorTextDim
    $statusPanel.Controls.Add($script:ramLabel)

    # Players
    $script:playerCountLabel = New-Object System.Windows.Forms.Label
    $script:playerCountLabel.Text = "Players: 0"
    $script:playerCountLabel.Location = New-Object System.Drawing.Point(480, 15)
    $script:playerCountLabel.Size = New-Object System.Drawing.Size(120, 20)
    $script:playerCountLabel.ForeColor = $colorTextDim
    $statusPanel.Controls.Add($script:playerCountLabel)

    $form.Controls.Add($statusPanel)

    # ====================
    # CONTROL BUTTONS
    # ====================

    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.BackColor = $colorBg
    $buttonPanel.Size = New-Object System.Drawing.Size(1100, 60)
    $buttonPanel.Location = New-Object System.Drawing.Point(0, 100)

    # START
    $btnStart = New-Object System.Windows.Forms.Button
    $btnStart.Text = "[START]"
    $btnStart.Location = New-Object System.Drawing.Point(15, 12)
    $btnStart.Size = New-Object System.Drawing.Size(100, 35)
    $btnStart.BackColor = $colorSuccess
    $btnStart.ForeColor = $colorButtonText
    $btnStart.FlatStyle = "Flat"
    $btnStart.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $btnStart.Add_Click({ Start-Server; Update-StatusDisplay })
    $buttonPanel.Controls.Add($btnStart)
    $toolTip.SetToolTip($btnStart, "Start the Palworld server")

    # STOP
    $btnStop = New-Object System.Windows.Forms.Button
    $btnStop.Text = "[STOP]"
    $btnStop.Location = New-Object System.Drawing.Point(120, 12)
    $btnStop.Size = New-Object System.Drawing.Size(100, 35)
    $btnStop.BackColor = $colorDanger
    $btnStop.ForeColor = $colorButtonText
    $btnStop.FlatStyle = "Flat"
    $btnStop.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $btnStop.Add_Click({
        Stop-Server | Out-Null
        Update-StatusDisplay
    })
    $buttonPanel.Controls.Add($btnStop)
    $toolTip.SetToolTip($btnStop, "Stop the server gracefully")

    # RESTART
    $btnRestart = New-Object System.Windows.Forms.Button
    $btnRestart.Text = "[RESTART]"
    $btnRestart.Location = New-Object System.Drawing.Point(225, 12)
    $btnRestart.Size = New-Object System.Drawing.Size(100, 35)
    $btnRestart.BackColor = $colorWarning
    $btnRestart.ForeColor = [System.Drawing.Color]::Black
    $btnRestart.FlatStyle = "Flat"
    $btnRestart.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $btnRestart.Add_Click({ Restart-Server; Update-StatusDisplay })
    $buttonPanel.Controls.Add($btnRestart)
    $toolTip.SetToolTip($btnRestart, "Restart the server")

    # FORCE KILL
    $btnForceKill = New-Object System.Windows.Forms.Button
    $btnForceKill.Text = "[FORCE KILL]"
    $btnForceKill.Location = New-Object System.Drawing.Point(330, 12)
    $btnForceKill.Size = New-Object System.Drawing.Size(110, 35)
    $btnForceKill.BackColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
    $btnForceKill.ForeColor = $colorButtonText
    $btnForceKill.FlatStyle = "Flat"
    $btnForceKill.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $btnForceKill.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Force kill the server IMMEDIATELY? This will terminate without warning and may cause data loss.",
            "Confirm Force Kill",
            "YesNo",
            "Warning"
        )
        if ($result -eq "Yes") {
            Force-Kill-Server | Out-Null
            Update-StatusDisplay
        }
    })
    $buttonPanel.Controls.Add($btnForceKill)
    $toolTip.SetToolTip($btnForceKill, "Force kill server (emergency only)")

    $form.Controls.Add($buttonPanel)

    # ====================
    # TAB CONTROL
    # ====================

    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Location = New-Object System.Drawing.Point(0, 160)
    $tabControl.Size = New-Object System.Drawing.Size(1100, 550)
    $tabControl.BackColor = $colorBg
    $tabControl.ForeColor = $colorText
        # Build tabs
    $tabServer = New-Object System.Windows.Forms.TabPage
    $tabServer.Text = "Server"
    $tabServer.BackColor = $colorPanelBg
    Build-ServerTab $tabServer $toolTip
    $tabControl.TabPages.Add($tabServer)

    $tabConfig = New-Object System.Windows.Forms.TabPage
    $tabConfig.Text = "Configuration"
    $tabConfig.BackColor = $colorPanelBg
    Build-ConfigTab $tabConfig $toolTip
    $tabControl.TabPages.Add($tabConfig)

    $tabBackups = New-Object System.Windows.Forms.TabPage
    $tabBackups.Text = "Backups"
    $tabBackups.BackColor = $colorPanelBg
    Build-BackupsTab $tabBackups $toolTip
    $tabControl.TabPages.Add($tabBackups)

    $tabPlayers = New-Object System.Windows.Forms.TabPage
    $tabPlayers.Text = "Players"
    $tabPlayers.BackColor = $colorPanelBg
    Build-PlayersTab $tabPlayers $toolTip
    $tabControl.TabPages.Add($tabPlayers)

    $tabMonitoring = New-Object System.Windows.Forms.TabPage
    $tabMonitoring.Text = "Monitoring"
    $tabMonitoring.BackColor = $colorPanelBg
    Build-MonitoringTab $tabMonitoring $toolTip
    $tabControl.TabPages.Add($tabMonitoring)

    $tabRCON = New-Object System.Windows.Forms.TabPage
    $tabRCON.Text = "RCON Console"
    $tabRCON.BackColor = $colorPanelBg
    Build-RCONTab $tabRCON $toolTip
    $tabControl.TabPages.Add($tabRCON)

    # Add tab control to form
    $form.Controls.Add($tabControl)

    # Form close event
    $form.Add_FormClosing({
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Save settings and close?",
            "Exit",
            "YesNo",
            "Question"
        )

        if ($result -eq "Yes") {
            Save-UISettings
            Cleanup-All
        } else {
            $_.Cancel = $true
        }
    })

    return $form
}


# ==========================================================================================
# TAB BUILDERS
# ==========================================================================================

# ===== SERVER TAB =====
function Build-ServerTab {
    param($tab, $toolTip)

    # Title
    $lblArgsTitle = New-Object System.Windows.Forms.Label
    $lblArgsTitle.Text = "Server Startup Arguments:"
    $lblArgsTitle.Location = New-Object System.Drawing.Point(10, 10)
    $lblArgsTitle.Size = New-Object System.Drawing.Size(400, 20)
    $lblArgsTitle.ForeColor = $colorText
    $lblArgsTitle.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($lblArgsTitle)

    # Scrollable panel for arguments
    $panelArgs = New-Object System.Windows.Forms.Panel
    $panelArgs.Location = New-Object System.Drawing.Point(10, 35)
    $panelArgs.Size = New-Object System.Drawing.Size(1070, 200)
    $panelArgs.BackColor = $colorPanelBg
    $panelArgs.BorderStyle = "FixedSingle"
    $panelArgs.AutoScroll = $true
    $tab.Controls.Add($panelArgs)

    # Store checkbox + textbox references
    $script:argumentCheckboxes = @{}
    $script:argumentTextboxes = @{}

    $yPos = 10
    foreach ($argDef in $script:startupArgsDefinitions) {

        # Checkbox
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = $argDef.Display
        $chk.Location = New-Object System.Drawing.Point(10, $yPos)
        $chk.Size = New-Object System.Drawing.Size(300, 20)
        $chk.ForeColor = $colorText
        $chk.BackColor = $colorPanelBg
        $panelArgs.Controls.Add($chk)
        $script:argumentCheckboxes[$argDef.Name] = $chk
        $toolTip.SetToolTip($chk, $argDef.Description)

        # Textbox for arguments with values
        if ($argDef.HasValue) {
            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Location = New-Object System.Drawing.Point(320, $yPos)
            $txt.Size = New-Object System.Drawing.Size(200, 20)
            $txt.BackColor = $colorTextboxBg
            $txt.ForeColor = $colorTextboxText
            $txt.Text = $argDef.DefaultValue
            $panelArgs.Controls.Add($txt)
            $script:argumentTextboxes[$argDef.Name] = $txt
            $toolTip.SetToolTip($txt, "Value for $($argDef.Argument)")
        }

        $yPos += 30
    }

    # Apply Arguments Button
    $btnApplyArgs = New-Object System.Windows.Forms.Button
    $btnApplyArgs.Text = "[APPLY ARGUMENTS]"
    $btnApplyArgs.Location = New-Object System.Drawing.Point(10, 245)
    $btnApplyArgs.Size = New-Object System.Drawing.Size(150, 35)
    $btnApplyArgs.BackColor = $colorSuccess
    $btnApplyArgs.ForeColor = $colorButtonText
    $btnApplyArgs.FlatStyle = "Flat"
    $btnApplyArgs.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)

    $btnApplyArgs.Add_Click({
        foreach ($argDef in $script:startupArgsDefinitions) {
            $chk = $script:argumentCheckboxes[$argDef.Name]

            # Check if property exists (works for both Hashtable and PSCustomObject)
            if ($null -eq $script:selectedArguments.$($argDef.Name)) {
                $script:selectedArguments[$argDef.Name] = @{}
            }

            $script:selectedArguments[$argDef.Name].selected = $chk.Checked
            $script:selectedArguments[$argDef.Name].argument = $argDef.Argument
            $script:selectedArguments[$argDef.Name].hasValue = $argDef.HasValue

            if ($argDef.HasValue -and $script:argumentTextboxes.ContainsKey($argDef.Name)) {
                $script:selectedArguments[$argDef.Name].value = $script:argumentTextboxes[$argDef.Name].Text
            }
        }

        Build-StartupArguments

        [System.Windows.Forms.MessageBox]::Show(
            "Arguments updated:`n`n$script:startupArguments",
            "Success",
            "OK",
            "Information"
        ) | Out-Null

        if ($script:currentArgsDisplay) {
            $script:currentArgsDisplay.Text = $script:startupArguments
        }
        
        # Save settings immediately so arguments persist
        Save-UISettings
    })

    $tab.Controls.Add($btnApplyArgs)
    $toolTip.SetToolTip($btnApplyArgs, "Apply selected startup arguments")

    # Current Arguments Display
    $lblCurrentArgs = New-Object System.Windows.Forms.Label
    $lblCurrentArgs.Text = "Current Arguments:"
    $lblCurrentArgs.Location = New-Object System.Drawing.Point(10, 290)
    $lblCurrentArgs.Size = New-Object System.Drawing.Size(200, 20)
    $lblCurrentArgs.ForeColor = $colorText
    $lblCurrentArgs.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($lblCurrentArgs)

    $txtCurrentArgs = New-Object System.Windows.Forms.TextBox
    $txtCurrentArgs.Location = New-Object System.Drawing.Point(10, 315)
    $txtCurrentArgs.Size = New-Object System.Drawing.Size(1070, 50)
    $txtCurrentArgs.Multiline = $true
    $txtCurrentArgs.ReadOnly = $true
    $txtCurrentArgs.BackColor = $colorTextboxBg
    $txtCurrentArgs.ForeColor = $colorTextboxText
    $txtCurrentArgs.Text = $script:startupArguments
    $tab.Controls.Add($txtCurrentArgs)
    $script:currentArgsDisplay = $txtCurrentArgs

    # Console Output
    $lblLogsTitle = New-Object System.Windows.Forms.Label
    $lblLogsTitle.Text = "Server Console Output:"
    $lblLogsTitle.Location = New-Object System.Drawing.Point(10, 375)
    $lblLogsTitle.Size = New-Object System.Drawing.Size(200, 20)
    $lblLogsTitle.ForeColor = $colorText
    $lblLogsTitle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($lblLogsTitle)

    $txtLogs = New-Object System.Windows.Forms.TextBox
    $txtLogs.Multiline = $true
    $txtLogs.ScrollBars = "Vertical"
    $txtLogs.Location = New-Object System.Drawing.Point(10, 400)
    $txtLogs.Size = New-Object System.Drawing.Size(1070, 60)
    $txtLogs.ReadOnly = $true
    $txtLogs.BackColor = $colorTextboxBg
    $txtLogs.ForeColor = $colorTextboxText
    $txtLogs.Font = New-Object System.Drawing.Font("Consolas", 8)
    $tab.Controls.Add($txtLogs)
    $toolTip.SetToolTip($txtLogs, "Live server console output")
    $script:serverLogsBox = $txtLogs

    # Clear Logs Button
    $btnClearLogs = New-Object System.Windows.Forms.Button
    $btnClearLogs.Text = "[CLEAR LOGS]"
    $btnClearLogs.Location = New-Object System.Drawing.Point(10, 470)
    $btnClearLogs.Size = New-Object System.Drawing.Size(100, 30)
    $btnClearLogs.BackColor = $colorButtonBg
    $btnClearLogs.ForeColor = $colorButtonText
    $btnClearLogs.FlatStyle = "Flat"
    $btnClearLogs.Add_Click({ $txtLogs.Clear() })
    $tab.Controls.Add($btnClearLogs)
    $toolTip.SetToolTip($btnClearLogs, "Clear log display")
}

# ===== CONFIG TAB =====
function Build-ConfigTab {
    param($tab, $toolTip)

    # Title
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Server Configuration - All Settings"
    $lblTitle.Location = New-Object System.Drawing.Point(10, 10)
    $lblTitle.Size = New-Object System.Drawing.Size(400, 20)
    $lblTitle.ForeColor = $colorText
    $lblTitle.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($lblTitle)

    # Search box
    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text = "Search:"
    $lblSearch.Location = New-Object System.Drawing.Point(10, 40)
    $lblSearch.Size = New-Object System.Drawing.Size(50, 20)
    $lblSearch.ForeColor = $colorText
    $tab.Controls.Add($lblSearch)

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(70, 40)
    $txtSearch.Size = New-Object System.Drawing.Size(300, 25)
    $txtSearch.BackColor = $colorTextboxBg
    $txtSearch.ForeColor = $colorTextboxText
    $tab.Controls.Add($txtSearch)

    # Config grid
    $gridConfig = New-Object System.Windows.Forms.DataGridView
    $gridConfig.Location = New-Object System.Drawing.Point(10, 75)
    $gridConfig.Size = New-Object System.Drawing.Size(1050, 380)
    $gridConfig.ReadOnly = $false
    $gridConfig.AllowUserToAddRows = $false
    $gridConfig.AllowUserToDeleteRows = $false
    $gridConfig.BackgroundColor = $colorTextboxBg
    $gridConfig.ForeColor = $colorTextboxText
    $gridConfig.GridColor = [System.Drawing.Color]::FromArgb(80,80,80)
    $gridConfig.ColumnHeadersDefaultCellStyle.BackColor = $colorPanelBg
    $gridConfig.ColumnHeadersDefaultCellStyle.ForeColor = $colorText
    $gridConfig.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $gridConfig.DefaultCellStyle.BackColor = $colorTextboxBg
    $gridConfig.DefaultCellStyle.ForeColor = $colorTextboxText
    $gridConfig.DefaultCellStyle.SelectionBackColor = $colorButtonBg
    $gridConfig.DefaultCellStyle.SelectionForeColor = $colorButtonText

    # Columns
    $gridConfig.ColumnCount = 3
    $gridConfig.Columns[0].Name = "Key"
    $gridConfig.Columns[0].Width = 300
    $gridConfig.Columns[0].ReadOnly = $true

    $gridConfig.Columns[1].Name = "Type"
    $gridConfig.Columns[1].Width = 80
    $gridConfig.Columns[1].ReadOnly = $true

    $gridConfig.Columns[2].Name = "Value"
    $gridConfig.Columns[2].Width = 650

    # Load config values
    $allKeys = Get-AllConfigKeys
    foreach ($key in $allKeys) {
        $value = Get-ConfigValue $key
        $type = Get-ConfigType $key
        $gridConfig.Rows.Add($key, $type, $value)
    }

    $tab.Controls.Add($gridConfig)
    $script:configGrid = $gridConfig
    $script:configSearchBox = $txtSearch

    # Search filter
    $txtSearch.Add_TextChanged({
        $search = $txtSearch.Text.ToLower()
        foreach ($row in $gridConfig.Rows) {
            $key = $row.Cells[0].Value
            $row.Visible = ($key -and $key.ToLower().Contains($search))
        }
    })

    # Save button
    $btnSaveConfig = New-Object System.Windows.Forms.Button
    $btnSaveConfig.Text = "[SAVE CONFIG]"
    $btnSaveConfig.Location = New-Object System.Drawing.Point(10, 465)
    $btnSaveConfig.Size = New-Object System.Drawing.Size(150, 35)
    $btnSaveConfig.BackColor = $colorSuccess
    $btnSaveConfig.ForeColor = $colorButtonText
    $btnSaveConfig.FlatStyle = "Flat"
    $btnSaveConfig.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)

    $btnSaveConfig.Add_Click({
        try {
            foreach ($row in $script:configGrid.Rows) {
                $key = $row.Cells[0].Value
                $value = $row.Cells[2].Value
                if ($key) {
                    Set-ConfigValue -key $key -value ($value.ToString())
                }
            }

            if (Save-Config) {
                # Reload REST API settings if they were changed
                try {
                    if (Get-Command Update-RestAPISettings -ErrorAction SilentlyContinue) {
                        Update-RestAPISettings
                        Write-Verbose "REST API settings reloaded"
                    }
                } catch {
                    # REST API module not loaded yet, that's okay
                }
                
                [System.Windows.Forms.MessageBox]::Show(
                    "Configuration saved successfully.",
                    "Config Saved",
                    "OK",
                    "Information"
                ) | Out-Null
            } else {
                [System.Windows.Forms.MessageBox]::Show(
                    "Failed to save configuration.",
                    "Save Error",
                    "OK",
                    "Error"
                ) | Out-Null
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Unexpected error while saving configuration:`r`n$($_.Exception.Message)",
                "Save Error",
                "OK",
                "Error"
            ) | Out-Null
        }
    })

    $tab.Controls.Add($btnSaveConfig)
    $toolTip.SetToolTip($btnSaveConfig, "Save all configuration changes to PalWorldSettings.ini")
}

# ===== BACKUPS TAB =====
function Build-BackupsTab {
    param($tab, $toolTip)

    # Title
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "World Backups"
    $lblTitle.Location = New-Object System.Drawing.Point(10, 10)
    $lblTitle.Size = New-Object System.Drawing.Size(300, 20)
    $lblTitle.ForeColor = $colorText
    $lblTitle.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($lblTitle)

    # Backup list grid
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(10, 40)
    $grid.Size = New-Object System.Drawing.Size(1050, 350)
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.SelectionMode = "FullRowSelect"
    $grid.MultiSelect = $false
    $grid.BackgroundColor = $colorTextboxBg
    $grid.ForeColor = $colorTextboxText
    $grid.GridColor = [System.Drawing.Color]::FromArgb(80,80,80)
    $grid.ColumnHeadersDefaultCellStyle.BackColor = $colorPanelBg
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = $colorText
    $grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)

    # --- DARK MODE STYLING FOR DATAGRIDVIEW ---

    $grid.EnableHeadersVisualStyles = $false

    # Default cell style
    $cellStyle = New-Object System.Windows.Forms.DataGridViewCellStyle
    $cellStyle.BackColor = $colorTextboxBg
    $cellStyle.ForeColor = $colorTextboxText
    $cellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(70,70,70)
    $cellStyle.SelectionForeColor = $colorText
    $grid.DefaultCellStyle = $cellStyle

    # Row header style
    $rowHeaderStyle = New-Object System.Windows.Forms.DataGridViewCellStyle
    $rowHeaderStyle.BackColor = $colorPanelBg
    $rowHeaderStyle.ForeColor = $colorText
    $rowHeaderStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(70,70,70)
    $rowHeaderStyle.SelectionForeColor = $colorText
    $grid.RowHeadersDefaultCellStyle = $rowHeaderStyle

    # Column header style
    $headerStyle = New-Object System.Windows.Forms.DataGridViewCellStyle
    $headerStyle.BackColor = $colorPanelBg
    $headerStyle.ForeColor = $colorText
    $headerStyle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $grid.ColumnHeadersDefaultCellStyle = $headerStyle

    # Row template styling
    $grid.RowTemplate.DefaultCellStyle.BackColor = $colorTextboxBg
    $grid.RowTemplate.DefaultCellStyle.ForeColor = $colorTextboxText
    $grid.RowTemplate.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(70,70,70)
    $grid.RowTemplate.DefaultCellStyle.SelectionForeColor = $colorText


    $grid.Columns.Add("Name","Backup Name")
    $grid.Columns.Add("Created","Created")
    $grid.Columns.Add("Size","Size (MB)")
    $grid.Columns.Add("Description","Description")

    $grid.Columns[0].Width = 300
    $grid.Columns[1].Width = 200
    $grid.Columns[2].Width = 100
    $grid.Columns[3].Width = 400

    $tab.Controls.Add($grid)
    $script:backupGrid = $grid

    # Refresh button
    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "[REFRESH]"
    $btnRefresh.Location = New-Object System.Drawing.Point(10, 400)
    $btnRefresh.Size = New-Object System.Drawing.Size(120, 35)
    $btnRefresh.BackColor = $colorButtonBg
    $btnRefresh.ForeColor = $colorButtonText
    $btnRefresh.FlatStyle = "Flat"
    $btnRefresh.Add_Click({ Refresh-BackupList })
    $tab.Controls.Add($btnRefresh)

    # Create backup button
    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.Text = "[CREATE BACKUP]"
    $btnBackup.Location = New-Object System.Drawing.Point(140, 400)
    $btnBackup.Size = New-Object System.Drawing.Size(150, 35)
    $btnBackup.BackColor = $colorSuccess
    $btnBackup.ForeColor = $colorButtonText
    $btnBackup.FlatStyle = "Flat"
    $btnBackup.Add_Click({
        $desc = [Microsoft.VisualBasic.Interaction]::InputBox(
            "Enter backup description (optional):",
            "Backup Description",
            ""
        )
        Perform-ManualBackup $desc | Out-Null
        Refresh-BackupList
    })
    $tab.Controls.Add($btnBackup)

    # Restore button
    $btnRestore = New-Object System.Windows.Forms.Button
    $btnRestore.Text = "[RESTORE]"
    $btnRestore.Location = New-Object System.Drawing.Point(300, 400)
    $btnRestore.Size = New-Object System.Drawing.Size(120, 35)
    $btnRestore.BackColor = $colorWarning
    $btnRestore.ForeColor = [System.Drawing.Color]::Black
    $btnRestore.FlatStyle = "Flat"
    $btnRestore.Add_Click({
        if ($script:backupGrid.SelectedRows.Count -eq 0) { return }
        $name = $script:backupGrid.SelectedRows[0].Cells[0].Value

        $result = [System.Windows.Forms.MessageBox]::Show(
            "Restore backup '$name'? Server must be stopped.",
            "Confirm Restore",
            "YesNo",
            "Warning"
        )

        if ($result -eq "Yes") {
            Restore-Backup $name | Out-Null
            Refresh-BackupList
        }
    })
    $tab.Controls.Add($btnRestore)

    # Delete button
    $btnDelete = New-Object System.Windows.Forms.Button
    $btnDelete.Text = "[DELETE]"
    $btnDelete.Location = New-Object System.Drawing.Point(430, 400)
    $btnDelete.Size = New-Object System.Drawing.Size(120, 35)
    $btnDelete.BackColor = $colorDanger
    $btnDelete.ForeColor = $colorButtonText
    $btnDelete.FlatStyle = "Flat"
    $btnDelete.Add_Click({
        if ($script:backupGrid.SelectedRows.Count -eq 0) { return }
        $name = $script:backupGrid.SelectedRows[0].Cells[0].Value

        $result = [System.Windows.Forms.MessageBox]::Show(
            "Delete backup '$name'?",
            "Confirm Delete",
            "YesNo",
            "Warning"
        )

        if ($result -eq "Yes") {
            Delete-Backup $name | Out-Null
            Refresh-BackupList
        }
    })
    $tab.Controls.Add($btnDelete)

    # Load initial list
    Refresh-BackupList
}

# Helper: Refresh backup list
function Refresh-BackupList {
    try {
        $script:backupGrid.Rows.Clear()
        $list = Get-BackupList
        foreach ($b in $list) {
            $script:backupGrid.Rows.Add($b.Name, $b.Created, $b.SizeMB, $b.Description)
        }
    } catch {
        # If something fails, clear grid safely
        $script:backupGrid.Rows.Clear()
    }
}

# ===== PLAYERS TAB =====
function Build-PlayersTab {
    param($tab, $toolTip)

    # Title
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Online Players"
    $lblTitle.Location = New-Object System.Drawing.Point(10, 10)
    $lblTitle.Size = New-Object System.Drawing.Size(300, 20)
    $lblTitle.ForeColor = $colorText
    $lblTitle.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($lblTitle)

    # Player list grid
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(10, 40)
    $grid.Size = New-Object System.Drawing.Size(1050, 350)
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.SelectionMode = "FullRowSelect"
    $grid.MultiSelect = $false
    $grid.BackgroundColor = $colorTextboxBg
    $grid.ForeColor = $colorTextboxText
    $grid.GridColor = [System.Drawing.Color]::FromArgb(80,80,80)
    $grid.ColumnHeadersDefaultCellStyle.BackColor = $colorPanelBg
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = $colorText
    $grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)

    $grid.Columns.Add("Name","Player Name")
    $grid.Columns.Add("PlayerUID","Player UID")
    $grid.Columns.Add("Level","Level") 

    $grid.Columns[0].Width = 300
    $grid.Columns[1].Width = 350
    $grid.Columns[2].Width = 350

    $tab.Controls.Add($grid)
    $script:playerGrid = $grid

    # Refresh button
    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "[REFRESH]"
    $btnRefresh.Location = New-Object System.Drawing.Point(10, 400)
    $btnRefresh.Size = New-Object System.Drawing.Size(120, 35)
    $btnRefresh.BackColor = $colorButtonBg
    $btnRefresh.ForeColor = $colorButtonText
    $btnRefresh.FlatStyle = "Flat"
    $btnRefresh.Add_Click({ Refresh-PlayerList })
    $tab.Controls.Add($btnRefresh)

    # Kick button
    $btnKick = New-Object System.Windows.Forms.Button
    $btnKick.Text = "[KICK]"
    $btnKick.Location = New-Object System.Drawing.Point(140, 400)
    $btnKick.Size = New-Object System.Drawing.Size(120, 35)
    $btnKick.BackColor = $colorWarning
    $btnKick.ForeColor = [System.Drawing.Color]::Black
    $btnKick.FlatStyle = "Flat"
    $btnKick.Add_Click({
        if ($script:playerGrid.SelectedRows.Count -eq 0) { return }
        $uid = $script:playerGrid.SelectedRows[0].Cells[1].Value
        Kick-Player $uid | Out-Null
        Refresh-PlayerList
    })
    $tab.Controls.Add($btnKick)

    # Ban button
    $btnBan = New-Object System.Windows.Forms.Button
    $btnBan.Text = "[BAN]"
    $btnBan.Location = New-Object System.Drawing.Point(270, 400)
    $btnBan.Size = New-Object System.Drawing.Size(120, 35)
    $btnBan.BackColor = $colorDanger
    $btnBan.ForeColor = $colorButtonText
    $btnBan.FlatStyle = "Flat"
    $btnBan.Add_Click({
        if ($script:playerGrid.SelectedRows.Count -eq 0) { return }
        $uid = $script:playerGrid.SelectedRows[0].Cells[1].Value
        Ban-Player $uid | Out-Null
        Refresh-PlayerList
    })
    $tab.Controls.Add($btnBan)

    # Unban button
    $btnUnban = New-Object System.Windows.Forms.Button
    $btnUnban.Text = "[UNBAN]"
    $btnUnban.Location = New-Object System.Drawing.Point(400, 400)
    $btnUnban.Size = New-Object System.Drawing.Size(120, 35)
    $btnUnban.BackColor = $colorSuccess
    $btnUnban.ForeColor = $colorButtonText
    $btnUnban.FlatStyle = "Flat"
    $btnUnban.Add_Click({
        $uid = [Microsoft.VisualBasic.Interaction]::InputBox(
            "Enter Player UID to unban:",
            "Unban Player",
            ""
        )
        if ($uid -and $uid.Trim() -ne "") {
            Unban-Player $uid | Out-Null
        }
    })
    $tab.Controls.Add($btnUnban)

    # Copy UID button
    $btnCopyUID = New-Object System.Windows.Forms.Button
    $btnCopyUID.Text = "[COPY UID]"
    $btnCopyUID.Location = New-Object System.Drawing.Point(530, 400)
    $btnCopyUID.Size = New-Object System.Drawing.Size(120, 35)
    $btnCopyUID.BackColor = $colorButtonBg
    $btnCopyUID.ForeColor = $colorButtonText
    $btnCopyUID.FlatStyle = "Flat"
    $btnCopyUID.Add_Click({
        if ($script:playerGrid.SelectedRows.Count -eq 0) { return }
        $uid = $script:playerGrid.SelectedRows[0].Cells[1].Value
        [System.Windows.Forms.Clipboard]::SetText($uid)
    })
    $tab.Controls.Add($btnCopyUID)

    # Copy Character UID button
    $btnCopyChar = New-Object System.Windows.Forms.Button
    $btnCopyChar.Text = "[COPY CHAR UID]"
    $btnCopyChar.Location = New-Object System.Drawing.Point(660, 400)
    $btnCopyChar.Size = New-Object System.Drawing.Size(150, 35)
    $btnCopyChar.BackColor = $colorButtonBg
    $btnCopyChar.ForeColor = $colorButtonText
    $btnCopyChar.FlatStyle = "Flat"
    $btnCopyChar.Add_Click({
        if ($script:playerGrid.SelectedRows.Count -eq 0) { return }
        $char = $script:playerGrid.SelectedRows[0].Cells[2].Value
        [System.Windows.Forms.Clipboard]::SetText($char)
    })
    $tab.Controls.Add($btnCopyChar)

    # Load initial list
    Refresh-PlayerList
}

# Helper: Refresh player list
function Refresh-PlayerList {
    try {
        $script:playerGrid.Rows.Clear()
        if (-not $script:serverRunning) { return }
        $players = Get-PlayersREST
        foreach ($p in $players) {
            $script:playerGrid.Rows.Add($p.Name, $p.PlayerUID, $p.Level, $p.Experience, $p.CharacterUID)
        }
    } catch {
        # If RCON fails, clear grid safely
        $script:playerGrid.Rows.Clear()
    }
}

# ===== MONITORING TAB =====
function Build-MonitoringTab {
    param($tab, $toolTip)

    # === MAIN PANEL (fills tab) ============================================
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = "Fill"
    $mainPanel.AutoScroll = $false
    $mainPanel.BackColor = $colorPanelBg
    $tab.Controls.Add($mainPanel)

    # === TITLE =============================================================
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Server Monitoring (REST API)"
    $lblTitle.AutoSize = $true
    $lblTitle.ForeColor = $colorText
    $lblTitle.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
    $lblTitle.Location = New-Object System.Drawing.Point(10, 10)
    $mainPanel.Controls.Add($lblTitle)

    # === LABEL STACK =======================================================
    $labelPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $labelPanel.Location = New-Object System.Drawing.Point(10, 40)
    $labelPanel.Size = New-Object System.Drawing.Size(350, 150)
    $labelPanel.FlowDirection = "TopDown"
    $labelPanel.WrapContents = $false
    $labelPanel.AutoSize = $true
    $labelPanel.BackColor = $colorPanelBg
    $mainPanel.Controls.Add($labelPanel)

# Create label objects
$script:monitoringLabels = @{
    CpuAvg  = New-Object System.Windows.Forms.Label
    CpuPeak = New-Object System.Windows.Forms.Label
    RamAvg  = New-Object System.Windows.Forms.Label
    RamPeak = New-Object System.Windows.Forms.Label
    Players = New-Object System.Windows.Forms.Label
    FPS     = New-Object System.Windows.Forms.Label
    Uptime  = New-Object System.Windows.Forms.Label
    Health  = New-Object System.Windows.Forms.Label
}

foreach ($lbl in $script:monitoringLabels.Values) {
    $lbl.AutoSize = $true
    $lbl.ForeColor = $colorText
    $lbl.Font = New-Object System.Drawing.Font("Arial", 10)
    $labelPanel.Controls.Add($lbl)
}

# Default text
$script:monitoringLabels.CpuAvg.Text  = "CPU: --"
$script:monitoringLabels.CpuPeak.Text = "Threads/Handles: --"
$script:monitoringLabels.RamAvg.Text  = "RAM: --"
$script:monitoringLabels.RamPeak.Text = "Peak RAM: --"
$script:monitoringLabels.Players.Text = "Players: --"
$script:monitoringLabels.FPS.Text     = "FPS: --"
$script:monitoringLabels.Uptime.Text  = "Uptime: --"

$script:monitoringLabels.Health.Font = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)
$script:monitoringLabels.Health.Text = "Health: --"

    # === CHART GRID (2×2) ==================================================
    Add-Type -AssemblyName System.Windows.Forms.DataVisualization

    function New-LineChart {
        param($title, $seriesName, $color)

        $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
        $chart.Width = 400
        $chart.Height = 150
        $chart.BackColor = $colorPanelBg

        $area = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
        $area.BackColor = $colorPanelBg
        $area.AxisX.MajorGrid.Enabled = $false
        $area.AxisY.MajorGrid.LineColor = [System.Drawing.Color]::FromArgb(60,60,60)
        $area.AxisX.LabelStyle.ForeColor = $colorTextDim
        $area.AxisY.LabelStyle.ForeColor = $colorTextDim
        $area.AxisX.LineColor = $colorTextDim
        $area.AxisY.LineColor = $colorTextDim
        $chart.ChartAreas.Add($area)

        $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series
        $series.ChartType = "Line"
        $series.Color = $color
        $series.BorderWidth = 2
        $series.Name = $seriesName
        $chart.Series.Add($series)

        $chart.Titles.Add($title) | Out-Null
        $chart.Titles[0].ForeColor = $colorText
        $chart.Titles[0].Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)

        return $chart
    }

    # Chart grid panel
    $chartGrid = New-Object System.Windows.Forms.TableLayoutPanel
    $chartGrid.Location = New-Object System.Drawing.Point(10, 200)
    $chartGrid.Size = New-Object System.Drawing.Size(820, 320)
    $chartGrid.ColumnCount = 2
    $chartGrid.RowCount = 2
    $chartGrid.BackColor = $colorPanelBg
    $chartGrid.CellBorderStyle = "None"
    $chartGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 410)))
    $chartGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 410)))
    $chartGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 160)))
    $chartGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 160)))
    $mainPanel.Controls.Add($chartGrid)

    # Create charts
    $script:cpuChart    = New-LineChart "CPU (%)"        "CPU"     $colorWarning
    $script:ramChart    = New-LineChart "RAM (MB)"       "RAM"     $colorSuccess
    $script:playerChart = New-LineChart "Players"        "Players" $colorButtonBg
    $script:fpsChart    = New-LineChart "FPS"            "FPS"     $colorDanger

    # Add charts to grid
    $chartGrid.Controls.Add($script:cpuChart,    0, 0)
    $chartGrid.Controls.Add($script:ramChart,    1, 0)
    $chartGrid.Controls.Add($script:playerChart, 0, 1)
    $chartGrid.Controls.Add($script:fpsChart,    1, 1)

    # Refresh button
    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "[REFRESH NOW]"
    $btnRefresh.Location = New-Object System.Drawing.Point(10, 540)
    $btnRefresh.Size = New-Object System.Drawing.Size(150, 35)
    $btnRefresh.BackColor = $colorButtonBg
    $btnRefresh.ForeColor = $colorButtonText
    $btnRefresh.FlatStyle = "Flat"
    $btnRefresh.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $btnRefresh.Add_Click({ Update-MetricsREST })
    $mainPanel.Controls.Add($btnRefresh)
}



# ===== RCON TAB =====
function Build-RCONTab {
    param($tab, $toolTip)

    # Title
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "REST API Console"
    $lblTitle.Location = New-Object System.Drawing.Point(10, 10)
    $lblTitle.Size = New-Object System.Drawing.Size(300, 20)
    $lblTitle.ForeColor = $colorText
    $lblTitle.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($lblTitle)

    # Quick Command Buttons (Row 1)
    $btnInfoPanel = New-Object System.Windows.Forms.Panel
    $btnInfoPanel.BackColor = $colorPanelBg
    $btnInfoPanel.Size = New-Object System.Drawing.Size(1050, 35)
    $btnInfoPanel.Location = New-Object System.Drawing.Point(10, 35)
    $tab.Controls.Add($btnInfoPanel)

    $quickButtons = @(
        @{ Text="[GET INFO]"; Cmd="info"; Method="GET"; Tooltip="Get server info" },
        @{ Text="[GET PLAYERS]"; Cmd="players"; Method="GET"; Tooltip="Get player list" },
        @{ Text="[GET METRICS]"; Cmd="metrics"; Method="GET"; Tooltip="Get server metrics" },
        @{ Text="[SAVE WORLD]"; Cmd="save"; Method="POST"; Tooltip="Save the world" },
        @{ Text="[GET SETTINGS]"; Cmd="settings"; Method="GET"; Tooltip="Get server settings" }
    )

    $xPos = 5
    foreach ($btn in $quickButtons) {
        $btnQuick = New-Object System.Windows.Forms.Button
        $btnQuick.Text = $btn.Text
        $btnQuick.Location = New-Object System.Drawing.Point($xPos, 5)
        $btnQuick.Size = New-Object System.Drawing.Size(200, 25)
        $btnQuick.BackColor = $colorButtonBg
        $btnQuick.ForeColor = $colorButtonText
        $btnQuick.FlatStyle = "Flat"
        $btnQuick.Font = New-Object System.Drawing.Font("Arial", 8)
        $btnQuick.Tag = @{ Endpoint = $btn.Cmd; Method = $btn.Method }
        
        $btnQuick.Add_Click({
            $endpoint = $this.Tag.Endpoint
            $method = $this.Tag.Method
            $script:rconOutputBox.AppendText("> $method $endpoint`r`n")
            try {
                $response = Invoke-RestAPIRequest -Endpoint $endpoint -Method $method
                if ($null -ne $response) {
                    $json = $response | ConvertTo-Json -Depth 10
                    $script:rconOutputBox.AppendText("$json`r`n")
                } else {
                    $script:rconOutputBox.AppendText("[API] Command executed successfully`r`n")
                }
            } catch {
                $script:rconOutputBox.AppendText("[API ERROR] $($_.Exception.Message)`r`n")
            }
            $script:rconOutputBox.SelectionStart = $script:rconOutputBox.Text.Length
            $script:rconOutputBox.ScrollToCaret()
        })
        
        $btnInfoPanel.Controls.Add($btnQuick)
        $toolTip.SetToolTip($btnQuick, $btn.Tooltip)
        $xPos += 205
    }

    # Quick Command Buttons (Row 2)
    $btnActionPanel = New-Object System.Windows.Forms.Panel
    $btnActionPanel.BackColor = $colorPanelBg
    $btnActionPanel.Size = New-Object System.Drawing.Size(1050, 35)
    $btnActionPanel.Location = New-Object System.Drawing.Point(10, 75)
    $tab.Controls.Add($btnActionPanel)

    $actionButtons = @(
        @{ Text="[ANNOUNCE]"; Cmd="announce"; Color=$colorWarning; TextColor=[System.Drawing.Color]::Black; Tooltip="Broadcast message to all players" },
        @{ Text="[KICK PLAYER]"; Cmd="kick"; Color=$colorWarning; TextColor=[System.Drawing.Color]::Black; Tooltip="Kick a player" },
        @{ Text="[BAN PLAYER]"; Cmd="ban"; Color=$colorDanger; TextColor=$colorButtonText; Tooltip="Ban a player" },
        @{ Text="[UNBAN PLAYER]"; Cmd="unban"; Color=$colorSuccess; TextColor=$colorButtonText; Tooltip="Unban a player" },
        @{ Text="[SHUTDOWN]"; Cmd="shutdown"; Color=$colorDanger; TextColor=$colorButtonText; Tooltip="Graceful shutdown" }
    )

    $xPos = 5
    foreach ($btn in $actionButtons) {
        $btnAction = New-Object System.Windows.Forms.Button
        $btnAction.Text = $btn.Text
        $btnAction.Location = New-Object System.Drawing.Point($xPos, 5)
        $btnAction.Size = New-Object System.Drawing.Size(200, 25)
        $btnAction.BackColor = $btn.Color
        $btnAction.ForeColor = $btn.TextColor
        $btnAction.FlatStyle = "Flat"
        $btnAction.Font = New-Object System.Drawing.Font("Arial", 8)
        $btnAction.Tag = $btn.Cmd
        
        $btnAction.Add_Click({
            $endpoint = $this.Tag
            
            # Get appropriate input based on endpoint
            $input = ""
            switch ($endpoint) {
                "announce" {
                    $input = [Microsoft.VisualBasic.Interaction]::InputBox("Enter message:", "Announce", "")
                    if ([string]::IsNullOrWhiteSpace($input)) { return }
                }
                "kick" {
                    $input = [Microsoft.VisualBasic.Interaction]::InputBox("Enter Player UID to kick:", "Kick Player", "")
                    if ([string]::IsNullOrWhiteSpace($input)) { return }
                }
                "ban" {
                    $input = [Microsoft.VisualBasic.Interaction]::InputBox("Enter Player UID to ban:", "Ban Player", "")
                    if ([string]::IsNullOrWhiteSpace($input)) { return }
                }
                "unban" {
                    $input = [Microsoft.VisualBasic.Interaction]::InputBox("Enter Player UID to unban:", "Unban Player", "")
                    if ([string]::IsNullOrWhiteSpace($input)) { return }
                }
                "shutdown" {
                    $confirm = [System.Windows.Forms.MessageBox]::Show(
                        "Shutdown the server?",
                        "Confirm",
                        "YesNo",
                        "Warning"
                    )
                    if ($confirm -ne "Yes") { return }
                }
            }
            
            $script:rconOutputBox.AppendText("> POST $endpoint`r`n")
            try {
                $body = @{}
                switch ($endpoint) {
                    "announce" { $body = @{ message = $input } }
                    "kick" { $body = @{ userid = $input; message = "You have been kicked" } }
                    "ban" { $body = @{ userid = $input; message = "You have been banned" } }
                    "unban" { $body = @{ userid = $input } }
                    "shutdown" { $body = @{ waittime = 30; message = "Server shutting down" } }
                }
                
                $response = Invoke-RestAPIRequest -Endpoint $endpoint -Method "POST" -Body $body
                if ($null -ne $response) {
                    $json = $response | ConvertTo-Json
                    $script:rconOutputBox.AppendText("$json`r`n")
                } else {
                    $script:rconOutputBox.AppendText("[API] Command executed`r`n")
                }
            } catch {
                $script:rconOutputBox.AppendText("[API ERROR] $($_.Exception.Message)`r`n")
            }
            $script:rconOutputBox.SelectionStart = $script:rconOutputBox.Text.Length
            $script:rconOutputBox.ScrollToCaret()
        })
        
        $btnActionPanel.Controls.Add($btnAction)
        $toolTip.SetToolTip($btnAction, $btn.Tooltip)
        $xPos += 205
    }

    # Output box
    $txtOutput = New-Object System.Windows.Forms.TextBox
    $txtOutput.Multiline = $true
    $txtOutput.ScrollBars = "Vertical"
    $txtOutput.Location = New-Object System.Drawing.Point(10, 120)
    $txtOutput.Size = New-Object System.Drawing.Size(1050, 300)
    $txtOutput.BackColor = $colorTextboxBg
    $txtOutput.ForeColor = $colorTextboxText
    $txtOutput.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txtOutput.ReadOnly = $true
    $tab.Controls.Add($txtOutput)
    $script:rconOutputBox = $txtOutput

    # Command input
    $txtCommand = New-Object System.Windows.Forms.TextBox
    $txtCommand.Location = New-Object System.Drawing.Point(10, 430)
    $txtCommand.Size = New-Object System.Drawing.Size(900, 30)
    $txtCommand.BackColor = $colorTextboxBg
    $txtCommand.ForeColor = $colorTextboxText
    $txtCommand.Font = New-Object System.Drawing.Font("Consolas", 10)
    $tab.Controls.Add($txtCommand)

    # Command history
    $script:rconHistory = @()
    $script:rconHistoryIndex = -1

    # History navigation
    $txtCommand.Add_KeyDown({
        param($sender, $e)

        if ($e.KeyCode -eq "Up") {
            if ($script:rconHistory.Count -gt 0) {
                $script:rconHistoryIndex = [Math]::Max(0, $script:rconHistoryIndex - 1)
                $txtCommand.Text = $script:rconHistory[$script:rconHistoryIndex]
                $txtCommand.SelectionStart = $txtCommand.Text.Length
            }
            $e.Handled = $true
        }

        if ($e.KeyCode -eq "Down") {
            if ($script:rconHistory.Count -gt 0) {
                $script:rconHistoryIndex = [Math]::Min($script:rconHistory.Count, $script:rconHistoryIndex + 1)
                if ($script:rconHistoryIndex -lt $script:rconHistory.Count) {
                    $txtCommand.Text = $script:rconHistory[$script:rconHistoryIndex]
                } else {
                    $txtCommand.Text = ""
                }
                $txtCommand.SelectionStart = $txtCommand.Text.Length
            }
            $e.Handled = $true
        }
    })

    # Send button
    $btnSend = New-Object System.Windows.Forms.Button
    $btnSend.Text = "[GET]"
    $btnSend.Location = New-Object System.Drawing.Point(920, 430)
    $btnSend.Size = New-Object System.Drawing.Size(65, 30)
    $btnSend.BackColor = $colorButtonBg
    $btnSend.ForeColor = $colorButtonText
    $btnSend.FlatStyle = "Flat"
    $btnSend.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($btnSend)

    # POST button
    $btnPost = New-Object System.Windows.Forms.Button
    $btnPost.Text = "[POST]"
    $btnPost.Location = New-Object System.Drawing.Point(990, 430)
    $btnPost.Size = New-Object System.Drawing.Size(70, 30)
    $btnPost.BackColor = $colorWarning
    $btnPost.ForeColor = [System.Drawing.Color]::Black
    $btnPost.FlatStyle = "Flat"
    $btnPost.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($btnPost)

    # GET handler
    $getHandler = {
        $endpoint = $txtCommand.Text.Trim()
        if ($endpoint -eq "") { return }

        $script:rconHistory += $endpoint
        $script:rconHistoryIndex = $script:rconHistory.Count

        $script:rconOutputBox.AppendText("> GET $endpoint`r`n")

        try {
            $response = Invoke-RestAPIRequest -Endpoint $endpoint -Method "GET"
            if ($null -ne $response) {
                $json = $response | ConvertTo-Json -Depth 10
                $script:rconOutputBox.AppendText("$json`r`n")
            } else {
                $script:rconOutputBox.AppendText("[API ERROR] No response`r`n")
            }
        } catch {
            $script:rconOutputBox.AppendText("[API ERROR] $($_.Exception.Message)`r`n")
        }

        $script:rconOutputBox.SelectionStart = $script:rconOutputBox.Text.Length
        $script:rconOutputBox.ScrollToCaret()
        $txtCommand.Text = ""
    }

    # POST handler
    $postHandler = {
        $input = $txtCommand.Text.Trim()
        if ($input -eq "") { return }

        $script:rconHistory += $input
        $script:rconHistoryIndex = $script:rconHistory.Count

        # Try to parse as endpoint or JSON
        $parts = $input -split '\s+', 2
        $endpoint = $parts[0]
        $bodyText = if ($parts.Count -gt 1) { $parts[1] } else { "{}" }

        $script:rconOutputBox.AppendText("> POST $endpoint`r`n")

        try {
            $body = $null
            if ($bodyText -ne "{}") {
                $body = $bodyText | ConvertFrom-Json
                # Convert to hashtable
                $bodyHash = @{}
                $body.PSObject.Properties | ForEach-Object { $bodyHash[$_.Name] = $_.Value }
                $body = $bodyHash
            } else {
                $body = @{}
            }

            $response = Invoke-RestAPIRequest -Endpoint $endpoint -Method "POST" -Body $body
            if ($null -ne $response) {
                $json = $response | ConvertTo-Json -Depth 10
                $script:rconOutputBox.AppendText("$json`r`n")
            } else {
                $script:rconOutputBox.AppendText("[API] Command executed`r`n")
            }
        } catch {
            $script:rconOutputBox.AppendText("[API ERROR] $($_.Exception.Message)`r`n")
        }

        $script:rconOutputBox.SelectionStart = $script:rconOutputBox.Text.Length
        $script:rconOutputBox.ScrollToCaret()
        $txtCommand.Text = ""
    }

    # Bind buttons
    $btnSend.Add_Click($getHandler)
    $btnPost.Add_Click($postHandler)

    # Bind Enter key to GET
    $txtCommand.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq "Enter") {
            $e.SuppressKeyPress = $true
            & $getHandler
        }
    })

    # Info label
    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "Use quick buttons above or enter endpoint/command manually. Press Enter for GET, click [POST] for POST requests with JSON body."
    $lblInfo.Location = New-Object System.Drawing.Point(10, 470)
    $lblInfo.Size = New-Object System.Drawing.Size(1050, 40)
    $lblInfo.ForeColor = $colorTextDim
    $lblInfo.Font = New-Object System.Drawing.Font("Arial", 8)
    $lblInfo.AutoSize = $false
    $tab.Controls.Add($lblInfo)
}

# ==========================================================================================
# UI SETTINGS (SAVE / LOAD)
# ==========================================================================================

function Save-UISettings {
    try {
        $settings = @{
            Window = @{
                Width  = $script:form.Width
                Height = $script:form.Height
                X      = $script:form.Location.X
                Y      = $script:form.Location.Y
            }
            SelectedTab = $script:form.Controls[0].SelectedIndex

            StartupArguments = $script:selectedArguments

            RCON = @{
                Host     = $script:rconHost
                Port     = $script:rconPort
                Password = $script:rconPassword
            }

            Backups = @{
                AutoBackupInterval = $script:autoBackupInterval
            }
        }

        $json = $settings | ConvertTo-Json -Depth 10
        Set-Content -Path $script:settingsPath -Value $json -Encoding UTF8 -Force

    } catch {
        Write-Warning "Failed to save UI settings: $_"
    }
}

function Load-UISettings {

    # CRITICAL FIX #1: Initialize selectedArguments IMMEDIATELY as empty hashtable
    if ($null -eq $script:selectedArguments) {
        $script:selectedArguments = @{}
    }

    if (-not (Test-Path $script:settingsPath)) {
        Write-Verbose "No UI settings file found - using defaults."
        return
    }

    try {
        $json = Get-Content $script:settingsPath -Raw -Encoding UTF8 -ErrorAction Stop
        
        # Validate JSON is not empty
        if ([string]::IsNullOrWhiteSpace($json)) {
            Write-Verbose "Settings file is empty - using defaults."
            return
        }

        $settings = $json | ConvertFrom-Json -ErrorAction Stop

        # Window size + position - ONLY if form is already initialized
        if ($null -ne $settings.Window -and $null -ne $script:form) {
            if ($null -ne $script:form.Width) {
                $script:form.Width  = $settings.Window.Width
                $script:form.Height = $settings.Window.Height

                if ($settings.Window.X -ge 0 -and $settings.Window.Y -ge 0) {
                    $script:form.StartPosition = "Manual"
                    $script:form.Location = New-Object System.Drawing.Point(
                        $settings.Window.X,
                        $settings.Window.Y
                    )
                }
            }
        }

        # Selected tab - ONLY if form is initialized
        if ($null -ne $settings.SelectedTab -and $settings.SelectedTab -ge 0 -and $null -ne $script:form -and $script:form.Controls.Count -gt 0) {
            try {
                $script:form.Controls[0].SelectedIndex = $settings.SelectedTab
            } catch {
                # Silently ignore if tab control doesn't exist yet
            }
        }

        # CRITICAL FIX #2 & #3: Startup arguments with proper PSCustomObject conversion
        if ($null -ne $settings.StartupArguments) {
            try {
                # Clear and rebuild as hashtable
                $script:selectedArguments = @{}
                
                # ConvertFrom-Json creates PSCustomObject, we need to convert to Hashtable
                $settings.StartupArguments.PSObject.Properties | ForEach-Object {
                    $key = $_.Name
                    $valueObj = $_.Value
                    
                    # If it's a PSCustomObject (nested object from JSON), convert to Hashtable
                    if ($valueObj -is [System.Management.Automation.PSCustomObject]) {
                        $hashtableValue = @{}
                        $valueObj.PSObject.Properties | ForEach-Object {
                            $hashtableValue[$_.Name] = $_.Value
                        }
                        $script:selectedArguments[$key] = $hashtableValue
                    } else {
                        # Simple value, assign directly
                        $script:selectedArguments[$key] = $valueObj
                    }
                }
                
                # Rebuild startup arguments display
                Build-StartupArguments
                if ($null -ne $script:currentArgsDisplay) {
                    $script:currentArgsDisplay.Text = $script:startupArguments
                }
            } catch {
                Write-Warning "Failed to restore startup arguments: $_"
                $script:selectedArguments = @{}
            }
        }

        # RCON settings - add null checks
        if ($null -ne $settings.RCON) {
            if ($null -ne $settings.RCON.Host)     { $script:rconHost = $settings.RCON.Host }
            if ($null -ne $settings.RCON.Port)     { $script:rconPort = $settings.RCON.Port }
            if ($null -ne $settings.RCON.Password) { $script:rconPassword = $settings.RCON.Password }
        }

        # Backup settings - add null checks
        if ($null -ne $settings.Backups) {
            if ($null -ne $settings.Backups.AutoBackupInterval) {
                $script:autoBackupInterval = $settings.Backups.AutoBackupInterval
            }
        }

    } catch {
        Write-Warning "Failed to load UI settings: $($_.Exception.Message)"
        # selectedArguments already initialized above, so it won't be null
    }
}


# ==========================================================================================
# UPDATE DISPLAY FUNCTIONS
# ==========================================================================================

function Update-StatusDisplay {
    if ($null -eq $script:statusLabel) { return }

    if ($script:serverRunning) {
        $script:statusLabel.Text = " RUNNING"
        $script:statusLabel.ForeColor = $colorSuccess
    } elseif ($script:serverStarting) {
        $script:statusLabel.Text = " STARTING..."
        $script:statusLabel.ForeColor = $colorWarning
    } else {
        $script:statusLabel.Text = " STOPPED"
        $script:statusLabel.ForeColor = $colorDanger
    }
}

function Update-MetricsDisplay {

    if (-not $script:serverRunning) { return }

    $metrics = Get-CurrentRESTMetrics
    if ($null -eq $metrics) { return }

    # Top bar
    if ($script:cpuLabel) {
        $script:cpuLabel.Text = "CPU: $($metrics.CPU)%"
    }
    if ($script:ramLabel) {
        $script:ramLabel.Text = "RAM: $([math]::Round($metrics.RAM,1)) MB"
    }
    if ($script:playerCountLabel) {
        $script:playerCountLabel.Text = "Players: $($metrics.Players)"
    }

    # Monitoring tab labels
    if ($script:monitoringLabels) {
        $script:monitoringLabels.CpuAvg.Text  = "CPU: $($metrics.CPU)%"
        $script:monitoringLabels.CpuPeak.Text = "FPS: $($metrics.FPS)"
        $script:monitoringLabels.RamAvg.Text  = "RAM: $([math]::Round($metrics.RAM,1)) MB"
        $script:monitoringLabels.RamPeak.Text = "Uptime: $($metrics.Uptime)"

        $health = Get-ServerHealthREST $metrics
        $script:monitoringLabels.Health.Text = " Health: $($health.Status)"
        $script:monitoringLabels.Health.ForeColor = $health.Color
    }

    # Charts
    Update-MonitoringCharts
}




function Restart-Server {
    # Stop the server
    Stop-Server | Out-Null
    
    # Wait for the process to actually exit (up to 30 seconds)
    $waitTime = 0
    $maxWait = 30
    while ($null -ne $script:serverProcess -and -not $script:serverProcess.HasExited -and $waitTime -lt $maxWait) {
        Start-Sleep -Seconds 1
        $waitTime++
    }
    
    # Force kill if still running
    if ($null -ne $script:serverProcess -and -not $script:serverProcess.HasExited) {
        try { $script:serverProcess.Kill() } catch {}
        Start-Sleep -Seconds 2
    }
    
    # Start the server
    Start-Server | Out-Null
}

# ==========================================================================================
# CLEANUP
# ==========================================================================================

function Cleanup-All {
    try { Cleanup-Core } catch {}
    try { Cleanup-RCON } catch {}
    try { Cleanup-Backups } catch {}
    try { Cleanup-Monitoring } catch {}
    try { Cleanup-ConfigManager } catch {}
}

# End of UI.ps1