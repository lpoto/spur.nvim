local M = {}

---@class SpurCopilotCliConfig
---@field enabled boolean|nil Whether the json extension is enabled
---@field model string|nil Which model to use for the copilot cli
---@field executable string|nil Custom executable for the copilot cli
---@field log_level string|nil Log level for the copilot cli (debug, info, warn, error, none)

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
  if type(config.model) == "string" and config.model ~= "" then
    cmd = cmd .. " --model " .. config.model
  end
  if type(config.log_level) == "string" and config.log_level ~= "" then
    cmd = cmd .. " --log-level " .. config.log_level
  else
    cmd = cmd .. " --log-level error"
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
  local job = {
    order = -90,
    type = "copilot-cli",
    job = {
      name = "[Copilot]",
      cmd = cmd,
    },
    ---@diagnostic disable-next-line
  }
  local manager = require("spur.manager")
  local handler = require "spur.extension.copilot.handler":new()
  manager.add_handler(handler)
  copilot_job = handler:create_job(job)
  manager.add_job(copilot_job)
end

return M
