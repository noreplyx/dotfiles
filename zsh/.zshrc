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
compinit -C
eval "$(starship init zsh)"
