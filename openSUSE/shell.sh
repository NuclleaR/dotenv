#!/bin/bash

# Shell setup script for openSUSE
#
# Installs Zsh, Starship and the zsh-users plugins, then points ~/.zshrc at the
# shared config in shared/zsh.sh. The setup is distro specific, the config is not.

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTENV_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common utilities and logger
source "$DOTENV_ROOT/common/logger.sh"
source "$DOTENV_ROOT/common/utils.sh"

# Zsh plugins are not packaged for openSUSE, so they are cloned here
# (manual install as documented by zsh-users)
ZSH_PLUGINS_DIR="$HOME/.zsh"

# Install Zsh if it is not present
install_zsh() {
    if command_exists zsh; then
        log_success "Zsh already installed"
        log_info "Zsh version: $(zsh --version)"
        return 0
    fi

    log_info "Installing Zsh from official repository..."
    sudo zypper --non-interactive refresh
    if ! sudo zypper --non-interactive install zsh; then
        log_error "Failed to install Zsh"
        return 1
    fi

    log_success "Zsh installed"
    log_info "Zsh version: $(zsh --version)"
}

# Install the packages the rest of the setup relies on
install_prerequisites() {
    local MISSING=()

    command_exists git || MISSING+=("git")
    command_exists curl || MISSING+=("curl")

    if [[ ${#MISSING[@]} -eq 0 ]]; then
        log_success "Prerequisites already installed (git, curl)"
        return 0
    fi

    log_info "Installing prerequisites: ${MISSING[*]}..."
    if ! sudo zypper --non-interactive install "${MISSING[@]}"; then
        log_error "Failed to install prerequisites"
        return 1
    fi

    log_success "Prerequisites installed"
}

# Install Starship prompt if it is not present and apply the dotenv config
install_starship() {
    if command_exists starship; then
        log_success "Starship already installed"
    else
        log_info "Installing Starship from the official install script..."
        if ! curl -sS https://starship.rs/install.sh | sh -s -- -y; then
            log_error "Failed to install Starship"
            return 1
        fi
        log_success "Starship installed"
    fi

    link_starship_config || log_warning "Starship config was not linked"
    log_info "Starship version: $(starship --version)"
}

# Symlink the Starship config from the dotenv repo into ~/.config
link_starship_config() {
    local CONFIG_SOURCE="$DOTENV_ROOT/shared/starship.toml"
    local CONFIG_TARGET="$HOME/.config/starship.toml"

    if [[ ! -f "$CONFIG_SOURCE" ]]; then
        log_warning "Starship config not found at $CONFIG_SOURCE"
        return 1
    fi

    mkdir -p "$(dirname "$CONFIG_TARGET")"

    if [[ -L "$CONFIG_TARGET" ]]; then
        if [[ "$(readlink -f "$CONFIG_TARGET")" == "$(readlink -f "$CONFIG_SOURCE")" ]]; then
            log_success "Starship config symlink already in place"
            return 0
        fi
        log_warning "$CONFIG_TARGET points somewhere else, replacing..."
    elif [[ -f "$CONFIG_TARGET" ]]; then
        log_warning "$CONFIG_TARGET already exists (not a symlink), backing up..."
        mv "$CONFIG_TARGET" "$CONFIG_TARGET.backup"
    fi

    ln -sf "$CONFIG_SOURCE" "$CONFIG_TARGET"
    log_success "Starship config symlinked to $CONFIG_TARGET"
}

# Install zsh-users plugins from Git (they are not available via zypper)
install_zsh_plugins() {
    clone_zsh_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions"
    clone_zsh_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git"
}

# Clone a single plugin into ~/.zsh if it is not there yet
clone_zsh_plugin() {
    local NAME="$1"
    local REPO="$2"
    local TARGET="$ZSH_PLUGINS_DIR/$NAME"

    if [[ -d "$TARGET" ]]; then
        log_success "$NAME already installed"
        return 0
    fi

    log_info "Cloning $NAME into $TARGET..."
    mkdir -p "$ZSH_PLUGINS_DIR"
    if ! git clone --depth 1 "$REPO" "$TARGET"; then
        log_error "Failed to clone $NAME"
        return 1
    fi

    log_success "$NAME installed"
}

# Tell how to switch the login shell (the setup never changes it silently)
show_default_shell_hint() {
    local ZSH_PATH
    ZSH_PATH="$(command -v zsh || echo /usr/bin/zsh)"
    local CURRENT_SHELL
    CURRENT_SHELL="$(getent passwd "${USER:-$(id -un)}" | cut -d: -f7)"

    if [[ "$CURRENT_SHELL" == "$ZSH_PATH" ]]; then
        log_success "Zsh is already your default shell"
        return 0
    fi

    log_warning "Your default shell is still ${CURRENT_SHELL:-unknown}"
    log_info "To make Zsh the default shell run:"
    log_info "    chsh -s $ZSH_PATH"
    log_info "  or, if chsh is not permitted:"
    log_info "    sudo usermod -s $ZSH_PATH ${USER:-$(id -un)}"
    log_info "Then log out and log back in — opening a new terminal is not enough"
}

main() {
    install_zsh
    install_prerequisites
    install_starship
    install_zsh_plugins
    setup_zshrc

    echo ""
    log_success "Shell setup completed!"

    echo ""
    show_default_shell_hint
}

# Run main only when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
