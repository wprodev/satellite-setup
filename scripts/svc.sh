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

# Check for existing services
if systemctl is-active --quiet wyoming-satellite || systemctl is-active --quiet wyoming-openwakeword; then
    echo "Existing Wyoming services detected:"
    systemctl is-active wyoming-satellite && echo "  - wyoming-satellite: $(systemctl is-active wyoming-satellite)"
    systemctl is-active wyoming-openwakeword && echo "  - wyoming-openwakeword: $(systemctl is-active wyoming-openwakeword)"
    echo ""
    
    read -p "Stop existing services and replace with new configuration? [y/N]: " REPLACE_SERVICES
    if [[ $REPLACE_SERVICES =~ ^[Yy]$ ]]; then
        echo "Stopping existing services..."
        sudo systemctl stop wyoming-satellite wyoming-openwakeword 2>/dev/null || true
        echo "Services stopped."
    else
        echo "Deployment cancelled."
        exit 0
    fi
fi

# Create service configuration directory
SERVICE_CONFIG_DIR="$USER_HOME/.wyoming-satellite"
mkdir -p "$SERVICE_CONFIG_DIR"

# Copy configuration to system directory
cp "$CONFIG_FILE" "$SERVICE_CONFIG_DIR/current-config.json"
echo "Configuration copied to: $SERVICE_CONFIG_DIR/current-config.json"

# Build Wyoming Satellite command
SATELLITE_CMD="$USER_HOME/wyoming-satellite/script/run \\\\
    --name '$SATELLITE_NAME' \\\\
    --uri 'tcp://0.0.0.0:10700' \\\\
    --mic-command 'arecord -D $MIC_DEVICE -r $MIC_RATE -c 1 -f S16_LE -t raw' \\\\
    --snd-command 'aplay -D $SPEAKER_DEVICE -r $SPEAKER_RATE -c 1 -f S16_LE -t raw' \\\\
    --wake-uri 'tcp://127.0.0.1:10400' \\\\
    --wake-word-name '$WAKE_WORD'"

# Add advanced audio options if configured
if [ -n "$MIC_AUTO_GAIN" ]; then
    SATELLITE_CMD="$SATELLITE_CMD \\\\
    --mic-auto-gain $MIC_AUTO_GAIN"
fi

if [ -n "$MIC_NOISE_SUPPRESSION" ]; then
    SATELLITE_CMD="$SATELLITE_CMD \\\\
    --mic-noise-suppression $MIC_NOISE_SUPPRESSION"
fi

# Add sound options if they exist
if [ -n "$WAKE_SOUND_PATH" ] && [ -f "$WAKE_SOUND_PATH" ]; then
    SATELLITE_CMD="$SATELLITE_CMD \\\\
    --awake-wav $WAKE_SOUND_PATH"
fi

if [ -n "$DONE_SOUND_PATH" ] && [ -f "$DONE_SOUND_PATH" ]; then
    SATELLITE_CMD="$SATELLITE_CMD \\\\
    --done-wav $DONE_SOUND_PATH"
fi

# Add debug flag if enabled
if [ "$DEBUG_MODE" = "true" ]; then
    SATELLITE_CMD="$SATELLITE_CMD \\\\
    --debug"
fi

echo "Creating systemd services..."

# Create OpenWakeWord service
sudo tee /etc/systemd/system/wyoming-openwakeword.service > /dev/null <<EOF_SERVICE
[Unit]
Description=Wyoming OpenWakeWord ($CONFIG_NAME)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$USER_HOME/wyoming-openwakeword/script/run \\
    --uri 'tcp://0.0.0.0:10400' \\
    --preload-model '$WAKE_WORD' \\
    --debug
WorkingDirectory=$USER_HOME/wyoming-openwakeword
Restart=always
RestartSec=10
User=$CURRENT_USER
Environment=CONFIG_NAME=$CONFIG_NAME
Environment=CONFIG_FILE=$SERVICE_CONFIG_DIR/current-config.json

[Install]
WantedBy=default.target
EOF_SERVICE

# Create Wyoming Satellite service
sudo tee /etc/systemd/system/wyoming-satellite.service > /dev/null <<EOF_SERVICE
[Unit]
Description=Wyoming Satellite ($CONFIG_NAME)
After=network-online.target wyoming-openwakeword.service
Wants=network-online.target
Requires=wyoming-openwakeword.service

[Service]
Type=simple
ExecStart=$SATELLITE_CMD
WorkingDirectory=$USER_HOME/wyoming-satellite
Restart=always
RestartSec=10
User=$CURRENT_USER
Environment=CONFIG_NAME=$CONFIG_NAME
Environment=CONFIG_FILE=$SERVICE_CONFIG_DIR/current-config.json

[Install]
WantedBy=default.target
EOF_SERVICE

echo "Services created successfully."

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
sudo systemctl enable wyoming-openwakeword.service
sudo systemctl enable wyoming-satellite.service

echo ""
echo "==========================================="
echo "Deployment Complete!"
echo "==========================================="
echo ""
echo "Configuration: $CONFIG_NAME"
echo "Services: wyoming-openwakeword, wyoming-satellite"
echo "Config stored in: $SERVICE_CONFIG_DIR/current-config.json"
echo ""
echo "Management commands:"
echo "  Start:   sudo systemctl start wyoming-openwakeword wyoming-satellite"
echo "  Stop:    sudo systemctl stop wyoming-satellite wyoming-openwakeword"
echo "  Status:  sudo systemctl status wyoming-satellite wyoming-openwakeword"
echo "  Logs:    journalctl -u wyoming-satellite -f"
echo ""

read -p "Start services now? [y/N]: " START_NOW
if [[ $START_NOW =~ ^[Yy]$ ]]; then
    echo "Starting services..."
    sudo systemctl start wyoming-openwakeword
    sleep 2
    sudo systemctl start wyoming-satellite
    
    echo ""
    echo "Service status:"
    sudo systemctl is-active wyoming-openwakeword && echo "  ✓ wyoming-openwakeword: active" || echo "  ✗ wyoming-openwakeword: failed"
    sudo systemctl is-active wyoming-satellite && echo "  ✓ wyoming-satellite: active" || echo "  ✗ wyoming-satellite: failed"
    
    echo ""
    echo "Monitor logs with: journalctl -u wyoming-satellite -f"
fi
