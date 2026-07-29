#!/usr/bin/env bash
# Symlink dotfiles-managed plugin overrides into ~/.tmux/plugins/
# Run this after TPM install/update (prefix+I)

DOTFILES_PLUGINS="$HOME/Codes/dotfiles/tmux/plugins"
TMUX_PLUGINS="$HOME/.tmux/plugins"

for plugin_dir in "$DOTFILES_PLUGINS"/*/; do
  plugin_name=$(basename "$plugin_dir")
  target_dir="$TMUX_PLUGINS/$plugin_name"
  if [ -d "$target_dir" ]; then
    find "$plugin_dir" -type f -exec sh -c '
      p="$1"; t="$2"; shift 2
      for f; do ln -sf "$f" "$t/${f#$p}"; done
    ' sh "$plugin_dir" "$target_dir" {} +
  fi
done
