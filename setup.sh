#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES="zsh tmux starship nvim yazi lazygit lazysql herdr wezterm"

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

# Yazi previewers shell out to external CLIs: rich (markdown/CSV/JSON/RST
# previews via the rich-preview plugin), resvg (SVG), poppler (PDF), ffmpeg
# (video thumbnails), 7z (archives), jq (JSON metadata), and chafa as the
# block-art image fallback.
install_yazi_preview_deps() {
  local os="$1"
  local missing=() pair

  case "$os" in
    macos)
      # pairs are "command:brew-formula"; brew sevenzip installs 7zz, not 7z
      for pair in \
        "resvg:resvg" \
        "rich:rich-cli" \
        "chafa:chafa" \
        "jq:jq" \
        "pdftotext:poppler" \
        "ffmpeg:ffmpeg" \
        "7zz:sevenzip"; do
        command_exists "${pair%%:*}" || missing+=("${pair##*:}")
      done
      if [[ ${#missing[@]} -eq 0 ]]; then
        skip "yazi preview dependencies already installed"
      else
        info "Installing yazi preview dependencies via brew: ${missing[*]}"
        brew install "${missing[@]}"
      fi
      ;;
    fedora)
      for pair in \
        "chafa:chafa" \
        "jq:jq" \
        "pdftotext:poppler-utils" \
        "ffmpeg:ffmpeg" \
        "7z:7zip"; do
        command_exists "${pair%%:*}" || missing+=("${pair##*:}")
      done
      if [[ ${#missing[@]} -gt 0 ]]; then
        info "Installing yazi preview dependencies via dnf: ${missing[*]}"
        # --skip-unavailable: ffmpeg needs RPM Fusion, which is not enabled everywhere
        sudo dnf install -y --skip-unavailable "${missing[@]}"
      else
        skip "dnf-packaged yazi preview dependencies already installed"
      fi
      install_resvg
      install_rich_cli
      ;;
    *)
      warn "Install yazi preview dependencies manually: resvg rich-cli chafa jq poppler ffmpeg 7z"
      ;;
  esac
}

# resvg is not packaged in Fedora repos; upstream ships Linux x86_64 binaries
install_resvg() {
  if command_exists resvg; then
    skip "resvg already installed"
    return 0
  fi
  local arch
  case "$(uname -m)" in
    x86_64) arch="x86_64" ;;
    *)
      warn "No upstream resvg binary for $(uname -m); yazi SVG preview unavailable"
      return 0
      ;;
  esac
  info "Installing resvg from upstream GitHub release"
  mkdir -p "$HOME/.local/bin"
  if curl -fsSL -o /tmp/resvg.tar.gz \
      "https://github.com/linebender/resvg/releases/latest/download/resvg-linux-${arch}.tar.gz" &&
    tar -xzf /tmp/resvg.tar.gz -C "$HOME/.local/bin" &&
    chmod +x "$HOME/.local/bin/resvg"; then
    ok "resvg installed to ~/.local/bin (make sure it is on PATH)"
  else
    warn "Could not install resvg from upstream; yazi SVG preview unavailable"
  fi
  rm -f /tmp/resvg.tar.gz
  return 0
}

# rich-cli is not packaged in Fedora repos either; pipx is the recommended route
install_rich_cli() {
  if command_exists rich; then
    skip "rich already installed"
    return 0
  fi
  if ! command_exists pipx && ! sudo dnf install -y python3-pipx; then
    warn "Could not install pipx; rich-preview will fall back to raw source view"
    return 0
  fi
  info "Installing rich-cli via pipx"
  if pipx install rich-cli && command_exists rich; then
    ok "rich installed"
  else
    warn "pipx install rich-cli failed or ~/.local/bin is not on PATH; yazi markdown previews fall back to raw source"
  fi
  return 0
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

install_herdr_opencode() {
  if ! command_exists herdr; then
    warn "herdr not found; run 'herdr integration install opencode' after installing it"
    return
  fi
  info "Installing opencode harness integration"
  herdr integration install opencode
}

install_wezterm() {
  if command_exists wezterm; then
    skip "WezTerm already installed"
    return
  fi

  case "$1" in
    fedora)
      info "Installing WezTerm via Fedora Copr"
      sudo dnf install -y dnf-plugins-core
      sudo dnf copr enable -y wezfurlong/wezterm-nightly
      sudo dnf install -y wezterm
      ;;
    macos)
      info "Installing WezTerm via brew"
      brew install --cask wezterm
      ;;
    *)
      warn "Install WezTerm manually"
      ;;
  esac
}

# tabline.wez is pinned to a reviewed commit; wezterm's plugin.require clones
# the default branch, so enforce the pin against wezterm's cached clone here.
pin_tabline_wez() {
  local PINNED_TABLINE_SHA="6022b9f9ec68c9a4dd50f40ceba3a7b9b9d1684a"  # v1.6.0
  if ! command_exists git; then
    warn "git not found; cannot enforce tabline.wez pin"
    return 0
  fi
  local clone found=0
  # wezterm's plugin cache lives under <DATA_DIR>/wezterm/plugins; DATA_DIR
  # differs per platform (and the exact macOS path is unverified), so probe all
  # plausible roots instead of hardcoding one.
  local roots=(
    "${XDG_DATA_HOME:-$HOME/.local/share}/wezterm"
    "$HOME/Library/Application Support/wezterm"
    "$HOME/Library/Caches/wezterm"
    "$HOME/.wezterm"
  )
  local root
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' clone; do
      found=1
      if [[ "$(git -C "$clone" rev-parse HEAD 2>/dev/null || true)" == "$PINNED_TABLINE_SHA" ]]; then
        ok "tabline.wez clone already at reviewed SHA"
        continue
      fi
      info "Forcing tabline.wez clone to reviewed SHA ${PINNED_TABLINE_SHA:0:12}"
      git -C "$clone" fetch --tags origin >/dev/null 2>&1 || true  # best effort; tolerate no network
      if git -C "$clone" checkout -q "$PINNED_TABLINE_SHA" >/dev/null 2>&1; then
        ok "tabline.wez clone pinned to reviewed SHA"
      else
        warn "Could not pin tabline.wez clone: $clone"
        printf '       fix manually: git -C %s fetch --tags origin && git -C %s checkout %s\n' \
          "$clone" "$clone" "$PINNED_TABLINE_SHA"
      fi
    done < <(find "$root" -maxdepth 3 -type d -name '*tabline*wez*' -print0 2>/dev/null)
  done
  if [[ $found -eq 0 ]]; then
    skip "tabline.wez clone not found; it is created on first wezterm start -- re-run setup.sh afterwards to pin it"
  fi
  return 0
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
  install_lazygit "$os"
  install_lazysql "$os"
  install_herdr "$os"
  install_herdr_opencode
  install_wezterm "$os"
  pin_tabline_wez
  write_dotfiles_path
  stow_packages
  install_yazi_plugins
  install_yazi_preview_deps "$os"

  printf "\n\033[1;32mDone.\033[0m Remaining manual steps:\n"
  printf "  1. chsh -s %s   (set Zsh as default shell)\n" "$(command -v zsh || echo /bin/zsh)"
  printf "  2. tmux new-session -s init   then press prefix+I to install tmux plugins\n"
  printf "  3. Start wezterm once, then re-run ./setup.sh to pin tabline.wez to the reviewed commit\n"
  printf "  4. exec zsh\n"
  printf "\nTip: set CODES_DIR=/path/to/projects before running setup.sh to change the\n"
  printf "     default projects directory (currently %s).\n" "${CODES_DIR:-$HOME/Codes}"
}

main "$@"
