#!/bin/bash

# SSH setup for Fedora
#
# Installs keychain (one ssh-agent per host, shared by every terminal — see
# shared/zsh.sh) and then hands over to common/ssh.sh, which generates the
# ed25519 key, loads it into the agent, writes ~/.ssh/config, seeds known_hosts
# and uploads the public key to GitHub when gh is authenticated.
#
# Needs the repo on disk: it sources common/ssh.sh, so it cannot be piped from
# curl the way fedora/shell.sh and fedora/apps.sh can.
#
#   ./fedora/ssh.sh                          # ~/.ssh/id_ed25519, Host github.com
#   ./fedora/ssh.sh -n id_ed25519_work -H github-work
#
# All flags are passed through to common/ssh.sh; run with -h for the list.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_ROOT/common/logger.sh"
source "$REPO_ROOT/common/utils.sh"

# keychain is the only piece common/ssh.sh wants that Fedora does not ship by
# default; openssh-clients is part of every install.
install_keychain() {
    if command_exists keychain; then
        log_success "keychain already installed"
        return 0
    fi

    log_info "Installing keychain..."
    if ! sudo dnf install -y keychain; then
        log_error "Failed to install keychain"
        return 1
    fi
    log_success "keychain installed"
}

# gh is optional: without it common/ssh.sh prints the public key and the URL to
# paste it at instead of uploading it. It comes from the GitHub repo, which
# fedora/apps.sh knows how to add.
hint_gh() {
    if command_exists gh; then
        return 0
    fi
    log_info "gh is not installed — the key will have to be added to GitHub by hand"
    log_info "To upload it automatically next time: ./fedora/apps.sh -i gh && gh auth login"
}

main() {
    install_keychain
    hint_gh

    echo ""
    # common/ssh.sh does its own argument parsing and reporting
    bash "$REPO_ROOT/common/ssh.sh" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
