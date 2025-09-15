#!/bin/bash
# Wyoming Satellite Service Manager
# Interactive management for multiple Wyoming satellite services

set -e

# Get current user info
CURRENT_USER=$(whoami)
USER_HOME=$(eval echo "~$CURRENT_USER")
CONFIG_DIR="$USER_HOME/wyoming-configs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to get service status with color
get_service_status() {
    local service_name=$1
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        echo -e "${GREEN}ACTIVE${NC}"
    elif systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        if systemctl is-failed --quiet "$service_name" 2>/dev/null; then
            echo -e "${RED}FAILED${NC}"
        else
            echo -e "${YELLOW}STOPPED${NC}"
        fi
    else
        echo -e "${RED}DISABLED${NC}"
    fi
}

# Function to get configuration info
get_config_info() {
    local config_name=$1
    local config_file="$CONFIG_DIR/${config_name}.json"
    
    if [ -f "$config_file" ]; then
        local wake_word=$(jq -r '.wake_word // "unknown"' "$config_file" 2>/dev/null)
        local sat_port=$(jq -r '.assigned_ports.satellite // "unknown"' "$config_file" 2>/dev/null)
        local wake_port=$(jq -r '.assigned_ports.wakeword // "unknown"' "$config_file" 2>/dev/null)
        echo "$wake_word @ $sat_port/$wake_port"
    else
        echo "config missing"
    fi
}

# Function to discover Wyoming satellite services
discover_satellites() {
    local satellites=()
    local config_names=()
    
    # Find all wyoming-satellite-* services
    for service_file in /etc/systemd/system/wyoming-satellite-*.service; do
        if [ -f "$service_file" ]; then
            local service_name=$(basename "$service_file" .service)
            local config_name=${service_name#wyoming-satellite-}
            satellites+=("$service_name")
            config_names+=("$config_name")
        fi
    done
    
    echo "${#satellites[@]}"
    printf '%s\n' "${satellites[@]}"
    printf '%s\n' "${config_names[@]}"
}

# Function to display satellite list
display_satellites() {
    echo ""
    echo -e "${BLUE}Wyoming Satellite Manager${NC}"
    echo "========================"
    echo ""
    
    # Get satellite info
    local discovery_output=$(discover_satellites)
    local lines=($discovery_output)
    local count=${lines[0]}
    
    if [ "$count" -eq 0 ]; then
        echo "No Wyoming satellite services found."
        echo ""
        echo "Use 'bash svc.sh [config_name]' to deploy a satellite service."
        return 1
    fi
    
    echo "Deployed Satellites:"
    
    # Parse discovery output
    local satellites=()
    local config_names=()
    for ((i=1; i<=count; i++)); do
        satellites+=("${lines[$i]}")
    done
    for ((i=count+1; i<=2*count; i++)); do
        config_names+=("${lines[$i]}")
    done
    
    # Display each satellite
    for ((i=0; i<count; i++)); do
        local satellite_service="${satellites[$i]}"
        local wakeword_service="wyoming-openwakeword-${config_names[$i]}"
        local config_name="${config_names[$i]}"
        
        local sat_status=$(get_service_status "$satellite_service")
        local wake_status=$(get_service_status "$wakeword_service")
        local config_info=$(get_config_info "$config_name")
        
        # Determine overall status
        local overall_status
        if [[ "$sat_status" == *"ACTIVE"* ]] && [[ "$wake_status" == *"ACTIVE"* ]]; then
            overall_status="${GREEN}ACTIVE${NC}"
        elif [[ "$sat_status" == *"FAILED"* ]] || [[ "$wake_status" == *"FAILED"* ]]; then
            overall_status="${RED}FAILED${NC}"
        else
            overall_status="${YELLOW}STOPPED${NC}"
        fi
        
        printf "  %d) %-12s [%b] - %s\n" $((i+1)) "$config_name" "$overall_status" "$config_info"
    done
    
    echo ""
    return 0
}

# Function to show service actions menu
show_actions_menu() {
    local config_name=$1
    local satellite_service="wyoming-satellite-${config_name}"
    local wakeword_service="wyoming-openwakeword-${config_name}"
    
    echo ""
    echo -e "${BLUE}Selected: $config_name${NC}"
    echo "Services: $satellite_service, $wakeword_service"
    echo ""
    
    # Show current status
    local sat_status=$(get_service_status "$satellite_service")
    local wake_status=$(get_service_status "$wakeword_service")
    echo "Current Status:"
    echo "  Satellite:  $sat_status"
    echo "  Wake Word:  $wake_status"
    echo ""
    
    echo "Actions:"
    echo "  s) Start services"
    echo "  t) Stop services"
    echo "  r) Restart services"
    echo "  e) Enable (auto-start)"
    echo "  d) Disable (no auto-start)"
    echo "  u) Uninstall services"
    echo "  v) View configuration"
    echo "  l) View logs"
    echo "  q) Back to main menu"
    echo ""
}

# Function to execute service action
execute_action() {
    local action=$1
    local config_name=$2
    local satellite_service="wyoming-satellite-${config_name}"
    local wakeword_service="wyoming-openwakeword-${config_name}"
    
    case $action in
        s)
            echo "Starting services..."
            sudo systemctl start "$wakeword_service" "$satellite_service"
            echo "Services started."
            ;;
        t)
            echo "Stopping services..."
            sudo systemctl stop "$satellite_service" "$wakeword_service"
            echo "Services stopped."
            ;;
        r)
            echo "Restarting services..."
            sudo systemctl restart "$wakeword_service"
            sleep 2
            sudo systemctl restart "$satellite_service"
            echo "Services restarted."
            ;;
        e)
            echo "Enabling services..."
            sudo systemctl enable "$wakeword_service" "$satellite_service"
            echo "Services enabled for auto-start."
            ;;
        d)
            echo "Disabling services..."
            sudo systemctl disable "$satellite_service" "$wakeword_service"
            echo "Services disabled from auto-start."
            ;;
        u)
            echo ""
            echo -e "${RED}WARNING: This will permanently remove the services!${NC}"
            read -p "Are you sure you want to uninstall '$config_name' services? [y/N]: " CONFIRM
            if [[ $CONFIRM =~ ^[Yy]$ ]]; then
                echo "Uninstalling services..."
                sudo systemctl stop "$satellite_service" "$wakeword_service" 2>/dev/null || true
                sudo systemctl disable "$satellite_service" "$wakeword_service" 2>/dev/null || true
                sudo rm -f "/etc/systemd/system/${satellite_service}.service"
                sudo rm -f "/etc/systemd/system/${wakeword_service}.service"
                sudo systemctl daemon-reload
                echo "Services uninstalled successfully."
                echo ""
                echo "Note: Configuration file preserved at: $CONFIG_DIR/${config_name}.json"
            else
                echo "Uninstall cancelled."
            fi
            ;;
        v)
            local config_file="$CONFIG_DIR/${config_name}.json"
            if [ -f "$config_file" ]; then
                echo ""
                echo -e "${BLUE}Configuration: $config_name${NC}"
                echo "File: $config_file"
                echo ""
                jq '.' "$config_file" 2>/dev/null || {
                    echo "Error reading configuration file"
                    cat "$config_file"
                }
            else
                echo "Configuration file not found: $config_file"
            fi
            echo ""
            read -p "Press Enter to continue..."
            ;;
        l)
            echo ""
            echo "Showing logs for $satellite_service (Ctrl+C to exit)..."
            echo ""
            journalctl -u "$satellite_service" -f
            ;;
        q)
            return 0
            ;;
        *)
            echo "Invalid action: $action"
            ;;
    esac
    
    # Show updated status after action (except for logs and quit)
    if [[ "$action" != "l" && "$action" != "q" && "$action" != "v" ]]; then
        echo ""
        echo "Updated Status:"
        local sat_status=$(get_service_status "$satellite_service")
        local wake_status=$(get_service_status "$wakeword_service")
        echo "  Satellite:  $sat_status"
        echo "  Wake Word:  $wake_status"
        echo ""
        read -p "Press Enter to continue..."
    fi
}

# Main program loop
main() {
    while true; do
        clear
        
        if ! display_satellites; then
            echo ""
            read -p "Press Enter to exit..."
            exit 0
        fi
        
        # Get satellite info for selection
        local discovery_output=$(discover_satellites)
        local lines=($discovery_output)
        local count=${lines[0]}
        
        # Parse config names
        local config_names=()
        for ((i=count+1; i<=2*count; i++)); do
            config_names+=("${lines[$i]}")
        done
        
        echo "Select satellite [1-$count] or 'q' to quit:"
        read -p "> " SELECTION
        
        if [[ "$SELECTION" == "q" || "$SELECTION" == "Q" ]]; then
            echo "Goodbye!"
            exit 0
        fi
        
        if [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le "$count" ]; then
            local selected_config="${config_names[$((SELECTION-1))]}"
            
            # Service management loop
            while true; do
                clear
                show_actions_menu "$selected_config"
                
                read -p "Choose action: " ACTION
                
                if [ "$ACTION" = "q" ]; then
                    break
                fi
                
                execute_action "$ACTION" "$selected_config"
            done
        else
            echo "Invalid selection: $SELECTION"
            sleep 2
        fi
    done
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "Please run this script as a regular user (not root)."
    echo "The script will use sudo when needed."
    exit 1
fi

# Check for required commands
for cmd in systemctl jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' not found."
        echo "Please install the required packages and try again."
        exit 1
    fi
done

# Run main program
main
