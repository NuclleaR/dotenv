#!/bin/zsh

autoload -Uz compinit && compinit

# Setup history
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000
setopt appendhistory

# eza (better ls) aliases
# Replace ls with eza for better file listing with colors, icons, and git status

# Basic ls replacements
alias ls='eza --color=always --group-directories-first'
alias ll='eza -lah --color=always --group-directories-first'
alias l='eza -F --color=always --group-directories-first'

# Advanced eza aliases
alias lt='eza --tree --level=2 --color=always --group-directories-first --icons'
alias ltl='eza -l --tree --level=2 --color=always --group-directories-first --icons'
alias lta='eza -la --tree --level=2 --color=always --group-directories-first --icons'

# Show only directories
alias lsd='eza -D --color=always --group-directories-first --icons'

# Show file sizes in human readable format
alias lh='eza -lh --color=always --group-directories-first --icons'

# Show files sorted by modification time (newest first)
alias ltm='eza -lt modified --color=always --group-directories-first --icons'
alias ltr='eza -ltr modified --color=always --group-directories-first --icons'

# Show files sorted by size (largest first)
alias lS='eza -lS --color=always --group-directories-first --icons'

# Show git status in file listing (if in a git repo)
alias lg='eza -l --git --color=always --group-directories-first --icons'
alias lga='eza -la --git --color=always --group-directories-first --icons'

# Show extended attributes and permissions
alias lx='eza -l --extended --color=always --group-directories-first --icons'

# Tree view with git status
alias tree='eza --tree --color=always --group-directories-first --icons'
alias treeg='eza --tree --git --color=always --group-directories-first --icons'

# zoxide (better cd) aliases
# Replace cd with z for smart directory jumping based on frequency and recency
alias cd='z'
alias cdi='zi'  # Interactive mode with fzf-like interface

alias trace='sudo traceroute -T'
alias ins='sudo apt install -y'
# alias search='grep -rn --color=auto "magicAuth" ./src --exclude-dir=node_modules | fzf'

# Quick navigation aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

alias myip="ifconfig | grep \"inet \" | grep -Fv 127.0.0.1 | awk '{print \$2}'"
alias zz="source ~/.zshrc"

# Git aliases
# Quick status and staging
alias g='git'
alias gs='git status'
alias ga='git add'
alias gaa='git add .'
alias gap='git add -p'  # Interactive staging

# Committing
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit -a'
alias gcam='git commit -am'
alias gcfix='git commit --fixup'
alias gcsq='git commit --squash'

# Branching and switching
alias gb='git branch'
alias gba='git branch -a'
alias gbd='git branch -d'
alias gbD='git branch -D'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gsw='git switch'
alias gswc='git switch -c'

# Remote operations
alias gf='git fetch'
alias gfa='git fetch --all'
alias gp='git push'
alias gpo='git push origin'
alias gpf='git push --force-with-lease'
alias gl='git pull'
alias glo='git pull origin'

# Reset and restore
alias grs='git reset'
alias grsh='git reset --hard'
alias grss='git reset --soft'
alias grt='git restore'
alias grts='git restore --staged'

# Useful shortcuts
alias gwip='git add -A && git commit -m "WIP: work in progress"'
alias gunwip='git log -n 1 --format="%s" | grep -q "^WIP:" && git reset HEAD~1'
alias gclean='git clean -fd'
alias gtag='git tag'
alias gshow='git show'

alias vpnu='sudo tailscale up --accept-routes'
alias vpnd='sudo tailscale down'
alias vpns='sudo tailscale status'

# Grep
# alias grp='grep -rn --color=auto'
# alias grpi='grep -rin --color=auto'
# alias grpjs='grep -rn --include="*.js" --include="*.jsx" --color=auto'
# alias grpts='grep -rn --include="*.ts" --include="*.tsx" --color=auto'
# alias grpnm='grep -r --exclude-dir=node_modules --exclude-dir=build --exclude-dir=dist --color=auto'

# Skim
# Fuzzy file finder with preview using bat
alias skf='sk --preview "bat --color=always --style=numbers {}" --preview-window=right:60%'

# Interactive ripgrep search with file preview
# Usage: skrg [rg options] [path]
# Examples:
#   skrg                      - search in current directory
#   skrg src/                 - search only in src/
#   skrg --type js            - search only in JS files
#   skrg --glob "*.ts" src/   - search in TS files in src/
skrg() {
    local search_path="${*:-.}"
    sk --ansi -i -c "rg --color=always --line-number --glob '!node_modules' '{}' $search_path" --delimiter : --preview "bat --color=always --style=numbers {1} --highlight-line {2}" --preview-window=right:60%
}

# Alternative: search in all files first, then filter
alias skrga='rg --color=always --line-number . | sk --ansi --delimiter : --preview "bat --color=always --style=numbers {1} --highlight-line {2}" --preview-window=right:60%'


# sudo systemctl stop docker
# sudo systemctl stop docker.socket
# systemctl --user stop docker