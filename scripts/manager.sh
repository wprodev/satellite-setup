#!/bin/bash
# Wyoming Satellite Manager - Master Control Script
# Run with: bash satellite-manager.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME=$(eval echo "~$(whoami)")
CONFIG_DIR="$USER_HOME/wyoming-configs"

echo "==========================================="
echo "Wyoming Satellite Manager"
echo "==========================================="
echo ""
echo "Available actions:"
echo "1) Install dependencies (first time setup)"
echo "2) Create/modify configuration"
echo "3) Deploy configuration to services"
echo "4) List configurations"
echo "5) Show current service status"
echo "6) View configuration details"
echo "7) Remove configuration"
echo "8) Service management (start/stop/restart)"
echo ""

read -p "Choose action [1-8]: " ACTION

case $ACTION in
    1)
        echo ""
        echo "=== Installing Dependencies ==="
        bash "$SCRIPT_DIR/satellite-install.sh"
        ;;
    2)
        echo ""
        echo "=== Configuration Management ==="
        read -p "Enter configuration name (or press Enter to see list): " CONFIG_NAME
        bash "$SCRIPT_DIR/satellite-config.sh" "$CONFIG_NAME"
        ;;
    3)
        echo ""
        echo "=== Service Deployment ==="
        read -p "Enter configuration name to deploy (or press Enter to see list): " CONFIG_NAME
        bash "$SCRIPT_DIR/satellite-run.sh" "$CONFIG_NAME"
        ;;
    4)
        echo ""
        echo "=== Available Configurations ==="
        if [ -d "$CONFIG_DIR" ]; then
            ls -1 "$CONFIG_DIR"/*.json 2>/dev/null | while read -r config_file; do
                if [ -f "$config_file" ]; then
                    config_name=$(basename "$config_file" .json)
                    satellite_name=$(jq -r '.satellite_name // "unknown"' "$config_file")
                    created_date=$(jq -r '.metadata.created_date // "unknown"' "$config_file")
                    echo "  $config_name"
                    echo "    Satellite: $satellite_name"
                    echo "    Created: $created_date"
                    echo ""
                fi
            done || echo "  (no configurations found)"
        else
            echo "  (no configurations found)"
        fi
        ;;
    5)
        echo ""
        echo "=== Current Service Status ==="
        if systemctl list-unit-files | grep -q wyoming-; then
            echo "Service Status:"
            systemctl is-active wyoming-openwakeword 2>/dev/null && \
                echo "  ✓ wyoming-openwakeword: $(systemctl is-active wyoming-openwakeword)" || \
                echo "  ✗ wyoming-openwakeword: $(systemctl is-active wyoming-openwakeword 2>/dev/null || echo 'not found')"
            systemctl is-active wyoming-satellite 2>/dev/null && \
                echo "  ✓ wyoming-satellite: $(systemctl is-active wyoming-satellite)" || \
                echo "  ✗ wyoming-satellite: $(systemctl is-active wyoming-satellite 2>/dev/null || echo 'not found')"
            
            if [ -f "$USER_HOME/.wyoming-satellite/current-config.json" ]; then
                echo ""
                echo "Active Configuration:"
                current_config=$(jq -r '.config_name // "unknown"' "$USER_HOME/.wyoming-satellite/current-config.json")
                satellite_name=$(jq -r '.satellite_name // "unknown"' "$USER_HOME/.wyoming-satellite/current-config.json")
                echo "  Config: $current_config"
                echo "  Satellite: $satellite_name"
            fi
        else
            echo "  No Wyoming services found"
        fi
        ;;
    6)
        echo ""
        echo "=== Configuration Details ==="
        if [ -d "$CONFIG_DIR" ]; then
            echo "Available configurations:"
            ls -1 "$CONFIG_DIR"/*.json 2>/dev/null | xargs -n1 basename -s .json | sed 's/^/  /' || echo "  (none)"
            echo ""
        fi
        read -p "Enter configuration name to view: " VIEW_CONFIG
        if [ -n "$VIEW_CONFIG" ] && [ -f "$CONFIG_DIR/${VIEW_CONFIG}.json" ]; then
            echo ""
            echo "Configuration: $VIEW_CONFIG"
            echo "============================================"
            jq -r '
                "Satellite Name: " + (.satellite_name // "unknown") + "\n" +
                "Wake Word: " + (.wake_word // "unknown") + "\n" +
                "Audio Device (Mic): " + (.audio.mic_device // "unknown") + " @ " + (.audio.mic_rate // "unknown") + "Hz\n" +
                "Audio Device (Speaker): " + (.audio.speaker_device // "unknown") + " @ " + (.audio.speaker_rate // "unknown") + "Hz\n" +
                "Wake Sound: " + (.sounds.wake_sound // "none") + "\n" +
                "Done Sound: " + (.sounds.done_sound // "none") + "\n" +
                "Created: " + (.metadata.created_date // "unknown") + "\n" +
                "Updated: " + (.metadata.updated_date // "unknown")
            ' "$CONFIG_DIR/${VIEW_CONFIG}.json"
        else
            echo "Configuration not found: $VIEW_CONFIG"
        fi
        ;;
    7)
        echo ""
        echo "=== Remove Configuration ==="
        if [ -d "$CONFIG_DIR" ]; then
            echo "Available configurations:"
            ls -1 "$CONFIG_DIR"/*.json 2>/dev/null | xargs -n1 basename -s .json | sed 's/^/  /' || echo "  (none)"
            echo ""
        fi
        read -p "Enter configuration name to remove: " REMOVE_CONFIG
        if [ -n "$REMOVE_CONFIG" ] && [ -f "$CONFIG_DIR/${REMOVE_CONFIG}.json" ]; then
            echo "Configuration to remove: $REMOVE_CONFIG"
            jq -r '"Satellite: " + (.satellite_name // "unknown")' "$CONFIG_DIR/${REMOVE_CONFIG}.json"
            echo ""
            read -p "Are you sure you want to remove this configuration? [y/N]: " CONFIRM_REMOVE
            if [[ $CONFIRM_REMOVE =~ ^[Yy]$ ]]; then
                # Remove config file
                rm "$CONFIG_DIR/${REMOVE_CONFIG}.json"
                
                # Remove associated sound files
                rm -f "$USER_HOME/sounds/${REMOVE_CONFIG}_awake.wav"
                rm -f "$USER_HOME/sounds/${REMOVE_CONFIG}_done.wav"
                
                echo "Configuration '$REMOVE_CONFIG' removed."
                
                # Check if this was the active configuration
                if [ -f "$USER_HOME/.wyoming-satellite/current-config.json" ]; then
                    current_config=$(jq -r '.config_name // "unknown"' "$USER_HOME/.wyoming-satellite/current-config.json" 2>/dev/null || echo "unknown")
                    if [ "$current_config" = "$REMOVE_CONFIG" ]; then
                        echo "Warning: This was the active configuration. Services may need to be reconfigured."
                    fi
                fi
            else
                echo "Removal cancelled."
            fi
        else
            echo "Configuration not found: $REMOVE_CONFIG"
        fi
        ;;
    8)
        echo ""
        echo "=== Service Management ==="
        echo "1) Start services"
        echo "2) Stop services"
        echo "3) Restart services"
        echo "4) View service logs"
        echo ""
        read -p "Choose service action [1-4]: " SERVICE_ACTION
        
        case $SERVICE_ACTION in
            1)
                echo "Starting Wyoming services..."
                sudo systemctl start wyoming-openwakeword wyoming-satellite
                echo "Services started."
                ;;
            2)
                echo "Stopping Wyoming services..."
                sudo systemctl stop wyoming-satellite wyoming-openwakeword
                echo "Services stopped."
                ;;
            3)
                echo "Restarting Wyoming services..."
                sudo systemctl restart wyoming-openwakeword wyoming-satellite
                echo "Services restarted."
                ;;
            4)
                echo "Service logs (press Ctrl+C to exit):"
                echo ""
                journalctl -u wyoming-satellite -u wyoming-openwakeword -f
                ;;
            *)
                echo "Invalid service action."
                ;;
        esac
        ;;
    *)
        echo "Invalid action."
        exit 1
        ;;
esac

echo ""
echo "Action completed."
