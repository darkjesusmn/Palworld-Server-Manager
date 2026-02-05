# ==========================================================================================
# ConfigManager.ps1 - Configuration File Management (Improved)
# ==========================================================================================
# Handles: INI parsing, editing, validation, and type conversion
# Supports all Palworld config options dynamically
# ==========================================================================================

# ==========================================================================================
# GLOBAL VARIABLES
# ==========================================================================================

# Determine server root
if (-not $script:serverRoot) {
    if ($PSScriptRoot -like "*\modules") {
        $script:serverRoot = Split-Path -Parent $PSScriptRoot
    } else {
        $script:serverRoot = $PSScriptRoot
    }
}

$script:configPath  = Join-Path $script:serverRoot "Pal\Saved\Config\WindowsServer\PalWorldSettings.ini"
$script:configCache = @{}
$script:configDirty = $false

# ==========================================================================================
# Initialize-ConfigManager
# ==========================================================================================

function Initialize-ConfigManager {
    Write-Verbose "Initializing ConfigManager..."
    Load-Config | Out-Null
}

# ==========================================================================================
# Load-Config (Improved)
# ==========================================================================================

function Load-Config {

    if (-not (Test-Path $script:configPath)) {
        Write-Error "Config file not found: $script:configPath"
        return $false
    }

    try {
        $content = Get-Content $script:configPath -Raw -Encoding UTF8

        # More robust multiline-safe regex
        if ($content -match "OptionSettings\s*=\s*\(([\s\S]*?)\)") {
            $optionString = $matches[1]

            $pairs = @()
            $current = ""
            $depth = 0
            $inQuotes = $false

            foreach ($char in $optionString.ToCharArray()) {

                if ($char -eq '"' -and ($current.Length -eq 0 -or $current[-1] -ne '\')) {
                    $inQuotes = -not $inQuotes
                }
                elseif ($char -eq '(' -and -not $inQuotes) {
                    $depth++
                }
                elseif ($char -eq ')' -and -not $inQuotes) {
                    $depth--
                }
                elseif ($char -eq ',' -and $depth -eq 0 -and -not $inQuotes) {
                    if ($current.Trim()) { $pairs += $current.Trim() }
                    $current = ""
                    continue
                }

                $current += $char
            }

            if ($current.Trim()) { $pairs += $current.Trim() }

            foreach ($pair in $pairs) {
                if ($pair -match '^(\w+)=(.*)$') {
                    $key   = $matches[1]
                    $value = $matches[2]

                    # Remove outer quotes safely (non-greedy)
                    if ($value -match '^"(.*?)(?<!\\)"$') {
                        $value = $matches[1]
                    }

                    $script:configCache[$key] = $value
                }
            }

            $script:configDirty = $false
            return $true
        }

        Write-Error "Could not parse OptionSettings block."
        return $false

    } catch {
        Write-Error "Error loading config: $_"
        return $false
    }
}

# ==========================================================================================
# Get-ConfigValue
# ==========================================================================================

function Get-ConfigValue {
    param([string]$key)

    if (-not $script:configCache.ContainsKey($key)) {
        return $null
    }

    $value = $script:configCache[$key]

    # Remove quotes if present
    if ($value -match '^"(.*)"$') {
        return $matches[1]
    }

    return $value
}

# ==========================================================================================
# Set-ConfigValue
# ==========================================================================================

function Set-ConfigValue {
    param(
        [string]$key,
        [string]$value
    )

    $script:configCache[$key] = $value
    $script:configDirty = $true
}

# ==========================================================================================
# Get-AllConfigKeys
# ==========================================================================================

function Get-AllConfigKeys {
    if ($script:configCache.Count -eq 0) {
        Load-Config | Out-Null
    }
    return $script:configCache.Keys | Sort-Object
}

# ==========================================================================================
# Get-ConfigType (Improved)
# ==========================================================================================

function Get-ConfigType {
    param([string]$key)

    $value = Get-ConfigValue $key
    if ($null -eq $value) { return "Unknown" }

    if ($value -match '^(?i:true|false)$') { return "Boolean" }
    if ($value -match '^-?\d+(\.\d+)?$')   { return "Number" }
    if ($value -match '^\(.*\)$')          { return "Array" }

    return "String"
}

# ==========================================================================================
# Save-Config (Improved)
# ==========================================================================================

function Save-Config {

    if (-not $script:configDirty) { return $true }

    try {
        Copy-Item $script:configPath "$script:configPath.bak" -Force

        $content = Get-Content $script:configPath -Raw -Encoding UTF8

        $optionPairs = @()

        foreach ($key in ($script:configCache.Keys | Sort-Object)) {
            $value = $script:configCache[$key]

            if ($value -match '^(?i:true|false)$' -or $value -match '^-?\d+(\.\d+)?$') {
                $optionPairs += "$key=$value"
            }
            elseif ($value -match '^\(.*\)$') {
                $optionPairs += "$key=$value"
            }
            else {
                $escaped = $value.Replace('"','\"')
                $optionPairs += "$key=""$escaped"""
            }
        }

        $newBlock = "OptionSettings=($($optionPairs -join ','))"

        # Multiline-safe replacement
        $newContent = $content -replace "OptionSettings\s*=\s*\(([\s\S]*?)\)", $newBlock

        Set-Content $script:configPath -Value $newContent -Encoding UTF8

        $script:configDirty = $false
        return $true

    } catch {
        Write-Error "Error saving config: $_"
        return $false
    }
}

# ==========================================================================================
# Reset-ConfigToDefault
# ==========================================================================================

function Reset-ConfigToDefault {

    # NOTE: This is still a partial default set.
    # Full 80-setting default table can be added later.

    $defaults = @{
        "Difficulty" = "None"
        "ExpRate" = "1.000000"
        "PalCaptureRate" = "1.000000"
        "DayTimeSpeedRate" = "1.000000"
        "NightTimeSpeedRate" = "1.000000"
        "bIsPvP" = "False"
        "bIsMultiplay" = "False"
        "ServerPlayerMaxNum" = "32"
        "ServerName" = "PalServer"
        "ServerPassword" = ""
    }

    foreach ($key in $defaults.Keys) {
        Set-ConfigValue $key $defaults[$key]
    }

    return Save-Config
}

# ==========================================================================================
# Cleanup-ConfigManager
# ==========================================================================================

function Cleanup-ConfigManager {
    if ($script:configDirty) {
        Save-Config | Out-Null
    }
}