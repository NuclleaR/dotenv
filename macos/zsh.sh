#!/bin/zsh

# eza (better ls) aliases
# Replace ls with eza for better file listing with colors, icons, and git status

# Basic ls replacements
alias ls='eza --color=always --group-directories-first'
alias ll='eza -lah --color=always --group-directories-first --icons'
alias l='eza -F --color=always --group-directories-first --icons'

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

# Quick navigation aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

alias myip="ifconfig | grep \"inet \" | grep -Fv 127.0.0.1 | awk '{print \$2}'"
alias zz="source ~/.zshrc"