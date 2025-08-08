local M = {}

--- Support running jobs with a DAP debugger.
function M.init()
  local manager = require "spur.core.manager"

  -- Register a custom initializer, so that jobs
  -- with "DAP" cmd are initialized differently,
  -- with the dap job.
  manager.__add_job_initializer(function(opts)
    if type(opts) ~= "table" or (opts.cmd ~= "dap" and opts.cmd ~= "dap") then
      return nil
    end
    return require("spur.extension.dap.job"):new(opts)
  end)
end

return M
