# Init SK
source <(sk --shell zsh)

# Fuzzy file finder with preview using bat
export SKIM_DEFAULT_COMMAND="git ls-tree -r --name-only HEAD || rg --files"
alias skf='sk --preview "bat --color=always --style=numbers {}" --preview-window=right:60%'

# Jump to a directory from the zoxide database, picked with skim
# Usage: cdd [keywords...]   - keywords narrow the list before the picker opens
cdd() {
    if ! command -v zoxide >/dev/null; then
        echo "cdd: zoxide is not installed" >&2
        return 1
    fi

    local dir
    dir=$(
        zoxide query -l "$@" | sk \
            --preview 'eza -la --color=always {} 2>/dev/null || ls -la {}' \
            --preview-window=right:60%
    )

    # z instead of cd, so the jump is recorded in the zoxide database
    [ -n "$dir" ] && z "$dir"
}

gco() {
  local branch
  branch=$(
    git branch --format='%(refname:short)' | sk \
      --preview 'git log --oneline --color=always -10 {}' \
      --preview-window=right:60%
  )
  [ -n "$branch" ] && git switch "$branch"
}

# Interactive ripgrep search with file preview
# Usage: skrg [rg options] [path]
# Examples:
#   skrg                      - search in current directory
#   skrg src/                 - search only in src/
#   skrg --type js            - search only in JS files
#   skrg --glob "*.ts" src/   - search in TS files in src/
skrg() {
    local search_path="${*:-.}"
    sk --ansi -i -c "rg --color=always --line-number --fixed-strings --glob '!node_modules' {q} \"$search_path\"" \
        --delimiter : \
        --preview 'bat --color=always --style=numbers {1} --highlight-line {2}' \
        --preview-window=right:60%
}