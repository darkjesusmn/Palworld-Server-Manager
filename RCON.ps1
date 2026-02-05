# ==========================================================================================
# RCON.ps1 - Palworld Server Command Interface (REST API Wrapper)
# ==========================================================================================
# This module wraps the REST_API.ps1 functions for backward compatibility
# and provides server control via REST API endpoints
# Dependencies: REST_API.ps1
# ==========================================================================================

# ==========================================================================================
# GLOBAL VARIABLES
# ==========================================================================================

$script:rconConnected  = $false
$script:rconHost       = "127.0.0.1"
$script:rconPort       = 8212
$script:playerList     = @()
$script:playerListUpdateTime = $null

# ==========================================================================================
# Initialize-RCON
# ==========================================================================================

function Initialize-RCON {
    Write-Verbose "Initializing REST API Interface (RCON wrapper)..."
    # REST_API.ps1 will be initialized separately by main script
}

# ==========================================================================================
# Update-RCONSettings (Compatibility function)
# ==========================================================================================

function Update-RCONSettings {
    # REST_API.ps1 handles this via Initialize-RestAPI
    Write-Verbose "RCON settings managed by REST_API module"
}

# ==========================================================================================
# Connect-RCON (Test REST API Connection)
# ==========================================================================================

function Connect-RCON {
    try {
        Write-Verbose "Testing REST API connection..."
        $response = Invoke-RestAPIRequest -Endpoint "info" -Method "GET" -TimeoutSeconds 2
        
        if ($null -ne $response) {
            $script:rconConnected = $true
            Write-Output "REST API connected successfully"
            return $true
        } else {
            throw "No response from API"
        }
    }
    catch {
        Write-Error "REST API connection failed: $_"
        $script:rconConnected = $false
        return $false
    }
}

# ==========================================================================================
# Disconnect-RCON (Compatibility function)
# ==========================================================================================

function Disconnect-RCON {
    $script:rconConnected = $false
}

# ==========================================================================================
# Get-PlayerList (Delegates to REST_API)
# ==========================================================================================

function Get-PlayerList {
    Write-Verbose "Getting player list via REST API..."
    return Get-PlayersREST
}

# ==========================================================================================
# Send-Announcement (Delegates to REST_API)
# ==========================================================================================

function Send-Announcement {
    param([string]$Message)
    return Send-Announcement -Message $Message
}

# ==========================================================================================
# Kick-Player (Delegates to REST_API)
# ==========================================================================================

function Kick-Player {
    param($uid)
    return Kick-PlayerREST -UserID $uid
}

# ==========================================================================================
# Ban-Player (Delegates to REST_API)
# ==========================================================================================

function Ban-Player {
    param($uid)
    return Ban-PlayerREST -UserID $uid
}

# ==========================================================================================
# Unban-Player (Delegates to REST_API)
# ==========================================================================================

function Unban-Player {
    param($uid)
    return Unban-PlayerREST -UserID $uid
}

# ==========================================================================================
# Save-World (Delegates to REST_API)
# ==========================================================================================

function Save-World {
    Write-Verbose "Saving world via REST API..."
    return Save-WorldREST
}

# ==========================================================================================
# Shutdown-ServerRCON (REST API Graceful Shutdown)
# ==========================================================================================

function Shutdown-ServerRCON {
    param(
        [int]$secondsWarning = 30,
        [string]$Message = "Server shutting down"
    )
    
    Write-Verbose "Initiating graceful shutdown via REST API..."
    return Shutdown-ServerREST -WaitTimeSeconds $secondsWarning -Message $Message
}

# ==========================================================================================
# Stop-ServerAPI (REST API Force Stop)
# ==========================================================================================

function Stop-ServerAPI {
    Write-Verbose "Force stopping server via REST API..."
    return Stop-ServerREST
}

# ==========================================================================================
# Test-RestAPIConnection (Compatibility function)
# ==========================================================================================

function Test-RestAPIConnection {
    return Connect-RCON
}

# ==========================================================================================
# Cleanup-RCON
# ==========================================================================================

function Cleanup-RCON {
    Disconnect-RCON
    Write-Verbose "RCON/REST API wrapper cleanup complete"
}