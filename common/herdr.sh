#!/bin/bash

# Herdr app module (distribution independent)
# Run it directly (./common/herdr.sh), also after every Herdr update, or source
# it and call setup_herdr_mods / build_herdr_layout

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$COMMON_DIR/logger.sh"
source "$COMMON_DIR/utils.sh"

HERDR_HOME="${HERDR_APP_HOME:-$HOME/.config/herdr-app}"
# Outside mods/ and layouts/: Herdr would load a backup kept there
HERDR_BACKUPS="$HERDR_HOME/backups"
# What Herdr writes into a mod folder by itself
HERDR_GENERATED=(gpui-kit.d.ts herdr.d.ts jsconfig.json)

# Symlink every mod in herdr/mods into the Herdr home. Herdr does not watch through
# these links: a repo edit reaches new copies of a mod, and one already on screen
# only after a layout switch and back. It does not draw SVGs through them either,
# so a mod's icons belong in a patch.
setup_herdr_mods() {
    local source_dir target_dir mod_dir name target
    source_dir="$(cd "$COMMON_DIR/../herdr/mods" && pwd)" || return 1
    target_dir="$HERDR_HOME/mods"

    mkdir -p "$target_dir"

    for mod_dir in "$source_dir"/*/; do
        mod_dir="${mod_dir%/}"
        name="$(basename "$mod_dir")"
        target="$target_dir/$name"

        if [[ -L "$target" && "$(readlink "$target")" == "$mod_dir" ]]; then
            log_success "Herdr mod $name already linked"
            continue
        fi

        if [[ -e "$target" && ! -L "$target" ]]; then
            herdr_backup "$target" "$name"
        fi

        ln -sfn "$mod_dir" "$target"
        log_success "Herdr mod $name linked"
    done

    log_info "Key bindings stay per machine, add to keys.json \"global\":"
    log_info "  \"cmd-shift-e\": \"mod.open:open-in-vscode\""
}

herdr_backup() {
    local path="$1" name="$2"
    mkdir -p "$HERDR_BACKUPS"
    mv "$path" "$HERDR_BACKUPS/$name.backup.$(date +%Y%m%d%H%M%S)"
    log_warning "Moved previous $name to $HERDR_BACKUPS"
}

# Shipped tabs mod + the VS Code button, the same rewrites as `mod.clone`
assemble_my_tabs() {
    local out="$1" version="$2" patch_dir="$COMMON_DIR/../herdr/patches/my-tabs"
    local anchor='enabled.includes("changes")' file generated
    local panels='shared("workspace.panels") ?? ["files", "changes"]'
    local sync='this.syncPanel(space, panel, body, enabled);' line

    cp -R "$HERDR_HOME/mods/tabs" "$out"
    for generated in "${HERDR_GENERATED[@]}"; do
        rm -f "$out/$generated"
    done

    for line in "$anchor" "$panels" "$sync" 'render() {'; do
        if [[ "$(grep -cF "$line" "$out/main.js" || true)" != 1 ]]; then
            log_error "The shipped tabs mod no longer has exactly one '$line' line to patch"
            return 1
        fi
    done

    # Without it in `enabled`, switching spaces would not restore the panel.
    # `r` must stay its own -e: BSD sed reads the file name up to the newline
    { printf 'import { repoSpace } from "./repo-space.js";\n'
      printf 'import { checkClones } from "./clone-check.js";\n'
      sed -e "/$anchor/r $patch_dir/button.js" \
          -e "/$sync/r $patch_dir/render-start.js" \
          -e 's|render() {|render(cx) {|' \
          -e 's|shared("workspace.panels") ?? \["files", "changes"\]|[...(&), "merge-requests"]|' \
          "$out/main.js"
    } > "$out/main.js.new"
    mv "$out/main.js.new" "$out/main.js"

    while IFS= read -r file; do
        sed -e 's|mods/tabs/|mods/my-tabs/|g' -e 's|mod: "tabs"|mod: "my-tabs"|g' "$file" > "$file.new"
        mv "$file.new" "$file"
    done < <(find "$out" -name '*.js')

    jq --arg version "$version" '.cloned_from = {name: "tabs", version: $version}' \
        "$out/mod.json" > "$out/mod.json.new" || return 1
    mv "$out/mod.json.new" "$out/mod.json"

    # After the path rewrite above: clone-check.js has to keep naming the shipped mod
    cp "$patch_dir/code.svg" "$patch_dir/merge-request.svg" "$patch_dir/repo-space.js" \
        "$patch_dir/clone-check.js" "$out/"

    # What this build came from, for clone-check.js. Not .js: Herdr must not load them
    mkdir -p "$out/shipped"
    cp "$HERDR_HOME/mods/tabs/main.js" "$out/shipped/tabs-main.txt"
    cp "$HERDR_HOME/layouts/main.json" "$out/shipped/main-layout.txt"
}

# Shipped main layout, pointed at my-tabs, with my-prs as one more side panel
assemble_my_layout() {
    local out="$1" version="$2" shipped="$HERDR_HOME/layouts/main.json"

    if [[ "$(jq '[.. | objects | select(.mod? == "tabs")] | length' "$shipped")" != 1 ]]; then
        log_error "The shipped main layout no longer has exactly one tabs block"
        return 1
    fi

    if [[ "$(jq '[.. | objects | select(.id? == "panel-body")] | length' "$shipped")" != 1 ]]; then
        log_error "The shipped main layout no longer has exactly one panel-body stack"
        return 1
    fi

    jq --arg version "$version" '
        (.. | objects | select(.mod? == "tabs") | .mod) |= "my-tabs"
        | (.. | objects | select(.id? == "panel-body") | .children) += [
            {id: "merge-requests", type: "block", content: {mod: "my-prs"}}
          ]
        | .cloned_from = {name: "main", version: $version}
    ' "$shipped" > "$out"
}

install_my_tabs() {
    local built="$1" target="$HERDR_HOME/mods/my-tabs" exclude=() generated
    for generated in "${HERDR_GENERATED[@]}"; do
        exclude+=(-x "$generated")
    done

    if [[ -d "$target" ]] && diff -r "${exclude[@]}" "$built" "$target" >/dev/null; then
        log_success "Herdr mod my-tabs already up to date"
        return 0
    fi

    [[ -e "$target" ]] && herdr_backup "$target" my-tabs
    mv "$built" "$target"
    log_success "Herdr mod my-tabs rebuilt"
}

install_my_layout() {
    local built="$1" target="$HERDR_HOME/layouts/my-layout.json"

    # Compared sorted: Herdr may rewrite the file with its keys in another order
    if [[ -f "$target" ]] && diff <(jq -S . "$built") <(jq -S . "$target") >/dev/null; then
        log_success "Herdr layout my-layout already up to date"
        return 0
    fi

    [[ -e "$target" ]] && herdr_backup "$target" my-layout.json
    mv "$built" "$target"
    log_success "Herdr layout my-layout rebuilt"
}

# `herdr-app check` only covers a mod: a layout is judged by the running window,
# which keeps the last good one and reports why. Without a window nothing can be asked.
verify_herdr_applied() {
    local report errors line

    sleep 2
    if ! report="$(herdr-app status 2>/dev/null)"; then
        log_info "Herdr is not running, so the rebuilt layout was not verified"
        return 0
    fi

    errors="$(jq -r '.errors[]' <<< "$report")"
    if [[ -z "$errors" ]]; then
        log_success "Herdr reports no errors"
        return 0
    fi

    log_error "Herdr reports errors, it may still show the previous version:"
    while IFS= read -r line; do
        [[ -n "$line" ]] && log_error "  $line"
    done <<< "$errors"
    return 1
}

# Rebuild my-tabs and my-layout from what the installed Herdr ships. Nothing is
# replaced unless the whole build passes, so a breaking update keeps the old pair.
# Hand edits to the two clones do not survive: they belong in herdr/patches.
build_herdr_layout() {
    local tool version build status=0

    for tool in jq herdr-app; do
        if ! command_exists "$tool"; then
            log_error "$tool is required to rebuild the Herdr layout"
            return 1
        fi
    done

    version="$(herdr-app --version)"
    version="${version##* }"
    # Hidden and outside mods/: Herdr must not load the build while it is half done
    build="$(mktemp -d "$HERDR_HOME/.build.XXXXXX")"

    if assemble_my_tabs "$build/my-tabs" "$version" \
        && assemble_my_layout "$build/my-layout.json" "$version" \
        && herdr-app check "$build/my-tabs"; then
        install_my_tabs "$build/my-tabs"
        install_my_layout "$build/my-layout.json"
        log_info "Herdr $version, to show the layout: herdr-app do layout.switch --name my-layout"
        verify_herdr_applied || status=1
    else
        log_error "Herdr $version: rebuild failed, my-tabs and my-layout were left as they were"
        status=1
    fi

    rm -rf "$build"
    return "$status"
}

# Run only when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
    setup_herdr_mods
    build_herdr_layout
fi
