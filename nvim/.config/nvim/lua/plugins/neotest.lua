return {
  {
    "nvim-neotest/neotest",
    lazy = true,
    dependencies = {
      { "nvim-neotest/neotest-jest", lazy = true },
      { "marilari88/neotest-vitest", lazy = true },
    },
    opts = {
      adapters = {
        ["neotest-jest"] = {},
        ["neotest-vitest"] = {},
      },
    },
  },
}
