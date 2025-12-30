#!/bin/bash

# CLI utilities installation module

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

install_delta() {
    log_info "Installing delta (better git diff)..."

    if ! command_exists delta; then
        # Check if cargo is available
        if ! command_exists cargo; then
            log_error "Cargo is not installed. Please install Rust first."
            log_info "Run: ./bootstrap.sh -i rust"
            return 1
        fi

        log_info "Installing delta from crates.io via Cargo..."
        cargo install git-delta

        log_success "delta installed via Cargo"
        log_info "delta binary location: $HOME/.cargo/bin/delta"
    else
        log_success "delta already installed"
    fi
}