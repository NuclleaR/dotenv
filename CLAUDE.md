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

Entry points that can be executed directly: `./openSUSE/shell.sh`, `./fedora/shell.sh`, `./fedora/postinstall.sh`, `./common/rust.sh`, `./common/ssh.sh`, `./fedora/ssh.sh` (installs keychain, then runs `common/ssh.sh`; pipeable, downloads `common/` when there is no clone), `./common/gpg.sh`, `./arch/drivers.sh`, `./arch/zram.sh <setup|disable|stats>`, `./kde/keyboard.sh`. `./arch.sh` and `./ubuntu/bootstrap.sh` are flag dispatchers — run them with `-h` for the list of installable names. Both take `-i <name>` (install one thing), `-a` (everything) and `-v` (print versions); arch additionally has `-u` for a system update, while ubuntu spells that `-i upd`.

## Architecture

Three layers; picking the right one is the main decision for any change.

- **`common/`** — distribution-independent *setup* functions, sourced by distro scripts. `logger.sh` (`log_info` / `log_success` / `log_warning` / `log_error`), `utils.sh` (`command_exists`, `setup_zshrc`, `install_cargo_app`), `git_conf.sh`, `rust.sh`, `ssh.sh`, `gpg.sh`, `backup-ssh.sh`, `restore-ssh.sh`. No package manager may appear here — `common/ssh.sh` only *checks* for `keychain`/`gh` and tells you which distro script installs them.
- **`shared/`** — the *runtime* zsh config, sourced from `~/.zshrc` at shell startup. `shared/zsh.sh` is the entry point: it derives `SHARED_DIR` from its own path (`${${(%):-%x}:A:h}`), sources its siblings (`aliases.sh`, `skim.sh`), then starship/zoxide init, then the plugins.
- **`<distro>/`** — only what differs per distribution: package installation, and wiring of distro-only config (`openSUSE/aliases.sh` holds the zypper aliases, `fedora/aliases.sh` the dnf ones).

Setup is not config: setup differs per distribution and lives in `common/` + `<distro>/`; config is shared and lives in `shared/`. Do not put installer logic in `shared/` or shell runtime config in `common/`.

Two generations coexist. `openSUSE/shell.sh` and `fedora/shell.sh` are the current pattern (thin distro script delegating to `common/` and `shared/`) — they are the same file bar the package manager. `fedora/bootstrap.sh` and `macos/bootstrap.sh` are older self-contained monoliths that define their own `log_*` helpers; `arch/` and `ubuntu/modules/` sit in between, with per-distro copies of the same CLI-tool installers. Leave the older ones alone unless asked to touch them.

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

### Self-contained scripts (do not "fix" their duplicated logger)

`fedora/shell.sh`, `fedora/postinstall.sh`, `fedora/apps.sh` and `fedora/ssh.sh` are meant to be
run straight off the internet, without a clone:

```bash
curl -sS https://raw.githubusercontent.com/NuclleaR/dotenv/main/fedora/apps.sh | bash -s -- -a
```

Two consequences that look like bugs but are deliberate:

- They **define `log_*` and `command_exists` inline** instead of sourcing
  `common/logger.sh`. Piped into a shell there is no script path to resolve a
  sibling from, so a `source` would abort under `set -e`. Keep the inline copies
  in step with `common/logger.sh`; do not replace them with a `source`.
- Their run guard is `if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]`,
  not the plain equality test the rest of the repo uses. Piped, `BASH_SOURCE[0]`
  is empty and `$0` is the shell's name, so the plain test never fires and the
  script silently does nothing at all.

`common/ssh.sh` and `common/gpg.sh` still want the repo on disk and keep the
normal `SCRIPT_DIR` + `source` form. All the pipeable ones need `bash`, not `sh`:
they use arrays and `mapfile`.

### The ~/.shell runtime directory (fedora)

`fedora/shell.sh` does need the runtime config, so it materialises it into
`$SHELL_DIR` (`~/.shell`) and points everything at that, never at the repo
directly:

- **piped** (`BASH_SOURCE[0]` empty) — downloads the files listed in
  `RUNTIME_FILES` from `$DOTENV_RAW`. `~/.shell` is then *managed*: a re-run
  overwrites it, and the script says so.
- **from a clone** (`detect_repo_root` finds `shared/zsh.sh` one level up) —
  symlinks `~/.shell/shared` and `~/.shell/fedora` at the repo. This is what
  preserves the repo's live-edit property; do not "simplify" it into a copy.

`RUNTIME_FILES` has to be maintained by hand: there is no directory listing over
raw.githubusercontent, so a new file sourced from `shared/zsh.sh` must be added
there or the piped install will be missing it.

`fedora/shell.sh` therefore has its own `setup_zshrc` rather than using the one
in `common/utils.sh` — the latter points `~/.zshrc` straight at the repo and is
still what `openSUSE/shell.sh` uses. The two are deliberately different.

### SSH / GPG / firewall invariants

- `common/ssh.sh` owns a block in `~/.ssh/config` delimited by `# >>> dotenv managed >>>` / `# <<< dotenv managed <<<`. Everything outside the markers is preserved; the block is *replaced*, never appended twice.
- `ssh-keygen -F <host>` **must** be called with `-f <known_hosts>`. Without it ssh-keygen resolves the path from the passwd entry rather than `$HOME`, so the check reads a different file than the script writes and the seeding stops being idempotent.
- Agent strategy is `keychain`, not a systemd user unit: one agent per host shared by every terminal, evaluated from `shared/zsh.sh` for **interactive shells only** (a non-interactive zsh must never block on a passphrase prompt). `gpg-agent` needs no equivalent — it is already one daemon per user; `common/gpg.sh` only sets its cache TTL.
- `GPG_TTY` is exported only when a terminal exists. An empty `GPG_TTY` is worse than an unset one — gpg tries to write the prompt into it.
- **fail2ban's ban action comes from the package, not from `jail.local`.**
  `fail2ban-firewalld` ships `jail.d/00-firewalld.conf` with
  `banaction = firewallcmd-rich-rules`, and **`jail.d` wins over `jail.local`** —
  setting `banaction` in the generated `jail.local` is silently ignored. An
  earlier version of this script moved that drop-in aside to force
  `banaction = ufw`, which then required hand-shipping an `action.d/ufw.conf`
  that Fedora does not package. `restore_firewalld_dropin` undoes both. Do not
  reintroduce a `banaction` line.
- `configure_fail2ban` ends with `systemctl restart`, not `enable --now`: on a
  re-run the service is already up and `--now` would leave it running with the
  old config.
- Validate any fail2ban change with `fail2ban-client -c <dir> -t` against a copy
  of `/etc/fail2ban` — it needs no root, so it works over a plain SSH session.

- **`postinstall.sh` runs first on a clean system, always.** "post install" means
  after installing the *operating system*, not after installing software — the
  name misreads easily. It is what closes the box, so everything that opens ports
  or pulls packages comes after it. It must therefore never depend on anything
  `apps.sh`, `storage.sh` or `shell.sh` provides; it installs what it needs
  itself. Anything that genuinely has to happen *after* `apps.sh` belongs at the
  end of the sequence in its own step, never folded back into `postinstall.sh`.
  Documented order: **postinstall, storage (only if this box wants the projects
  volume), shell, apps** — `storage.sh` before `apps.sh` because the package
  manager stores live inside that volume, and `shell.sh` before `apps.sh` so the
  rest of the setup is driven from a shell that is already zsh.
- `fedora/postinstall.sh` assumes a headless box reached over SSH, so the order in `main()` matters: firewalld is installed, unmasked, allowed the `ssh` service in the default zone and reloaded **before** `remove_ufw` takes the old firewall away. Every zone Fedora ships already permits `ssh`, so bringing firewalld up cannot cut a live session. A non-default sshd port is opened explicitly, since the `ssh` service definition only covers 22.
