#!/bin/bash

# SSH setup: key generation, agent, client config and GitHub wiring.
#
# Distribution independent: only ssh-keygen, ssh-add, ssh-keyscan and optionally
# keychain are used, and nothing is ever installed from here, so it runs the
# same anywhere. The passphrase is always asked for interactively; it is never
# taken from a file or an argument.

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

# Set once the key is known to be on the account (gh uploaded it, or it was
# already there) and once the manual instructions have been printed. The
# connection test reads both: they are what separates "GitHub never got this
# key" from "GitHub has it and still refuses it", and they keep the key from
# being printed twice in one run.
KEY_ON_GITHUB=false
MANUAL_UPLOAD_SHOWN=false

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

# Load the key into an agent.
#
# keychain, when it is there, keeps one agent per host that every terminal
# reuses, so the passphrase is asked once per boot instead of once per session —
# which is what you want on a box you reach from many terminals. It is an
# optimisation, not a requirement: this script lives in common/ and has to run on
# any distribution, so it never installs anything and falls back to the plain
# agent. Install keychain from the distro app script if you want the nicer path.
setup_agent() {
    local KEY_PATH="$SSH_DIR/$KEY_NAME"

    # Already in the agent? Then a re-run must not ask for the passphrase again.
    if [[ -f "$KEY_PATH.pub" ]]; then
        local FPR
        FPR="$(ssh-keygen -lf "$KEY_PATH.pub" 2>/dev/null | awk '{print $2}')"
        if [[ -n "$FPR" ]] && ssh-add -l 2>/dev/null | grep -qF "$FPR"; then
            log_success "$KEY_NAME is already loaded in the agent"
            return 0
        fi
    fi

    if command_exists keychain; then
        log_info "Loading $KEY_NAME into keychain (passphrase prompt follows)..."
        if keychain --quiet "$KEY_PATH"; then
            log_success "Key loaded — every new shell reuses this agent"
        else
            log_warning "keychain failed — load the key later with: keychain ~/.ssh/$KEY_NAME"
        fi

        log_info "If logind kills user processes at logout, keep the agent alive with:"
        log_info "    sudo loginctl enable-linger ${USER:-$(id -un)}"
        return 0
    fi

    log_info "keychain is not installed, using the plain ssh-agent"

    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        log_warning "No agent is running in this session"
        log_info "Start one and add the key with:"
        log_info "    eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/$KEY_NAME"
        return 0
    fi

    log_info "Adding $KEY_NAME to the running agent (passphrase prompt follows)..."
    if ssh-add "$KEY_PATH"; then
        log_success "Key added to the running agent"
    else
        log_warning "ssh-add failed — add it later with: ssh-add ~/.ssh/$KEY_NAME"
    fi
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
        # A re-run must not churn the file or drop another backup next to it,
        # so compare what is there with what we would write first
        local CURRENT
        CURRENT="$(awk -v b="$CONFIG_BEGIN" -v e="$CONFIG_END" \
            '$0 == b { f = 1 } f { print } $0 == e { f = 0 }' "$CONFIG")"

        if [[ "$CURRENT" == "$BLOCK" ]]; then
            chmod 600 "$CONFIG"
            log_success "$CONFIG already up to date"
            return 0
        fi

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

# Copy stdin to the clipboard when the session has one. A headless box reached
# over SSH has none, so failing here is normal and never fatal — the caller
# treats it as a hint, not as a step that has to succeed.
copy_to_clipboard() {
    if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command_exists wl-copy; then
        wl-copy >/dev/null 2>&1 && return 0
    fi

    if [[ -n "${DISPLAY:-}" ]] && command_exists xclip; then
        xclip -selection clipboard >/dev/null 2>&1 && return 0
    fi

    if [[ -n "${DISPLAY:-}" ]] && command_exists xsel; then
        xsel --clipboard --input >/dev/null 2>&1 && return 0
    fi

    return 1
}

# Fallback for every path where gh cannot upload the key: print the key itself,
# not just its path. On a headless box the script output is often the only
# window on that file, so a bare path means a second round trip.
show_key_for_manual_upload() {
    local PUB="$SSH_DIR/$KEY_NAME.pub"

    if [[ ! -f "$PUB" ]]; then
        log_error "Public key $PUB not found"
        return 0
    fi

    log_info "Add it by hand at https://github.com/settings/keys (New SSH key, type: Authentication)"
    log_info "Title: $(hostname)"
    echo ""
    echo "--------8<-------- $PUB --------8<--------"
    cat "$PUB"
    echo "--------8<------------------------------------------------"
    echo ""

    if copy_to_clipboard < "$PUB"; then
        log_success "Public key also copied to the clipboard"
    fi

    log_info "Once it is added, verify with: ssh -T git@$HOST_ALIAS"
    MANUAL_UPLOAD_SHOWN=true
}

# Upload the public key to GitHub with gh, skipping if it is already there.
# Every branch that cannot upload falls back to show_key_for_manual_upload.
upload_key_to_github() {
    if ! command_exists gh; then
        log_warning "gh is not installed — the key has to go to GitHub by hand"
        show_key_for_manual_upload
        return 0
    fi

    if ! gh auth status >/dev/null 2>&1; then
        log_warning "gh is not authenticated — run 'gh auth login' and re-run, or add the key by hand"
        show_key_for_manual_upload
        return 0
    fi

    local KEY_BODY
    KEY_BODY="$(awk '{print $2}' "$SSH_DIR/$KEY_NAME.pub")"

    if gh ssh-key list 2>/dev/null | grep -qF "$KEY_BODY"; then
        log_success "Key already uploaded to GitHub"
        KEY_ON_GITHUB=true
        return 0
    fi

    log_info "Uploading the public key to GitHub..."
    if gh ssh-key add "$SSH_DIR/$KEY_NAME.pub" --title "$(hostname)"; then
        log_success "Key uploaded to GitHub as '$(hostname)'"
        KEY_ON_GITHUB=true
    else
        log_warning "gh ssh-key add failed"
        show_key_for_manual_upload
    fi
}

# What to do about "Permission denied (publickey)". Everything local is already
# correct at this point, so the answer is never a stack trace: either the key
# was never offered, or GitHub has not been given it yet.
explain_publickey_denial() {
    # A key that is not in the agent fails exactly like a key GitHub does not
    # know, so rule that out before blaming the account.
    local IN_AGENT=true
    local FPR
    FPR="$(ssh-keygen -lf "$SSH_DIR/$KEY_NAME.pub" 2>/dev/null | awk '{print $2}')"
    if [[ -n "$FPR" ]] && ! ssh-add -l 2>/dev/null | grep -qF "$FPR"; then
        IN_AGENT=false
        log_warning "$KEY_NAME is not loaded in the agent, so ssh may never have offered it"
        log_info "Load it and try again: keychain --quiet ~/.ssh/$KEY_NAME   (or: ssh-add ~/.ssh/$KEY_NAME)"
    fi

    # gh says the key is on the account, yet this host still refuses it: the
    # account it went to is not the one this alias authenticates against.
    if [[ "$KEY_ON_GITHUB" == true ]]; then
        log_warning "gh reports the key is on the account it is logged into, but $HOST_ALIAS still refused it"
        log_info "Two usual reasons:"
        log_info "  1. the key landed on a different account than the one $HOST_ALIAS is for"
        log_info "  2. the organisation enforces SAML SSO — authorize the key at https://github.com/settings/keys"
        return 0
    fi

    # Only true when the agent check above found nothing wrong; otherwise it
    # would contradict the warning it just printed.
    [[ "$IN_AGENT" == true ]] &&
        log_info "Nothing local is broken — GitHub has simply never been given this key"

    if [[ "$HOST_ALIAS" != "github.com" ]]; then
        # ssh reports the real host, so the error names github.com even though
        # the alias does not. That reads like a bug and is not one.
        log_info "Host $HOST_ALIAS maps to HostName github.com, which is why the error above names github.com"
        log_info "It is still a separate identity: the key has to be on the account $HOST_ALIAS is for, not necessarily the one gh is logged into"
    fi

    # The key was already printed once this run; do not paste it a second time.
    if [[ "$MANUAL_UPLOAD_SHOWN" == true ]]; then
        log_info "Add the key printed above at https://github.com/settings/keys, then re-check with: ssh -T git@$HOST_ALIAS"
        return 0
    fi

    show_key_for_manual_upload
}

# GitHub answers with exit code 1 even on success, so match on the greeting
test_github_connection() {
    log_info "Testing the connection to $HOST_ALIAS..."

    local OUTPUT
    OUTPUT="$(ssh -T -o StrictHostKeyChecking=accept-new "git@$HOST_ALIAS" 2>&1)" || true

    if grep -q "successfully authenticated" <<<"$OUTPUT"; then
        log_success "${OUTPUT}"
        return 0
    fi

    # The expected ending of a first run without gh: the setup is complete and
    # correct, GitHub has simply never seen this key. Say that, and hand over
    # the manual path — do not leave the raw ssh error as the last word.
    if grep -qF "Permission denied (publickey)" <<<"$OUTPUT"; then
        log_warning "$HOST_ALIAS refused the key: Permission denied (publickey)"
        echo ""
        explain_publickey_denial
        return 0
    fi

    # Network and host-key failures say nothing about the key, so printing it
    # would only be noise.
    if grep -qE "Could not resolve hostname|Connection timed out|Network is unreachable|Connection refused|Host key verification failed" <<<"$OUTPUT"; then
        log_warning "Could not reach $HOST_ALIAS — this is not a key problem:"
        log_warning "    $OUTPUT"
        log_info "Re-check when the network is back: ssh -T git@$HOST_ALIAS"
        return 0
    fi

    log_warning "Could not authenticate to $HOST_ALIAS:"
    log_warning "    $OUTPUT"
    log_info "Re-check with: ssh -T git@$HOST_ALIAS"
}

main() {
    parse_args "$@"

    ensure_ssh_dir
    generate_ssh_key
    setup_agent
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
