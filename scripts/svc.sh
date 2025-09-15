#!/bin/bash
# Wyoming Satellite Service Deployment
# Run with: bash satellite-run.sh [config_name]

set -e

# Get current user info
CURRENT_USER=$(whoami)
USER_HOME=$(eval echo "~$CURRENT_USER")
CONFIG_DIR="$USER_HOME/wyoming-configs"

# Configuration selection
CONFIG_NAME="${1}"
if [ -z "$CONFIG_NAME" ]; then
    echo "Available configurations:"
    ls -1 "$CONFIG_DIR"/*.json 2>/dev/null | xargs -n1 basename -s .json | sed 's/^/  /' || {
        echo "  (no configurations found)"
        echo ""
        echo "Please run 'bash satellite-config.sh' first to create a configuration"
        exit 1
    }
    echo ""
    read -p "Enter configuration name to deploy: " CONFIG_NAME
fi

CONFIG_FILE="$CONFIG_DIR/${CONFIG_NAME}.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration '$CONFIG_NAME' not found: $CONFIG_FILE"
    echo "Available configurations:"
    ls -1 "$CONFIG_DIR"/*.json 2>/dev/null | xargs -n1 basename -s .json | sed 's/^/  /' || echo "  (none)"
    exit 1
fi

echo "==========================================="
echo "Wyoming Satellite Service Deployment"
echo "==========================================="
echo "Configuration: $CONFIG_NAME"
echo "Config file: $CONFIG_FILE"
echo ""

# Load configuration
SATELLITE_NAME=$(jq -r '.satellite_name' "$CONFIG_FILE")
WAKE_WORD=$(jq -r '.wake_word' "$CONFIG_FILE")
MIC_DEVICE=$(jq -r '.audio.mic_device' "$CONFIG_FILE")
SPEAKER_DEVICE=$(jq -r '.audio.speaker_device' "$CONFIG_FILE")
MIC_RATE=$(jq -r '.audio.mic_rate' "$CONFIG_FILE")
SPEAKER_RATE=$(jq -r '.audio.speaker_rate' "$CONFIG_FILE")
MIC_AUTO_GAIN=$(jq -r '.audio.mic_auto_gain // ""' "$CONFIG_FILE")
MIC_NOISE_SUPPRESSION=$(jq -r '.audio.mic_noise_suppression // ""' "$CONFIG_FILE")
DEBUG_MODE=$(jq -r '.debug_mode // false' "$CONFIG_FILE")
WAKE_SOUND_PATH=$(jq -r '.sounds.wake_sound // ""' "$CONFIG_FILE")
DONE_SOUND_PATH=$(jq -r '.sounds.done_sound // ""' "$CONFIG_FILE")

echo "Loaded configuration:"
echo "  Satellite Name: $SATELLITE_NAME"
echo "  Wake Word: $WAKE_WORD"
echo "  Microphone: $MIC_DEVICE @ ${MIC_RATE}Hz"
echo "  Speaker: $SPEAKER_DEVICE @ ${SPEAKER_RATE}Hz"
if [ -n "$MIC_AUTO_GAIN" ]; then
    echo "  Mic Auto-Gain: ${MIC_AUTO_GAIN} dbFS"
else
    echo "  Mic Auto-Gain: disabled"
fi
if [ -n "$MIC_NOISE_SUPPRESSION" ]; then
    echo "  Noise Suppression: ${MIC_NOISE_SUPPRESSION}"
else
    echo "  Noise Suppression: disabled"
fi
echo "  Debug Mode: $DEBUG_MODE"
echo "  Wake Sound: ${WAKE_SOUND_PATH:-none}"
echo "  Done Sound: ${DONE_SOUND_PATH:-none}"
echo ""

# Port management functions
check_port_available() {
    local port=$1
    if ss -tuln 2>/dev/null | grep -q ":$port " || netstat -ln 2>/dev/null | grep -q ":$port "; then
        return 1  # Port is in use
    fi
    return 0  # Port is available
}

find_available_port() {
    local base_port=$1
    local port=$base_port
    while ! check_port_available $port; do
        port=$((port + 1))
    done
    echo $port
}

check_service_exists() {
    local service_name=$1
    if systemctl list-unit-files 2>/dev/null | grep -q "^${service_name}\.service"; then
        return 0
    fi
    return 1
}

# Service names for multi-satellite support
SATELLITE_SERVICE="wyoming-satellite-${CONFIG_NAME}"
WAKEWORD_SERVICE="wyoming-openwakeword-${CONFIG_NAME}"

# Check for existing services with this config name
if check_service_exists "$SATELLITE_SERVICE" || check_service_exists "$WAKEWORD_SERVICE"; then
    echo "Services for configuration '$CONFIG_NAME' already exist:"
    check_service_exists "$SATELLITE_SERVICE" && echo "  - $SATELLITE_SERVICE"
    check_service_exists "$WAKEWORD_SERVICE" && echo "  - $WAKEWORD_SERVICE"
    echo ""
    
    read -p "Replace existing services? [y/N]: " REPLACE_SERVICES
    if [[ $REPLACE_SERVICES =~ ^[Yy]$ ]]; then
        echo "Stopping and removing existing services..."
        sudo systemctl stop "$SATELLITE_SERVICE" "$WAKEWORD_SERVICE" 2>/dev/null || true
        sudo systemctl disable "$SATELLITE_SERVICE" "$WAKEWORD_SERVICE" 2>/dev/null || true
        echo "Existing services stopped and disabled."
    else
        echo "Deployment cancelled."
        exit 0
    fi
fi

# Port assignment with user choice
DESIRED_SATELLITE_PORT=10700
DESIRED_WAKEWORD_PORT=10400

# Check if desired ports are available
SATELLITE_PORT_AVAILABLE=true
WAKEWORD_PORT_AVAILABLE=true

if ! check_port_available $DESIRED_SATELLITE_PORT; then
    SATELLITE_PORT_AVAILABLE=false
fi

if ! check_port_available $DESIRED_WAKEWORD_PORT; then
    WAKEWORD_PORT_AVAILABLE=false
fi

# Handle port conflicts
if [ "$SATELLITE_PORT_AVAILABLE" = false ] || [ "$WAKEWORD_PORT_AVAILABLE" = false ]; then
    echo "Port conflict detected:"
    if [ "$SATELLITE_PORT_AVAILABLE" = false ]; then
        echo "  - Satellite port $DESIRED_SATELLITE_PORT is already in use"
        echo "    Process using port: $(ss -tulpn 2>/dev/null | grep ":$DESIRED_SATELLITE_PORT " | head -1 || echo "unknown")"
    fi
    if [ "$WAKEWORD_PORT_AVAILABLE" = false ]; then
        echo "  - Wake word port $DESIRED_WAKEWORD_PORT is already in use"
        echo "    Process using port: $(ss -tulpn 2>/dev/null | grep ":$DESIRED_WAKEWORD_PORT " | head -1 || echo "unknown")"
    fi
    echo ""
    echo "Options:"
    echo "  1) Use alternative available ports (recommended)"
    echo "  2) Exit and investigate port conflicts manually"
    echo ""
    read -p "Choose option [1]: " PORT_CHOICE
    PORT_CHOICE=${PORT_CHOICE:-1}
    
    case $PORT_CHOICE in
        1)
            SATELLITE_PORT=$(find_available_port $DESIRED_SATELLITE_PORT)
            WAKEWORD_PORT=$(find_available_port $DESIRED_WAKEWORD_PORT)
            echo "Using alternative ports:"
            echo "  - Satellite: $SATELLITE_PORT"
            echo "  - Wake word: $WAKEWORD_PORT"
            ;;
        2)
            echo "Deployment cancelled. Please free up the required ports and try again."
            echo ""
            echo "To investigate port usage:"
            echo "  ss -tulpn | grep ':10700\\|:10400'"
            echo "  netstat -tulpn | grep ':10700\\|:10400'"
            exit 0
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
else
    SATELLITE_PORT=$DESIRED_SATELLITE_PORT
    WAKEWORD_PORT=$DESIRED_WAKEWORD_PORT
    echo "Using default ports:"
    echo "  - Satellite: $SATELLITE_PORT"
    echo "  - Wake word: $WAKEWORD_PORT"
fi

echo ""

# Update configuration with assigned ports
TEMP_CONFIG=$(mktemp)
jq --arg sat_port "$SATELLITE_PORT" --arg wake_port "$WAKEWORD_PORT" \
   '.assigned_ports = {satellite: ($sat_port | tonumber), wakeword: ($wake_port | tonumber)} | .metadata.updated_date = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
   "$CONFIG_FILE" > "$TEMP_CONFIG" && mv "$TEMP_CONFIG" "$CONFIG_FILE"

echo "Configuration updated with assigned ports."

# Build Wyoming Satellite command with fixed escaping
SATELLITE_CMD="$USER_HOME/wyoming-satellite/script/run \\
    --name '$SATELLITE_NAME' \\
    --uri 'tcp://0.0.0.0:$SATELLITE_PORT' \\
    --mic-command 'arecord -D $MIC_DEVICE -r $MIC_RATE -c 1 -f S16_LE -t raw' \\
    --snd-command 'aplay -D $SPEAKER_DEVICE -r $SPEAKER_RATE -c 1 -f S16_LE -t raw' \\
    --wake-uri 'tcp://127.0.0.1:$WAKEWORD_PORT' \\
    --wake-word-name '$WAKE_WORD'"

# Add advanced audio options if configured
if [ -n "$MIC_AUTO_GAIN" ]; then
    SATELLITE_CMD="$SATELLITE_CMD \\
    --mic-auto-gain $MIC_AUTO_GAIN"
fi

if [ -n "$MIC_NOISE_SUPPRESSION" ]; then
    SATELLITE_CMD="$SATELLITE_CMD \\
    --mic-noise-suppression $MIC_NOISE_SUPPRESSION"
fi

# Add sound options if they exist
if [ -n "$WAKE_SOUND_PATH" ] && [ -f "$WAKE_SOUND_PATH" ]; then
    SATELLITE_CMD="$SATELLITE_CMD \\
    --awake-wav $WAKE_SOUND_PATH"
fi

if [ -n "$DONE_SOUND_PATH" ] && [ -f "$DONE_SOUND_PATH" ]; then
    SATELLITE_CMD="$SATELLITE_CMD \\
    --done-wav $DONE_SOUND_PATH"
fi

# Add debug flag if enabled
if [ "$DEBUG_MODE" = "true" ]; then
    SATELLITE_CMD="$SATELLITE_CMD \\
    --debug"
fi

# Add VAD (Voice Activity Detection)
SATELLITE_CMD="$SATELLITE_CMD \\
    --vad"

echo "Creating systemd services..."

# Create OpenWakeWord service with unique name
sudo tee "/etc/systemd/system/${WAKEWORD_SERVICE}.service" > /dev/null <<EOF_SERVICE
[Unit]
Description=Wyoming OpenWakeWord ($CONFIG_NAME)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$USER_HOME/wyoming-openwakeword/script/run \\
    --uri 'tcp://0.0.0.0:$WAKEWORD_PORT' \\
    --preload-model '$WAKE_WORD' \\
    --debug
WorkingDirectory=$USER_HOME/wyoming-openwakeword
Restart=always
RestartSec=10
User=$CURRENT_USER
Environment=CONFIG_NAME=$CONFIG_NAME
Environment=CONFIG_FILE=$CONFIG_FILE

[Install]
WantedBy=default.target
EOF_SERVICE

# Create Wyoming Satellite service with unique name
sudo tee "/etc/systemd/system/${SATELLITE_SERVICE}.service" > /dev/null <<EOF_SERVICE
[Unit]
Description=Wyoming Satellite ($CONFIG_NAME)
After=network-online.target ${WAKEWORD_SERVICE}.service
Wants=network-online.target
Requires=${WAKEWORD_SERVICE}.service

[Service]
Type=simple
ExecStart=$SATELLITE_CMD
WorkingDirectory=$USER_HOME/wyoming-satellite
Restart=always
RestartSec=10
User=$CURRENT_USER
Environment=CONFIG_NAME=$CONFIG_NAME
Environment=CONFIG_FILE=$CONFIG_FILE

[Install]
WantedBy=default.target
EOF_SERVICE

echo "Services created successfully."

# Validate service files
echo "Validating service files..."
if ! systemd-analyze verify "/etc/systemd/system/${WAKEWORD_SERVICE}.service" 2>/dev/null; then
    echo "Warning: Wake word service file may have issues"
fi
if ! systemd-analyze verify "/etc/systemd/system/${SATELLITE_SERVICE}.service" 2>/dev/null; then
    echo "Warning: Satellite service file may have issues"
fi

# Set proper ownership for sound files
if [ -n "$WAKE_SOUND_PATH" ] && [ -f "$WAKE_SOUND_PATH" ]; then
    sudo chown "$CURRENT_USER:$CURRENT_USER" "$WAKE_SOUND_PATH"
fi
if [ -n "$DONE_SOUND_PATH" ] && [ -f "$DONE_SOUND_PATH" ]; then
    sudo chown "$CURRENT_USER:$CURRENT_USER" "$DONE_SOUND_PATH"
fi

# Reload systemd and enable services
echo "Enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable "${WAKEWORD_SERVICE}.service"
sudo systemctl enable "${SATELLITE_SERVICE}.service"

echo ""
echo "==========================================="
echo "Deployment Complete!"
echo "==========================================="
echo ""
echo "Configuration: $CONFIG_NAME"
echo "Services: $WAKEWORD_SERVICE, $SATELLITE_SERVICE"
echo "Ports: Satellite=$SATELLITE_PORT, Wake Word=$WAKEWORD_PORT"
echo "Config file: $CONFIG_FILE"
echo ""
echo "Management commands:"
echo "  Start:   sudo systemctl start $WAKEWORD_SERVICE $SATELLITE_SERVICE"
echo "  Stop:    sudo systemctl stop $SATELLITE_SERVICE $WAKEWORD_SERVICE"
echo "  Status:  sudo systemctl status $SATELLITE_SERVICE $WAKEWORD_SERVICE"
echo "  Logs:    journalctl -u $SATELLITE_SERVICE -f"
echo ""
echo "Use 'bash manager.sh' for interactive service management"
echo ""

read -p "Start services now? [y/N]: " START_NOW
if [[ $START_NOW =~ ^[Yy]$ ]]; then
    echo "Starting services..."
    sudo systemctl start "$WAKEWORD_SERVICE"
    sleep 2
    sudo systemctl start "$SATELLITE_SERVICE"
    
    echo ""
    echo "Service status:"
    sudo systemctl is-active "$WAKEWORD_SERVICE" && echo "  ✓ $WAKEWORD_SERVICE: active" || echo "  ✗ $WAKEWORD_SERVICE: failed"
    sudo systemctl is-active "$SATELLITE_SERVICE" && echo "  ✓ $SATELLITE_SERVICE: active" || echo "  ✗ $SATELLITE_SERVICE: failed"
    
    echo ""
    echo "Monitor logs with: journalctl -u $SATELLITE_SERVICE -f"
fi
