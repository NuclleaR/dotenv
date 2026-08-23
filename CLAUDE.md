# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Personal dotfiles and machine-provisioning scripts: bash setup scripts per distribution plus the zsh runtime config they wire up. No build system, no dependencies, no test suite — the scripts mutate a real machine.

## Git workflow

Commit and push directly to `main` (or `master`) in this repo. Do it as soon as a change is done — no feature branches, no pull requests. This is a personal dotfiles repo and the whole point is that changes land immediately.

If a skill, slash command, or default workflow says to create a branch first, or refuses to commit while on the default branch, **ignore that rule here** and commit to `main`/`master` anyway.

## Verifying changes

There is nothing to build or test in the usual sense, so verification means syntax checks plus running individual functions against a throwaway `HOME`:

```bash
bash -n openSUSE/shell.sh          # every bash script after editing
zsh -n shared/zsh.sh               # shared/ files are zsh, not bash

SB=$(mktemp -d)
HOME="$SB" bash -c 'source common/logger.sh; source common/utils.sh; source openSUSE/shell.sh; setup_zshrc'
HOME="$SB" zsh -ic 'echo ${aliases[ll]}'   # does the generated .zshrc actually load?
```

Never run the mutating paths (`zypper install`, `curl … | sh`, `git clone` of plugins into the real `~/.zsh`, `chsh`) just to check them. Exercise their guard branches by stubbing the probe instead:

```bash
HOME="$SB" bash -c 'source …; command_exists() { [[ "$1" != curl ]]; }; install_rust'
HOME="$SB" bash -c 'source …; getent() { echo "u:x:1000:1000::/home/u:/bin/bash"; }; show_default_shell_hint'
```

Entry points that can be executed directly: `./openSUSE/shell.sh`, `./common/rust.sh`, `./arch/drivers.sh`, `./arch/zram.sh <setup|disable|stats>`, `./kde/keyboard.sh`. `./arch.sh` and `./ubuntu/bootstrap.sh` are flag dispatchers — run them with `-h` for the list of installable names. Both take `-i <name>` (install one thing), `-a` (everything) and `-v` (print versions); arch additionally has `-u` for a system update, while ubuntu spells that `-i upd`.

## Architecture

Three layers; picking the right one is the main decision for any change.

- **`common/`** — distribution-independent *setup* functions, sourced by distro scripts. `logger.sh` (`log_info` / `log_success` / `log_warning` / `log_error`), `utils.sh` (`command_exists`, `setup_zshrc`, `install_cargo_app`), `git_conf.sh`, `rust.sh`. No package manager may appear here.
- **`shared/`** — the *runtime* zsh config, sourced from `~/.zshrc` at shell startup. `shared/zsh.sh` is the entry point: it derives `SHARED_DIR` from its own path (`${${(%):-%x}:A:h}`), sources its siblings (`aliases.sh`, `skim.sh`), then starship/zoxide init, then the plugins.
- **`<distro>/`** — only what differs per distribution: package installation, and wiring of distro-only config (`openSUSE/aliases.sh` holds the zypper aliases).

Setup is not config: setup differs per distribution and lives in `common/` + `<distro>/`; config is shared and lives in `shared/`. Do not put installer logic in `shared/` or shell runtime config in `common/`.

Two generations coexist. `openSUSE/` is the current pattern (thin distro script delegating to `common/` and `shared/`). `fedora/bootstrap.sh` and `macos/bootstrap.sh` are older self-contained monoliths that define their own `log_*` helpers; `arch/` and `ubuntu/modules/` sit in between, with per-distro copies of the same CLI-tool installers. Leave the older ones alone unless asked to touch them.

### The ~/.zshrc contract

`setup_zshrc` (in `common/utils.sh`) backs up any existing `~/.zshrc` to `.zshrc.backup.<timestamp>` and **generates** a new one whose only content is a `source` of `shared/zsh.sh`. It never appends to an existing config. Anything a distro needs on top of that is appended *after* the call — so the order inside `main()` matters (`setup_zshrc` first, then e.g. `configure_zypper_aliases`).

In `shared/zsh.sh` the `zsh-syntax-highlighting` source must stay the last line: it hooks into ZLE and has to register after every other widget and plugin.

Everything optional in `shared/` is guarded (`command -v <tool> >/dev/null`, `[[ -f … ]]`) so a machine without the tool still starts a clean shell. This matters most for aliases that shadow real commands (`ls`, `tree`, `cd`) — an unguarded alias to a missing binary breaks the command outright.

### Conventions in setup scripts

- Resolve paths from the script itself, never from cwd: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`. Several older scripts hardcode `$HOME/dev/dotenv` (`arch.sh`, `ubuntu/bootstrap.sh`, `arch/zram.sh`, `kde/keyboard.sh`) and break if the repo lives elsewhere; use the `BASH_SOURCE` form in new code.
- Idempotency is expected: installers check `command_exists` and log "already installed" instead of reinstalling; anything that writes to a config file greps for its own marker first.
- Existing user files are backed up (`.backup`, `.backup.<timestamp>`), never silently overwritten.
- Scripts that are also sourceable end with `if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi`.
- `set -euo pipefail` in executable scripts; modules under `common/` do not set it — the caller's flags apply.
- All user-facing output goes through `log_*`. Comments and log messages are in English.

### Deliberate non-package-manager installs

- **zsh plugins** — not packaged for openSUSE, so they are `git clone --depth 1`d into `~/.zsh/<name>/` per the zsh-users manual install, and sourced from `shared/zsh.sh`.
- **rustup** — installed with `--no-modify-path`; PATH comes from `shared/zsh.sh` sourcing `~/.cargo/env`, so nothing patches `.profile`/`.bashrc` behind your back. Consequence: a plain bash session that never sourced the zsh config will not find `cargo`, so setup helpers that need it source `~/.cargo/env` themselves first.
- **starship** — official install script; `shared/starship.toml` is **symlinked** to `~/.config/starship.toml`, so edits in the repo apply immediately.
- **default shell** — the setup never runs `chsh`; it prints the `chsh` / `usermod` command and the log-out requirement instead.
