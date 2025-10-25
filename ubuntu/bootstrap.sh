#!/bin/bash

# Ubuntu/Pop!_OS Bootstrap Script
# This script installs essential development tools and packages
# Supports Ubuntu 24.04+ and Pop!_OS 24.04+

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$HOME/dev/dotenv/ubuntu"
DOTENV_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common Git configuration
source "$DOTENV_ROOT/common/utils.sh"
source "$DOTENV_ROOT/common/git_conf.sh"
source "$DOTENV_ROOT/common/logger.sh"
# Source all modules
source "$SCRIPT_DIR/modules/utils.sh"
source "$SCRIPT_DIR/modules/env_setup.sh"
source "$SCRIPT_DIR/modules/packages.sh"
source "$SCRIPT_DIR/modules/shell.sh"
source "$SCRIPT_DIR/modules/dev_tools.sh"
source "$SCRIPT_DIR/modules/cli_tools.sh"
source "$SCRIPT_DIR/modules/applications.sh"


# Show help message
show_help() {
    echo "Ubuntu/Pop!_OS Bootstrap Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --all, -a                      Run all installation functions (default)"
    echo "  -i, --install FUNCTION         Run specific function(s)"
    echo "  -v, --versions                 Show installed versions only"
    echo "  --help, -h                     Show this help message"
    echo ""
    echo "Group Functions:"
    echo "  upd                            Update system packages"
    echo "  shell                          Setup shell environment (zsh, starship, dotenv, symlink)"
    echo "  vcs                            Setup version control (git, gpg, gh)"
    echo "  mise                           Setup mise version manager"
    echo "  devtools                       Setup development tools (rust, node, bun, pnpm, jdk, ruby)"
    echo "  cli                            Setup CLI tools (bat, eza, zoxide, rip2, dust)"
    echo "  apps                           Setup applications (warp, vicinae, tailscale, slack, timeshift, docker)"
    echo "  essential                      Install essential packages"
    echo ""
    echo "Available Functions:"
    echo "  install_user_bin                Create ~/.bin and add to PATH in .zshrc"
    echo "  create_zshrc                   Create .zshrc file if it doesn't exist"
    echo "  configure_dotenv_sourcing      Configure dotenv sourcing in ~/.zshrc"
    echo "  configure_git                  Configure Git with useful aliases and settings"
    echo "  essential                      Install essential development packages"
    echo "  git                            Install Git version control"
    echo "  gpg                            Install GPG (GNU Privacy Guard)"
    echo "  gh                             Install GitHub CLI (gh)"
    echo "  zsh                            Install Zsh shell and set as default"
    echo "  rust                           Install Rust and Cargo"
    echo "  starship                       Install Starship prompt"
    echo "  mise                           Install mise CLI version manager"
    echo "  bat                            Install bat (better cat)"
    echo "  eza                            Install eza (better ls)"
    echo "  zoxide                         Install zoxide (better cd)"
    echo "  rip2                           Install rip2 (better rm)"
    echo "  dust                           Install dust (better du)"
    echo "  nodejs                         Install Node.js using mise"
    echo "  bun                            Install Bun using mise"
    echo "  pnpm                           Install pnpm package manager"
    echo "  jdk                            Install Eclipse Temurin JDK 21"
    echo "  ruby                           Install Ruby using mise"
    echo "  warp                           Install Warp Terminal"
    echo "  vicinae                        Install Vicinae (Raycast for Linux)"
    echo "  tailscale                      Install Tailscale VPN"
    echo "  slack                          Install Slack"
    echo "  timeshift                      Install Timeshift (system backup tool)"
    echo "  docker                         Install Docker Engine"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Run all functions"
    echo "  $0 --all                              # Run all functions"
    echo "  $0 -a                                 # Run all functions"
    echo "  $0 -v                                 # Show installed versions only"
    echo "  $0 -i upd                             # Update system only"
    echo "  $0 -i shell                           # Setup shell environment"
    echo "  $0 -i vcs                             # Setup version control"
    echo "  $0 -i devtools                        # Setup all dev tools"
    echo "  $0 -i shell -i vcs -i devtools        # Setup shell, vcs, and devtools"
    echo "  $0 -i configure_dotenv_sourcing       # Only configure dotenv sourcing"
    echo "  $0 -i git                             # Install Git only"
    echo "  $0 -i git -i zsh                      # Install Git and Zsh"
    echo "  $0 --install configure_dotenv_sourcing git  # Multiple functions"
}

# Show installed versions
show_versions() {
    log_info "Installed versions:"
    echo "Git: $(git --version 2>/dev/null || echo 'Not available')"
    echo "GPG: $(gpg --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "GitHub CLI: $(gh --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "Zsh: $(zsh --version 2>/dev/null || echo 'Not available')"
    echo "Rust: $(rustc --version 2>/dev/null || echo 'Not available')"
    echo "Cargo: $(cargo --version 2>/dev/null || echo 'Not available')"
    echo "Starship: $(starship --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "mise: $(mise --version 2>/dev/null || echo 'Not available')"
    echo "bat: $(bat --version 2>/dev/null || echo 'Not available')"
    echo "eza: $(eza --version 2>/dev/null | head -n2 || echo 'Not available')"
    echo "zoxide: $(zoxide --version 2>/dev/null || echo 'Not available')"
    echo "rip2: $(rip --version 2>/dev/null || echo 'Not available')"
    echo "dust: $(dust --version 2>/dev/null || echo 'Not available')"
    echo "Node.js: $(node --version 2>/dev/null || echo 'Not available')"
    echo "Bun: $(bun --version 2>/dev/null || echo 'Not available')"
    echo "pnpm: $(pnpm --version 2>/dev/null || echo 'Not available')"
    echo "Java: $(java --version 2>/dev/null | head -n1 || echo 'Not available')"
    echo "Ruby: $(ruby --version 2>/dev/null || echo 'Not available')"
    echo "Warp: $(warp-terminal --version 2>/dev/null || echo 'Not available')"
    echo "Vicinae: $(vicinae --version 2>/dev/null || echo 'Not available')"
    echo "Tailscale: $(tailscale version 2>/dev/null || echo 'Not available')"
    echo "Slack: $(slack --version 2>/dev/null || echo 'Not available')"
    echo "Timeshift: $(timeshift --version 2>/dev/null || echo 'Not available')"
    echo "Docker: $(docker --version 2>/dev/null || echo 'Not available')"
}

# Group function: Update system
group_upd() {
    log_info "Updating system..."
    echo "=================================="
    update_system
    echo "=================================="
    log_success "System update completed!"
}

# Group function: Setup shell environment
group_shell() {
    log_info "Setting up shell environment..."
    echo "=================================="
    create_zshrc
    install_user_bin
    configure_dotenv_sourcing
    install_zsh
    install_starship

    # Create symlink to bootstrap script in ~/.bin
    log_info "Creating symlink to bootstrap script in ~/.bin..."
    mkdir -p "$HOME/.bin"
    ln -sf "$SCRIPT_DIR/bootstrap.sh" "$HOME/.bin/dotenv-bootstrap"
    log_success "Symlink created: ~/.bin/dotenv-bootstrap -> $SCRIPT_DIR/bootstrap.sh"
    log_info "You can now run 'dotenv-bootstrap' from anywhere"

    echo "=================================="
    log_success "Shell environment setup completed!"
}

# Group function: Setup version control
group_vcs() {
    log_info "Setting up version control tools..."
    echo "=================================="
    install_git
    install_gpg
    install_github_cli
    configure_git
    echo "=================================="
    log_success "Version control setup completed!"
}

# Group function: Setup mise only
group_mise() {
    log_info "Setting up mise..."
    echo "=================================="
    install_mise
    echo "=================================="
    log_success "mise setup completed!"
}

# Group function: Setup development tools
group_devtools() {
    log_info "Setting up development tools..."
    echo "=================================="
    install_rust
    install_mise
    install_nodejs
    install_bun
    install_pnpm
    install_jdk
    install_ruby
    echo "=================================="
    log_success "Development tools setup completed!"
}

# Group function: Setup CLI tools
group_cli() {
    log_info "Setting up CLI tools..."
    echo "=================================="
    install_bat
    install_eza
    install_zoxide
    install_rip2
    install_dust
    echo "=================================="
    log_success "CLI tools setup completed!"
}

# Group function: Setup applications
group_apps() {
    log_info "Setting up applications..."
    echo "=================================="
    install_warp
    install_vicinae
    install_tailscale
    install_slack
    install_timeshift
    install_docker
    echo "=================================="
    log_success "Applications setup completed!"
}

# Group function: Install essential packages
group_essential() {
    log_info "Installing essential packages..."
    echo "=================================="
    install_essential_packages
    echo "=================================="
    log_success "Essential packages installed!"
}

# Run all installation functions
run_all() {
    log_info "Starting Bootstrap Process..."
    echo "=================================="

    check_ubuntu
    update_system
    create_zshrc
    install_user_bin
    configure_dotenv_sourcing

    # Create symlink to bootstrap script
    mkdir -p "$HOME/.bin"
    ln -sf "$SCRIPT_DIR/bootstrap.sh" "$HOME/.bin/dotenv-bootstrap"
    log_success "Symlink created: ~/.bin/dotenv-bootstrap"

    install_essential_packages
    install_git
    install_gpg
    install_github_cli
    configure_git
    install_zsh
    install_rust
    install_starship
    install_mise
    install_bat
    install_eza
    install_zoxide
    install_rip2
    install_dust
    install_nodejs
    install_bun
    install_pnpm
    install_jdk
    install_ruby
    install_warp
    install_vicinae
    install_tailscale
    install_slack
    install_timeshift
    install_docker

    echo "=================================="
    log_success "Bootstrap completed successfully!"
    log_info "Please restart your terminal or run 'source ~/.zshrc' to apply all changes"

    echo ""
    show_versions
}

# Main function with argument parsing
main() {
    # If no arguments provided, show recommended installation order
    if [[ $# -eq 0 ]]; then
        echo "Ubuntu/Pop!_OS Bootstrap Script"
        echo ""
        log_info "No arguments provided. Here's the recommended installation order:"
        echo ""
        echo "Recommended setup sequence:"
        echo "  1. $0 -i upd           # Update system packages"
        echo "  2. $0 -i essential     # Install essential development packages"
        echo "  3. $0 -i shell         # Setup shell environment (zsh, starship, dotenv)"
        echo "     ${YELLOW}Note: You'll need to log out/in after this step${NC}"
        echo ""
        echo "  4. $0 -i vcs           # Setup version control (git, gpg, gh)"
        echo "  5. $0 -i mise          # Setup mise version manager"
        echo "  6. $0 -i devtools      # Setup development tools (rust, node, bun, etc.)"
        echo "  7. $0 -i cli           # Setup CLI tools (bat, eza, zoxide, etc.)"
        echo "  8. $0 -i apps          # Setup applications (warp, docker, etc.)"
        echo ""
        echo "Or run everything at once:"
        echo "  $0 --all               # Run complete installation"
        echo ""
        echo "For more options, run:"
        echo "  $0 --help"
        echo ""
        return
    fi

    local functions_to_run=()
    local run_all_flag=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                return 0
                ;;
            --versions|-v)
                show_versions
                return 0
                ;;
            --all|-a)
                run_all_flag=true
                shift
                ;;
            -i|--install)
                shift
                # Collect all function names until next flag or end of arguments
                while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                    # Validate function name and map short names to actual function names
                    case $1 in
                        # Group functions
                        upd)
                            functions_to_run+=(group_upd)
                            ;;
                        shell)
                            functions_to_run+=(group_shell)
                            ;;
                        vcs)
                            functions_to_run+=(group_vcs)
                            ;;
                        mise)
                            functions_to_run+=(group_mise)
                            ;;
                        devtools)
                            functions_to_run+=(group_devtools)
                            ;;
                        cli)
                            functions_to_run+=(group_cli)
                            ;;
                        apps)
                            functions_to_run+=(group_apps)
                            ;;
                        essential)
                            functions_to_run+=(group_essential)
                            ;;
                        # Individual functions
                        install_user_bin)
                            functions_to_run+=(install_user_bin)
                            ;;
                        create_zshrc|configure_dotenv_sourcing|configure_git)
                            functions_to_run+=("$1")
                            ;;
                        git)
                            functions_to_run+=(install_git)
                            ;;
                        gpg)
                            functions_to_run+=(install_gpg)
                            ;;
                        gh)
                            functions_to_run+=(install_github_cli)
                            ;;
                        zsh)
                            functions_to_run+=(install_zsh)
                            ;;
                        rust)
                            functions_to_run+=(install_rust)
                            ;;
                        starship)
                            functions_to_run+=(install_starship)
                            ;;
                        bat)
                            functions_to_run+=(install_bat)
                            ;;
                        eza)
                            functions_to_run+=(install_eza)
                            ;;
                        zoxide)
                            functions_to_run+=(install_zoxide)
                            ;;
                        rip2)
                            functions_to_run+=(install_rip2)
                            ;;
                        dust)
                            functions_to_run+=(install_dust)
                            ;;
                        nodejs)
                            functions_to_run+=(install_nodejs)
                            ;;
                        bun)
                            functions_to_run+=(install_bun)
                            ;;
                        pnpm)
                            functions_to_run+=(install_pnpm)
                            ;;
                        jdk)
                            functions_to_run+=(install_jdk)
                            ;;
                        ruby)
                            functions_to_run+=(install_ruby)
                            ;;
                        warp)
                            functions_to_run+=(install_warp)
                            ;;
                        vicinae)
                            functions_to_run+=(install_vicinae)
                            ;;
                        tailscale)
                            functions_to_run+=(install_tailscale)
                            ;;
                        slack)
                            functions_to_run+=(install_slack)
                            ;;
                        timeshift)
                            functions_to_run+=(install_timeshift)
                            ;;
                        docker)
                            functions_to_run+=(install_docker)
                            ;;
                        *)
                            log_error "Unknown function: $1"
                            log_info "Run '$0 --help' to see available functions"
                            return 1
                            ;;
                    esac
                    shift
                done
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                return 1
                ;;
        esac
    done

    # Run all functions if --all flag is set
    if [[ "$run_all_flag" == true ]]; then
        run_all
        return
    fi

    # Run specific functions
    if [[ ${#functions_to_run[@]} -gt 0 ]]; then
        log_info "Running selected functions..."
        echo "=================================="

        for func in "${functions_to_run[@]}"; do
            $func
        done

        echo "=================================="
        log_success "Selected functions completed successfully!"

        echo ""
        show_versions
    else
        log_error "No valid functions specified"
        show_help
        return 1
    fi
}

# Run the main function
main "$@"
