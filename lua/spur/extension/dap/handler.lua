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
    table.insert(actions, { label = "Step Over", value = "step_over" })
    table.insert(actions, { label = "Step Into", value = "step_into" })
    table.insert(actions, { label = "Step Out", value = "step_out" })
    table.insert(actions, { label = "Scopes", value = "scopes" })
    table.insert(actions, { label = "Frames", value = "frames" })
    table.insert(actions, { label = "Threads", value = "threads" })
    if job:supports_step_back() then
      table.insert(actions, { label = "Step Back", value = "step_back" })
    end
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
  if action.value == "step_over"
      or action.value == "scopes"
      or action.value == "frames"
      or action.value == "threads"
      or action.value == "step_into"
      or action.value == "step_out"
      or action.value == "step_back" then
    if type(job[action.value]) == "function" then
      local winids = vim.api.nvim_list_wins()
      local config = require "spur.config"
      for _, winid in ipairs(winids) do
        local buf = vim.api.nvim_win_get_buf(winid)
        if vim.bo[buf].filetype == config.filetype then
          pcall(function()
            vim.api.nvim_win_close(winid, true)
          end)
        end
      end
      job[action.value](job)
      return true
    end
    return false
  end
  if action.value == "step_over" then
    job:step_over()
    if not job:is_quiet() then
      self:open_job_output(job)
    end
    return true
  end
  return false
end

return SpurJobDapHandler
