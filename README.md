# Dotfiles

Configuration for my development environment.

## Included

* **Zsh**
* **tmux**
* **Starship**
* (สามารถเพิ่ม Neovim, Git, Kitty ฯลฯ ได้ภายหลัง)

---

## Prerequisites (Fedora)

Update packages:

```bash
sudo dnf upgrade -y
```

Install required packages:

```bash
sudo dnf install -y \
  git \
  stow \
  zsh \
  tmux \
  curl \
  fzf \
  ripgrep \
  fd-find \
  bat \
  eza \
  zoxide
```

---

## Clone this repository

```bash
git clone <YOUR_GIT_REPOSITORY_URL> ~/Codes/dotfiles
cd ~/Codes/dotfiles
```

---

## Install configurations

Create symbolic links using GNU Stow:

```bash
stow -t ~ zsh
stow -t ~ tmux
stow -t ~ starship
```

Verify:

```bash
ls -l ~/.zshrc
ls -l ~/.tmux.conf
ls -l ~/.config/starship.toml
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

Plugins configured in `.zshrc` will be installed automatically the first time they are loaded.

---

## Install Starship

```bash
curl -sS https://starship.rs/install.sh | sh
```

Verify:

```bash
starship --version
```

---

## Set Zsh as the default shell

```bash
chsh -s /usr/bin/zsh
```

Log out and log back in.

Verify:

```bash
echo $SHELL
```

Expected output:

```text
/usr/bin/zsh
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

stow -t ~ zsh
stow -t ~ tmux
stow -t ~ starship
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
└── README.md
```

---

## Troubleshooting

Remove existing symbolic links:

```bash
stow -D -t ~ zsh
stow -D -t ~ tmux
stow -D -t ~ starship
```

Recreate them:

```bash
stow -t ~ zsh
stow -t ~ tmux
stow -t ~ starship
```

Check where a symlink points:

```bash
ls -l ~/.zshrc
ls -l ~/.tmux.conf
ls -l ~/.config/starship.toml
```

