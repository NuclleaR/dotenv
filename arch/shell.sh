#!/bin/bash

# Shell configuration module for Arch Linux

# Install shell setup (Zsh + Starship + Plugins)
install_shell() {
    log_info "Installing Zsh shell, Starship prompt, and plugins..."

    # Install Zsh
    if ! command_exists zsh; then
        log_info "Installing Zsh from official repository..."
        sudo pacman -S --noconfirm zsh
        log_success "Zsh installed"
    else
        log_success "Zsh already installed"
    fi

    # Install Starship
    if ! command_exists starship; then
        log_info "Installing Starship from official repository..."
        sudo pacman -S --noconfirm starship
        log_success "Starship installed"
    else
        log_success "Starship already installed"
    fi

    # Install zsh-autosuggestions
    if [[ ! -d "/usr/share/zsh/plugins/zsh-autosuggestions" ]]; then
        log_info "Installing zsh-autosuggestions..."
        sudo pacman -S --noconfirm zsh-autosuggestions
        log_success "zsh-autosuggestions installed"
    else
        log_success "zsh-autosuggestions already installed"
    fi

    # Install zsh-syntax-highlighting
    if [[ ! -d "/usr/share/zsh/plugins/zsh-syntax-highlighting" ]]; then
        log_info "Installing zsh-syntax-highlighting..."
        sudo pacman -S --noconfirm zsh-syntax-highlighting
        log_success "zsh-syntax-highlighting installed"
    else
        log_success "zsh-syntax-highlighting already installed"
    fi

    # Create .zshrc if it doesn't exist
    if [[ ! -f "$HOME/.zshrc" ]]; then
        log_info "Creating .zshrc file..."
        touch "$HOME/.zshrc"
    fi

    # Add Starship initialization to .zshrc if not already there
    if ! grep -q "starship init zsh" "$HOME/.zshrc"; then
        log_info "Configuring Starship in .zshrc..."
        echo "" >> "$HOME/.zshrc"
        echo "# Initialize Starship prompt" >> "$HOME/.zshrc"
        echo 'eval "$(starship init zsh)"' >> "$HOME/.zshrc"
        log_success "Starship configured in .zshrc"
    fi

    # Add zsh-autosuggestions to .zshrc if not already there
    if ! grep -q "zsh-autosuggestions" "$HOME/.zshrc"; then
        log_info "Configuring zsh-autosuggestions in .zshrc..."
        echo "" >> "$HOME/.zshrc"
        echo "# zsh-autosuggestions plugin" >> "$HOME/.zshrc"
        echo "source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" >> "$HOME/.zshrc"
        log_success "zsh-autosuggestions configured in .zshrc"
    fi

    # Add zsh-syntax-highlighting to .zshrc if not already there
    if ! grep -q "zsh-syntax-highlighting" "$HOME/.zshrc"; then
        log_info "Configuring zsh-syntax-highlighting in .zshrc..."
        echo "" >> "$HOME/.zshrc"
        echo "# zsh-syntax-highlighting plugin" >> "$HOME/.zshrc"
        echo "source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> "$HOME/.zshrc"
        log_success "zsh-syntax-highlighting configured in .zshrc"
    fi

    # Add PATH configuration to .zshrc if not already there
    if ! grep -q '\$HOME/.bin' "$HOME/.zshrc"; then
        log_info "Configuring PATH in .zshrc..."
        echo "" >> "$HOME/.zshrc"
        echo "# Add local bin directory to PATH" >> "$HOME/.zshrc"
        echo 'export PATH="$PATH:$HOME/.bin"' >> "$HOME/.zshrc"
        log_success "PATH configured in .zshrc"
    fi

    # Set Zsh as default shell
    if [[ "$SHELL" != *"zsh"* ]]; then
        log_info "Setting Zsh as default shell..."
        chsh -s /usr/bin/zsh
        log_success "Zsh set as default shell"
    else
        log_success "Zsh is already the default shell"
    fi

    log_success "Zsh, Starship, and plugins installed and configured successfully!"
    log_info "Zsh version: $(zsh --version)"
    log_info "Starship version: $(starship --version)"
}

# Legacy functions kept for backward compatibility
# install_zsh() {
#     install_shell
# }

# install_starship() {
#     install_shell
# }

# install_zsh_autosuggestions() {
#     install_shell
# }

# install_zsh_syntax_highlighting() {
#     install_shell
# }
