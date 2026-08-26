#!/bin/bash

# SSH setup: key generation, agent, client config and GitHub wiring.
#
# Distribution independent — only ssh-keygen, ssh-add and systemd --user are
# used, so this works the same on Fedora, openSUSE and Arch. The passphrase is
# always asked for interactively; it is never taken from a file or an argument.

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities and logger
source "$SCRIPT_DIR/logger.sh"
source "$SCRIPT_DIR/utils.sh"

SSH_DIR="$HOME/.ssh"

# Defaults, overridable with -n / -H / -c
KEY_NAME="id_ed25519"
HOST_ALIAS="github.com"
KEY_COMMENT=""

# Hosts seeded into known_hosts so the first clone does not stop on a prompt
KNOWN_HOSTS_SEED=(github.com gitlab.com)

# Markers delimiting the block this script owns inside ~/.ssh/config
CONFIG_BEGIN="# >>> dotenv managed >>>"
CONFIG_END="# <<< dotenv managed <<<"

usage() {
    cat <<EOF
Usage: ${0##*/} [-n NAME] [-H HOST] [-c COMMENT] [-h]

  -n NAME     key file name in ~/.ssh (default: $KEY_NAME)
  -H HOST     Host alias written to ~/.ssh/config (default: $HOST_ALIAS)
  -c COMMENT  key comment (default: \$USER@\$(hostname))
  -h          show this help

Examples:
  ${0##*/}                            # default key, Host github.com
  ${0##*/} -n id_ed25519_work -H github-work
EOF
}

parse_args() {
    local opt
    while getopts ":n:H:c:h" opt; do
        case "$opt" in
            n) KEY_NAME="$OPTARG" ;;
            H) HOST_ALIAS="$OPTARG" ;;
            c) KEY_COMMENT="$OPTARG" ;;
            h) usage; exit 0 ;;
            \?) log_error "Unknown option: -$OPTARG"; usage; exit 1 ;;
            :) log_error "Option -$OPTARG requires an argument"; exit 1 ;;
        esac
    done

    [[ -n "$KEY_COMMENT" ]] || KEY_COMMENT="${USER:-$(id -un)}@$(hostname)"
}

# ~/.ssh must be 700, private keys 600, everything else 644 — sshd and ssh both
# refuse to use a key whose permissions are too open.
ensure_ssh_dir() {
    if [[ ! -d "$SSH_DIR" ]]; then
        log_info "Creating $SSH_DIR..."
        mkdir -p "$SSH_DIR"
    fi

    chmod 700 "$SSH_DIR"

    local file
    for file in "$SSH_DIR"/*; do
        [[ -f "$file" ]] || continue
        case "$file" in
            *.pub)                              chmod 644 "$file" ;;
            "$SSH_DIR/known_hosts"|"$SSH_DIR/config") chmod 600 "$file" ;;
            *)                                  chmod 600 "$file" ;;
        esac
    done

    log_success "$SSH_DIR permissions fixed (700, keys 600, *.pub 644)"
}

# Ask for the passphrase twice and compare. Never echoes it, never stores it
# anywhere but the variable ssh-keygen is called with.
prompt_passphrase() {
    if [[ ! -t 0 ]]; then
        log_error "No terminal available — the passphrase must be typed interactively"
        return 1
    fi

    local first second answer
    while true; do
        read -rsp "Passphrase for $KEY_NAME (empty for none): " first || return 1
        echo
        read -rsp "Repeat passphrase: " second || return 1
        echo

        if [[ "$first" != "$second" ]]; then
            log_error "Passphrases do not match, try again"
            continue
        fi

        if [[ -z "$first" ]]; then
            read -rp "Create a key with NO passphrase? [y/N] " answer || return 1
            [[ "$answer" == [yY] ]] || continue
        fi

        SSH_PASSPHRASE="$first"
        return 0
    done
}

# Generate an ed25519 key. An existing key is never overwritten.
generate_ssh_key() {
    local KEY_PATH="$SSH_DIR/$KEY_NAME"

    if [[ -f "$KEY_PATH" ]]; then
        log_success "Key $KEY_PATH already exists, keeping it"
        log_info "Fingerprint: $(ssh-keygen -lf "$KEY_PATH.pub" 2>/dev/null || echo unknown)"
        return 0
    fi

    log_info "Generating a new ed25519 key at $KEY_PATH..."
    prompt_passphrase || return 1

    if ! ssh-keygen -t ed25519 -C "$KEY_COMMENT" -f "$KEY_PATH" -N "$SSH_PASSPHRASE" >/dev/null; then
        unset SSH_PASSPHRASE
        log_error "ssh-keygen failed"
        return 1
    fi
    unset SSH_PASSPHRASE

    chmod 600 "$KEY_PATH"
    chmod 644 "$KEY_PATH.pub"

    log_success "Key generated: $KEY_PATH"
    log_info "Fingerprint: $(ssh-keygen -lf "$KEY_PATH.pub")"
}

# keychain keeps a single ssh-agent per host, so every terminal you open — and
# on a remote box that is many — reuses the same one and the passphrase is asked
# once per boot. The agent is picked up at shell start by shared/zsh.sh; this
# starts it now and loads the key, so the very next session is already unlocked.
setup_keychain() {
    if ! command_exists keychain; then
        log_warning "keychain not installed — install it with the distro shell script (Fedora: ./fedora/shell.sh)"
        log_info "Without it every shell starts its own agent: ssh-add ~/.ssh/$KEY_NAME"
        return 0
    fi

    log_info "Loading $KEY_NAME into keychain (passphrase prompt follows)..."
    if keychain --quiet "$SSH_DIR/$KEY_NAME"; then
        log_success "Key loaded — every new shell reuses this agent"
    else
        log_warning "keychain failed — load the key later with: keychain ~/.ssh/$KEY_NAME"
    fi

    log_info "If logind kills user processes at logout, keep the agent alive with:"
    log_info "    sudo loginctl enable-linger ${USER:-$(id -un)}"
}

# Write the dotenv block into ~/.ssh/config. Everything outside the markers is
# left untouched, so hand-written host entries survive.
configure_ssh_config() {
    local CONFIG="$SSH_DIR/config"
    local BLOCK
    BLOCK="$(cat <<EOF
$CONFIG_BEGIN
Host *
    AddKeysToAgent yes
    IdentitiesOnly yes
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host $HOST_ALIAS
    HostName github.com
    User git
    IdentityFile $SSH_DIR/$KEY_NAME
$CONFIG_END
EOF
    )"

    if [[ ! -f "$CONFIG" ]]; then
        log_info "Creating $CONFIG..."
        printf '%s\n' "$BLOCK" > "$CONFIG"
        chmod 600 "$CONFIG"
        log_success "$CONFIG created"
        return 0
    fi

    if grep -qF "$CONFIG_BEGIN" "$CONFIG"; then
        log_info "Replacing the dotenv block in $CONFIG..."
        local BACKUP="$CONFIG.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$CONFIG" "$BACKUP"
        log_warning "Existing config backed up to $BACKUP"

        local TMP
        TMP="$(mktemp)"
        awk -v begin="$CONFIG_BEGIN" -v end="$CONFIG_END" -v block="$BLOCK" '
            $0 == begin { print block; skip = 1; next }
            $0 == end   { skip = 0; next }
            !skip
        ' "$CONFIG" > "$TMP"
        mv "$TMP" "$CONFIG"
    else
        log_info "Appending the dotenv block to $CONFIG..."
        printf '\n%s\n' "$BLOCK" >> "$CONFIG"
    fi

    chmod 600 "$CONFIG"
    log_success "$CONFIG updated (Host $HOST_ALIAS -> $KEY_NAME)"
}

# Pre-seed known_hosts so the first git clone does not stop on a yes/no prompt.
# This trusts whatever the network answers right now — see the warning below.
seed_known_hosts() {
    local KNOWN_HOSTS="$SSH_DIR/known_hosts"
    touch "$KNOWN_HOSTS"

    local HOST
    for HOST in "${KNOWN_HOSTS_SEED[@]}"; do
        # -f is required: without it ssh-keygen resolves known_hosts from the
        # passwd entry, not from $HOME, and would check the wrong file
        if ssh-keygen -F "$HOST" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
            log_success "$HOST already in known_hosts"
            continue
        fi

        log_info "Fetching host keys for $HOST..."
        if ssh-keyscan -t ed25519,rsa "$HOST" >> "$KNOWN_HOSTS" 2>/dev/null; then
            log_success "$HOST added to known_hosts"
        else
            log_warning "ssh-keyscan failed for $HOST"
        fi
    done

    chmod 600 "$KNOWN_HOSTS"
    log_warning "known_hosts was seeded from the network — verify github.com against https://docs.github.com/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints"
}

# Upload the public key to GitHub with gh, skipping if it is already there
upload_key_to_github() {
    if ! command_exists gh; then
        log_warning "gh not installed — add the key manually at https://github.com/settings/keys"
        log_info "Public key: $SSH_DIR/$KEY_NAME.pub"
        return 0
    fi

    if ! gh auth status >/dev/null 2>&1; then
        log_warning "gh is not authenticated — run: gh auth login"
        return 0
    fi

    local KEY_BODY
    KEY_BODY="$(awk '{print $2}' "$SSH_DIR/$KEY_NAME.pub")"

    if gh ssh-key list 2>/dev/null | grep -qF "$KEY_BODY"; then
        log_success "Key already uploaded to GitHub"
        return 0
    fi

    log_info "Uploading the public key to GitHub..."
    if gh ssh-key add "$SSH_DIR/$KEY_NAME.pub" --title "$(hostname)"; then
        log_success "Key uploaded to GitHub as '$(hostname)'"
    else
        log_warning "gh ssh-key add failed — add it manually at https://github.com/settings/keys"
    fi
}

# GitHub answers with exit code 1 even on success, so match on the greeting
test_github_connection() {
    log_info "Testing the connection to $HOST_ALIAS..."

    local OUTPUT
    OUTPUT="$(ssh -T -o StrictHostKeyChecking=accept-new "git@$HOST_ALIAS" 2>&1)" || true

    if grep -q "successfully authenticated" <<<"$OUTPUT"; then
        log_success "${OUTPUT}"
    else
        log_warning "Could not authenticate to $HOST_ALIAS:"
        log_warning "    $OUTPUT"
    fi
}

main() {
    parse_args "$@"

    ensure_ssh_dir
    generate_ssh_key
    setup_keychain
    configure_ssh_config
    seed_known_hosts
    upload_key_to_github

    echo ""
    log_success "SSH setup completed!"

    echo ""
    test_github_connection
}

# Run main only when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
