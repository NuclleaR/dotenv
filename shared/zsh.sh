#!/bin/zsh

# Common Zsh configuration
# Shared by every machine — source it from ~/.zshrc:
#   source "$HOME/.shell/dotenv/shared/zsh.sh"
# Machine specific bits (SSH agent socket, Wayland clipboard, work stuff)
# stay in the per-machine config next to it.

# Enable Zsh completion system (includes Git)
autoload -Uz compinit
compinit

# Zsh history
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt APPEND_HISTORY        # append on exit
setopt INC_APPEND_HISTORY    # write incrementally
setopt SHARE_HISTORY         # merge across sessions
setopt HIST_IGNORE_SPACE     # ignore commands starting with space
setopt HIST_IGNORE_ALL_DUPS  # drop duplicates
setopt EXTENDED_HISTORY      # timestamps

# Word navigation - Alt+Q/W
bindkey '^[q' backward-word
bindkey '^[w' forward-word

# Home / End
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
# Home / End (alternative)
bindkey '^[[1~' beginning-of-line
bindkey '^[[4~' end-of-line

export GITHUB_USERNAME=NuclleaR

export RIP_GRAVEYARD=~/.local/share/Trash

# keychain keeps one ssh-agent per host, shared by every terminal, so on a
# remote box the passphrase is asked by the first session after a boot and by
# none of the ones after it. Interactive shells only — a non-interactive one
# (scp, rsync, cron) must never block on a passphrase prompt.
if [[ -o interactive ]] && command -v keychain >/dev/null; then
    _kc_keys=("$HOME"/.ssh/id_*(N))
    _kc_keys=(${_kc_keys:#*.pub})
    (( $#_kc_keys )) && eval "$(keychain --eval --quiet "${_kc_keys[@]}")"
    unset _kc_keys
fi

# gpg has to know which terminal to ask for the signing passphrase on,
# otherwise signing fails with "Inappropriate ioctl for device".
# Only exported when there really is a terminal — an empty GPG_TTY is worse
# than an unset one, gpg would try to write the prompt to it.
[[ -t 0 ]] && export GPG_TTY="${TTY:-$(tty)}"

# Directory of this file, so the other shared configs can be sourced next to it
SHARED_DIR="${${(%):-%x}:A:h}"

# Cargo / Rust environment (rustup is installed with --no-modify-path,
# so this is what puts cargo on PATH in every shell)
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# Shared aliases
[[ -f "$SHARED_DIR/aliases.sh" ]] && source "$SHARED_DIR/aliases.sh"

# Skim (fuzzy finder) helpers
command -v sk >/dev/null && source "$SHARED_DIR/skim.sh"

# Starship prompt
command -v starship >/dev/null && eval "$(starship init zsh)"

command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# Zsh plugins (installed by the per-distro setup script into ~/.zsh)
[[ -f "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] &&
    source "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"

# zsh-syntax-highlighting must stay last — it hooks into ZLE and has to
# register after every other widget and plugin has loaded
[[ -f "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] &&
    source "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
