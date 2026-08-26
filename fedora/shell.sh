#!/bin/bash

# Shell setup for Fedora
#
# Sets up the shell: zsh, starship, the zsh-users plugins, and the runtime
# config in ~/.shell that ~/.zshrc sources. Applications that are not part of
# the shell itself live in fedora/apps.sh.
#
# Run it straight off the internet, no clone needed:
#
#   curl -sS https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/shell.sh | bash
#
# Piped, it downloads the files it needs into ~/.shell. Run from a clone, it
# symlinks ~/.shell/<dir> at the repo instead, so editing a file in the repo
# still applies to every new shell without re-running anything.
#
# The log helpers are inline rather than sourced from common/ because piped into
# a shell there is no script path to resolve a sibling file from. Keep them in
# step with common/logger.sh.

set -euo pipefail

# Where the runtime config lives once installed
SHELL_DIR="${SHELL_DIR:-$HOME/.shell}"

# Where to fetch from when there is no clone to link against
RAW_BASE="${DOTENV_RAW:-https://raw.githubusercontent.com/NuclleaR/dotenv/main}"

# Zsh plugins are not packaged for Fedora, so they are cloned here
# (manual install as documented by zsh-users)
ZSH_PLUGINS_DIR="$HOME/.zsh"

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

# Directories of the repo that hold runtime config, mirrored into ~/.shell
RUNTIME_DIRS=(shared fedora)

# The files inside them that the shell actually sources at startup.
# shared/zsh.sh finds its siblings itself, but when downloading we have to know
# the list up front — there is no directory listing over raw.githubusercontent.
RUNTIME_FILES=(
    shared/zsh.sh
    shared/aliases.sh
    shared/skim.sh
    shared/starship.toml
    fedora/aliases.sh
)

# Repo root when running from a clone, empty when piped into a shell
REPO_ROOT=""

# Work out whether we are running from a checkout. Piped, BASH_SOURCE[0] is
# empty, so there is nothing to resolve and we fall back to downloading.
detect_repo_root() {
    local self dir

    if [[ -z "${BASH_SOURCE[0]:-}" ]]; then
        log_info "Running from a pipe — the runtime config will be downloaded"
        return 0
    fi

    self="$(readlink -f "${BASH_SOURCE[0]}")"
    dir="$(dirname "$(dirname "$self")")"

    if [[ -f "$dir/shared/zsh.sh" ]]; then
        REPO_ROOT="$dir"
        log_info "Running from the repo at $REPO_ROOT — the runtime config will be symlinked"
    else
        log_info "Not inside a checkout — the runtime config will be downloaded"
    fi
}

# Move whatever is currently at $1 out of the way, once, with a timestamp
back_up_path() {
    local TARGET="$1"
    local BACKUP="$TARGET.backup.$(date +%Y%m%d-%H%M%S)"

    mv "$TARGET" "$BACKUP"
    log_warning "Existing $TARGET moved to $BACKUP"
}

# Point ~/.shell/<dir> at the repo, so repo edits apply with no further steps
link_runtime_dir() {
    local DIR="$1"
    local SOURCE="$REPO_ROOT/$DIR"
    local TARGET="$SHELL_DIR/$DIR"

    if [[ ! -d "$SOURCE" ]]; then
        log_warning "$SOURCE does not exist, skipping"
        return 0
    fi

    if [[ -L "$TARGET" ]]; then
        if [[ "$(readlink -f "$TARGET")" == "$(readlink -f "$SOURCE")" ]]; then
            log_success "$TARGET already links to $SOURCE"
            return 0
        fi
        rm -f "$TARGET"
    elif [[ -e "$TARGET" ]]; then
        back_up_path "$TARGET"
    fi

    ln -sfn "$SOURCE" "$TARGET"
    log_success "$TARGET -> $SOURCE"
}

# Fetch one runtime file from GitHub into ~/.shell
download_runtime_file() {
    local REL="$1"
    local TARGET="$SHELL_DIR/$REL"

    mkdir -p "$(dirname "$TARGET")"

    # A stale symlink from a previous clone-based run would be written through
    [[ -L "$TARGET" ]] && rm -f "$TARGET"

    log_info "Downloading $REL..."
    if ! curl -fsSL "$RAW_BASE/$REL" -o "$TARGET.tmp"; then
        log_error "Failed to download $RAW_BASE/$REL"
        rm -f "$TARGET.tmp"
        return 1
    fi

    mv "$TARGET.tmp" "$TARGET"
    log_success "$REL"
}

# Put the runtime config under ~/.shell, by symlink or by download
install_runtime_config() {
    mkdir -p "$SHELL_DIR"

    if [[ -n "$REPO_ROOT" ]]; then
        local DIR
        for DIR in "${RUNTIME_DIRS[@]}"; do
            link_runtime_dir "$DIR"
        done
        return 0
    fi

    if ! command_exists curl; then
        log_error "curl is needed to download the runtime config"
        return 1
    fi

    log_warning "$SHELL_DIR is managed by this script — re-running overwrites it"
    log_warning "Keep local changes in the repo, not in $SHELL_DIR"

    local REL
    for REL in "${RUNTIME_FILES[@]}"; do
        download_runtime_file "$REL"
    done
}

# Install Zsh if it is not present
install_zsh() {
    if command_exists zsh; then
        log_success "Zsh already installed"
        log_info "Zsh version: $(zsh --version)"
        return 0
    fi

    log_info "Installing Zsh from official repository..."
    if ! sudo dnf install -y zsh; then
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
    if ! sudo dnf install -y "${MISSING[@]}"; then
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

# Symlink the Starship config out of ~/.shell into ~/.config
link_starship_config() {
    local CONFIG_SOURCE="$SHELL_DIR/shared/starship.toml"
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
        back_up_path "$CONFIG_TARGET"
    fi

    ln -sfn "$CONFIG_SOURCE" "$CONFIG_TARGET"
    log_success "Starship config symlinked to $CONFIG_TARGET"
}

# Install zsh-users plugins from Git (they are not available via dnf)
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

# Generate ~/.zshrc pointing at ~/.shell. Any existing file is backed up, never
# appended to — the generated one holds nothing but the source line.
setup_zshrc() {
    local ZSHRC="$HOME/.zshrc"
    local CONFIG="$SHELL_DIR/shared/zsh.sh"

    if [[ ! -f "$CONFIG" ]]; then
        log_error "$CONFIG is missing — the runtime config was not installed"
        return 1
    fi

    if [[ -f "$ZSHRC" ]] && grep -qF "$CONFIG" "$ZSHRC"; then
        log_success ".zshrc already sources $CONFIG"
        return 0
    fi

    [[ -f "$ZSHRC" ]] && back_up_path "$ZSHRC"

    cat > "$ZSHRC" <<EOF
# Generated by the dotenv setup
# The actual config lives in $SHELL_DIR — edit it there, not here
source "$CONFIG"
EOF

    log_success "Created .zshrc sourcing $CONFIG"
}

# Append the Fedora specific aliases (dnf) to .zshrc, after setup_zshrc has
# generated it — they are distro specific and cannot live in shared/.
configure_dnf_aliases() {
    local ZSHRC="$HOME/.zshrc"
    local ALIASES="$SHELL_DIR/fedora/aliases.sh"

    if [[ ! -f "$ALIASES" ]]; then
        log_warning "Fedora aliases not found at $ALIASES"
        return 1
    fi

    if [[ -f "$ZSHRC" ]] && grep -qF "$ALIASES" "$ZSHRC"; then
        log_success "Fedora aliases already sourced in .zshrc"
        return 0
    fi

    log_info "Sourcing Fedora aliases in .zshrc..."
    echo "" >> "$ZSHRC"
    echo "# Fedora specific aliases (dnf)" >> "$ZSHRC"
    echo "source \"$ALIASES\"" >> "$ZSHRC"
    log_success "Fedora aliases sourced in .zshrc"
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
    detect_repo_root

    install_zsh
    install_prerequisites
    install_runtime_config
    install_starship
    install_zsh_plugins
    setup_zshrc
    configure_dnf_aliases

    echo ""
    log_success "Shell setup completed!"
    log_info "Runtime config: $SHELL_DIR"

    echo ""
    show_default_shell_hint
}

# Run main when executed directly or piped into a shell, but not when sourced.
# Piped, BASH_SOURCE[0] is empty and $0 is the shell's name, so the plain
# equality test used elsewhere in this repo would silently do nothing.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
