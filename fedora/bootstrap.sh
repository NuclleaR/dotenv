#!/bin/bash

# Fedora Linux Bootstrap Script
# This script installs essential development tools and packages

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running on Fedora
check_fedora() {
    if [[ ! -f /etc/fedora-release ]]; then
        log_error "This script is designed for Fedora Linux only"
        exit 1
    fi
    log_success "Detected Fedora Linux: $(cat /etc/fedora-release)"
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    sudo dnf update -y
    log_success "System packages updated"
}

# Install essential development packages
install_development_packages() {
    log_info "Installing essential development packages..."

    local packages=(
        "git"
        "curl"
        "wget"
        "zsh"
        "htop"
        "tree"
    )

    sudo dnf install -y "${packages[@]}"
    log_success "Essential development packages installed"
}

# Install RPM Fusion repositories
install_rpm_fusion() {
    log_info "Installing RPM Fusion repositories..."

    if ! rpm -qa | grep -q rpmfusion-free-release; then
        sudo dnf install -y \
            https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
            https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
        log_success "RPM Fusion repositories installed"
    else
        log_success "RPM Fusion repositories already installed"
    fi
}

# Install multimedia codecs
install_multimedia_codecs() {
    log_info "Installing multimedia codecs..."
    sudo dnf install -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
    sudo dnf install -y gstreamer1-plugins-{bad-\*,good-\*,base} gstreamer1-plugin-openh264 gstreamer1-libav --exclude=gstreamer1-plugins-bad-free-devel
    sudo dnf install -y lame\* --exclude=lame-devel
    sudo dnf group upgrade -y --setopt=group_package_types=mandatory,default,optional Multimedia
    log_success "Multimedia codecs installed"
}

# Install Flatpak
install_flatpak() {
    log_info "Setting up Flatpak..."

    if ! command_exists flatpak; then
        sudo dnf install -y flatpak
        log_success "Flatpak installed"
    else
        log_success "Flatpak already installed"
    fi

    # Add Flathub repository
    if ! flatpak remotes | grep -q flathub; then
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        log_success "Flathub repository added"
    else
        log_success "Flathub repository already configured"
    fi
}

# Install Zsh and set as default shell
install_zsh() {
    log_info "Configuring Zsh..."

    # Verify Zsh is installed
    if ! command_exists zsh; then
        log_error "Zsh is not installed"
        return 1
    fi
    log_success "Zsh is available"

    # Check if Zsh is already the default shell
    if [[ "$SHELL" == *"zsh" ]]; then
        log_success "Zsh is already the default shell"
        return 0
    fi

    # Get the path to zsh
    local zsh_path
    zsh_path=$(command -v zsh)
    log_info "Found zsh at: $zsh_path"

    # Method 1: Use usermod (recommended for system-wide change)
    log_info "Setting zsh as default shell using usermod..."
    if sudo usermod -s "$zsh_path" "$USER"; then
        log_success "Successfully set zsh as default shell"
        log_warning "Please log out and log back in to use zsh as your default shell"

        # Switch to zsh for the remainder of the script
        log_info "Switching to zsh for current session..."
        export SHELL="$zsh_path"
        return 0
    else
        log_error "Failed to set zsh as default shell"
        log_error "You may need to set it manually with: sudo usermod -s $zsh_path $USER"
        exit 1
    fi
}

# Install Starship prompt
install_starship() {
    log_info "Installing Starship prompt..."

    if ! command_exists starship; then
        curl -sS https://starship.rs/install.sh | sh -s -- -y

        # Add starship init to shell config if not already present
        if ! grep -q "starship init" ~/.zshrc 2>/dev/null; then
            echo 'eval "$(starship init zsh)"' >> ~/.zshrc
        fi

        log_success "Starship installed and configured"
    else
        log_success "Starship already installed"
    fi
}

# Install mise (formerly rtx) - runtime version manager
install_mise() {
    log_info "Installing mise CLI..."

    if ! command_exists mise; then
        log_info "Downloading and installing mise..."
        curl https://mise.run | sh

        # The installer should automatically add activation to .zshrc, but let's verify
        if [[ -f "$HOME/.local/bin/mise" ]]; then
            log_success "mise CLI installed successfully to ~/.local/bin/mise"

            # Check if activation is already in .zshrc
            if ! grep -q "mise activate" ~/.zshrc 2>/dev/null; then
                log_info "Adding mise activation to ~/.zshrc"
                echo 'eval "$($HOME/.local/bin/mise activate zsh)"' >> ~/.zshrc
            fi

            # Source mise for current session to make it available immediately
            if [[ -f "$HOME/.local/bin/mise" ]]; then
                export PATH="$HOME/.local/bin:$PATH"
                eval "$($HOME/.local/bin/mise activate zsh)" 2>/dev/null || true
            fi

            log_success "mise CLI configured and activated"
            log_info "Run 'mise doctor' after restart to verify setup"
        else
            log_error "mise installation may have failed - binary not found in ~/.local/bin/mise"
        fi
    else
        log_success "mise CLI already installed"
        log_info "Updating mise to latest version..."
        mise self-update
        log_success "mise updated"

        # Ensure activation is in .zshrc for existing installations
        if ! grep -q "mise activate" ~/.zshrc 2>/dev/null; then
            log_info "Adding mise activation to ~/.zshrc"
            if command_exists mise; then
                echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
            elif [[ -f "$HOME/.local/bin/mise" ]]; then
                echo 'eval "$($HOME/.local/bin/mise activate zsh)"' >> ~/.zshrc
            fi
        fi
    fi
}

# Install bat (better cat)
install_bat() {
    log_info "Installing bat (better cat)..."

    if ! command_exists bat; then
        sudo dnf install -y bat
        log_success "bat installed"
    else
        log_success "bat already installed"
    fi
}

# Install eza (better ls)
install_eza() {
    log_info "Installing eza (better ls)..."

    if ! command_exists eza; then
        # Install from GitHub releases since eza might not be in Fedora repos
        local latest_url=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | grep "browser_download_url.*x86_64-unknown-linux-gnu.tar.gz" | cut -d '"' -f 4)
        if [[ -n "$latest_url" ]]; then
            cd /tmp
            wget "$latest_url" -O eza.tar.gz
            tar -xzf eza.tar.gz
            sudo mv eza /usr/local/bin/
            rm eza.tar.gz
            log_success "eza installed"
        else
            log_warning "Could not download eza, skipping..."
        fi
    else
        log_success "eza already installed"
    fi
}

# Install fd (better find)
install_fd() {
    log_info "Installing fd (better find)..."

    if ! command_exists fd; then
        sudo dnf install -y fd-find
        log_success "fd installed"
    else
        log_success "fd already installed"
    fi
}

# Install ripgrep (better grep)
install_ripgrep() {
    log_info "Installing ripgrep (better grep)..."

    if ! command_exists rg; then
        sudo dnf install -y ripgrep
        log_success "ripgrep installed"
    else
        log_success "ripgrep already installed"
    fi
}

# Install fzf (fuzzy finder)
install_fzf() {
    log_info "Installing fzf (fuzzy finder)..."

    if ! command_exists fzf; then
        sudo dnf install -y fzf
        log_success "fzf installed"
    else
        log_success "fzf already installed"
    fi

    # Configure fzf with bat integration following official documentation
    log_info "Setting up fzf shell integration and bat preview..."

    # Add fzf shell integration and configuration to .zshrc if not already present
    if ! grep -q "fzf --zsh" ~/.zshrc 2>/dev/null; then
        cat >> ~/.zshrc << 'EOF'

# Set up fzf key bindings and fuzzy completion
source <(fzf --zsh)

# Preview file content using bat (https://github.com/sharkdp/bat)
export FZF_CTRL_T_OPTS="
  --walker-skip .git,node_modules,target
  --preview 'bat -n --color=always {}'
  --bind 'ctrl-/:change-preview-window(down|hidden|)'"

# Print tree structure in the preview window for ALT-C
export FZF_ALT_C_OPTS="
  --walker-skip .git,node_modules,target
  --preview 'tree -C {}'"

# Advanced customization of fzf options via _fzf_comprun function
# - The first argument to the function is the name of the command.
# - You should make sure to pass the rest of the arguments ($@) to fzf.
_fzf_comprun() {
  local command=$1
  shift

  case "$command" in
    cd)           fzf --preview 'tree -C {} | head -200'   "$@" ;;
    export|unset) fzf --preview "eval 'echo \$'{}"         "$@" ;;
    ssh)          fzf --preview 'dig {}'                   "$@" ;;
    *)            fzf --preview 'bat -n --color=always {}' "$@" ;;
  esac
}
EOF
        log_success "fzf configured with bat integration and shell key bindings"
    else
        log_success "fzf configuration already exists in ~/.zshrc"
    fi
}

# Install dust (better du)
install_dust() {
    log_info "Installing dust (better du)..."

    if ! command_exists dust; then
        # Install from Fedora official repositories (package name is du-dust)
        if sudo dnf install -y du-dust; then
            log_success "dust installed from Fedora repositories"
        else
            log_warning "Could not install dust from repositories"
        fi
    else
        log_success "dust already installed"
    fi
}

# Install Node.js using mise
install_nodejs() {
    log_info "Installing Node.js using mise..."

    if command_exists mise; then
        log_info "Installing Node.js LTS using mise..."
        if mise install node@lts 2>/dev/null && mise use -g node@lts 2>/dev/null; then
            log_success "Node.js (LTS) installed via mise"
        else
            log_warning "Failed to install Node.js via mise, falling back to system package"
            sudo dnf install -y nodejs npm
            log_success "Node.js installed via system package manager"
        fi
    else
        log_warning "mise not available, installing Node.js via system package"
        sudo dnf install -y nodejs npm
        log_success "Node.js installed via system package manager"
    fi
}

# Install Bun using mise
install_bun() {
    log_info "Installing Bun using mise..."

    if command_exists mise; then
        log_info "Installing Bun latest using mise..."
        if mise install bun@latest 2>/dev/null && mise use -g bun@latest 2>/dev/null; then
            log_success "Bun installed via mise"
        else
            log_warning "Failed to install Bun via mise, you can install it manually later"
        fi
    else
        log_warning "mise not available, skipping Bun installation"
        log_info "You can install Bun manually later with: curl -fsSL https://bun.sh/install | bash"
    fi
}

# Install pnpm
install_pnpm() {
    log_info "Installing pnpm..."

    if ! command_exists pnpm; then
        # Install pnpm standalone and configure for zsh
        log_info "Installing pnpm via standalone installer..."
        curl -fsSL https://get.pnpm.io/install.sh | sh -

        # Add pnpm to .zshrc if not already present
        if [[ -f "$HOME/.local/share/pnpm/pnpm" ]] && ! grep -q "PNPM_HOME" ~/.zshrc 2>/dev/null; then
            log_info "Adding pnpm to ~/.zshrc..."
            echo '' >> ~/.zshrc
            echo '# pnpm' >> ~/.zshrc
            echo 'export PNPM_HOME="$HOME/.local/share/pnpm"' >> ~/.zshrc
            echo 'case ":$PATH:" in' >> ~/.zshrc
            echo '  *":$PNPM_HOME:"*) ;;' >> ~/.zshrc
            echo '  *) export PATH="$PNPM_HOME:$PATH" ;;' >> ~/.zshrc
            echo 'esac' >> ~/.zshrc
            echo '# pnpm end' >> ~/.zshrc
        else
            log_success "pnpm configuration already exists in ~/.zshrc"
        fi

        log_success "pnpm installed via standalone installer"
    else
        log_success "pnpm already installed"
    fi
}

# Install Java Development Kit
install_jdk() {
    log_info "Installing OpenJDK..."

    # Install OpenJDK 21 (LTS)
    sudo dnf install -y java-21-openjdk java-21-openjdk-devel

    # Set JAVA_HOME in shell config
    if ! grep -q "JAVA_HOME.*java-21-openjdk" ~/.zshrc 2>/dev/null; then
        # Remove any existing JAVA_HOME line first
        if grep -q "JAVA_HOME" ~/.zshrc 2>/dev/null; then
            sed -i '/JAVA_HOME/d' ~/.zshrc
        fi
        echo 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk' >> ~/.zshrc
        log_info "JAVA_HOME configured to point to OpenJDK 21"
    fi

    log_success "OpenJDK 21 installed"
}

# Install Docker
install_docker() {
    log_info "Installing Docker..."

    if ! command_exists docker; then
        # Uninstall old versions - EXACT commands from Docker docs
        log_info "Removing old Docker packages if they exist..."
        sudo dnf remove docker \
                        docker-client \
                        docker-client-latest \
                        docker-common \
                        docker-latest \
                        docker-latest-logrotate \
                        docker-logrotate \
                        docker-selinux \
                        docker-engine-selinux \
                        docker-engine || true

        # Set up the repository - EXACT commands from Docker docs
        log_info "Installing dnf-plugins-core..."
        sudo dnf -y install dnf-plugins-core

        log_info "Adding Docker repository..."
        sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

        # Install Docker Engine - EXACT commands from Docker docs
        log_info "Installing Docker packages..."
        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        # Start Docker - EXACT commands from Docker docs
        log_info "Starting Docker service..."
        sudo systemctl enable --now docker

        # Add current user to docker group
        log_info "Adding user to docker group..."
        sudo usermod -aG docker $USER

        log_success "Docker installed and configured"
        log_warning "Please log out and log back in for Docker group membership to take effect"
        log_info "You can verify the installation with: sudo docker run hello-world"
    else
        log_success "Docker already installed"
    fi
}

# Install VS Code
install_vscode() {
    log_info "Installing Visual Studio Code..."

    if ! command_exists code; then
        # Import Microsoft GPG key
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

        # Add VS Code repository
        sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'

        # Install VS Code
        sudo dnf check-update
        sudo dnf install -y code

        log_success "Visual Studio Code installed"
    else
        log_success "Visual Studio Code already installed"
    fi
}

# Install Git configuration
configure_git() {
    log_info "Configuring Git..."

    # Set up some useful Git aliases and configurations
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    git config --global core.autocrlf input

    # Useful aliases
    git config --global alias.co checkout
    git config --global alias.br branch
    git config --global alias.ci commit
    git config --global alias.st status
    git config --global alias.unstage 'reset HEAD --'
    git config --global alias.last 'log -1 HEAD'
    git config --global alias.visual '!gitk'
    git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"

    log_success "Git configured with useful aliases"
}

# Create .zshrc if it doesn't exist
create_zshrc() {
    if [[ ! -f ~/.zshrc ]]; then
        touch ~/.zshrc
        log_info "Created ~/.zshrc"
    fi
}

# Install additional useful tools
install_additional_tools() {
    log_info "Installing additional useful tools..."

    local tools=(
        "fastfetch"    # System information tool (better than neofetch)
        "btop"         # Better top/htop
        # "tmux"         # Terminal multiplexer
        "jq"           # JSON processor
        "yq"           # YAML processor
        "tree"         # Directory tree viewer
        "ncdu"         # Disk usage analyzer
        "tldr"         # Simplified man pages
    )

    sudo dnf install -y "${tools[@]}"
    log_success "Additional tools installed"
}

# Setup firewall
setup_firewall() {
    log_info "Configuring firewall..."

    # Enable firewall service
    sudo systemctl enable firewalld
    sudo systemctl start firewalld

    log_success "Firewall configured and enabled"
}

# Install Warp terminal
install_warp() {
    log_info "Installing Warp terminal..."

    if ! command_exists warp-terminal; then
        # Download and install Warp RPM package directly (as per official docs)
        log_info "Downloading Warp RPM package..."
        cd /tmp

        # Use curl with redirect following to properly download the RPM
        if curl -L "https://app.warp.dev/download?package=rpm" -o warp.rpm; then
            # Verify it's actually an RPM file
            if file warp.rpm | grep -q "RPM"; then
                # Install Warp from downloaded RPM
                log_info "Installing Warp from RPM package..."
                sudo dnf install -y ./warp.rpm
                log_success "Warp terminal installed"
            else
                log_warning "Downloaded file is not a valid RPM package, skipping Warp installation"
            fi
            # Cleanup
            rm -f warp.rpm
        else
            log_warning "Failed to download Warp RPM package, skipping installation"
        fi
    else
        log_success "Warp terminal already installed"
    fi
}

# Install Vicinae (Raycast analog for Linux)
install_vicinae() {
    log_info "Installing Vicinae (Raycast analog for Linux)..."

    if ! command_exists vicinae; then
        # Install from official Fedora COPR repository as per docs.vicinae.com
        log_info "Adding official Vicinae COPR repository..."
        sudo dnf copr enable -y gvalkov/vicinae

        log_info "Installing Vicinae from COPR repository..."
        sudo dnf install -y vicinae

        systemctl enable --user --now vicinae

        log_success "Vicinae installed successfully from official repository"

        # Configure global shortcut for Vicinae (Ctrl+Space)
        log_info "Setting up global shortcut for Vicinae (Ctrl+Space)..."

        # Check if we're in a desktop environment that supports gsettings
        if command_exists gsettings && [[ -n "$DISPLAY" ]]; then
            # Get current custom shortcuts
            local shortcuts_list=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
            local new_shortcut_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae/"

            # Add our shortcut path to the list if not already there
            if [[ "$shortcuts_list" != *"$new_shortcut_path"* ]]; then
                if [[ "$shortcuts_list" == "@as []" ]]; then
                    # First custom shortcut
                    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$new_shortcut_path']"
                else
                    # Add to existing shortcuts
                    local updated_list=${shortcuts_list%]}
                    updated_list="${updated_list}, '$new_shortcut_path']"
                    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$updated_list"
                fi
            fi

            # Configure the shortcut
            gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$new_shortcut_path name 'Vicinae'
            gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$new_shortcut_path command 'vicinae'
            gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$new_shortcut_path binding '<Control>space'

            log_success "Global shortcut Ctrl+Space configured for Vicinae"
        else
            log_warning "Desktop environment not detected - you'll need to configure shortcut manually"
        fi

        log_info "You can launch Vicinae from the applications menu, by running 'vicinae' in terminal, or with Ctrl+Space"
    else
        log_success "Vicinae already installed"
    fi
}

# Configure keyboard shortcuts and language switching
configure_keyboard() {
    log_info "Configuring keyboard shortcuts..."

    # Check if we're in a desktop environment that supports gsettings
    if command_exists gsettings && [[ -n "$DISPLAY" ]]; then
        # Configure Caps Lock as language switch
        log_info "Configuring Caps Lock as language switch..."
        gsettings set org.gnome.desktop.input-sources xkb-options "['grp:caps_toggle']"
        log_success "Caps Lock configured as language switch"
    else
        log_warning "Desktop environment not detected - you'll need to configure keyboard manually"
        log_info "To set Caps Lock as language switch manually, run: gsettings set org.gnome.desktop.input-sources xkb-options \"['grp:caps_toggle']\""
    fi
}

# Main installation function
main() {
    log_info "Starting Fedora Linux Bootstrap Process..."
    echo "=========================================="

    check_fedora
    create_zshrc
    update_system
    install_development_packages
    install_rpm_fusion
    # install_multimedia_codecs
    install_flatpak
    install_zsh
    install_starship
    install_mise
    install_bat
    install_eza
    install_fd
    install_ripgrep
    install_fzf
    install_dust
    install_nodejs
    install_bun
    install_pnpm
    install_jdk
    install_docker
    # install_vscode
    configure_git
    install_additional_tools
    # setup_firewall
    install_warp
    install_vicinae
    configure_keyboard

    echo "=========================================="
    log_success "Bootstrap completed successfully!"
    log_info "Please restart your terminal or run 'source ~/.zshrc' to apply all changes"
    log_warning "If you installed Docker, please log out and log back in for group membership to take effect"

    # Apply shell changes immediately
    log_info "Applying shell configuration changes..."
    if [[ -f ~/.zshrc ]]; then
        # Source the new configuration in current shell
        source ~/.zshrc 2>/dev/null || true
        log_success "Shell configuration reloaded"
    fi

    # Show installed versions
    echo ""
    log_info "Installed versions:"
    echo "Git: $(git --version 2>/dev/null || echo 'Not available')"
    echo "Zsh: $(zsh --version 2>/dev/null || echo 'Not available')"
    echo "Starship: $(starship --version 2>/dev/null || echo 'Not available')"
    echo "mise: $(mise --version 2>/dev/null || echo 'Not available')"
    echo "bat: $(bat --version 2>/dev/null || echo 'Not available')"
    echo "eza: $(eza --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "dust: $(dust --version 2>/dev/null || echo 'Not available')"
    echo "Node.js: $(node --version 2>/dev/null || echo 'Not available')"
    echo "Bun: $(bun --version 2>/dev/null || echo 'Not available')"
    echo "pnpm: $(pnpm --version 2>/dev/null || echo 'Not available')"
    echo "Java: $(java --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "Docker: $(docker --version 2>/dev/null || echo 'Not available')"
    echo "VS Code: $(code --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "Warp: $(warp-terminal --version 2>/dev/null || echo 'Not available')"
    echo "Vicinae: $(vicinae --version 2>/dev/null || (test -f /usr/local/bin/vicinae && echo 'Installed as AppImage') || echo 'Not available')"

    echo ""
    log_info "To fully apply all changes, you have the following options:"
    echo "  1. Restart your terminal manually"
    echo "  2. Run: source ~/.zshrc"
    echo "  3. Log out and log back in (recommended for Docker group changes)"
    echo ""

    # Ask user if they want to restart the shell automatically
    read -p "Would you like to start a new Zsh session now? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Starting new Zsh session..."
        log_warning "Type 'exit' to return to the original shell"
        exec zsh
    else
        log_info "You can manually restart your terminal or run 'source ~/.zshrc' when ready"
    fi
}

# Run the main function
main "$@"