#!/bin/bash

# Ubuntu/Pop!_OS Bootstrap Script
# This script installs essential development tools and packages
# Supports Ubuntu 24.04+ and Pop!_OS 24.04+

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTENV_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source common Git configuration
source "$DOTENV_ROOT/common/git_conf.sh"

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

# Check if running on Ubuntu or Pop!_OS
check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot determine OS version"
        exit 1
    fi

    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "pop" ]]; then
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

# Install essential development packages
install_essential_packages() {
    log_info "Installing essential development packages..."

    local packages=(
        "build-essential"
        "curl"
        "wget"
        "git"
        "zsh"
        "htop"
        "tree"
        "software-properties-common"
        "apt-transport-https"
        "ca-certificates"
        "gnupg"
        "lsb-release"
    )

    sudo apt install -y "${packages[@]}"
    log_success "Essential development packages installed"
}

# Install Git
install_git() {
    log_info "Checking for Git..."

    if ! command_exists git; then
        log_info "Installing Git..."
        sudo apt install -y git
        log_success "Git installed"
    else
        log_success "Git already installed"
        log_info "Git version: $(git --version)"
    fi
}

# Install Zsh and set as default shell
install_zsh() {
    log_info "Configuring Zsh..."

    # Verify Zsh is installed
    if ! command_exists zsh; then
        log_info "Installing Zsh..."
        sudo apt install -y zsh
    fi
    log_success "Zsh is available"

    # Check if Zsh is already the default shell
    if [[ "$SHELL" == *"zsh" ]]; then
        log_success "Zsh is already the default shell"
        return 0
    fi

    # Get the path to zsh
    local zsh_path
    zsh_path=$(which zsh)
    log_info "Found zsh at: $zsh_path"

    # Set Zsh as default shell using chsh
    log_info "Setting zsh as default shell using chsh..."
    if chsh -s "$zsh_path"; then
        log_success "Successfully set zsh as default shell"
        echo ""
        log_warning "=========================================="
        log_warning "Log out and log back in again to use your new default shell."
        log_warning "=========================================="
        echo ""
        exit 0
    else
        log_error "Failed to set zsh as default shell"
        log_error "You may need to set it manually with: chsh -s $zsh_path"
        exit 1
    fi
}

# Install Rust and Cargo
install_rust() {
    log_info "Installing Rust and Cargo..."

    if ! command_exists cargo; then
        log_info "Downloading and installing Rust via rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

        # Source cargo env for current session
        if [[ -f "$HOME/.cargo/env" ]]; then
            source "$HOME/.cargo/env"
            log_success "Rust and Cargo installed successfully"
        else
            log_error "Rust installation may have failed - cargo env not found"
            return 1
        fi

        # Add cargo to .zshrc if not already present
        if ! grep -q ".cargo/env" ~/.zshrc 2>/dev/null; then
            log_info "Adding Cargo to ~/.zshrc..."
            echo '' >> ~/.zshrc
            echo '# Rust/Cargo' >> ~/.zshrc
            echo 'source "$HOME/.cargo/env"' >> ~/.zshrc
        fi

        log_success "Rust and Cargo configured"
        log_info "Rust version: $(rustc --version)"
        log_info "Cargo version: $(cargo --version)"
    else
        log_success "Rust and Cargo already installed"
        log_info "Updating Rust to latest stable version..."
        rustup update stable
        log_success "Rust updated"
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
        sudo apt install -y bat

        # Create symlink if batcat is installed instead of bat
        if command_exists batcat && ! command_exists bat; then
            mkdir -p ~/.local/bin
            ln -sf /usr/bin/batcat ~/.local/bin/bat
            log_info "Created bat symlink from batcat"
        fi

        log_success "bat installed"
    else
        log_success "bat already installed"
    fi
}

# Install eza (better ls)
install_eza() {
    log_info "Installing eza (better ls)..."

    if ! command_exists eza; then
        # Install from GitHub releases
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

# Install zoxide (better cd)
install_zoxide() {
    log_info "Installing zoxide (better cd)..."

    if ! command_exists zoxide; then
        curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash

        # Add zoxide init to shell config if not already present
        if ! grep -q "zoxide init" ~/.zshrc 2>/dev/null; then
            echo 'eval "$(zoxide init zsh)"' >> ~/.zshrc
        fi

        log_success "zoxide installed and configured"
    else
        log_success "zoxide already installed"
    fi
}

# Install rip2 (better rm)
install_rip2() {
    log_info "Installing rip2 (better rm)..."

    if ! command_exists rip; then
        # Check if cargo is available
        if ! command_exists cargo; then
            log_error "Cargo is not installed. Please install Rust first."
            log_info "Run: ./bootstrap.sh -i rust"
            return 1
        fi

        log_info "Installing rip2 from crates.io via Cargo..."
        cargo install --locked rip2

        log_success "rip2 installed via Cargo"
        log_info "rip binary location: $HOME/.cargo/bin/rip"
    else
        log_success "rip2 already installed"
    fi
}

# Install dust (better du)
install_dust() {
    log_info "Installing dust (better du)..."

    if ! command_exists dust; then
        # Check if cargo is available
        if ! command_exists cargo; then
            log_error "Cargo is not installed. Please install Rust first."
            log_info "Run: ./bootstrap.sh -i rust"
            return 1
        fi

        log_info "Installing dust from crates.io via Cargo..."
        cargo install du-dust

        log_success "dust installed via Cargo"
        log_info "dust binary location: $HOME/.cargo/bin/dust"
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
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt install -y nodejs
            log_success "Node.js installed via system package manager"
        fi
    else
        log_warning "mise not available, installing Node.js via system package"
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt install -y nodejs
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

# Install Eclipse Temurin JDK 21 for Android development
install_jdk() {
    log_info "Installing Eclipse Temurin JDK 21 for Android development..."

    # Check if JDK 21 is already installed
    if dpkg -l | grep -q "temurin-21-jdk"; then
        log_success "Eclipse Temurin JDK 21 already installed"
    else
        log_info "Adding Adoptium APT repository..."
        wget -O - https://packages.adoptium.net/artifactory/api/gpg/key/public | sudo tee /usr/share/keyrings/adoptium.asc
        echo "deb [signed-by=/usr/share/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | sudo tee /etc/apt/sources.list.d/adoptium.list

        sudo apt update
        sudo apt install -y temurin-21-jdk
        log_success "Eclipse Temurin JDK 21 installed"
    fi

    # Set JAVA_HOME in shell config
    if ! grep -q "JAVA_HOME.*java-21" ~/.zshrc 2>/dev/null; then
        # Remove any existing JAVA_HOME line first
        if grep -q "JAVA_HOME" ~/.zshrc 2>/dev/null; then
            sed -i '/JAVA_HOME/d' ~/.zshrc
        fi
        echo 'export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64' >> ~/.zshrc
        log_info "JAVA_HOME configured to point to Temurin JDK 21"
    fi

    log_success "JDK 21 configuration complete"
}

# Install Warp Terminal
install_warp() {
    log_info "Installing Warp Terminal..."

    if command_exists warp-terminal; then
        log_success "Warp Terminal already installed"
        return
    fi

    log_info "Downloading Warp Terminal..."
    cd /tmp
    wget https://app.warp.dev/get_warp?package=deb -O warp-terminal.deb

    log_info "Installing Warp Terminal..."
    sudo apt install -y ./warp-terminal.deb

    # Clean up
    rm warp-terminal.deb

    log_success "Warp Terminal installed successfully"
    log_info "You can launch it from the applications menu or run: warp-terminal"
}

# Create .zshrc if it doesn't exist
create_zshrc() {
    if [[ ! -f ~/.zshrc ]]; then
        touch ~/.zshrc
        log_info "Created ~/.zshrc"
    fi
}

# Configure dotenv sourcing in .zshrc
configure_dotenv_sourcing() {
    log_info "Configuring dotenv sourcing in ~/.zshrc..."

    # Check if dotenv configuration already exists
    if ! grep -q "DOTENV_DIR" ~/.zshrc 2>/dev/null; then
        log_info "Adding dotenv configuration to ~/.zshrc..."

        # Add dotenv configuration
        cat >> ~/.zshrc << 'EOF'

# Set dotenv path
DOTENV_DIR="$HOME/dev/dotenv"

# Load zsh configuration
if [[ -f "$DOTENV_DIR/zsh.sh" ]]; then
    source "$DOTENV_DIR/zsh.sh"
fi
EOF

        log_success "Dotenv sourcing configured in ~/.zshrc"
    else
        log_success "Dotenv sourcing already configured in ~/.zshrc"
    fi
}

# Show help message
show_help() {
    echo "Ubuntu/Pop!_OS Bootstrap Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --all, -a                      Run all installation functions (default)"
    echo "  -i, --install FUNCTION         Run specific function(s)"
    echo "  -v, --versions                 Show installed versions only"
    echo "  --help, -h                     Show this help message"
    echo ""
    echo "Available Functions:"
    echo "  create_zshrc                   Create .zshrc file if it doesn't exist"
    echo "  configure_dotenv_sourcing      Configure dotenv sourcing in ~/.zshrc"
    echo "  configure_git                  Configure Git with useful aliases and settings"
    echo "  essential                      Install essential development packages"
    echo "  git                            Install Git version control"
    echo "  zsh                            Install Zsh shell and set as default"
    echo "  rust                           Install Rust and Cargo"
    echo "  starship                       Install Starship prompt"
    echo "  mise                           Install mise CLI version manager"
    echo "  bat                            Install bat (better cat)"
    echo "  eza                            Install eza (better ls)"
    echo "  zoxide                         Install zoxide (better cd)"
    echo "  rip2                           Install rip2 (better rm)"
    echo "  dust                           Install dust (better du)"
    echo "  nodejs                         Install Node.js using mise"
    echo "  bun                            Install Bun using mise"
    echo "  pnpm                           Install pnpm package manager"
    echo "  jdk                            Install Eclipse Temurin JDK 21"
    echo "  warp                           Install Warp Terminal"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Run all functions"
    echo "  $0 --all                              # Run all functions"
    echo "  $0 -a                                 # Run all functions"
    echo "  $0 -v                                 # Show installed versions only"
    echo "  $0 -i configure_dotenv_sourcing       # Only configure dotenv sourcing"
    echo "  $0 -i git                             # Install Git only"
    echo "  $0 -i git -i zsh                      # Install Git and Zsh"
    echo "  $0 --install configure_dotenv_sourcing git  # Multiple functions"
}

# Show installed versions
show_versions() {
    log_info "Installed versions:"
    echo "Git: $(git --version 2>/dev/null || echo 'Not available')"
    echo "Zsh: $(zsh --version 2>/dev/null || echo 'Not available')"
    echo "Rust: $(rustc --version 2>/dev/null || echo 'Not available')"
    echo "Cargo: $(cargo --version 2>/dev/null || echo 'Not available')"
    echo "Starship: $(starship --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "mise: $(mise --version 2>/dev/null || echo 'Not available')"
    echo "bat: $(bat --version 2>/dev/null || echo 'Not available')"
    echo "eza: $(eza --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "zoxide: $(zoxide --version 2>/dev/null || echo 'Not available')"
    echo "rip2: $(rip --version 2>/dev/null || echo 'Not available')"
    echo "dust: $(dust --version 2>/dev/null || echo 'Not available')"
    echo "Node.js: $(node --version 2>/dev/null || echo 'Not available')"
    echo "Bun: $(bun --version 2>/dev/null || echo 'Not available')"
    echo "pnpm: $(pnpm --version 2>/dev/null || echo 'Not available')"
    echo "Java: $(java --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "Warp: $(warp-terminal --version 2>/dev/null || echo 'Not available')"
}

# Run all installation functions
run_all() {
    log_info "Starting Bootstrap Process..."
    echo "=================================="

    check_ubuntu
    update_system
    create_zshrc
    configure_dotenv_sourcing
    install_essential_packages
    install_git
    configure_git
    install_zsh
    install_rust
    install_starship
    install_mise
    install_bat
    install_eza
    install_zoxide
    install_rip2
    install_dust
    install_nodejs
    install_bun
    install_pnpm
    install_jdk
    install_warp

    echo "=================================="
    log_success "Bootstrap completed successfully!"
    log_info "Please restart your terminal or run 'source ~/.zshrc' to apply all changes"

    echo ""
    show_versions
}

# Main function with argument parsing
main() {
    # If no arguments provided, run all functions
    if [[ $# -eq 0 ]]; then
        run_all
        return
    fi

    local functions_to_run=()
    local run_all_flag=false

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
            --all|-a)
                run_all_flag=true
                shift
                ;;
            -i|--install)
                shift
                # Collect all function names until next flag or end of arguments
                while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                    # Validate function name and map short names to actual function names
                    case $1 in
                        create_zshrc|configure_dotenv_sourcing|configure_git)
                            functions_to_run+=("$1")
                            ;;
                        essential)
                            functions_to_run+=(install_essential_packages)
                            ;;
                        git)
                            functions_to_run+=(install_git)
                            ;;
                        zsh)
                            functions_to_run+=(install_zsh)
                            ;;
                        rust)
                            functions_to_run+=(install_rust)
                            ;;
                        starship)
                            functions_to_run+=(install_starship)
                            ;;
                        mise)
                            functions_to_run+=(install_mise)
                            ;;
                        bat)
                            functions_to_run+=(install_bat)
                            ;;
                        eza)
                            functions_to_run+=(install_eza)
                            ;;
                        zoxide)
                            functions_to_run+=(install_zoxide)
                            ;;
                        rip2)
                            functions_to_run+=(install_rip2)
                            ;;
                        dust)
                            functions_to_run+=(install_dust)
                            ;;
                        nodejs)
                            functions_to_run+=(install_nodejs)
                            ;;
                        bun)
                            functions_to_run+=(install_bun)
                            ;;
                        pnpm)
                            functions_to_run+=(install_pnpm)
                            ;;
                        jdk)
                            functions_to_run+=(install_jdk)
                            ;;
                        warp)
                            functions_to_run+=(install_warp)
                            ;;
                        *)
                            log_error "Unknown function: $1"
                            log_info "Run '$0 --help' to see available functions"
                            return 1
                            ;;
                    esac
                    shift
                done
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                return 1
                ;;
        esac
    done

    # Run all functions if --all flag is set
    if [[ "$run_all_flag" == true ]]; then
        run_all
        return
    fi

    # Run specific functions
    if [[ ${#functions_to_run[@]} -gt 0 ]]; then
        log_info "Running selected functions..."
        echo "=================================="

        for func in "${functions_to_run[@]}"; do
            $func
        done

        echo "=================================="
        log_success "Selected functions completed successfully!"

        echo ""
        show_versions
    else
        log_error "No valid functions specified"
        show_help
        return 1
    fi
}

# Run the main function
main "$@"
