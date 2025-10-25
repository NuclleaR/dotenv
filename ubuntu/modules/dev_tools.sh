#!/bin/bash

# Development tools installation module

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

# Install Eclipse Temurin JDK 21 using mise
install_jdk() {
    log_info "Installing Eclipse Temurin JDK 21 using mise..."

    if command_exists mise; then
        log_info "Installing Java (Temurin 21) using mise..."
        if mise install java@temurin-21 2>/dev/null && mise use -g java@temurin-21 2>/dev/null; then
            log_success "Eclipse Temurin JDK 21 installed via mise"
            log_info "Java version: $(java -version 2>&1 | head -n1 || echo 'Unknown')"
        else
            log_error "Failed to install JDK via mise"
            log_info "You can try installing manually with: mise install java@temurin-21"
            return 1
        fi
    else
        log_warning "mise not available, skipping JDK installation"
        log_info "Install mise first with: ./bootstrap.sh -i mise"
        return 1
    fi

    log_success "JDK 21 configuration complete"
}

# Install Ruby dependencies and Ruby via mise
install_ruby() {
    log_info "Installing Ruby dependencies..."

    # Install Ruby build dependencies
    local ruby_deps=(
        "libffi-dev"
        "libyaml-dev"
        # "libssl-dev"
        # "libreadline-dev"
        "zlib1g-dev"
        # "libgdbm-dev"
        # "libncurses5-dev"
        # "libgmp-dev"
        # "build-essential"
        # "bison"
    )

    sudo apt install -y "${ruby_deps[@]}"
    log_success "Ruby dependencies installed"

    # Install Ruby via mise if mise is available
    if command_exists mise; then
        log_info "Installing Ruby latest using mise..."
        if mise install ruby@latest 2>/dev/null && mise use -g ruby@latest 2>/dev/null; then
            log_success "Ruby installed via mise"
            log_info "Ruby version: $(ruby --version 2>/dev/null || echo 'Not available')"
        else
            log_error "Failed to install Ruby via mise"
            log_info "You can try installing manually with: mise install ruby@latest"
            return 1
        fi
    else
        log_warning "mise not available, skipping Ruby installation"
        log_info "Install mise first with: ./bootstrap.sh -i mise"
        return 1
    fi
}
