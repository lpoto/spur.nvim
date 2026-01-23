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

local private = setmetatable({}, { __mode = "k" })

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


  private[instance] = {
    id = spur_job:get_id(),
    session = nil
  }
  instance.dap = opts.dap
  ---@diagnostic disable-next-line
  return instance
end

--- Check if the job is currently running.
---
---@return boolean
function SpurDapJob:is_running()
  local private_opts = private[self]
  if type(private_opts) ~= "table" or type(private_opts.session) ~= "table" then
    return false
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    return false
  end
  local session = dap.session()
  return type(session) == "table" and session.id == private_opts.session.id
end

function SpurDapJob:can_restart()
  return self:is_running()
end

--- Check whether this job can be run
function SpurDapJob:can_run()
  if not SpurJob.can_run(self) then
    return false
  end
  local private_opts = private[self]
  if private_opts == nil then
    return false
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    return false
  end
  local session = dap.session()
  if session == nil or session.closed == true then
    return true
  end
  if private_opts.session == nil then
    return false
  end
  return session.id == private_opts.session.id
end

local killed = {}

--- Kills the job if it is running.
--- This does not delete the job's buffer.
function SpurDapJob:kill(flag)
  local private_opts = private[self]
  if private_opts == nil then
    error("SpurDapJob instance is not properly initialized")
  end
  if private_opts.session == nil then
    return
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    return
  end
  local session = dap.session()
  if session == nil or private_opts.session.id ~= session.id then
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
  local private_opts = private[self]
  if private_opts == nil then
    error("SpurDapJob instance is not properly initialized")
  end
  SpurJob.clean(self)

  vim.schedule(function()
    private_opts.buf = nil
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
  local private_opts = private[self]
  if private_opts == nil then
    error("SpurDapJob instance is not properly initialized")
  end
  if private_opts.session == nil then
    return
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    return
  end
  local session = dap.session()
  if session == nil
      or private_opts.session.id ~= session.id
      or session.stopped_thread_id == nil
  then
    return
  end
  return session.capabilities.supportsStepBack == true
end

function SpurDapJob:is_stopped()
  if not self:is_running() then
    return false
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    return false
  end
  local session = dap.session()
  if type(session) == "table" and session.stopped_thread_id then
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
  local private_opts = private[self]
  if type(private_opts) == "table"
      and type(private_opts.buf) == "number"
  then
    return private_opts.buf
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
    local session = dap.session()
    if type(session) == "table" and session.stopped_thread_id then
      return "Stopped"
    end
  end
  return status
end

--- Run the job with the command specified when creating the instance.
--- The job cannot be run, if it is already running.
function SpurDapJob:run()
  local private_opts = private[self]
  if not private_opts then
    error("SpurJob instance is not properly initialized")
  end
  vim.schedule(function()
    local existing_buf = self:get_bufnr()
    local winids = vim.api.nvim_list_wins()

    self:__start_job()

    pcall(function()
      local config = require "spur.config"
      for _, winid in ipairs(winids) do
        local buf = vim.api.nvim_win_get_buf(winid)
        if buf == existing_buf
            or (vim.bo[buf].filetype == config.filetype
              and vim.bo[buf].buftype == "prompt")
        then
          pcall(function()
            vim.api.nvim_win_close(winid, true)
          end)
        end
      end
    end)
    pcall(function()
      if existing_buf ~= nil and vim.api.nvim_buf_is_valid(existing_buf) then
        -- If the job was already running, we need to clean up the old buffer.
        vim.api.nvim_buf_delete(existing_buf, { force = true })
      end
    end)
  end)
end

function SpurDapJob:__execute_stopped_session_call(call)
  if type(call) ~= "function" then
    return
  end
  local private_opts = private[self]
  if private_opts == nil then
    error("SpurDapJob instance is not properly initialized")
  end
  if private_opts.session == nil then
    return
  end
  local ok, dap = pcall(require, "dap")
  if not ok then
    return
  end
  local session = dap.session()
  if session == nil
      or private_opts.session.id ~= session.id
      or session.stopped_thread_id == nil
  then
    return
  end
  call(dap, session)
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
  local private_opts = private[self]
  if type(private_opts) ~= "table" then
    error("SpurDapJob:run expects 'private' to be a table")
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
    private_opts.session = nil
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
      local buf = vim.api.nvim_create_buf(false, true)
      local float = require "spur.core.handler":__open_float(self, buf)
      return buf, float
    end
  end

  local prev_session = dap.session()
  dap.run(configuration, {
    new = true,
    after = on_exit
  })
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
      local new_bufs = {}
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].buftype == "terminal" then
          local found = false
          for _, old_buf in ipairs(old_bufs) do
            if buf == old_buf then
              found = true
              break
            end
          end
          if not found then
            table.insert(new_bufs, buf)
          end
        end
      end
      local bufnr = new_bufs[1]
      if type(bufnr) ~= "number" then
        return
      end
      -- TODO: Override dap function to open
      -- output in a float like other spur jobs do

      local config = require "spur.config"
      vim.bo[bufnr].filetype = config.filetype
      private_opts.session = new_session
      private_opts.buf = bufnr
      self:__on_start()
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
