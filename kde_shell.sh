#!/bin/bash

BACKUP_DIR="$HOME/.kde_backups"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

ARCHIVE_NAME="kde_config_backup_$TIMESTAMP.tar.gz"

ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"

# Files and folders to back up
CONFIG_PATHS=(
  "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  "$HOME/.config/kdeglobals"
  "$HOME/.config/kwinrc"
  "$HOME/.config/kglobalshortcutsrc"
  "$HOME/.config/kscreenlockerrc"
  "$HOME/.config/ksmserverrc"
  "$HOME/.config/krunnerrc"
  "$HOME/.config/dolphinrc"
  "$HOME/.config/konsolerc"
  "$HOME/.config/systemsettingsrc"
  "$HOME/.config/autostart"
  "$HOME/.local/share/plasma"
  "$HOME/.local/share/icons"
  "$HOME/.local/share/aurorae"
  "$HOME/.local/share/konsole"
  "$HOME/.local/share/kwin/scripts"
  "$HOME/.local/share/wallpapers"
  "$HOME/.local/share/knewstuff3"
  "$HOME/.local/share/fonts"
)

usage() {
    cat << EOF
Usage: $0 {backup|restore|upload} [OPTIONS]

Commands:
    backup      Create a backup of KDE configuration
    restore     Restore KDE configuration from latest backup
    upload      Commit and push recent backups to git repository

Options:
    -h, --help  Show this help message

Examples:
    $0 backup      # Create a new backup
    $0 restore     # Restore from latest backup
    $0 upload      # Upload backups to git

EOF
    exit 0
}

do_backup() {
    # Create backup directory if needed
    mkdir -p "$BACKUP_DIR"

    # Filter CONFIG_PATHS to only include existing paths
    EXISTING_PATHS=()
    for path in "${CONFIG_PATHS[@]}"; do
        if [ -e "$path" ]; then
            EXISTING_PATHS+=("$path")
        fi
    done

    if [ ${#EXISTING_PATHS[@]} -eq 0 ]; then
        echo "No configuration files found to backup."
        return 1
    fi

    # Create archive
    echo "Creating KDE config backup at: $ARCHIVE_PATH"
    tar -czf "$ARCHIVE_PATH" "${EXISTING_PATHS[@]}"

    if [ $? -eq 0 ]; then
      echo "Backup successful!"
    else
      echo "Backup failed. Check for missing files or permissions."
    fi
}

do_restore() {
    # Check if backup directory exists
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "No backup directory found at: $BACKUP_DIR"
        return 1
    fi

    # Find the latest backup
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)

    if [ -z "$LATEST_BACKUP" ]; then
        echo "No backups found in: $BACKUP_DIR"
        return 1
    fi

    echo "Restoring from: $LATEST_BACKUP"
    tar -xzf "$LATEST_BACKUP" -C "$HOME"

    if [ $? -eq 0 ]; then
        echo "Restore successful!"
    else
        echo "Restore failed. Check permissions or backup integrity."
    fi
}

upload() {
    # Check if git is initialized in the backup directory
    if [ ! -d "$BACKUP_DIR/.git" ]; then
        echo "Git is not initialized in: $BACKUP_DIR"
        return 1
    fi

    # Get the last 3 files in backup directory
    RECENT_FILES=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -3)

    if [ -z "$RECENT_FILES" ]; then
        echo "No backup files found in: $BACKUP_DIR"
        return 1
    fi

    # Navigate to backup directory
    cd "$BACKUP_DIR" || return 1

    # Stage the files
    echo "$RECENT_FILES" | xargs git add

    # Commit if there are changes
    if git diff --cached --quiet; then
        echo "No changes to commit"
        return 0
    fi

    git commit -m "Backup KDE config - $(date +"%Y-%m-%d %H:%M:%S")"

    # Push to remote
    if git push; then
        echo "Upload successful!"
    else
        echo "Push failed. Check your remote configuration."
        return 1
    fi
}

case "$1" in
    backup) do_backup ;;
    restore) do_restore ;;
    upload) upload ;;
    -h|--help) usage ;;
    *) usage ;;
esac