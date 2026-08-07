return {
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    keys = {
      { "<leader>tf", "<cmd>ToggleTerm<cr>", desc = "Toggle floating terminal" },
    },
    opts = {
      size = 20,
      open_mapping = [[<c-\>]],
      hide_numbers = true,
      shade_terminals = true,
      shading_factor = 2,
      start_in_insert = true,
      insert_mappings = true,
      terminal_mappings = true,
      direction = "float",
      close_on_exit = true,
      float_opts = {
        border = "curved",
      },
    },
  },
}
