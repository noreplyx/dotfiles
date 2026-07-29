return {
  {
    "saghen/blink.cmp",
    opts = {
      cmdline = {
        completion = {
          menu = {
            auto_show = function(ctx)
              return vim.fn.getcmdtype() == ":"
            end,
          },
        },
      },
    },
  },
}
