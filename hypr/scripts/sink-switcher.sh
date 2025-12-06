#!/bin/bash

# Define the sinks
monitor_sink="alsa_output.pci-0000_04_00.1.HiFi__HDMI1__sink"
bt_sink="bluez_output.CC_14_BC_BA_31_3E.1"

# Device names
speakers="🖥️ - Horizon ZPRO"
headset="🎧 - Edifier W800BT Plus"

# Get the current default sink
current_sink=$(pactl get-default-sink)

# Check if Bluetooth sink exists (if headset is connected)
bt_available=$(pactl list short sinks | grep -c "$bt_sink")

# Function to move audio streams
move_streams() {
    new_sink="$1"
    for stream in $(pactl list short sink-inputs | awk '{print $1}'); do
        pactl move-sink-input "$stream" "$new_sink"
    done
}

notify() {
    title="$1"
    msg="$2"
    icon="$3"

    notify-send -u low -i "$icon" "$title" "$msg"
}

############################################
#            MAIN LOGIC
############################################

# If Bluetooth is NOT available → force HDMI
if [[ "$bt_available" -eq 0 ]]; then
    pactl set-default-sink "$monitor_sink"
    move_streams "$monitor_sink"
    notify "Audio switch failed!" "$headset is unavailable!"
    exit 0
fi

# Bluetooth IS available → normal toggle
if [[ "$current_sink" == "$monitor_sink" ]]; then
    pactl set-default-sink "$bt_sink"
    move_streams "$bt_sink"
    notify "Audio switched to: $headset"
else
    pactl set-default-sink "$monitor_sink"
    move_streams "$monitor_sink"
    notify "Audio switched to: $speakers"
fi

