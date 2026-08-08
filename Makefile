PACKAGES = zsh tmux starship nvim yazi lazygit lazysql
TARGET   = $(HOME)

.PHONY: install uninstall restow

install:
	stow -t $(TARGET) $(PACKAGES)

uninstall:
	stow -D -t $(TARGET) $(PACKAGES)

restow:
	stow -R -t $(TARGET) $(PACKAGES)
