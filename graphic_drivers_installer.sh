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

print_info "Starting Xorg drivers and components installation..."

# List of packages to install
XORG_PACKAGES=(
    "libva-mesa-driver"
    "mesa"
    "vulkan-radeon"
    "xf86-video-amdgpu"
    "xf86-video-ati"
    "xorg-server"
    "xorg-xinit"
)

# Update system
print_info "Updating system packages..."
sudo pacman -Syu --noconfirm
check_status "System updated successfully" "Failed to update system"

# Install packages
print_info "Installing Xorg drivers and components..."
echo ""
SUCCESS=0
TOTAL=${#XORG_PACKAGES[@]}

for package in "${XORG_PACKAGES[@]}"; do
    print_info "[$((SUCCESS + 1))/$TOTAL] Installing $package..."
    sudo pacman -S --needed --noconfirm "$package"
    if [ $? -eq 0 ]; then
        print_success "$package installed"
        ((SUCCESS++))
    else
        print_warning "Failed to install $package"
    fi
done

echo ""
print_success "==================== INSTALLATION COMPLETE ===================="
print_info "Packages installed: $SUCCESS/$TOTAL"
print_success "==============================================================="
echo ""

# Display helpful information
print_info "Installed components:"
echo "  - Mesa drivers (OpenGL support)"
echo "  - VA-API hardware acceleration"
echo "  - Vulkan support for AMD/Radeon"
echo "  - AMD GPU drivers (amdgpu and ati)"
echo "  - Xorg server and initialization tools"
echo ""

print_info "Next steps:"
echo "  1. You may need to reboot for drivers to take effect"
echo "  2. Configure your .xinitrc file to start your window manager/DE"
echo "  3. Use 'startx' to start the X server"
echo ""

# Check if running in a VM or has AMD GPU
print_info "Checking system hardware..."
if lspci | grep -i "VGA\|3D\|Display" | grep -qi "AMD\|ATI\|Radeon"; then
    print_success "AMD/ATI/Radeon GPU detected - drivers should work properly"
elif lspci | grep -i "VGA\|3D\|Display" | grep -qi "VMware\|VirtualBox\|QEMU"; then
    print_warning "Virtual machine detected - you may need different drivers"
    print_info "Consider also installing: xf86-video-vmware or virtualbox-guest-utils"
else
    print_warning "No AMD GPU detected - these drivers may not be optimal for your hardware"
    print_info "Check 'lspci | grep VGA' to identify your graphics card"
fi

print_success "Installation complete!"