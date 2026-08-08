PACKAGES = zsh tmux starship nvim yazi lazygit lazysql
TARGET   = $(HOME)
DOTFILES_DIR = $(shell pwd)

.PHONY: install uninstall restow path

path:
	mkdir -p $(TARGET)/.config/dotfiles
	printf 'DOTFILES_DIR="%s"\n' "$(DOTFILES_DIR)" > $(TARGET)/.config/dotfiles/path

install: path
	stow -t $(TARGET) $(PACKAGES)

uninstall:
	stow -D -t $(TARGET) $(PACKAGES)

restow: path
	stow -R -t $(TARGET) $(PACKAGES)
