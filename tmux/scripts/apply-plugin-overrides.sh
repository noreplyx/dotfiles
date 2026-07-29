#!/usr/bin/env bash
# Symlink dotfiles-managed plugin overrides into ~/.tmux/plugins/
# Run this after TPM install/update (prefix+I)

DOTFILES_PLUGINS="$HOME/Codes/dotfiles/tmux/plugins"
TMUX_PLUGINS="$HOME/.tmux/plugins"

shopt -s globstar

for plugin_dir in "$DOTFILES_PLUGINS"/*/; do
  plugin_name=$(basename "$plugin_dir")
  target_dir="$TMUX_PLUGINS/$plugin_name"
  if [ -d "$target_dir" ]; then
    for file in "$plugin_dir"**/*; do
      if [ -f "$file" ]; then
        rel_path="${file#$plugin_dir}"
        ln -sf "$file" "$target_dir/$rel_path"
      fi
    done
  fi
done
