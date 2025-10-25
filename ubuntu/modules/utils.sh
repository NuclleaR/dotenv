#!/bin/bash

# Utility functions for Ubuntu bootstrap script



# Check if running on Ubuntu or Pop!_OS
check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot determine OS version"
        exit 1
    fi

    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "pop" && "$ID" != "neon" ]]; then
        log_error "This script is designed for Ubuntu or Pop!_OS only"
        log_error "Detected: $ID"
        exit 1
    fi

    if [[ "$ID" == "pop" ]]; then
        log_success "Detected Pop!_OS $VERSION"
    else
        log_success "Detected Ubuntu $VERSION"
    fi
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    sudo apt update && sudo apt upgrade -y
    log_success "System packages updated"
}
