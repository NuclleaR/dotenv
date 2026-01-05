#!/bin/bash

# Environment setup module for Arch Linux

# Create .zshrc if it doesn't exist
create_zshrc() {
    log_info "Checking for .zshrc file..."

    if [[ -f "$HOME/.zshrc" ]]; then
        log_success ".zshrc already exists"
        return
    fi

    log_info "Creating .zshrc file..."
    touch "$HOME/.zshrc"
    log_success ".zshrc created"
}

# Configure dotenv sourcing in .zshrc
configure_dotenv_sourcing() {
    log_info "Configuring dotenv sourcing in .zshrc..."

    local zshrc="$HOME/.zshrc"
    local dotenv_line='[ -f "$HOME/dev/dotenv/zsh.sh" ] && source "$HOME/dev/dotenv/zsh.sh"'

    if [[ ! -f "$zshrc" ]]; then
        log_error ".zshrc not found. Run create_zshrc first."
        return 1
    fi

    if grep -Fxq "$dotenv_line" "$zshrc"; then
        log_success "Dotenv sourcing already configured"
        return
    fi

    log_info "Adding dotenv sourcing to .zshrc..."
    echo '' >> "$zshrc"
    echo '# Source dotenv configuration' >> "$zshrc"
    echo "$dotenv_line" >> "$zshrc"

    log_success "Dotenv sourcing configured in .zshrc"
}
