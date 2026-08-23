# apps = [
#   rust
#   eza,
#   zoxide,
#   podman,
#   bat,
#   dust,
#   rip2,
#   sk,
#   git-delta
# ]

install_zypper() {
    local appname="${1}"
    log_info "Installing ${appname}..."

    if command_exists "$appname"; then
        log_success "${appname} already installed"
        log_info "${appname} version: $($appname --version)"
        return
    fi

    sudo zypper --non-interactive install "$appname"
    log_success "${appname} installed successfully"
}
