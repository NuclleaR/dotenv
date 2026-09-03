#!/bin/bash

# Installs the commands in bin/ into ~/.local/bin.
#
# Run it straight off the internet, no clone needed:
#
#   curl -fsSL https://raw.githubusercontent.com/NuclleaR/dotenv/main/bin/install.sh | bash
#
# From a clone it copies the file sitting next to it instead of downloading.
# The log helpers are inline for the same reason as in fedora/apps.sh: piped
# into a shell there is no script path to source a sibling from.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

RAW_BASE="${DOTENV_RAW:-https://raw.githubusercontent.com/NuclleaR/dotenv/main}"

# There is no directory listing over raw.githubusercontent, so a new command in
# bin/ has to be added here by hand or the piped install will miss it.
BIN_FILES=(
    vpn
    dev
)

TARGET_DIR="${HOME}/.local/bin"

# Empty when piped into a shell, the directory holding this script otherwise
script_dir() {
    if [[ -z "${BASH_SOURCE[0]:-}" ]]; then
        return 1
    fi
    (cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
}

# Existing files are backed up rather than silently replaced, but only when they
# actually differ — re-running this should not litter the directory. Returns 1
# when the target is already identical, so the caller can skip the copy.
back_up_if_changed() {
    local TARGET="$1" NEW="$2"

    if [[ ! -f "$TARGET" ]]; then
        return 0
    fi

    if cmp -s "$TARGET" "$NEW"; then
        return 1
    fi

    local BACKUP="${TARGET}.backup.$(date +%Y%m%d%H%M%S)"
    cp "$TARGET" "$BACKUP"
    log_info "Existing $(basename "$TARGET") backed up to $(basename "$BACKUP")"
}

install_one() {
    local NAME="$1"
    local TARGET="$TARGET_DIR/$NAME"
    local SRC DIR TMP=""

    if DIR="$(script_dir)" && [[ -f "$DIR/$NAME" ]]; then
        SRC="$DIR/$NAME"
        log_info "$NAME: copying from the clone"
    else
        TMP="$(mktemp)"
        log_info "$NAME: downloading from $RAW_BASE/bin/$NAME"
        if ! curl -fsSL "$RAW_BASE/bin/$NAME" -o "$TMP"; then
            rm -f "$TMP"
            log_error "$NAME: download failed"
            return 1
        fi
        SRC="$TMP"
    fi

    if back_up_if_changed "$TARGET" "$SRC"; then
        cp "$SRC" "$TARGET"
        chmod 0755 "$TARGET"
        log_success "$NAME installed into $TARGET_DIR"
    else
        log_success "$NAME already up to date"
    fi

    [[ -n "$TMP" ]] && rm -f "$TMP"
    return 0
}

check_path() {
    case ":$PATH:" in
        *":$TARGET_DIR:"*)
            log_success "$TARGET_DIR is on PATH"
            ;;
        *)
            log_warning "$TARGET_DIR is not on PATH in this shell"
            log_info "shared/zsh.sh adds it, so a new zsh session will find it"
            ;;
    esac
}

main() {
    mkdir -p "$TARGET_DIR"

    local NAME
    for NAME in "${BIN_FILES[@]}"; do
        install_one "$NAME" || log_warning "$NAME did not install cleanly"
    done

    echo ""
    check_path
    echo ""
    log_info "Try it: vpn help, dev help"
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
