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

local private = setmetatable({}, { __mode = "k" })

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
function SpurDapJob:kill()
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
  self:__send_signal("interrupt")
  dap.terminate()
end

--- Continues the job if it has been stopped.
function SpurDapJob:continue()
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
  dap.continue({ new = false })
end

--- Override run to start DAP session
function SpurDapJob:__tostring()
  return string.format("SpurDapJob(%s)", self.name)
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

function SpurDapJob:__start_job(bufnr)
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
    private_opts.session = nil
    if did_set_adapter
        and previous_adapter ~= nil
        and type(dap.adapters) == "table"
    then
      dap.adapters[configuration.type] = previous_adapter
    end
    if type(dap.listeners) == "table"
        and type(dap.listeners.after) == "table"
    then
      if type(dap.listeners.after.event_output) == "table" then
        dap.listeners.after.event_output[key] = nil
      end
      if type(dap.listeners.after.event_stopped) == "table" then
        dap.listeners.after.event_stopped[key] = nil
      end
    end
    if type(dap.listeners) == "table"
        and type(dap.listeners.before) == "table"
    then
      if type(dap.listeners.before.event_stopped) == "table" then
        dap.listeners.before.event_stopped[key] = nil
      end
    end
    did_exit = true

    self:__on_exit({
      killed = did_kill
    })
  end

  local prev_session = dap.session()
  dap.run(configuration, {
    new = true,
    after = on_exit
  })
  local new_session = dap.session()
  ok = new_session ~= nil
      and (prev_session == nil or prev_session.id ~= new_session.id)
      and not new_session.closed
  if not ok then
    return nil
  end
  private_opts.session = new_session
  local config = require "spur.config"
  self:__handle_output(config.prefix .. "Debug\n", config.hl.info)

  if type(dap.listeners) ~= "table" then
    dap.listeners = {}
  end
  if type(dap.listeners.after) ~= "table" then
    dap.listeners.after = {}
  end
  if type(dap.listeners.before) ~= "table" then
    dap.listeners.before = {}
  end
  if type(dap.listeners.after.event_output) ~= "table" then
    dap.listeners.after.event_output = {}
  end
  if type(dap.listeners.after.event_stopped) ~= "table" then
    dap.listeners.after.event_stopped = {}
  end
  if type(dap.listeners.before.event_stopped) ~= "table" then
    dap.listeners.before.event_stopped = {}
  end
  dap.listeners.after.event_output[key] = function(session, output)
    if type(output) ~= "table"
        or type(session) ~= "table"
        or type(private_opts.session) ~= "table"
        or type(output.output) ~= "string"
        or session.id ~= private_opts.session.id
        or type(output.category) ~= "string" or output.category == "console" then
      return
    end
    self:__handle_output(output.output)
  end
  dap.listeners.before.event_stopped[key] = function(session, o)
    if type(session) ~= "table"
        or type(private_opts.session) ~= "table"
        or session.id ~= private_opts.session.id
        or type(o) ~= "table" or o.reason ~= "breakpoint" then
      return
    end
    -- NOTE: Before breakpoint we try to close
    -- any existing windows for this plugin, so
    -- we dont jump to breakpoints in our floats.
    if type(o) == "table" and o.reason == "breakpoint" then
      pcall(function()
        local win_ids = vim.api.nvim_list_wins()
        for _, win_id in ipairs(win_ids) do
          local buf = vim.api.nvim_win_get_buf(win_id)
          if bufnr == buf
              or vim.bo[buf].filetype == config.filetype
              and vim.bo[buf].buftype == "prompt"
          then
            vim.api.nvim_win_close(win_id, true)
            break
          end
        end
      end)
    end
  end
  dap.listeners.after.event_stopped[key] = function(session, o)
    pcall(function()
      if type(session) ~= "table"
          or type(private_opts.session) ~= "table"
          or session.id ~= private_opts.session.id then
        return
      end
      local msg = "Stopped"
      if type(o) == "table"
          and type(o.reason) == "string"
          and o.reason ~= "" then
        if o.reason == "pause"
            and type(killed) == "table"
            and type(self.get_id) == "function"
            and type(self:get_id()) == "number"
            and killed[self:get_id()] == true
        then
          return
        end

        msg = msg .. " - " .. o.reason
      end
      self:__handle_output("\n \n" .. config.prefix .. msg .. "\n \n", config.hl.debug)
    end)
  end
  return bufnr
end

return SpurDapJob
