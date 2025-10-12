#!/bin/bash

# macOS Bootstrap Script
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

# Install Xcode Command Line Tools if not already installed
install_xcode_tools() {
    log_info "Checking for Xcode Command Line Tools..."

    if ! xcode-select -p &>/dev/null; then
        log_info "Installing Xcode Command Line Tools..."
        xcode-select --install

        # Wait for installation to complete
        until xcode-select -p &>/dev/null; do
            sleep 5
        done
        log_success "Xcode Command Line Tools installed"
    else
        log_success "Xcode Command Line Tools already installed"
    fi
}

# Install Homebrew
install_homebrew() {
    log_info "Checking for Homebrew..."

    if ! command_exists brew; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add Homebrew to PATH for Apple Silicon Macs
        if [[ $(uname -m) == "arm64" ]]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
            eval "$(/usr/local/bin/brew shellenv)"
        fi

        log_success "Homebrew installed"
    else
        log_success "Homebrew already installed"
        log_info "Updating Homebrew..."
        brew update
    fi
}

# Install Git
install_git() {
    log_info "Checking for Git..."

    if ! command_exists git; then
        log_info "Installing Git..."
        brew install git
        log_success "Git installed"
    else
        log_success "Git already installed"
        log_info "Updating Git to latest version..."
        brew upgrade git
        log_success "Git updated"
    fi
}

# Install Zsh
install_zsh() {
    log_info "Checking for Zsh..."

    if ! command_exists zsh; then
        log_info "Installing Zsh..."
        brew install zsh
        log_success "Zsh installed"
    else
        log_success "Zsh already installed"
    fi

    # Set Zsh as default shell if not already
    if [[ "$SHELL" != *"zsh" ]]; then
        log_info "Setting Zsh as default shell..."
        chsh -s $(which zsh)
        log_success "Zsh set as default shell"
    fi
}

# Install Starship
install_starship() {
    log_info "Checking for Starship..."

    if ! command_exists starship; then
        log_info "Installing Starship..."
        brew install starship

        # Add starship init to shell config if not already present
        if ! grep -q "starship init" ~/.zshrc 2>/dev/null; then
            echo 'eval "$(starship init zsh)"' >> ~/.zshrc
        fi

        log_success "Starship installed"
    else
        log_success "Starship already installed"
    fi
}

# Install mise CLI
install_mise() {
    log_info "Checking for mise CLI..."

    if ! command_exists mise; then
        log_info "Installing mise CLI using official installer..."
        # Use the official mise.run installer which automatically configures shell activation
        curl https://mise.run/zsh | sh
        log_success "mise CLI installed and configured"
    else
        log_success "mise CLI already installed"
        log_info "Updating mise to latest version..."
        if command_exists brew && brew list mise &>/dev/null; then
            # If installed via brew, update via brew
            brew upgrade mise
        else
            # If installed via mise.run installer, use self-update
            mise self-update
        fi
        log_success "mise updated"
    fi
}

# Install bat (better cat)
install_bat() {
    log_info "Checking for bat..."

    if ! command_exists bat; then
        log_info "Installing bat..."
        brew install bat
        log_success "bat installed"
    else
        log_success "bat already installed"
    fi
}

# Install eza (better ls)
install_eza() {
    log_info "Checking for eza..."

    if ! command_exists eza; then
        log_info "Installing eza..."
        brew install eza
        log_success "eza installed"
    else
        log_success "eza already installed"
    fi
}

# Install Node.js using mise
install_nodejs() {
    log_info "Installing Node.js using mise..."

    # Source mise if it's available
    if command_exists mise; then
        eval "$(mise activate zsh)"
        mise install node@lts
        mise use -g node@lts
        log_success "Node.js (LTS) installed via mise"
    else
        log_error "mise not available, skipping Node.js installation"
    fi
}

# Install Bun using mise
install_bun() {
    log_info "Installing Bun using mise..."

    if command_exists mise; then
        eval "$(mise activate zsh)"
        mise install bun@latest
        mise use -g bun@latest
        log_success "Bun installed via mise"
    else
        log_error "mise not available, skipping Bun installation"
    fi
}

# Install pnpm
install_pnpm() {
    log_info "Installing pnpm..."

    if ! command_exists pnpm; then
        # Install pnpm using npm (which should be available after Node.js installation)
        if command_exists npm; then
            npm install -g pnpm
            log_success "pnpm installed"
        else
            log_warning "npm not available, trying alternative pnpm installation..."
            curl -fsSL https://get.pnpm.io/install.sh | sh -
            log_success "pnpm installed via standalone installer"
        fi
    else
        log_success "pnpm already installed"
    fi
}

# Install Eclipse Temurin JDK 21 for Android development
install_jdk() {
    log_info "Installing Eclipse Temurin JDK 21 for Android development..."

    # Check if Temurin JDK 21 is already installed
    if brew list --cask temurin@21 &>/dev/null; then
        log_success "Eclipse Temurin JDK 21 already installed"
    else
        log_info "Installing Eclipse Temurin JDK 21 via Homebrew..."
        brew install --cask temurin@21
        log_success "Eclipse Temurin JDK 21 installed"
    fi

    # Set JAVA_HOME in shell config to point to JDK 21
    if ! grep -q "JAVA_HOME.*temurin-21" ~/.zshrc 2>/dev/null; then
        # Remove any existing JAVA_HOME line first
        if grep -q "JAVA_HOME" ~/.zshrc 2>/dev/null; then
            sed -i '' '/JAVA_HOME/d' ~/.zshrc
        fi
        # Add new JAVA_HOME pointing to Temurin 21
        echo 'export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home' >> ~/.zshrc
        log_info "JAVA_HOME configured to point to Temurin JDK 21"
    fi
}

# Create .zshrc if it doesn't exist
create_zshrc() {
    if [[ ! -f ~/.zshrc ]]; then
        touch ~/.zshrc
        log_info "Created ~/.zshrc"
    fi
}

# Main installation function
main() {
    log_info "Starting macOS Bootstrap Process..."
    echo "=================================="

    create_zshrc
    install_xcode_tools
    install_homebrew
    install_git
    install_zsh
    install_starship
    install_mise
    install_bat
    install_eza
    install_nodejs
    install_bun
    install_pnpm
    install_jdk

    echo "=================================="
    log_success "Bootstrap completed successfully!"
    log_info "Please restart your terminal or run 'source ~/.zshrc' to apply all changes"

    # Show installed versions
    echo ""
    log_info "Installed versions:"
    echo "Git: $(git --version 2>/dev/null || echo 'Not available')"
    echo "Zsh: $(zsh --version 2>/dev/null || echo 'Not available')"
    echo "Starship: $(starship --version 2>/dev/null || echo 'Not available')"
    echo "mise: $(mise --version 2>/dev/null || echo 'Not available')"
    echo "bat: $(bat --version 2>/dev/null || echo 'Not available')"
    echo "eza: $(eza --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "Node.js: $(node --version 2>/dev/null || echo 'Not available')"
    echo "Bun: $(bun --version 2>/dev/null || echo 'Not available')"
    echo "pnpm: $(pnpm --version 2>/dev/null || echo 'Not available')"
    echo "Java: $(java --version 2>/dev/null | head -n1 || echo 'Not available')"
}

# Run the main function
main "$@"