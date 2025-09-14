#!/bin/bash
# Wyoming Satellite Configuration Manager
# Run with: bash satellite-config.sh [config_name]

set -e

# Global variables for sound selection
SELECTED_SOUND_PATH=""
SOUND_SELECTION_SUCCESS=false

# Simple sound selector function
simple_sound_selector() {
    local title="$1"
    local sounds_dir="$2"
    local speaker_device="$3"
    local speaker_rate="$4"
    
    # Reset global variables
    SELECTED_SOUND_PATH=""
    SOUND_SELECTION_SUCCESS=false
    
    # Check if sounds directory exists and has WAV files
    if [ ! -d "$sounds_dir" ]; then
        echo "Error: Directory $sounds_dir does not exist"
        return 1
    fi
    
    if ! ls "$sounds_dir"/*.wav 1> /dev/null 2>&1; then
        echo "Error: No WAV files found in $sounds_dir"
        return 1
    fi
    
    # Get list of WAV files
    local sound_files=()
    local sound_names=()
    
    for wav_file in "$sounds_dir"/*.wav; do
        if [ -f "$wav_file" ]; then
            sound_files+=("$wav_file")
            sound_names+=("$(basename "$wav_file")")
        fi
    done
    
    if [ ${#sound_files[@]} -eq 0 ]; then
        echo "Error: No WAV files found after scanning directory"
        return 1
    fi
    
    while true; do
        echo ""
        echo "$title"
        echo "$(printf '=%.0s' $(seq 1 ${#title}))"
        echo ""
        
        # Display sound list with None as option 0
        echo "  0) None (no sound)"
        for i in $(seq 0 $((${#sound_files[@]} - 1))); do
            echo "  $((i + 1))) ${sound_names[$i]}"
        done
        
        echo ""
        echo "Options:"
        echo "  1) Play a sound"
        echo "  2) Select a sound"
        echo ""
        
        read -p "Choose option [2]: " action
        action=${action:-2}
        
        case $action in
            1)
                # Play sound mode
                while true; do
                    echo ""
                    read -p "Enter sound number to play (1-${#sound_files[@]}) or 'q' to go back: " play_choice
                    
                    if [ "$play_choice" = "q" ] || [ "$play_choice" = "Q" ]; then
                        break
                    fi
                    
                    if [[ "$play_choice" =~ ^[0-9]+$ ]] && [ "$play_choice" -ge 1 ] && [ "$play_choice" -le ${#sound_files[@]} ]; then
                        play_index=$((play_choice - 1))
                        echo "Playing: ${sound_names[$play_index]}"
                        if [ -n "$speaker_device" ]; then
                            aplay -D "$speaker_device" -r "$speaker_rate" "${sound_files[$play_index]}" 2>/dev/null
                        else
                            aplay "${sound_files[$play_index]}" 2>/dev/null
                        fi
                    else
                        echo "Invalid selection. Please choose 1-${#sound_files[@]} or 'q'."
                    fi
                done
                ;;
            2)
                # Select sound mode
                echo ""
                read -p "Enter sound number to select (0-${#sound_files[@]}): " select_choice
                
                if [ "$select_choice" = "0" ]; then
                    # User selected "None"
                    SELECTED_SOUND_PATH=""
                    SOUND_SELECTION_SUCCESS=true
                    return 0
                elif [[ "$select_choice" =~ ^[0-9]+$ ]] && [ "$select_choice" -ge 1 ] && [ "$select_choice" -le ${#sound_files[@]} ]; then
                    # User selected a sound file
                    selected_index=$((select_choice - 1))
                    SELECTED_SOUND_PATH="${sound_files[$selected_index]}"
                    SOUND_SELECTION_SUCCESS=true
                    return 0
                else
                    echo "Invalid selection. Please choose 0-${#sound_files[@]}."
                    sleep 2
                fi
                ;;
            *)
                echo "Invalid option. Please choose 1 or 2."
                sleep 2
                ;;
        esac
    done
}

# Get current user info
CURRENT_USER=$(whoami)
USER_HOME=$(eval echo "~$CURRENT_USER")
CONFIG_DIR="$USER_HOME/wyoming-configs"
SOUNDS_DIR="$USER_HOME/sounds"

# Check and create directories if needed
if [ ! -d "$CONFIG_DIR" ]; then
    echo "Configuration directory does not exist: $CONFIG_DIR"
    read -p "Create configuration directory? [Y/n]: " CREATE_CONFIG_DIR
    if [[ ! $CREATE_CONFIG_DIR =~ ^[Nn]$ ]]; then
        mkdir -p "$CONFIG_DIR"
        echo "Created configuration directory: $CONFIG_DIR"
    else
        echo "Cannot proceed without configuration directory."
        exit 1
    fi
fi

if [ ! -d "$SOUNDS_DIR" ]; then
    echo "Sounds directory does not exist: $SOUNDS_DIR"
    read -p "Create sounds directory? [Y/n]: " CREATE_SOUNDS_DIR
    if [[ ! $CREATE_SOUNDS_DIR =~ ^[Nn]$ ]]; then
        mkdir -p "$SOUNDS_DIR"
        echo "Created sounds directory: $SOUNDS_DIR"
    else
        echo "Cannot proceed without sounds directory."
        exit 1        
    fi
fi

# Configuration selection
CONFIG_NAME="${1}"
if [ -z "$CONFIG_NAME" ]; then
    echo ""
    echo "Configuration Selection:"
    echo "========================"
    
    # Check for existing configurations
    EXISTING_CONFIGS=()
    if ls "$CONFIG_DIR"/*.json 1> /dev/null 2>&1; then
        echo "Available configurations:"
        CONFIG_COUNT=1
        for config_file in "$CONFIG_DIR"/*.json; do
            config_name=$(basename "$config_file" .json)
            echo "  $CONFIG_COUNT) $config_name"
            EXISTING_CONFIGS+=("$config_name")
            CONFIG_COUNT=$((CONFIG_COUNT + 1))
        done
        echo "  $CONFIG_COUNT) Create new configuration"
        echo ""
        read -p "Select option [1]: " SELECTION
        SELECTION=${SELECTION:-1}
        
        if [ "$SELECTION" -eq "$CONFIG_COUNT" ] 2>/dev/null; then
            # Create new configuration
            read -p "Enter new configuration name: " CONFIG_NAME
            if [ -z "$CONFIG_NAME" ]; then
                echo "Configuration name cannot be empty."
                exit 1
            fi
        elif [ "$SELECTION" -ge 1 ] 2>/dev/null && [ "$SELECTION" -lt "$CONFIG_COUNT" ]; then
            # Select existing configuration
            CONFIG_NAME="${EXISTING_CONFIGS[$((SELECTION - 1))]}"
        else
            echo "Invalid selection."
            exit 1
        fi
    else
        echo "No existing configurations found."
        read -p "Enter new configuration name: " CONFIG_NAME
        if [ -z "$CONFIG_NAME" ]; then
            echo "Configuration name cannot be empty."
            exit 1
        fi
    fi
fi

CONFIG_FILE="$CONFIG_DIR/${CONFIG_NAME}.json"

echo "==========================================="
echo "Wyoming Satellite Configuration Manager"
echo "==========================================="
echo "Configuration: $CONFIG_NAME"
echo "Config file: $CONFIG_FILE"
echo ""

# Load existing config or create new
if [ -f "$CONFIG_FILE" ]; then
    echo "Loading existing configuration..."
    NEW_CONFIG=false
else
    echo "Creating new configuration: $CONFIG_NAME"
    NEW_CONFIG=true
fi

# Load existing values or set defaults
if [ "$NEW_CONFIG" = false ]; then
    SATELLITE_NAME=$(jq -r '.satellite_name // "raspberry-pi-test"' "$CONFIG_FILE")
    WAKE_WORD=$(jq -r '.wake_word // "ok_nabu"' "$CONFIG_FILE")
    MIC_DEVICE=$(jq -r '.audio.mic_device // ""' "$CONFIG_FILE")
    SPEAKER_DEVICE=$(jq -r '.audio.speaker_device // ""' "$CONFIG_FILE")
    MIC_RATE=$(jq -r '.audio.mic_rate // "16000"' "$CONFIG_FILE")
    SPEAKER_RATE=$(jq -r '.audio.speaker_rate // "22050"' "$CONFIG_FILE")
    MIC_AUTO_GAIN=$(jq -r '.audio.mic_auto_gain // ""' "$CONFIG_FILE")
    MIC_NOISE_SUPPRESSION=$(jq -r '.audio.mic_noise_suppression // ""' "$CONFIG_FILE")
    DEBUG_MODE=$(jq -r '.debug_mode // false' "$CONFIG_FILE")
    WAKE_SOUND_PATH=$(jq -r '.sounds.wake_sound // ""' "$CONFIG_FILE")
    DONE_SOUND_PATH=$(jq -r '.sounds.done_sound // ""' "$CONFIG_FILE")
    
    echo "Current configuration:"
    echo "  Satellite: $SATELLITE_NAME"
    echo "  Wake Word: $WAKE_WORD"
    echo "  Audio: $MIC_DEVICE @ ${MIC_RATE}Hz / $SPEAKER_DEVICE @ ${SPEAKER_RATE}Hz"
    echo ""
    
    read -p "Do you want to modify this configuration? [y/N]: " MODIFY_CONFIG
    if [[ ! $MODIFY_CONFIG =~ ^[Yy]$ ]]; then
        echo "Configuration unchanged."
        exit 0
    fi
else
    # Set defaults for new config
    SATELLITE_NAME="raspberry-pi-test"
    WAKE_WORD="ok_nabu"
    MIC_DEVICE=""
    SPEAKER_DEVICE=""
    MIC_RATE="16000"
    SPEAKER_RATE="22050"
    MIC_AUTO_GAIN=""
    MIC_NOISE_SUPPRESSION=""
    DEBUG_MODE=false
    WAKE_SOUND_PATH=""
    DONE_SOUND_PATH=""
fi

# Basic configuration
echo "=== Basic Configuration ==="
read -p "Satellite name [$SATELLITE_NAME]: " NEW_SATELLITE_NAME
SATELLITE_NAME=${NEW_SATELLITE_NAME:-$SATELLITE_NAME}

read -p "Wake word [$WAKE_WORD]: " NEW_WAKE_WORD
WAKE_WORD=${NEW_WAKE_WORD:-$WAKE_WORD}

# Audio configuration
echo ""
echo "=== Audio Configuration ==="

# Show available devices
echo "Available recording devices:"
arecord -L 2>/dev/null || echo "  (arecord not available - install audio tools first)"
echo ""
echo "Available playback devices:"
aplay -L 2>/dev/null || echo "  (aplay not available - install audio tools first)"
echo ""

read -p "Microphone device [$MIC_DEVICE]: " NEW_MIC_DEVICE
MIC_DEVICE=${NEW_MIC_DEVICE:-$MIC_DEVICE}

read -p "Speaker device [$SPEAKER_DEVICE]: " NEW_SPEAKER_DEVICE
SPEAKER_DEVICE=${NEW_SPEAKER_DEVICE:-$SPEAKER_DEVICE}

echo "Sample rate options: 16000 (default), 44100 (CD), 48000 (professional)"
read -p "Microphone sample rate [$MIC_RATE]: " NEW_MIC_RATE
MIC_RATE=${NEW_MIC_RATE:-$MIC_RATE}

read -p "Speaker sample rate [$SPEAKER_RATE]: " NEW_SPEAKER_RATE
SPEAKER_RATE=${NEW_SPEAKER_RATE:-$SPEAKER_RATE}

# Advanced audio options
echo ""
echo "=== Advanced Audio Options ==="
echo "Microphone auto-gain control (0-31 dbFS, 31 being loudest, empty to disable)"
read -p "Mic auto-gain [$MIC_AUTO_GAIN]: " NEW_MIC_AUTO_GAIN
MIC_AUTO_GAIN=${NEW_MIC_AUTO_GAIN:-$MIC_AUTO_GAIN}

echo "Noise suppression (0-4, 4 being maximum suppression, empty to disable)"
read -p "Mic noise suppression [$MIC_NOISE_SUPPRESSION]: " NEW_MIC_NOISE_SUPPRESSION
MIC_NOISE_SUPPRESSION=${NEW_MIC_NOISE_SUPPRESSION:-$MIC_NOISE_SUPPRESSION}

echo "Debug mode (enables detailed logging)"
if [ "$DEBUG_MODE" = "true" ]; then
    DEBUG_DISPLAY="enabled"
else
    DEBUG_DISPLAY="disabled"
fi
read -p "Debug mode [$DEBUG_DISPLAY] (y/n): " NEW_DEBUG_MODE
case "$NEW_DEBUG_MODE" in
    [Yy]*)
        DEBUG_MODE=true
        ;;
    [Nn]*)
        DEBUG_MODE=false
        ;;
    "")
        # Keep current setting
        ;;
    *)
        echo "Invalid input. Keeping current setting."
        ;;
esac

# Audio testing
if [ -n "$MIC_DEVICE" ] && [ -n "$SPEAKER_DEVICE" ]; then
    echo ""
    read -p "Test audio configuration? [y/N]: " TEST_AUDIO
    if [[ $TEST_AUDIO =~ ^[Yy]$ ]]; then
        # Iterative audio testing loop
        AUDIO_TEST_SATISFIED=false
        TEST_ITERATION=1
        
        REPLAY_MODE=false
        PLAYBACK_FILE=""
        while [ "$AUDIO_TEST_SATISFIED" = false ]; do
            if [ "$REPLAY_MODE" = true ]; then
                aplay -D "$SPEAKER_DEVICE" -r "$SPEAKER_RATE" "$PLAYBACK_FILE"
                REPLAY_MODE=false
            else
                echo ""
                echo "=== Audio Test - Iteration $TEST_ITERATION ==="
                echo "Current: $MIC_DEVICE @ ${MIC_RATE}Hz → $SPEAKER_DEVICE @ ${SPEAKER_RATE}Hz"
            
                echo "Recording 3 seconds of audio..."
                read -p "Press Enter to start recording..."
            
                arecord -D "$MIC_DEVICE" -r "$MIC_RATE" -c 1 -f S16_LE -t wav -d 3 "test_$TEST_ITERATION.wav"
                PLAYBACK_FILE="test_$TEST_ITERATION.wav"
            
                echo "Playing back recording..."
                aplay -D "$SPEAKER_DEVICE" -r "$SPEAKER_RATE" "$PLAYBACK_FILE"
            fi
            
            echo ""
            echo "0) Replay current recording"
            echo "1) Audio quality is good - continue"
            echo "2) Adjust sample rates and re-test"
            echo "3) Change devices and re-test"
            read -p "Choose option [1]: " AUDIO_RESULT
            AUDIO_RESULT=${AUDIO_RESULT:-1}
            
            case $AUDIO_RESULT in
                0)
                    echo "Replaying..."
                    REPLAY_MODE=true
                    ;;
                1)
                    echo "Audio configuration confirmed."
                    AUDIO_TEST_SATISFIED=true
                    rm -f test_*.wav test_*_converted.wav
                    ;;
                2)
                    read -p "New microphone sample rate [$MIC_RATE]: " NEW_MIC_RATE_TEST
                    MIC_RATE=${NEW_MIC_RATE_TEST:-$MIC_RATE}
                    
                    read -p "New speaker sample rate [$SPEAKER_RATE]: " NEW_SPEAKER_RATE_TEST
                    SPEAKER_RATE=${NEW_SPEAKER_RATE_TEST:-$SPEAKER_RATE}
                    
                    TEST_ITERATION=$((TEST_ITERATION + 1))
                    ;;
                3)
                    echo "Available recording devices:"
                    arecord -L
                    read -p "New microphone device [$MIC_DEVICE]: " NEW_MIC_DEVICE_TEST
                    MIC_DEVICE=${NEW_MIC_DEVICE_TEST:-$MIC_DEVICE}
                    
                    echo "Available playback devices:"
                    aplay -L
                    read -p "New speaker device [$SPEAKER_DEVICE]: " NEW_SPEAKER_DEVICE_TEST
                    SPEAKER_DEVICE=${NEW_SPEAKER_DEVICE_TEST:-$SPEAKER_DEVICE}
                    
                    TEST_ITERATION=$((TEST_ITERATION + 1))
                    ;;
            esac
        done
    fi
fi

# Sound configuration
echo ""
echo "=== Sound Configuration ==="
echo "Current wake sound: ${WAKE_SOUND_PATH:-none}"
echo "Current done sound: ${DONE_SOUND_PATH:-none}"

# Wake sound
echo ""
echo "Wake sound options:"
echo "1) Accept current: ${WAKE_SOUND_PATH:-none}"
echo "2) Select from local WAV files"
echo "3) Custom URL"
echo "4) Record new wake sound"
echo "5) Remove wake sound"
read -p "Choose option [1]: " WAKE_OPTION
WAKE_OPTION=${WAKE_OPTION:-1}

case $WAKE_OPTION in
    2)
        # Interactive sound selection from local WAV files
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        REPO_SOUNDS_DIR="$SCRIPT_DIR/../sounds/wav"
        
        if [ -d "$REPO_SOUNDS_DIR" ] && ls "$REPO_SOUNDS_DIR"/*.wav 1> /dev/null 2>&1; then
            echo "Opening sound selector..."
            
            # Call function directly and use global variables
            simple_sound_selector "Select Wake Sound" "$REPO_SOUNDS_DIR" "$SPEAKER_DEVICE" "$SPEAKER_RATE"
            
            # Process the selection using global variables
            if [ "$SOUND_SELECTION_SUCCESS" = true ]; then
                if [ -n "$SELECTED_SOUND_PATH" ]; then
                    # Copy selected sound to user's sounds directory with proper naming
                    mkdir -p "$SOUNDS_DIR"
                    SOUND_NAME=$(basename "$SELECTED_SOUND_PATH" .wav)
                    WAKE_SOUND_PATH="$SOUNDS_DIR/${SATELLITE_NAME}-wake-${SOUND_NAME}.wav"
                    cp "$SELECTED_SOUND_PATH" "$WAKE_SOUND_PATH"
                    echo "Selected wake sound: $SOUND_NAME.wav"
                    echo "Copied to: $WAKE_SOUND_PATH"
                else
                    # User selected "None"
                    WAKE_SOUND_PATH=""
                    echo "Wake sound set to none."
                fi
            else
                echo "No sound selected. Keeping current setting."
            fi
        else
            echo "No WAV files found in $REPO_SOUNDS_DIR"
            echo "Please run the convert-sounds.sh script first to convert MP3 files to WAV."
        fi
        ;;
    3)
        read -p "Enter wake sound URL: " WAKE_URL
        if [ -n "$WAKE_URL" ]; then
            mkdir -p "$SOUNDS_DIR"
            WAKE_SOUND_PATH="$SOUNDS_DIR/${CONFIG_NAME}_awake.wav"
            wget -O "$WAKE_SOUND_PATH" "$WAKE_URL" || {
                echo "Warning: Could not download from $WAKE_URL"
                WAKE_SOUND_PATH=""
            }
        fi
        ;;
    4)
        if [ -n "$MIC_DEVICE" ] && [ -n "$SPEAKER_DEVICE" ]; then
            mkdir -p "$SOUNDS_DIR"
            WAKE_RECORD_SATISFIED=false
            WAKE_ITERATION=1
            
            while [ "$WAKE_RECORD_SATISFIED" = false ]; do
                echo "Recording wake sound #$WAKE_ITERATION (2 seconds)..."
                read -p "Press Enter to start recording..."
                arecord -D "$MIC_DEVICE" -r "$SPEAKER_RATE" -c 1 -f S16_LE -d 2 "$SOUNDS_DIR/${CONFIG_NAME}_awake_$WAKE_ITERATION.wav"
                
                echo "Playing back..."
                aplay -D "$SPEAKER_DEVICE" "$SOUNDS_DIR/${CONFIG_NAME}_awake_$WAKE_ITERATION.wav"
                
                read -p "Accept this recording? [y/N]: " WAKE_ACCEPT
                if [[ $WAKE_ACCEPT =~ ^[Yy]$ ]]; then
                    WAKE_SOUND_PATH="$SOUNDS_DIR/${CONFIG_NAME}_awake.wav"
                    mv "$SOUNDS_DIR/${CONFIG_NAME}_awake_$WAKE_ITERATION.wav" "$WAKE_SOUND_PATH"
                    WAKE_RECORD_SATISFIED=true
                    rm -f "$SOUNDS_DIR/${CONFIG_NAME}_awake_"*.wav 2>/dev/null || true
                else
                    WAKE_ITERATION=$((WAKE_ITERATION + 1))
                fi
            done
        else
            echo "Cannot record - audio devices not configured"
        fi
        ;;
    5)
        WAKE_SOUND_PATH=""
        ;;
esac

# Done sound
echo ""
echo "Done sound options:"
echo "1) Accept current: ${DONE_SOUND_PATH:-none}"
echo "2) Select from local WAV files"
echo "3) Custom URL"
echo "4) Record new done sound"
echo "5) Remove done sound"
read -p "Choose option [1]: " DONE_OPTION
DONE_OPTION=${DONE_OPTION:-1}

case $DONE_OPTION in
    2)
        # Interactive sound selection from local WAV files
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        REPO_SOUNDS_DIR="$SCRIPT_DIR/../sounds/wav"
        
        if [ -d "$REPO_SOUNDS_DIR" ] && ls "$REPO_SOUNDS_DIR"/*.wav 1> /dev/null 2>&1; then
            echo "Opening sound selector..."
            
            # Call function directly and use global variables
            simple_sound_selector "Select Done Sound" "$REPO_SOUNDS_DIR" "$SPEAKER_DEVICE" "$SPEAKER_RATE"
            
            # Process the selection using global variables
            if [ "$SOUND_SELECTION_SUCCESS" = true ]; then
                if [ -n "$SELECTED_SOUND_PATH" ]; then
                    # Copy selected sound to user's sounds directory with proper naming
                    mkdir -p "$SOUNDS_DIR"
                    SOUND_NAME=$(basename "$SELECTED_SOUND_PATH" .wav)
                    DONE_SOUND_PATH="$SOUNDS_DIR/${SATELLITE_NAME}-done-${SOUND_NAME}.wav"
                    cp "$SELECTED_SOUND_PATH" "$DONE_SOUND_PATH"
                    echo "Selected done sound: $SOUND_NAME.wav"
                    echo "Copied to: $DONE_SOUND_PATH"
                else
                    # User selected "None"
                    DONE_SOUND_PATH=""
                    echo "Done sound set to none."
                fi
            else
                echo "No sound selected. Keeping current setting."
            fi
        else
            echo "No WAV files found in $REPO_SOUNDS_DIR"
            echo "Please run the convert-sounds.sh script first to convert MP3 files to WAV."
        fi
        ;;
    3)
        read -p "Enter done sound URL: " DONE_URL
        if [ -n "$DONE_URL" ]; then
            mkdir -p "$SOUNDS_DIR"
            DONE_SOUND_PATH="$SOUNDS_DIR/${CONFIG_NAME}_done.wav"
            wget -O "$DONE_SOUND_PATH" "$DONE_URL" || {
                echo "Warning: Could not download from $DONE_URL"
                DONE_SOUND_PATH=""
            }
        fi
        ;;
    4)
        if [ -n "$MIC_DEVICE" ] && [ -n "$SPEAKER_DEVICE" ]; then
            mkdir -p "$SOUNDS_DIR"
            DONE_RECORD_SATISFIED=false
            DONE_ITERATION=1
            
            while [ "$DONE_RECORD_SATISFIED" = false ]; do
                echo "Recording done sound #$DONE_ITERATION (2 seconds)..."
                read -p "Press Enter to start recording..."
                arecord -D "$MIC_DEVICE" -r "$SPEAKER_RATE" -c 1 -f S16_LE -d 2 "$SOUNDS_DIR/${CONFIG_NAME}_done_$DONE_ITERATION.wav"
                
                echo "Playing back..."
                aplay -D "$SPEAKER_DEVICE" "$SOUNDS_DIR/${CONFIG_NAME}_done_$DONE_ITERATION.wav"
                
                read -p "Accept this recording? [y/N]: " DONE_ACCEPT
                if [[ $DONE_ACCEPT =~ ^[Yy]$ ]]; then
                    DONE_SOUND_PATH="$SOUNDS_DIR/${CONFIG_NAME}_done.wav"
                    mv "$SOUNDS_DIR/${CONFIG_NAME}_done_$DONE_ITERATION.wav" "$DONE_SOUND_PATH"
                    DONE_RECORD_SATISFIED=true
                    rm -f "$SOUNDS_DIR/${CONFIG_NAME}_done_"*.wav 2>/dev/null || true
                else
                    DONE_ITERATION=$((DONE_ITERATION + 1))
                fi
            done
        else
            echo "Cannot record - audio devices not configured"
        fi
        ;;
    5)
        DONE_SOUND_PATH=""
        ;;
esac

# Save configuration to JSON
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" << EOF_JSON
{
  "config_name": "$CONFIG_NAME",
  "satellite_name": "$SATELLITE_NAME",
  "wake_word": "$WAKE_WORD",
  "audio": {
    "mic_device": "$MIC_DEVICE",
    "speaker_device": "$SPEAKER_DEVICE",
    "mic_rate": "$MIC_RATE",
    "speaker_rate": "$SPEAKER_RATE",
    "mic_auto_gain": "$MIC_AUTO_GAIN",
    "mic_noise_suppression": "$MIC_NOISE_SUPPRESSION"
  },
  "debug_mode": $DEBUG_MODE,
  "sounds": {
    "wake_sound": "$WAKE_SOUND_PATH",
    "done_sound": "$DONE_SOUND_PATH"
  },
  "metadata": {
    "created_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "updated_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "created_by": "$CURRENT_USER",
    "hostname": "$(hostname)"
  }
}
EOF_JSON

echo ""
echo "==========================================="
echo "Configuration Saved!"
echo "==========================================="
echo ""
echo "Configuration: $CONFIG_NAME"
echo "File: $CONFIG_FILE"
echo ""
echo "Summary:"
echo "  Satellite: $SATELLITE_NAME"
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
echo "Next: Run 'bash satellite-run.sh $CONFIG_NAME' to deploy this configuration"
