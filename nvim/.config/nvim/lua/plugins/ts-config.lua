local eslint_config_files = {
  ".eslintrc",
  ".eslintrc.js",
  ".eslintrc.cjs",
  ".eslintrc.yaml",
  ".eslintrc.yml",
  ".eslintrc.json",
  "eslint.config.js",
  "eslint.config.mjs",
  "eslint.config.cjs",
  "eslint.config.ts",
  "eslint.config.mts",
  "eslint.config.cts",
}

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        eslint = {
          root_dir = function(buffer_or_filename, on_root_dir)
            local root = vim.fs.root(buffer_or_filename, eslint_config_files)
            if root and type(on_root_dir) == "function" then
              on_root_dir(root)
            end
            return root
          end,
          settings = {
            workingDirectories = { mode = "auto" },
            format = false,
          },
        },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters = opts.formatters or {}
      opts.formatters["eslint"] = {
        require_cwd = true,
        cwd_file = eslint_config_files,
      }
    end,
  },
}
