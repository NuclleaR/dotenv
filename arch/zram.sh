#!/bin/bash

# Zram configuration script for Arch Linux
# Zram creates a block device in RAM that is compressed
# Useful for increasing available memory through compression

set -euo pipefail

SCRIPT_DIR="$HOME/dev/dotenv"
source "$SCRIPT_DIR/common/logger.sh"

# Install and configure Zram
setup_zram() {
    log_info "Setting up Zram..."

    # Check if zram-generator is already installed
    if pacman -Qi zram-generator &>/dev/null; then
        log_success "zram-generator already installed"
    else
        log_info "Installing zram-generator..."
        sudo pacman -S --noconfirm zram-generator
        log_success "zram-generator installed"
    fi

    # Create zram configuration directory if it doesn't exist
    sudo mkdir -p /etc/systemd/zram-generator.conf.d

    # Get total memory in MB
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_mb=$((total_mem_kb / 1024))

    # Configure zram with compression ratio
    # Typically zram compression ratio is 3:1 to 4:1
    log_info "Creating Zram configuration..."
    sudo tee /etc/systemd/zram-generator.conf.d/zram.conf > /dev/null << 'EOF'
# Zram configuration for systemd-zram-generator
# This creates a compressed block device in RAM for swap

[zram0]
# Compression algorithm: lz4 (fast), zstd (better compression), lzo
compression-algorithm = zstd

# Zram device size (auto = 50% of RAM)
zram-size = min(ram / 2, 4096)

# Swap priority (higher = preferred)
swap-priority = 100

# Filesystem type (swap)
fs-type = swap
EOF

    # Enable and start systemd-zram-setup service
    log_info "Enabling systemd-zram-setup service..."
    sudo systemctl daemon-reload
    sudo systemctl enable systemd-zram-setup@zram0.service

    # Start the service
    log_info "Starting Zram service..."
    sudo systemctl start systemd-zram-setup@zram0.service

    # Check if service is active
    if sudo systemctl is-active --quiet systemd-zram-setup@zram0.service; then
        log_success "Zram service is active"
    else
        log_warning "Zram service failed to start. Check status with: sudo systemctl status systemd-zram-setup@zram0.service"
    fi

    # Display zram info
    log_info "Zram device information:"
    if [[ -d /sys/block/zram0 ]]; then
        echo "  Device: /dev/zram0"
        echo "  Size: $(cat /sys/block/zram0/disksize)"
        echo "  Compression: $(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo 'N/A')"
    fi

    # Display swap information
    log_info "Current swap configuration:"
    swapon --show || log_warning "No swap currently active"

    log_success "Zram setup completed!"
    log_info "Configuration file: /etc/systemd/zram-generator.conf.d/zram.conf"
    log_info "Monitor with: watch 'zramctl; echo; free -h'"
}

# Alternative setup using zram-init script (if zram-generator is not available)
setup_zram_legacy() {
    log_info "Setting up Zram using legacy method..."

    # Create zram initialization script
    sudo tee /usr/local/bin/zram-init.sh > /dev/null << 'SCRIPT'
#!/bin/bash

# Initialize Zram devices
# This script creates and activates zram swap devices

set -e

# Number of zram devices to create (typically 1)
NUM_ZR=1

# Get total memory in bytes
TOTALMEM=$(grep MemTotal /proc/meminfo | awk '{print $2 * 1024}')

# Allocate 50% of RAM to zram (in bytes)
ZRAMSIZE=$((TOTALMEM / 2))

modprobe zram num_devices=$NUM_ZR

for i in $(seq 0 $((NUM_ZR - 1))); do
    ZRAM_DEV="/dev/zram$i"

    # Wait for device to be created
    until [[ -b $ZRAM_DEV ]]; do
        sleep 1
    done

    # Set compression algorithm
    echo zstd > /sys/block/zram$i/comp_algorithm

    # Set zram device size
    echo $ZRAMSIZE > /sys/block/zram$i/disksize

    # Format as swap
    mkswap $ZRAM_DEV

    # Enable swap
    swapon -p 100 $ZRAM_DEV
done

echo "Zram initialized:"
zramctl
SCRIPT

    sudo chmod +x /usr/local/bin/zram-init.sh

    # Create systemd service for zram
    sudo tee /etc/systemd/system/zram-init.service > /dev/null << 'SERVICE'
[Unit]
Description=Initialize Zram block device
After=systemd-modules-load.service
Before=swap.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/zram-init.sh
RemainAfterExit=yes

[Install]
WantedBy=swap.target
SERVICE

    # Create modprobe configuration for zram
    sudo tee /etc/modprobe.d/zram.conf > /dev/null << 'MODPROBE'
# Zram kernel module configuration
# Create 1 zram device
options zram num_devices=1
MODPROBE

    log_info "Enabling zram-init service..."
    sudo systemctl daemon-reload
    sudo systemctl enable zram-init.service
    sudo systemctl start zram-init.service

    log_success "Zram legacy setup completed!"
    log_info "Configuration files:"
    log_info "  - /etc/modprobe.d/zram.conf"
    log_info "  - /etc/systemd/system/zram-init.service"
    log_info "  - /usr/local/bin/zram-init.sh"
}

# Disable and remove Zram
disable_zram() {
    log_info "Disabling Zram..."

    # Disable with zram-generator
    if systemctl is-active --quiet systemd-zram-setup@zram0.service; then
        log_info "Stopping Zram service..."
        sudo systemctl stop systemd-zram-setup@zram0.service
        sudo systemctl disable systemd-zram-setup@zram0.service
        log_success "Zram service disabled"
    fi

    # Disable legacy setup if exists
    if systemctl is-active --quiet zram-init.service 2>/dev/null; then
        log_info "Stopping legacy zram-init service..."
        sudo systemctl stop zram-init.service
        sudo systemctl disable zram-init.service
        log_success "Legacy Zram service disabled"
    fi

    # Remove zram from swap
    if swapon --show | grep -q zram; then
        log_info "Removing zram from swap..."
        sudo swapoff /dev/zram0 2>/dev/null || true
    fi

    log_success "Zram disabled"
}

# Show zram status and statistics
show_zram_stats() {
    log_info "Zram Statistics:"
    echo ""

    if command -v zramctl &>/dev/null; then
        zramctl
    else
        log_warning "zramctl not found"
    fi

    echo ""
    log_info "Swap info:"
    swapon --show

    echo ""
    log_info "Memory info:"
    free -h
}

# Main function
main() {
    case "${1:-help}" in
        setup)
            setup_zram
            ;;
        setup-legacy)
            setup_zram_legacy
            ;;
        disable)
            disable_zram
            ;;
        stats)
            show_zram_stats
            ;;
        help)
            cat << 'HELP'
Zram Configuration Script

Usage: $0 [COMMAND]

Commands:
  setup           Setup Zram using systemd-zram-generator (recommended)
  setup-legacy    Setup Zram using manual initialization script
  disable         Disable Zram and remove from swap
  stats           Show Zram statistics
  help            Show this help message

Examples:
  $0 setup              # Setup Zram with generator
  $0 disable            # Disable Zram
  $0 stats              # Show current statistics
HELP
            ;;
        *)
            log_error "Unknown command: $1"
            $0 help
            return 1
            ;;
    esac
}

main "$@"
