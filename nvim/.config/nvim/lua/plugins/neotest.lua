return {
  {
    "nvim-neotest/neotest",
    lazy = true,
    dependencies = {
      { "nvim-neotest/neotest-jest", lazy = true },
      { "marilari88/neotest-vitest", lazy = true },
      { "Nsidorenco/neotest-vstest", lazy = true },
    },
    opts = {
      adapters = {
        ["neotest-jest"] = {},
        ["neotest-vitest"] = {},
        ["neotest-vstest"] = {
          dap_settings = {
            type = "netcoredbg",
          },
          filter_dir = function(directory_name)
            return require("util.dotnet").is_searchable_test_directory(directory_name)
          end,
        },
      },
    },
  },
}
