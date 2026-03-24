local SpurJob = require("spur.core.job")

---@class SpurDapJobConfig
---@field adapter table|function
---@field configuration table|string

---@class SpurDapJob : SpurJob
---@field dap SpurDapJobConfig
local SpurDapJob = setmetatable({}, { __index = SpurJob })
SpurDapJob.__index = SpurDapJob
SpurDapJob.__type = "SpurJob"
SpurDapJob.__subtype = "SpurDapJob"
SpurDapJob.__metatable = SpurDapJob

local id = nil
local buf = nil
local session = nil

--- Create a new SpurDapJob instance.
---
---@param opts table
---@return SpurDapJob
function SpurDapJob:new(opts)
  if type(opts) ~= "table" then
    opts = {
      type = "dap"
    }
  end
  if opts.dap == nil or type(opts.dap) ~= "table" then
    error("SpurDapJob:new expects 'dap' to be a table in options")
  end

  if opts.dap.configuration == nil or (type(opts.dap.configuration) ~= "table" and type(opts.dap.configuration) ~= "string") then
    error("SpurDapJob:new expects 'dap.configuration' to be a table in options")
  end
  if type(opts.dap.configuration) == "table" then
    if type(opts.dap.configuration.type) ~= "string" or opts.dap.configuration.type == "" then
      error("SpurDapJob:new expects 'dap.configuration.type' to be a non-empty string in options")
    end
  end
  if opts.dap.adapter ~= nil
      and type(opts.dap.adapter) ~= "table"
      and type(opts.dap.adapter) ~= "function" then
    error("SpurDapJob:new expects 'dap.adapter' to be a table or a function in options if provided")
  end
  local name = opts.name

  -- NOTE: We set adapters to dap here,
  -- so that they may be reused in jobs.
  local ok, dap = pcall(require, "dap")
  if ok then
    local config = nil
    if type(opts.dap.configuration) == "string" then
      config = type(dap.configurations) == "table" and
          dap.configurations[opts.dap.configuration]
      if type(config) ~= "table" then
        error("[Spur.dap] DAP configuration not found for: " .. opts.dap.configuration)
      end
    elseif type(opts.dap.configuration) == "table" then
      config = opts.dap.configuration
    end
    if type(config) ~= "table" then
      error(
        "SpurDapJob:new expects 'dap.configuration' to be a table or a string that resolves to a table in options")
    end
    if type(config.type) ~= "string" then
      error("SpurDapJob:new expects 'dap.configuration.type' to be a string in options")
    end
    if type(name) ~= "string" or name == "" then
      if type(config.name) ~= "string" or config.name == "" then
        error("SpurDapJob:new expects 'dap.configuration.name' to be a non-empty string in options")
      end
      name = config.name
    end
    if opts.dap.adapter == nil then
      local adapter = type(dap.adapters) == "table"
          and type(config.type) == "string"
          and dap.adapters[config.type] or nil
      if type(adapter) ~= "table" and type(adapter) ~= "function" then
        error("[Spur.dap] DAP adapter not found for: " .. config.type)
      end
    elseif type(config.type) == "string" then
      local adapter = type(dap.adapters) == "table" and dap.adapters[config.type] or nil
      if (type(opts.dap.adapter) == "table" or type(opts.dap.adapter) == "function") and adapter == nil then
        if type(dap.adapters) ~= "table" then
          dap.adapters = {}
        end
        dap.adapters[config.type] = opts.dap.adapter
      end
    end
  end

  opts.job = {
    cmd = "dap",
    name = name,
  }
  local spur_job = SpurJob:new(opts)

  local instance = setmetatable(spur_job, SpurDapJob)

  instance.dap = opts.dap
  ---@diagnostic disable-next-line
  return instance
end

local function is_any_running()
  if type(session) ~= "table" or type(id) ~= "number" then
    return false
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    return false
  end
  local local_session = dap.session()
  return type(local_session) == "table" and session.id == local_session.id
end

--- Check if the job is currently running.
---
---@return boolean
function SpurDapJob:is_running()
  if id ~= self:get_id() then
    return false
  end
  return is_any_running()
end

--- Check if the job is currently processing.
--- Might be either running or just waiting to start the run.
---
---@return boolean
function SpurDapJob:is_processing()
  return id ~= nil and id == self:get_id()
end

--- Check if the job can be restarted.
function SpurDapJob:can_restart()
  return self:is_running()
end

--- Check whether this job can be run
function SpurDapJob:can_run()
  if id ~= nil and buf == nil then
    return false
  end
  if not SpurJob.can_run(self) then
    return false
  end
  if is_any_running() then
    return false
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    return false
  end
  local local_session = dap.session()
  if local_session == nil or local_session.closed == true then
    return true
  end
  if session == nil then
    return false
  end
  return session.id == local_session.id
end

local killed = {}

--- Kills the job if it is running.
--- This does not delete the job's buffer.
function SpurDapJob:kill(flag)
  if session == nil then
    return
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    return
  end
  local local_session = dap.session()
  if local_session == nil or local_session.id ~= session.id then
    return
  end
  killed[self:get_id()] = true
  vim.schedule(function()
    if flag == "restart" then
      local key = "Spur.Dap." .. self:get_id()
      dap.listeners.after.disconnect[key] = function()
        dap.listeners.after.disconnect[key] = nil
        vim.defer_fn(function()
          self:run()
        end, 250)
      end
    end
    dap.terminate()
  end)
end

function SpurDapJob:clean()
  SpurJob.clean(self)
  vim.schedule(function()
    buf = nil
    id = nil
    session = nil
  end)
end

--- Continues the job if it has been stopped.
function SpurDapJob:continue()
  self:__execute_stopped_session_call(function(dap)
    dap.continue({ new = false })
  end)
end

function SpurDapJob:step_over()
  self:__execute_stopped_session_call(function(dap)
    dap.step_over()
  end)
end

function SpurDapJob:step_into()
  self:__execute_stopped_session_call(function(dap)
    dap.step_into()
  end)
end

function SpurDapJob:step_out()
  self:__execute_stopped_session_call(function(dap)
    dap.step_out()
  end)
end

function SpurDapJob:step_back()
  self:__execute_stopped_session_call(function(dap)
    dap.step_back()
  end)
end

function SpurDapJob:scopes()
  self:__execute_stopped_session_call(function()
    self:__get_widget("scopes"):open()
  end)
end

function SpurDapJob:frames()
  self:__execute_stopped_session_call(function()
    self:__get_widget("frames"):open()
  end)
end

function SpurDapJob:threads()
  self:__execute_stopped_session_call(function()
    self:__get_widget("threads"):open()
  end)
end

function SpurDapJob:supports_step_back()
  if session == nil then
    return
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    return
  end
  local local_session = dap.session()
  if local_session == nil
      or local_session.id ~= session.id
      or local_session.stopped_thread_id == nil
  then
    return
  end
  return local_session.capabilities.supportsStepBack == true
end

function SpurDapJob:is_stopped()
  if not self:is_running() then
    return false
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    return false
  end
  local local_session = dap.session()
  if type(local_session) == "table" and local_session.stopped_thread_id then
    return true
  end
  return false
end

--- Get the buffer number associated with the job,
--- bufnr is only available after the job has been started,
--- and the job's buffer still exists.
---
--- @return number|nil
function SpurDapJob:get_bufnr()
  if type(buf) == "number"
      and id == self:get_id()
  then
    return buf
  end
  return nil
end

--- Get the status associated with the job.
---
---@return string|nil
function SpurDapJob:get_status()
  local status = SpurJob.get_status(self)
  if status == "Running" then
    local ok, dap = pcall(require, "dap")
    if not ok then
      return
    end
    local local_session = dap.session()
    if type(local_session) == "table" and local_session.stopped_thread_id then
      return "Stopped"
    end
  end
  if status ~= nil then
    return status
  end
  if session == nil and id ~= nil and id == self:get_id() then
    return "Waiting"
  end
  return nil
end

--- Run the job with the command specified when creating the instance.
--- The job cannot be run, if it is already running.
function SpurDapJob:run()
  vim.schedule(function()
    self:__start_job()
  end)
end

function SpurDapJob:__execute_stopped_session_call(call)
  if type(call) ~= "function" then
    return
  end
  if session == nil then
    return
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    return
  end
  local local_session = dap.session()
  if local_session == nil
      or local_session.id ~= session.id
      or local_session.stopped_thread_id == nil
  then
    return
  end
  call(dap, local_session)
end

--- Override run to start DAP session
function SpurDapJob:__tostring()
  return string.format("SpurDapJob(%s)", self:get_name())
end

---@param kind string
---@return SpurDapWidget
function SpurDapJob:__get_widget(kind)
  return require("spur.extension.dap.widget"):new(kind, self)
end

function SpurDapJob:__start_job()
  if not self:can_run() then
    error("SpurDapJob:run cannot be run at this time")
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    error("[Spur.dap] DAP module not found. Please install 'mfussenegger/nvim-dap' plugin.")
  end

  if type(self.dap) ~= "table"
      or (type(self.dap.configuration) ~= "table" and type(self.dap.configuration) ~= "string")
      or (self.dap.adapter ~= nil and type(self.dap.adapter) ~= "table") then
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

  local previous_adapter = nil
  local did_set_adapter = false

  -- Register adapter if it's a table and not already registered
  if type(self.dap.adapter) == "table" then
    previous_adapter = nil
    if type(dap.adapters) == "table" then
      previous_adapter = dap.adapters[configuration.type]
    end
    did_set_adapter = true
    dap.adapters[configuration.type] = self.dap.adapter
  else
    local adapter_cfg = dap.adapters[configuration.type]
    if type(adapter_cfg) ~= "table" and type(adapter_cfg) ~= "function" then
      error("[Spur.dap] Dap adapter not found for: " .. configuration.type)
    end
  end
  local key = "Spur.Dap." .. self:get_id()
  local settings = dap.defaults[configuration.type]
  local old_f_value = type(settings) == "table" and settings.terminal_win_cmd

  local did_exit = false
  local on_exit = function()
    if did_exit then
      return
    end
    local did_kill = false
    pcall(function()
      did_kill = killed[self:get_id()] == true
      killed[self:get_id()] = nil
    end)
    pcall(function()
      if type(settings) == "table" then
        settings.terminal_win_cmd = old_f_value
      end
    end)
    session = nil
    if did_set_adapter
        and previous_adapter ~= nil
        and type(dap.adapters) == "table"
    then
      dap.adapters[configuration.type] = previous_adapter
    end
    dap.listeners.after.launch[key] = nil
    did_exit = true

    self:__on_exit({
      killed = did_kill
    })
  end
  local old_bufs = vim.api.nvim_list_bufs()

  if type(settings) == "table" then
    settings.terminal_win_cmd = function()
      local local_buf = vim.api.nvim_create_buf(false, true)
      local float = -1
      if buf ~= nil and vim.api.nvim_buf_is_valid(buf) then
        float = vim.fn.bufwinid(buf)
      end
      if float <= -1 then
        float = require "spur.core.handler":__open_float(self, local_buf)
      end
      return local_buf, float
    end
  end

  local prev_session = dap.session()
  dap.run(configuration, {
    new = true,
    after = on_exit
  })
  id = self:get_id()
  dap.listeners.after.launch[key] = function()
    dap.listeners.after.launch[key] = nil
    settings.terminal_win_cmd = old_f_value
    local new_session = dap.session()
    ok = new_session ~= nil
        and (prev_session == nil or prev_session.id ~= new_session.id)
        and not new_session.closed
    if not ok then
      return nil
    end
    vim.defer_fn(function()
      local found_buf = nil
      local new_bufs = {}
      for _, local_buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[local_buf].buftype == "terminal" then
          for _, old_buf in ipairs(old_bufs) do
            if local_buf == old_buf then
              found_buf = local_buf
              break
            end
          end
          if found_buf == nil then
            table.insert(new_bufs, local_buf)
          end
        end
      end
      local bufnr = found_buf or new_bufs[1]
      if type(bufnr) ~= "number" then
        return
      end
      local config = require "spur.config"
      vim.bo[bufnr].filetype = config.filetype
      session = new_session
      buf = bufnr
      id = self:get_id()
      self:__on_start()
      vim.schedule(function()
        if buf ~= vim.api.nvim_get_current_buf() then
          require("spur.manager").__find_handler(self, "open_job_output"):open_job_output(self)
        end
      end)
    end, 50)
  end
end

function SpurDapJob:__is_available()
  if not SpurJob.__is_available(self) then
    return false
  end
  local ok, _ = pcall(require, "dap")
  return ok
end

return SpurDapJob
