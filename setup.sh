#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES="zsh tmux starship nvim yazi lazygit lazysql herdr wezterm"

# Supply-chain pins (best-effort: upstream publishes no checksums/hashes).
# Transport is hardened to HTTPS-only (--proto '=https' --tlsv1.2) everywhere.
# Re-pin to a reviewed tag/commit when updating; hashes marked UNKNOWN mean
# upstream provides no checksum file to verify against.
# Re-pin: replace HEAD/latest with a reviewed tag/commit when updating (Major pins deferred).
ZINIT_PIN_REF="HEAD" # UNKNOWN hash: zdharma-continuum/zinit publishes no checksum; pinned to branch ref, review file before exec
STARSHIP_INSTALL_URL="https://starship.rs/install.sh" # UNKNOWN hash: starship.rs installer publishes no checksum file
HERDR_INSTALL_URL="https://herdr.dev/install.sh" # UNKNOWN hash: herdr.dev installer publishes no versioned checksum
RESVG_PIN_TAG="latest" # UNKNOWN hash: linebender/resvg publishes no checksums; change to vX.Y.Z to pin
LAZYSQL_PIN_TAG="latest" # UNKNOWN hash: jorgerojas26/lazysql publishes no checksums; change to vX.Y.Z to pin
# MACISM via brew formula (versioned by Homebrew; `brew info macism` shows pinned
# version). Install is warn-only/non-fatal: failure leaves detect-layout.sh on
# im-select/defaults fallback, macOS KB behavior unchanged.

# Create an isolated temp dir for downloads/extracts (mktemp -d).
# Caller owns cleanup with explicit rm -rf.
make_temp_dir() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-setup.XXXXXX")" || return 1
  printf '%s' "$tmp"
}

# Validate tar entries (reject absolute paths, .. path components, and
# symlink/hardlink entries), then extract into a caller-provided fresh
# empty dir without preserving owner.
safe_extract_tarball() {
  local archive="$1" dest="$2"
  local listing line ftype fname
  local -a no_owner_arg=()
  mkdir -p "$dest"
  if tar --help 2>/dev/null | grep -q -- '--no-same-owner'; then
    no_owner_arg=(--no-same-owner)
  fi
  listing="$(tar -tzvf "$archive" 2>/dev/null)" || { warn "tar listing failed"; return 1; }
  [[ -n "$listing" ]] || { warn "tar listing failed (empty archive listing)"; return 1; }
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      *" -> "*|*" link to "*) warn "Refusing to extract link tar entry: $line"; return 1 ;;
    esac
    ftype="${line:0:1}"
    case "$ftype" in
      l|h) warn "Refusing to extract link tar entry: $line"; return 1 ;;
    esac
    fname="${line##* }"
    case "$fname" in
      /*) warn "Refusing to extract unsafe tar entry: $fname"; return 1 ;;
    esac
    case "$fname" in
      ../*|*/../*|*/..|..) warn "Refusing to extract unsafe tar entry: $fname"; return 1 ;;
    esac
  done <<< "$listing" || true
  tar "${no_owner_arg[@]}" -xzf "$archive" -C "$dest"
}

info()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m  ok\033[0m %s\n" "$*"; }
skip()  { printf "\033[1;33m skip\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;31m warn\033[0m %s\n" "$*"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

is_wsl() {
  [[ -f /proc/version ]] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null
}

is_windows() {
  case "${OS:-} ${OSTYPE:-} $(uname -s 2>/dev/null)" in
    *[Ww]indows*|*MINGW*|*MSYS*|*CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

detect_os() {
  if is_windows; then
    echo "windows"
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    echo "macos"
  elif is_wsl; then
    echo "wsl"
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
      fedora|wsl) missing+=(fd-find) ;;
      macos)  missing+=(fd) ;;
      windows) missing+=(fd) ;;
      *)      missing+=(fd) ;;
    esac
  fi

  if [[ ${#missing[@]} -eq 0 ]]; then
    skip "prerequisites already installed"
    return
  fi

  case "$os" in
    fedora|wsl)
      info "Installing prerequisites via dnf: ${missing[*]}"
      sudo dnf install -y "${missing[@]}" || warn "dnf install failed (non-fatal; e.g. WSL/sudo-less); install manually: ${missing[*]}"
      ;;
    macos)
      info "Installing prerequisites via brew: ${missing[*]}"
      brew install "${missing[@]}"
      ;;
    windows)
      warn "Windows (Git Bash) detected. Install via winget manually: ${missing[*]}"
      warn "Example: winget install sharkdp.fd  (fd; see README Windows section)"
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
    fedora|wsl)
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
        # (on WSL without systemd/sudo, dnf may fail; install manually per README)
        sudo dnf install -y --skip-unavailable "${missing[@]}" || warn "dnf install failed (non-fatal); install manually: ${missing[*]}"
      else
        skip "dnf-packaged yazi preview dependencies already installed"
      fi
      install_resvg
      install_rich_cli
      ;;
    windows)
      warn "Windows detected. Install yazi preview deps via winget/choco manually: resvg rich-cli chafa jq poppler ffmpeg 7z (see README)"
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
  # Upstream publishes no checksums; pinned to HTTPS transport only (mutable latest tag).
  mkdir -p "$HOME/.local/bin"
  local tmp stage
  tmp="$(make_temp_dir)" || { warn "Could not create temp dir; aborting resvg install"; return 0; }
  stage="$tmp/stage"; mkdir -p "$stage"
  if curl --proto '=https' --tlsv1.2 -fsSL -o "$tmp/resvg.tar.gz" \
      "https://github.com/linebender/resvg/releases/${RESVG_PIN_TAG}/download/resvg-linux-${arch}.tar.gz" &&
    safe_extract_tarball "$tmp/resvg.tar.gz" "$stage" &&
    [ -f "$stage/resvg" ] && [ ! -L "$stage/resvg" ] &&
    install -m 0755 "$stage/resvg" "$HOME/.local/bin/resvg"; then
    ok "resvg installed to ~/.local/bin (make sure it is on PATH)"
  else
    warn "Could not install resvg from upstream; yazi SVG preview unavailable"
  fi
  rm -rf "$tmp"
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
    # No checksum published upstream; HTTPS+TLS hardened transport only. Download to file for review, then exec.
    local tmp installer
    tmp="$(make_temp_dir)" || { warn "Could not create temp dir; skipping zinit"; return 0; }
    installer="$tmp/zinit-install.sh"
    if curl --proto '=https' --tlsv1.2 -fsSL -o "$installer" "https://raw.githubusercontent.com/zdharma-continuum/zinit/${ZINIT_PIN_REF}/scripts/install.sh"; then
      info "Review before exec: less $installer (kept on failure; clean up with rm -rf $tmp)"
      bash "$installer" && rm -rf "$tmp" || warn "Zinit installer failed; script kept at $installer for review (clean up with rm -rf $tmp)"
    else
      warn "Zinit download failed; skipping"
      rm -rf "$tmp"
    fi
  fi
}

install_starship() {
  if command_exists starship; then
    skip "Starship already installed"
  else
    info "Installing Starship prompt"
    # No checksum published upstream; HTTPS+TLS hardened transport only. Download to file for review, then exec.
    local tmp installer
    tmp="$(make_temp_dir)" || { warn "Could not create temp dir; skipping starship"; return 0; }
    installer="$tmp/starship-install.sh"
    if curl --proto '=https' --tlsv1.2 -fsSL -o "$installer" "$STARSHIP_INSTALL_URL"; then
      info "Review before exec: less $installer (kept on failure; clean up with rm -rf $tmp)"
      sh "$installer" && rm -rf "$tmp" || warn "Starship installer failed; script kept at $installer for review (clean up with rm -rf $tmp)"
    else
      warn "Starship download failed; skipping"
      rm -rf "$tmp"
    fi
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
    fedora|wsl)
      info "Installing lazygit via dnf"
      sudo dnf install -y lazygit || warn "dnf install lazygit failed (non-fatal); install manually"
      ;;
    macos)
      info "Installing lazygit via brew"
      brew install lazygit
      ;;
    windows)
      warn "Windows detected. Install lazygit via winget: winget install JesseDuffield.lazygit"
      ;;
    *)
      warn "Install lazygit manually"
      ;;
  esac
}

install_gh() {
  if command_exists gh; then
    skip "gh already installed"
    return
  fi
  case "$1" in
    fedora|wsl)
      info "Installing GitHub CLI via dnf"
      sudo dnf install -y gh || warn "dnf install gh failed (non-fatal); install manually (https://cli.github.com/)"
      ;;
    macos)
      info "Installing GitHub CLI via brew"
      brew install gh
      ;;
    windows)
      warn "Windows detected. Install gh via winget: winget install GitHub.cli"
      ;;
    *)
      warn "Install gh manually (https://cli.github.com/)"
      ;;
  esac
}

install_lazysql() {
  if command_exists lazysql; then
    skip "lazysql already installed"
    return
  fi
  case "$1" in
    fedora|wsl)
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
      # Upstream publishes no checksums; pinned to HTTPS transport only (mutable latest tag). Fail closed on download/extract error.
      local tmp stage
      tmp="$(make_temp_dir)" || { warn "lazysql temp dir failed; install manually"; return; }
      stage="$tmp/stage"; mkdir -p "$stage"
      curl --proto '=https' --tlsv1.2 -fsSL -o "$tmp/lazysql.tar.gz" \
        "https://github.com/jorgerojas26/lazysql/releases/${LAZYSQL_PIN_TAG}/download/lazysql_Linux_${arch}.tar.gz" || {
        warn "lazysql download failed; install manually"
        rm -rf "$tmp"
        return
      }
      safe_extract_tarball "$tmp/lazysql.tar.gz" "$stage" || {
        warn "lazysql extraction failed; install manually"
        rm -rf "$tmp"
        return
      }
      if [ ! -f "$stage/lazysql" ] || [ -L "$stage/lazysql" ]; then
        warn "lazysql staged binary missing or is a symlink; install manually"
        rm -rf "$tmp"
        return
      fi
      install -m 0755 "$stage/lazysql" "$HOME/.local/bin/lazysql" || {
        warn "lazysql install failed; install manually"
        rm -rf "$tmp"
        return
      }
      rm -rf "$tmp"
      ;;
    macos)
      info "Installing lazysql via brew"
      brew install lazysql
      ;;
    windows)
      warn "Windows detected. Install lazysql manually (download Windows release)"
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
    windows)
      warn "Windows detected. Install herdr manually (see https://herdr.dev)"
      ;;
    *)
      info "Installing herdr via installer script"
      # Pre-existing upstream installer (no versioned checksum published); harden transport only.
      # To review interactively first, download the script and inspect before piping to sh.
      warn "herdr installer is unverified upstream; review https://herdr.dev/install.sh before proceeding if needed"
      local tmp installer
      tmp="$(make_temp_dir)" || { warn "Could not create temp dir; skipping herdr"; return; }
      installer="$tmp/herdr-install.sh"
      if curl --proto '=https' --tlsv1.2 -fsSL -o "$installer" "$HERDR_INSTALL_URL"; then
        info "Review before exec: less $installer (kept on failure; clean up with rm -rf $tmp)"
        sh "$installer" && rm -rf "$tmp" || warn "herdr installer failed; script kept at $installer for review (clean up with rm -rf $tmp)"
      else
        warn "herdr download failed; install manually"
        rm -rf "$tmp"
      fi
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
    fedora|wsl)
      info "Installing WezTerm via Fedora Copr"
      sudo dnf install -y dnf-plugins-core || warn "dnf install dnf-plugins-core failed (non-fatal); install WezTerm manually"
      sudo dnf copr enable -y wezfurlong/wezterm-nightly || warn "dnf copr enable failed (non-fatal); install WezTerm manually"
      sudo dnf install -y wezterm || warn "dnf install wezterm failed (non-fatal); install WezTerm manually"
      ;;
    macos)
      info "Installing WezTerm via brew"
      brew install --cask wezterm
      ;;
    windows)
      warn "Windows detected. Install WezTerm manually: winget install wez.wezterm"
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

install_kb_layout_watcher() {
  local os="${1:-$(detect_os)}"
  info "Setting up keyboard layout watcher"
  chmod +x "$DOTFILES_DIR/wezterm/.config/wezterm/scripts/detect-layout.sh" \
    "$DOTFILES_DIR/wezterm/.config/wezterm/scripts/toggle-layout.sh" \
    "$DOTFILES_DIR/wezterm/.config/wezterm/scripts/kb-layout-watch.sh" 2>/dev/null || true
  if [[ "$os" == "macos" ]]; then
    if ! command -v macism >/dev/null 2>&1 && ! command -v im-select >/dev/null 2>&1; then
      if command_exists brew; then
        # Pinned via brew formula versioning (see MACISM note above); warn-only.
        info "Installing macism via brew (best-effort)"
        brew install macism || warn "brew install macism failed (non-fatal); install manually: brew install macism"
      else
        warn "macOS input switching needs macism or im-select: brew install macism  (or: brew install im-select)"
      fi
    else
      skip "input switcher already installed"
    fi
    if [[ "$os" == "macos" ]]; then
      _kb_dir="${XDG_RUNTIME_DIR:-/tmp}"
      if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "$HOME/.cache" ]]; then _kb_dir="$HOME/.cache"; fi
      mkdir -p "$_kb_dir" 2>/dev/null || true
      if command -v macism >/dev/null 2>&1; then
        printf '%s' "macism" > "$_kb_dir/wezterm-kb-selector" 2>/dev/null || true
      elif command -v im-select >/dev/null 2>&1; then
        printf '%s' "im-select" > "$_kb_dir/wezterm-kb-selector" 2>/dev/null || true
      fi
      _plist_src="$DOTFILES_DIR/wezterm/.config/wezterm/scripts/com.wezterm.kb-layout-watch.plist"
      _plist_dest="$HOME/Library/LaunchAgents/com.wezterm.kb-layout-watch.plist"
      if [[ -f "$_plist_src" ]]; then
        mkdir -p "$HOME/Library/LaunchAgents" 2>/dev/null || true
        ln -sf "$_plist_src" "$_plist_dest" 2>/dev/null || true
        if command_exists launchctl; then
          launchctl bootout "gui/$(id -u)" "$_plist_dest" >/dev/null 2>&1 || true
          launchctl bootstrap "gui/$(id -u)" "$_plist_dest" >/dev/null 2>&1 || \
            launchctl load -w "$_plist_dest" >/dev/null 2>&1 || \
            warn "could not load kb-layout-watch LaunchAgent (non-fatal; wezterm gui-startup fallback still works)"
        fi
      fi
    fi
    skip "systemd not used on macOS; LaunchAgent (gui-startup fallback) launches kb-layout-watch.sh"
    return 0
  fi
  # Windows (Git Bash) and WSL without systemd use the file-cache fallback.
  if [[ "$os" == "windows" ]] || { [[ "$os" == "wsl" ]] && ! command_exists systemctl; }; then
    skip "systemd not used on this target; kb-layout-watch file-cache fallback still works"
    return 0
  fi
  mkdir -p "$HOME/.config/systemd/user" 2>/dev/null || true
  ln -sf "$DOTFILES_DIR/wezterm/.config/wezterm/scripts/kb-layout-watch.service" \
    "$HOME/.config/systemd/user/kb-layout-watch.service" 2>/dev/null || true
  if command_exists systemctl; then
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable --now kb-layout-watch.service >/dev/null 2>&1 || \
      warn "could not enable kb-layout-watch.service (non-fatal; file-cache fallback still works)"
  else
    skip "systemctl not found; kb-layout-watch.service not enabled (file-cache fallback still works)"
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
  install_gh "$os"
  install_lazysql "$os"
  install_herdr "$os"
  install_herdr_opencode
  install_wezterm "$os"
  pin_tabline_wez
  install_kb_layout_watcher "$os"
  write_dotfiles_path
  stow_packages
  install_yazi_plugins
  install_yazi_preview_deps "$os"

  printf "\n\033[1;32mDone.\033[0m Remaining manual steps:\n"
  printf "  1. chsh -s %s   (set Zsh as default shell)\n" "$(command -v zsh || echo /bin/zsh)"
  printf "  2. tmux new-session -s init   then press prefix+I to install tmux plugins\n"
  printf "  3. Start wezterm once, then re-run ./setup.sh to pin tabline.wez to the reviewed commit\n"
  printf "  4. gh auth login   (required for Octo PR creation <leader>gpc in Neovim)\n"
  printf "  5. exec zsh\n"
  printf "\nTip: set CODES_DIR=/path/to/projects before running setup.sh to change the\n"
  printf "     default projects directory (currently %s).\n" "${CODES_DIR:-$HOME/Codes}"
}

main "$@"
