#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES="zsh tmux starship nvim yazi lazygit lazysql herdr"

info()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m  ok\033[0m %s\n" "$*"; }
skip()  { printf "\033[1;33m skip\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;31m warn\033[0m %s\n" "$*"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_os() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "macos"
  elif command_exists dnf; then
    echo "fedora"
  else
    echo "unknown"
  fi
}

install_packages() {
  local os="$1"
  local pkgs=(git stow zsh tmux neovim curl fzf ripgrep bat eza zoxide yazi)
  local missing=()
  for p in "${pkgs[@]}"; do
    command_exists "$p" || missing+=("$p")
  done

  # fd ships as fd-find on Fedora, fd on macOS
  if ! command_exists fd; then
    case "$os" in
      fedora) missing+=(fd-find) ;;
      macos)  missing+=(fd) ;;
      *)      missing+=(fd) ;;
    esac
  fi

  if [[ ${#missing[@]} -eq 0 ]]; then
    skip "prerequisites already installed"
    return
  fi

  case "$os" in
    fedora)
      info "Installing prerequisites via dnf: ${missing[*]}"
      sudo dnf install -y "${missing[@]}"
      ;;
    macos)
      info "Installing prerequisites via brew: ${missing[*]}"
      brew install "${missing[@]}"
      ;;
    *)
      warn "Unsupported OS. Install manually: ${missing[*]}"
      ;;
  esac
}

install_tpm() {
  if [[ -d "$HOME/.tmux/plugins/tpm" ]]; then
    skip "TPM already installed"
  else
    info "Installing TPM (Tmux Plugin Manager)"
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi
}

install_zinit() {
  if [[ -f "$HOME/.local/share/zinit/zinit.git/zinit.zsh" ]]; then
    skip "Zinit already installed"
  else
    info "Installing Zinit (Zsh plugin manager)"
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"
  fi
}

install_starship() {
  if command_exists starship; then
    skip "Starship already installed"
  else
    info "Installing Starship prompt"
    curl -sS https://starship.rs/install.sh | sh
  fi
}

install_yazi_plugins() {
  if command_exists ya; then
    info "Installing Yazi plugins"
    ya pkg install
  else
    warn "yazi not found; run 'ya pkg install' after installing it"
  fi
}

install_lazygit() {
  if command_exists lazygit; then
    skip "lazygit already installed"
    return
  fi
  case "$1" in
    fedora)
      info "Installing lazygit via dnf"
      sudo dnf install -y lazygit
      ;;
    macos)
      info "Installing lazygit via brew"
      brew install lazygit
      ;;
    *)
      warn "Install lazygit manually"
      ;;
  esac
}

install_lazysql() {
  if command_exists lazysql; then
    skip "lazysql already installed"
    return
  fi
  case "$1" in
    fedora)
      info "Installing lazysql"
      local arch
      case "$(uname -m)" in
        x86_64)  arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        i386|i686) arch="i386" ;;
        *)
          warn "Unsupported architecture $(uname -m); install lazysql manually"
          return
          ;;
      esac
      mkdir -p "$HOME/.local/bin"
      curl -fsSL -o /tmp/lazysql.tar.gz \
        "https://github.com/jorgerojas26/lazysql/releases/latest/download/lazysql_Linux_${arch}.tar.gz"
      tar -xzf /tmp/lazysql.tar.gz -C "$HOME/.local/bin"
      chmod +x "$HOME/.local/bin/lazysql"
      ;;
    macos)
      info "Installing lazysql via brew"
      brew install lazysql
      ;;
    *)
      warn "Install lazysql manually"
      ;;
  esac
}

install_herdr() {
  if command_exists herdr; then
    skip "herdr already installed"
    return
  fi
  case "$1" in
    macos)
      info "Installing herdr via brew"
      brew install herdr
      ;;
    *)
      info "Installing herdr via installer script"
      curl -fsSL https://herdr.dev/install.sh | sh
      ;;
  esac
}

install_herdr_board() {
  if ! command_exists herdr; then
    warn "herdr not found; install herdr-board plugin after installing it"
    return
  fi
  if command_exists board; then
    skip "herdr-board already installed"
    return
  fi
  info "Installing herdr-board plugin"
  herdr plugin install nelsonPires5/herdr-board --ref v0.16.1 --yes
  info "Installing opencode harness integration"
  herdr integration install opencode
}

write_dotfiles_path() {
  info "Writing dotfiles path to ~/.config/dotfiles/path"
  mkdir -p "$HOME/.config/dotfiles"
  {
    printf 'DOTFILES_DIR="%s"\n' "$DOTFILES_DIR"
    printf 'CODES_DIR="%s"\n' "${CODES_DIR:-$HOME/Codes}"
  } > "$HOME/.config/dotfiles/path"
}

stow_packages() {
  if ! command_exists stow; then
    warn "stow not installed; skipping symlinks"
    return
  fi
  info "Deploying symlinks with stow"
  stow -t "$HOME" $PACKAGES
}

main() {
  local os
  os="$(detect_os)"
  info "Detected OS: $os"

  install_packages "$os"
  install_tpm
  install_zinit
  install_starship
  install_yazi_plugins
  install_lazygit "$os"
  install_lazysql "$os"
  install_herdr "$os"
  install_herdr_board
  write_dotfiles_path
  stow_packages

  printf "\n\033[1;32mDone.\033[0m Remaining manual steps:\n"
  printf "  1. chsh -s %s   (set Zsh as default shell)\n" "$(command -v zsh || echo /bin/zsh)"
  printf "  2. tmux new-session -s init   then press prefix+I to install tmux plugins\n"
  printf "  3. exec zsh\n"
  printf "\nTip: set CODES_DIR=/path/to/projects before running setup.sh to change the\n"
  printf "     default projects directory (currently %s).\n" "${CODES_DIR:-$HOME/Codes}"
}

main "$@"
