# Dotfiles

Configuration for my development environment on Fedora Linux and macOS.

## How to use this project

This repository uses [GNU Stow](https://www.gnu.org/software/stow/) to manage
dotfiles as symlinks. Each directory (`zsh/`, `tmux/`, `nvim/`, `starship/`)
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

# 4. Start tmux and press prefix+I to install plugins
tmux new-session -s init

# 5. Restart shell
exec zsh
```

`setup.sh` is idempotent and detects Fedora vs macOS (dnf vs brew). Steps that
require interaction (changing your shell, tmux plugin install) are left manual.

`setup.sh` and `make install` write the repo location to
`~/.config/dotfiles/path`, which tmux sources to find the plugin-override
script. This means the repo can live anywhere, not just `~/Codes/dotfiles`.

The projects directory defaults to `~/Codes` (used by tmux sessionx and the
yazi `g c` bookmark). To change it, set `CODES_DIR` before running
`setup.sh` or `make install`:

```bash
CODES_DIR=~/Projects ./setup.sh
# or
make install CODES_DIR=~/Projects
```

Per-machine settings (e.g. Flutter, Antigravity CLI paths) go in
`~/.zshrc.local`, which is sourced automatically and not tracked by git.

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
mkdir -p nvim/.config/nvim/lua/plugins
# Place your config file
cp ~/.config/nvim/lua/plugins/example.lua nvim/.config/nvim/lua/plugins/example.lua
# Stow it
stow -t ~ nvim
```

---

## Included

- **Zsh** — Zinit plugin manager with autosuggestions, completions, fzf-tab, syntax highlighting
- **tmux** — TPM with tmux-sensible, tmux-sessionx (fzf session switcher), prefix-highlight. Vim-style pane resize, 72/28 split layout, custom fzf colors.
- **Starship** — Minimal prompt with directory, git status, and language runtime info
- **Neovim** — LazyVim-based IDE with TypeScript, .NET, Docker, SQL, testing, debugging, Git integration
- **Yazi** — Terminal file manager with image preview (WezTerm), git status linemode, and plugins: smart-enter, full-border, toggle-pane, jump-to-char, smart-filter, smart-paste, diff, githead, yaziline
- **LazyGit** — TUI git client with Tokyo Night theme, opened from Neovim with `<leader>gg`
- **LazySQL** — TUI database client (MySQL, PostgreSQL, SQLite, MSSQL, MongoDB) with configurable connections, opened from Neovim with `<leader>ls`
- **Herdr** — terminal workspace manager for AI coding agents, with always-running background server, pane state tracking (working/blocked/idle), and agent-native CLI/socket API

### Neovim plugins

- **Git** — gitsigns (inline blame), lazygit, gitgraph (`<leader>gl`), diffview (`<leader>gd`), git-worktree (`<leader>gw`), git-messenger (`<leader>gm`), GitHub PR creation with Octo (`<leader>gpc`), git-conflict
- **opencode** — AI coding assistant with render-markdown, restart server with `<leader>or`
- **yazi.nvim** — file manager in a floating window (`<leader>-`, `<leader>cw`, `<c-up>`)
- **toggleterm** — floating terminal (`<leader>tf`, `<c-\>`)
- **UI** — edgy (sidebar windows), aerial (code outline), rainbow-delimiters, indent-blankline, smear-cursor, snacks (picker/terminal), blink.cmp, nvim-colorizer
- **Testing** — neotest with jest, vitest, and dotnet adapters

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
  tmux \
  neovim \
  curl \
  fzf \
  ripgrep \
  fd-find \
  bat \
  eza \
  zoxide \
  yazi
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
  tmux \
  neovim \
  curl \
  fzf \
  ripgrep \
  fd \
  bat \
  eza \
  zoxide \
  yazi
```

Install a [Nerd Font](https://www.nerdfonts.com/) (e.g. JetBrainsMono) for icons in Neovim and Starship.

---

## Repository structure

```text
dotfiles/
├── Makefile
├── setup.sh
├── zsh/
│   └── .zshrc
├── tmux/
│   ├── .tmux.conf
│   ├── scripts/
│   │   └── apply-plugin-overrides.sh
│   └── plugins/
│       └── tmux-sessionx/
│           ├── sessionx.tmux
│           └── scripts/
│               └── sessionx.sh
├── starship/
│   └── .config/
│       └── starship.toml
├── nvim/
│   └── .config/
│       └── nvim/
│           ├── init.lua
│           ├── lazyvim.json
│           ├── lazy-lock.json
│           ├── stylua.toml
│           ├── .neoconf.json
│           ├── .gitignore
│           ├── README.md
│           ├── LICENSE
│           ├── lua/
│           │   ├── config/
│           │   │   ├── lazy.lua
│           │   │   ├── options.lua
│           │   │   ├── keymaps.lua
│           │   │   └── autocmds.lua
│           │   └── plugins/
│           │       ├── aerial.lua
│           │       ├── blink.lua
│           │       ├── colors.lua
│           │       ├── diffview.lua
│           │       ├── edgy.lua
│           │       ├── git-conflict.lua
│           │       ├── git-messenger.lua
│           │       ├── git-worktree.lua
│           │       ├── gitgraph.lua
│           │       ├── gitsigns.lua
│           │       ├── indent-blankline.lua
│           │       ├── lazygit.lua
│           │       ├── lazysql.lua
│           │       ├── neotest.lua
│           │       ├── opencode.lua
│           │       ├── rainbow-delimiters.lua
│           │       ├── smear-cursor.lua
│           │       ├── snacks.lua
│           │       ├── toggleterm.lua
│           │       ├── ts-config.lua
│           │       └── yazi.nvim.lua
├── yazi/
│   └── .config/
│       └── yazi/
│           ├── yazi.toml
│           ├── keymap.toml
│           ├── theme.toml
│           ├── init.lua
│           └── package.toml
├── lazygit/
│   └── .config/
│       └── lazygit/
│           └── config.yml
└── lazysql/
    └── .config/
        └── lazysql/
            └── config.toml
└── herdr/
    └── .config/
        └── herdr/
            └── config.toml
```

---

## Tmux

### Keybindings

| Key              | Action                        |
| ---------------- | ----------------------------- |
| `prefix + o`     | Launch sessionx (fzf session switcher) |
| `prefix + y`     | Launch yazi in a new window   |
| `prefix + H/J/K/L` | Resize pane left/down/up/right (5 cells) |
| `prefix + I`     | Install/update TPM plugins    |
| `prefix + R`     | Reload tmux config             |

### sessionx (inside the fzf popup)

| Key           | Action                        |
| ------------- | ----------------------------- |
| `enter`       | Switch to / create session    |
| `ctrl-w`      | List all windows              |
| `ctrl-t`      | Tree view of sessions+windows |
| `ctrl-x`      | Browse config directory       |
| `ctrl-e`      | Browse local directories      |
| `ctrl-b`      | Go back to session list       |
| `ctrl-r`      | Rename selected session       |
| `alt-bspace`  | Kill selected session         |
| `ctrl-u/d`    | Scroll preview up/down        |
| `?`           | Toggle preview pane           |

### Status bar

```
[prefix] | session_name | HH:MM
```

Shows prefix highlight indicator, current session name, and time.

### Layout

New sessions start with a 72/28 horizontal split (left pane 72%, right pane 28%).

---

## Yazi

Terminal file manager with image preview (WezTerm), git status linemode, and plugins.

### Plugins

Installed via `ya pkg` (see `yazi/.config/yazi/package.toml`):

- `smart-enter` — open files or enter directories with one key
- `full-border` — full rounded border
- `toggle-pane` — show/hide/maximize panes
- `jump-to-char` — vim-like `f<char>` navigation
- `git` — git status linemode
- `smart-filter` — continuous filtering, auto-enter unique dir
- `smart-paste` — paste into hovered directory or CWD
- `diff` — diff selected with hovered file

### Keybindings

| Key        | Action                              |
| ---------- | ----------------------------------- |
| `l`        | Enter dir or open file (smart-enter) |
| `f`        | Jump to char                        |
| `F`        | Smart filter                        |
| `p`        | Smart paste                         |
| `T`        | Show/hide preview pane              |
| `M`        | Maximize/restore preview pane       |
| `Ctrl-d`   | Diff selected with hovered file     |
| `g d`      | Cd to ~/Downloads                   |
| `g c`      | Cd to projects dir (`$CODES_DIR`)   |
| `g h`      | Cd to home                          |
| `g z`      | Cd to ~/.config                     |

### Install plugins

```bash
ya pkg install
```

### Troubleshooting

Reinstall plugins:

```bash
rm -rf ~/.config/yazi/plugins
ya pkg install
```

Clear image preview cache:

```bash
yazi --clear-cache
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
ls -l ~/.tmux.conf
ls -l ~/.config/starship.toml
ls -l ~/.config/nvim
ls -l ~/.config/yazi
```

### Tmux

Reinstall TPM plugins:

```bash
rm -rf ~/.tmux/plugins/tpm
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
# Start tmux, press prefix+I
```

Re-apply plugin overrides:

```bash
bash ~/Codes/dotfiles/tmux/scripts/apply-plugin-overrides.sh
```

The script self-locates, so it works from any clone path.
