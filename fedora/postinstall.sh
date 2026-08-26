#!/bin/bash

# Post-install setup for Fedora
#
# Sets up firewalld and adds fail2ban to watch sshd for brute force.
#
# RUN THIS FIRST on a fresh system, before apps.sh, storage.sh or shell.sh.
# "post install" is after installing the *operating system*, not after installing
# software. This is what closes the box, so it needs nothing any of the other
# scripts provide and installs what it needs itself. Running it later leaves a
# new machine exposed for the whole length of the setup.
#
# Anything that has to happen after apps.sh belongs at the end of that sequence,
# not in here.
# Written for a headless box reached over SSH/Tailscale: every step that touches
# the firewall keeps the current session alive — the ssh service is allowed in
# the default zone before firewalld is reloaded, and the local networks are
# never banned. An earlier version of this script installed ufw instead; that
# is reverted here.

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

# Put firewalld back: earlier versions of this script replaced it with ufw, so
# it may be masked or gone. Fedora's shipped zones already allow the ssh service,
# so bringing it up cannot cut an existing session.
restore_firewalld() {
    if ! rpm -q firewalld >/dev/null 2>&1; then
        log_info "Installing firewalld..."
        if ! sudo dnf install -y firewalld; then
            log_error "Failed to install firewalld"
            return 1
        fi
    else
        log_success "firewalld already installed"
    fi

    if [[ "$(systemctl is-enabled firewalld 2>&1)" == "masked" ]]; then
        log_info "firewalld is masked, unmasking..."
        sudo systemctl unmask firewalld
    fi

    sudo systemctl enable firewalld >/dev/null 2>&1 || true

    # Start it only when it is down. Bouncing a running firewall on every re-run
    # is needless churn on a box we are logged into.
    if systemctl is-active --quiet firewalld; then
        log_success "firewalld already running"
    else
        log_info "Starting firewalld..."
        if ! sudo systemctl start firewalld; then
            log_error "firewalld failed to start — check: sudo journalctl -u firewalld -n 30"
            return 1
        fi
    fi

    log_success "firewalld enabled ($(sudo firewall-cmd --state 2>/dev/null || echo unknown))"
}

# Make sure the port we are logged in over is allowed, and trust the tailnet
configure_firewalld() {
    local ZONE
    ZONE="$(sudo firewall-cmd --get-default-zone 2>/dev/null || echo public)"
    log_info "Default zone: $ZONE"

    # Every --add-* below is asked about first: firewall-cmd warns and returns
    # non-zero flavours of "already there" otherwise, and under set -e a re-run
    # would abort the script instead of being a no-op.
    local CHANGED=false

    if sudo firewall-cmd --permanent --zone="$ZONE" --query-service=ssh >/dev/null 2>&1; then
        log_success "ssh service already allowed in $ZONE"
    else
        log_info "Allowing the ssh service in $ZONE..."
        sudo firewall-cmd --permanent --zone="$ZONE" --add-service=ssh >/dev/null
        CHANGED=true
    fi

    # A non-standard sshd port is not covered by the ssh service definition
    local PORT
    for PORT in "${SSH_PORTS[@]}"; do
        [[ "$PORT" == "22" ]] && continue

        if sudo firewall-cmd --permanent --zone="$ZONE" --query-port="$PORT/tcp" >/dev/null 2>&1; then
            log_success "port $PORT/tcp already allowed in $ZONE"
        else
            log_info "Allowing the non-standard sshd port $PORT/tcp..."
            sudo firewall-cmd --permanent --zone="$ZONE" --add-port="$PORT/tcp" >/dev/null
            CHANGED=true
        fi
    done

    if ip link show "$TAILSCALE_IFACE" >/dev/null 2>&1; then
        if sudo firewall-cmd --permanent --zone=trusted --query-interface="$TAILSCALE_IFACE" >/dev/null 2>&1; then
            log_success "$TAILSCALE_IFACE already in the trusted zone"
        else
            log_info "Moving $TAILSCALE_IFACE into the trusted zone..."
            sudo firewall-cmd --permanent --zone=trusted --change-interface="$TAILSCALE_IFACE" >/dev/null
            CHANGED=true
        fi
    else
        log_warning "$TAILSCALE_IFACE does not exist — re-run this after Tailscale is up to trust it"
    fi

    if [[ "$CHANGED" == true ]]; then
        sudo firewall-cmd --reload >/dev/null
        log_success "firewalld configured"
    else
        log_success "firewalld already configured, nothing to reload"
    fi
}

# Undo the ufw setup an earlier version of this script may have applied
remove_ufw() {
    if ! rpm -q ufw >/dev/null 2>&1; then
        log_success "ufw is not installed"
        return 0
    fi

    log_info "Disabling ufw..."
    sudo ufw --force disable >/dev/null 2>&1 || true
    sudo systemctl disable --now ufw >/dev/null 2>&1 || true

    log_info "Removing ufw..."
    if ! sudo dnf remove -y ufw; then
        log_warning "Could not remove ufw — it is disabled, so it will not interfere"
        return 0
    fi

    log_success "ufw removed"
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

# fail2ban-firewalld ships jail.d/00-firewalld.conf, which sets
# banaction = firewallcmd-rich-rules. An earlier version of this script moved it
# aside to force banaction = ufw; put it back and let the packaged action win, so
# nothing here has to hand-maintain a ban action.
restore_firewalld_dropin() {
    local DROPIN="/etc/fail2ban/jail.d/00-firewalld.conf"
    local UFW_ACTION="/etc/fail2ban/action.d/ufw.conf"

    if [[ -f "$DROPIN.disabled" && ! -f "$DROPIN" ]]; then
        log_info "Restoring the fail2ban firewalld drop-in..."
        sudo mv "$DROPIN.disabled" "$DROPIN"
        log_success "Restored $DROPIN"
    elif [[ -f "$DROPIN" ]]; then
        log_success "fail2ban firewalld drop-in in place"
    else
        log_warning "$DROPIN is missing — install it with: sudo dnf install fail2ban-firewalld"
    fi

    # Our hand-written ufw action is dead weight now
    if [[ -f "$UFW_ACTION" ]] && grep -qF "dotenv setup" "$UFW_ACTION"; then
        log_info "Removing the ufw action this script used to install..."
        sudo rm -f "$UFW_ACTION"
    fi
}

# Point fail2ban at ufw and watch sshd. Tailscale and localhost are never banned.
configure_fail2ban() {
    build_ignoreip
    restore_firewalld_dropin

    local JAIL="/etc/fail2ban/jail.local"

    if [[ -f "$JAIL" ]] && ! grep -qF "Generated by the dotenv setup" "$JAIL"; then
        local BACKUP="$JAIL.backup.$(date +%Y%m%d-%H%M%S)"
        log_warning "Existing $JAIL backed up to $BACKUP"
        sudo cp "$JAIL" "$BACKUP"
    fi

    log_info "Writing $JAIL..."
    sudo tee "$JAIL" >/dev/null <<EOF
# Generated by the dotenv setup (fedora/postinstall.sh)

[DEFAULT]
# banaction is deliberately not set here: jail.d/00-firewalld.conf from the
# fail2ban-firewalld package sets firewallcmd-rich-rules, and jail.d wins over
# jail.local, so setting it here would be silently ignored anyway.
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
    log_success "fail2ban configured (banaction from the firewalld drop-in, sshd jail enabled)"
    log_info "Never banned: $FAIL2BAN_IGNOREIP"
    log_info "Everything knocking from outside those is subject to the jail"

    log_info "Enabling fail2ban..."
    sudo systemctl enable fail2ban >/dev/null 2>&1 || true
    # restart, not "enable --now": on a re-run the service is already up and
    # --now would leave it running with the previous config
    if ! sudo systemctl restart fail2ban; then
        log_error "fail2ban failed to start — check: sudo journalctl -u fail2ban -n 30"
        return 1
    fi
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
    log_info "firewalld:"
    sudo firewall-cmd --list-all || true

    echo ""
    log_info "fail2ban sshd jail:"
    sudo fail2ban-client status sshd || log_warning "fail2ban is not answering yet — check: sudo systemctl status fail2ban"
}

main() {
    detect_ssh_ports
    warn_if_remote_session

    # firewalld first, so the box is never briefly unprotected, then ufw goes
    restore_firewalld
    configure_firewalld
    remove_ufw

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
