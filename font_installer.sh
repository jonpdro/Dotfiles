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

print_info "Starting comprehensive font installation process..."

# Official repository fonts
OFFICIAL_FONTS=(
    # Original fonts
    "adobe-source-code-pro-fonts"
    "adobe-source-sans-fonts"
    "adobe-source-serif-fonts"
    "noto-fonts"
    "noto-fonts-cjk"
    "noto-fonts-emoji"
    "noto-fonts-extra"
    "ttf-ubuntu-font-family"
    "gsfonts"
    
    # Essential symbol coverage
    "gnu-unifont"
    "gnu-free-fonts"
    "ttf-dejavu"
    "ttf-liberation"
    
    # Language-specific fonts
    "ttf-indic-otf"
    "ttf-tibetan-machine"
    "ttf-khmer"
    "ttf-hanazono"
    
    # Japanese fonts
    "otf-ipafont"
    "otf-ipaexfont"
    "adobe-source-han-sans-jp-fonts"
    "adobe-source-han-serif-jp-fonts"
    
    # Additional coverage
    "ttf-font-awesome"
    "ttf-hack"
    "ttf-inconsolata"
    "ttf-cascadia-code"
)

# AUR fonts
AUR_FONTS=(
    # Original AUR fonts
    "ttf-nerd-fonts-symbols"
    "ttf-nerd-fonts-symbols-common"
    "ttf-jetbrains-mono-nerd"
    "ttf-firacode-nerd"
    "woff2-font-awesome"
    "ttf-ms-fonts"
    
    # Additional symbol fonts
    "ttf-symbola-free"
    "ttf-ancient-fonts"
    "ttf-quivira"
    "ttf-gentium-plus"
    
    # Japanese fonts from AUR
    "otf-monapo"
    "ttf-monapo"
    "ttf-koruri"
    "ttf-mplus"
    "ttf-migu"
    "otf-takao"
    
    # Powerline and extras
    "powerline-fonts-git"
    "ttf-twemoji"
)

# Update system
print_info "Updating system packages..."
sudo pacman -Syu --noconfirm
check_status "System updated successfully" "Failed to update system"

# Install official repository fonts
print_info "Installing fonts from official repositories..."
echo ""
OFFICIAL_SUCCESS=0
OFFICIAL_TOTAL=${#OFFICIAL_FONTS[@]}

for font in "${OFFICIAL_FONTS[@]}"; do
    print_info "[$((OFFICIAL_SUCCESS + 1))/$OFFICIAL_TOTAL] Installing $font..."
    sudo pacman -S --needed --noconfirm "$font" &> /dev/null
    if [ $? -eq 0 ]; then
        print_success "$font installed"
        ((OFFICIAL_SUCCESS++))
    else
        print_warning "Failed to install $font (may not exist in repos)"
    fi
done

echo ""
print_success "Official repository fonts: $OFFICIAL_SUCCESS/$OFFICIAL_TOTAL installed successfully!"
echo ""

# Install AUR fonts
print_info "Installing fonts from AUR (this may take a while)..."
echo ""
AUR_SUCCESS=0
AUR_TOTAL=${#AUR_FONTS[@]}

for font in "${AUR_FONTS[@]}"; do
    print_info "[$((AUR_SUCCESS + 1))/$AUR_TOTAL] Installing $font from AUR..."
    yay -S --needed --noconfirm "$font" &> /dev/null
    if [ $? -eq 0 ]; then
        print_success "$font installed"
        ((AUR_SUCCESS++))
    else
        print_warning "Failed to install $font (may not exist or build failed)"
    fi
done

echo ""
print_success "AUR fonts: $AUR_SUCCESS/$AUR_TOTAL installed successfully!"
echo ""

# Update font cache
print_info "Updating font cache..."
fc-cache -fv &> /dev/null
check_status "Font cache updated successfully" "Failed to update font cache"

# Display installed fonts statistics
print_info "Checking installed fonts..."
FONT_COUNT=$(fc-list | wc -l)
FONT_FAMILIES=$(fc-list : family | sort -u | wc -l)

echo ""
print_success "==================== INSTALLATION COMPLETE ===================="
print_info "Total fonts installed: $FONT_COUNT"
print_info "Font families available: $FONT_FAMILIES"
print_info "Official repo fonts: $OFFICIAL_SUCCESS/$OFFICIAL_TOTAL"
print_info "AUR fonts: $AUR_SUCCESS/$AUR_TOTAL"
print_success "==============================================================="
echo ""
print_info "You may need to restart applications to see the new fonts."
print_info "To verify Japanese fonts: fc-list :lang=ja"
print_info "To verify symbol fonts: fc-list | grep -i symbol"