local SpurJob = require("spur.core.job")

---@class SpurDapJobConfig
---@field adapter string|table
---@field configuration table

---@class SpurDapJob : SpurJob
---@field dap SpurDapJobConfig
local SpurDapJob = setmetatable({}, { __index = SpurJob })
SpurDapJob.__index = SpurDapJob
SpurDapJob.__type = "SpurJob"
SpurDapJob.__subtype = "SpurDapJob"
SpurDapJob.__metatable = SpurDapJob

--- Create a new SpurDapJob instance.
---
---@param opts table
---@return SpurDapJob
function SpurDapJob:new(opts)
  local spur_job = SpurJob:new(opts)

  local instance = setmetatable(spur_job, SpurDapJob)

  if opts.dap == nil or type(opts.dap) ~= "table" then
    error("SpurDapJob:new expects 'dap' to be a table in options")
  end

  if opts.dap.configuration == nil or (type(opts.dap.configuration) ~= "table" and type(opts.dap.configuration) ~= "string") then
    error("SpurDapJob:new expects 'dap.configuration' to be a table in options")
  end

  if opts.dap.adapter == nil or (type(opts.dap.adapter) ~= "table" and type(opts.dap.adapter) ~= "string") then
    error("SpurDapJob:new expects 'dap.adapter' to be a table or a string in options")
  end

  instance.dap = opts.dap
  ---@diagnostic disable-next-line
  return instance
end

--- Override run to start DAP session
function SpurDapJob:run()
  local ok, dap = pcall(require, "dap")
  if not ok then
    error("[Spur.dap] DAP module not found. Please install 'mfussenegger/nvim-dap' plugin.")
  end

  if type(self.dap) ~= "table"
      or (type(self.dap.configuration) ~= "table" and type(self.dap.configuration) ~= "string")
      or (type(self.dap.adapter) ~= "table" and type(self.dap.adapter) ~= "string") then
    error("SpurDapJob:run expects 'dap' to be a table with 'adapter' and 'configuration'")
  end
  local configuration = self.dap.configuration
  if type(configuration) == "string" then
    configuration = dap.configurations[configuration]
    if not configuration then
      error("[Spur.dap] DAP configuration not found for: " .. self.dap.configuration)
    end
  end

  if type(configuration.type) ~= "string" or configuration.type == "" then
    error("SpurDapJob:run expects 'dap.configuration.type' to be a non-empty string")
  end

  local adapter = self.dap.adapter

  -- Register adapter if it's a table and not already registered
  if type(adapter) == "string" then
    local adapter_cfg = dap.adapters[adapter]
    if type(adapter_cfg) ~= "table" and type(adapter_cfg) ~= "function" then
      error("[Spur.dap] Dap adapter not found for: " .. adapter)
    end
    adapter = adapter_cfg
  else
    dap.adapters[configuration.type] = adapter
  end

  dap.run(configuration)
end

function SpurDapJob:__tostring()
  return string.format("SpurDapJob(%s)", self.name)
end

return SpurDapJob
