#!/bin/bash

# SELinux fix for SSH port forwarding on Fedora
#
# Symptom: plain ssh into the box works, but anything that needs a forwarded
# port does not. VS Code Remote-SSH gets as far as starting its server and then
# loops on
#
#     channel 2: open failed: connect failed: open failed
#
# while sudo ausearch -m avc -ts recent -c sshd-session shows the real reason:
#
#     avc: denied { name_connect } comm="sshd-session" dest=<high port>
#     scontext=...sshd_session_t tcontext=...ephemeral_port_t
#
# OpenSSH 9.8+ splits the daemon into sshd and sshd-session. The shipped policy
# gives the new sshd_session_t domain no port-forwarding rights, and there is no
# boolean for it (getsebool -a | grep ssh lists none). audit2allow suggests
# nis_enabled, which grants port-connect broadly across many domains — this
# installs the three rules forwarding actually needs instead.
#
# What this does NOT touch:
#
#   - sshd_config. AllowTcpForwarding is already yes on a stock Fedora, and the
#     denial happens after sshd has agreed to the forward. Setting it changes
#     nothing and hides the real cause.
#   - the audit log. The policy below is written out in full rather than
#     generated with audit2allow, because a box that has not been connected to
#     yet has no denials to generate it from.
#
# The policy is written as source, so it is auditable: three name_connect rules
# for one domain, no file access, no exec, no capabilities.
#
# Run it straight off the internet, no clone needed:
#
#   curl -sS https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/fix-ssh.sh | bash
#   curl -sS https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/fix-ssh.sh | bash -s -- -r
#
# The log helpers are inline rather than sourced from common/ because piped into
# a shell there is no script path to resolve a sibling file from. Keep them in
# step with common/logger.sh.

set -euo pipefail

MODULE_NAME="sshd-forward-ports"

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

usage() {
    cat <<EOF
SELinux fix for SSH port forwarding on Fedora

Usage:
  ./fedora/fix-ssh.sh [-r] [-s] [-h]
  curl -sS <raw-url>/fedora/fix-ssh.sh | bash

  -r   remove the $MODULE_NAME module again
  -s   show what is installed and what the audit log says, change nothing
  -h   this help

Installing is idempotent: an already-loaded module is reported, not rebuilt.
EOF
}

# Temp dir for the policy sources; global so the EXIT trap can reach it
TMP_DIR=""

cleanup_tmp_dir() {
    [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
    TMP_DIR=""
    return 0
}

module_installed() {
    command_exists semodule || return 1
    sudo semodule -l 2>/dev/null | grep -qx "$MODULE_NAME"
}

# Every rule here comes from a real denial; nothing was added "just in case".
#   ephemeral_port_t   the port a VS Code / JetBrains remote server listens on
#   unreserved_port_t  anything else above 1024 you forward to
#   ssh_port_t         forwarding to 22 itself, e.g. a jump to another host
write_policy_source() {
    cat > "$TMP_DIR/$MODULE_NAME.te" <<'EOF'
module sshd-forward-ports 1.0;

require {
    type sshd_session_t;
    type ephemeral_port_t;
    type unreserved_port_t;
    type ssh_port_t;
    class tcp_socket name_connect;
}

allow sshd_session_t ephemeral_port_t:tcp_socket name_connect;
allow sshd_session_t unreserved_port_t:tcp_socket name_connect;
allow sshd_session_t ssh_port_t:tcp_socket name_connect;
EOF
}

# checkmodule comes from checkpolicy, semodule_package from policycoreutils.
# audit2allow is deliberately not used, so policycoreutils-devel is not needed.
install_build_deps() {
    local MISSING=()
    command_exists checkmodule || MISSING+=(checkpolicy)
    command_exists semodule_package || MISSING+=(policycoreutils)

    if [[ ${#MISSING[@]} -eq 0 ]]; then
        log_success "Build tools already installed (checkmodule, semodule_package)"
        return 0
    fi

    log_info "Installing ${MISSING[*]}..."
    if ! sudo dnf install -y "${MISSING[@]}"; then
        log_error "Failed to install ${MISSING[*]}"
        return 1
    fi
    log_success "${MISSING[*]} installed"
}

# SELinux has to be enabled for any of this to mean anything
check_selinux() {
    if ! command_exists getenforce; then
        log_error "getenforce not found — this box does not have SELinux, nothing to fix"
        return 1
    fi

    local MODE
    MODE="$(getenforce)"
    case "$MODE" in
        Enforcing)
            log_success "SELinux is Enforcing"
            ;;
        Permissive)
            log_warning "SELinux is Permissive — denials are logged but not enforced"
            log_info "Installing anyway, so the module is in place when it goes back to Enforcing"
            ;;
        Disabled)
            log_error "SELinux is Disabled — it cannot be what blocks your forwarding"
            return 1
            ;;
    esac
}

show_status() {
    if module_installed; then
        log_success "$MODULE_NAME is installed"
    else
        log_warning "$MODULE_NAME is not installed"
    fi

    command_exists getenforce && log_info "SELinux: $(getenforce)"

    log_info "Recent sshd-session denials (empty is what you want):"
    if command_exists ausearch; then
        sudo ausearch -m avc -ts today -c sshd-session 2>/dev/null |
            grep -c "denied" |
            xargs -I{} log_info "    {} denial(s) logged today"
    else
        log_warning "    ausearch not installed (package: audit)"
    fi
}

remove_module() {
    if ! module_installed; then
        log_success "$MODULE_NAME is not installed, nothing to remove"
        return 0
    fi

    log_info "Removing $MODULE_NAME..."
    if ! sudo semodule -r "$MODULE_NAME"; then
        log_error "Failed to remove $MODULE_NAME"
        return 1
    fi
    log_success "$MODULE_NAME removed"
}

install_module() {
    check_selinux || return 1

    if module_installed; then
        log_success "$MODULE_NAME already installed"
        log_info "Re-check with: sudo ausearch -m avc -ts recent -c sshd-session"
        return 0
    fi

    install_build_deps || return 1

    TMP_DIR="$(mktemp -d)"
    trap cleanup_tmp_dir EXIT

    write_policy_source

    log_info "Compiling the policy module..."
    # sshd_session_t only exists once the policy knows the split daemon; saying
    # so beats letting checkmodule's "unknown type" scroll past.
    if ! checkmodule -M -m -o "$TMP_DIR/$MODULE_NAME.mod" "$TMP_DIR/$MODULE_NAME.te"; then
        log_error "checkmodule failed"
        log_info "If it says sshd_session_t is unknown, this policy predates the sshd/sshd-session split"
        log_info "and your forwarding problem is something else — check: sudo ausearch -m avc -ts recent"
        return 1
    fi

    if ! semodule_package -o "$TMP_DIR/$MODULE_NAME.pp" -m "$TMP_DIR/$MODULE_NAME.mod"; then
        log_error "semodule_package failed"
        return 1
    fi

    # sudo belongs on this command too: in a "sudo cmd | tool" pipeline only the
    # first half is privileged, and semodule fails as a normal user with the
    # opaque "could not establish direct connection".
    log_info "Installing $MODULE_NAME..."
    if ! sudo semodule -i "$TMP_DIR/$MODULE_NAME.pp"; then
        log_error "semodule -i failed"
        log_info "If it complains about the module store, check your SELinux role: sudo id -Z"
        return 1
    fi

    if ! module_installed; then
        log_error "semodule reported success but $MODULE_NAME is not in semodule -l"
        return 1
    fi

    log_success "$MODULE_NAME installed"
    log_info "sshd needs no restart — the policy applies to new connections immediately"
    log_info "In VS Code: 'Remote-SSH: Kill VS Code Server on Host...', then reconnect"
}

main() {
    local ACTION="install"
    local opt

    while getopts ":rsh" opt; do
        case "$opt" in
            r) ACTION="remove" ;;
            s) ACTION="status" ;;
            h) usage; exit 0 ;;
            \?) log_error "Unknown option: -$OPTARG"; echo ""; usage; exit 1 ;;
        esac
    done

    case "$ACTION" in
        install) install_module ;;
        remove)  remove_module ;;
        status)  show_status ;;
    esac
}

# Run main when executed directly or piped into a shell, but not when sourced.
# Piped, BASH_SOURCE[0] is empty and $0 is the shell's name, so the plain
# equality test used elsewhere in this repo would silently do nothing.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
