#!/bin/bash

# AdGuard Home for Fedora — network-wide DNS ad blocking
#
# Runs it as a ROOTFUL podman container driven by systemd through a quadlet
# unit, which is the native way to run a service on Fedora: podman generates a
# real .service from /etc/containers/systemd/, so it starts at boot, restarts on
# failure and shows up in systemctl like anything else.
#
#   curl -fsSL https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/adguard.sh | bash -s -- -h
#   curl -fsSL https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/adguard.sh | bash -s -- -a
#
# That is why the log helpers are inline instead of sourced from common/: piped
# into a shell there is no script path to resolve a sibling file from. Keep them
# in step with common/logger.sh.
#
# Run fedora/postinstall.sh FIRST — this script expects firewalld to already be
# up and the tailscale0 interface to already be in the trusted zone.
#
# Three decisions worth knowing before you edit anything here:
#
#   * Rootful, not rootless. Port 53 is privileged, and more importantly the
#     rootless network stack rewrites the source address of inbound traffic, so
#     every LAN client would show up in the query log as the same gateway IP and
#     per-client rules would be meaningless.
#
#   * Network=host, not published ports. AdGuard Home then binds the host's
#     interfaces directly: real client addresses in the log, and nothing else to
#     rewire if this box ever takes over DHCP. The cost is that the container
#     owns those host ports outright — see ADGUARD_WEB_PORT below.
#
#   * The host resolves through systemd-resolved's UPSTREAM, not through
#     AdGuard Home. See free_port_53: the box has to keep resolving names while
#     the container is stopped, or a re-run of this script cannot even pull the
#     new image. The machine itself is therefore unfiltered; every other device
#     on the LAN is what this is for.

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

# The image. Left at :latest so a first run cannot fail on a tag that has since
# been retired; pin it as soon as you have a working box — `-v` prints the exact
# line to paste:
#   ADGUARD_TAG=v0.107.68 ./fedora/adguard.sh -i service
ADGUARD_IMAGE="${ADGUARD_IMAGE:-docker.io/adguard/adguardhome}"
ADGUARD_TAG="${ADGUARD_TAG:-latest}"

# Config and query-log database live here. Everything worth backing up on this
# box is these two directories.
ADGUARD_DATA_DIR="${ADGUARD_DATA_DIR:-/var/lib/adguardhome}"

# The admin UI port. AdGuard Home's first-run wizard always listens on 3000, so
# keeping the UI on 3000 afterwards means one port to open instead of two — and
# leaves the host's port 80 free, which Network=host would otherwise hand to the
# container. Pick the SAME number in the wizard's "Admin Web Interface" step.
ADGUARD_WEB_PORT="${ADGUARD_WEB_PORT:-3000}"

ADGUARD_SERVICE="adguardhome.service"
QUADLET_DIR="/etc/containers/systemd"
QUADLET_FILE="$QUADLET_DIR/adguardhome.container"

RESOLVED_DROPIN_DIR="/etc/systemd/resolved.conf.d"
RESOLVED_DROPIN="$RESOLVED_DROPIN_DIR/10-adguardhome.conf"

# systemd-resolved's uplink resolv.conf: the real upstream servers, without the
# 127.0.0.53 stub that would otherwise fight AdGuard Home for port 53.
RESOLV_UPSTREAM="/run/systemd/resolve/resolv.conf"

# Same detection postinstall.sh uses for the fail2ban ignore list: the private
# subnets this machine is actually attached to.
detect_local_subnets() {
    ip -o -4 route show scope link 2>/dev/null |
        awk '{print $1}' |
        grep -E '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)[0-9./]+$' |
        sort -u
}

# Quadlet needs podman 4.4+. apps.sh installs podman too; this is here so the
# script stands alone when piped.
ensure_podman() {
    if ! command_exists podman; then
        log_info "Installing podman..."
        if ! sudo dnf install -y podman; then
            log_error "Failed to install podman"
            return 1
        fi
    else
        log_success "podman already installed ($(podman --version))"
    fi

    if [[ ! -d "$QUADLET_DIR" ]] && ! sudo test -d /usr/lib/systemd/system-generators; then
        log_warning "Could not verify quadlet support — podman 4.4 or newer is required"
    fi
}

# Hand port 53 over to AdGuard Home.
#
# Fedora Server runs systemd-resolved with a stub listener on 127.0.0.53:53.
# AdGuard Home wants to bind 0.0.0.0:53, which includes that address, so one of
# them has to move. We switch the stub off and point /etc/resolv.conf at
# resolved's UPSTREAM file instead of its stub file.
#
# Deliberately NOT "nameserver 127.0.0.1": that would send the host's own
# lookups through the container, and then a stopped container means a box that
# cannot resolve anything — including the registry it needs to pull the fixed
# image from. Reliability of the box beats filtering the box.
free_port_53() {
    if ! systemctl is-active --quiet systemd-resolved; then
        log_info "systemd-resolved is not running — nothing holding port 53"
        return 0
    fi

    local CHANGED=false

    if [[ -f "$RESOLVED_DROPIN" ]] && grep -qF "DNSStubListener=no" "$RESOLVED_DROPIN"; then
        log_success "systemd-resolved stub listener already disabled"
    else
        log_info "Disabling the systemd-resolved stub listener..."
        sudo mkdir -p "$RESOLVED_DROPIN_DIR"
        sudo tee "$RESOLVED_DROPIN" >/dev/null <<EOF
# Generated by the dotenv setup (fedora/adguard.sh)
# Frees 127.0.0.53:53 so AdGuard Home can bind 0.0.0.0:53.
# Remove this file and restart systemd-resolved to undo.
[Resolve]
DNSStubListener=no
EOF
        CHANGED=true
    fi

    # Point the host at the upstream file rather than the stub that no longer
    # listens. Existing state is preserved, per the repo's backup convention.
    local CURRENT=""
    if [[ -L /etc/resolv.conf ]]; then
        CURRENT="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
    fi

    if [[ "$CURRENT" == "$RESOLV_UPSTREAM" ]]; then
        log_success "/etc/resolv.conf already points at the upstream resolver"
    else
        if [[ -e /etc/resolv.conf && ! -L /etc/resolv.conf ]]; then
            local BACKUP="/etc/resolv.conf.backup.$(date +%Y%m%d%H%M%S)"
            log_info "Backing up the existing /etc/resolv.conf to $BACKUP"
            sudo cp -a /etc/resolv.conf "$BACKUP"
        elif [[ -n "$CURRENT" ]]; then
            log_info "/etc/resolv.conf currently points at $CURRENT"
        fi

        log_info "Pointing /etc/resolv.conf at $RESOLV_UPSTREAM..."
        sudo ln -sf "$RESOLV_UPSTREAM" /etc/resolv.conf
        CHANGED=true
    fi

    if [[ "$CHANGED" == true ]]; then
        sudo systemctl restart systemd-resolved
        log_success "Port 53 released by systemd-resolved"
    else
        log_success "Port 53 already free, nothing to restart"
    fi

    # Say so loudly if something else is still sitting on it — the container
    # would fail to start with a bind error that is not obvious from the logs.
    local HOLDER
    HOLDER="$(sudo ss -lnup 'sport = :53' 2>/dev/null | awk 'NR>1 {print $NF}' | head -n1 || true)"
    if [[ -n "$HOLDER" ]] && ! systemctl is-active --quiet "$ADGUARD_SERVICE"; then
        log_warning "Something is still listening on port 53: $HOLDER"
    fi
}

# Open DNS and the admin UI to the LAN only.
#
# Not to the whole default zone: a DNS resolver reachable from the internet gets
# conscripted into amplification attacks within days. Everything here is scoped
# to the private subnets this box is actually on. Tailscale needs no rule —
# postinstall.sh puts tailscale0 in the trusted zone, which bypasses this zone
# entirely.
configure_firewall() {
    if ! command_exists firewall-cmd; then
        log_warning "firewalld is not installed — run fedora/postinstall.sh first"
        return 1
    fi

    local ZONE
    ZONE="$(sudo firewall-cmd --get-default-zone 2>/dev/null || echo public)"
    log_info "Default zone: $ZONE"

    local SUBNETS=()
    local NET
    while read -r NET; do
        [[ -n "$NET" ]] && SUBNETS+=("$NET")
    done < <(detect_local_subnets)

    if [[ ${#SUBNETS[@]} -eq 0 ]]; then
        log_error "No private subnet detected — refusing to open port 53 to everything"
        log_error "Connect this box to the LAN and re-run, or add the rules by hand"
        return 1
    fi

    log_info "Allowing DNS from: ${SUBNETS[*]}"

    # Every rule is queried first: firewall-cmd returns non-zero flavours of
    # "already there", which under set -e would abort a re-run.
    local CHANGED=false
    local RULE SPEC

    for NET in "${SUBNETS[@]}"; do
        for SPEC in "53:udp" "53:tcp" "$ADGUARD_WEB_PORT:tcp"; do
            RULE="rule family=\"ipv4\" source address=\"$NET\" port port=\"${SPEC%%:*}\" protocol=\"${SPEC##*:}\" accept"

            if sudo firewall-cmd --permanent --zone="$ZONE" --query-rich-rule="$RULE" >/dev/null 2>&1; then
                log_success "${SPEC/:/\/} already allowed from $NET"
            else
                log_info "Allowing ${SPEC/:/\/} from $NET..."
                sudo firewall-cmd --permanent --zone="$ZONE" --add-rich-rule="$RULE" >/dev/null
                CHANGED=true
            fi
        done
    done

    if [[ "$CHANGED" == true ]]; then
        sudo firewall-cmd --reload >/dev/null
        log_success "firewalld configured for AdGuard Home"
    else
        log_success "firewalld already configured, nothing to reload"
    fi

    if ! ip link show tailscale0 >/dev/null 2>&1; then
        log_warning "tailscale0 does not exist — the admin UI is reachable from the LAN only"
    fi
}

# Write the quadlet unit and bring the container up
install_service() {
    ensure_podman

    log_info "Creating $ADGUARD_DATA_DIR/{work,conf}..."
    sudo mkdir -p "$ADGUARD_DATA_DIR/work" "$ADGUARD_DATA_DIR/conf"

    local TZ_VALUE
    TZ_VALUE="$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)"

    sudo mkdir -p "$QUADLET_DIR"

    # Rewritten on every run; the container's own state lives in the volumes, so
    # replacing this file costs nothing.
    log_info "Writing $QUADLET_FILE..."
    sudo tee "$QUADLET_FILE" >/dev/null <<EOF
# Generated by the dotenv setup (fedora/adguard.sh) — edits here are overwritten.
[Unit]
Description=AdGuard Home (network-wide DNS ad blocking)
Documentation=https://github.com/AdguardTeam/AdGuardHome/wiki
Wants=network-online.target
After=network-online.target

[Container]
ContainerName=adguardhome
Image=$ADGUARD_IMAGE:$ADGUARD_TAG
AutoUpdate=registry
# Host networking keeps the real client addresses in the query log, which is
# what makes per-client rules and "which device asked for this" work at all.
Network=host
Environment=TZ=$TZ_VALUE
# :Z relabels for SELinux — without it the container cannot write its config
Volume=$ADGUARD_DATA_DIR/work:/opt/adguardhome/work:Z
Volume=$ADGUARD_DATA_DIR/conf:/opt/adguardhome/conf:Z

[Service]
Restart=always
# First start pulls the image, which is slow on a cold box
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
EOF

    log_info "Reloading systemd so quadlet regenerates the unit..."
    sudo systemctl daemon-reload

    if systemctl is-active --quiet "$ADGUARD_SERVICE"; then
        log_info "Restarting $ADGUARD_SERVICE to pick up the new unit..."
        sudo systemctl restart "$ADGUARD_SERVICE"
    else
        log_info "Starting $ADGUARD_SERVICE (pulling the image may take a while)..."
        if ! sudo systemctl start "$ADGUARD_SERVICE"; then
            log_error "$ADGUARD_SERVICE failed to start — check: sudo journalctl -u $ADGUARD_SERVICE -n 50"
            return 1
        fi
    fi

    log_success "$ADGUARD_SERVICE is up"
}

# podman-auto-update pulls a newer image for anything marked AutoUpdate=registry
# and rolls back on its own if the new container fails its health check.
# Pointless while ADGUARD_TAG is a pinned version, which is the whole idea of
# pinning — so this only nags when it would actually do nothing.
enable_autoupdate() {
    if [[ "$ADGUARD_TAG" != "latest" ]]; then
        log_warning "ADGUARD_TAG is pinned to $ADGUARD_TAG — auto-update will not move it"
    fi

    if systemctl is-enabled --quiet podman-auto-update.timer 2>/dev/null; then
        log_success "podman-auto-update.timer already enabled"
        return 0
    fi

    log_info "Enabling podman-auto-update.timer..."
    sudo systemctl enable --now podman-auto-update.timer
    log_success "Images will be checked daily ($(systemctl show -p TimersCalendar --value podman-auto-update.timer 2>/dev/null || echo 'see systemctl list-timers'))"
}

# What the box ended up with, plus the two things you need after a first run
show_status() {
    log_info "$ADGUARD_SERVICE: $(systemctl is-active "$ADGUARD_SERVICE" 2>&1) / $(systemctl is-enabled "$ADGUARD_SERVICE" 2>&1)"

    if command_exists podman; then
        sudo podman ps --filter name=adguardhome --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || true

        local DIGEST
        DIGEST="$(sudo podman image inspect --format '{{index .RepoDigests 0}}' "$ADGUARD_IMAGE:$ADGUARD_TAG" 2>/dev/null || true)"
        if [[ -n "$DIGEST" ]]; then
            echo ""
            log_info "Running image: $DIGEST"
        fi

        local VERSION
        VERSION="$(sudo podman exec adguardhome /opt/adguardhome/AdGuardHome --version 2>/dev/null | head -n1 || true)"
        if [[ -n "$VERSION" ]]; then
            log_info "$VERSION"
            log_info "Pin it once you are happy:  ADGUARD_TAG=<version> $0 -i service"
        fi
    fi

    echo ""
    log_info "Listening on port 53:"
    sudo ss -lntup 'sport = :53' 2>/dev/null || log_warning "nothing on port 53"

    echo ""
    if [[ -L /etc/resolv.conf ]]; then
        log_info "/etc/resolv.conf -> $(readlink -f /etc/resolv.conf)"
    else
        log_info "/etc/resolv.conf is a regular file, not a symlink"
    fi

    # Prefer an RFC1918 address: on a box with Tailscale the tailnet 100.x
    # address sorts first, and printing that here would point at an interface
    # the firewall rules above deliberately do not cover.
    local IP
    IP="$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 |
        grep -E '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' | head -n1 || true)"
    [[ -z "$IP" ]] && IP="$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
    echo ""
    log_info "Admin UI: http://${IP:-<this-box>}:$ADGUARD_WEB_PORT"
}

usage() {
    cat <<EOF
AdGuard Home for Fedora (rootful podman + systemd quadlet)

Usage:
  ./fedora/adguard.sh [-i <name>] [-a] [-l] [-v] [-h]
  curl -fsSL <raw-url>/fedora/adguard.sh | bash -s -- -a

  -i <name>   run one step (repeatable)
  -a          run everything, in order
  -l          list the step names
  -v          print status, listening ports and the image version
  -h          this help

Names:
  resolved    turn off the systemd-resolved stub listener, freeing port 53
  firewall    allow 53/udp, 53/tcp and $ADGUARD_WEB_PORT/tcp from the local subnets only
  service     write $QUADLET_FILE and start it
  autoupdate  enable podman-auto-update.timer

Environment:
  ADGUARD_IMAGE      container image (default: $ADGUARD_IMAGE)
  ADGUARD_TAG        image tag (default: $ADGUARD_TAG — pin this once it works)
  ADGUARD_DATA_DIR   config and query log (default: $ADGUARD_DATA_DIR)
  ADGUARD_WEB_PORT   admin UI port (default: $ADGUARD_WEB_PORT)

Run fedora/postinstall.sh before this. After a first run, open the admin UI and
finish the wizard — set "Admin Web Interface" to port $ADGUARD_WEB_PORT so this
script's firewall rule keeps matching.
EOF
}

ALL_TARGETS=(resolved firewall service autoupdate)

list_targets() {
    printf '%s\n' "${ALL_TARGETS[@]}"
}

run_target() {
    case "$1" in
        resolved)   free_port_53 ;;
        firewall)   configure_firewall ;;
        service)    install_service ;;
        autoupdate) enable_autoupdate ;;
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
            v) show_status; exit 0 ;;
            h) usage; exit 0 ;;
            \?) log_error "Unknown option: -$OPTARG"; echo ""; usage; exit 1 ;;
            :) log_error "Option -$OPTARG requires an argument"; exit 1 ;;
        esac
    done

    if [[ "$RUN_ALL" == true ]]; then
        # resolved before service: the container cannot bind 53 until the stub
        # listener is gone
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

    echo ""
    show_status

    echo ""
    log_warning "Finish the setup wizard in the admin UI, then point the router's DHCP DNS at this box"
}

# Run main when executed directly or piped into a shell, but not when sourced.
# Piped, BASH_SOURCE[0] is empty and $0 is the shell's name, so the plain
# equality test used elsewhere in this repo would silently do nothing.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
