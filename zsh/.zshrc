# Created by newuser for 5.9

### Added by Zinit's installer
if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
    print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
    command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
    command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" && \
        print -P "%F{33} %F{34}Installation successful.%f%b" || \
        print -P "%F{160} The clone has failed.%f%b"
fi

source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"

autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# Load a few important annexes, without Turbo
# (this is currently required for annexes)
zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust

### End of Zinit's installer chunk

### ===== TURBO MODE PLUGINS =====

# autosuggestions (เดาคำสั่ง)
zinit ice wait"0" lucid atload"_zsh_autosuggest_start"
zinit light zsh-users/zsh-autosuggestions

# completions เพิ่มเติม
zinit ice wait"0" lucid
zinit light zsh-users/zsh-completions

# fzf-tab (Tab UI)
zinit ice wait"0" lucid
zinit light Aloxaf/fzf-tab

# syntax highlight (ต้องท้ายสุด)
zinit ice wait"0"
zinit light zsh-users/zsh-syntax-highlighting

autoload -Uz compinit
() {
  setopt local_options extended_glob
  if [[ ! -f ~/.zcompdump || -n ~/.zcompdump(#qN.mh+24) ]]; then
    compinit && touch ~/.zcompdump
  else
    compinit -C
  fi
  if [[ -f ~/.zcompdump && ( ! -f ~/.zcompdump.zwc || ~/.zcompdump -nt ~/.zcompdump.zwc ) ]]; then
    { zcompile ~/.zcompdump } &!
  fi
}

_zsh_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
command mkdir -p "$_zsh_cache_dir" 2>/dev/null || true

_zsh_source_cached_init() {
  local tool_name="$1"
  command -v "$tool_name" >/dev/null 2>&1 || return 0
  local tool_binary="${commands[$tool_name]:-$(command -v "$tool_name")}"
  local init_cache="$_zsh_cache_dir/${tool_name}-init.zsh"
  if [[ ! -r "$init_cache" || "$tool_binary" -nt "$init_cache" ]]; then
    "$tool_name" init zsh > "$init_cache" 2>/dev/null || rm -f "$init_cache"
  fi
  [[ -r "$init_cache" ]] && source "$init_cache"
}

_zsh_source_cached_init zoxide
unfunction _zsh_source_cached_init

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

# local binaries
export PATH="$HOME/.local/bin:$PATH"

# Homebrew (portable: Linuxbrew vs macOS / generic PATH)
if [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -x "/opt/homebrew/bin/brew" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
fi

# Per-machine overrides (gitignored). Put machine-specific PATHs here,
# e.g. flutter, Antigravity CLI, etc.
if [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi
