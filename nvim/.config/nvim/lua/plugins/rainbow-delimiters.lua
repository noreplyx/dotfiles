return {
  "HiPhish/rainbow-delimiters.nvim",
  event = "LazyFile",
  main = "rainbow-delimiters.setup",
  opts = {
    strategy = { [""] = "rainbow-delimiters.strategy.local" },
    query = {
      javascript = "rainbow-delimiters",
      typescript = "rainbow-delimiters",
      lua = "rainbow-delimiters",
      python = "rainbow-delimiters",
      html = "rainbow-delimiters",
    },
    blacklist = {
      "c_sharp",
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
