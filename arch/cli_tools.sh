#!/bin/bash

# CLI tools installation module for Arch Linux

# Install bat (better cat)
install_bat() {
    log_info "Installing bat..."

    if command_exists bat; then
        log_success "bat already installed"
        log_info "bat version: $(bat --version)"
        return
    fi

    sudo pacman -S --noconfirm bat
    log_success "bat installed successfully"
}

# Install eza (better ls)
install_eza() {
    log_info "Installing eza..."

    if command_exists eza; then
        log_success "eza already installed"
        log_info "eza version: $(eza --version | head -n2)"
        return
    fi

    sudo pacman -S --noconfirm eza
    log_success "eza installed successfully"
}

# Install zoxide (better cd)
install_zoxide() {
    log_info "Installing zoxide..."

    if command_exists zoxide; then
        log_success "zoxide already installed"
        log_info "zoxide version: $(zoxide --version)"
        return
    fi

    sudo pacman -S --noconfirm zoxide
    log_success "zoxide installed successfully"

    # Add zoxide init to shell config if not already present
    if ! grep -q "zoxide init" ~/.zshrc 2>/dev/null; then
        echo 'eval "$(zoxide init zsh)"' >> ~/.zshrc
    fi

    # zoxide (better cd) aliases
    # Replace cd with z for smart directory jumping based on frequency and recency
    # alias cd='z'
    # alias cdi='zi'  # Interactive mode with fzf-like interface
}

# Install rip2 (better rm)
install_rip2() {
    log_info "Installing rip2..."

    if command_exists rip; then
        log_success "rip2 already installed"
        log_info "rip version: $(rip --version)"
        return
    fi

    log_info "Installing rip2 via cargo..."
    if ! command_exists cargo; then
        log_error "Cargo not found. Please install Rust first."
        return 1
    fi

    cargo install rm-improved
    log_success "rip2 installed successfully"
}

# Install dust (better du)
install_dust() {
    log_info "Installing dust..."

    if command_exists dust; then
        log_success "dust already installed"
        log_info "dust version: $(dust --version)"
        return
    fi

    sudo pacman -S --noconfirm dust
    log_success "dust installed successfully"
}

# Install skim (fuzzy finder)
install_skim() {
    log_info "Installing skim (sk)..."

    if command_exists sk; then
        log_success "skim already installed"
        log_info "skim version: $(sk --version | head -n1)"
        return
    fi

    # Use upstream installer to get latest stable binary (avoids old repo/AUR builds)
    local SKIM_VERSION="1.5.1"
    local SKIM_INSTALLER_URL="https://github.com/skim-rs/skim/releases/download/v${SKIM_VERSION}/skim-installer.sh"

    log_info "Downloading skim installer v${SKIM_VERSION}..."
    if ! curl --proto '=https' --tlsv1.2 -LsSf "$SKIM_INSTALLER_URL" | sh; then
        log_error "skim install failed via upstream installer"
        return 1
    fi

    log_success "skim installed successfully (v${SKIM_VERSION})"
}

# Install delta (better git diff)
install_delta() {
    log_info "Installing delta..."

    if command_exists delta; then
        log_success "delta already installed"
        log_info "delta version: $(delta --version)"
        return
    fi

    sudo pacman -S --noconfirm git-delta
    log_success "delta installed successfully"
}
