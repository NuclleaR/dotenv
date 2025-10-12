eval "$(starship init zsh)"

# fpath=(~/.zsh/compl $fpath)
autoload -Uz compinit
# compinit -u
compinit
zstyle ':completion:*' menu select

eval "$(zoxide init zsh)"

source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/zsh-git-plugin/zsh-git-plugin.zsh
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# source ~/.zsh/zsh-better-npm-completion/zsh-better-npm-completion.plugin.zsh
# source ~/.zsh/zsh-history-substring-search/zsh-history-substring-search.zsh

alias ll='exa -al'
alias l='exa -l'
alias rf='rm -rf'
alias myip="ifconfig | grep \"inet \" | grep -Fv 127.0.0.1 | awk '{print \$2}'"
alias ..="cd .."
alias ...="cd ..."
alias ....="cd ...."
alias zz="source ~/.zshrc"

alias cd='z'

export PATH="/usr/local/sbin:/Users/nuclear/Library/Android/sdk/platform-tools:/Users/nuclear/Library/Android/sdk/cmdline-tools/bin:$HOME/.pub-cache/bin:$PATH"
export ANDROID_SDK_ROOT="/Users/nuclear/Library/Android/sdk"
export ANDROID_HOME="/Users/nuclear/Library/Android/sdk"

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
# export SDKMAN_DIR="/Users/nuclear/.sdkman"
# [[ -s "/Users/nuclear/.sdkman/bin/sdkman-init.sh" ]] && source "/Users/nuclear/.sdkman/bin/sdkman-init.sh"

# pnpm
export PNPM_HOME="/Users/nuclear/Library/pnpm"
export PATH="$PNPM_HOME:$PATH"
# pnpm end###-begin-npm-completion-###

# tabtab source for packages
# uninstall by removing these lines
#[[ -f ~/.config/tabtab/zsh/__tabtab.zsh ]] && . ~/.config/tabtab/zsh/__tabtab.zsh || true

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/nuclear/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/nuclear/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/nuclear/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/nuclear/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

# Kubectl autocomplete
source <(kubectl completion zsh)
# bun completions
[ -s "/Users/nuclear/.bun/_bun" ] && source "/Users/nuclear/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
