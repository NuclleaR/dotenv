#!/bin/bash

# Shell installation module

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

# Install zsh-autosuggestions plugin
install_zsh_autosuggestions() {
    log_info "Installing zsh-autosuggestions..."

    # Create .zsh directory if it doesn't exist
    mkdir -p ~/.zsh

    # Clone zsh-autosuggestions if not already present
    if [ ! -d ~/.zsh/plugins/zsh-autosuggestions ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/plugins/zsh-autosuggestions
        log_success "zsh-autosuggestions cloned successfully"

        # Add source line to .zshrc if not already present
        if ! grep -q "zsh-autosuggestions.zsh" ~/.zshrc 2>/dev/null; then
            echo 'source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' >> ~/.zshrc
            log_success "Added zsh-autosuggestions to .zshrc"
        fi
    else
        log_success "zsh-autosuggestions already installed"
    fi
}

# Install zsh-syntax-highlighting plugin
install_zsh_syntax_highlighting() {
    log_info "Installing zsh-syntax-highlighting..."

    # Create .zsh/plugins directory if it doesn't exist
    mkdir -p ~/.zsh/plugins

    # Clone zsh-syntax-highlighting if not already present
    if [ ! -d ~/.zsh/plugins/zsh-syntax-highlighting ]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.zsh/plugins/zsh-syntax-highlighting
        log_success "zsh-syntax-highlighting cloned successfully"

        # Add source line to .zshrc if not already present
        if ! grep -q "zsh-syntax-highlighting.zsh" ~/.zshrc 2>/dev/null; then
            echo 'source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' >> ~/.zshrc
            log_success "Added zsh-syntax-highlighting to .zshrc"
        fi
    else
        log_success "zsh-syntax-highlighting already installed"
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

    # Apply Catppuccin Powerline preset
    log_info "Applying Catppuccin Powerline preset..."
    mkdir -p ~/.config
    starship preset catppuccin-powerline -o ~/.config/starship.toml
    log_success "Starship preset configured"
}
