# Spur.nvim

### Example config (lazy.nvim)
```lua
return {
  "lpoto/spur.nvim",
  dependencies = {
    {
      "mfussenegger/nvim-dap",
      cmd = { "DapToggleBreakpoint" },
      tag = "0.10.0"
    },
  },
  keys = {
    { "<leader>s", function() require "spur".select_job() end },
    { "<leader>o", function() require "spur".toggle_output() end },
    { "<leader>d", function() require "spur".toggle_output() end },
  },
  opts = {
    extensions = {
      "dap",
      "makefile",
      "json",
    }
  }
}
```
