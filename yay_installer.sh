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
        exit 1
    fi
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Do not run this script as root or with sudo"
    exit 1
fi

print_info "Starting yay installation process..."

# Update system
print_info "Updating system packages..."
sudo pacman -Syu --noconfirm
check_status "System updated successfully" "Failed to update system"

# Install base-devel and git if not already installed
print_info "Installing required dependencies (base-devel and git)..."
sudo pacman -S --needed --noconfirm base-devel git
check_status "Dependencies installed successfully" "Failed to install dependencies"

# Create temporary directory
print_info "Creating temporary directory..."
mkdir -p /tmp/yay
check_status "Temporary directory created" "Failed to create temporary directory"

# Clone yay repository
print_info "Downloading yay from AUR..."
cd /tmp/yay
git clone https://aur.archlinux.org/yay.git
check_status "Yay repository cloned successfully" "Failed to clone yay repository"

# Build and install yay
print_info "Building and installing yay..."
cd yay
makepkg -si --noconfirm
check_status "Yay installed successfully" "Failed to build/install yay"

# Clean up
print_info "Cleaning up temporary files..."
cd
rm -rf /tmp/yay
check_status "Temporary files removed" "Failed to remove temporary files"

# Verify installation
print_info "Verifying yay installation..."
if command -v yay &> /dev/null; then
    YAY_VERSION=$(yay --version | head -n 1)
    print_success "Yay is installed successfully!"
    print_info "Version: $YAY_VERSION"
else
    print_error "Yay installation verification failed"
    exit 1
fi

print_success "Installation complete! You can now use 'yay' to install AUR packages."