# Dotfiles

Configuration for my development environment on Fedora Linux, macOS, Windows (Git Bash), and WSL.

## Support matrix

| Target | Shell bootstrap | Package manager | Status |
| ------ | --------------- | --------------- | ------ |
| macOS | `./setup.sh` | Homebrew | supported |
| Fedora | `./setup.sh` | dnf | supported |
| WSL (Fedora/remix under WSL2) | `./setup.sh` | dnf (same as Fedora) | supported |
| Windows (Git Bash) | `./setup.sh` (winget guidance) | winget (manual) | supported |

`setup.sh` detects the OS via `detect_os` (`windows` → `macos` → `wsl` → `fedora` → `unknown`).
WSL is a distinct target from bare Fedora; Windows (Git Bash/MSYS/MINGW/Cygwin) is a distinct
target that prints `winget` install guidance instead of invoking `dnf`/`brew`.

## How to use this project

This repository uses [GNU Stow](https://www.gnu.org/software/stow/) to manage
dotfiles as symlinks. Each directory (`zsh/`,
`herdr/`, `lazygit/`, `lazysql/`)
mirrors the target home directory structure. Running `stow` creates symlinks
from your home directory back into this repo, so changes are tracked in one
place.

### Quick start

```bash
# 1. Clone
git clone <YOUR_REPO_URL> ~/Codes/dotfiles
cd ~/Codes/dotfiles

# 2. Run the bootstrap script (installs deps, plugins, and symlinks)
./setup.sh

# 3. Set Zsh as default shell
chsh -s "$(command -v zsh)"

# 4. Authenticate GitHub CLI
gh auth login

# 5. Restart shell
exec zsh
```

`setup.sh` is idempotent and detects Fedora vs macOS vs WSL vs Windows (dnf vs brew vs dnf-on-WSL vs winget guidance). Steps that
require interaction (changing your shell, authenticating GitHub CLI) are left manual.

`setup.sh` and `make install` write the repo location to
`~/.config/dotfiles/path` so shells can resolve the repo location.
This means the repo can live anywhere, not just `~/Codes/dotfiles`.

The projects directory defaults to `~/Codes` (used by the `c` shortcut in
Zsh). To change it, set `CODES_DIR` before running
`setup.sh` or `make install`:

```bash
CODES_DIR=~/Projects ./setup.sh
# or
make install CODES_DIR=~/Projects
```

Per-machine settings (e.g. Flutter, Antigravity CLI paths) go in
`~/.zshrc.local`, which is
sourced automatically and not tracked by git.

### Updating

After editing any config file in this repo:

```bash
cd ~/Codes/dotfiles
git add -A
git commit -m "description of change"
git push
```

On another machine, pull and re-stow:

```bash
cd ~/Codes/dotfiles
git pull
make install
```

### Adding a new config

```bash
# Create the directory structure matching your home directory
mkdir -p example/.config/example
# Place your config file
cp ~/.config/example/config.toml example/.config/example/config.toml
# Stow it
stow -t ~ example
```

---

## Included

- **Zsh** — Zinit plugin manager with autosuggestions, completions, fzf-tab, syntax highlighting
- **LazyGit** — TUI git client with Tokyo Night theme
- **GitHub CLI** — `gh`, installed by `setup.sh` (dnf/brew). Authenticate once with `gh auth login`; tokens live in `~/.config/gh/hosts.yml` (never committed)
- **LazySQL** — TUI database client (MySQL, PostgreSQL, SQLite, MSSQL, MongoDB) with configurable connections
- **Herdr** — terminal workspace manager for AI coding agents, with always-running background server, pane state tracking (working/blocked/idle), direct agent navigation (`alt+[` / `alt+]` for previous/next agent), and agent-native CLI/socket API. Birdseye plugin (`prefix+shift+b`) shows all agents in a live grid/column dashboard. Automations plugin (`prefix+a`) schedules recurring agent prompts on cron with a live board. Terminal-browser plugin (`prefix+t`) opens a real Chromium browser in a right split. Git Workspace Manager (`prefix+o`) opens an interactive `fzf` overlay pane displaying active workspaces and Git worktrees with live status indicators (branch name, `[push:A | pull:B | rebase:C]` commit counters, dirty `*` flag), commit and status previews, fast worktree switching (`Enter`), and safe Git operations (`Alt-p` push, `Alt-u` pull, `Alt-r` rebase) with Herdr notifications (`git-workspace-manager.sh` / `git-workspace-manager.ps1`). Keep-awake toggle (`prefix+shift+a`) inhibits screen blanking/locking and system idle sleep (`keep-awake.sh` / `keep-awake.ps1`) with automatic cleanup when Herdr exits

---

## Prerequisites

### Fedora

```bash
sudo dnf upgrade -y
```

```bash
sudo dnf install -y \
  git \
  stow \
  zsh \
  curl \
  fzf \
  ripgrep \
  fd-find \
  bat \
  eza \
  zoxide \
  chafa \
  jq \
  poppler-utils \
  7zip
```

```bash
# Optional: ffmpeg for video thumbnails (requires RPM Fusion)
sudo dnf install -y --skip-unavailable ffmpeg
```

### macOS

```bash
brew update
```
```bash
brew install \
  git \
  stow \
  zsh \
  curl \
  fzf \
  ripgrep \
  fd \
  bat \
  eza \
  zoxide \
  chafa \
  jq \
  poppler \
  ffmpeg \
  sevenzip
```

### WSL

WSL is a distinct target from bare Fedora. Inside the WSL distribution, follow the
Fedora prerequisites above (`dnf`). `setup.sh` reports `Detected OS: wsl` and reuses
the Fedora `dnf` path.

### Windows (Git Bash)

`setup.sh` reports `Detected OS: windows` under Git Bash / MSYS / MINGW / Cygwin and
prints `winget` guidance instead of installing automatically:

```powershell
winget install Git.Git fzf BurntSushi.ripgrep.MSVC sharkdp.fd sharkdp.bat eza-community.eza ajeetdsouza.zoxide JesseDuffield.lazygit GitHub.cli
```

Install `stow` (required for `./setup.sh` to deploy symlinks). `stow` is not
available via winget; install it via [MSYS2](https://www.msys2.org/)
(`pacman -S stow`) or use the Git Bash/MSYS2 environment that already
provides it, then verify with `stow --version`.

Then re-run `./setup.sh` to deploy symlinks via `stow` (install `stow` first if missing).

`setup.sh` also configures Git performance settings (including Windows filesystem cache and fsmonitor daemon) so `lazygit` stays fast:

```bash
git config --global core.preloadIndex true
git config --global core.untrackedCache true
git config --global feature.manyFiles true
git config --global core.fscache true
git config --global core.fsmonitor true
```

---

## Repository structure

```text
dotfiles/
├── Makefile
├── setup.sh
├── zsh/
│   └── .zshrc
├── lazygit/
│   └── .config/
│       └── lazygit/
│           └── config.yml
├── lazysql/
│   └── .config/
│       └── lazysql/
│           └── config.toml
└── herdr/
    └── .config/
        └── herdr/
            ├── config.toml
            └── scripts/
                ├── git-workspace-manager-preview.cmd
                ├── git-workspace-manager-preview.sh
                ├── git-workspace-manager.ps1
                ├── git-workspace-manager.sh
                ├── keep-awake.ps1
                └── keep-awake.sh
```

---

## Troubleshooting

Remove existing symlinks:

```bash
make uninstall
```

Recreate them:

```bash
make install
```

Recreate them (and prune stale symlinks):

```bash
make restow
```

Check where a symlink points:

```bash
ls -l ~/.zshrc
ls -l ~/.config/lazygit
ls -l ~/.config/lazysql
ls -l ~/.config/herdr
```

### Orphaned user state (notes only, repo does not touch `$HOME` outside stow)

Removing these components from the repo does not delete per-user caches,
plugin clones, or services that may exist on machines where they were
previously installed. If you want to clean a machine, do it manually:

```bash
# caches (safe to delete, regenerated on demand)
rm -rf ~/.cache/zsh
```

Previously installed tools, if no longer wanted, can be removed with the
system package manager (for example `sudo dnf remove` / `brew uninstall` /
`winget uninstall`). The repo itself never uninstalls machine packages.
