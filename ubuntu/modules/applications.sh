#!/bin/bash

# Applications installation module

# Install Warp Terminal
install_warp() {
    log_info "Installing Warp Terminal..."

    if command_exists warp-terminal; then
        log_success "Warp Terminal already installed"
        return
    fi

    log_info "Downloading Warp Terminal..."

    wget https://app.warp.dev/download?package=deb -O warp-terminal.deb

    log_info "Installing Warp Terminal..."
    sudo apt install -y ./warp-terminal.deb

    # Clean up
    rm warp-terminal.deb

    log_success "Warp Terminal installed successfully"
    log_info "You can launch it from the applications menu or run: warp-terminal"
}

# Install Tailscale VPN
install_tailscale() {
    log_info "Installing Tailscale..."

    if command_exists tailscale; then
        log_success "Tailscale already installed"
        log_info "Tailscale version: $(tailscale version 2>/dev/null || echo 'Unknown')"
        return
    fi

    log_info "Downloading and installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh

    log_success "Tailscale installed successfully"
    log_info "To start Tailscale, run: sudo tailscale up"
    log_info "To check status, run: tailscale status"
}

# Install Slack
install_slack() {
    log_info "Installing Slack..."

    if command_exists slack; then
        log_success "Slack already installed"
        return
    fi

    log_info "Installing Slack from Snap Store..."
    sudo snap install slack

    log_success "Slack installed successfully"
}

# Install Timeshift
install_timeshift() {
    log_info "Installing Timeshift..."

    if command_exists timeshift; then
        log_success "Timeshift already installed"
        return
    fi

    log_info "Installing Timeshift from APT..."
    sudo apt install -y timeshift

    log_success "Timeshift installed successfully"
    log_info "To configure Timeshift, run: sudo timeshift-gtk"
    log_info "Or use the command line: sudo timeshift --create"
}

# Install Docker Engine
install_docker() {
    log_info "Installing Docker Engine..."

    if command_exists docker; then
        log_success "Docker already installed"
        log_info "Docker version: $(docker --version 2>/dev/null || echo 'Unknown')"
        return
    fi

    # Uninstall old versions
    log_info "Removing old Docker packages if present..."
    sudo apt remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc 2>/dev/null || true

    # Set up Docker's apt repository
    log_info "Setting up Docker apt repository..."

    # Add Docker's official GPG key
    sudo apt update
    sudo apt install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    log_info "Installing Docker Engine, containerd, and Docker Compose..."
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add user to docker group
    log_info "Adding current user to docker group..."
    sudo usermod -aG docker $USER

    # Enable and start Docker service
    log_info "Enabling and starting Docker service..."
    sudo systemctl enable docker
    sudo systemctl start docker

    log_success "Docker Engine installed successfully"
    log_info "Docker version: $(sudo docker --version)"
    log_info "Docker Compose version: $(sudo docker compose version)"
    echo ""
    log_warning "=========================================="
    log_warning "You need to log out and log back in (or restart)"
    log_warning "to use Docker without sudo."
    log_warning "=========================================="
    echo ""
    log_info "Test Docker installation with: docker run hello-world"
}

# Install Vicinae (Raycast analog for Linux)
install_vicinae() {
    log_info "Installing Vicinae (Raycast analog for Linux)..."

    if command_exists vicinae; then
        log_success "Vicinae already installed"
        return
    fi

    # Install runtime dependencies according to https://docs.vicinae.com/release-install
    log_info "Installing Vicinae runtime dependencies..."
    local deps=(
        "libssl-dev"
        "libwayland-dev"
        "qt6-base-dev"
        "qt6-wayland-dev"
        # "qt6-svg-dev"
        # "qt6-svg-plugins"
        # "qt6-svg-private-dev"
        "libqt6svg6"
        "qtkeychain-qt6-dev"
        "protobuf-compiler"
        "cmark-gfm"
        "layer-shell-qt"
        "libqalculate-dev"
        "libminizip-dev"
        "zlib1g-dev"
        "librapidfuzz-cpp-dev"
        "libprotobuf-dev"
        "libcmark-gfm-dev"
    )

    sudo apt install -y "${deps[@]}"
    log_success "Runtime dependencies installed"

    # Download latest release
    log_info "Downloading latest Vicinae release..."
    local latest_version=$(curl -s https://api.github.com/repos/vicinaehq/vicinae/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)

    if [[ -z "$latest_version" ]]; then
        log_error "Failed to get latest Vicinae version"
        return 1
    fi

    log_info "Latest version: $latest_version"

    cd /tmp
    local tarball="vicinae-linux-x86_64-${latest_version}.tar.gz"
    local download_url="https://github.com/vicinaehq/vicinae/releases/download/${latest_version}/${tarball}"

    log_info "Downloading from: $download_url"
    wget "$download_url" -O "$tarball"

    # Extract to vicinae directory
    log_info "Extracting Vicinae to vicinae directory..."
    mkdir -p vicinae
    tar xvf "$tarball" -C vicinae

    # Install to system directories
    log_info "Installing to system directories..."
    sudo cp vicinae/bin/* /usr/local/bin/
    sudo cp -r vicinae/share/* /usr/local/share/

    # Clean up - remove tarball and extracted directory
    log_info "Cleaning up temporary files..."
    rm -rf "$tarball" vicinae

    log_success "Vicinae installed successfully"

    # Create systemd user service file for Vicinae
    log_info "Creating systemd user service for Vicinae..."
    mkdir -p ~/.config/systemd/user

    cat > ~/.config/systemd/user/vicinae.service << 'EOF'
[Unit]
Description=Vicinae Server
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vicinae server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    # Reload systemd user daemon and enable service
    systemctl --user daemon-reload

    log_info "Enabling and starting Vicinae server service..."
    if systemctl enable --now --user vicinae.service; then
        log_success "Vicinae server service enabled and started"
    else
        log_warning "Could not start vicinae.service automatically"
        log_info "You can start it manually with: systemctl enable --now --user vicinae.service"
        log_info "Or run the server directly with: vicinae server"
    fi

    # # Configure global shortcut for Vicinae (Ctrl+Space)
    # log_info "Setting up global shortcut for Vicinae (Ctrl+Space)..."

    # # Check if we're in a desktop environment that supports gsettings
    # if command_exists gsettings && [[ -n "$DISPLAY" ]]; then
    #     # Get current custom shortcuts
    #     local shortcuts_list=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
    #     local new_shortcut_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae/"

    #     # Add our shortcut path to the list if not already there
    #     if [[ "$shortcuts_list" != *"$new_shortcut_path"* ]]; then
    #         if [[ "$shortcuts_list" == "@as []" ]]; then
    #             # First custom shortcut
    #             gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$new_shortcut_path']"
    #         else
    #             # Add to existing shortcuts
    #             local updated_list=${shortcuts_list%]}
    #             updated_list="${updated_list}, '$new_shortcut_path']"
    #             gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$updated_list"
    #         fi
    #     fi

    #     # Configure the shortcut
    #     gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$new_shortcut_path name 'Vicinae'
    #     gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$new_shortcut_path command 'vicinae'
    #     gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$new_shortcut_path binding '<Control>space'

    #     log_success "Global shortcut Ctrl+Space configured for Vicinae"
    # else
    #     log_warning "Desktop environment not detected - you'll need to configure shortcut manually"
    # fi

    echo ""
    log_success "Vicinae installation complete!"
    log_info "To control the window, run: vicinae toggle"
    # log_info "Or use the configured Ctrl+Space shortcut"
    log_info "Server commands:"
    log_info "  - Start server: systemctl start --user vicinae.service"
    log_info "  - Stop server:  systemctl stop --user vicinae.service"
    log_info "  - Or run directly: vicinae server"
    log_info ""
    log_info "If you encounter missing library errors, run: ldd /usr/local/bin/vicinae | grep 'not'"
}
