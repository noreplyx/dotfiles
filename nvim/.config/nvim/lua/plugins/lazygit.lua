return {
  {
    "kdheepak/lazygit.nvim",
    lazy = true,
    cmd = {
      "LazyGit",
      "LazyGitConfig",
      "LazyGitCurrentFile",
      "LazyGitFilter",
      "LazyGitFilterCurrentFile",
      "LazyGitFilterAuthor",
    },
    dependencies = {
      { "nvim-lua/plenary.nvim", lazy = true },
    },
    keys = {
      {
        "<leader>gg",
        function()
          if _G.Snacks and Snacks.lazygit then
            Snacks.lazygit()
          else
            vim.cmd("LazyGit")
          end
        end,
        desc = "LazyGit",
      },
      {
        "<leader>gf",
        function()
          if _G.Snacks and Snacks.lazygit then
            Snacks.lazygit.log_file()
          else
            vim.cmd("LazyGitFilterCurrentFile")
          end
        end,
        desc = "LazyGit Current File History",
      },
    },
    init = function()
      vim.g.lazygit_floating_window_scaling_factor = 0.85
      vim.g.lazygit_use_neovim_remote = 1
    end,
  },
}
