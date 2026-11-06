return {
  {
    "ThePrimeagen/git-worktree.nvim",
    lazy = true,
    dependencies = {
      { "nvim-lua/plenary.nvim", lazy = true },
      { "nvim-telescope/telescope.nvim", lazy = true },
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
      {
        "<leader>gw",
        function()
          require("telescope").extensions.git_worktree.git_worktrees()
        end,
        desc = "Git Worktrees",
      },
      {
        "<leader>gW",
        function()
          require("telescope").extensions.git_worktree.create_git_worktree()
        end,
        desc = "Git Create Worktree",
      },
    },
  },
}
