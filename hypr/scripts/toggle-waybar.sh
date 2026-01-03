#!/usr/bin/env bash

if pidof waybar >/dev/null; then
  killall waybar
else
  waybar </dev/null >/dev/null 2>&1 &
fi
