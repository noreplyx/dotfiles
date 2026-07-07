return {
  "HiPhish/rainbow-delimiters.nvim",
  config = function()
    local rainbow = require("rainbow-delimiters")
    vim.g.rainbow_delimiters = {
      strategy = rainbow.strategy.global,
      query = {
        javascript = "rainbow-delimiters",
        typescript = "rainbow-delimiters",
        lua = "rainbow-delimiters",
        python = "rainbow-delimiters",
        html = "rainbow-delimiters",
      },
      highlight = {
        "RainbowDelimiterRed",
        "RainbowDelimiterYellow",
        "RainbowDelimiterBlue",
        "RainbowDelimiterOrange",
        "RainbowDelimiterGreen",
        "RainbowDelimiterViolet",
        "RainbowDelimiterCyan",
      },
    }
  end,
}
