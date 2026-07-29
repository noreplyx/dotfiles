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
  },
}
