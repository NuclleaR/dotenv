#!/bin/bash

# SSH Restore from Private Gist
# This script downloads and restores an encrypted SSH backup from a GitHub Gist

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common logger
source "$SCRIPT_DIR/logger.sh"

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI (gh) is not installed"
    log_info "Install it with your distro's bootstrap script, e.g. ./ubuntu/bootstrap.sh -i gh"
    exit 1
fi

# Check if user is authenticated with gh
if ! gh auth status &> /dev/null; then
    log_error "Not authenticated with GitHub CLI"
    log_info "Run: gh auth login"
    exit 1
fi

# Show help message
show_help() {
    echo "SSH Restore Script"
    echo ""
    echo "Usage: $0 <RAW_GIST_URL>"
    echo ""
    echo "Arguments:"
    echo "  RAW_GIST_URL    The raw URL of the Gist containing the SSH backup"
    echo ""
    echo "Example:"
    echo "  $0 https://gist.githubusercontent.com/username/gist_id/raw/ssh_backup_20231023_120000.tar.gz.gpg.b64"
    echo ""
    echo "Note: You will be prompted for the passphrase used during backup encryption"
}

# Check if URL is provided
if [[ $# -eq 0 ]]; then
    log_error "No URL provided"
    echo ""
    show_help
    exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

RAW_URL="$1"

# Validate URL format
if [[ ! "$RAW_URL" =~ ^https://gist\.githubusercontent\.com/ ]]; then
    log_error "Invalid URL format"
    log_info "URL must start with: https://gist.githubusercontent.com/"
    exit 1
fi

# Create temporary directory
#
# The download, the decoded archive and the *decrypted* tarball of ~/.ssh all
# land in here, so the directory must not outlive the script — not on an error,
# and above all not on a Ctrl-C at the GPG passphrase prompt, which is exactly
# where this script waits. One trap replaces the rm -rf that used to be
# copy-pasted into every exit path.
TEMP_DIR=$(mktemp -d)

cleanup_temp_dir() {
    [[ -n "${TEMP_DIR:-}" ]] && rm -rf "$TEMP_DIR"
    return 0
}
trap cleanup_temp_dir EXIT

log_info "Created temporary directory: $TEMP_DIR"

# Download the backup
log_info "Downloading backup from Gist..."
ENCODED_FILE="${TEMP_DIR}/ssh_backup.b64"
if ! curl -sL "$RAW_URL" -o "$ENCODED_FILE"; then
    log_error "Failed to download backup"
    exit 1
fi

if [[ ! -s "$ENCODED_FILE" ]]; then
    log_error "Downloaded file is empty"
    exit 1
fi

log_success "Backup downloaded"

# Decode from base64
log_info "Decoding from base64..."
ENCRYPTED_FILE="${TEMP_DIR}/ssh_backup.gpg"
if ! base64 -d "$ENCODED_FILE" > "$ENCRYPTED_FILE"; then
    log_error "Failed to decode base64"
    exit 1
fi
log_success "Backup decoded"

# Decrypt with GPG
log_info "Decrypting backup..."
log_warning "You will be prompted to enter the passphrase used during backup"
echo ""

ARCHIVE_FILE="${TEMP_DIR}/ssh_backup.tar.gz"
if ! gpg -d "$ENCRYPTED_FILE" > "$ARCHIVE_FILE" 2>/dev/null; then
    log_error "Failed to decrypt backup (wrong passphrase or corrupted file)"
    exit 1
fi

if [[ ! -s "$ARCHIVE_FILE" ]]; then
    log_error "Decrypted file is empty"
    exit 1
fi

log_success "Backup decrypted"

# Backup existing .ssh directory if it exists
if [[ -d ~/.ssh ]]; then
    BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="${HOME}/.ssh_backup_${BACKUP_TIMESTAMP}"
    log_warning "Existing ~/.ssh directory found"
    log_info "Creating backup at: ${BACKUP_DIR}"
    cp -r ~/.ssh "$BACKUP_DIR"
    log_success "Existing ~/.ssh backed up to ${BACKUP_DIR}"
fi

# Extract the archive
log_info "Extracting SSH files..."
if ! tar -xzf "$ARCHIVE_FILE" -C ~; then
    log_error "Failed to extract archive"
    exit 1
fi
log_success "SSH files extracted"

# Set proper permissions
log_info "Setting proper permissions..."
chmod 700 ~/.ssh
chmod 600 ~/.ssh/* 2>/dev/null || true
chmod 644 ~/.ssh/*.pub 2>/dev/null || true
log_success "Permissions set"

echo ""
echo "======================================"
log_success "SSH restore complete!"
echo "======================================"
echo ""
log_info "Your SSH keys have been restored to ~/.ssh"

if [[ -n "${BACKUP_DIR:-}" ]]; then
    log_info "Previous SSH directory backed up to: ${BACKUP_DIR}"
fi

echo ""
log_success "Done!"
