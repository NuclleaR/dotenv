#!/bin/bash

# SSH Backup to Private Gist
# This script creates an encrypted backup of ~/.ssh and uploads it to a private GitHub Gist

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

# Check if ~/.ssh exists
if [[ ! -d ~/.ssh ]]; then
    log_error "~/.ssh directory does not exist"
    exit 1
fi

# Create temporary directory
#
# Everything below is written in here, including the *plaintext* archive of
# ~/.ssh before it is encrypted, so the directory must not outlive the script —
# not on an error, and above all not on a Ctrl-C at the GPG passphrase prompt.
# One trap replaces the rm -rf that used to be copy-pasted into every exit path.
TEMP_DIR=$(mktemp -d)

cleanup_temp_dir() {
    [[ -n "${TEMP_DIR:-}" ]] && rm -rf "$TEMP_DIR"
    return 0
}
trap cleanup_temp_dir EXIT

log_info "Created temporary directory: $TEMP_DIR"

# Archive name with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE_NAME="ssh_backup_${TIMESTAMP}.tar.gz"
ENCRYPTED_NAME="${ARCHIVE_NAME}.gpg"
ENCODED_NAME="${ENCRYPTED_NAME}.b64"

log_info "Creating archive of ~/.ssh..."
cd ~
tar -czf "${TEMP_DIR}/${ARCHIVE_NAME}" .ssh
log_success "Archive created: ${ARCHIVE_NAME}"

log_info "Encrypting archive..."
log_warning "You will be prompted to enter a passphrase for encryption"
echo ""

# Encrypt with GPG using symmetric encryption
gpg --symmetric --cipher-algo AES256 --output "${TEMP_DIR}/${ENCRYPTED_NAME}" "${TEMP_DIR}/${ARCHIVE_NAME}"

if [[ ! -f "${TEMP_DIR}/${ENCRYPTED_NAME}" ]]; then
    log_error "Encryption failed"
    exit 1
fi

log_success "Archive encrypted: ${ENCRYPTED_NAME}"

log_info "Encoding to base64..."
base64 "${TEMP_DIR}/${ENCRYPTED_NAME}" > "${TEMP_DIR}/${ENCODED_NAME}"
log_success "Archive encoded: ${ENCODED_NAME}"

log_info "Uploading to private GitHub Gist..."
GIST_URL=$(gh gist create "${TEMP_DIR}/${ENCODED_NAME}" --desc "SSH Backup ${TIMESTAMP}")

if [[ -z "$GIST_URL" ]]; then
    log_error "Failed to create Gist"
    exit 1
fi

log_success "Backup uploaded successfully!"
echo ""
echo "======================================"
echo "Gist URL: ${GIST_URL}"
echo "======================================"
echo ""

# Get the raw URL
GIST_ID=$(basename "$GIST_URL")
RAW_URL="https://gist.githubusercontent.com/$(gh api user --jq .login)/${GIST_ID}/raw/${ENCODED_NAME}"

log_success "Backup complete!"
echo ""
echo "======================================"
log_info "RESTORE COMMAND:"
echo "======================================"
echo ""
echo "# Download, decode, decrypt, extract and set permissions:"
echo "curl -sL '${RAW_URL}' | base64 -d | gpg -d | tar -xzf - -C ~ && chmod 700 ~/.ssh && chmod 600 ~/.ssh/* && chmod 644 ~/.ssh/*.pub"
echo ""
echo "# Or step by step:"
echo "curl -sL '${RAW_URL}' > ssh_backup.b64"
echo "base64 -d ssh_backup.b64 > ssh_backup.gpg"
echo "gpg -d ssh_backup.gpg > ssh_backup.tar.gz"
echo "tar -xzf ssh_backup.tar.gz -C ~"
echo "chmod 700 ~/.ssh"
echo "chmod 600 ~/.ssh/*"
echo "chmod 644 ~/.ssh/*.pub"
echo ""
echo "======================================"
echo ""
log_warning "Save the restore command and remember your passphrase!"

echo ""
log_success "Done!"
