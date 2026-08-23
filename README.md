# dotenv

Personal dotfiles and machine-provisioning scripts — plain bash setup scripts per distribution, plus the zsh config they wire up. No dependencies, no build step: clone the repo and run a script.

Covered: openSUSE, Arch, Ubuntu/Pop!\_OS, Fedora, macOS.

## Layout

| Path | What it is |
| --- | --- |
| `common/` | Distribution-independent **setup** functions: `logger.sh`, `utils.sh` (`command_exists`, `setup_zshrc`, `install_cargo_app`), `git_conf.sh`, `rust.sh` |
| `shared/` | The **runtime** zsh config, sourced from `~/.zshrc`: `zsh.sh` (entry point), `aliases.sh`, `skim.sh`, `starship.toml` |
| `openSUSE/` | zypper installs and zypper aliases |
| `arch/`, `arch.sh` | Arch bootstrap with per-topic modules (drivers, zram, packages, cli tools) |
| `ubuntu/` | Ubuntu/Pop!\_OS bootstrap with `modules/`, plus SSH backup/restore helpers |
| `fedora/`, `macos/` | Older self-contained bootstrap scripts |
| `git/` | Global gitignore, symlinked by `common/git_conf.sh` |
| `kde/`, `kde_shell.sh` | KDE keyboard remapping and config backup |
| `keyd/` | keyd keymap (`default.conf`) |
| `vscode/` | Recommended extensions and settings |

Setup and config are deliberately separate: setup differs per distribution, config does not.

## Quick start (openSUSE)

```bash
git clone https://github.com/NuclleaR/dotenv.git ~/.shell/dotenv
~/.shell/dotenv/openSUSE/shell.sh
```

That script:

1. installs `zsh`, `git` and `curl` via zypper;
2. installs [starship](https://starship.rs) with its official install script and symlinks `shared/starship.toml` to `~/.config/starship.toml`;
3. clones `zsh-autosuggestions` and `zsh-syntax-highlighting` into `~/.zsh/` (they are not packaged for openSUSE);
4. backs up any existing `~/.zshrc` to `.zshrc.backup.<timestamp>` and generates a new one that sources `shared/zsh.sh`;
5. appends the zypper aliases from `openSUSE/aliases.sh`;
6. prints how to make zsh the default shell — it never runs `chsh` for you.

Rust is separate:

```bash
~/.shell/dotenv/common/rust.sh
```

It installs rustup with `--no-modify-path`; `cargo` lands on `PATH` through `shared/zsh.sh`, which sources `~/.cargo/env`.

## Other machines

```bash
./arch.sh -h                # Arch: -i <name>, -u, -a, -v
./ubuntu/bootstrap.sh -h    # Ubuntu/Pop!_OS: -i <name|group>, -a, -v
./fedora/bootstrap.sh
./macos/bootstrap.sh
```

Standalone helpers: `./arch/drivers.sh`, `./arch/zram.sh <setup|disable|stats>`, `./kde/keyboard.sh`, `./kde_shell.sh` (backs up KDE config to `~/.kde_backups`).

> The older scripts (`arch.sh`, `ubuntu/bootstrap.sh`, `arch/zram.sh`, `kde/keyboard.sh`) still hardcode `$HOME/dev/dotenv` as the repo location; the newer ones resolve their own path and work from anywhere.

## Shell config

`~/.zshrc` is generated and contains nothing but a `source` of `shared/zsh.sh`, which sets up completion, history, key bindings, then sources its siblings and initialises the tools:

- `aliases.sh` — eza, zoxide and tailscale aliases, each guarded by `command -v`, so a missing tool never breaks `ls`, `tree` or `cd`;
- `skim.sh` — skim key bindings plus the `skf`, `gco` and `skrg` fuzzy finders;
- starship prompt, zoxide, `~/.cargo/env`;
- the zsh plugins from `~/.zsh/`, with `zsh-syntax-highlighting` last (it hooks into ZLE and must register after everything else).

Edit the files in this repo — `~/.config/starship.toml` is a symlink and `~/.zshrc` only points here, so changes apply without re-running any setup.

## Conventions

Every installer is idempotent: it checks whether the tool is already there and says so instead of reinstalling, and anything that writes to a config file looks for its own marker first. Existing user files are backed up, never silently overwritten. All output goes through the `log_info` / `log_success` / `log_warning` / `log_error` helpers in `common/logger.sh`.
