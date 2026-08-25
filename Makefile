PACKAGES = zsh tmux starship nvim yazi lazygit lazysql herdr
TARGET   = $(HOME)
DOTFILES_DIR = $(shell pwd)
CODES_DIR ?= $(HOME)/Codes

.PHONY: install uninstall restow path

path:
	mkdir -p $(TARGET)/.config/dotfiles
	printf 'DOTFILES_DIR="%s"\nCODES_DIR="%s"\n' "$(DOTFILES_DIR)" "$(CODES_DIR)" > $(TARGET)/.config/dotfiles/path

install: path
	stow -t $(TARGET) $(PACKAGES)

uninstall:
	stow -D -t $(TARGET) $(PACKAGES)

restow: path
	stow -R -t $(TARGET) $(PACKAGES)
