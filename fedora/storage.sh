#!/bin/bash

# Projects volume for Fedora
#
# Carves a logical volume out of the free space in the volume group, puts XFS on
# it and mounts it at ~/projects, with the package manager stores inside it.
#
#   curl -fsSL https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/storage.sh | bash -s -- -h
#
# By default the volume is VDO backed: block level deduplication plus
# compression. That is worth it because npm *copies* packages into every
# node_modules — twenty worktrees of one repo are twenty physical copies of the
# same 4 GB. pnpm and bun avoid this themselves by hardlinking out of a shared
# store, so if everything you build uses those, pass --no-vdo and skip the write
# overhead entirely.
#
# Nothing here wipes a disk: the volume comes from unallocated space in an
# existing VG, and the script refuses to touch anything that already exists.
#
# The log helpers are inline rather than sourced from common/ because piped into
# a shell there is no script path to resolve a sibling file from. Keep them in
# step with common/logger.sh.

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

VG=""                                   # auto-detected when empty
LV_NAME="${LV_NAME:-projects}"
LV_SIZE="${LV_SIZE:-120G}"              # physical space actually consumed
LV_VSIZE="${LV_VSIZE:-240G}"            # what the filesystem believes it has
MOUNT_POINT="${MOUNT_POINT:-$HOME/projects}"
USE_VDO=true
ASSUME_YES=false

# Whether -s / -V were given explicitly. When they were not, the sizes are asked
# for interactively instead of silently defaulting.
SIZE_GIVEN=false
VSIZE_GIVEN=false

# Free space in the volume group, in whole gigabytes, filled in by resolve_vg
VG_FREE_G=0

# Package manager stores, kept on this volume. pnpm and bun deduplicate by
# hardlinking out of their store, and a hardlink cannot cross a filesystem
# boundary — a store left on / would silently degrade to copying.
STORES=(pnpm bun npm yarn)

usage() {
    cat <<EOF
Projects volume for Fedora

Usage:
  ./fedora/storage.sh [-g VG] [-n NAME] [-s SIZE] [-V VSIZE] [-m MOUNT] [--no-vdo] [-y] [-h]
  curl -fsSL <raw-url>/fedora/storage.sh | bash -s -- -s 120G

  -g VG       volume group (default: the only one present)
  -n NAME     logical volume name (default: $LV_NAME)
  -s SIZE     physical size, the space really taken (default: $LV_SIZE)
  -V VSIZE    virtual size the filesystem sees, VDO only (default: $LV_VSIZE)
  -m MOUNT    mount point (default: \$HOME/projects)
  --no-vdo    plain logical volume, no deduplication or compression
  -y          do not ask for confirmation
  -h          this help

Leave -s and -V off and the script asks for them, showing how much the volume
group actually has free and suggesting a value. Pressing Enter takes the
suggestion. -y skips the questions and uses the defaults above.

VDO is thin provisioned: VSIZE is a bet on the deduplication ratio, and the
volume can only ever store SIZE bytes of *unique* data. The suggested 2x is
deliberately conservative — raise it once vdostats shows what you really get.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -g) VG="$2"; shift 2 ;;
            -n) LV_NAME="$2"; shift 2 ;;
            -s) LV_SIZE="$2"; SIZE_GIVEN=true; shift 2 ;;
            -V) LV_VSIZE="$2"; VSIZE_GIVEN=true; shift 2 ;;
            -m) MOUNT_POINT="$2"; shift 2 ;;
            --no-vdo) USE_VDO=false; shift ;;
            -y) ASSUME_YES=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) log_error "Unknown option: $1"; echo ""; usage; exit 1 ;;
        esac
    done
}

# Everything that has to be true before we create anything
check_prerequisites() {
    if ! command_exists lvcreate; then
        log_error "lvm2 is not installed — sudo dnf install lvm2"
        return 1
    fi

    if [[ "$USE_VDO" == true ]]; then
        if ! modinfo dm_vdo >/dev/null 2>&1; then
            log_error "The dm_vdo kernel module is not available on $(uname -r)"
            log_info "Run again with --no-vdo for a plain volume"
            return 1
        fi

        if ! command_exists vdoformat; then
            log_info "Installing the vdo userspace tools..."
            if ! sudo dnf install -y vdo; then
                log_error "Failed to install the vdo package"
                return 1
            fi
        fi
        log_success "VDO available (dm_vdo in $(uname -r))"
    fi
}

# Find the volume group, and make sure it has room for what was asked
resolve_vg() {
    if [[ -z "$VG" ]]; then
        local VGS
        mapfile -t VGS < <(sudo vgs --noheadings -o vg_name 2>/dev/null | awk '{print $1}')

        if [[ ${#VGS[@]} -eq 0 ]]; then
            log_error "No volume group found — this script expects an LVM setup"
            return 1
        fi

        if [[ ${#VGS[@]} -gt 1 ]]; then
            log_error "More than one volume group: ${VGS[*]}"
            log_info "Pick one with -g <vg>"
            return 1
        fi

        VG="${VGS[0]}"
    fi

    local FREE
    FREE="$(sudo vgs --noheadings --units g -o vg_free "$VG" 2>/dev/null | tr -d ' <g')"
    VG_FREE_G="$(awk -v f="$FREE" 'BEGIN { printf "%d", f }')"

    log_info "Volume group: $VG (${VG_FREE_G}G free)"

    if [[ "$VG_FREE_G" -lt 5 ]]; then
        log_error "Only ${VG_FREE_G}G free in $VG — nothing useful to carve out"
        return 1
    fi
}

# Turn 120G / 500M / 1T into whole gigabytes. Empty when it is not a size.
to_gib() {
    local RAW="${1^^}"
    local NUM="${RAW%[GMT]}"

    [[ "$NUM" =~ ^[0-9]+$ ]] || { echo ""; return 0; }

    case "$RAW" in
        *T) echo $(( NUM * 1024 )) ;;
        *M) echo $(( NUM / 1024 )) ;;
        *)  echo "$NUM" ;;
    esac
}

# Ask once, re-ask until the answer is a size within bounds. Everything the user
# reads goes to stderr, so only the accepted value lands on stdout.
prompt_size() {
    local LABEL="$1" DEFAULT="$2" MIN="$3" MAX="$4"
    local ANSWER GIB

    while true; do
        read -rp "  $LABEL [$DEFAULT]: " ANSWER < /dev/tty
        ANSWER="${ANSWER:-$DEFAULT}"
        GIB="$(to_gib "$ANSWER")"

        if [[ -z "$GIB" ]] || (( GIB < 1 )); then
            log_error "Not a size: '$ANSWER' — try 120G, 500G or 1T" >&2
            continue
        fi

        if [[ -n "$MIN" ]] && (( GIB < MIN )); then
            log_error "Too small: at least ${MIN}G" >&2
            continue
        fi

        if [[ -n "$MAX" ]] && (( GIB > MAX )); then
            log_error "Too big: ${MAX}G is the most available" >&2
            continue
        fi

        echo "${GIB}G"
        return 0
    done
}

# Suggest sizes from what is actually free, then let the answer override them
ask_sizes() {
    # Anything pinned on the command line is not asked about again
    if [[ "$SIZE_GIVEN" == true && ( "$VSIZE_GIVEN" == true || "$USE_VDO" == false ) ]]; then
        return 0
    fi

    if [[ "$ASSUME_YES" == true ]] || ! { : < /dev/tty; } 2>/dev/null; then
        log_info "Not interactive — using ${LV_SIZE} physical$( [[ "$USE_VDO" == true ]] && echo ", ${LV_VSIZE} virtual" )"
        return 0
    fi

    # Leave roughly a third of the group unallocated: / lives in the same VG and
    # XFS grows online but never shrinks, so over-taking now is hard to undo.
    local SUGGEST=$(( VG_FREE_G * 7 / 10 / 10 * 10 ))
    (( SUGGEST < 5 )) && SUGGEST=$VG_FREE_G

    echo ""
    log_info "$VG has ${VG_FREE_G}G unallocated."

    if [[ "$SIZE_GIVEN" != true ]]; then
        echo ""
        log_info "Physical size — the space actually taken from the group."
        log_info "Suggested ${SUGGEST}G, which leaves $(( VG_FREE_G - SUGGEST ))G for / to grow into."
        LV_SIZE="$(prompt_size "Physical size" "${SUGGEST}G" 1 "$VG_FREE_G")"
    fi

    if [[ "$USE_VDO" == true && "$VSIZE_GIVEN" != true ]]; then
        local PHYS_G
        PHYS_G="$(to_gib "$LV_SIZE")"

        echo ""
        log_info "Virtual size — what the filesystem will believe it has."
        log_info "VDO still only stores ${PHYS_G}G of *unique* data; this is a bet on the"
        log_info "deduplication ratio. Suggested $(( PHYS_G * 2 ))G (2x), which is conservative."
        log_info "Raise it later once vdostats shows the ratio you really get."
        LV_VSIZE="$(prompt_size "Virtual size" "$(( PHYS_G * 2 ))G" "$PHYS_G" "")"
    fi
}

# Say exactly what is about to happen, and wait to be told to go ahead
confirm() {
    echo ""
    log_info "About to create:"
    if [[ "$USE_VDO" == true ]]; then
        log_info "    $VG/$LV_NAME   VDO, ${LV_SIZE} physical, ${LV_VSIZE} virtual"
        log_info "                   deduplication on, compression on"
    else
        log_info "    $VG/$LV_NAME   plain logical volume, ${LV_SIZE}"
    fi
    log_info "    XFS on it, mounted at $MOUNT_POINT via /etc/fstab"
    log_info "    stores under $MOUNT_POINT/.stores: ${STORES[*]}"
    echo ""
    log_info "This takes unallocated space from $VG. No existing data is touched."
    echo ""

    if [[ "$ASSUME_YES" == true ]]; then
        return 0
    fi

    # stdin is the curl pipe, so ask the terminal directly. Test that it can be
    # opened, not that the device node exists: with no controlling terminal the
    # node is still there and the redirect fails with a raw shell error.
    if ! { : < /dev/tty; } 2>/dev/null; then
        log_error "No terminal to confirm on — re-run with -y if this is what you want"
        return 1
    fi

    local answer
    read -rp "Proceed? [y/N] " answer < /dev/tty
    [[ "$answer" == [yY] ]] || { log_warning "Aborted"; return 1; }
}

create_volume() {
    if sudo lvs "$VG/$LV_NAME" >/dev/null 2>&1; then
        log_success "$VG/$LV_NAME already exists, keeping it"
        return 0
    fi

    if [[ "$USE_VDO" == true ]]; then
        log_info "Creating VDO volume $VG/$LV_NAME (${LV_SIZE} physical, ${LV_VSIZE} virtual)..."
        if ! sudo lvcreate --type vdo \
            --name "$LV_NAME" \
            --size "$LV_SIZE" \
            --virtualsize "$LV_VSIZE" \
            --compression y \
            --deduplication y \
            --yes "$VG"; then
            log_error "lvcreate failed"
            return 1
        fi
    else
        log_info "Creating plain volume $VG/$LV_NAME (${LV_SIZE})..."
        if ! sudo lvcreate --name "$LV_NAME" --size "$LV_SIZE" --yes "$VG"; then
            log_error "lvcreate failed"
            return 1
        fi
    fi

    log_success "$VG/$LV_NAME created"
}

# XFS with -K: never discard the whole device at mkfs time. On VDO that would
# walk the entire virtual size for nothing, and it is slow on any thin volume.
make_filesystem() {
    local DEV="/dev/$VG/$LV_NAME"

    if sudo blkid -o value -s TYPE "$DEV" 2>/dev/null | grep -q .; then
        log_success "$DEV already has a filesystem, not touching it"
        return 0
    fi

    log_info "Creating XFS on $DEV..."
    if ! sudo mkfs.xfs -K "$DEV"; then
        log_error "mkfs.xfs failed"
        return 1
    fi

    log_success "XFS created on $DEV"
}

# Mount by UUID, with nofail so a missing volume can never block boot
mount_volume() {
    local DEV="/dev/$VG/$LV_NAME"
    local UUID
    UUID="$(sudo blkid -o value -s UUID "$DEV")"

    if [[ -z "$UUID" ]]; then
        log_error "Could not read the UUID of $DEV"
        return 1
    fi

    sudo mkdir -p "$MOUNT_POINT"

    if grep -qF "$UUID" /etc/fstab; then
        log_success "fstab already has an entry for $UUID"
    else
        local BACKUP="/etc/fstab.backup.$(date +%Y%m%d-%H%M%S)"
        sudo cp /etc/fstab "$BACKUP"
        log_warning "fstab backed up to $BACKUP"

        log_info "Adding the fstab entry..."
        printf 'UUID=%s %s xfs defaults,nofail,x-systemd.device-timeout=10 0 2\n' \
            "$UUID" "$MOUNT_POINT" | sudo tee -a /etc/fstab >/dev/null
        sudo systemctl daemon-reload
    fi

    if mountpoint -q "$MOUNT_POINT"; then
        log_success "$MOUNT_POINT already mounted"
    else
        log_info "Mounting $MOUNT_POINT..."
        if ! sudo mount "$MOUNT_POINT"; then
            log_error "mount failed — check /etc/fstab"
            return 1
        fi
        log_success "$MOUNT_POINT mounted"
    fi

    sudo chown "$(id -u):$(id -g)" "$MOUNT_POINT"
}

# The stores have to sit on this volume, not on /, or pnpm and bun lose their
# hardlinks and quietly start copying instead
create_stores() {
    local STORE_DIR="$MOUNT_POINT/.stores"
    local S

    mkdir -p "$STORE_DIR"
    for S in "${STORES[@]}"; do
        mkdir -p "$STORE_DIR/$S"
    done

    log_success "Stores ready under $STORE_DIR"

    if command_exists pnpm; then
        pnpm config set store-dir "$STORE_DIR/pnpm" >/dev/null 2>&1 &&
            log_success "pnpm store-dir pointed at $STORE_DIR/pnpm"
    else
        log_info "When pnpm is installed, point it here with:"
        log_info "    pnpm config set store-dir $STORE_DIR/pnpm"
    fi

    log_info "shared/zsh.sh exports the npm, yarn and bun cache variables when this directory exists"
}

# VDO only frees physical space when the filesystem discards blocks, and Fedora
# trims weekly. Deleting and reinstalling node_modules all day would let the
# volume fill with blocks nothing references any more.
tighten_fstrim() {
    [[ "$USE_VDO" == true ]] || return 0

    local DROPIN_DIR="/etc/systemd/system/fstrim.timer.d"
    local DROPIN="$DROPIN_DIR/00-dotenv.conf"

    if [[ -f "$DROPIN" ]] && grep -qF "OnCalendar=daily" "$DROPIN"; then
        log_success "fstrim already runs daily"
        return 0
    fi

    log_info "Making fstrim run daily instead of weekly..."
    sudo mkdir -p "$DROPIN_DIR"
    sudo tee "$DROPIN" >/dev/null <<'EOF'
# Generated by the dotenv setup (fedora/storage.sh)
# VDO reclaims physical space only through discard, and weekly is not often
# enough for a volume that churns node_modules.
[Timer]
OnCalendar=
OnCalendar=daily
EOF

    sudo systemctl daemon-reload
    sudo systemctl restart fstrim.timer 2>/dev/null || true
    log_success "fstrim set to daily"
}

show_status() {
    echo ""
    log_info "Filesystem:"
    df -h "$MOUNT_POINT" | tail -1

    if [[ "$USE_VDO" == true ]] && command_exists vdostats; then
        echo ""
        log_info "VDO (this is the number that matters — 'used' is physical):"
        sudo vdostats --human-readable 2>/dev/null || true
        echo ""
        log_warning "Watch this. When physical use approaches 100% writes start failing,"
        log_warning "and no amount of free space in df will save you. Check it with:"
        log_warning "    sudo vdostats --human-readable"
    fi
}

main() {
    parse_args "$@"

    check_prerequisites
    resolve_vg
    ask_sizes
    confirm

    create_volume
    make_filesystem
    mount_volume
    create_stores
    tighten_fstrim

    echo ""
    log_success "Projects volume ready at $MOUNT_POINT"

    show_status
}

# Run main when executed directly or piped into a shell, but not when sourced.
# Piped, BASH_SOURCE[0] is empty and $0 is the shell's name, so the plain
# equality test used elsewhere in this repo would silently do nothing.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
