#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES="zsh powershell lazygit lazysql herdr"

# Supply-chain pins (best-effort: upstream publishes no checksums/hashes).
# Transport is hardened to HTTPS-only (--proto '=https' --tlsv1.2) everywhere.
# Re-pin to a reviewed tag/commit when updating; hashes marked UNKNOWN mean
# upstream provides no checksum file to verify against.
# Re-pin: replace HEAD/latest with a reviewed tag/commit when updating (Major pins deferred).
ZINIT_PIN_REF="HEAD" # UNKNOWN hash: zdharma-continuum/zinit publishes no checksum; pinned to branch ref, review file before exec
HERDR_INSTALL_URL="https://herdr.dev/install.sh" # UNKNOWN hash: herdr.dev installer publishes no versioned checksum
HERDR_BIRDSEYE_REF="0521d53ec31f129f79fdda889ed219a12fd9d60b" # reviewed commit (upstream publishes no tags; manifest version 0.6.0): calebcauthon/herdr-birdseye birdseye dashboard (prefix+shift+b)
HERDR_AUTOMATIONS_REF="c869ffa5ffee3e94f9507cd366d3c4330e6435fd" # reviewed commit (upstream publishes no tags; manifest version 0.8.0): DnzzL/herdr-automations cron-scheduled agent prompts (prefix+a)
HERDR_TERMINAL_BROWSER_REF="b641f508632d883c2abd596d582cecc80099d349" # reviewed commit (upstream publishes no tags; manifest version 0.1.1): zenbu-labs/terminal-browser/herdr-plugin in-terminal browser (prefix+t)
LAZYSQL_PIN_TAG="latest" # UNKNOWN hash: jorgerojas26/lazysql publishes no checksums; change to vX.Y.Z to pin

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
  local pkgs=(git stow zsh curl fzf ripgrep bat eza zoxide)
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

preseed_herdr_cache_badges() {
  local cache_dirs=("${HOME}/.cache")
  if [[ -n "${USERPROFILE:-}" ]] && { command_exists cygpath || [[ "${OSTYPE:-}" == "msys" || "${OSTYPE:-}" == "cygwin" ]]; }; then
    local windows_cache_dir="$USERPROFILE/.cache"
    command_exists cygpath && windows_cache_dir="$(cygpath -u "$USERPROFILE")/.cache"
    cache_dirs+=("$windows_cache_dir")
  fi
  local cache_dir
  for cache_dir in "${cache_dirs[@]}"; do
    mkdir -p "$cache_dir" 2>/dev/null || true
    if [[ ! -f "$cache_dir/herdr-keep-awake.badge" ]]; then
      printf 'AWAKE: OFF\n' > "$cache_dir/herdr-keep-awake.badge" 2>/dev/null || true
    fi
  done
}

sync_herdr_target_dir() {
  local target_dir="$1"
  mkdir -p "$target_dir" 2>/dev/null || true
  ln -sf "$DOTFILES_DIR/herdr/.config/herdr/config.toml" "$target_dir/config.toml" 2>/dev/null \
    || cp -f "$DOTFILES_DIR/herdr/.config/herdr/config.toml" "$target_dir/config.toml" 2>/dev/null || true
  if [[ ! -e "$target_dir/scripts" ]]; then
    ln -s "$DOTFILES_DIR/herdr/.config/herdr/scripts" "$target_dir/scripts" 2>/dev/null \
      || { mkdir -p "$target_dir/scripts" && cp -rf "$DOTFILES_DIR/herdr/.config/herdr/scripts/." "$target_dir/scripts/"; } 2>/dev/null || true
  elif [[ ! -L "$target_dir/scripts" ]]; then
    cp -rf "$DOTFILES_DIR/herdr/.config/herdr/scripts/." "$target_dir/scripts/" 2>/dev/null || true
  fi
  chmod +x "$target_dir/scripts/keep-awake.sh" 2>/dev/null || true
  chmod +x "$target_dir/scripts/git-workspace-manager.sh" 2>/dev/null || true
  chmod +x "$target_dir/scripts/git-workspace-manager-preview.sh" 2>/dev/null || true
  preseed_herdr_cache_badges
}

install_herdr() {
  chmod +x "$DOTFILES_DIR/herdr/.config/herdr/scripts/keep-awake.sh" 2>/dev/null || true
  chmod +x "$DOTFILES_DIR/herdr/.config/herdr/scripts/git-workspace-manager.sh" 2>/dev/null || true
  chmod +x "$DOTFILES_DIR/herdr/.config/herdr/scripts/git-workspace-manager-preview.sh" 2>/dev/null || true
  if [[ "${1:-}" == "windows" && -n "${APPDATA:-}" ]]; then
    local appdata_dir="$APPDATA"
    command_exists cygpath && appdata_dir="$(cygpath -u "$APPDATA")"
    sync_herdr_target_dir "$appdata_dir/herdr"
  fi
  sync_herdr_target_dir "$HOME/.config/herdr"
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

install_herdr_birdseye() {
  if ! command_exists herdr; then
    warn "herdr not found; run 'herdr plugin install calebcauthon/herdr-birdseye' after installing it"
    return
  fi
  if herdr plugin list 2>/dev/null | grep -q "herdr-plugins.birdseye\|birdseye"; then
    skip "herdr birdseye plugin already installed"
    return
  fi
  info "Installing herdr birdseye plugin (${HERDR_BIRDSEYE_REF})"
  herdr plugin install "calebcauthon/herdr-birdseye" --ref "$HERDR_BIRDSEYE_REF" -y \
    || warn "herdr birdseye install failed (non-fatal); install manually: herdr plugin install calebcauthon/herdr-birdseye"
}

install_herdr_opencode() {
  if ! command_exists herdr; then
    warn "herdr not found; run 'herdr integration install opencode' after installing it"
    return
  fi
  info "Installing opencode harness integration"
  herdr integration install opencode
}

install_herdr_automations() {
  if ! command_exists herdr; then
    warn "herdr not found; run 'herdr plugin install DnzzL/herdr-automations' after installing it"
    return
  fi
  if herdr plugin list 2>/dev/null | grep -q "dnzzl.automations\|herdr-automations"; then
    skip "herdr automations plugin already installed"
    return
  fi
  info "Installing herdr automations plugin (${HERDR_AUTOMATIONS_REF})"
  herdr plugin install "DnzzL/herdr-automations" --ref "$HERDR_AUTOMATIONS_REF" -y \
    || warn "herdr automations install failed (non-fatal); install manually: herdr plugin install DnzzL/herdr-automations"
}

install_herdr_terminal_browser() {
  if ! command_exists herdr; then
    warn "herdr not found; run 'herdr plugin install zenbu-labs/terminal-browser/herdr-plugin' after installing it"
    return
  fi
  if herdr plugin list 2>/dev/null | grep -q "zenbu-labs.terminal-browser\|terminal-browser"; then
    skip "herdr terminal-browser plugin already installed"
    return
  fi
  info "Installing herdr terminal-browser plugin (${HERDR_TERMINAL_BROWSER_REF})"
  herdr plugin install "zenbu-labs/terminal-browser/herdr-plugin" --ref "$HERDR_TERMINAL_BROWSER_REF" -y \
    || warn "herdr terminal-browser install failed (non-fatal); install manually: herdr plugin install zenbu-labs/terminal-browser/herdr-plugin"
}


configure_git_performance() {
  local os="${1:-$(detect_os)}"
  if ! command_exists git; then
    warn "git not found; skipping git performance configuration"
    return 0
  fi
  info "Configuring git performance defaults"
  git config --global core.preloadIndex true
  git config --global core.untrackedCache true
  git config --global feature.manyFiles true
  if [[ "$os" == "windows" ]]; then
    git config --global core.fscache true
    git config --global core.fsmonitor true
  fi
  ok "git performance defaults configured"
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

link_powershell_profile() {
  local os="${1:-$(detect_os)}"
  local xdg_profile_src="$DOTFILES_DIR/powershell/.config/powershell/Microsoft.PowerShell_profile.ps1"
  local xdg_profile_dest="$HOME/.config/powershell/Microsoft.PowerShell_profile.ps1"

  if [[ -f "$xdg_profile_src" && ! -L "$xdg_profile_dest" ]]; then
    mkdir -p "$HOME/.config/powershell"
    ln -sf "$xdg_profile_src" "$xdg_profile_dest" 2>/dev/null || cp -f "$xdg_profile_src" "$xdg_profile_dest"
  fi

  if [[ "$os" != "windows" ]]; then
    return 0
  fi

  info "Configuring PowerShell 7 profile and execution policy for Windows"
  if ! command_exists pwsh; then
    warn "pwsh not found; skipping Windows PowerShell 7 profile bootstrap"
    return 0
  fi

  local raw_profile_path unix_profile_path profile_dir
  local bootstrap_profile_src="$DOTFILES_DIR/powershell/Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
  raw_profile_path="$(pwsh -NoProfile -NoLogo -Command '$PROFILE.CurrentUserCurrentHost' 2>/dev/null | tr -d '\r')" || raw_profile_path=""
  if [[ -n "$raw_profile_path" && -f "$bootstrap_profile_src" ]]; then
    if command_exists cygpath; then
      unix_profile_path="$(cygpath -u "$raw_profile_path" 2>/dev/null || printf '%s' "$raw_profile_path")"
    else
      unix_profile_path="$raw_profile_path"
    fi
    profile_dir="$(dirname "$unix_profile_path")"
    mkdir -p "$profile_dir" 2>/dev/null || true
    if [[ ! -L "$unix_profile_path" ]]; then
      if ln -sf "$bootstrap_profile_src" "$unix_profile_path" 2>/dev/null || cp -f "$bootstrap_profile_src" "$unix_profile_path"; then
        ok "pwsh bootstrap profile deployed to $unix_profile_path"
      else
        warn "Could not write pwsh profile at $unix_profile_path"
      fi
    fi
  fi

  pwsh -NoProfile -NoLogo -Command '
    $policy = Get-ExecutionPolicy -Scope CurrentUser
    if ($policy -in @("Undefined", "Restricted")) {
      Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue
    }
  ' >/dev/null 2>&1 || warn "Could not set RemoteSigned execution policy for pwsh (non-fatal)"
  return 0
}

main() {
  local os
  os="$(detect_os)"
  info "Detected OS: $os"

  install_packages "$os"
  configure_git_performance "$os"
  install_zinit
  install_lazygit "$os"
  install_gh "$os"
  install_lazysql "$os"
  install_herdr "$os"
  install_herdr_opencode
  install_herdr_birdseye
  install_herdr_automations
  install_herdr_terminal_browser
  write_dotfiles_path
  stow_packages
  link_powershell_profile "$os"

  printf "\n\033[1;32mDone.\033[0m Remaining manual steps:\n"
  printf "  1. chsh -s %s   (set Zsh as default shell)\n" "$(command -v zsh || echo /bin/zsh)"
  printf "  2. gh auth login   (to authenticate GitHub CLI)\n"
  printf "  3. exec zsh\n"
  printf "\nTip: set CODES_DIR=/path/to/projects before running setup.sh to change the\n"
  printf "     default projects directory (currently %s).\n" "${CODES_DIR:-$HOME/Codes}"
}

main "$@"
