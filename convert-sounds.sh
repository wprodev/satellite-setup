#!/bin/bash
# Convert MP3 files to WAV with simple numbered names

set -e

SOUNDS_DIR="sounds"
OUTPUT_DIR="sounds/wav"

# Check if ffmpeg is available
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Error: ffmpeg is required for MP3 to WAV conversion"
    echo "Install with: sudo apt install ffmpeg (Ubuntu/Debian) or brew install ffmpeg (macOS)"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Converting MP3 files to WAV format..."
echo "======================================"

# Get all MP3 files and sort them
MP3_FILES=($(ls "$SOUNDS_DIR"/*.mp3 2>/dev/null | sort))

if [ ${#MP3_FILES[@]} -eq 0 ]; then
    echo "No MP3 files found in $SOUNDS_DIR directory"
    exit 1
fi

# Convert each file with numbered names
counter=1
for mp3_file in "${MP3_FILES[@]}"; do
    # Format counter with leading zero
    padded_counter=$(printf "%02d" $counter)
    
    # Get original filename for reference
    original_name=$(basename "$mp3_file" .mp3)
    
    # Output filename
    wav_file="$OUTPUT_DIR/${padded_counter}.wav"
    
    echo "Converting: $original_name.mp3 → ${padded_counter}.wav"
    
    # Convert MP3 to WAV with standard settings for voice applications
    # 22050 Hz sample rate, mono channel, 16-bit
    ffmpeg -i "$mp3_file" -ar 22050 -ac 1 -sample_fmt s16 -y "$wav_file" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Success"
    else
        echo "  ✗ Failed to convert $original_name.mp3"
    fi
    
    counter=$((counter + 1))
done

echo ""
echo "Conversion complete!"
echo "==================="
echo "Converted ${#MP3_FILES[@]} files to $OUTPUT_DIR/"
echo ""
echo "File mapping:"
for i in "${!MP3_FILES[@]}"; do
    padded_num=$(printf "%02d" $((i + 1)))
    original_name=$(basename "${MP3_FILES[$i]}" .mp3)
    echo "  ${padded_num}.wav ← $original_name.mp3"
done
