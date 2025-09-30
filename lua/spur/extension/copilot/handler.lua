local SpurJobHandler = require("spur.core.handler")

---@class SpurJobCopilotCliHandler : SpurJobHandler
local SpurJobCopilotCliHandler = setmetatable({}, { __index = SpurJobHandler })
SpurJobCopilotCliHandler.__index = SpurJobCopilotCliHandler
SpurJobCopilotCliHandler.__type = "SpurHandler"
SpurJobCopilotCliHandler.__subtype = "SpurJobCopilotCliHandler"
SpurJobCopilotCliHandler.__metatable = SpurJobCopilotCliHandler

function SpurJobCopilotCliHandler:new()
  local handler = SpurJobHandler:new()
  local instance = setmetatable(handler, SpurJobCopilotCliHandler)
  return instance
end

--- Check whether this handler accepts the job
---
--- @param opts table Input fields for SpurJob
--- @param action string What action the job should be accepted for
--- @return boolean
function SpurJobCopilotCliHandler:accepts_job(opts, action)
  if type(opts) ~= "table" then
    return false
  end
  -- NOTE: This handler overrides all actions
  -- of the default handler, so we accept all actions.
  if type(action) ~= "string" or action == "" then
    return false
  end
  return opts.type == "copilot-cli"
end

---@param job SpurJob
---@return table[]
function SpurJobCopilotCliHandler:__get_job_actions(job)
  local actions = SpurJobHandler.__get_job_actions(self, job)
  local new_actions = {}
  if type(actions) == "table" then
    for _, action in ipairs(actions) do
      table.insert(new_actions, action)
      if type(action) == "table" and action.value == "run" then
        table.insert(new_actions, { label = "Resume", value = "resume" })
      end
    end
  end
  return new_actions
end

function SpurJobCopilotCliHandler:__execute_job_action(job, action)
  if SpurJobHandler.__execute_job_action(self, job, action) then
    return
  end
  if type(action) == "table" and action.value == "resume" then
    vim.schedule(function()
      job:run("--resume")
      vim.schedule(function()
        if job:is_running() and not job:is_quiet() then
          self:open_job_output(job)
        end
      end)
    end)
    return true
  end
  return false
end

return SpurJobCopilotCliHandler
