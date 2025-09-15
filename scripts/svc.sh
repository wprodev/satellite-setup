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

# Remote services configuration
WAKE_SERVICE_TYPE=$(jq -r '.services.wake_service_type // "local"' "$CONFIG_FILE")
REMOTE_WAKE_HOST=$(jq -r '.services.remote_wake_host // ""' "$CONFIG_FILE")
REMOTE_WAKE_PORT=$(jq -r '.services.remote_wake_port // "10400"' "$CONFIG_FILE")

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
echo "  Wake Service: $WAKE_SERVICE_TYPE"
if [ "$WAKE_SERVICE_TYPE" = "remote" ]; then
    echo "  Remote Wake: $REMOTE_WAKE_HOST:$REMOTE_WAKE_PORT"
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

# Determine wake word service URI
if [ "$WAKE_SERVICE_TYPE" = "remote" ]; then
    WAKE_URI="tcp://$REMOTE_WAKE_HOST:$REMOTE_WAKE_PORT"
    echo "Using remote wake word service: $WAKE_URI"
    
    # Test connection to remote wake word service
    echo "Testing connection to remote wake word service..."
    if timeout 5 bash -c "</dev/tcp/$REMOTE_WAKE_HOST/$REMOTE_WAKE_PORT" 2>/dev/null; then
        echo "✓ Connection to remote wake word service successful!"
    else
        echo "✗ Warning: Cannot connect to remote wake word service at $REMOTE_WAKE_HOST:$REMOTE_WAKE_PORT"
        echo "  Make sure your Wyoming OpenWakeWord service is running on the remote server."
        read -p "Continue anyway? [y/N]: " CONTINUE_ANYWAY
        if [[ ! $CONTINUE_ANYWAY =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled."
            exit 1
        fi
    fi
else
    WAKE_URI="tcp://127.0.0.1:$WAKEWORD_PORT"
    echo "Using local wake word service: $WAKE_URI"
fi

# Build Wyoming Satellite command with fixed escaping
SATELLITE_CMD="$USER_HOME/wyoming-satellite/script/run \\
    --name '$SATELLITE_NAME' \\
    --uri 'tcp://0.0.0.0:$SATELLITE_PORT' \\
    --mic-command 'arecord -D $MIC_DEVICE -r $MIC_RATE -c 1 -f S16_LE -t raw --buffer-size=4096' \\
    --snd-command 'aplay -D $SPEAKER_DEVICE -r $SPEAKER_RATE -c 1 -f S16_LE -t raw' \\
    --wake-uri '$WAKE_URI' \\
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

# Create services based on wake word service type
if [ "$WAKE_SERVICE_TYPE" = "local" ]; then
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

    # Create Wyoming Satellite service with local wake word dependency
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

    echo "Created local wake word and satellite services."
    SERVICES_TO_ENABLE="$WAKEWORD_SERVICE $SATELLITE_SERVICE"
    SERVICES_TO_START="$WAKEWORD_SERVICE $SATELLITE_SERVICE"
    SERVICES_TO_VALIDATE="$WAKEWORD_SERVICE $SATELLITE_SERVICE"
else
    # Create Wyoming Satellite service without local wake word dependency
    sudo tee "/etc/systemd/system/${SATELLITE_SERVICE}.service" > /dev/null <<EOF_SERVICE
[Unit]
Description=Wyoming Satellite ($CONFIG_NAME)
After=network-online.target
Wants=network-online.target

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

    echo "Created satellite service for remote wake word."
    SERVICES_TO_ENABLE="$SATELLITE_SERVICE"
    SERVICES_TO_START="$SATELLITE_SERVICE"
    SERVICES_TO_VALIDATE="$SATELLITE_SERVICE"
fi

echo "Services created successfully."

# Validate service files
echo "Validating service files..."
for service in $SERVICES_TO_VALIDATE; do
    if ! systemd-analyze verify "/etc/systemd/system/${service}.service" 2>/dev/null; then
        echo "Warning: $service service file may have issues"
    fi
done

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
for service in $SERVICES_TO_ENABLE; do
    sudo systemctl enable "${service}.service"
done

echo ""
echo "==========================================="
echo "Deployment Complete!"
echo "==========================================="
echo ""
echo "Configuration: $CONFIG_NAME"
if [ "$WAKE_SERVICE_TYPE" = "local" ]; then
    echo "Services: $WAKEWORD_SERVICE, $SATELLITE_SERVICE"
    echo "Ports: Satellite=$SATELLITE_PORT, Wake Word=$WAKEWORD_PORT"
else
    echo "Services: $SATELLITE_SERVICE"
    echo "Ports: Satellite=$SATELLITE_PORT"
    echo "Remote Wake: $REMOTE_WAKE_HOST:$REMOTE_WAKE_PORT"
fi
echo "Config file: $CONFIG_FILE"
echo ""
echo "Management commands:"
echo "  Start:   sudo systemctl start $SERVICES_TO_START"
echo "  Stop:    sudo systemctl stop $SERVICES_TO_START"
echo "  Status:  sudo systemctl status $SERVICES_TO_START"
echo "  Logs:    journalctl -u $SATELLITE_SERVICE -f"
echo ""
echo "Use 'bash manager.sh' for interactive service management"
echo ""

read -p "Start services now? [y/N]: " START_NOW
if [[ $START_NOW =~ ^[Yy]$ ]]; then
    echo "Starting services..."
    for service in $SERVICES_TO_START; do
        sudo systemctl start "$service"
        if [ "$service" = "$WAKEWORD_SERVICE" ]; then
            sleep 2  # Wait for wake word service to be ready
        fi
    done
    
    echo ""
    echo "Service status:"
    for service in $SERVICES_TO_START; do
        if sudo systemctl is-active "$service" >/dev/null 2>&1; then
            echo "  ✓ $service: active"
        else
            echo "  ✗ $service: failed"
        fi
    done
    
    echo ""
    echo "Monitor logs with: journalctl -u $SATELLITE_SERVICE -f"
fi
