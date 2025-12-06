#!/bin/bash

# Check if a Kitty window with the class "wiremix" exists
if pgrep -f "kitty.*--class wiremix" >/dev/null; then
    # Kill only that kitty instance
    pkill -f "kitty.*--class wiremix"
else
    # Launch wiremix in a kitty window
    kitty --class wiremix --title "wiremix" -e wiremix &
fi
