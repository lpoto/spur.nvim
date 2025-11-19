local M = {}

---@class SpurCopilotCliConfig
---@field enabled boolean|nil Whether the json extension is enabled
---@field executable string|nil Custom executable for the copilot cli

---@type SpurJob|nil
local copilot_job = nil
local init_job


--- Set up the copilot cli spur plugin
---
---@param config SpurCopilotCliConfig|nil
function M.init(config)
  if config ~= nil and type(config) ~= "table" then
    error("[Spur.json] init expects a table as config")
  end
  config = config or {}
  local enabled = config.enabled == nil or config.enabled == true
  if not enabled then
    return
  end
  local cmd = "copilot"
  if type(config.executable) == "string" and config.executable ~= "" then
    cmd = config.executable
  end
  if copilot_job ~= nil then
    pcall(function()
      ---@diagnostic disable-next-line
      copilot_job.job.cmd = cmd
    end)
  else
    ---@diagnostic disable-next-line
    init_job(cmd)
  end
end

---@param cmd string
function init_job(cmd)
  if type(cmd) ~= "string" or cmd == "" then
    error("[Spur.copilot] init_job expects a non-empty string as cmd")
  end
  ---@diagnostic disable-next-line
  local last_print_time = vim.loop.now()
  local job = {
    order = -90,
    type = "copilot-cli",
    job = {
      name = "[Copilot]",
      cmd = cmd,
    },
    show_headers = false,
    on_stdout = function(_, out)
      vim.schedule(function()
        if type(out) ~= "table" then
          return
        end
        local bufnr = vim.api.nvim_get_current_buf()
        if copilot_job == nil or bufnr == copilot_job:get_bufnr() then
          return
        end
        ---@diagnostic disable-next-line
        local now = vim.loop.now()
        if last_print_time + 1000 > now then
          return
        end
        for _, line in ipairs(out) do
          if string.find(line, "Confirm with number keys or ↑↓ keys and Enter, Cancel with Esc") then
            local msg = "User confirmation is required"
            if type(vim.g.display_message) == "function" then
              local config = require "spur.config"
              vim.g.display_message {
                message = msg,
                title = config.title,
              }
            end
            last_print_time = now
            local config = require "spur.config"
            vim.notify("[Copilot] " .. msg,
              vim.log.levels.INFO,
              {
                title = config.title
              })
            return
          end
        end
      end)
    end
  }
  local manager = require("spur.manager")
  local handler = require "spur.extension.copilot.handler":new()
  manager.add_handler(handler)
  copilot_job = handler:create_job(job)
  manager.add_job(copilot_job)
end

return M
