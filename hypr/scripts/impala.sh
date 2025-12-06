#!/bin/bash

# Check if a Kitty window with the class "impala" exists
if pgrep -f "kitty.*--class impala" >/dev/null; then
    # Kill only that kitty instance
    pkill -f "kitty.*--class impala"
else
    # Launch impala in a kitty window
    kitty --class impala --title "impala" -e impala &
fi
