#!/usr/bin/env python3
"""
Windows Chrome Extension Sideloader Builder

This module provides Windows-specific functionality for building Chrome extension
sideloaders using PowerShell scripts.
"""

from pathlib import Path
from base_extension_builder import BaseExtensionBuilder


class WindowsExtensionBuilder(BaseExtensionBuilder):
    """Windows-specific extension sideloader builder using PowerShell."""
    
    def get_script_extension(self):
        """Return the PowerShell script extension."""
        return ".ps1"
    
    def create_extraction_functions(self, extension_base64):
        """Create PowerShell extraction functions."""
        
        extract_extension_func = f'''
function Extract-EmbeddedExtension {{
    param([string]$ExtensionPath)
    
    Write-Host "Extracting embedded extension to: $ExtensionPath" -ForegroundColor Cyan
    
    # Create directory if it doesn't exist, or clear existing content
    if (Test-Path $ExtensionPath) {{
        Write-Host "Clearing existing extension directory..." -ForegroundColor Yellow
        Remove-Item $ExtensionPath -Recurse -Force
    }}
    New-Item -ItemType Directory -Path $ExtensionPath -Force | Out-Null
    
    # Decode and extract the embedded extension
    $extensionZipBase64 = "{extension_base64}"
    $extensionZipBytes = [System.Convert]::FromBase64String($extensionZipBase64)
    
    # Create temporary ZIP file
    $tempZipPath = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllBytes($tempZipPath, $extensionZipBytes)
    
    try {{
        # Extract ZIP contents
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZipPath, $ExtensionPath)
        Write-Host "Extension extracted successfully" -ForegroundColor Green
    }}
    finally {{
        # Clean up temp file
        if (Test-Path $tempZipPath) {{
            Remove-Item $tempZipPath -Force
        }}
    }}
}}
'''
        
        return extract_extension_func
    
    def read_template_script(self):
        """Read the PowerShell template script."""
        script_path = Path(__file__).parent / "powershell" / "ChromeExtensionSideloader.ps1"
        with open(script_path, 'r', encoding='utf-8') as f:
            return f.read()
    
    def build_script_content(self, template_script, extraction_functions, extension_base64):
        """Build the complete PowerShell script content."""
        
        # Replace placeholder functions in template
        script_content = template_script.replace(
            '# These functions will be replaced by the Python builder with actual extraction logic\n'
            'function Extract-EmbeddedExtension {\n'
            '    param([string]$ExtensionPath)\n'
            '    # This will be replaced by the Python builder\n'
            '    throw "Extract-EmbeddedExtension function not implemented - this should be replaced by the Python builder"\n'
            '}\n\n',
            extraction_functions
        )
        
        # Set default parameters
        script_content = script_content.replace(
            '[string]$ExtensionInstallDir = "%LOCALAPPDATA%\\Google\\Chrome\\User Data\\Default\\Extensions\\myextension"',
            f'[string]$ExtensionInstallDir = "{self.install_path}"'
        )
        
        return script_content
