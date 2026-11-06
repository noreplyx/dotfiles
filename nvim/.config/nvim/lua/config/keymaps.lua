-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>fth", function()
  for _, window_id in ipairs(vim.api.nvim_list_wins()) do
    local buffer_id = vim.api.nvim_win_get_buf(window_id)
    if vim.bo[buffer_id].filetype == "snacks_terminal" then
      vim.api.nvim_win_close(window_id, true)
    end
  end
end, { desc = "Hide All Terminals" })
