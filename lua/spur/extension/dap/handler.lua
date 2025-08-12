local SpurJobHandler = require("spur.core.handler")

---@class SpurJobDapHandler : SpurJobHandler
local SpurJobDapHandler = setmetatable({}, { __index = SpurJobHandler })
SpurJobDapHandler.__index = SpurJobDapHandler
SpurJobDapHandler.__type = "SpurHandler"
SpurJobDapHandler.__subtype = "SpurJobDapHandler"
SpurJobDapHandler.__metatable = SpurJobDapHandler

function SpurJobDapHandler:new()
  local handler = SpurJobHandler:new()
  local instance = setmetatable(handler, SpurJobDapHandler)
  return instance
end

--- Check whether this handler accepts the job
---
--- @param opts table Input fields for SpurJob
--- @return boolean
function SpurJobDapHandler:accepts_job(opts)
  if type(opts) ~= "table" then
    return false
  end
  if type(opts.dap) ~= "table" then
    return false
  end
  if type(opts.job) == "table" then
    return opts.job.cmd == "dap"
  end
  return true
end

---@param o table Input fields for SpurJob
---@return SpurJob
function SpurJobDapHandler:create_job(o)
  return require "spur.extension.dap.job":new(o)
end

---@param job SpurDapJob
---@return table[]
function SpurJobDapHandler:__get_job_actions(job)
  local actions = {}
  if job:is_stopped() then
    table.insert(actions, { label = "Continue", value = "continue" })
  end
  local existing = SpurJobHandler.__get_job_actions(self, job)
  if type(existing) == "table" then
    for _, action in ipairs(existing) do
      table.insert(actions, action)
    end
  end
  return actions
end

---@param job SpurDapJob
---@param action table
function SpurJobDapHandler:__execute_job_action(job, action)
  if type(action) ~= "table" then
    return
  end
  local r = SpurJobHandler.__execute_job_action(self, job, action)
  if r == true then
    return r
  end
  if action.value == "continue" then
    job:continue()
    if not job:is_quiet() then
      self:open_job_output(job)
    end
    return true
  end
  return false
end

return SpurJobDapHandler
