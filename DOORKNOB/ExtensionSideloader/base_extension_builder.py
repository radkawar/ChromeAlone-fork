#!/usr/bin/env python3
"""
Base Chrome Extension Sideloader Builder

This module provides the base class for building platform-specific Chrome extension
sideloaders. It handles common functionality like extension zipping and base64 encoding.
"""

import os
import sys
import zipfile
import base64
import argparse
from pathlib import Path
from io import BytesIO
from abc import ABC, abstractmethod


class BaseExtensionBuilder(ABC):
    """Base class for platform-specific extension sideloader builders."""
    
    def __init__(self, extension_folder, install_path, output_path=None):
        self.extension_folder = Path(extension_folder)
        self.install_path = install_path
        self.output_path = output_path
        
        # Validate extension folder
        if not self.extension_folder.exists() or not self.extension_folder.is_dir():
            raise ValueError(f"Extension folder does not exist: {self.extension_folder}")
    
    def zip_extension(self):
        """Create a ZIP file from the extension folder and return it as bytes."""
        zip_data = BytesIO()
        
        with zipfile.ZipFile(zip_data, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for root, dirs, files in os.walk(self.extension_folder):
                for file in files:
                    file_path = Path(root) / file
                    arc_name = file_path.relative_to(self.extension_folder)
                    zipf.write(file_path, arc_name)
        
        return zip_data.getvalue()
    
    def encode_extension_base64(self):
        """Create ZIP of extension and return base64 encoded content."""
        extension_zip_bytes = self.zip_extension()
        return base64.b64encode(extension_zip_bytes).decode('utf-8')
    
    def read_file_as_base64(self, file_path):
        """Read a file and return its base64 encoded content."""
        file_path = Path(file_path)
        if not file_path.exists():
            raise ValueError(f"File does not exist: {file_path}")
        
        with open(file_path, 'rb') as f:
            content = f.read()
        
        return base64.b64encode(content).decode('utf-8')
    
    def get_output_file_path(self):
        """Determine the output file path."""
        if self.output_path:
            return Path(self.output_path)
        else:
            extension_name = self.extension_folder.name
            return Path(f"{extension_name}_sideloader{self.get_script_extension()}")
    
    @abstractmethod
    def get_script_extension(self):
        """Return the file extension for the target platform script."""
        pass
    
    @abstractmethod
    def create_extraction_functions(self, extension_base64):
        """Create platform-specific extraction functions."""
        pass
    
    @abstractmethod
    def read_template_script(self):
        """Read the platform-specific template script."""
        pass
    
    @abstractmethod
    def build_script_content(self, template_script, extraction_functions, extension_base64):
        """Build the complete script content for the target platform."""
        pass
    
    def build_sideloader_script(self):
        """Build the complete sideloader script."""
        print(f"Building {self.__class__.__name__} sideloader script...")
        print(f"  Extension folder: {self.extension_folder}")
        print(f"  Install path: {self.install_path}")
        
        # Create base64 encoded extension
        print("Creating extension ZIP...")
        extension_base64 = self.encode_extension_base64()
        
        # Read template script
        print("Reading template script...")
        template_script = self.read_template_script()
        
        # Create extraction functions
        print("Creating extraction functions...")
        extraction_functions = self.create_extraction_functions(extension_base64)
        
        # Build complete script
        print("Building script content...")
        script_content = self.build_script_content(template_script, extraction_functions, extension_base64)
        
        # Write output
        output_file = self.get_output_file_path()
        print(f"Writing output to: {output_file}")
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(script_content)
        
        # Make executable if needed
        self.make_executable(output_file)
        
        print(f"✅ Sideloader script created successfully: {output_file}")
        print(f"📦 Extension size: {len(base64.b64decode(extension_base64)):,} bytes")
        
        return output_file
    
    def make_executable(self, file_path):
        """Make the script executable (platform-specific implementation)."""
        pass  # Default implementation does nothing
