return {
  {
    "folke/edgy.nvim",
    event = "VeryLazy",
    opts = {
      left = {
        "aerial",
        "neo-tree",
        "neotest-summary",
      },
      right = {
        "dbui",
        "grug-far",
        "diffview",
      },
      bottom = {
        "trouble",
        "qf",
        "snacks_terminal",
        "help",
        "neotest-output-panel",
      },
      keys = {
        ["<c-q>"] = false,
      },
    },
  },
}
