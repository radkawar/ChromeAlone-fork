#!/usr/bin/env python3
"""
IWA Sideloader Script Generator

This script generates platform-specific sideloader scripts for Isolated Web Apps (IWAs).
It supports both Windows (PowerShell) and macOS (bash) platforms.

The script has been refactored into a modular architecture:
- base_sideloader.py: Common functionality and abstract base class
- windows_sideloader.py: Windows-specific PowerShell script generation
- macos_sideloader.py: macOS-specific bash script generation

Usage:
    python3 createSideloader.py bundle.swbn --platform windows
    python3 createSideloader.py bundle.swbn --platform macos
"""

import os
import sys
import argparse
from windows_sideloader import WindowsSideloader
from macos_sideloader import MacOSSideloader

IWA_APP_NAME = "DOORKNOB"



def main():
    parser = argparse.ArgumentParser(description='Generate platform-specific IWA sideloader scripts')
    parser.add_argument('bundle_path', help='Path to the .swbn bundle file')
    parser.add_argument('--output', help='Output path for the sideloader script')
    parser.add_argument('--appname', help='Override the default IWA app name (default: DOORKNOB)')
    parser.add_argument('--platform', choices=['windows', 'macos'], default='windows', 
                        help='Target platform for the sideloader (default: windows)')
    args = parser.parse_args()
    
    try:
        # Validate bundle path
        if not os.path.exists(args.bundle_path):
            raise FileNotFoundError(f"Bundle file not found: {args.bundle_path}")
        
        # Use provided app_name if available, otherwise use default
        app_name = args.appname if args.appname else IWA_APP_NAME
        
        # Generate default output path if not specified
        if not args.output:
            bundle_name = os.path.splitext(os.path.basename(args.bundle_path))[0]
            extension = ".ps1" if args.platform == "windows" else ".sh"
            args.output = f"{bundle_name}-sideloader-{args.platform}{extension}"
        
        # Create the appropriate sideloader instance
        if args.platform == "windows":
            sideloader = WindowsSideloader(args.bundle_path, app_name)
        else:  # macos
            sideloader = MacOSSideloader(args.bundle_path, app_name)
        
        # Generate the script
        sideloader.generate_script(args.output)
        
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main() 