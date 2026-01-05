#!/bin/bash

# Package installation module for Arch Linux

# Install essential development packages
install_essential_packages() {
    log_info "Installing essential development packages..."

    local packages=(
        "base-devel"
        "curl"
        "wget"
        "git"
        "zsh"
        "htop"
        "tree"
        "gnupg"
    )

    sudo pacman -S --noconfirm "${packages[@]}"
    log_success "Essential development packages installed"
}

# Install Git
install_git() {
    log_info "Checking for Git..."

    if ! command_exists git; then
        log_info "Installing Git..."
        sudo pacman -S --noconfirm git
        log_success "Git installed"
    else
        log_success "Git already installed"
        log_info "Git version: $(git --version)"
    fi
}

# Install GPG
install_gpg() {
    log_info "Installing GPG..."

    if command_exists gpg; then
        log_success "GPG already installed"
        log_info "GPG version: $(gpg --version | head -n1)"
        return
    fi

    log_info "Installing GPG and related tools..."
    sudo pacman -S --noconfirm gnupg

    log_success "GPG installed successfully"
    log_info "GPG version: $(gpg --version | head -n1)"
}

# Install GitHub CLI
install_github_cli() {
    log_info "Installing GitHub CLI..."

    if command_exists gh; then
        log_success "GitHub CLI already installed"
        log_info "GitHub CLI version: $(gh --version | head -n1)"
        return
    fi

    log_info "Installing GitHub CLI from official repository..."
    sudo pacman -S --noconfirm github-cli

    log_success "GitHub CLI installed successfully"
    log_info "To authenticate, run: gh auth login"
}

# Install Flatpak
install_flatpak() {
    log_info "Installing Flatpak..."

    if command_exists flatpak; then
        log_success "Flatpak already installed"
        log_info "Flatpak version: $(flatpak --version)"
        return
    fi

    log_info "Installing Flatpak..."
    sudo pacman -S --noconfirm flatpak

    log_info "Adding Flathub repository..."
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

    log_success "Flatpak installed and Flathub repository added"
    log_info "Flatpak version: $(flatpak --version)"
}
