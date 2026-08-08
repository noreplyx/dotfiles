-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.number = true
vim.opt.relativenumber = false
if vim.g.neovide or vim.fn.has("gui_running") == 1 then
  vim.opt.guifont = "MesloLGS Nerd Font Mono"
end
