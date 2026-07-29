return {
  {
    "ThePrimeagen/git-worktree.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
    },
    opts = {
      change_directory_command = "cd",
      update_on_change = true,
      update_on_change_command = "e .",
      clearjumps_on_change = true,
      autopush = false,
    },
    config = function(_, opts)
      require("git-worktree").setup(opts)
      require("telescope").load_extension("git_worktree")
    end,
    keys = {
      { "<leader>gw", "<cmd>lua require('telescope').extensions.git_worktree.git_worktrees()<cr>", desc = "Git Worktrees" },
      { "<leader>gW", "<cmd>lua require('telescope').extensions.git_worktree.create_git_worktree()<cr>", desc = "Git Create Worktree" },
    },
  },
}
