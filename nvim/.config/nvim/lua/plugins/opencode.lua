return {
  {
    "sudo-tee/opencode.nvim",
    dependencies = {
      {
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          anti_conceal = { enabled = false },
          file_types = { "markdown", "opencode_output" },
        },
        ft = { "markdown", "opencode_output" },
      },
      "saghen/blink.cmp",
      "folke/snacks.nvim",
    },
    opts = {
      server = {
        url = "http://127.0.0.1",
        port = 4096,
      },
    },
    keys = {
      {
        "<leader>or",
        function()
          local state = require("opencode.state")
          local server_job = require("opencode.server_job")

          -- 1. Shut down the current server if one is running
          local server = state.opencode_server
          if server and server:is_running() then
            server:shutdown()
          end
          state.jobs.clear_server()

          -- 2. Start a fresh server (ensure_server() spawns or attaches)
          vim.schedule(function()
            server_job.ensure_server():and_then(function()
              vim.notify("opencode server restarted", vim.log.levels.INFO)
            end)
          end)
        end,
        desc = "Restart opencode server",
      },
    },
  },
}
