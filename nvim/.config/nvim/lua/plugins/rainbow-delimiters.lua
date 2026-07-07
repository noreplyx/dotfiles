return {
  "HiPhish/rainbow-delimiters.nvim",
  main = "rainbow-delimiters.setup",
  opts = {
    strategy = { [""] = "rainbow-delimiters.strategy.global" },
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
  },
}
