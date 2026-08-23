# Безпечна робота з файлами (за запитом підтвердження)
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# eza (better ls) — guarded, ls and tree shadow real commands
if command -v eza >/dev/null; then
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
fi

# zoxide (better cd) — z jumps by frequency, zi is the interactive picker
if command -v zoxide >/dev/null; then
    alias cd='z'
    alias cdi='zi'
fi

# Швидкий підйом по директоріях
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias zz="source ~/.zshrc"

# VPN aliases
if command -v tailscale >/dev/null; then
    alias vpnu='sudo tailscale up --accept-routes'
    alias vpnd='sudo tailscale down'
    alias vpns='sudo tailscale status'
fi
