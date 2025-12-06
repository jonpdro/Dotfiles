#!/bin/bash

# Check if a Kitty window with the class "bluetuith" exists
if pgrep -f "kitty.*--class bluetuith" >/dev/null; then
    # Kill only that kitty instance
    pkill -f "kitty.*--class bluetuith"
else
    # Launch bluetuith in a kitty window
    kitty --class bluetuith --title "bluetuith" -e bluetuith &
fi
