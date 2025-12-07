#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        print_success "$1"
    else
        print_error "$2"
        return 1
    fi
}

print_info "Starting iwd installation and configuration..."

# Update system
print_info "Updating system packages..."
sudo pacman -Syu --noconfirm
check_status "System updated successfully" "Failed to update system"

# Check and stop conflicting services
print_info "Checking for conflicting network services..."
CONFLICTS=("NetworkManager" "wpa_supplicant")
STOPPED_SERVICES=()

for service in "${CONFLICTS[@]}"; do
    if systemctl is-active --quiet "$service"; then
        print_warning "$service is running - stopping and disabling..."
        sudo systemctl stop "$service"
        sudo systemctl disable "$service"
        STOPPED_SERVICES+=("$service")
        print_success "$service stopped and disabled"
    fi
done

if [ ${#STOPPED_SERVICES[@]} -gt 0 ]; then
    echo ""
    print_warning "Stopped services: ${STOPPED_SERVICES[*]}"
    print_info "These services conflict with iwd"
    echo ""
fi

# Install iwd
print_info "Installing iwd..."
sudo pacman -S --needed --noconfirm iwd
check_status "iwd installed successfully" "Failed to install iwd" || exit 1

# Create iwd configuration directory
print_info "Creating iwd configuration directory..."
sudo mkdir -p /etc/iwd
check_status "Configuration directory created" "Failed to create directory"

# Create basic iwd configuration
print_info "Creating iwd configuration file..."
sudo tee /etc/iwd/main.conf > /dev/null << 'EOF'
[General]
EnableNetworkConfiguration=true
UseDefaultInterface=true

[Network]
NameResolvingService=systemd
EOF
check_status "Configuration file created" "Failed to create configuration"

# Enable and start iwd service
print_info "Enabling iwd service..."
sudo systemctl enable iwd
check_status "iwd service enabled" "Failed to enable iwd service"

print_info "Starting iwd service..."
sudo systemctl start iwd
check_status "iwd service started" "Failed to start iwd service"

# Check service status
sleep 2
if systemctl is-active --quiet iwd; then
    print_success "iwd service is running"
else
    print_error "iwd service failed to start"
    print_info "Check logs with: journalctl -u iwd -n 50"
    exit 1
fi

# Detect wireless interfaces
print_info "Detecting wireless interfaces..."
WIRELESS_INTERFACES=$(ip link show | grep -o "wl[^:]*" || iwconfig 2>/dev/null | grep -o "wl[^[:space:]]*")

if [ -z "$WIRELESS_INTERFACES" ]; then
    print_warning "No wireless interfaces detected"
    print_info "Your system may not have a wireless adapter"
else
    print_success "Wireless interfaces detected:"
    echo "$WIRELESS_INTERFACES" | while read -r iface; do
        echo "  - $iface"
    done
fi

echo ""
print_success "==================== INSTALLATION COMPLETE ===================="
print_info "iwd has been installed and enabled successfully!"
print_success "==============================================================="
echo ""

print_info "Quick start guide:"
echo ""
echo "  1. Enter interactive mode:"
echo "     $ iwctl"
echo ""
echo "  2. List wireless devices:"
echo "     [iwd]# device list"
echo ""
echo "  3. Scan for networks:"
echo "     [iwd]# station <device> scan"
echo ""
echo "  4. List available networks:"
echo "     [iwd]# station <device> get-networks"
echo ""
echo "  5. Connect to a network:"
echo "     [iwd]# station <device> connect <SSID>"
echo ""
echo "  Or use single command:"
echo "     $ iwctl station <device> connect <SSID>"
echo ""

print_info "Configuration file: /etc/iwd/main.conf"
print_info "Check service status: systemctl status iwd"
print_info "View logs: journalctl -u iwd -f"

if [ ${#STOPPED_SERVICES[@]} -gt 0 ]; then
    echo ""
    print_warning "Note: The following services were disabled: ${STOPPED_SERVICES[*]}"
    print_info "If you need them back, use: sudo systemctl enable --now <service>"
fi

print_success "Setup complete! You can now connect to WiFi networks using iwctl."