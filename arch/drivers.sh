#!/bin/bash

# Arch Linux Drivers Installation Script
# Install GPU drivers with proper kernel headers detection

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source common utilities and logger
source "$SCRIPT_DIR/common/logger.sh"

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Detect kernel type (linux or linux-lts) - silent version
detect_kernel_silent() {
    local kernel_version=$(uname -r)

    if [[ "$kernel_version" =~ "lts" ]]; then
        echo "lts"
    else
        echo "standard"
    fi
}

# Detect kernel type (linux or linux-lts)
detect_kernel() {
    log_info "Detecting kernel type..."

    local kernel_version=$(uname -r)
    log_info "Current kernel: $kernel_version"

    if [[ "$kernel_version" =~ "lts" ]]; then
        echo "lts"
    else
        echo "standard"
    fi
}

# Get appropriate headers package
get_headers_package() {
    local kernel_type=$1

    if [[ "$kernel_type" == "lts" ]]; then
        echo "linux-lts-headers"
    else
        echo "linux-headers"
    fi
}

# Check if headers are installed
check_headers() {
    local headers_package=$1

    if pacman -Qi "$headers_package" &>/dev/null; then
        log_success "$headers_package is already installed"
        return 0
    else
        return 1
    fi
}

# Install kernel headers
install_headers() {
    local headers_package=$1

    log_info "Installing $headers_package..."
    pacman -S --noconfirm "$headers_package"
    log_success "$headers_package installed successfully"
}

# Check if NVIDIA GPU is present
check_nvidia_gpu() {
    log_info "Checking for NVIDIA GPU..."

    if lspci | grep -i nvidia &>/dev/null; then
        log_success "NVIDIA GPU detected"
        return 0
    else
        log_warning "No NVIDIA GPU detected"
        return 1
    fi
}

# Install NVIDIA drivers
install_nvidia_drivers() {
    log_info "Installing NVIDIA drivers..."

    # Check if already installed
    if pacman -Qi nvidia-open-dkms &>/dev/null && pacman -Qi nvidia-utils &>/dev/null; then
        log_success "NVIDIA drivers already installed"
        log_info "nvidia-open-dkms version: $(pacman -Qi nvidia-open-dkms | grep Version | awk '{print $3}')"
        log_info "nvidia-utils version: $(pacman -Qi nvidia-utils | grep Version | awk '{print $3}')"
        return 0
    fi

    log_info "Installing nvidia-open-dkms and nvidia-utils..."
    pacman -S --noconfirm nvidia-open-dkms nvidia-utils

    log_success "NVIDIA drivers installed successfully"
    log_info "nvidia-open-dkms version: $(pacman -Qi nvidia-open-dkms | grep Version | awk '{print $3}')"
    log_info "nvidia-utils version: $(pacman -Qi nvidia-utils | grep Version | awk '{print $3}')"
}

# Install 32-bit NVIDIA utilities (for gaming)
install_lib32_nvidia() {
    log_info "Installing lib32-nvidia-utils (32-bit support for gaming)..."

    if pacman -Qi lib32-nvidia-utils &>/dev/null; then
        log_success "lib32-nvidia-utils already installed"
        return 0
    fi

    log_info "Installing lib32-nvidia-utils..."
    pacman -S --noconfirm lib32-nvidia-utils
    log_success "lib32-nvidia-utils installed successfully"
}

# Install VDPAU libraries (for video decoding)
install_vdpau() {
    log_info "Installing VDPAU libraries (GPU video decoding)..."

    local packages=(
        "libvdpau"
        "lib32-libvdpau"
    )

    for package in "${packages[@]}"; do
        if ! pacman -Qi "$package" &>/dev/null; then
            log_info "Installing $package..."
            pacman -S --noconfirm "$package"
        else
            log_success "$package already installed"
        fi
    done

    log_success "VDPAU libraries installed successfully"
}

# Rebuild modules
rebuild_modules() {
    log_info "Rebuilding kernel modules..."

    # dkms is automatically handled by pacman, but we can verify
    if command -v dkms &>/dev/null; then
        log_info "Rebuilding DKMS modules..."
        dkms status
    fi

    log_success "Kernel modules ready"
}

# Show help
show_help() {
    echo "Arch Linux Drivers Installation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n, --nvidia                   Install NVIDIA drivers (open-source)"
    echo "  -32, --lib32                   Install lib32-nvidia-utils (gaming support)"
    echo "  --vdpau                        Install VDPAU libraries (video decoding)"
    echo "  -a, --all                      Install NVIDIA drivers + all libraries"
    echo "  --versions                     Show installed driver versions"
    echo "  -h, --help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo $0 -n                     # Install NVIDIA drivers only"
    echo "  sudo $0 -n --vdpau             # Install drivers + video decoding"
    echo "  sudo $0 -n -32                 # Install drivers + 32-bit gaming support"
    echo "  sudo $0 -a                     # Install everything"
    echo "  $0 --versions                  # Show driver versions"
}

# Show installed versions
show_versions() {
    log_info "Installed drivers:"

    local kernel_type=$(detect_kernel_silent)
    local headers_package=$(get_headers_package "$kernel_type")
    local kernel_version=$(uname -r)

    echo "Kernel type: $kernel_type"
    echo "Kernel version: $kernel_version"
    echo "Headers: $(pacman -Qi "$headers_package" 2>/dev/null | grep -i "версія\|version" | awk '{print $3}' | head -1 || echo 'Not installed')"
    echo ""
    echo "NVIDIA Drivers:"
    echo "  nvidia-open-dkms: $(pacman -Qi nvidia-open-dkms 2>/dev/null | grep -i "версія\|version" | awk '{print $3}' | head -1 || echo 'Not installed')"
    echo "  nvidia-utils: $(pacman -Qi nvidia-utils 2>/dev/null | grep -i "версія\|version" | awk '{print $3}' | head -1 || echo 'Not installed')"
    echo ""
    echo "Optional Libraries:"
    echo "  lib32-nvidia-utils: $(pacman -Qi lib32-nvidia-utils 2>/dev/null | grep -i "версія\|version" | awk '{print $3}' | head -1 || echo 'Not installed')"
    echo "  libvdpau: $(pacman -Qi libvdpau 2>/dev/null | grep -i "версія\|version" | awk '{print $3}' | head -1 || echo 'Not installed')"
    echo "  lib32-libvdpau: $(pacman -Qi lib32-libvdpau 2>/dev/null | grep -i "версія\|version" | awk '{print $3}' | head -1 || echo 'Not installed')"
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        return 0
    fi

    local do_nvidia=false
    local do_lib32=false
    local do_vdpau=false
    local do_all=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                return 0
                ;;
            --versions)
                show_versions
                return 0
                ;;
            --nvidia|-n)
                do_nvidia=true
                shift
                ;;
            --lib32|-32)
                do_lib32=true
                shift
                ;;
            --vdpau)
                do_vdpau=true
                shift
                ;;
            --all|-a)
                do_all=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                return 1
                ;;
        esac
    done

    # Check root privileges
    if [[ "$do_nvidia" == true || "$do_lib32" == true || "$do_vdpau" == true || "$do_all" == true ]]; then
        check_root
    fi

    # Detect kernel and setup headers
    local kernel_type=$(detect_kernel)
    local headers_package=$(get_headers_package "$kernel_type")

    if [[ "$do_nvidia" == true || "$do_all" == true ]]; then
        log_info "Setting up kernel headers for $kernel_type kernel..."

        if ! check_headers "$headers_package"; then
            install_headers "$headers_package"
        fi

        # Check for NVIDIA GPU
        if check_nvidia_gpu; then
            install_nvidia_drivers
            rebuild_modules
            log_success "NVIDIA drivers setup completed!"
            log_warning "You may need to reboot for drivers to take full effect"
        else
            log_error "No NVIDIA GPU detected. Skipping driver installation."
            return 1
        fi
    fi

    if [[ "$do_lib32" == true || "$do_all" == true ]]; then
        install_lib32_nvidia
    fi

    if [[ "$do_vdpau" == true || "$do_all" == true ]]; then
        install_vdpau
    fi

    if [[ "$do_nvidia" == false && "$do_lib32" == false && "$do_vdpau" == false && "$do_all" == false ]]; then
        log_error "No operation specified"
        show_help
        return 1
    fi

    echo ""
    log_success "Driver installation completed!"
}

# Run main function
main "$@"
