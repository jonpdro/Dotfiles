#!/bin/bash

# Exit on error
set -e

echo "=== Bluetooth Setup Script for Arch Linux with Pipewire ==="
echo "This script will install and configure Bluetooth without GUI components."

# Function to run commands with sudo if needed
run_sudo() {
    if [[ $EUID -ne 0 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

# Function to check if command succeeded
check_success() {
    if [ $? -eq 0 ]; then
        echo "✓ $1"
    else
        echo "✗ $1 failed"
        return 1
    fi
}

# Update system packages (requires sudo)
echo "Updating system packages..."
run_sudo pacman -Syu --noconfirm
check_success "System update"

# Install required packages (requires sudo)
echo "Installing Bluetooth packages..."
run_sudo pacman -S --needed --noconfirm \
    bluez \
    bluez-utils \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber
check_success "Package installation"

# Enable system services (requires sudo)
echo "Enabling system services..."
run_sudo systemctl enable --now bluetooth.service
check_success "Bluetooth service enable"

# Load kernel modules (requires sudo)
echo "Loading Bluetooth kernel modules..."
run_sudo modprobe btusb 2>/dev/null || true
run_sudo modprobe bluetooth 2>/dev/null || true
check_success "Kernel modules loaded"

# Add kernel modules to load at boot (requires sudo)
echo "Configuring auto-load kernel modules..."
run_sudo bash -c 'mkdir -p /etc/modules-load.d && echo -e "btusb\nbluetooth" > /etc/modules-load.d/bluetooth.conf'
check_success "Kernel modules configured"

# Configure bluetooth (requires sudo)
echo "Configuring Bluetooth..."
run_sudo tee /etc/bluetooth/main.conf > /dev/null << 'EOF'
[General]
AutoEnable=true
Name = Arch Bluetooth
Class = 0x20041C
Experimental = true
KernelExperimental = true
ControllerMode = dual
JustWorksRepairing = always
Privacy = device
EOF
check_success "Bluetooth configuration"

# Enable and start Pipewire user services (as current user)
echo "Setting up Pipewire user services..."

# Check if we're in a desktop session (needed for user services)
if [[ -z "$DBUS_SESSION_BUS_ADDRESS" ]]; then
    echo "Warning: DBUS session not detected. User services may not start properly."
    echo "You may need to log out and log back in for Pipewire to work."
fi

# Enable and start user services
systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || {
    echo "Note: Could not start user services immediately."
    echo "This is normal if you just installed Pipewire."
    echo "They will start automatically on next login."
}

# Create a helper script in user's bin directory
mkdir -p ~/.local/bin
cat > ~/.local/bin/bluetooth-setup << 'EOF'
#!/bin/bash
echo "Bluetooth Audio Setup Helper"
echo "============================="
echo ""
echo "Quick commands:"
echo "1. Start Bluetooth: sudo systemctl start bluetooth"
echo "2. Enter Bluetooth control: bluetoothctl"
echo "3. Power on: bluetoothctl power on"
echo "4. Scan: bluetoothctl scan on"
echo "5. List devices: bluetoothctl devices"
echo "6. Pair: bluetoothctl pair <MAC>"
echo "7. Connect: bluetoothctl connect <MAC>"
echo ""
echo "Audio troubleshooting:"
echo "- Check audio outputs: pactl list sinks"
echo "- Restart Pipewire: systemctl --user restart pipewire"
echo "- Check service status: systemctl --user status pipewire"
EOF

chmod +x ~/.local/bin/bluetooth-setup

# Create desktop autostart entry for Pipewire (if in desktop environment)
if [[ -d ~/.config/autostart ]]; then
    cat > ~/.config/autostart/pipewire-autostart.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Pipewire Autostart
Exec=systemctl --user restart pipewire pipewire-pulse wireplumber
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
fi

# Try to power on Bluetooth
echo "Attempting to power on Bluetooth..."
run_sudo bluetoothctl power on 2>/dev/null || {
    echo "Note: Could not power on Bluetooth via command line."
    echo "You can enable it manually with: bluetoothctl power on"
}

# Final instructions
echo ""
echo "=== SETUP COMPLETE ==="
echo ""
echo "What was done:"
echo "1. Installed Bluetooth and Pipewire packages"
echo "2. Enabled Bluetooth system service"
echo "3. Configured kernel modules to load at boot"
echo "4. Set up Pipewire user services"
echo ""
echo "Next steps:"
echo "1. If audio doesn't work immediately, LOG OUT AND LOG BACK IN"
echo "2. After login, check if Pipewire is running:"
echo "   systemctl --user status pipewire"
echo "3. Pair your Bluetooth device:"
echo "   bluetoothctl"
echo "   > power on"
echo "   > scan on"
echo "   > pair [MAC]"
echo "   > connect [MAC]"
echo ""
echo "Helper command available: bluetooth-setup"
echo ""
