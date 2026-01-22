#!/bin/bash

# Arch Linux Bootstrap Script
# This script updates system and installs Flatpak

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$HOME/dev/dotenv"

# Source common utilities and logger
source "$SCRIPT_DIR/common/logger.sh"
source "$SCRIPT_DIR/common/git_conf.sh"
source "$SCRIPT_DIR/arch/utils.sh"
source "$SCRIPT_DIR/arch/shell.sh"
source "$SCRIPT_DIR/arch/env_setup.sh"

# Show help message
show_help() {
    echo "Arch Linux Bootstrap Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -u, --update                   Update system packages"
    echo "  -i, --install PACKAGE          Install package (flatpak, vivaldi, docker-desktop, vscode, slack, localsend, yakuake, fastfetch, shell, zed, git, rust, snapper, grub, cli, vpn, keyd, zram, kwallet, wl-clipboard)"
    echo "  -a, --all                      Update system and install Flatpak"
    echo "  -v, --versions                 Show installed versions"
    echo "  -h, --help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -u                          # Update system only"
    echo "  $0 -i flatpak                  # Install Flatpak only"
    echo "  $0 -i vivaldi                  # Install Vivaldi browser"
    echo "  $0 -i docker                   # Install Docker"
    echo "  $0 -i docker-desktop           # Install Docker Desktop"
    echo "  $0 -i vscode                   # Install Visual Studio Code"
    echo "  $0 -i slack                    # Install Slack"
    echo "  $0 -i localsend                # Install LocalSend"
    echo "  $0 -i yakuake                  # Install Yakuake (KDE Terminal)"
    echo "  $0 -i fastfetch                # Install Fastfetch (system info tool)"
    echo "  $0 -i shell                    # Install Zsh and Starship shell"
    echo "  $0 -i zed                      # Install Zed editor"
    echo "  $0 -i vpn                      # Install Tailscale"
    echo "  $0 -i git                      # Setup Git configuration"
    echo "  $0 -i snapper                  # Install Snapper for BTRFS snapshots"
    echo "  $0 -i grub                     # Setup GRUB with BTRFS support"
    echo "  $0 -i cli                      # Install CLI tools (bat, eza, zoxide, rip2, dust, skim)"
    echo "  $0 -i keyd                     # Install keyd (key remapper)"
    echo "  $0 -i zram                     # Setup Zram compressed swap"
    echo "  $0 -a                          # Update system and install Flatpak"
    echo "  $0 -u -i flatpak -i vivaldi    # Update, install Flatpak and Vivaldi"
}

# Show installed versions
show_versions() {
    log_info "Installed versions:"
    echo "Flatpak: $(flatpak --version 2>/dev/null || echo 'Not available')"
    echo "Vivaldi: $(vivaldi --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "Docker: $(command -v docker >/dev/null 2>&1 && docker --version || echo 'Not available')"
    echo "Docker Desktop: $(command -v docker-desktop >/dev/null 2>&1 && echo 'Installed' || echo 'Not available')"
    echo "VSCode: $(code --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "Slack: $(command -v slack >/dev/null 2>&1 && echo 'Installed' || echo 'Not available')"
    echo "LocalSend: $(command -v localsend >/dev/null 2>&1 && echo 'Installed' || echo 'Not available')"
    echo "Yakuake: $(command -v yakuake >/dev/null 2>&1 && echo 'Installed' || echo 'Not available')"
    echo "Fastfetch: $(command -v fastfetch >/dev/null 2>&1 && echo 'Installed' || echo 'Not available')"
    echo "Zsh: $(command -v zsh >/dev/null 2>&1 && zsh --version | head -n1 || echo 'Not available')"
    echo "Starship: $(command -v starship >/dev/null 2>&1 && starship --version | head -n1 || echo 'Not available')"
    echo "Zed: $(command -v zed >/dev/null 2>&1 && zed --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "Tailscale: $(command -v tailscale >/dev/null 2>&1 && tailscale version || echo 'Not available')"
    echo "Rust: $(command -v rustc >/dev/null 2>&1 && rustc --version | head -n1 || echo 'Not available')"
    echo "Snapper: $(command -v snapper >/dev/null 2>&1 && snapper --version | head -n1 || echo 'Not available')"
    echo "GRUB-BTRFS: $(systemctl is-enabled grub-btrfsd.service 2>/dev/null || echo 'Not available')"
}

# Main function with argument parsing
main() {
    # If no arguments provided, show help
    if [[ $# -eq 0 ]]; then
        show_help
        return
    fi

    local do_update=false
    local do_flatpak=false
    local do_vivaldi=false
    local do_docker=false
    local do_docker_desktop=false
    local do_vscode=false
    local do_slack=false
    local do_localsend=false
    local do_yakuake=false
    local do_fastfetch=false
    local do_shell=false
    local do_zed=false
    local do_tailscale=false
    local do_git=false
    local do_rust=false
    local do_snapper=false
    local do_grub=false
    local do_cli_tools=false
    local do_keyd=false
    local do_zram=false
    local do_kwallet=false
    local do_wl_clipboard=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                return 0
                ;;
            --versions|-v)
                show_versions
                return 0
                ;;
            --update|-u)
                do_update=true
                shift
                ;;
            --install|-i)
                shift
                if [[ $# -eq 0 ]]; then
                    log_error "Option -i requires a package name"
                    show_help
                    return 1
                fi
                case $1 in
                    flatpak)
                        do_flatpak=true
                        ;;
                    vivaldi)
                        do_vivaldi=true
                        ;;
                    docker)
                        do_docker=true
                        ;;
                    docker-desktop)
                        do_docker_desktop=true
                        ;;
                    vscode)
                        do_vscode=true
                        ;;
                    slack)
                        do_slack=true
                        ;;
                    localsend)
                        do_localsend=true
                        ;;
                    yakuake)
                        do_yakuake=true
                        ;;
                    fastfetch)
                        do_fastfetch=true
                        ;;
                    shell)
                        do_shell=true
                        ;;
                    zed)
                        do_zed=true
                        ;;
                    git)
                        do_git=true
                        ;;
                    rust)
                        do_rust=true
                        ;;
                    vpn)
                        do_tailscale=true
                        ;;
                    snapper)
                        do_snapper=true
                        ;;
                    grub)
                        do_grub=true
                        ;;
                    cli)
                        do_cli_tools=true
                        ;;
                    keyd)
                        do_keyd=true
                        ;;
                    zram)
                        do_zram=true
                        ;;
                    kwallet)
                        do_kwallet=true
                        ;;
                    wl-clipboard)
                        do_wl_clipboard=true
                        ;;
                    *)
                        log_error "Unknown package: $1"
                        log_info "Available packages: flatpak, vivaldi, docker-desktop, vscode, slack, localsend, yakuake, fastfetch, shell, zed, git, rust, snapper, grub, cli, vpn, keyd, zram, kwallet, wl-clipboard"
                        return 1
                        ;;
                esac
                shift
                ;;
            --all|-a)
                do_update=true
                do_flatpak=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                return 1
                ;;
        esac
    done

    # Check Arch Linux
    check_arch

    # Execute requested operations
    if [[ "$do_update" == true ]]; then
        log_info "Updating system packages..."
        update_system
        log_success "System update completed!"
    fi

    if [[ "$do_flatpak" == true ]]; then
        install_flatpak
    fi

    if [[ "$do_vivaldi" == true ]]; then
        install_vivaldi
    fi

    if [[ "$do_docker" == true ]]; then
        install_docker
    fi

    if [[ "$do_docker_desktop" == true ]]; then
        install_docker_desktop
    fi

    if [[ "$do_vscode" == true ]]; then
        install_vscode
    fi

    if [[ "$do_slack" == true ]]; then
        install_slack
    fi

    if [[ "$do_localsend" == true ]]; then
        install_localsend
    fi

    if [[ "$do_yakuake" == true ]]; then
        install_yakuake
    fi

    if [[ "$do_fastfetch" == true ]]; then
        install_fastfetch
    fi

    if [[ "$do_shell" == true ]]; then
        install_shell
    fi

    if [[ "$do_zed" == true ]]; then
        install_zed
    fi

    if [[ "$do_git" == true ]]; then
        setup_git
    fi

    if [[ "$do_rust" == true ]]; then
        install_rust
    fi

    if [[ "$do_tailscale" == true ]]; then
        install_tailscale
    fi

    if [[ "$do_snapper" == true ]]; then
        install_snapper
    fi

    if [[ "$do_grub" == true ]]; then
        setup_grub_btrfs
    fi

    if [[ "$do_cli_tools" == true ]]; then
        install_cli_tools
        configure_dotenv_sourcing
    fi

    if [[ "$do_keyd" == true ]]; then
        install_keyd
    fi

    if [[ "$do_zram" == true ]]; then
        setup_zram
    fi

    if [[ "$do_kwallet" == true ]]; then
        install_kwallet
    fi

    if [[ "$do_wl_clipboard" == true ]]; then
        install_wl_clipboard
    fi

    if [[ "$do_update" == false && "$do_flatpak" == false && "$do_vivaldi" == false && "$do_docker_desktop" == false && "$do_vscode" == false && "$do_slack" == false && "$do_localsend" == false && "$do_yakuake" == false && "$do_fastfetch" == false && "$do_shell" == false && "$do_zed" == false && "$do_git" == false && "$do_rust" == false && "$do_snapper" == false && "$do_grub" == false && "$do_cli_tools" == false && "$do_keyd" == false && "$do_zram" == false && "$do_kwallet" == false && "$do_wl_clipboard" == false ]]; then
        log_error "No operation specified"
        show_help
        return 1
    fi

    echo ""
    log_success "Bootstrap completed successfully!"
}


# Applications installation module for Arch Linux

# Install Flatpak
install_flatpak() {
    log_info "Installing Flatpak..."

    if command_exists flatpak; then
        log_success "Flatpak already installed"
        log_info "Flatpak version: $(flatpak --version)"
        return
    fi

    log_info "Installing Flatpak package..."
    sudo pacman -S --noconfirm flatpak

    log_info "Adding Flathub repository..."
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

    log_success "Flatpak installed successfully"
    log_info "Flatpak version: $(flatpak --version)"
    log_info "You may need to restart your system for all changes to take effect"
}

# Install Docker
install_docker() {
    log_info "Installing Docker..."

    if command_exists docker; then
        log_success "Docker already installed"
        log_info "Docker version: $(docker --version)"
        return
    fi

    log_info "Installing Docker..."
    # sudo pacman -S --noconfirm docker docker-compose
    sudo pacman -S --noconfirm docker

    log_info "Starting Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker

    log_info "Adding user to docker group..."
    sudo usermod -aG docker "$USER"

    log_success "Docker installed successfully"
    log_warning "Please log out and log back in for docker group membership to take effect"
}

# Install Tailscale
install_tailscale() {
    log_info "Installing Tailscale..."

    if command_exists tailscale; then
        log_success "Tailscale already installed"
        log_info "Tailscale version: $(tailscale version)"
        return
    fi

    log_info "Installing Tailscale..."
    sudo pacman -S --noconfirm tailscale

    log_info "Starting Tailscale service..."
    sudo systemctl start tailscaled
    sudo systemctl enable tailscaled

    log_success "Tailscale installed successfully"
    log_info "Run 'sudo tailscale up' to connect to your Tailscale network"
}

# Install Timeshift (system backup tool)
install_timeshift() {
    log_info "Installing Timeshift..."

    if command_exists timeshift; then
        log_success "Timeshift already installed"
        log_info "Timeshift version: $(timeshift --version)"
        return
    fi

    log_info "Installing Timeshift..."
    sudo pacman -S --noconfirm timeshift

    log_success "Timeshift installed successfully"
    log_info "Run 'sudo timeshift-gtk' to configure system backups"
}

# Install yay AUR helper if not present
install_yay() {
    if command_exists yay; then
        return 0
    fi

    log_info "Installing yay AUR helper..."

    # Install dependencies
    sudo pacman -S --needed --noconfirm base-devel git

    # Clone and build yay
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
    rm -rf "$temp_dir"

    log_success "yay AUR helper installed"
}

# Install Vivaldi browser from AUR
install_vivaldi() {
    log_info "Installing Vivaldi browser..."

    if command_exists vivaldi; then
        log_success "Vivaldi already installed"
        log_info "Vivaldi version: $(vivaldi --version 2>/dev/null | head -n1 || echo 'Unknown')"
        return
    fi

    # Ensure yay is installed
    install_yay

    log_info "Installing Vivaldi from AUR..."
    yay -S --noconfirm vivaldi

    log_success "Vivaldi installed successfully"
    log_info "You can launch Vivaldi from your application menu"
}

# Install Docker Desktop from AUR
install_docker_desktop() {
    log_info "Installing Docker Desktop..."

    if command_exists docker-desktop; then
        log_success "Docker Desktop already installed"
        return
    fi

    # Ensure yay is installed
    install_yay

    log_info "Installing Docker Desktop from AUR..."
    yay -S --noconfirm docker-desktop

    log_info "Enabling Docker Desktop service..."
    systemctl --user enable docker-desktop

    log_success "Docker Desktop installed successfully"
    log_info "You can launch Docker Desktop from your application menu"
    log_warning "Please log out and log back in, then start Docker Desktop from the application menu"
}

# Install Visual Studio Code from AUR
install_vscode() {
    log_info "Installing Visual Studio Code..."

    if command_exists code; then
        log_success "Visual Studio Code already installed"
        log_info "VSCode version: $(code --version 2>/dev/null | head -n1 || echo 'Unknown')"
        return
    fi

    # Ensure yay is installed
    install_yay

    log_info "Installing Visual Studio Code from AUR..."
    yay -S --noconfirm visual-studio-code-bin

    log_success "Visual Studio Code installed successfully"
    log_info "You can launch VSCode from your application menu or run 'code'"
}

# Install Slack from AUR
install_slack() {
    log_info "Installing Slack..."

    if command_exists slack; then
        log_success "Slack already installed"
        return
    fi

    # Ensure yay is installed
    install_yay

    log_info "Installing Slack from AUR..."
    yay -S --noconfirm slack-desktop

    log_success "Slack installed successfully"
    log_info "You can launch Slack from your application menu or run 'slack'"
}

# Install LocalSend from AUR
install_localsend() {
    log_info "Installing LocalSend..."

    if command_exists localsend; then
        log_success "LocalSend already installed"
        return
    fi

    # Ensure yay is installed
    install_yay

    log_info "Installing LocalSend from AUR..."
    yay -S --noconfirm localsend-bin

    log_success "LocalSend installed successfully"
    log_info "You can launch LocalSend from your application menu or run 'localsend'"
}

# Install Yakuake (KDE Terminal)
install_yakuake() {
    log_info "Installing Yakuake..."

    if command_exists yakuake; then
        log_success "Yakuake already installed"
        return
    fi

    # Check if KDE Plasma is installed
    if ! command_exists plasmashell; then
        log_warning "KDE Plasma is not detected. Yakuake may not work properly without it."
    fi

    log_info "Installing Yakuake from official repository..."
    sudo pacman -S --noconfirm yakuake

    log_success "Yakuake installed successfully"
    log_info "You can launch Yakuake from your application menu or press Meta+Backtick"
}

# Install Fastfetch (system info tool)
install_fastfetch() {
    log_info "Installing Fastfetch..."

    if command_exists fastfetch; then
        log_success "Fastfetch already installed"
        log_info "Fastfetch version: $(fastfetch --version 2>/dev/null | head -n1 || echo 'Unknown')"
        return
    fi

    log_info "Installing Fastfetch from official repository..."
    sudo pacman -S --noconfirm fastfetch

    log_success "Fastfetch installed successfully"
    log_info "Run 'fastfetch' to display system information"
}

# Install Zed editor from AUR
install_zed() {
    log_info "Installing Zed editor..."

    if command_exists zed; then
        log_success "Zed already installed"
        log_info "Zed version: $(zed --version 2>/dev/null | head -n1 || echo 'Unknown')"
        return
    fi

    log_info "Installing Zed from Script..."
    curl -f https://zed.dev/install.sh | sh

    log_success "Zed installed successfully"
    log_info "You can launch Zed from your application menu or run 'zed'"
}

# Install Snapper and BTRFS Assistant
install_snapper() {
    log_info "Installing Snapper for BTRFS snapshots..."

    if command_exists snapper; then
        log_success "Snapper already installed"
        log_info "Snapper version: $(snapper --version | head -n1)"
    else
        # Ensure yay is installed
        install_yay

        log_info "Installing Snapper..."
        yay -S --noconfirm snapper
        log_success "Snapper installed successfully"
    fi

    # Install BTRFS Assistant
    if ! command_exists btrfs-assistant; then
        log_info "Installing BTRFS Assistant..."
        yay -S --noconfirm btrfs-assistant
        log_success "BTRFS Assistant installed successfully"
    else
        log_success "BTRFS Assistant already installed"
    fi

    # Install snap-pac (for automatic snapshots on pacman operations)
    if ! pacman -Qi snap-pac &>/dev/null; then
        log_info "Installing snap-pac for automatic snapshots..."
        yay -S --noconfirm snap-pac
        log_success "snap-pac installed successfully"
    else
        log_success "snap-pac already installed"
    fi

    log_success "Snapper setup completed!"
    log_info "Use 'btrfs-assistant' GUI or 'snapper' CLI to manage snapshots"
    log_info "Automatic snapshots will be created before/after pacman operations"
}

# Setup GRUB with BTRFS support
setup_grub_btrfs() {
    log_info "Setting up GRUB with BTRFS snapshot support..."

    # Ensure yay is installed
    install_yay

    # Install grub-btrfs
    if ! pacman -Qi grub-btrfs &>/dev/null; then
        log_info "Installing grub-btrfs..."
        yay -S --noconfirm grub-btrfs
        log_success "grub-btrfs installed successfully"
    else
        log_success "grub-btrfs already installed"
    fi

    # Install inotify-tools (required for grub-btrfsd service)
    if ! pacman -Qi inotify-tools &>/dev/null; then
        log_info "Installing inotify-tools..."
        yay -S --noconfirm inotify-tools
        log_success "inotify-tools installed successfully"
    else
        log_success "inotify-tools already installed"
    fi

    # Enable and start grub-btrfsd service
    log_info "Enabling grub-btrfsd service..."
    sudo systemctl enable --now grub-btrfsd.service

    # Check if service is running
    if systemctl is-active --quiet grub-btrfsd.service; then
        log_success "grub-btrfsd service is running"
    else
        log_warning "grub-btrfsd service failed to start. Check status with: sudo systemctl status grub-btrfsd.service"
    fi

    # Update GRUB configuration
    log_info "Updating GRUB configuration..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    log_success "GRUB BTRFS setup completed!"
    log_info "GRUB will now automatically detect BTRFS snapshots at boot"
    log_info "Snapshots will appear in the GRUB menu under 'Arch Linux snapshots'"
}

# Install bat (better cat)
install_bat() {
    log_info "Installing bat..."

    if command_exists bat; then
        log_success "bat already installed"
        log_info "bat version: $(bat --version)"
        return
    fi

    sudo pacman -S --noconfirm bat
    log_success "bat installed successfully"
}

# Install eza (better ls)
install_eza() {
    log_info "Installing eza..."

    if command_exists eza; then
        log_success "eza already installed"
        log_info "eza version: $(eza --version | head -n2)"
        return
    fi

    sudo pacman -S --noconfirm eza
    log_success "eza installed successfully"
}

# Install zoxide (better cd)
install_zoxide() {
    log_info "Installing zoxide..."

    if command_exists zoxide; then
        log_success "zoxide already installed"
        log_info "zoxide version: $(zoxide --version)"
        return
    fi

    sudo pacman -S --noconfirm zoxide
    log_success "zoxide installed successfully"

    # Add zoxide init to shell config if not already present
    if ! grep -q "zoxide init" ~/.zshrc 2>/dev/null; then
        echo 'eval "$(zoxide init zsh)"' >> ~/.zshrc
    fi

    # zoxide (better cd) aliases
    # Replace cd with z for smart directory jumping based on frequency and recency
    # alias cd='z'
    # alias cdi='zi'  # Interactive mode with fzf-like interface
}

# Install rip2 (better rm)
install_rip2() {
    log_info "Installing rip2..."

    if command_exists rip; then
        log_success "rip2 already installed"
        log_info "rip version: $(rip --version)"
        return
    fi

    log_info "Installing rip2 via cargo..."
    if ! command_exists cargo; then
        log_error "Cargo not found. Please install Rust first."
        return 1
    fi

    cargo install rm-improved
    log_success "rip2 installed successfully"
}

# Install dust (better du)
install_dust() {
    log_info "Installing dust..."

    if command_exists dust; then
        log_success "dust already installed"
        log_info "dust version: $(dust --version)"
        return
    fi

    sudo pacman -S --noconfirm dust
    log_success "dust installed successfully"
}

# Install skim (fuzzy finder)
install_skim() {
    log_info "Installing skim (sk)..."

    if command_exists sk; then
        log_success "skim already installed"
        log_info "skim version: $(sk --version | head -n1)"
        return
    fi

    # Install via cargo to avoid missing/old distro packages
    if ! command_exists cargo; then
        log_warning "Cargo not found; continuing with upstream installer"
    fi

    # Use upstream installer to get latest stable binary (avoids old repo/AUR builds)
    local SKIM_VERSION="1.5.1"
    local SKIM_INSTALLER_URL="https://github.com/skim-rs/skim/releases/download/v${SKIM_VERSION}/skim-installer.sh"

    log_info "Downloading skim installer v${SKIM_VERSION}..."
    if ! curl --proto '=https' --tlsv1.2 -LsSf "$SKIM_INSTALLER_URL" | sh; then
        log_error "skim install failed via upstream installer"
        return 1
    fi

    log_success "skim installed successfully (v${SKIM_VERSION})"
}

# Install keyd (key remapper)
install_keyd() {
    log_info "Installing keyd..."

    if command_exists keyd; then
        log_success "keyd already installed"
        return
    fi

    log_info "Installing keyd from AUR..."
    install_yay
    yay -S --noconfirm keyd

    log_info "Setting up keyd configuration..."
    sudo mkdir -p /etc/keyd

    # Create default keyd configuration
    sudo tee /etc/keyd/default.conf > /dev/null << 'EOF'
[ids]
*

[alt]
left  = home
right = end
EOF

    log_info "Enabling keyd service..."
    sudo systemctl enable keyd
    sudo systemctl restart keyd

    log_success "keyd installed and configured successfully"
    log_info "Configuration file: /etc/keyd/default.conf"
    log_info "Service status: $(sudo systemctl is-active keyd)"
}

# Install KWallet (KDE wallet + askpass)
install_kwallet() {
    log_info "Installing KWallet..."

    # Warn if KDE is not present; KWallet still installs but may not unlock automatically
    if ! command_exists plasmashell; then
        log_warning "KDE Plasma not detected. KWallet auto-unlock may require manual PAM setup."
    fi

    sudo pacman -S --noconfirm kwallet kwalletmanager kwallet-pam ksshaskpass
    log_success "KWallet packages installed (kwalletmanager, kwallet-pam, ksshaskpass)"
    log_info "Configure PAM for auto-unlock if needed (see Arch wiki: KWallet)"
}

# Install wl-clipboard (Wayland clipboard utilities)
install_wl_clipboard() {
    log_info "Installing wl-clipboard..."

    if command_exists wl-copy && command_exists wl-paste; then
        log_success "wl-clipboard already installed"
        return
    fi

    sudo pacman -S --noconfirm wl-clipboard
    log_success "wl-clipboard installed successfully"
}

# Setup Zram (compressed swap)
setup_zram() {
    log_info "Setting up Zram (compressed swap)..."

    # Check if zram-generator is already installed
    if pacman -Qi zram-generator &>/dev/null; then
        log_success "zram-generator already installed"
    else
        log_info "Installing zram-generator..."
        sudo pacman -S --noconfirm zram-generator
        log_success "zram-generator installed"
    fi

    # Create zram configuration directory if it doesn't exist
    sudo mkdir -p /etc/systemd/zram-generator.conf.d

    log_info "Creating Zram configuration..."
    sudo tee /etc/systemd/zram-generator.conf.d/zram.conf > /dev/null << 'EOF'
# Zram configuration for systemd-zram-generator
[zram0]
compression-algorithm = zstd
zram-size = min(ram / 2, 4096)
swap-priority = 100
fs-type = swap
EOF

    log_info "Enabling systemd-zram-setup service..."
    sudo systemctl daemon-reload
    sudo systemctl enable systemd-zram-setup@zram0.service
    sudo systemctl start systemd-zram-setup@zram0.service

    if sudo systemctl is-active --quiet systemd-zram-setup@zram0.service; then
        log_success "Zram service is active"
    else
        log_warning "Zram service failed to start. Check status with: sudo systemctl status systemd-zram-setup@zram0.service"
    fi

    log_success "Zram setup completed!"
    log_info "Configuration file: /etc/systemd/zram-generator.conf.d/zram.conf"
    log_info "Monitor with: watch 'zramctl; echo; free -h'"
}

# Install Rust toolchain via rustup
install_rust() {
    log_info "Installing Rust toolchain (rustup)..."

    # Install rustup if missing
    if command_exists rustup; then
        log_success "rustup already installed"
    else
        log_info "Installing rustup from official repository..."
        sudo pacman -S --noconfirm rustup
        log_success "rustup installed"
    fi

    # Install and set stable toolchain as default
    log_info "Ensuring stable toolchain is installed..."
    rustup toolchain install stable
    rustup default stable

    # Install common components
    log_info "Installing Rust components (rustfmt, clippy)..."
    rustup component add rustfmt clippy

    log_success "Rust toolchain installed"
    log_info "Rust version: $(rustc --version 2>/dev/null || echo 'Unavailable')"
}


install_cli_tools() {
    install_bat
    install_eza
    install_zoxide
    install_rip2
    install_dust
    install_skim
}

# Run the main function
main "$@"
