#!/bin/bash

CHOICE=$(echo -e "󰐥\n󰜉\n󰌾" | rofi -dmenu -p "" -theme ~/.config/rofi/power-menu.rasi -selected-row 0)

case $CHOICE in
    "󰐥")
        sleep 10 && systemctl poweroff
        ;;
    "󰜉")
        sleep 3 && reboot
        ;;
    "󰌾")
        killall rofi
        sleep 0.5 && hyprlock
        ;;
esac
