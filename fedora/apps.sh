#!/bin/bash

# App installer for Fedora
#
# Run it straight off the internet, no clone needed — it only installs software,
# it touches nothing in this repo:
#
#   curl -fsSL https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/apps.sh | bash -s -- -h
#   curl -fsSL https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/apps.sh | bash -s -- -a
#   curl -fsSL https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/apps.sh | bash -s -- -i rust
#
# That is why the log helpers are inline instead of sourced from common/: piped
# into a shell there is no script path to resolve a sibling file from. Keep them
# in step with common/logger.sh.
#
# Shell setup (zsh, starship config, ~/.zshrc) is fedora/shell.sh and does need
# the repo. Firewall and system hardening is fedora/postinstall.sh.

set -euo pipefail

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

# mise and other user-level installers write to ~/.local/bin, which is not on
# PATH in every shell. Without this the probes below report things as missing
# right after installing them.
[[ -d "$HOME/.local/bin" ]] && PATH="$HOME/.local/bin:$PATH"

# Which Nerd Font to fetch; the release asset is named "$NERD_FONT.tar.xz".
# The default lives in its own variable so usage() cannot drift from it.
NERD_FONT_DEFAULT="RobotoMono"
NERD_FONT="${NERD_FONT:-$NERD_FONT_DEFAULT}"

# Packages installed straight from the Fedora repositories
CLI_PACKAGES=(
    bat         # cat with syntax highlighting
    eza         # ls replacement
    zoxide      # smarter cd
    fd-find     # find replacement
    ripgrep     # grep replacement
    git-delta   # git diff pager
    jq          # JSON processor
    tree
    ncdu        # disk usage
    wget2-wget  # shim providing /usr/bin/wget; plain 'wget' is gone since F41
    unzip
    du-dust
    keychain    # one ssh-agent per host, shared by every terminal
)

# Rust tools that are not packaged, installed with cargo
CARGO_APPS=(
    rip2            # rm replacement with a graveyard
    skim            # fuzzy finder
    cargo-update
    cargo-binstall
)

usage() {
    cat <<EOF
App installer for Fedora

Usage:
  ./fedora/apps.sh [-i <name>] [-a] [-l] [-v] [-h]
  curl -fsSL <raw-url>/fedora/apps.sh | bash -s -- -a

  -i <name>   install one thing (repeatable)
  -a          install everything, in dependency order
  -l          list the installable names
  -v          print versions of what is already installed
  -h          this help

Names:
  base        Development Tools group, gcc-c++, make, curl, git
  cli         ${CLI_PACKAGES[*]}
  podman      podman, podman-compose
  gh          GitHub CLI
  tailscale   Tailscale VPN client
  starship    official install script
  mise        official install script
  rust        rustup, with --no-modify-path
  cargo-apps  ${CARGO_APPS[*]}   (needs rust)
  fonts       $NERD_FONT Nerd Font into ~/.local/share/fonts

Environment:
  NERD_FONT   which Nerd Font to fetch (default: $NERD_FONT_DEFAULT)
EOF
}

ALL_TARGETS=(base cli podman gh tailscale starship mise rust cargo-apps fonts)

list_targets() {
    printf '%s\n' "${ALL_TARGETS[@]}"
}

# Install one dnf package, saying so instead of reinstalling. A package that is
# not in the repositories is a warning, not a reason to abort the whole run.
install_dnf() {
    local PKG="$1"
    local PROBE="${2:-$1}"

    if command_exists "$PROBE"; then
        log_success "$PKG already installed"
        return 0
    fi

    log_info "Installing $PKG..."
    if ! sudo dnf install -y "$PKG"; then
        log_warning "Could not install $PKG — skipping"
        return 0
    fi

    log_success "$PKG installed"
}

# rustup is installed with --no-modify-path, so a plain bash session that never
# sourced the zsh config has no cargo on PATH. Pull it in before using it.
source_cargo_env() {
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    return 0
}

install_cargo_app() {
    local APP="$1"
    local PROBE="${2:-$1}"

    if command_exists "$PROBE"; then
        log_success "$APP already installed"
        return 0
    fi

    if ! command_exists cargo; then
        log_error "cargo not found — install rust first: -i rust"
        return 1
    fi

    log_info "Installing $APP via cargo..."
    if ! cargo install --locked "$APP"; then
        log_warning "cargo install $APP failed — skipping"
        return 0
    fi

    log_success "$APP installed"
}

install_base() {
    log_info "Installing Development Tools..."
    sudo dnf group install -y development-tools ||
        sudo dnf groupinstall -y "Development Tools" ||
        log_warning "Could not install the Development Tools group"

    # The group is not a C toolchain on its own: recent Fedora releases leave the
    # compiler out of it, and anything with a native module (node-pty, most
    # node-gyp packages, cc-rs crates) then fails to build. gcc-c++ pulls gcc and
    # glibc-devel along with it, so those two names cover the whole toolchain.
    install_dnf gcc-c++ g++
    install_dnf make

    install_dnf curl
    install_dnf git
    log_success "Base tooling ready"
}

install_cli() {
    local PKG
    for PKG in "${CLI_PACKAGES[@]}"; do
        case "$PKG" in
            fd-find)   install_dnf "$PKG" fd ;;
            ripgrep)   install_dnf "$PKG" rg ;;
            git-delta)  install_dnf "$PKG" delta ;;
            wget2-wget) install_dnf "$PKG" wget ;;
            *)         install_dnf "$PKG" ;;
        esac
    done
}

install_podman() {
    install_dnf podman
    install_dnf podman-compose
}

# gh is not in the Fedora repositories — GitHub ships its own.
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md
GH_REPO_URL="${GH_REPO_URL:-https://cli.github.com/packages/rpm/gh-cli.repo}"
GH_REPO_FILE="${GH_REPO_FILE:-/etc/yum.repos.d/gh-cli.repo}"

add_gh_repo() {
    if [[ -f "$GH_REPO_FILE" ]]; then
        log_success "gh-cli repository already configured"
        return 0
    fi

    log_info "Adding the gh-cli repository..."

    # dnf5 (Fedora 41+) spells it "config-manager addrepo --from-repofile"
    if sudo dnf install -y dnf5-plugins >/dev/null 2>&1 &&
        sudo dnf config-manager addrepo --from-repofile="$GH_REPO_URL"; then
        log_success "gh-cli repository added (dnf5)"
        return 0
    fi

    # dnf4 spells it "config-manager --add-repo"
    if sudo dnf install -y 'dnf-command(config-manager)' >/dev/null 2>&1 &&
        sudo dnf config-manager --add-repo "$GH_REPO_URL"; then
        log_success "gh-cli repository added (dnf4)"
        return 0
    fi

    return 1
}

install_gh() {
    if command_exists gh; then
        log_success "gh already installed"
        log_info "gh version: $(gh --version | head -n1)"
        return 0
    fi

    # Fedora 41+ ships gh in its own updates repo (verified on F44: gh-2.97.0).
    # Only older releases need GitHub's repository, so try the plain way first.
    log_info "Installing gh..."
    if sudo dnf install -y gh; then
        log_success "gh installed from the Fedora repositories"
    else
        log_info "gh is not in the configured repositories, adding GitHub's own..."

        if ! add_gh_repo; then
            log_error "Could not add the gh-cli repository"
            log_info "Add it by hand: $GH_REPO_URL"
            return 1
        fi

        if ! sudo dnf install -y gh; then
            log_error "Failed to install gh"
            return 1
        fi

        log_success "gh installed from the gh-cli repository"
    fi

    # Freshly installed binaries are not always visible to this shell yet
    if command_exists gh; then
        log_info "gh version: $(gh --version | head -n1)"
    else
        log_info "Open a new shell to pick gh up"
    fi
}

install_tailscale() {
    if command_exists tailscale; then
        log_success "tailscale already installed"
        log_info "tailscale version: $(tailscale --version | head -n1)"
    else
        # Their script, not a copy of its steps: it already handles dnf4 vs
        # dnf5, adds the repository and enables the daemon, and it keeps
        # working when Tailscale changes any of that. Same reasoning as
        # starship and mise above. https://tailscale.com/download/linux/fedora
        log_info "Installing tailscale from the official install script..."
        if ! curl -fsSL https://tailscale.com/install.sh | sh; then
            log_error "Failed to install tailscale"
            return 1
        fi

        log_success "tailscale installed"
    fi

    # The installer enables tailscaled itself, but this box is reached over the
    # tailnet, so it is worth being sure rather than assuming.
    if systemctl is-active tailscaled >/dev/null 2>&1 &&
        systemctl is-enabled tailscaled >/dev/null 2>&1; then
        log_success "tailscaled enabled and running"
    else
        log_info "Enabling tailscaled..."
        sudo systemctl enable --now tailscaled
        log_success "tailscaled enabled"
    fi

    # Joining a tailnet is a decision, not an installation step: it opens a
    # browser login and picks which tailnet this machine belongs to. Their
    # installer stops here too.
    if tailscale status >/dev/null 2>&1; then
        log_success "already joined a tailnet"
        return 0
    fi

    log_warning "tailscale is installed but has not joined a tailnet yet"
    log_info "Finish it by hand — it prints a URL to open in a browser:"
    echo ""
    echo "    sudo tailscale up --hostname=$(hostname -s)"
    echo ""
    log_info "Then two things that are easy to forget on a headless box:"
    log_info "  1. disable key expiry for this node in the Tailscale admin console,"
    log_info "     or it drops off the tailnet in 180 days and takes remote access with it"
    log_info "  2. re-run fedora/postinstall.sh, so firewalld puts tailscale0 in the trusted zone"
}

install_starship() {
    if command_exists starship; then
        log_success "starship already installed"
        return 0
    fi

    log_info "Installing starship from the official install script..."
    if ! curl -sS https://starship.rs/install.sh | sh -s -- -y; then
        log_error "Failed to install starship"
        return 1
    fi

    log_success "starship installed"
    log_info "Its config is symlinked by fedora/shell.sh, which needs the repo"
}

install_mise() {
    local MISE_BIN="$HOME/.local/bin/mise"

    if command_exists mise; then
        log_success "mise already installed"
        log_info "mise version: $(mise --version 2>&1 | head -n1)"
        return 0
    fi

    if [[ -x "$MISE_BIN" ]]; then
        log_success "mise already installed at $MISE_BIN"
        return 0
    fi

    log_info "Installing mise from the official install script..."
    if ! curl -sS https://mise.run | sh; then
        log_error "Failed to install mise"
        return 1
    fi

    # The installer writes to ~/.local/bin and never touches PATH — it only
    # prints the activation hint. A zero exit code is therefore not proof the
    # binary is there, and "installed" must not be claimed on the strength of it.
    if [[ ! -x "$MISE_BIN" ]]; then
        log_error "The installer reported success but $MISE_BIN is not there"
        return 1
    fi

    log_success "mise installed at $MISE_BIN"
    log_info "mise version: $("$MISE_BIN" --version 2>&1 | head -n1)"
    log_info "shared/zsh.sh puts ~/.local/bin on PATH and runs 'mise activate zsh'"
}

install_rust() {
    source_cargo_env

    if command_exists rustc; then
        log_success "rust already installed"
        log_info "rust version: $(rustc --version)"
        return 0
    fi

    log_info "Installing rustup (--no-modify-path)..."
    if ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs |
        sh -s -- -y --no-modify-path; then
        log_error "Failed to install rustup"
        return 1
    fi

    source_cargo_env
    log_success "rust installed"
    log_info "cargo lands on PATH through shared/zsh.sh sourcing ~/.cargo/env"
}

install_cargo_apps() {
    source_cargo_env

    if ! command_exists cargo; then
        log_error "cargo not found — run with -i rust first"
        return 1
    fi

    local APP
    for APP in "${CARGO_APPS[@]}"; do
        case "$APP" in
            du-dust)        install_cargo_app "$APP" dust ;;
            rip2)           install_cargo_app "$APP" rip ;;
            skim)           install_cargo_app "$APP" sk ;;
            cargo-update)   install_cargo_app "$APP" cargo-install-update ;;
            cargo-binstall) install_cargo_app "$APP" cargo-binstall ;;
            *)              install_cargo_app "$APP" ;;
        esac
    done
}

# Temp dir holding the font tarball; global so the EXIT trap can still reach it
# after install_fonts has returned.
FONT_TMP=""

cleanup_font_tmp() {
    [[ -n "$FONT_TMP" ]] && rm -rf "$FONT_TMP"
    FONT_TMP=""
    return 0
}

# Nerd Fonts are not in the Fedora repositories, so take the release tarball
install_fonts() {
    local FONT_DIR="$HOME/.local/share/fonts/$NERD_FONT"
    local URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$NERD_FONT.tar.xz"

    if [[ -d "$FONT_DIR" ]] && compgen -G "$FONT_DIR/*.ttf" >/dev/null; then
        log_success "$NERD_FONT Nerd Font already installed"
        return 0
    fi

    if ! command_exists curl; then
        log_error "curl not found — run with -i base first"
        return 1
    fi

    # The trap is what makes this safe: Ctrl-C during a font download used to
    # leave the tarball behind in /tmp, and so did a tar that could not read it.
    FONT_TMP="$(mktemp -d)"
    trap cleanup_font_tmp EXIT
    local TMP="$FONT_TMP"

    log_info "Downloading $NERD_FONT Nerd Font..."
    if ! curl -fsSL "$URL" -o "$TMP/font.tar.xz"; then
        log_error "Could not download $URL"
        log_info "Check the name against https://github.com/ryanoasis/nerd-fonts/releases"
        cleanup_font_tmp
        return 1
    fi

    mkdir -p "$FONT_DIR"
    if ! tar -xJf "$TMP/font.tar.xz" -C "$FONT_DIR"; then
        log_error "Could not unpack the $NERD_FONT archive"
        cleanup_font_tmp
        return 1
    fi
    cleanup_font_tmp

    if command_exists fc-cache; then
        fc-cache -f "$FONT_DIR" >/dev/null
    fi

    log_success "$NERD_FONT Nerd Font installed into $FONT_DIR"
}

print_versions() {
    local PAIRS=(
        "bat:bat" "eza:eza" "zoxide:zoxide" "fd:fd" "rg:rg" "delta:delta"
        "jq:jq" "podman:podman" "gh:gh" "tailscale:tailscale"
        "starship:starship" "mise:mise" "g++:g++" "make:make"
        "rustc:rustc" "cargo:cargo" "sk:sk" "dust:dust" "rip:rip"
    )

    source_cargo_env

    local PAIR NAME
    for PAIR in "${PAIRS[@]}"; do
        NAME="${PAIR%%:*}"
        if command_exists "$NAME"; then
            log_success "$NAME: $($NAME --version 2>&1 | head -n1)"
        else
            log_warning "$NAME: not installed"
        fi
    done
}

run_target() {
    case "$1" in
        base)       install_base ;;
        cli)        install_cli ;;
        podman)     install_podman ;;
        gh)         install_gh ;;
        tailscale)  install_tailscale ;;
        starship)   install_starship ;;
        mise)       install_mise ;;
        rust)       install_rust ;;
        cargo-apps) install_cargo_apps ;;
        fonts)      install_fonts ;;
        *)
            log_error "Unknown name: $1"
            echo ""
            list_targets
            return 1
            ;;
    esac
}

main() {
    local TARGETS=()
    local RUN_ALL=false
    local opt

    while getopts ":i:alvh" opt; do
        case "$opt" in
            i) TARGETS+=("$OPTARG") ;;
            a) RUN_ALL=true ;;
            l) list_targets; exit 0 ;;
            v) print_versions; exit 0 ;;
            h) usage; exit 0 ;;
            \?) log_error "Unknown option: -$OPTARG"; echo ""; usage; exit 1 ;;
            :) log_error "Option -$OPTARG requires an argument"; exit 1 ;;
        esac
    done

    if [[ "$RUN_ALL" == true ]]; then
        # rust before cargo-apps, base before everything that needs curl
        TARGETS=("${ALL_TARGETS[@]}")
    fi

    if [[ ${#TARGETS[@]} -eq 0 ]]; then
        usage
        exit 0
    fi

    local TARGET
    for TARGET in "${TARGETS[@]}"; do
        echo ""
        log_info "=== $TARGET ==="
        run_target "$TARGET" || log_warning "$TARGET did not finish cleanly"
    done

    echo ""
    log_success "Done!"
}

# Run main when executed directly or piped into a shell, but not when sourced.
# Piped, BASH_SOURCE[0] is empty and $0 is the shell's name, so the plain
# equality test used elsewhere in this repo would silently do nothing.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
