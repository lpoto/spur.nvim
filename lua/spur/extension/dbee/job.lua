local SpurJob = require("spur.core.job")

---@class SpurDbeeJobConfig
---@field adapter table|function
---@field configuration table|string

---@class SpurDbeeJob : SpurJob
---@field dap SpurDbeeJobConfig
local SpurDbeeJob = setmetatable({}, { __index = SpurJob })
SpurDbeeJob.__index = SpurDbeeJob
SpurDbeeJob.__type = "SpurJob"
SpurDbeeJob.__subtype = "SpurDbeeJob"
SpurDbeeJob.__metatable = SpurDbeeJob

local g_result = nil

--- Create a new SpurDbeeJob instance.
---
---@return SpurDbeeJob
function SpurDbeeJob:new()
  local opts = {
    type = "dbee",
    job = {
      cmd = "dbee",
      name = "[Dbee]",
    }
  }
  local spur_job = SpurJob:new(opts)
  local instance = setmetatable(spur_job, SpurDbeeJob)
  ---@diagnostic disable-next-line
  return instance
end

--- Check if the job is currently running.
---
---@return boolean
function SpurDbeeJob:is_running()
  if g_result == nil then
    return false
  end
  if g_result:is_exited() then
    return false
  end
  local call = self:__get_call()
  if type(call) ~= "table" then
    return false
  end
  local state = call.state
  if type(state) ~= "string" or state == "" then
    return false
  end
  if state == "archived"
      or state == "executing_failed"
      or state == "retrieving_failed"
      or state == "canceled" then
    return false
  end
  return true
end

--- Check whether this job can be run
function SpurDbeeJob:can_run()
  -- NOTE: Dbee job can never be run with "run"
  -- command. We have to navigate to query execution
  return false
end

--- Kills the job if it is running.
--- This does not delete the job's buffer.
function SpurDbeeJob:kill()
  vim.schedule(function()
    local call = self:__get_call()
    if type(call) ~= "table" or call.id == nil then
      return
    end
    pcall(function()
      local ok, api = pcall(require, "dbee.api")
      if not ok then
        return
      end
      api.core.call_cancel(call.id)
    end)
  end)
end

function SpurDbeeJob:__get_call()
  local result = self:__get_result()
  if type(result) ~= "table"
      or type(result.get_call) ~= "function"
      or result:get_call() == nil
      or not result:get_call().id then
    return nil
  end
  return result:get_call()
end

--- Kills the job if it is running and deletes the job's result.
function SpurDbeeJob:clean()
  pcall(function()
    SpurJob.clean(self)
  end)
  vim.schedule(function()
    pcall(function()
      if g_result ~= nil then
        g_result:clean()
      end
    end)
    g_result = nil
  end)
end

--- Get the buffer number associated with the job,
--- bufnr is only available after the job has been started,
--- and the job's buffer still exists.
---
--- @return number|nil
function SpurDbeeJob:get_bufnr()
  local result = self:__get_result()
  if type(result) == "table"
      and type(result:get_bufnr()) == "number"
  then
    return result:get_bufnr()
  end
  return nil
end

--- Run the job with the command specified when creating the instance.
--- The job cannot be run, if it is already running.
function SpurDbeeJob:run()
  error("SpurDbeeJob cannot be run")
end

function SpurDbeeJob:execute_query(conn, query)
  if self:is_running() then
    error("Job is already running")
  end
  if type(conn) ~= "table" or not conn.id then
    return false
  end
  if type(query) ~= "string" or query == "" then
    return false
  end
  pcall(function()
    self:clean()
  end)
  vim.schedule(function()
    g_result = require("spur.extension.dbee.result"):new(function(o) self:__on_exit(o) end)
    local api = require "dbee.api"
    local call = api.core.connection_execute(conn.id, query)
    g_result:set_call(call)
  end)
  return true
end

function SpurDbeeJob:__is_available()
  if not SpurJob.__is_available(self) then
    return false
  end
  local ok, api = pcall(require, "dbee.api")
  if not ok or type(api) ~= "table" or type(api.core) ~= "table" then
    return false
  end
  return true
end

function SpurDbeeJob:__on_exit(opts)
  vim.schedule(function()
    SpurJob.__on_exit(self, opts)
  end)
end

--- Override run to start DAP session
function SpurDbeeJob:__tostring()
  return string.format("SpurDbeeJob(%s)", self:get_name())
end

---@return SpurDbeeResult|nil
function SpurDbeeJob:__get_result()
  if (type(g_result) == "table") then
    return g_result
  end
  return nil
end

return SpurDbeeJob
