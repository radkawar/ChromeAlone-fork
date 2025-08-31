#!/usr/bin/env python3
r"""
Chrome Extension Sideloader Builder

This script creates a self-contained script that embeds extension content
and optionally a native messaging host, then deploys them to the specified location.

Supports both Windows (PowerShell) and macOS (Bash) targets.

Usage:
    python build_sideloader.py <extension_folder> <install_path> [--os {windows,macos}]

Examples:
    python build_sideloader.py ./myextension "%LOCALAPPDATA%\Google\com.chrome.alone" --os windows
    python build_sideloader.py ./myextension "$HOME/Library/Application Support/Google/myextension" --os macos
"""

import os
import sys
import argparse
from pathlib import Path

from windows_extension_builder import WindowsExtensionBuilder
from macos_extension_builder import MacOSExtensionBuilder


def get_default_install_path(os_target, extension_name):
    """Get default install path for the target OS."""
    if os_target == "windows":
        return f"%LOCALAPPDATA%\\Google\\Chrome\\User Data\\Default\\Extensions\\{extension_name}"
    elif os_target == "macos":
        return f"$HOME/Library/Application Support/Google/{extension_name}"
    else:
        raise ValueError(f"Unsupported OS target: {os_target}")


def create_builder(os_target, extension_folder, install_path, output_path=None):
    """Create the appropriate builder for the target OS."""
    if os_target == "windows":
        return WindowsExtensionBuilder(extension_folder, install_path, output_path)
    elif os_target == "macos":
        return MacOSExtensionBuilder(extension_folder, install_path, output_path)
    else:
        raise ValueError(f"Unsupported OS target: {os_target}")


def main():
    parser = argparse.ArgumentParser(
        description="Build a Chrome Extension Sideloader script for Windows or macOS",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument(
        "extension_folder",
        help="Path to the extension folder to deploy"
    )
    
    parser.add_argument(
        "install_path",
        nargs="?",
        help="Installation path for the extension (can include environment variables). If not provided, uses OS-appropriate default."
    )
    
    parser.add_argument(
        "--os", "--target-os",
        dest="os_target",
        choices=["windows", "macos"],
        default="windows",
        help="Target operating system (default: windows)"
    )
    
    parser.add_argument(
        "-o", "--output",
        help="Output file path (default: <extension_name>_sideloader.<ext>)"
    )
    
    args = parser.parse_args()
    
    # Determine install path
    extension_name = Path(args.extension_folder).name
    if args.install_path:
        install_path = args.install_path
    else:
        install_path = get_default_install_path(args.os_target, extension_name)
        print(f"Using default install path for {args.os_target}: {install_path}")
    
    try:
        # Create appropriate builder
        builder = create_builder(args.os_target, args.extension_folder, install_path, args.output)
        
        # Build the sideloader script
        output_file = builder.build_sideloader_script()
        
        print(f"\n🎉 Build completed successfully!")
        print(f"📄 Generated: {output_file}")
        print(f"🎯 Target OS: {args.os_target}")
        
        if args.os_target == "windows":
            print(f"\nTo deploy the extension, run:")
            print(f"  powershell -ExecutionPolicy Bypass -File {output_file}")
        elif args.os_target == "macos":
            print(f"\nTo deploy the extension, run:")
            print(f"  chmod +x {output_file}")
            print(f"  ./{output_file}")
        
    except Exception as e:
        print(f"❌ Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
