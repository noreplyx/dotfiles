# Dotfiles

Configuration for my development environment on Fedora Linux.

## How to use this project

This repository uses [GNU Stow](https://www.gnu.org/software/stow/) to manage
dotfiles as symlinks. Each directory (`zsh/`, `tmux/`, `nvim/`, `starship/`)
mirrors the target home directory structure. Running `stow` creates symlinks
from your home directory back into this repo, so changes are tracked in one
place.

### Quick start

```bash
# 1. Install prerequisites
sudo dnf install -y git stow zsh tmux neovim curl fzf ripgrep fd-find bat eza zoxide

# 2. Clone
git clone <YOUR_REPO_URL> ~/Codes/dotfiles
cd ~/Codes/dotfiles

# 3. Deploy symlinks
stow -t ~ zsh tmux starship nvim

# 4. Install Zinit (Zsh plugin manager)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"

# 5. Install Starship prompt
curl -sS https://starship.rs/install.sh | sh

# 6. Set Zsh as default shell
chsh -s /usr/bin/zsh

# 7. Restart shell
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
stow -t ~ zsh tmux starship nvim
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
- **tmux** — TPM plugins for session persistence, fzf navigation, status enhancements
- **Starship** — Minimal prompt with directory, git status, and language runtime info
- **Neovim** — LazyVim-based IDE with TypeScript, .NET, Docker, SQL, testing, debugging, Git integration

---

## Prerequisites (Fedora)

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
  zoxide
```

Install a [Nerd Font](https://www.nerdfonts.com/) (e.g. JetBrainsMono) for icons in Neovim and Starship.

---

## Repository structure

```text
dotfiles/
├── zsh/
│   └── .zshrc
├── tmux/
│   └── .tmux.conf
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
└── README.md
```

---

## Troubleshooting

Remove existing symlinks:

```bash
stow -D -t ~ zsh tmux starship nvim
```

Recreate them:

```bash
stow -t ~ zsh tmux starship nvim
```

Check where a symlink points:

```bash
ls -l ~/.zshrc
ls -l ~/.tmux.conf
ls -l ~/.config/starship.toml
ls -l ~/.config/nvim
```
