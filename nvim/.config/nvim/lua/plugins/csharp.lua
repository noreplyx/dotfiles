local mason_registries = {
  "github:mason-org/mason-registry",
  "github:Crashdummyy/mason-registry",
}

local mason_tools = {
  "roslyn",
  "csharpier",
  "netcoredbg",
}

local treesitter_parsers = {
  "c_sharp",
  "xml",
}

local roslyn_lsp_settings = {
  ["csharp|background_analysis"] = {
    dotnet_analyzer_diagnostics_scope = "fullSolution",
    dotnet_compiler_diagnostics_scope = "fullSolution",
  },
  ["csharp|inlay_hints"] = {
    csharp_enable_inlay_hints_for_implicit_object_creation = true,
    csharp_enable_inlay_hints_for_implicit_variable_types = true,
    csharp_enable_inlay_hints_for_lambda_parameter_types = true,
    csharp_enable_inlay_hints_for_types = true,
    dotnet_enable_inlay_hints_for_indexer_parameters = true,
    dotnet_enable_inlay_hints_for_literal_parameters = true,
    dotnet_enable_inlay_hints_for_object_creation_parameters = true,
    dotnet_enable_inlay_hints_for_other_parameters = true,
    dotnet_enable_inlay_hints_for_parameters = true,
    dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix = true,
    dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,
    dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent = true,
  },
  ["csharp|code_lens"] = {
    dotnet_enable_references_code_lens = true,
    dotnet_enable_tests_code_lens = true,
  },
  ["csharp|completion"] = {
    dotnet_provide_regex_completions = true,
    dotnet_show_completion_items_from_unimported_namespaces = true,
    dotnet_show_name_completion_suggestions = true,
  },
  ["csharp|symbol_search"] = {
    dotnet_search_reference_assemblies = true,
  },
}

return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      local dotnet = require("util.dotnet")
      opts.registries = dotnet.append_unique_items(opts.registries, mason_registries)
      opts.ensure_installed = dotnet.append_unique_items(opts.ensure_installed, mason_tools)
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      local dotnet = require("util.dotnet")
      opts.ensure_installed = dotnet.append_unique_items(opts.ensure_installed, treesitter_parsers)
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        omnisharp = { enabled = false },
        fsautocomplete = { enabled = false },
      },
    },
  },
  {
    "seblyng/roslyn.nvim",
    ft = "cs",
    opts = {
      broad_search = true,
    },
    config = function(_, opts)
      if vim.lsp and vim.lsp.config then
        vim.lsp.config("roslyn", {
          settings = roslyn_lsp_settings,
        })
      end

      local loaded, roslyn = pcall(require, "roslyn")
      if not loaded then
        vim.notify(
          "roslyn.nvim is not installed on disk yet; run :Lazy sync to complete C# LSP setup.",
          vim.log.levels.WARN,
          { title = "C# LSP" }
        )
        return
      end

      roslyn.setup(opts)
    end,
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        cs = { "csharpier", lsp_format = "fallback" },
      },
    },
  },
  {
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      local dap = require("dap")
      local dotnet = require("util.dotnet")
      local netcoredbg_adapter = {
        type = "executable",
        command = dotnet.resolve_netcoredbg_executable(),
        args = { "--interpreter=vscode" },
      }

      dap.adapters.netcoredbg = netcoredbg_adapter
      dap.adapters.coreclr = netcoredbg_adapter

      dap.listeners.on_config["csharp_netcoredbg"] = function(config)
        return dotnet.apply_default_working_directory(config)
      end

      dap.configurations.cs = {
        {
          type = "netcoredbg",
          name = "Launch - netcoredbg (Build & Pick DLL)",
          request = "launch",
          program = dotnet.select_and_build_dotnet_dll,
        },
        {
          type = "netcoredbg",
          name = "Attach - netcoredbg (Pick Process)",
          request = "attach",
          processId = require("dap.utils").pick_process,
        },
      }
    end,
  },
}
