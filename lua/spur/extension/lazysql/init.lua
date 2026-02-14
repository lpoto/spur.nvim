local M = {}

---@class SpurLazySqlCliConfig
---@field enabled boolean|nil Whether the json extension is enabled
---@field executable string|nil Custom executable for the lazysql cli

---@type SpurJob|nil
local lazysql_job = nil
local init_job


--- Set up the lazysql cli spur plugin
---
---@param config SpurLazySqlCliConfig|nil
function M.init(config)
  if config ~= nil and type(config) ~= "table" then
    error("[Spur.json] init expects a table as config")
  end
  config = config or {}
  local enabled = config.enabled == nil or config.enabled == true
  if not enabled then
    return
  end
  local cmd = "lazysql"
  if type(config.executable) == "string" and config.executable ~= "" then
    cmd = config.executable
  end
  if lazysql_job ~= nil then
    pcall(function()
      ---@diagnostic disable-next-line
      lazysql_job.job.cmd = cmd
    end)
  else
    ---@diagnostic disable-next-line
    init_job(cmd)
  end
end

---@param cmd string
function init_job(cmd)
  if type(cmd) ~= "string" or cmd == "" then
    error("[Spur.lazysql] init_job expects a non-empty string as cmd")
  end
  local handler = require "spur.extension.lazysql.handler":new()
  ---@diagnostic disable-next-line
  local last_print_time = vim.loop.now()
  local job = {
    order = -91,
    type = "lazysql",
    job = {
      name = "[LazySql]",
      cmd = cmd,
    },
    show_headers = false,
    on_exit = function()
      vim.schedule(function()
        pcall(function()
          ---@diagnostic disable-next-line
          lazysql_job:clean()
        end)
      end)
    end
  }
  local manager = require("spur.manager")
  manager.add_handler(handler)
  lazysql_job = handler:create_job(job)
  manager.add_job(lazysql_job)
end

return M
