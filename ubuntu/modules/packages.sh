#!/bin/bash

# Package installation module

# Install essential development packages
install_essential_packages() {
    log_info "Installing essential development packages..."

    local packages=(
        "build-essential"
        "curl"
        "wget"
        "git"
        "zsh"
        "htop"
        "tree"
        "software-properties-common"
        "apt-transport-https"
        "ca-certificates"
        "gnupg"
        "lsb-release"
    )

    sudo apt install -y "${packages[@]}"
    log_success "Essential development packages installed"
}

# Install Git
install_git() {
    log_info "Checking for Git..."

    if ! command_exists git; then
        log_info "Installing Git..."
        sudo apt install -y git
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
    sudo apt install -y gnupg gpg

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

    log_info "Adding GitHub CLI repository and installing..."

    # Official installation from https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian
    (type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
    && sudo mkdir -p -m 755 /etc/apt/keyrings \
    && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && sudo mkdir -p -m 755 /etc/apt/sources.list.d \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update \
    && sudo apt install gh -y

    log_success "GitHub CLI installed successfully"
    log_info "To authenticate, run: gh auth login"
}
