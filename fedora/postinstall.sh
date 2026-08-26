#!/bin/bash

# Post-install setup for Fedora
#
# Replaces firewalld with ufw and adds fail2ban to watch sshd for brute force.
# Written for a headless box reached over SSH/Tailscale: every step that touches
# the firewall keeps the current session alive — the SSH port is allowed before
# ufw is ever enabled, and the Tailscale range is never banned.

# Run it straight off the internet, no clone needed — it only touches system
# packages and system config, nothing in this repo:
#
#   curl -sS https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/postinstall.sh | bash
#
# That is why the log helpers are inline instead of sourced from common/: piped
# into a shell there is no script path to resolve a sibling file from. Keep them
# in step with common/logger.sh.

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

# Tailscale hands out addresses from the CGNAT range; never firewall or ban it
TAILSCALE_CGNAT="100.64.0.0/10"
TAILSCALE_IFACE="tailscale0"

# Upper bound for the persistent journal
JOURNAL_MAX_USE="200M"

# Networks fail2ban must never ban. Left empty here and filled in by
# build_ignoreip: loopback, the tailnet, and the private subnets this machine is
# actually attached to. Anything knocking from outside those still gets banned,
# which is the whole point of the jail. Override to pin it by hand:
#   FAIL2BAN_IGNOREIP="127.0.0.1/8 ::1 10.0.0.0/8" ./postinstall.sh
FAIL2BAN_IGNOREIP="${FAIL2BAN_IGNOREIP:-}"

# Ports sshd actually listens on, filled in by detect_ssh_ports
SSH_PORTS=()

# Ask sshd itself which ports it listens on, so a non-standard port is not
# locked out. Falls back to the config files, then to 22.
detect_ssh_ports() {
    local ports=()

    if command_exists sshd; then
        mapfile -t ports < <(sudo sshd -T 2>/dev/null | awk '/^port /{print $2}') || true
    fi

    if [[ ${#ports[@]} -eq 0 ]]; then
        mapfile -t ports < <(
            cat /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null |
                awk '/^[[:space:]]*[Pp]ort[[:space:]]+[0-9]+/{print $2}'
        ) || true
    fi

    if [[ ${#ports[@]} -eq 0 ]]; then
        ports=(22)
        log_warning "Could not detect the sshd port, assuming 22"
    fi

    SSH_PORTS=("${ports[@]}")
    log_info "sshd listens on port(s): ${SSH_PORTS[*]}"
}

# Say out loud that we are about to firewall the machine we are logged into
warn_if_remote_session() {
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        log_warning "You are connected over SSH — the firewall rules below allow ${SSH_PORTS[*]} before ufw is enabled"
        log_warning "Established connections survive 'ufw enable', but keep this session open until you verified a second one"
    fi
}

# Stop, disable and mask firewalld. Removal only happens when nothing else
# depends on it — otherwise the package stays, masked and inert.
disable_firewalld() {
    if ! systemctl list-unit-files firewalld.service >/dev/null 2>&1; then
        log_success "firewalld is not installed"
        return 0
    fi

    if systemctl is-active --quiet firewalld; then
        log_info "Stopping firewalld..."
        sudo systemctl stop firewalld
    fi

    log_info "Disabling and masking firewalld..."
    sudo systemctl disable firewalld >/dev/null 2>&1 || true
    sudo systemctl mask firewalld >/dev/null 2>&1 || true
    log_success "firewalld stopped, disabled and masked"

    remove_firewalld
}

# Remove the firewalld package, but only when that does not drag anything else
# out with it (libvirt-daemon-config-network and cockpit both require it).
remove_firewalld() {
    local dependents=()

    mapfile -t dependents < <(
        dnf repoquery --installed --whatrequires firewalld --qf '%{name}' 2>/dev/null |
            grep -vE '^(firewalld|python3-firewall)' | sort -u
    ) || true

    if [[ ${#dependents[@]} -gt 0 ]]; then
        log_warning "Not removing firewalld — these installed packages require it:"
        local pkg
        for pkg in "${dependents[@]}"; do
            log_warning "    $pkg"
        done
        log_info "firewalld stays installed but masked, so it cannot start"
        log_info "To remove it anyway (and everything above) run:"
        log_info "    sudo dnf remove firewalld"
        return 0
    fi

    log_info "Removing firewalld..."
    if ! sudo dnf remove -y firewalld; then
        log_error "Failed to remove firewalld (it stays masked, so it will not start)"
        return 1
    fi

    log_success "firewalld removed"
}

# Install ufw from the Fedora repositories
install_ufw() {
    if command_exists ufw; then
        log_success "ufw already installed"
        log_info "ufw version: $(sudo ufw version | head -n1)"
        return 0
    fi

    log_info "Installing ufw..."
    if ! sudo dnf install -y ufw; then
        log_error "Failed to install ufw"
        return 1
    fi

    log_success "ufw installed"
}

# Stage the rules, verify SSH is among them, and only then enable ufw
configure_ufw() {
    log_info "Configuring ufw defaults..."
    sudo ufw default deny incoming >/dev/null
    sudo ufw default allow outgoing >/dev/null
    log_success "Defaults set: deny incoming, allow outgoing"

    # limit instead of allow: same access, but rate limited against brute force
    local port
    for port in "${SSH_PORTS[@]}"; do
        log_info "Allowing (rate limited) SSH on $port/tcp..."
        sudo ufw limit "$port/tcp" comment 'SSH (dotenv)' >/dev/null
    done

    log_info "Allowing everything on $TAILSCALE_IFACE..."
    sudo ufw allow in on "$TAILSCALE_IFACE" comment 'Tailscale (dotenv)' >/dev/null
    if ! ip link show "$TAILSCALE_IFACE" >/dev/null 2>&1; then
        log_warning "$TAILSCALE_IFACE does not exist yet — the rule applies once Tailscale is up"
    fi

    # Last line of defence before we start dropping packets on a remote box
    if ! sudo ufw show added | grep -qE "limit .*${SSH_PORTS[0]}"; then
        log_error "SSH rule is missing from the staged ufw rules — refusing to enable ufw"
        return 1
    fi

    log_info "Enabling ufw..."
    sudo ufw --force enable >/dev/null
    sudo systemctl enable ufw >/dev/null 2>&1 || true
    log_success "ufw enabled"
}

# Install fail2ban
install_fail2ban() {
    if command_exists fail2ban-server; then
        log_success "fail2ban already installed"
        return 0
    fi

    log_info "Installing fail2ban..."
    if ! sudo dnf install -y fail2ban; then
        log_error "Failed to install fail2ban"
        return 1
    fi

    log_success "fail2ban installed"
}

# The directly attached IPv4 networks, already in network form. Only RFC1918
# ranges are kept: on a box with a public address the connected route would be
# the provider's subnet, and whitelisting that would be a hole, not a courtesy.
detect_local_subnets() {
    ip -o -4 route show scope link 2>/dev/null |
        awk '{print $1}' |
        grep -E '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)[0-9./]+$' |
        sort -u
}

# Loopback + tailnet + local subnets, unless the caller pinned it by hand
build_ignoreip() {
    if [[ -n "$FAIL2BAN_IGNOREIP" ]]; then
        log_info "Using the FAIL2BAN_IGNOREIP given: $FAIL2BAN_IGNOREIP"
        return 0
    fi

    local NETS=("127.0.0.1/8" "::1" "$TAILSCALE_CGNAT")
    local NET

    while read -r NET; do
        [[ -n "$NET" ]] && NETS+=("$NET")
    done < <(detect_local_subnets)

    FAIL2BAN_IGNOREIP="${NETS[*]}"
}

# Point fail2ban at ufw and watch sshd. Tailscale and localhost are never banned.
configure_fail2ban() {
    build_ignoreip

    local JAIL="/etc/fail2ban/jail.local"
    local FIREWALLD_DROPIN="/etc/fail2ban/jail.d/00-firewalld.conf"

    # Fedora ships this drop-in and it forces banaction back to firewalld
    if [[ -f "$FIREWALLD_DROPIN" ]]; then
        log_info "Disabling the firewalld drop-in that overrides banaction..."
        sudo mv "$FIREWALLD_DROPIN" "$FIREWALLD_DROPIN.disabled"
        log_success "Moved to $FIREWALLD_DROPIN.disabled"
    fi

    if [[ -f "$JAIL" ]] && ! grep -qF "Generated by the dotenv setup" "$JAIL"; then
        local BACKUP="$JAIL.backup.$(date +%Y%m%d-%H%M%S)"
        log_warning "Existing $JAIL backed up to $BACKUP"
        sudo cp "$JAIL" "$BACKUP"
    fi

    log_info "Writing $JAIL..."
    sudo tee "$JAIL" >/dev/null <<EOF
# Generated by the dotenv setup (fedora/postinstall.sh)

[DEFAULT]
# ufw owns the firewall on this box, so bans go through it, not firewalld
banaction = ufw
# Fedora logs sshd to the journal, not to a file
backend   = systemd
# Never ban ourselves over loopback or the tailnet
ignoreip  = $FAIL2BAN_IGNOREIP
bantime   = 1h
findtime  = 10m
maxretry  = 5

[sshd]
enabled = true
port    = $(IFS=,; echo "${SSH_PORTS[*]}")
EOF
    log_success "fail2ban configured (banaction=ufw, sshd jail enabled)"
    log_info "Never banned: $FAIL2BAN_IGNOREIP"
    log_info "Everything knocking from outside those is subject to the jail"

    log_info "Enabling fail2ban..."
    sudo systemctl enable --now fail2ban
    log_success "fail2ban enabled"
}

# Weekly TRIM for SSDs. Fedora ships the timer but does not always enable it.
enable_fstrim() {
    if ! systemctl list-unit-files fstrim.timer >/dev/null 2>&1; then
        log_warning "fstrim.timer not available (util-linux missing?)"
        return 0
    fi

    if systemctl is-enabled --quiet fstrim.timer 2>/dev/null; then
        log_success "fstrim.timer already enabled"
    else
        log_info "Enabling fstrim.timer..."
        sudo systemctl enable --now fstrim.timer
        log_success "fstrim.timer enabled"
    fi

    log_info "Next run: $(systemctl list-timers fstrim.timer --no-pager --no-legend 2>/dev/null | awk '{print $1, $2, $3}')"
}

# Cap the journal so logs cannot eat the disk. Written as a drop-in, so the
# distribution's own journald.conf is left alone.
limit_journal_size() {
    local DROPIN_DIR="/etc/systemd/journald.conf.d"
    local DROPIN="$DROPIN_DIR/00-dotenv.conf"

    if [[ -f "$DROPIN" ]] && grep -qF "SystemMaxUse=$JOURNAL_MAX_USE" "$DROPIN"; then
        log_success "Journal already capped at $JOURNAL_MAX_USE"
        return 0
    fi

    log_info "Capping the journal at $JOURNAL_MAX_USE..."
    sudo mkdir -p "$DROPIN_DIR"
    sudo tee "$DROPIN" >/dev/null <<EOF
# Generated by the dotenv setup (fedora/postinstall.sh)
[Journal]
SystemMaxUse=$JOURNAL_MAX_USE
EOF

    sudo systemctl restart systemd-journald
    log_success "Journal capped at $JOURNAL_MAX_USE ($DROPIN)"
    log_info "Current journal size: $(journalctl --disk-usage 2>/dev/null || echo unknown)"
}

# Print what the machine ended up with
show_status() {
    log_info "ufw status:"
    sudo ufw status verbose || true

    echo ""
    log_info "fail2ban sshd jail:"
    sudo fail2ban-client status sshd || log_warning "fail2ban is not answering yet — check: sudo systemctl status fail2ban"
}

main() {
    detect_ssh_ports
    warn_if_remote_session

    disable_firewalld

    install_ufw
    configure_ufw

    install_fail2ban
    configure_fail2ban

    enable_fstrim
    limit_journal_size

    echo ""
    log_success "Post-install setup completed!"

    echo ""
    show_status

    echo ""
    log_warning "Open a SECOND ssh session now and confirm it works before closing this one"
}

# Run main only when executed directly, not when sourced
# Piped into a shell, BASH_SOURCE[0] is empty and $0 is the shell's name, so the
# plain equality test used elsewhere in this repo would silently do nothing.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
