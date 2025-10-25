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
