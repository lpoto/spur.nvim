local M = {}

---@class SpurDapConfig
---@field enabled boolean|nil Whether the dap extension is enabled

--- Support running jobs with a DAP debugger.
---@param config SpurDapConfig|nil
function M.init(config)
  if config ~= nil and type(config) ~= "table" then
    error("[Spur.dap] init expects a table as config")
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

  local handler = require "spur.extension.dap.handler":new()
  manager.add_handler(handler)
end

return M
