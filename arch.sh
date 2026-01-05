#!/bin/bash

# Arch Linux Bootstrap Script
# This script updates system and installs Flatpak

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$HOME/dev/dotenv/arch"
DOTENV_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common utilities and logger
source "$DOTENV_ROOT/common/logger.sh"
source "$SCRIPT_DIR/modules/utils.sh"

# Show help message
show_help() {
    echo "Arch Linux Bootstrap Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -u, --update                   Update system packages"
    echo "  -i, --install PACKAGE          Install package (flatpak, vivaldi, docker-desktop, vscode, slack, localsend, yakuake, fastfetch, shell, zed)"
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
    echo "  $0 -i tailscale                # Install Tailscale"
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
}}

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
    local do_docker
    local do_docker_desktop=false
    local do_vscode=false
    local do_slack=false
    local do_localsend=false
    local do_yakuake=false
    local do_fastfetch=false
    local do_shell=false
    local do_zed=false
    local do_tailscale=false

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
                    *)
                        log_error "Unknown package: $1"
                        log_info "Available packages: flatpak, vivaldi, docker-desktop, vscode, slack, localsend, yakuake, fastfetch, shell, zed"
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

    if [[ "$do_update" == false && "$do_flatpak" == false && "$do_vivaldi" == false && "$do_docker_desktop" == false && "$do_vscode" == false && "$do_slack" == false && "$do_localsend" == false && "$do_yakuake" == false && "$do_fastfetch" == false && "$do_shell" == false && "$do_zed" == false ]]; then
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

    # Ensure yay is installed
    install_yay

    log_info "Installing Zed from AUR..."
    yay -S --noconfirm zed

    log_success "Zed installed successfully"
    log_info "You can launch Zed from your application menu or run 'zed'"
}

# Run the main function
main "$@"
