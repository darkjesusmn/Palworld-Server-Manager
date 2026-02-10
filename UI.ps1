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
# theme colors
$script:Themes = @{
    "Dark" = @{
        Bg            = [System.Drawing.Color]::FromArgb(30, 30, 30)
        PanelBg       = [System.Drawing.Color]::FromArgb(45, 45, 45)
        Text          = [System.Drawing.Color]::FromArgb(220, 220, 220)
        TextDim       = [System.Drawing.Color]::FromArgb(150, 150, 150)
        ButtonBg      = [System.Drawing.Color]::FromArgb(0, 120, 215)
        ButtonText    = [System.Drawing.Color]::White
        ButtonHover   = [System.Drawing.Color]::FromArgb(0, 140, 235)
        Danger        = [System.Drawing.Color]::FromArgb(220, 53, 69)
        Success       = [System.Drawing.Color]::FromArgb(40, 167, 69)
        Warning       = [System.Drawing.Color]::FromArgb(255, 193, 7)
        TextboxBg     = [System.Drawing.Color]::FromArgb(60, 60, 60)
        TextboxText   = [System.Drawing.Color]::FromArgb(200, 200, 200)
    }
}

$script:Themes["Midnight Blue"] = @{
    Bg            = [System.Drawing.Color]::FromArgb(20, 25, 40)
    PanelBg       = [System.Drawing.Color]::FromArgb(30, 35, 55)
    Text          = [System.Drawing.Color]::White
    TextDim       = [System.Drawing.Color]::FromArgb(160, 160, 160)
    ButtonBg      = [System.Drawing.Color]::FromArgb(50, 60, 90)
    ButtonText    = [System.Drawing.Color]::White
    ButtonHover   = [System.Drawing.Color]::FromArgb(70, 80, 120)
    Danger        = [System.Drawing.Color]::FromArgb(200, 60, 60)
    Success       = [System.Drawing.Color]::FromArgb(50, 150, 50)
    Warning       = [System.Drawing.Color]::FromArgb(255, 200, 50)
    TextboxBg     = [System.Drawing.Color]::FromArgb(25, 30, 45)
    TextboxText   = [System.Drawing.Color]::White
}

Write-Host "Loaded themes: $($script:Themes.Keys -join ', ')" -ForegroundColor Yellow



# Load default theme
$theme = $script:Themes["Dark"]
# default colors
$colorBg          = $theme.Bg
$colorPanelBg     = $theme.PanelBg
$colorText        = $theme.Text
$colorTextDim     = $theme.TextDim
$colorButtonBg    = $theme.ButtonBg
$colorButtonText  = $theme.ButtonText
$colorButtonHover = $theme.ButtonHover
$colorDanger      = $theme.Danger
$colorSuccess     = $theme.Success
$colorWarning     = $theme.Warning
$colorTextboxBg   = $theme.TextboxBg
$colorTextboxText = $theme.TextboxText


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
$script:nextRestartTime = $null
$script:rootPath = Split-Path $PSScriptRoot -Parent

# ==========================================================================================
# FUNCTION: Initialize-UI
# ==========================================================================================

function Initialize-UI {
    $script:form = New-ServerManagerForm
    Setup-EventCallbacks
    Load-UISettings
    Restore-StartupArguments

    # Hook monitoring callback AFTER UI is built
    $script:onMetricsUpdate = { Update-MetricsREST }

    Initialize-AutoRestart

    # ------------------------------------------------------------
    # REAL-TIME CONSOLE LOG UPDATE TIMER
    # ------------------------------------------------------------
    # This timer polls the rolling log file created by the
    # Console Redirect Engine in your main script.
    # Any new lines are pushed into the GUI console window.
    # ------------------------------------------------------------
    $ConsoleUpdateTimer = New-Object System.Windows.Forms.Timer
    $ConsoleUpdateTimer.Interval = 300   # update every 0.3 seconds

    $ConsoleUpdateTimer.Add_Tick({
        $newLines = Get-ConsoleLogTail
        foreach ($line in $newLines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            Append-ServerConsole $line
        }
    })

    $ConsoleUpdateTimer.Start()
    $script:ConsoleUpdateTimer = $ConsoleUpdateTimer
    # ------------------------------------------------------------

    # Mark UI as fully initialized
    $script:uiReady = $true

    # Start monitoring timer ONLY after UI is ready
    if ($script:monitoringTimer) {
        $script:monitoringTimer.Start()
    }

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
# FUNCTION: Apply-ThemeToUI
# ==========================================================================================
function Apply-ThemeToUI {

    function ApplyThemeToControl($control) {

        # Label
        if ($control -is [System.Windows.Forms.Label]) {
            $control.ForeColor = $colorText
        }

        # Button
        elseif ($control -is [System.Windows.Forms.Button]) {
            $control.BackColor = $colorButtonBg
            $control.ForeColor = $colorButtonText
        }

        # TextBox
        elseif ($control -is [System.Windows.Forms.TextBox]) {
            $control.BackColor = $colorTextboxBg
            $control.ForeColor = $colorTextboxText
        }

        # Panel
        elseif ($control -is [System.Windows.Forms.Panel]) {
            $control.BackColor = $colorPanelBg
        }

        # TabPage
        elseif ($control -is [System.Windows.Forms.TabPage]) {
            $control.BackColor = $colorPanelBg
            $control.ForeColor = $colorText
        }

        # DataGridView
        elseif ($control -is [System.Windows.Forms.DataGridView]) {
            $control.BackgroundColor = $colorTextboxBg
            $control.ForeColor = $colorTextboxText
            $control.ColumnHeadersDefaultCellStyle.BackColor = $colorPanelBg
            $control.ColumnHeadersDefaultCellStyle.ForeColor = $colorText
            $control.DefaultCellStyle.BackColor = $colorTextboxBg
            $control.DefaultCellStyle.ForeColor = $colorTextboxText

            foreach ($row in $control.Rows) {
                $row.DefaultCellStyle.BackColor = $colorTextboxBg
                $row.DefaultCellStyle.ForeColor = $colorTextboxText
            }
        }

        # Recurse into children
        foreach ($child in $control.Controls) {
            ApplyThemeToControl $child
        }
    }

    # Apply theme to the entire form and all nested controls
    ApplyThemeToControl $script:form
}





# ==========================================================================================
# FUNCTION: New-ServerManagerForm
# ==========================================================================================

function New-ServerManagerForm {

    $form = New-Object System.Windows.Forms.Form
    $script:form = $form
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

    # Next Restart Timer
    $script:nextRestartLabel = New-Object System.Windows.Forms.Label
    $script:nextRestartLabel.Text = "Next Restart: --"
    $script:nextRestartLabel.ForeColor = $colorText
    $script:nextRestartLabel.Location = New-Object System.Drawing.Point(350, 70)   # adjust as needed
    $script:nextRestartLabel.AutoSize = $true
    $statusPanel.Controls.Add($script:nextRestartLabel)

    




    $form.Controls.Add($statusPanel)

    $form.Controls.Add($statusPanel)

    # ====================
    # THEME DROPDOWN
    # ====================
    $themeDropdown = New-Object System.Windows.Forms.ComboBox
    $themeDropdown.Location = New-Object System.Drawing.Point(900, 15)
    $themeDropdown.Size = New-Object System.Drawing.Size(150, 25)
    $themeDropdown.DropDownStyle = "DropDownList"
    Write-Host "DEBUG: Themes.Keys = $($script:Themes.Keys -join ', ')" -ForegroundColor Yellow
    $themeDropdown.Items.Clear()
    if ($script:Themes.Keys.Count -eq 0) { 
        Write-Host "ERROR: No themes loaded!" -ForegroundColor Red 
    } else { 
        $themeDropdown.Items.AddRange([string[]]$script:Themes.Keys)
        $items = $themeDropdown.Items | ForEach-Object { "'$_'" }
        Write-Host "DEBUG: Dropdown items = $($items -join ', ')" -ForegroundColor Green
    }
    $themeDropdown.SelectedItem = "Dark"

    $themeDropdown.Add_SelectedIndexChanged({
        $selected = $themeDropdown.SelectedItem
        Write-Host "Theme changed to: $selected" -ForegroundColor Cyan # ← PUT IT RIGHT HERE
        if (-not $selected) { return }
        $theme = $script:Themes[$selected]
        if (-not $theme) { return }

        # Update global color variables
        $colorBg          = $theme.Bg
        $colorPanelBg     = $theme.PanelBg
        $colorText        = $theme.Text
        $colorTextDim     = $theme.TextDim
        $colorButtonBg    = $theme.ButtonBg
        $colorButtonText  = $theme.ButtonText
        $colorButtonHover = $theme.ButtonHover
        $colorDanger      = $theme.Danger
        $colorSuccess     = $theme.Success
        $colorWarning     = $theme.Warning
        $colorTextboxBg   = $theme.TextboxBg
        $colorTextboxText = $theme.TextboxText

        Apply-ThemeToUI
    })

    $statusPanel.Controls.Add($themeDropdown)





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
    $tabRCON.Text = "Console"
    $tabRCON.BackColor = $colorPanelBg
    Build-RCONTab $tabRCON $toolTip
    $tabControl.TabPages.Add($tabRCON)

    # ============================
    # SteamCMD Tab
    # ============================
    $steamcmdTab = New-Object System.Windows.Forms.TabPage
    $steamcmdTab.Text = "SteamCMD"
    $steamcmdTab.BackColor = $colorPanelBg
    Build-SteamCMDTab $steamcmdTab $toolTip
    $tabControl.TabPages.Add($steamcmdTab)


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

    # ============================================================
    # HEADER: Server Startup Arguments + Apply Button
    # ============================================================
    $lblArgsTitle = New-Object System.Windows.Forms.Label
    $lblArgsTitle.Text = "Server Startup Arguments:"
    $lblArgsTitle.Location = New-Object System.Drawing.Point(10, 10)
    $lblArgsTitle.Size = New-Object System.Drawing.Size(250, 20)
    $lblArgsTitle.ForeColor = $colorText
    $lblArgsTitle.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($lblArgsTitle)

    # Apply Arguments button (now next to header)
    $btnApplyArgs = New-Object System.Windows.Forms.Button
    $btnApplyArgs.Text = "Apply"
    $btnApplyArgs.Location = New-Object System.Drawing.Point(270, 8)
    $btnApplyArgs.Size = New-Object System.Drawing.Size(70, 25)
    $btnApplyArgs.BackColor = $colorSuccess
    $btnApplyArgs.ForeColor = $colorButtonText
    $btnApplyArgs.FlatStyle = "Flat"
    $btnApplyArgs.Font = New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($btnApplyArgs)
    $toolTip.SetToolTip($btnApplyArgs, "Apply selected startup arguments")

    # ============================================================
    # ARGUMENTS PANEL
    # ============================================================
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

    # ============================================================
    # CURRENT ARGUMENTS (inside panel)
    # ============================================================
    $lblCurrentArgs = New-Object System.Windows.Forms.Label
    $lblCurrentArgs.Text = "Current Arguments:"
    $lblCurrentArgs.Location = New-Object System.Drawing.Point(10, $yPos)
    $lblCurrentArgs.Size = New-Object System.Drawing.Size(200, 20)
    $lblCurrentArgs.ForeColor = $colorText
    $lblCurrentArgs.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $panelArgs.Controls.Add($lblCurrentArgs)

    $yPos += 25

    $txtCurrentArgs = New-Object System.Windows.Forms.TextBox
    $txtCurrentArgs.Location = New-Object System.Drawing.Point(10, $yPos)
    $txtCurrentArgs.Size = New-Object System.Drawing.Size(1020, 50)
    $txtCurrentArgs.Multiline = $true
    $txtCurrentArgs.ReadOnly = $true
    $txtCurrentArgs.BackColor = $colorTextboxBg
    $txtCurrentArgs.ForeColor = $colorTextboxText
    $txtCurrentArgs.Text = $script:startupArguments
    $panelArgs.Controls.Add($txtCurrentArgs)
    $script:currentArgsDisplay = $txtCurrentArgs

    $yPos += 60

    # ============================================================
    # APPLY ARGUMENTS BUTTON (logic stays the same)
    # ============================================================
    $btnApplyArgs.Add_Click({
        foreach ($argDef in $script:startupArgsDefinitions) {
            $chk = $script:argumentCheckboxes[$argDef.Name]

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

        Save-UISettings
    })

    # ============================================================
    # AUTO-RESTART CHECKBOX (moved to top row)
    # ============================================================
    $script:chkAutoRestart = New-Object System.Windows.Forms.CheckBox
    $script:chkAutoRestart.Text = "Auto-Restart (every 6 hours)"
    $script:chkAutoRestart.Location = New-Object System.Drawing.Point(600, 10)
    $script:chkAutoRestart.Size = New-Object System.Drawing.Size(250, 25)
    $script:chkAutoRestart.ForeColor = $colorText
    $script:chkAutoRestart.BackColor = $colorPanelBg

    if ($script:autoRestartEnabled) {
        $script:chkAutoRestart.Checked = $true
    }

    $script:chkAutoRestart.Add_CheckedChanged({
        param($sender, $eventArgs)

        $script:autoRestartEnabled = $sender.Checked
        Save-UISettings

        if ($script:autoRestartEnabled) {
            if ($script:serverRunning) {
                $script:nextRestartTime = (Get-Date).AddHours(6)
            } else {
                $script:nextRestartTime = $null
                $script:nextRestartLabel.Text = "Next Restart: --"
            }
        } else {
            $script:nextRestartTime = $null
            if ($script:nextRestartLabel) {
                $script:nextRestartLabel.Text = "Next Restart: --"
            }
        }
    })

    $tab.Controls.Add($script:chkAutoRestart)
    $toolTip.SetToolTip($script:chkAutoRestart, "Automatically restart the server every 6 hours")

    # ============================================================
    # CONSOLE HEADER + CLEAR BUTTON
    # ============================================================
    $lblLogsTitle = New-Object System.Windows.Forms.Label
    $lblLogsTitle.Text = "Server Console Output:"
    $lblLogsTitle.Location = New-Object System.Drawing.Point(10, 250)
    $lblLogsTitle.Size = New-Object System.Drawing.Size(200, 20)
    $lblLogsTitle.ForeColor = $colorText
    $lblLogsTitle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($lblLogsTitle)

    # Clear Logs button (now next to header)
    $btnClearLogs = New-Object System.Windows.Forms.Button
    $btnClearLogs.Text = "Clear"
    $btnClearLogs.Location = New-Object System.Drawing.Point(220, 247)
    $btnClearLogs.Size = New-Object System.Drawing.Size(60, 25)
    $btnClearLogs.BackColor = $colorButtonBg
    $btnClearLogs.ForeColor = $colorButtonText
    $btnClearLogs.FlatStyle = "Flat"
    $btnClearLogs.Font = New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Bold)
    $btnClearLogs.Add_Click({
        if ($script:logsTextBox) {
            $script:logsTextBox.Clear()
        }
    })
    $tab.Controls.Add($btnClearLogs)
    $toolTip.SetToolTip($btnClearLogs, "Clear log display")

    # ============================================================
    # CONSOLE WINDOW (expanded)
    # ============================================================
    $txtLogs = New-Object System.Windows.Forms.TextBox
    $txtLogs.Multiline = $true
    $txtLogs.ScrollBars = "Vertical"
    $txtLogs.Location = New-Object System.Drawing.Point(10, 275)
    $txtLogs.Size = New-Object System.Drawing.Size(1070, 260)
    $txtLogs.ReadOnly = $true
    $txtLogs.BackColor = $colorTextboxBg
    $txtLogs.ForeColor = $colorTextboxText
    $txtLogs.Font = New-Object System.Drawing.Font("Consolas", 8)
    $tab.Controls.Add($txtLogs)
    $toolTip.SetToolTip($txtLogs, "Live server console output")
    Set-LogOutputBox $txtLogs

    $script:logsTextBox = $txtLogs
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

    # DARK MODE
    $gridConfig.BackgroundColor = $colorTextboxBg
    $gridConfig.ForeColor = $colorTextboxText
    $gridConfig.GridColor = [System.Drawing.Color]::FromArgb(80,80,80)
    $gridConfig.ColumnHeadersDefaultCellStyle.BackColor = $colorPanelBg
    $gridConfig.ColumnHeadersDefaultCellStyle.ForeColor = $colorText
    $gridConfig.DefaultCellStyle.BackColor = $colorTextboxBg
    $gridConfig.DefaultCellStyle.ForeColor = $colorTextboxText
    $gridConfig.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(60,60,60)
    $gridConfig.DefaultCellStyle.SelectionForeColor = $colorText

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

    # === CRASH-PROOF SEARCH HANDLER ===
    $txtSearch.Add_TextChanged({
        if (-not $script:configGrid) { return }

        $search = $txtSearch.Text.ToLower()

        foreach ($row in $script:configGrid.Rows) {
            $key   = $row.Cells[0].Value
            $value = $row.Cells[2].Value

            $match = $false

            if ($key   -and $key.ToLower().Contains($search))   { $match = $true }
            if ($value -and $value.ToLower().Contains($search)) { $match = $true }

            $row.Visible = $match
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

    # DARK MODE BASE COLORS
    $grid.BackgroundColor = $colorTextboxBg
    $grid.ForeColor = $colorTextboxText
    $grid.GridColor = [System.Drawing.Color]::FromArgb(80,80,80)

    $grid.ColumnHeadersDefaultCellStyle.BackColor = $colorPanelBg
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = $colorText
    $grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)

    $grid.DefaultCellStyle.BackColor = $colorTextboxBg
    $grid.DefaultCellStyle.ForeColor = $colorTextboxText
    $grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(60,60,60)
    $grid.DefaultCellStyle.SelectionForeColor = $colorText

    # Columns
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
    if (-not $script:playerGrid) { return }

    $script:playerGrid.Rows.Clear()

    $players = Get-PlayersREST
    foreach ($p in $players) {
        $script:playerGrid.Rows.Add($p.Name, $p.PlayerUID, $p.Level)
    }

    # === FORCE DARK MODE ON REFRESH ===
    foreach ($row in $script:playerGrid.Rows) {
        $row.DefaultCellStyle.BackColor = $colorTextboxBg
        $row.DefaultCellStyle.ForeColor = $colorTextboxText
        $row.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(60,60,60)
        $row.DefaultCellStyle.SelectionForeColor = $colorText
    }
}


# ===== MONITORING TAB =====
function Build-MonitoringTab {
    param($tab, $toolTip)

    # === MAIN SCROLLABLE VERTICAL LAYOUT ============================================
    $mainPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $mainPanel.Dock = "Fill"
    $mainPanel.FlowDirection = "TopDown"
    $mainPanel.WrapContents = $false
    $mainPanel.AutoScroll = $false   # IMPORTANT: no scrolling for 720p embed
    $mainPanel.BackColor = $colorPanelBg
    $mainPanel.Padding = '10,10,10,10'
    $tab.Controls.Add($mainPanel)

    # === TITLE ======================================================================
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Server Monitoring (REST API)"
    $lblTitle.AutoSize = $true
    $lblTitle.ForeColor = $colorText
    $lblTitle.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
    $mainPanel.Controls.Add($lblTitle)

    # === CHART CREATOR =============================================================
    Add-Type -AssemblyName System.Windows.Forms.DataVisualization

    function New-LineChart {
        param($title, $seriesName, $color)

        $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
        $chart.Width = 500
        $chart.Height = 160
        $chart.BackColor = $colorPanelBg
        $chart.Margin = '5,5,5,5'

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

        # Title will be dynamically updated by Update-MetricsREST
        $chart.Titles.Add($title) | Out-Null
        $chart.Titles[0].ForeColor = $colorText
        $chart.Titles[0].Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)

        return $chart
    }

    # === CHART GRID (2×2) ===========================================================
    $chartGrid = New-Object System.Windows.Forms.TableLayoutPanel
    $chartGrid.ColumnCount = 2
    $chartGrid.RowCount = 2
    $chartGrid.BackColor = $colorPanelBg
    $chartGrid.Margin = '0,10,0,10'
    $chartGrid.AutoSize = $true

    $chartGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    $chartGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))

    $chartGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 160)))
    $chartGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 160)))

    $mainPanel.Controls.Add($chartGrid)

    # === CREATE CHARTS ==============================================================
    $script:cpuChart    = New-LineChart "CPU: -- | Threads: -- | Handles: --" "CPU"     $colorWarning
    $script:ramChart    = New-LineChart "RAM: -- | Peak: --"                  "RAM"     $colorSuccess
    $script:playerChart = New-LineChart "Players: --"                         "Players" $colorButtonBg
    $script:fpsChart    = New-LineChart "FPS: --"                             "FPS"     $colorDanger

    # Add charts to grid
    $chartGrid.Controls.Add($script:cpuChart,    0, 0)
    $chartGrid.Controls.Add($script:ramChart,    1, 0)
    $chartGrid.Controls.Add($script:playerChart, 0, 1)
    $chartGrid.Controls.Add($script:fpsChart,    1, 1)

    # === REFRESH BUTTON =============================================================
    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "[REFRESH NOW]"
    $btnRefresh.Size = New-Object System.Drawing.Size(150, 35)
    $btnRefresh.BackColor = $colorButtonBg
    $btnRefresh.ForeColor = $colorButtonText
    $btnRefresh.FlatStyle = "Flat"
    $btnRefresh.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $btnRefresh.Margin = '0,10,0,10'
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


# =====================================================================
# BUILD: SteamCMD Tab (UI Module)
# =====================================================================
function Build-SteamCMDTab {
    param(
        $tab,
        $toolTip
    )

    # Main layout container
    $mainPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $mainPanel.Dock = "Fill"
    $mainPanel.ColumnCount = 1
    $mainPanel.RowCount = 3
    $mainPanel.BackColor = $colorPanelBg
    $mainPanel.Padding = '10,10,10,10'
    $mainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $mainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $mainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $tab.Controls.Add($mainPanel)

    # ============================================================
    # HEADER + STATUS
    # ============================================================
    $headerPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $headerPanel.FlowDirection = "TopDown"
    $headerPanel.WrapContents = $false
    $headerPanel.AutoSize = $true
    $headerPanel.BackColor = $colorPanelBg
    $mainPanel.Controls.Add($headerPanel)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "SteamCMD - Server Installer & Updates"
    $lblTitle.AutoSize = $true
    $lblTitle.ForeColor = $colorText
    $lblTitle.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
    $headerPanel.Controls.Add($lblTitle)

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = "Download, validate, and update the Palworld Dedicated Server using SteamCMD."
    $lblDesc.AutoSize = $true
    $lblDesc.ForeColor = $colorTextDim
    $lblDesc.Font = New-Object System.Drawing.Font("Arial", 9)
    $headerPanel.Controls.Add($lblDesc)

    # Status labels
    $statusPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $statusPanel.FlowDirection = "TopDown"
    $statusPanel.WrapContents = $false
    $statusPanel.AutoSize = $true
    $statusPanel.BackColor = $colorPanelBg
    $statusPanel.Margin = '0,10,0,10'
    $headerPanel.Controls.Add($statusPanel)

    $script:lblSteamCMD_ServerStatus = New-Object System.Windows.Forms.Label
    $script:lblSteamCMD_ServerStatus.Text = "PalServer.exe: [Not checked]"
    $script:lblSteamCMD_ServerStatus.AutoSize = $true
    $script:lblSteamCMD_ServerStatus.ForeColor = $colorTextDim
    $statusPanel.Controls.Add($script:lblSteamCMD_ServerStatus)

    $script:lblSteamCMD_IniStatus = New-Object System.Windows.Forms.Label
    $script:lblSteamCMD_IniStatus.Text = "PalWorldSettings.ini: [Not checked]"
    $script:lblSteamCMD_IniStatus.AutoSize = $true
    $script:lblSteamCMD_IniStatus.ForeColor = $colorTextDim
    $statusPanel.Controls.Add($script:lblSteamCMD_IniStatus)

    $script:lblSteamCMD_UpdateStatus = New-Object System.Windows.Forms.Label
    $script:lblSteamCMD_UpdateStatus.Text = "Update Status: Unknown"
    $script:lblSteamCMD_UpdateStatus.AutoSize = $true
    $script:lblSteamCMD_UpdateStatus.ForeColor = $colorTextDim
    $statusPanel.Controls.Add($script:lblSteamCMD_UpdateStatus)


    # ============================================================
    # BUTTONS + OPTIONS
    # ============================================================
    $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonPanel.FlowDirection = "LeftToRight"
    $buttonPanel.WrapContents = $true
    $buttonPanel.AutoSize = $true
    $buttonPanel.BackColor = $colorPanelBg
    $buttonPanel.Margin = '0,10,0,10'
    $mainPanel.Controls.Add($buttonPanel)

    # --- DOWNLOAD SERVER FILES ---
    $btnDownload = New-Object System.Windows.Forms.Button
    $btnDownload.Text = "[ DOWNLOAD SERVER FILES ]"
    $btnDownload.Size = New-Object System.Drawing.Size(220, 35)
    $btnDownload.BackColor = $colorButtonBg
    $btnDownload.ForeColor = $colorButtonText
    $btnDownload.FlatStyle = "Flat"
    $btnDownload.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $btnDownload.Add_Click({
        Write-SteamCMDLog "=== DOWNLOAD SERVER FILES CLICKED ==="
        Install-PalworldServer
    })
    $buttonPanel.Controls.Add($btnDownload)

    # --- CHECK REQUIRED FILES ---
    $btnCheckFiles = New-Object System.Windows.Forms.Button
    $btnCheckFiles.Text = "[ CHECK REQUIRED FILES ]"
    $btnCheckFiles.Size = New-Object System.Drawing.Size(220, 35)
    $btnCheckFiles.BackColor = $colorButtonBg
    $btnCheckFiles.ForeColor = $colorButtonText
    $btnCheckFiles.FlatStyle = "Flat"
    $btnCheckFiles.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $btnCheckFiles.Add_Click({
        Write-SteamCMDLog "=== CHECK REQUIRED FILES CLICKED ==="
        Check-RequiredServerFiles | Out-Null
    })
    $buttonPanel.Controls.Add($btnCheckFiles)

    # --- CHECK FOR UPDATES ---
    $btnCheckUpdates = New-Object System.Windows.Forms.Button
    $btnCheckUpdates.Text = "[ CHECK FOR UPDATES ]"
    $btnCheckUpdates.Size = New-Object System.Drawing.Size(220, 35)
    $btnCheckUpdates.BackColor = $colorButtonBg
    $btnCheckUpdates.ForeColor = $colorButtonText
    $btnCheckUpdates.FlatStyle = "Flat"
    $btnCheckUpdates.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $btnCheckUpdates.Add_Click({
        Write-SteamCMDLog "=== CHECK FOR UPDATES CLICKED ==="
        Check-ForPalworldUpdates
        Update-PalworldUpdateStatus
    })
    $buttonPanel.Controls.Add($btnCheckUpdates)

    # --- UPDATE SERVER ---
    $btnUpdate = New-Object System.Windows.Forms.Button
    $btnUpdate.Text = "[ UPDATE SERVER ]"
    $btnUpdate.Size = New-Object System.Drawing.Size(220, 35)
    $btnUpdate.BackColor = $colorButtonBg
    $btnUpdate.ForeColor = $colorButtonText
    $btnUpdate.FlatStyle = "Flat"
    $btnUpdate.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $btnUpdate.Add_Click({
        Write-SteamCMDLog "=== UPDATE SERVER CLICKED ==="
        Update-PalworldServer
    })
    $buttonPanel.Controls.Add($btnUpdate)

    # --- DOWNLOAD STEAMCMD ONLY ---
    $btnDownloadSteamCMD = New-Object System.Windows.Forms.Button
    $btnDownloadSteamCMD.Text = "[ DOWNLOAD STEAMCMD ]"
    $btnDownloadSteamCMD.Size = New-Object System.Drawing.Size(220, 35)
    $btnDownloadSteamCMD.BackColor = $colorButtonBg
    $btnDownloadSteamCMD.ForeColor = $colorButtonText
    $btnDownloadSteamCMD.FlatStyle = "Flat"
    $btnDownloadSteamCMD.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $btnDownloadSteamCMD.Add_Click({
        Write-SteamCMDLog "=== DOWNLOAD STEAMCMD CLICKED ==="
        Install-SteamCMD
    })
    $buttonPanel.Controls.Add($btnDownloadSteamCMD)


    # --- AUTO-RESTART CHECKBOX ---
    $script:chkSteamCMD_AutoRestart = New-Object System.Windows.Forms.CheckBox
    $script:chkSteamCMD_AutoRestart.Text = "Auto-restart server after update"
    $script:chkSteamCMD_AutoRestart.AutoSize = $true
    $script:chkSteamCMD_AutoRestart.ForeColor = $colorText
    $script:chkSteamCMD_AutoRestart.Margin = '15,10,0,0'
    $buttonPanel.Controls.Add($script:chkSteamCMD_AutoRestart)

    # ============================================================
    # OUTPUT CONSOLE
    # ============================================================
    $outputPanel = New-Object System.Windows.Forms.Panel
    $outputPanel.Dock = "Fill"
    $outputPanel.BackColor = $colorPanelBg
    $mainPanel.Controls.Add($outputPanel)

    $script:steamcmdOutputBox = New-Object System.Windows.Forms.TextBox
    $script:steamcmdOutputBox.Multiline = $true
    $script:steamcmdOutputBox.ScrollBars = "Vertical"
    $script:steamcmdOutputBox.ReadOnly = $true
    $script:steamcmdOutputBox.Dock = "Fill"
    $script:steamcmdOutputBox.BackColor = [System.Drawing.Color]::FromArgb(20,20,20)
    $script:steamcmdOutputBox.ForeColor = $colorText
    $script:steamcmdOutputBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $outputPanel.Controls.Add($script:steamcmdOutputBox)

    Write-SteamCMDLog "SteamCMD tab initialized. Ready when you are."
    Update-PalworldUpdateStatus
}

# ==========================================================================================
# UI SETTINGS (SAVE / LOAD)
# ==========================================================================================

function Save-UISettings {
    try {

        # Convert selectedArguments to a JSON-safe hashtable
        $startupArgsHT = @{}
        foreach ($key in $script:selectedArguments.Keys) {
            $value = $script:selectedArguments[$key]

            if ($value -is [System.Collections.Hashtable]) {
                $startupArgsHT[$key] = $value
            }
            elseif ($value -is [System.Management.Automation.PSCustomObject]) {
                $ht = @{}
                $value.PSObject.Properties | ForEach-Object {
                    $ht[$_.Name] = $_.Value
                }
                $startupArgsHT[$key] = $ht
            }
            else {
                $startupArgsHT[$key] = $value
            }
        }

        # Compute SelectedTab *before* building the hashtable
        $selectedTab = 0
        if ($script:form -and
            $script:form.Controls.Count -gt 0 -and 
            $script:form.Controls[0] -is [System.Windows.Forms.TabControl]) {

            $selectedTab = $script:form.Controls[0].SelectedIndex
        }

        $settings = @{
            Window = @{
                Width  = $script:form.Width
                Height = $script:form.Height
                X      = $script:form.Location.X
                Y      = $script:form.Location.Y
            }

            SelectedTab      = $selectedTab
            StartupArguments = $startupArgsHT
            autoRestartEnabled = $script:autoRestartEnabled

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
        Write-Warning "Failed to save UI settings: $($_.Exception.Message)"
    }
}


#=========================================================================================
# LOAD UI SETTINGS
#=========================================================================================

function Load-UISettings {

    # Always initialize selectedArguments
    if ($null -eq $script:selectedArguments) {
        $script:selectedArguments = @{}
    }

    if (-not (Test-Path $script:settingsPath)) {
        Write-Verbose "No UI settings file found - using defaults."
        return
    }

    try {
        $json = Get-Content $script:settingsPath -Raw -Encoding UTF8 -ErrorAction Stop
        
        if ([string]::IsNullOrWhiteSpace($json)) {
            Write-Verbose "Settings file is empty - using defaults."
            return
        }

        $settings = $json | ConvertFrom-Json -ErrorAction Stop

        # ============================================================
        # WINDOW SIZE + POSITION (ONLY if form is fully initialized)
        # ============================================================
        if ($null -ne $script:form -and $script:form -is [System.Windows.Forms.Form]) {

            if ($settings.Window) {
                if ($settings.Window.Width -and $settings.Window.Height) {
                    $script:form.Width  = $settings.Window.Width
                    $script:form.Height = $settings.Window.Height
                }

                if ($settings.Window.X -ge 0 -and $settings.Window.Y -ge 0) {
                    $script:form.StartPosition = "Manual"
                    $script:form.Location = New-Object System.Drawing.Point(
                        $settings.Window.X,
                        $settings.Window.Y
                    )
                }
            }

            # Selected tab (only if tab control exists)
            if ($settings.SelectedTab -ne $null -and 
                $script:form.Controls.Count -gt 0 -and 
                $script:form.Controls[0] -is [System.Windows.Forms.TabControl]) {

                try {
                    $script:form.Controls[0].SelectedIndex = $settings.SelectedTab
                } catch {}
            }
        }

        # ============================================================
        # STARTUP ARGUMENTS (convert PSCustomObject → Hashtable)
        # ============================================================
        if ($settings.StartupArguments) {
            try {
                $script:selectedArguments = @{}

                $settings.StartupArguments.PSObject.Properties | ForEach-Object {
                    $key = $_.Name
                    $valueObj = $_.Value

                    if ($valueObj -is [System.Management.Automation.PSCustomObject]) {
                        $ht = @{}
                        $valueObj.PSObject.Properties | ForEach-Object {
                            $ht[$_.Name] = $_.Value
                        }
                        $script:selectedArguments[$key] = $ht
                    }
                    else {
                        $script:selectedArguments[$key] = $valueObj
                    }
                }

            } catch {
                Write-Warning "Failed to restore startup arguments: $_"
                $script:selectedArguments = @{}
            }
        }

        # ============================================================
        # AUTO-RESTART SETTING
        # ============================================================
        if ($settings.autoRestartEnabled -ne $null) {
            $script:autoRestartEnabled = $settings.autoRestartEnabled
        }

        # ============================================================
        # RCON SETTINGS
        # ============================================================
        if ($settings.RCON) {
            if ($settings.RCON.Host)     { $script:rconHost = $settings.RCON.Host }
            if ($settings.RCON.Port)     { $script:rconPort = $settings.RCON.Port }
            if ($settings.RCON.Password) { $script:rconPassword = $settings.RCON.Password }
        }

        # ============================================================
        # BACKUP SETTINGS
        # ============================================================
        if ($settings.Backups) {
            if ($settings.Backups.AutoBackupInterval) {
                $script:autoBackupInterval = $settings.Backups.AutoBackupInterval
            }
        }

    } catch {
        Write-Warning "Failed to load UI settings: $($_.Exception.Message)"
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
#=========================================================================================
# UPDATE METRICS DISPLAY
#=========================================================================================

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

    # === Auto-Restart Countdown Update ===
    if ($script:nextRestartLabel -ne $null) {
        Write-Host "COUNTDOWN: Enabled=$script:autoRestartEnabled Time=$script:nextRestartTime Label=$($script:nextRestartLabel.Text)" -ForegroundColor Magenta
        
        if ($script:autoRestartEnabled -and $script:nextRestartTime) {

            $remaining = $script:nextRestartTime - (Get-Date)

            if ($remaining.TotalSeconds -le 0) {
                $script:nextRestartLabel.Text = "Next Restart: NOW"
            }
            else {
                $hours   = [int]$remaining.TotalHours
                $minutes = $remaining.Minutes
                $seconds = $remaining.Seconds

                $script:nextRestartLabel.Text = "Next Restart: {0:00}:{1:00}:{2:00}" -f $hours, $minutes, $seconds
            }
        }
        else {
            $script:nextRestartLabel.Text = "Next Restart: --"
        }
    }

    # Charts
    Update-MonitoringCharts
}



#=========================================================================================
# RESTART SERVER
#========================================================================================= 

function Restart-Server {

    Write-Host "`n=== SERVER RESTART INITIATED ===" -ForegroundColor Yellow

    # --- STOP SERVER --------------------------------------------------------------
    Stop-Server | Out-Null

    # --- WAIT FOR PROCESS TO EXIT -------------------------------------------------
    $waitTime = 0
    $maxWait  = 30

    while ($null -ne $script:serverProcess -and 
           -not $script:serverProcess.HasExited -and 
           $waitTime -lt $maxWait) {

        Start-Sleep -Seconds 1
        $waitTime++
    }

    # --- FORCE KILL IF STILL RUNNING ----------------------------------------------
    if ($null -ne $script:serverProcess -and -not $script:serverProcess.HasExited) {
        Write-Host "Force killing server process..." -ForegroundColor Red
        try { $script:serverProcess.Kill() } catch {}
        Start-Sleep -Seconds 2
    }

    # --- RESET MONITORING UI BEFORE RESTART ---------------------------------------
    Reset-MonitoringUI

    # --- CLEAR PROCESS REFERENCE --------------------------------------------------
    $script:serverProcess = $null

    # --- START SERVER --------------------------------------------------------------
    Write-Host "Starting server..." -ForegroundColor Green
    Start-Server | Out-Null

    Write-Host "=== SERVER RESTART COMPLETE ===" -ForegroundColor Green
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