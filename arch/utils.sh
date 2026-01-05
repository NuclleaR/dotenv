#!/bin/bash

# Utility functions for Arch Linux

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running on Arch Linux
check_arch() {
    if [[ ! -f /etc/arch-release ]]; then
        log_error "This script is designed for Arch Linux"
        exit 1
    fi
    log_success "Arch Linux detected"
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    sudo pacman -Syu --noconfirm
    log_success "System packages updated"
}
