import os
from base_sideloader import BaseSideloader


class MacOSSideloader(BaseSideloader):
    """macOS-specific sideloader implementation using bash and osascript."""
    
    def get_platform_config(self):
        """Return macOS-specific configuration."""
        return {
            'chrome_paths': [
                "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            ],
            'base_data_dir': "$HOME/Library/Application Support",
            'chrome_profile_path': "Default",
            'iwa_path_separator': "/",
            'leveldb_path': "Default/Sync Data/LevelDB"
        }
    
    def generate_script(self, output_path):
        """Generate the macOS bash script sideloader."""
        config = self.get_platform_config()
        
        # Create the macOS shell script
        script = f'''#!/bin/bash

# Generated IWA Sideloader Script for macOS
# App ID: {self.app_id}
# App Name: {self.app_name}
# IWA Tab: {self.iwa_tab_url}
# IWA Folder: {self.iwa_folder_name}

set -e

export APP_NAME="{self.app_name}"

# Base64 encoded bundle data
BUNDLE_DATA="{self.bundle_data}"

# Function to find Chrome installation
find_chrome() {{
    local chrome_path="{config['chrome_paths'][0]}"
    if [[ -f "$chrome_path" ]]; then
        echo "$chrome_path"
        return 0
    fi
    
    echo "Error: Chrome not found at $chrome_path" >&2
    exit 1
}}

# CRC32C implementation ported from PowerShell
# Initialize CRC32C lookup table
init_crc32c_table() {{
    local polynomial=0x82F63B78
    local i j crc
    
    # Create lookup table array
    for ((i=0; i<256; i++)); do
        crc=$i
        for ((j=0; j<8; j++)); do
            if (( (crc & 1) == 1 )); then
                crc=$(( (crc >> 1) ^ polynomial ))
            else
                crc=$(( crc >> 1 ))
            fi
        done
        CRC32C_TABLE[$i]=$crc
    done
}}

# XOR operation for CRC32C (equivalent to PowerShell DoMath function)
do_xor() {{
    local val1=$1
    local val2=$2
    echo $(( val1 ^ val2 ))
}}

# Calculate CRC32C hash
get_crc32c() {{
    local hex_data="$1"
    local crc=0xFFFFFFFF
    local byte_val temp index shifted
    
    # Convert hex string to bytes and process each byte
    for ((i=0; i<${{#hex_data}}; i+=2)); do
        byte_val="0x${{hex_data:$i:2}}"
        temp=$(do_xor $crc $byte_val)
        index=$(( temp & 0xFF ))
        shifted=$(( crc >> 8 ))
        crc=$(do_xor ${{CRC32C_TABLE[$index]}} $shifted)
        crc=$(( crc & 0xFFFFFFFF ))
    done
    
    crc=$(do_xor $crc 0xFFFFFFFF)
    echo $crc
}}

# Mask CRC32C (equivalent to PowerShell Mask-CRC32C)
mask_crc32c() {{
    local crc=$1
    local K_MASK_DELTA=0xA282EAD8
    
    local right_shift=$(( crc >> 15 ))
    local left_shift=$(( (crc << 17) & 0xFFFFFFFF ))
    local rotated=$(( right_shift | left_shift ))
    
    local masked=$(( (rotated + K_MASK_DELTA) & 0xFFFFFFFF ))
    echo $masked
}}

# Convert uint32 to little-endian hex
to_little_endian_hex() {{
    local value=$1
    printf "%02x%02x%02x%02x" \\
        $(( value & 0xFF )) \\
        $(( (value >> 8) & 0xFF )) \\
        $(( (value >> 16) & 0xFF )) \\
        $(( (value >> 24) & 0xFF ))
}}

# Calculate LevelDB hash
calc_leveldb_hash() {{
    local data="$1"
    local crc32c_hash=$(get_crc32c "$data")
    local masked_crc32c=$(mask_crc32c $crc32c_hash)
    to_little_endian_hex $masked_crc32c
}}

# Convert integer to VarInt32 format
to_varint32() {{
    local value=$1
    local result=""
    local byte
    
    if [[ $value -eq 0 ]]; then
        echo "00"
        return
    fi
    
    while [[ $value -ne 0 ]]; do
        byte=$(( value & 0x7F ))
        value=$(( value >> 7 ))
        
        if [[ $value -ne 0 ]]; then
            byte=$(( byte | 0x80 ))
        fi
        
        result="$result$(printf "%02x" $byte)"
    done
    
    echo "$result"
}}

# Convert string to hex
string_to_hex() {{
    local str="$1"
    echo -n "$str" | xxd -p | tr -d '\\n'
}}

# Create complete LevelDB entry
create_leveldb_entry() {{
    local sequence_number=$1
    local key="$2"
    local value_hex="$3"
    
    # 1. Create Record Format Entry
    local key_hex=$(string_to_hex "$key")
    local key_length=$(to_varint32 ${{#key}})
    local value_length=$(to_varint32 $(( ${{#value_hex}} / 2 )))
    
    # Clean value hex (remove any spaces)
    local clean_value_hex=$(echo "$value_hex" | tr -d ' ')
    
    local record_entry="01${{key_length}}${{key_hex}}${{value_length}}${{clean_value_hex}}"
    
    # 2. Create Batch Header (8 bytes sequence + 4 bytes count)
    local seq_hex=$(printf "%016x" $sequence_number)
    # Convert to little-endian byte order
    local seq_le=""
    for ((i=14; i>=0; i-=2)); do
        seq_le="$seq_le${{seq_hex:$i:2}}"
    done
    local count_hex="01000000"  # 1 record in little-endian
    local batch_header="${{seq_le}}${{count_hex}}"
    
    # 3. Calculate LevelDB Hash
    local data_to_hash="01${{batch_header}}${{record_entry}}"
    local hash=$(calc_leveldb_hash "$data_to_hash")
    
    # 4. Calculate content length
    local content_length=$(( (${{#batch_header}} + ${{#record_entry}}) / 2 ))
    local length_hex_be=$(printf "%04x" $content_length)
    # Convert to little-endian
    local length_hex="${{length_hex_be:2:2}}${{length_hex_be:0:2}}"
    
    # 5. Combine all parts
    local final_hex="${{hash}}${{length_hex}}01${{batch_header}}${{record_entry}}"
    echo "$final_hex"
}}

# Write LevelDB entry to file
write_leveldb_entry() {{
    local log_file="$1"
    local key="$2"
    local value_hex="$3"
    local sequence_number="$4"
    
    local entry=$(create_leveldb_entry "$sequence_number" "$key" "$value_hex")
    
    # Convert hex to binary and append to log file
    echo -n "$entry" | xxd -r -p >> "$log_file"
}}

# Initialize CRC32C lookup table
declare -a CRC32C_TABLE
init_crc32c_table

# Set up paths
CHROME_PATH=$(find_chrome)
BASE_DATA_DIR="{config['base_data_dir']}"
USER_DATA_DIR="$BASE_DATA_DIR/$APP_NAME"
IWA_DIR="$USER_DATA_DIR/{config['chrome_profile_path']}/iwa/{self.iwa_folder_name}"
LEVELDB_DIR="$USER_DATA_DIR/{config['leveldb_path']}"

echo "Chrome found at: $CHROME_PATH"
echo "User data directory: $USER_DATA_DIR"

# Create necessary directories
mkdir -p "$LEVELDB_DIR"

# Initialize Chrome with IWA settings
LOCAL_STATE_FILE="$USER_DATA_DIR/Local State"

# Create Local State file if it doesn't exist
if [[ ! -f "$LOCAL_STATE_FILE" ]]; then
    cat > "$LOCAL_STATE_FILE" << 'EOF'
{{
    "browser": {{
        "default_browser_infobar_declined_count": 1,
        "default_browser_infobar_last_declined_time": 0,
        "enabled_labs_experiments": [
            "enable-isolated-web-app-dev-mode@1",
            "enable-isolated-web-apps@1"
        ],
        "first_run_finished": true
    }}
}}
EOF
else
    # Update existing Local State file using Python for JSON manipulation
    python3 -c "
import json
import sys

try:
    with open('$LOCAL_STATE_FILE', 'r') as f:
        data = json.load(f)
except:
    data = {{}}

if 'browser' not in data:
    data['browser'] = {{}}

data['browser']['enabled_labs_experiments'] = [
    'enable-isolated-web-app-dev-mode@1',
    'enable-isolated-web-apps@1'
]
data['browser']['first_run_finished'] = True

with open('$LOCAL_STATE_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
fi

echo "Chrome Local State configured for IWA support"

# Find the latest LevelDB log file
LEVELDB_LOG_FILE=$(ls -t "$LEVELDB_DIR"/*.log 2>/dev/null | head -n1)

if [[ -z "$LEVELDB_LOG_FILE" ]]; then
    # If no log file exists, start Chrome briefly to create the database structure
    echo "Initializing Chrome profile..."
    
    CHROME_ARGS=(
        --allow-no-sandbox-job
        --disable-3d-apis
        --disable-gpu
        --disable-d3d11
        --disable-accelerated-layers
        --disable-accelerated-plugins
        --disable-accelerated-2d-canvas
        --disable-deadline-scheduling
        --disable-ui-deadline-scheduling
        --user-data-dir="$USER_DATA_DIR"
        --profile-directory=Default
        --app-id={self.app_id}
    )

    # Start Chrome briefly in the background
    "$CHROME_PATH" "${{CHROME_ARGS[@]}}" --headless --disable-gpu --remote-debugging-port=9222 &
    CHROME_PID=$!
    
    # Wait for Chrome to initialize
    sleep 5
    
    # Kill Chrome
    kill $CHROME_PID 2>/dev/null || true
    wait $CHROME_PID 2>/dev/null || true
    
    # Wait for files to be written
    sleep 2
    
    # Find the log file again
    LEVELDB_LOG_FILE=$(ls -t "$LEVELDB_DIR"/*.log 2>/dev/null | head -n1)
fi

if [[ -n "$LEVELDB_LOG_FILE" ]]; then
    echo "Writing LevelDB entry to: $LEVELDB_LOG_FILE"
    write_leveldb_entry "$LEVELDB_LOG_FILE" "web_apps-dt-{self.app_id}" "{self.protobuf_hex}" 99
    echo "LevelDB entry written successfully"
else
    echo "Warning: Could not find or create LevelDB log file"
fi

# Write bundle data to IWA directory
mkdir -p "$IWA_DIR"
echo -n "$BUNDLE_DATA" | base64 -d > "$IWA_DIR/main.swbn"
echo "Bundle written to: $IWA_DIR/main.swbn"

# Create a simple start script for later use
START_SCRIPT="$USER_DATA_DIR/start_iwa.sh"
cat > "$START_SCRIPT" << 'STARTEOF'
#!/bin/bash
CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
USER_DATA_DIR="$HOME/Library/Application Support/{self.app_name}"

# Use an array for proper handling of spaces
CHROME_ARGS=(
    --allow-no-sandbox-job
    --disable-3d-apis
    --disable-gpu
    --disable-d3d11
    --disable-accelerated-layers
    --disable-accelerated-plugins
    --disable-accelerated-2d-canvas
    --disable-deadline-scheduling
    --disable-ui-deadline-scheduling
    --user-data-dir="$USER_DATA_DIR"
    --profile-directory=Default
)

nohup "$CHROME_PATH" "${{CHROME_ARGS[@]}}" --headless --remote-debugging-port=9222 > /dev/null 2>&1 &
echo "IWA launched with PID: $!"
sleep 10
curl -s -X PUT "http://localhost:9222/json/new?{self.iwa_tab_url}"
STARTEOF


chmod +x "$START_SCRIPT"
echo "Start script created at: $START_SCRIPT"

# Setup persistence using launchd (macOS equivalent of Windows startup)
echo "Setting up persistence..."

PLIST_FILE="$HOME/Library/LaunchAgents/com.{self.app_name.lower()}.iwa.plist"
cat > "$PLIST_FILE" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.{self.app_name.lower()}.iwa</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$START_SCRIPT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>LSUIElement</key>
    <true/>
    <key>LSBackgroundOnly</key>
    <true/>
</dict>
</plist>
PLISTEOF

# Load the launch agent
launchctl load "$PLIST_FILE" 2>/dev/null || true

echo "Persistence configured using launchd"
echo "Sideloader setup completed successfully!"
'''
        
        with open(output_path, 'w') as f:
            f.write(script)
        
        # Make the script executable
        os.chmod(output_path, 0o755)
        
        print(f"\nGenerated macOS sideloader script: {output_path}")
        print("Script has been made executable")
