#!/usr/bin/env python3
"""
macOS Chrome Extension Sideloader Builder

This module provides macOS-specific functionality for building Chrome extension
sideloaders using Bash scripts.
"""

import os
import stat
from pathlib import Path
from base_extension_builder import BaseExtensionBuilder


class MacOSExtensionBuilder(BaseExtensionBuilder):
    """macOS-specific extension sideloader builder using Bash."""
    
    def get_script_extension(self):
        """Return the Bash script extension."""
        return ".sh"
    
    def create_extraction_functions(self, extension_base64):
        """Create Bash extraction functions."""
        
        extract_extension_func = f'''
extract_embedded_extension() {{
    local extension_path="$1"
    
    echo "Extracting embedded extension to: $extension_path"
    
    # Create directory if it doesn't exist, or clear existing content
    if [[ -d "$extension_path" ]]; then
        echo "Clearing existing extension directory..."
        rm -rf "$extension_path"
    fi
    mkdir -p "$extension_path"
    
    # Decode and extract the embedded extension
    local extension_zip_base64="{extension_base64}"
    
    # Create temporary file for ZIP data
    local temp_zip_path=$(mktemp)
    
    # Decode base64 to temporary file
    echo "$extension_zip_base64" | base64 -d > "$temp_zip_path"
    
    # Extract ZIP contents
    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$temp_zip_path" -d "$extension_path"
        echo "Extension extracted successfully"
    else
        echo "Error: unzip command not found. Please install unzip utility."
        rm -f "$temp_zip_path"
        return 1
    fi
    
    # Clean up temp file
    rm -f "$temp_zip_path"
}}
'''
        
        return extract_extension_func
    
    def read_template_script(self):
        """Read the JXA Bash template script."""
        script_path = Path(__file__).parent / "macos" / "ChromeExtensionSideloader.sh"
        with open(script_path, 'r', encoding='utf-8') as f:
            return f.read()
    
    def build_script_content(self, template_script, extraction_functions, extension_base64):
        """Build the complete Bash script content."""
        
        # Replace placeholder functions in template
        script_content = template_script.replace(
            '# These functions will be replaced by the Python builder with actual extraction logic\n'
            'extract_embedded_extension() {\n'
            '    local extension_path="$1"\n'
            '    # This will be replaced by the Python builder\n'
            '    echo "Extract-EmbeddedExtension function not implemented - this should be replaced by the Python builder"\n'
            '    exit 1\n'
            '}',
            extraction_functions
        )
        
        # Set default parameters
        script_content = script_content.replace(
            'EXTENSION_INSTALL_DIR="$HOME/Library/Application Support/Google/Chrome/Default/Extensions/myextension"',
            f'EXTENSION_INSTALL_DIR="{self.install_path}"'
        )
        
        return script_content
    
    def make_executable(self, file_path):
        """Make the Bash script executable."""
        # Add execute permissions for owner, group, and others
        current_permissions = os.stat(file_path).st_mode
        os.chmod(file_path, current_permissions | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
