local SpurJobHandler = require("spur.core.handler")

---@class SpurJobTerminalHandler : SpurJobHandler
local SpurJobTerminalHandler = setmetatable({}, { __index = SpurJobHandler })
SpurJobTerminalHandler.__index = SpurJobTerminalHandler
SpurJobTerminalHandler.__type = "SpurHandler"
SpurJobTerminalHandler.__subtype = "SpurJobTerminalHandler"
SpurJobTerminalHandler.__metatable = SpurJobTerminalHandler

function SpurJobTerminalHandler:new()
  local handler = SpurJobHandler:new()
  local instance = setmetatable(handler, SpurJobTerminalHandler)
  return instance
end

--- Check whether this handler accepts the job
---
--- @param opts table Input fields for SpurJob
--- @param action string What action the job should be accepted for
--- @return boolean
function SpurJobTerminalHandler:accepts_job(opts, action)
  if type(opts) ~= "table" then
    return false
  end
  -- NOTE: This handler overrides all actions
  -- of the default handler, so we accept all actions.
  if type(action) ~= "string" or action == "" then
    return false
  end
  return opts.type == "terminal"
end

---@return SpurJob
function SpurJobTerminalHandler:create_job()
  return require "spur.extension.terminal.job":new()
end

return SpurJobTerminalHandler
