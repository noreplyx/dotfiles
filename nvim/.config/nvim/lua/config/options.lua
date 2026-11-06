-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Disable unused remote host providers to avoid executable probing overhead
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_python3_provider = 0

vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.synmaxcol = 300
vim.opt.updatetime = 250
vim.opt.swapfile = false

-- Defer clipboard provider probing (win32yank.exe) on Windows until VeryLazy
if vim.fn.has("win32") == 1 then
  if vim.fn.executable("pwsh") == 1 or vim.fn.executable("powershell") == 1 then
    vim.o.shell = vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell"
    vim.o.shellcmdflag =
      "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();$PSDefaultParameterValues['Out-File:Encoding']='utf8';Remove-Alias -Force -ErrorAction SilentlyContinue tee;"
    vim.o.shellredir = '2>&1 | %%{ "$_" } | Out-File %s; exit $LastExitCode'
    vim.o.shellpipe = '2>&1 | %%{ "$_" } | tee %s; exit $LastExitCode'
    vim.o.shellquote = ""
    vim.o.shellxquote = ""
  end

  vim.opt.clipboard = ""
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("dotfiles_win32_clipboard", { clear = true }),
    pattern = "VeryLazy",
    once = true,
    callback = function()
      vim.opt.clipboard = vim.env.SSH_TTY and "" or "unnamedplus"
    end,
  })
end

if vim.g.neovide or vim.fn.has("gui_running") == 1 then
  vim.opt.guifont = "MesloLGS Nerd Font Mono"
end
