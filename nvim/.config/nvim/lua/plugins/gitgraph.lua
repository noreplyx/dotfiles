return {
  {
    "isakbm/gitgraph.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
    },
    ---@type I.GGConfig
    opts = {
      hooks = {
        on_select_commit = function(commit)
          vim.cmd(":DiffviewOpen " .. commit.hash .. "^!")
        end,
        on_select_range_commit = function(from, to)
          vim.cmd(":DiffviewOpen " .. from.hash .. "~1.." .. to.hash)
        end,
      },
    },
    keys = {
      {
        "<leader>gl",
        function()
          require("gitgraph").draw({}, { all = true, max_count = 5000 })
        end,
        desc = "GitGraph",
      },
    },
    config = function(_, opts)
      require("gitgraph").setup(opts)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "gitgraph",
        callback = function()
          vim.keymap.set("n", "q", "<cmd>bdelete<cr>", { buffer = true, desc = "Close GitGraph" })
        end,
      })
    end,
  },
}
