#!/bin/bash

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

install_cargo_app() {
    local appname="${1}"
    log_info "Installing ${appname} via cargo..."

    if command_exists "$appname"; then
        log_success "${appname} already installed"
        log_info "${appname} version: $($appname --version)"
        return
    fi

    if ! command_exists cargo; then
        log_error "Cargo not found. Please install Rust first."
        return 1
    fi

    cargo install "$appname"
    log_success "${appname} installed successfully"
}
