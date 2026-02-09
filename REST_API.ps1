# ==========================================================================================
# REST_API.ps1 - Palworld REST API Communication Module (Full SafeRetry Version)
# ==========================================================================================
# Handles: Server info, players, settings, metrics, announcements, kicks, bans, shutdown
# Features:
#   - Safe REST API port check before every call
#   - Automatic retry while server is starting
#   - AdminPassword fallback for key verification
#   - Debug logging for all requests
# ==========================================================================================

# ==========================================================================================
# GLOBAL VARIABLES
# ==========================================================================================
$script:restApiEnabled = $false
$script:restApiHost = "127.0.0.1"
$script:restApiPort = 8212
$script:restApiBaseUrl = "http://127.0.0.1:8212/v1/api"
$script:restApiTimeout = 5  # seconds
$script:restApiKey = "DJMN-Palworld-Admin-2026"

# ==========================================================================================
# Initialize-RestAPI
# ==========================================================================================
function Initialize-RestAPI {
    Write-Verbose "Initializing REST API..."

    if (-not $script:configCache -or $script:configCache.Count -eq 0) {
        if (Get-Command Initialize-ConfigManager -ErrorAction SilentlyContinue) {
            Initialize-ConfigManager
        } else {
            Write-Warning "ConfigManager not loaded! REST API settings may fail."
        }
    }

    # Load REST API settings from config WITHOUT verifying the key yet
    # Verification happens on-demand when server is running (20 seconds after Start)
    Load-RestAPISettings-NoVerify
}

# ==========================================================================================
# Load-RestAPISettings-NoVerify (Lightweight - No API Check)
# ==========================================================================================
function Load-RestAPISettings-NoVerify {
    try {
        if (-not $script:configCache -or $script:configCache.Count -eq 0) { 
            Initialize-ConfigManager 
        }

        # Just load config values, don't verify
        $restApiPortValue = Get-ConfigValue "RESTAPIPort"
        if ($restApiPortValue) { $script:restApiPort = [int]$restApiPortValue }

        $restApiKeyValue = Get-ConfigValue "RESTAPIKey"
        if ($restApiKeyValue) { $script:restApiKey = $restApiKeyValue }

        $script:restApiBaseUrl = "http://$($script:restApiHost):$($script:restApiPort)/v1/api"

        Write-Host "=== REST API CONFIG LOADED (No Verification Yet) ==="
        Write-Host "API Host   : $script:restApiHost"
        Write-Host "API Port   : $script:restApiPort"
        Write-Host "API Base   : $script:restApiBaseUrl"
        Write-Host "===================================================="

    } catch { 
        Write-Warning "Failed to load REST API settings: $($_.Exception.Message)" 
    }
}

# ==========================================================================================
# Update-RestAPISettings (With Verification - Call after server starts)
# ==========================================================================================
function Update-RestAPISettings {
    try {
        if (-not $script:configCache -or $script:configCache.Count -eq 0) { Initialize-ConfigManager }

        $palWorldINI = $script:configPath

        $restApiPortValue = Get-ConfigValue "RESTAPIPort"
        if ($restApiPortValue) { $script:restApiPort = [int]$restApiPortValue }

        $restApiKeyValue = Get-ConfigValue "RESTAPIKey"
        if ($restApiKeyValue) { $script:restApiKey = $restApiKeyValue }

        $script:restApiBaseUrl = "http://$($script:restApiHost):$($script:restApiPort)/v1/api"

        Write-Host "=== REST API CONFIG LOADING ==="
        Write-Host "INI Path   : $palWorldINI"
        Write-Host "API Host   : $script:restApiHost"
        Write-Host "API Port   : $script:restApiPort"
        Write-Host "API Base   : $script:restApiBaseUrl"
        Write-Host "Initial Key: $script:restApiKey"
        Write-Host "=============================="

        # Runtime Key Verification
        $verified = $false
        if (-not [string]::IsNullOrWhiteSpace($script:restApiKey)) {
            Write-Host "Verifying RESTAPIKey..."
            if (Verify-RestAPIKey) { $verified = $true }
        }

        if (-not $verified) {
            $adminPass = Get-ConfigValue "AdminPassword"
            if (-not [string]::IsNullOrWhiteSpace($adminPass)) {
                Write-Host "RESTAPIKey failed. Trying AdminPassword..."
                $script:restApiKey = $adminPass
                if (Verify-RestAPIKey) { $verified = $true }
            }
        }

        if ($verified) { Write-Host "[OK] REST API key successfully verified." }
        else { Write-Warning "[WARN] REST API key could not be verified. API calls may fail." }

    } catch { 
        Write-Warning "Failed to update REST API settings: $($_.Exception.Message)"
    }
}

# ==========================================================================================
# Verify-RestAPIKey
# ==========================================================================================
function Verify-RestAPIKey {
    try {
        $resp = Invoke-RestMethod -Uri "$($script:restApiBaseUrl)/info" -Headers @{
            "Accept" = "application/json"
            "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$($script:restApiKey)"))
        } -Method GET -ErrorAction Stop
        return ($resp -and $resp.servername)
    }
    catch { return $false }
}

# ==========================================================================================
# Test-RestAPIPort
# ==========================================================================================
function Test-RestAPIPort {
    param([string]$HostAddr = $script:restApiHost, [int]$Port = $script:restApiPort)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $async = $tcp.BeginConnect($HostAddr, $Port, $null, $null)
        $wait = $async.AsyncWaitHandle.WaitOne(10)
        if ($wait) { $tcp.EndConnect($async); $tcp.Close(); return $true }
        return $false
    } catch { return $false }
}

# ==========================================================================================
# Invoke-RestAPIRequest (Internal)
# ==========================================================================================
function Invoke-RestAPIRequest {
    param([string]$Endpoint, [string]$Method = "GET", [hashtable]$Body = $null, [int]$TimeoutSeconds = $script:restApiTimeout)

    function Build-Headers($password) {
        $pairBytes = [System.Text.Encoding]::UTF8.GetBytes("admin:$password")
        $base64 = [Convert]::ToBase64String($pairBytes)
        return @{
            "Accept" = "application/json"
            "Content-Type" = "application/json"
            "Authorization" = "Basic $base64"
        }
    }

    try {
        $url = "$($script:restApiBaseUrl)/$Endpoint"
        $authPassword = $script:restApiKey
        $headers = Build-Headers $authPassword

        $params = @{
            Uri = $url
            Method = $Method
            Headers = $headers
            TimeoutSec = $TimeoutSeconds
            ErrorAction = "Stop"
        }
        if ($Body) { $params["Body"] = ($Body | ConvertTo-Json -Compress) }

        Write-Host "=== REST API REQUEST ==="
        Write-Host "Method      : $Method"
        Write-Host "URL         : $url"
        Write-Host "AuthHeader  : $($headers['Authorization'])"
        Write-Host "Body        : " + ($Body | ConvertTo-Json -Compress -ErrorAction SilentlyContinue)
        Write-Host "======================="

        $response = Invoke-RestMethod @params
        
        Write-Host "=== REST API RESPONSE ==="
        Write-Host "Status      : Success"
        Write-Host "Response    : " + ($response | ConvertTo-Json -Compress -ErrorAction SilentlyContinue)
        Write-Host "======================="
        
        return $response
    }
    catch [System.Net.WebException] {
        $statusCode = $_.Exception.Response.StatusCode -as [int]
        Write-Host "=== REST API ERROR (WebException) ==="
        Write-Host "Status Code : $statusCode"
        Write-Host "Error       : $($_.Exception.Message)"
        Write-Host "=====================================\n"
        
        if ($statusCode -eq 401) {
            Write-Warning "REST API Key failed (401 Unauthorized). Retrying with AdminPassword..."
            $adminPass = Get-ConfigValue "AdminPassword"
            if (-not [string]::IsNullOrWhiteSpace($adminPass)) {
                Write-Host "Attempting retry with AdminPassword..."
                $headers = Build-Headers $adminPass
                $params["Headers"] = $headers
                try { 
                    $retryResponse = Invoke-RestMethod @params
                    Write-Host "Retry successful!"
                    return $retryResponse 
                } catch { 
                    Write-Warning "Retry failed: $($_.Exception.Message)"
                    return $null 
                }
            } else { 
                Write-Warning "AdminPassword not found. Cannot retry."
                return $null 
            }
        } else { 
            Write-Warning "REST API request failed with status $statusCode`: $($_.Exception.Message)"
            return $null 
        }
    }
    catch {
        Write-Host "=== REST API ERROR (General) ==="
        Write-Host "Error Type  : $($_.Exception.GetType().Name)"
        Write-Host "Error Msg   : $($_.Exception.Message)"
        Write-Host "================================`n"
        Write-Warning "REST API request failed: $($_.Exception.Message)"
        return $null 
    }
}

# ==========================================================================================
# Invoke-RestAPIRequest-SafeRetry
# ==========================================================================================
function Invoke-RestAPIRequest-SafeRetry {
    param([string]$Endpoint, [string]$Method="GET", [hashtable]$Body=$null, [int]$TimeoutSeconds=$script:restApiTimeout, [int]$WaitForSeconds=10)

    $startTime = Get-Date
    $portChecked = $false
    
    # First, check if port is already open
    if (Test-RestAPIPort) {
        $portChecked = $true
        Write-Verbose "REST API port $($script:restApiPort) is open, making request immediately"
        $result = Invoke-RestAPIRequest -Endpoint $Endpoint -Method $Method -Body $Body -TimeoutSeconds $TimeoutSeconds
        if ($null -ne $result) {
            return $result
        }
    }
    
    # If port wasn't open or request failed, wait for it to open
    if (-not $portChecked) {
        Write-Verbose "Waiting for REST API port $($script:restApiPort) to open (max ${WaitForSeconds}s)..."
        while ((Get-Date) - $startTime -lt [TimeSpan]::FromSeconds($WaitForSeconds)) {
            if (Test-RestAPIPort) {
                Write-Verbose "REST API port opened, making request"
                return Invoke-RestAPIRequest -Endpoint $Endpoint -Method $Method -Body $Body -TimeoutSeconds $TimeoutSeconds
            }
            Start-Sleep -Milliseconds 500
        }
        Write-Warning "REST API port $($script:restApiPort) did not open within $WaitForSeconds seconds."
    }
    
    return $null
}

# ==========================================================================================
# ============================
# ALL API FUNCTIONS
# ============================
# Replace every Invoke-RestAPIRequest call with Invoke-RestAPIRequest-SafeRetry
# ==========================================================================================

function Get-ServerInfo {
    $resp = Invoke-RestAPIRequest-SafeRetry -Endpoint "info"
    if ($resp) { return @{ ServerName=$resp.servername; Version=$resp.version; Status="Online"; Players=$resp.player_count } }
    return $null
}

function Get-PlayersREST {
    $resp = Invoke-RestAPIRequest-SafeRetry -Endpoint "players"
    if ($resp -and $resp.players) {
        $players = @()
        foreach ($p in $resp.players) {
            $players += @{ Name=$p.name; PlayerUID=$p.userid; CharacterUID=$p.characterid; Level=$p.level; Experience=$p.experience }
        }
        return $players
    }
    return @()
}

function Get-ServerSettingsREST { 
    return Invoke-RestAPIRequest-SafeRetry -Endpoint "settings" 
}

function Get-ServerMetricsREST {
    $resp = Invoke-RestAPIRequest-SafeRetry -Endpoint "metrics"

    if (-not $script:serverRunning) {
        return $null
    }


    if ($resp) {
        return @{
            CPU     = $null                     # Not provided by your server
            RAM     = $null                     # Not provided by your server
            Players = $resp.currentplayernum
            FPS     = $resp.serverfps
            Uptime  = $resp.uptime
        }
    }
    return $null
}



function Send-Announcement { 
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { Write-Error "Message empty"; return $false }
    $body = @{message=$Message}
    return (Invoke-RestAPIRequest-SafeRetry -Endpoint "announce" -Method "POST" -Body $body -TimeoutSeconds $script:restApiTimeout -WaitForSeconds 10) -ne $null
}

function Kick-PlayerREST { 
    param([string]$UserID,[string]$Message="You have been kicked")
    if ([string]::IsNullOrWhiteSpace($UserID)){ Write-Error "UserID empty"; return $false }
    $body = @{userid=$UserID;message=$Message}
    return (Invoke-RestAPIRequest-SafeRetry -Endpoint "kick" -Method "POST" -Body $body -TimeoutSeconds $script:restApiTimeout -WaitForSeconds 10) -ne $null
}

function Ban-PlayerREST { 
    param([string]$UserID,[string]$Message="You have been banned")
    if ([string]::IsNullOrWhiteSpace($UserID)){ Write-Error "UserID empty"; return $false }
    $body = @{userid=$UserID;message=$Message}
    return (Invoke-RestAPIRequest-SafeRetry -Endpoint "ban" -Method "POST" -Body $body -TimeoutSeconds $script:restApiTimeout -WaitForSeconds 10) -ne $null
}

function Unban-PlayerREST { 
    param([string]$UserID)
    if ([string]::IsNullOrWhiteSpace($UserID)){ Write-Error "UserID empty"; return $false }
    $body = @{userid=$UserID}
    return (Invoke-RestAPIRequest-SafeRetry -Endpoint "unban" -Method "POST" -Body $body -TimeoutSeconds $script:restApiTimeout -WaitForSeconds 10) -ne $null
}

function Save-WorldREST { 
    return (Invoke-RestAPIRequest-SafeRetry -Endpoint "save" -Method "POST" -TimeoutSeconds $script:restApiTimeout -WaitForSeconds 10) -ne $null
}

function Shutdown-ServerREST { 
    param([int]$WaitTimeSeconds=30,[string]$Message="Server will shutdown soon.")
    $body = @{waittime=$WaitTimeSeconds;message=$Message}
    return (Invoke-RestAPIRequest-SafeRetry -Endpoint "shutdown" -Method "POST" -Body $body -TimeoutSeconds $script:restApiTimeout -WaitForSeconds 10) -ne $null
}

function Stop-ServerREST { 
    return (Invoke-RestAPIRequest-SafeRetry -Endpoint "stop" -Method "POST" -TimeoutSeconds $script:restApiTimeout -WaitForSeconds 10) -ne $null
}

# ==========================================================================================
# Test-RestAPIConnection
# ==========================================================================================
function Test-RestAPIConnection { 
    return (Invoke-RestAPIRequest-SafeRetry -Endpoint "info" -Method "GET" -TimeoutSeconds $script:restApiTimeout -WaitForSeconds 10) -ne $null
}

# ==========================================================================================
# Cleanup-RestAPI
# ==========================================================================================
function Cleanup-RestAPI { 
    Write-Verbose "REST API cleanup complete" 
}