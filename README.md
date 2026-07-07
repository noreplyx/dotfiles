# Dotfiles

Configuration for my development environment on Fedora Linux.

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

## Clone

```bash
git clone <YOUR_REPO_URL> ~/Codes/dotfiles
cd ~/Codes/dotfiles
```

---

## Deploy with GNU Stow

```bash
stow -t ~ zsh
stow -t ~ tmux
stow -t ~ starship
stow -t ~ nvim
```

Verify:

```bash
ls -l ~/.zshrc
ls -l ~/.tmux.conf
ls -l ~/.config/starship.toml
ls -l ~/.config/nvim
```

Each file should point back to this repository.

---

## Install Zinit

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"
```

Restart Zsh:

```bash
exec zsh
```

Plugins configured in `.zshrc` will be installed automatically on first load.

---

## Install Starship

```bash
curl -sS https://starship.rs/install.sh | sh
```

---

## Set Zsh as default shell

```bash
chsh -s /usr/bin/zsh
```

Log out and log back in. Verify:

```bash
echo $SHELL
# /usr/bin/zsh
```

---

## Reload configuration

```bash
source ~/.zshrc
```

or simply restart the terminal.

---

## Updating

After editing any configuration:

```bash
cd ~/Codes/dotfiles
git add .
git commit -m "Update configuration"
git push
```

On another machine:

```bash
cd ~/Codes/dotfiles
git pull
stow -t ~ zsh tmux starship nvim
```

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
