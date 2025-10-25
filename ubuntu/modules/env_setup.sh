#!/bin/bash

# Shell environment setup module

# Create ~/.bin and add to PATH in .zshrc
install_user_bin() {
    log_info "Creating ~/.bin and adding to PATH in .zshrc..."
    mkdir -p "$HOME/.bin"
    if ! grep -q 'export PATH="$HOME/.bin:$PATH"' "$HOME/.zshrc" 2>/dev/null; then
        echo '' >> "$HOME/.zshrc"
        echo '# Add ~/.bin to PATH' >> "$HOME/.zshrc"
        echo 'export PATH="$HOME/.bin:$PATH"' >> "$HOME/.zshrc"
        log_success "Added ~/.bin to PATH in .zshrc"
    else
        log_success "~/.bin already in PATH in .zshrc"
    fi
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
