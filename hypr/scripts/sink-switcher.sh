#!/bin/bash

# Audio device switcher for PipeWire
# Toggles between Monitor and Bluetooth headphones

# Sink names (use actual sink IDs)
MONITOR_SINK="alsa_output.pci-0000_04_00.1.HiFi__HDMI1__sink"
HEADPHONES_SINK="bluez_output.CC:14:BC:BA:31:3E"

# Get current default sink
CURRENT_SINK=$(pactl get-default-sink)

# Determine which device to switch to
if echo "$CURRENT_SINK" | grep -q "HDMI"; then
    # Currently on monitor, switch to headphones
    TARGET_SINK="$HEADPHONES_SINK"
    NOTIFICATION="Audio → 🎧"
else
    # Currently on headphones (or unknown), switch to monitor
    TARGET_SINK="$MONITOR_SINK"
    NOTIFICATION="Audio → 🖥️"
fi

# Verify the target sink exists
if ! pactl list short sinks | grep -q "^[0-9]*\s*$TARGET_SINK"; then
    notify-send "Audio Switch Error" "Target device not found"
    exit 1
fi

# Set the new default sink
pactl set-default-sink "$TARGET_SINK"

# Move all currently playing streams to the new sink
pactl list short sink-inputs | awk '{print $1}' | while read -r stream; do
    pactl move-sink-input "$stream" "$TARGET_SINK" 2>/dev/null
done

# Send notification
notify-send -u low -t 2000 "$NOTIFICATION"
