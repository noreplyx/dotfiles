# Dotfiles

Configuration for my development environment on Fedora Linux and macOS.

## How to use this project

This repository uses [GNU Stow](https://www.gnu.org/software/stow/) to manage
dotfiles as symlinks. Each directory (`zsh/`, `tmux/`, `nvim/`, `starship/`)
mirrors the target home directory structure. Running `stow` creates symlinks
from your home directory back into this repo, so changes are tracked in one
place.

### Quick start (Fedora)

```bash
# 1. Install prerequisites
sudo dnf install -y git stow zsh tmux neovim curl fzf ripgrep fd-find bat eza zoxide

# 2. Clone
git clone <YOUR_REPO_URL> ~/Codes/dotfiles
cd ~/Codes/dotfiles

# 3. Deploy symlinks
stow -t ~ zsh tmux starship nvim yazi

# 4. Install TPM (Tmux Plugin Manager)
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# 5. Install Zinit (Zsh plugin manager)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"

# 6. Install Starship prompt
curl -sS https://starship.rs/install.sh | sh

# 7. Install Yazi and its plugins
cargo install --locked yazi-fm yazi-cli
ya pkg install

# 8. Set Zsh as default shell
chsh -s /usr/bin/zsh

# 9. Start tmux and press prefix+I to install plugins
tmux new-session -s init

# 10. Restart shell
exec zsh
```

### Quick start (macOS)

```bash
# 1. Install prerequisites
brew install git stow zsh tmux neovim curl fzf ripgrep fd bat eza zoxide

# 2. Clone
git clone <YOUR_REPO_URL> ~/Codes/dotfiles
cd ~/Codes/dotfiles

# 3. Deploy symlinks
stow -t ~ zsh tmux starship nvim yazi

# 4. Install TPM (Tmux Plugin Manager)
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# 5. Install Zinit (Zsh plugin manager)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"

# 6. Install Starship prompt
curl -sS https://starship.rs/install.sh | sh

# 7. Install Yazi and its plugins
brew install yazi
ya pkg install

# 8. Set Zsh as default shell (macOS already uses Zsh by default)
# chsh -s /bin/zsh

# 9. Start tmux and press prefix+I to install plugins
tmux new-session -s init

# 10. Restart shell
exec zsh
```

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
stow -t ~ zsh tmux starship nvim yazi
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
- **Yazi** — Terminal file manager with image preview (WezTerm), git status linemode, and plugins: smart-enter, full-border, toggle-pane, jump-to-char, smart-filter, smart-paste, diff

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
│           ├── lua/
│           │   ├── config/
│           │   │   ├── lazy.lua
│           │   │   ├── options.lua
│           │   │   ├── keymaps.lua
│           │   │   └── autocmds.lua
│           │   └── plugins/
│           │       ├── aerial.lua
│           │       ├── colors.lua
│           │       ├── gitsigns.lua
│           │       ├── indent-blankline.lua
│           │       ├── neogit.lua
│           │       ├── neotest.lua
│           │       ├── rainbow-delimiters.lua
│           │       ├── snacks.lua
│           │       └── ts-config.lua
│           └── .gitignore
├── yazi/
│   └── .config/
│       └── yazi/
│           ├── yazi.toml
│           ├── keymap.toml
│           ├── theme.toml
│           ├── init.lua
│           └── package.toml
└── README.md
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
| `g c`      | Cd to ~/Codes                       |
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
stow -D -t ~ zsh tmux starship nvim yazi
```

Recreate them:

```bash
stow -t ~ zsh tmux starship nvim yazi
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
