return {
  {
    "norcalli/nvim-colorizer.lua",
    event = "LazyFile",
    opts = {
      filetypes = {
        "css",
        "scss",
        "html",
        "javascript",
        "typescript",
        "javascriptreact",
        "typescriptreact",
        "vue",
        "svelte",
        "astro",
        "lua",
        "toml",
        "yaml",
        "conf",
      },
      user_default_options = {
        RGB = true,
        RRGGBB = true,
        names = false,
        RRGGBBAA = true,
        rgb_fn = true,
        hsl_fn = true,
        css = true,
        css_fn = true,
        mode = "foreground",
      },
    },
    config = function(_, opts)
      require("colorizer").setup(opts.filetypes, opts.user_default_options)
    end,
  },
}
