local M = {}

--- Support running jobs with a DAP debugger.
function M.init()
  local manager = require "spur.manager"
  if not manager.is_initialized() then
    manager.init()
  end

  local handler = require "spur.extension.dap.handler":new()
  manager.add_handler(handler)
end

return M
