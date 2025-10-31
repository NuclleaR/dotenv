#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$HOME/dev/dotenv/kde"
DOTENV_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTENV_ROOT/common/utils.sh"
source "$DOTENV_ROOT/common/logger.sh"

config_xremap() {
    log_info "Configuring xremap for keyboard remapping..."
    # Install xremap
    cargo install xremap --features kde

    log_success "Xremap installed successfully."

    xremap_path=$(which xremap)
    service_dir="$HOME/.config/systemd/user"

    log_info "Setting up xremap configuration and systemd service..."

    mkdir -p $HOME/.config/xremap

    log_info "Creating xremap config.yml"

    cat <<EOF | tee $HOME/.config/xremap/config.yml
# Xremap configuration file
keymap:
  - name: Global
    remap:
      Alt_L-left: home
      Alt_L-right: end
EOF

    log_success "xremap config.yml created."
    log_info "Creating systemd user service for xremap"

    cat <<EOF | tee $service_dir/xremap.service
[Unit]
Description=Xremap
After=default.target

[Service]
ExecStart=$xremap_path --watch=device %h/.config/xremap/config.yml
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

    log_success "xremap systemd service created."

    log_info "Enabling xremap service..."
    # Enable and start the xremap service
    systemctl --user daemon-reload
    systemctl --user enable xremap.service
    #systemctl --user start xremap.service

    log_success "Xremap service has been set up."

    # Setup permissions
    sudo gpasswd -a $USER input
    echo 'KERNEL=="uinput", GROUP="input", TAG+="uaccess"' | sudo tee /etc/udev/rules.d/input.rules

    log_success "Permissions for xremap configured. Reboot your system for changes to take effect."
}

config_xremap