local M = {}

---@class SpurDbeeConfig
---@field enabled boolean|nil Whether the dbee extension is enabled

---@param config SpurDbeeConfig|nil
function M.init(config)
  if config ~= nil and type(config) ~= "table" then
    error("[Spur.dbee] init expects a table as config")
  end
  config = config or {}
  local enabled = config.enabled == nil or config.enabled == true
  if not enabled then
    return
  end
  if M.__inititalized then
    return
  end
  M.__inititalized = true

  local manager = require "spur.manager"
  if not manager.is_initialized() then
    manager.init()
  end
  local handler = require "spur.extension.dbee.handler":new()
  manager.add_handler(handler)

  manager.add_job({ dbee = true })
end

return M
