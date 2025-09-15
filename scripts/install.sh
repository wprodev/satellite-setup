#!/bin/bash
# Wyoming Satellite Dependencies Installer
# Run with: bash install.sh

set -e

# Get current user info
CURRENT_USER=$(whoami)
USER_HOME=$(eval echo "~$CURRENT_USER")

echo "==========================================="
echo "Wyoming Satellite Installer"
echo "==========================================="
echo "Current User: $CURRENT_USER"
echo "User Home: $USER_HOME"
echo ""

# Update system
echo "Updating system packages..."
sudo apt update -qq
sudo apt upgrade -qqy

# Install dependencies
echo "Installing dependencies..."
sudo apt install -y \
    python3-dev \
    python3-venv \
    python3-pip \
    alsa-utils \
    git \
    alsa-utils \
    libatlas-base-dev \
    libgfortran5 \
    wget \
    curl \
    sox \
    jq

# Create Wyoming directory structure
mkdir -p "$USER_HOME/wyoming-configs"
mkdir -p "$USER_HOME/sounds"
mkdir -p "$USER_HOME/.wyoming-satellite"

rm -rf "$USER_HOME/satellite-setup"
mkdir -p "$USER_HOME/satellite-setup"
git clone https://github.com/wprodev/satellite-setup.git "$USER_HOME/satellite-setup"
rm -rf "$USER_HOME/satellite-setup/.git"

# Setup Wyoming Satellite
echo "Setting up Wyoming Satellite..."
rm -rf "$USER_HOME/wyoming-satellite"
mkdir -p "$USER_HOME/wyoming-satellite"
cp -R "$USER_HOME/satellite-setup/wyoming-satellite" "$USER_HOME/"
cd "$USER_HOME/wyoming-satellite"
echo "Running Wyoming Satellite setup script..."
script/setup

# Setup Wyoming OpenWakeWord
echo "Setting up Wyoming OpenWakeWord..."
rm -rf "$USER_HOME/wyoming-openwakeword"
mkdir -p "$USER_HOME/wyoming-openwakeword"
cp -R "$USER_HOME/satellite-setup/wyoming-openwakeword" "$USER_HOME/"
cd "$USER_HOME/wyoming-openwakeword"
echo "Running Wyoming OpenWakeWord setup script..."
script/setup

echo ""
echo "==========================================="
echo "Installation Complete!"
echo "==========================================="
echo ""
echo "Wyoming Satellite and OpenWakeWord have been installed with all dependencies."
echo ""
echo "Next steps:"
echo "  1. Create configuration: bash scripts/cfg.sh"
echo "  2. Deploy as service: bash scripts/svc.sh [config_name]"
echo "  3. Or use menu interface: bash scripts/manager.sh"
