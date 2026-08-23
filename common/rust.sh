#!/bin/bash

# Rust installation module (distribution independent)
# Run it directly (./common/rust.sh) or source it and call install_rust

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$COMMON_DIR/logger.sh"
source "$COMMON_DIR/utils.sh"

# Install Rust via rustup if it is not present
install_rust() {
    # rustup may already be installed but not on PATH in this shell
    if [[ -f "$HOME/.cargo/env" ]]; then
        source "$HOME/.cargo/env"
    fi

    if command_exists cargo; then
        log_success "Rust already installed"
        log_info "Rust version: $(rustc --version)"
        return 0
    fi

    if ! command_exists curl; then
        log_error "curl is required to install Rust, install it first"
        return 1
    fi

    # --no-modify-path: PATH comes from shared/cargo.sh, not from rustup
    # patching .profile / .zshenv behind our back
    log_info "Installing Rust via rustup..."
    if ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path; then
        log_error "Failed to install Rust"
        return 1
    fi

    source "$HOME/.cargo/env"

    log_success "Rust installed"
    log_info "Rust version: $(rustc --version)"
    log_info "Cargo version: $(cargo --version)"
    log_info "Cargo lands on PATH in new shells via shared/zsh.sh -> shared/cargo.sh"
}

# Run only when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    install_rust
fi
