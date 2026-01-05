#!/bin/bash

# Common Git Configuration Script
# This script configures Git with useful aliases and settings
# Can be sourced from any bootstrap script

setup_git() {
    echo -e "${BLUE}[INFO]${NC} Setting up Git configuration..."

    # Get the script directory and dotenv root
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local DOTENV_ROOT="$(dirname "$SCRIPT_DIR")"

    # Create symlink for global gitignore
    local GITIGNORE_SOURCE="$DOTENV_ROOT/git/gitignore_global"
    local GITIGNORE_TARGET="$HOME/.gitignore_global"

    if [[ -f "$GITIGNORE_SOURCE" ]]; then
        if [[ -L "$GITIGNORE_TARGET" ]]; then
            echo -e "${BLUE}[INFO]${NC} Global gitignore symlink already exists"
        elif [[ -f "$GITIGNORE_TARGET" ]]; then
            echo -e "${YELLOW}[WARNING]${NC} $GITIGNORE_TARGET already exists (not a symlink), backing up..."
            mv "$GITIGNORE_TARGET" "$GITIGNORE_TARGET.backup"
            ln -sf "$GITIGNORE_SOURCE" "$GITIGNORE_TARGET"
            echo -e "${GREEN}[SUCCESS]${NC} Created global gitignore symlink"
        else
            ln -sf "$GITIGNORE_SOURCE" "$GITIGNORE_TARGET"
            echo -e "${GREEN}[SUCCESS]${NC} Created global gitignore symlink"
        fi

        # Configure git to use global gitignore
        git config --global core.excludesfile "$GITIGNORE_TARGET"
    else
        echo -e "${YELLOW}[WARNING]${NC} Global gitignore file not found at $GITIGNORE_SOURCE"
    fi

    # Run git configuration
    configure_git

    echo -e "${GREEN}[SUCCESS]${NC} Git setup completed"
}

configure_git() {
    echo -e "${BLUE}[INFO]${NC} Configuring Git..."

    # Set up some useful Git aliases and configurations
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    git config --global core.autocrlf input
    git config --global core.editor nano

    # Useful aliases
    git config --global alias.co checkout
    git config --global alias.br branch
    git config --global alias.ci 'commit -a'
    git config --global alias.cia 'commit -a --amend'
    git config --global alias.st status
    git config --global alias.unstage 'reset HEAD --'
    git config --global alias.last 'log -1 HEAD'
    git config --global alias.rf '!f() { git checkout HEAD -- "$@"; }; f'
    git config --global alias.sync '!f() { echo "Fetching latest changes..." && git fetch --all && echo "Attempting to merge with main/master..." && (git merge --no-ff origin/main || git merge --no-ff origin/master || echo "Merge conflicts detected. Please resolve manually"); }; f'
    git config --global alias.rm '!f() { git fetch --all && (git reset --hard origin/main || git reset --hard origin/master); }; f'
    git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"

    # Diff settings
    git config --global core.pager delta
    git config --global interactive.diffFilter "delta --color-only"
    git config --global merge.conflictStyle zdiff3

    # Delta setup
    git config --global delta.navigate true
    # git config --global delta.syntax-theme Dracula
    git config --global delta.dark true
    git config --global delta.side-by-side true
    git config --global delta.line-numbers true
    git config --global delta.hyperlinks true

    echo -e "${GREEN}[SUCCESS]${NC} Git configured with useful aliases"
}
