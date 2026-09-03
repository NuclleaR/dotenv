#!/bin/bash

# SSH setup for Fedora
#
# Installs keychain (one ssh-agent per host, shared by every terminal — see
# shared/zsh.sh) and then hands over to common/ssh.sh, which generates the
# ed25519 key, loads it into the agent, writes ~/.ssh/config and uploads the
# public key to GitHub when gh is authenticated. It does not touch known_hosts.
#
# Run it straight off the internet, no clone needed:
#
#   curl -fsSL https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/ssh.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/ssh.sh | bash -s -- -n id_ed25519_work -H github-work
#
# Piped, it downloads common/ssh.sh and its two helpers into a temp dir and runs
# them from there; from a clone it runs the local copy. Either way stdin is
# re-pointed at /dev/tty for the child, so the passphrase prompt works even
# though curl owns the pipe.
#
# The log helpers are inline rather than sourced from common/ because piped into
# a shell there is no script path to resolve a sibling file from. Keep them in
# step with common/logger.sh.
#
# All flags are passed through to common/ssh.sh; run with -h for the list. -h is
# intercepted before anything is installed, so asking for the usage never calls
# dnf.

set -euo pipefail

# Where to fetch from when there is no clone to run against
RAW_BASE="${DOTENV_RAW:-https://raw.githubusercontent.com/NuclleaR/dotenv/main}"

# What common/ssh.sh needs next to itself
COMMON_FILES=(common/logger.sh common/utils.sh common/ssh.sh)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions (mirror of common/logger.sh)
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Mirror of common/utils.sh
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Repo root when running from a clone, empty when piped into a shell
REPO_ROOT=""

# Piped, BASH_SOURCE[0] is empty, so there is nothing to resolve and we fall
# back to downloading.
detect_repo_root() {
    [[ -n "${BASH_SOURCE[0]:-}" ]] || return 0

    local script_dir root file
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    root="$(cd "$script_dir/.." && pwd)"

    # A partial checkout is worse than no clone at all: common/ssh.sh sources
    # its siblings, so all of them have to be there before we prefer the clone.
    for file in "${COMMON_FILES[@]}"; do
        [[ -f "$root/$file" ]] || return 0
    done

    REPO_ROOT="$root"
}

# keychain is the only piece common/ssh.sh wants that Fedora does not ship by
# default; openssh-clients is part of every install.
install_keychain() {
    if command_exists keychain; then
        log_success "keychain already installed"
        return 0
    fi

    if ! command_exists dnf; then
        log_error "dnf not found — this script only installs on Fedora"
        return 1
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
    log_info "To upload it automatically next time:"
    log_info "    curl -fsSL $RAW_BASE/fedora/apps.sh | bash -s -- -i gh && gh auth login"
}

# Temp dir holding the downloaded common/ when piped; global so the EXIT trap
# can still see it after main() has returned
TMP_ROOT=""

cleanup_tmp_root() {
    [[ -n "$TMP_ROOT" ]] && rm -rf "$TMP_ROOT"
    return 0
}

# Fetch common/ into TMP_ROOT, keeping the layout common/ssh.sh resolves its
# siblings from.
download_common() {
    if ! command_exists curl; then
        log_error "curl is required to fetch common/ — install it with: sudo dnf install -y curl"
        return 1
    fi

    TMP_ROOT="$(mktemp -d)"
    trap cleanup_tmp_root EXIT
    mkdir -p "$TMP_ROOT/common"

    local file
    for file in "${COMMON_FILES[@]}"; do
        log_info "Downloading $file..."
        if ! curl -sSfL "$RAW_BASE/$file" -o "$TMP_ROOT/$file"; then
            log_error "Failed to download $RAW_BASE/$file"
            return 1
        fi
    done
}

# common/ssh.sh asks for the passphrase on stdin and refuses without a
# terminal, so it gets /dev/tty as stdin regardless of what ours is.
run_ssh_setup() {
    local root="$1"; shift

    if ! { : < /dev/tty; } 2>/dev/null; then
        log_error "No terminal available — the passphrase must be typed interactively"
        return 1
    fi

    bash "$root/common/ssh.sh" "$@" < /dev/tty
}

# -h anywhere in the arguments means "print the usage and touch nothing"
wants_help() {
    local arg
    for arg in "$@"; do
        [[ "$arg" == "-h" || "$arg" == "--help" ]] && return 0
    done
    return 1
}

main() {
    detect_repo_root

    local help=0
    wants_help "$@" && help=1

    if (( ! help )); then
        # keychain is an optimisation, not a requirement — common/ssh.sh falls
        # back to the plain ssh-agent — so a failed install must not take the
        # whole SSH setup down with it under set -e.
        install_keychain || log_warning "Continuing without keychain — the plain ssh-agent will be used"
        hint_gh
        echo ""
    fi

    local root="$REPO_ROOT"
    if [[ -z "$root" ]]; then
        download_common || return 1
        root="$TMP_ROOT"
        echo ""
    fi

    # The usage text lives in common/ssh.sh; print it from there rather than
    # keeping a second copy in step. No terminal is needed for that.
    if (( help )); then
        bash "$root/common/ssh.sh" -h
        return
    fi

    run_ssh_setup "$root" "$@"
}

# Piped into a shell BASH_SOURCE[0] is empty and $0 is "bash", so the plain
# equality test would never fire and the script would silently do nothing.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
