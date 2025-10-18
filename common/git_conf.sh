#!/bin/bash

# Common Git Configuration Script
# This script configures Git with useful aliases and settings
# Can be sourced from any bootstrap script

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

    echo -e "${GREEN}[SUCCESS]${NC} Git configured with useful aliases"
}
