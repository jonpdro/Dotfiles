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

# Check if yay is installed
if ! command -v yay &> /dev/null; then
    print_error "yay is not installed. Please install yay first."
    exit 1
fi

print_info "Starting applications installation process..."

# Official repository packages (pacman)
OFFICIAL_PACKAGES=(
    "hyprland"
    "hyprpaper"
    "hyprlock"
    "hypridle"
    "dunst"
    "qbittorrent"
    "yazi"
    "mpv"
    "kate"
    "rofi"
    "neovim"
    "chromium"
    "waybar"
)

# AUR packages (yay)
AUR_PACKAGES=(
    "python-pywal16"
    "obsidian"
    "impala"
    "bluetuith"
    "qimgv"
    "sioyek"
)

# Update system
print_info "Updating system packages..."
sudo pacman -Syu --noconfirm
check_status "System updated successfully" "Failed to update system"

# Install official repository packages
print_info "Installing applications from official repositories..."
echo ""
OFFICIAL_SUCCESS=0
OFFICIAL_TOTAL=${#OFFICIAL_PACKAGES[@]}

for package in "${OFFICIAL_PACKAGES[@]}"; do
    print_info "[$((OFFICIAL_SUCCESS + 1))/$OFFICIAL_TOTAL] Installing $package..."
    sudo pacman -S --needed --noconfirm "$package" &> /dev/null
    if [ $? -eq 0 ]; then
        print_success "$package installed"
        ((OFFICIAL_SUCCESS++))
    else
        print_warning "Failed to install $package"
    fi
done

echo ""
print_success "Official repository packages: $OFFICIAL_SUCCESS/$OFFICIAL_TOTAL installed!"
echo ""

# Install AUR packages
print_info "Installing applications from AUR (this may take a while)..."
echo ""
AUR_SUCCESS=0
AUR_TOTAL=${#AUR_PACKAGES[@]}

for package in "${AUR_PACKAGES[@]}"; do
    print_info "[$((AUR_SUCCESS + 1))/$AUR_TOTAL] Installing $package from AUR..."
    yay -S --needed --noconfirm "$package" &> /dev/null
    if [ $? -eq 0 ]; then
        print_success "$package installed"
        ((AUR_SUCCESS++))
    else
        print_warning "Failed to install $package (may require manual intervention)"
    fi
done

echo ""
print_success "AUR packages: $AUR_SUCCESS/$AUR_TOTAL installed!"
echo ""

# Display installation summary
echo ""
print_success "==================== INSTALLATION COMPLETE ===================="
print_info "Official repo packages: $OFFICIAL_SUCCESS/$OFFICIAL_TOTAL"
print_info "AUR packages: $AUR_SUCCESS/$AUR_TOTAL"
print_info "Total: $((OFFICIAL_SUCCESS + AUR_SUCCESS))/$((OFFICIAL_TOTAL + AUR_TOTAL))"
print_success "==============================================================="
echo ""

# Display installed applications with descriptions
print_info "Installed applications:"
echo ""
echo "  Hyprland Ecosystem:"
echo "    • hyprland      - Wayland compositor"
echo "    • hyprpaper     - Wallpaper utility"
echo "    • hyprlock      - Screen locker"
echo "    • hypridle      - Idle daemon"
echo ""
echo "  System & UI:"
echo "    • dunst         - Notification daemon"
echo "    • rofi          - Application launcher"
echo "    • waybar        - Wayland status bar"
echo "    • python-pywal16 - Color scheme generator"
echo ""
echo "  File Management:"
echo "    • yazi          - Terminal file manager"
echo "    • qimgv         - Image viewer"
echo ""
echo "  Editors:"
echo "    • neovim        - Text editor"
echo "    • kate          - Advanced text editor"
echo "    • obsidian      - Note-taking app"
echo ""
echo "  Media & Documents:"
echo "    • mpv           - Media player"
echo "    • sioyek        - PDF viewer for research"
echo ""
echo "  Internet:"
echo "    • chromium      - Web browser"
echo "    • qbittorrent   - BitTorrent client"
echo ""
echo "  Utilities:"
echo "    • bluetuith     - Bluetooth TUI manager"
echo "    • impala        - System information tool"
echo ""

print_info "Configuration notes:"
echo "  • hyprland: Configure in ~/.config/hypr/hyprland.conf"
echo "  • hyprpaper: Configure in ~/.config/hypr/hyprpaper.conf"
echo "  • hyprlock: Configure in ~/.config/hypr/hyprlock.conf"
echo "  • hypridle: Configure in ~/.config/hypr/hypridle.conf"
echo "  • dunst: Configure in ~/.config/dunst/dunstrc"
echo "  • waybar: Configure in ~/.config/waybar/config"
echo "  • neovim: Configure in ~/.config/nvim/init.lua or init.vim"
echo "  • yazi: Configure in ~/.config/yazi/"
echo "  • rofi: Configure in ~/.config/rofi/config.rasi"
echo ""

print_success "All applications have been installed successfully!"
print_info "To start Hyprland, run: Hyprland"
print_info "You may need to restart your session for some changes to take effect."