local M = {}

---@class SpurLazyGitCliConfig
---@field enabled boolean|nil Whether the json extension is enabled
---@field executable string|nil Custom executable for the lazygit cli

---@type SpurJob|nil
local lazygit_job = nil
local init_job


--- Set up the lazygit cli spur plugin
---
---@param config SpurLazyGitCliConfig|nil
function M.init(config)
  if config ~= nil and type(config) ~= "table" then
    error("[Spur.json] init expects a table as config")
  end
  config = config or {}
  local enabled = config.enabled == nil or config.enabled == true
  if not enabled then
    return
  end
  local cmd = "lazygit"
  if type(config.executable) == "string" and config.executable ~= "" then
    cmd = config.executable
  end
  if lazygit_job ~= nil then
    pcall(function()
      ---@diagnostic disable-next-line
      lazygit_job.job.cmd = cmd
    end)
  else
    ---@diagnostic disable-next-line
    init_job(cmd)
  end
end

---@param cmd string
function init_job(cmd)
  if type(cmd) ~= "string" or cmd == "" then
    error("[Spur.lazygit] init_job expects a non-empty string as cmd")
  end
  local handler = require "spur.extension.lazygit.handler":new()
  ---@diagnostic disable-next-line
  local last_print_time = vim.loop.now()
  local job = {
    order = -90,
    type = "lazygit",
    job = {
      name = "[LazyGit]",
      cmd = cmd,
    },
    show_headers = false,
    on_exit = function()
      vim.schedule(function()
        pcall(function()
          ---@diagnostic disable-next-line
          lazygit_job:clean()
        end)
      end)
    end
  }
  local manager = require("spur.manager")
  manager.add_handler(handler)
  lazygit_job = handler:create_job(job)
  manager.add_job(lazygit_job)
end

return M
