#!/bin/bash

# Simple Bluetooth setup script
set -e

echo "=== Minimal Bluetooth Setup ==="

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

echo "Installing packages..."
pacman -S --needed --noconfirm bluez bluez-utils

echo "Enabling Bluetooth service..."
systemctl enable --now bluetooth.service

echo "Loading kernel modules..."
modprobe btusb 2>/dev/null || true
modprobe bluetooth 2>/dev/null || true

echo "Configuring auto-start..."
mkdir -p /etc/modules-load.d
echo -e "btusb\nbluetooth" >/etc/modules-load.d/bluetooth.conf

echo ""
echo "=== DONE ==="
echo ""
echo "Now as your regular user (after logout/login if needed), run:"
echo ""
echo "For Pipewire user services:"
echo "  systemctl --user enable --now pipewire pipewire-pulse wireplumber"
echo ""
echo "To pair devices:"
echo "  bluetoothctl"
echo "  > power on"
echo "  > agent on"
echo "  > default-agent"
echo "  > scan on"
echo "  > pair [MAC]"
echo "  > trust [MAC]"
echo "  > connect [MAC]"
