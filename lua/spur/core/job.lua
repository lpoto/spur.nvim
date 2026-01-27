---@class SpurJob
---@field name string|nil
---@field type string|nil
---@field order number|nil
---@field quiet boolean
---@field on_exit function|nil
---@field on_start function|nil
---@field on_clean function|nil
---@field on_stdout function|nil
---@field job SpurJobData|nil
---@field condition SpurJobCondition|nil
---@field note string|nil
---@field show_headers boolean|nil
local SpurJob = {}
SpurJob.__index = SpurJob
SpurJob.__type = "SpurJob"

---@class SpurJobCondition
---@field dir string|nil
---@field show_in_subdirs boolean|nil

---@class SpurJobData
---@field cmd string
---@field name string
---@field working_dir string|nil
---@field clear_env boolean|nil
---@field env table<string, string>|nil

local private = setmetatable({}, { __mode = "k" })
local id_counter = 0
local start_job

--- Create a new SpurJob instance.
---
---@param opts table
---@return SpurJob
function SpurJob:new(opts)
  if type(opts) ~= "table" then
    error("SpurJob:new expects a table of options")
  end
  local jobdata = opts.job
  if type(jobdata) ~= "table" then
    error("SpurJob:new expects a 'job' table in options")
  end
  if jobdata.cmd == nil or type(jobdata.cmd) ~= "string" then
    error("SpurJob:new expects a 'job.cmd' string in options")
  end
  if type(opts.name) ~= "string" or opts.name == "" then
    if jobdata.name == nil or type(jobdata.name) ~= "string" or jobdata.name == "" then
      error("SpurJob:new expects 'job.name' to be a non-empty string")
    end
    opts.name = jobdata.name
  end
  if jobdata.working_dir ~= nil and type(jobdata.working_dir) ~= "string" then
    error("SpurJob:new expects 'job.working_dir' to be a string if provided")
  end
  if jobdata.clear_env ~= nil and type(jobdata.clear_env) ~= "boolean" then
    error("SpurJob:new expects 'job.clear_env' to be a boolean if provided")
  end
  jobdata.clear_env = jobdata.clear_env == true
  if jobdata.env ~= nil then
    if type(jobdata.env) ~= "table" then
      error("SpurJob:new expects 'job.env' to be a table if provided")
    end
    local len = 0
    for k, v in pairs(jobdata.env) do
      if type(k) ~= "string" or (type(v) ~= "string" and type(v) ~= "number" and type(v) ~= "boolean") then
        error(
          "SpurJob:new expects 'job.env' to be a table of string keys and string, number or boolean values")
      end
      len = len + 1
    end
    if len == 0 then
      jobdata.env = nil
    end
  end
  if opts.on_exit ~= nil and type(opts.on_exit) ~= "function" then
    error("SpurJob:new expects 'on_exit' to be a function if provided")
  end
  if opts.on_stdout ~= nil and type(opts.on_stdout) ~= "function" then
    error("SpurJob:new expects 'on_stdout' to be a function if provided")
  end
  if opts.on_start ~= nil and type(opts.on_start) ~= "function" then
    error("SpurJob:new expects 'on_start' to be a function if provided")
  end
  if opts.on_clean ~= nil and type(opts.on_clean) ~= "function" then
    error("SpurJob:new expects 'on_clean' to be a function if provided")
  end
  if opts.quiet ~= nil and type(opts.quiet) ~= "boolean" then
    error("SpurJob:new expects 'quiet' to be a boolean if provided")
  end
  if opts.order ~= nil and type(opts.order) ~= "number" then
    error("SpurJob:new expects 'order' to be a number if provided")
  end
  if opts.type ~= nil and type(opts.type) ~= "string" then
    error("SpurJob:new expects 'type' to be a string if provided")
  end
  if opts.note ~= nil and type(opts.note) ~= "string" then
    error("SpurJob:new expects 'note' to be a string if provided")
  end
  if opts.condition ~= nil and type(opts.condition) ~= "table" then
    error("SpurJob:new expects 'condition' to be a table if provided")
  end
  if opts.condition ~= nil then
    if opts.condition.dir ~= nil and type(opts.condition.dir) ~= "string" then
      error("SpurJob:new expects 'condition.dir' to be a string if provided")
    end
    if opts.condition.show_in_subdirs ~= nil
        and type(opts.condition.show_in_subdirs) ~= "boolean"
    then
      error("SpurJob:new expects 'condition.show_in_subdirs' to be a boolean if provided")
    end
  end
  if opts.show_headers ~= nil and type(opts.show_headers) ~= "boolean" then
    error("SpurJob:new expects 'show_headers' to be a boolean if provided")
  end
  id_counter = id_counter + 1
  local private_opts = {
    id = id_counter,
    job_id = nil,
    bufnr = nil,
  }
  local instance = setmetatable({
    job = jobdata,
    name = opts.name or jobdata.name,
    type = opts.type or nil,
    quiet = opts.quiet == true,
    order = opts.order,
    on_exit = opts.on_exit,
    on_start = opts.on_start,
    on_clean = opts.on_clean,
    on_stdout = opts.on_stdout,
    condition = opts.condition,
    note = opts.note,
    show_headers = opts.show_headers == true,
  }, self)
  private[instance] = private_opts
  return instance
end

--- Check if the job is currently running.
---
--- @return boolean
function SpurJob:is_running()
  return self:__get_job_id() ~= nil
end

--- Check if the job is quiet, meaning output
--- buffer is not shown.
---
--- @return boolean
function SpurJob:is_quiet()
  return self.quiet == true
end

--- Get the job's internal id.
--- This is NOT the job id associated with
--- the underlying Neovim job process.
---
--- @return number
function SpurJob:get_id()
  local private_opts = private[self]
  if type(private_opts) == "table"
      and private_opts.id ~= nil
      and type(private_opts.id) == "number"
  then
    return private_opts.id
  end
  error("SpurJob id is not available")
end

--- Get the name associated with the job.
--- If no name is provided, the cmd is returned.
---
--- @return string
function SpurJob:get_name()
  return self.name
end

--- Get the status associated with the job.
---
--- @return string|nil
function SpurJob:get_status()
  if self:is_running() then
    if self:is_quiet() then
      return "Running - quiet"
    end
    return "Running"
  end
  if self:can_show_output() then
    return "Output"
  end
  return nil
end

--- Get the buffer number associated with the job,
--- bufnr is only available after the job has been started,
--- and the job's buffer still exists.
---
--- @return number|nil
function SpurJob:get_bufnr()
  local private_opts = private[self]
  if type(private_opts) == "table"
      and type(private_opts.bufnr) == "number"
  then
    return private_opts.bufnr
  end
  vim.schedule(function()
    if type(private_opts.bufnr) ~= "number"
        or not vim.api.nvim_buf_is_valid(private_opts.bufnr) then
      private_opts.bufnr = nil
    end
  end)
  return nil
end

--- Check whether output may be shown for this job.
---
--- @return boolean
function SpurJob:can_show_output()
  local bufnr = self:get_bufnr()
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

--- Check whether this job can be run
function SpurJob:can_run()
  local private_opts = private[self]
  return private_opts ~= nil and not self:is_running()
end

function SpurJob:can_restart()
  local private_opts = private[self]
  return private_opts ~= nil
end

function SpurJob:can_run_before_clean()
  return true
end

local create_job_buffer

--- Run the job with the command specified when creating the instance.
--- The job cannot be run, if it is already running.
---@param args string|string[]|nil
function SpurJob:run(args)
  local private_opts = private[self]
  if not private_opts then
    error("SpurJob instance is not properly initialized")
  end
  local is_restarting =
      type(private_opts) == "table"
      and type(private_opts.flags) == "table"
      and private_opts.flags.restart == true
  if is_restarting then
    private_opts.flags.restart = nil
  end

  vim.schedule(function()
    local existing_buf = self:get_bufnr()
    if self:is_quiet() then
      private_opts.bufnr = nil
    elseif is_restarting then
      private_opts.bufnr = existing_buf
    else
      private_opts.bufnr = create_job_buffer(self)
    end
    local winids = vim.api.nvim_list_wins()

    local ok, err = pcall(self.__start_job, self, private_opts.bufnr, args)
    if not ok then
      pcall(function()
        local b = private_opts.bufnr
        if type(b) == "number" and vim.api.nvim_buf_is_valid(b) then
          vim.api.nvim_buf_delete(b, { force = true })
        end
        private_opts.bufnr = nil
      end)
      error(err)
    end
    if not is_restarting then
      pcall(function()
        local config = require "spur.config"
        for _, winid in ipairs(winids) do
          local buf = vim.api.nvim_win_get_buf(winid)
          if buf == existing_buf
              or vim.bo[buf].filetype == config.filetype then
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
    end
  end)
end

--- Kills the job if it is running.
--- This does not delete the job's buffer.
---@param flag string|nil
function SpurJob:kill(flag)
  local private_opts = private[self]
  if private_opts == nil then
    error("SpurJob instance is not properly initialized")
  end
  local job_id = self:__get_job_id()
  if type(flag) == "string" and flag ~= "" then
    if type(private_opts.flags) ~= "table" then
      private_opts.flags = {}
    end
    private_opts.flags[flag] = true
  end
  if vim.v.exiting ~= 0 then
    pcall(vim.fn.jobstop, job_id)
  else
    self:__send_signal("interrupt")
    vim.schedule(function()
      pcall(vim.fn.jobstop, job_id)
    end)
  end
end

function SpurJob:__get_job_id()
  local private_opts = private[self]
  if private_opts == nil then
    return nil
  end
  if private_opts.job_id == nil then
    return nil
  end
  return private_opts.job_id
end

function SpurJob:__send_signal(name)
  if type(name) ~= "string" or name == "" then
    return
  end
  local job_id = self:__get_job_id()
  if job_id == nil then
    return
  end
  vim.schedule(function()
    pcall(function()
      local config = require "spur.config"
      vim.api.nvim_chan_send(job_id, "\n\n#" .. config.prefix .. "Signal - " .. name .. "\n")
    end)
  end)
end

--- Kills the job if it is running and deletes the job's buffer.
function SpurJob:clean()
  local private_opts = private[self]
  if private_opts == nil then
    error("SpurJob instance is not properly initialized")
  end
  self:kill()
  vim.schedule(function()
    local buf = self:get_bufnr()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == buf then
        vim.api.nvim_win_close(win, true)
      end
    end
    if type(buf) == "number" and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
      if type(self.on_clean) == "function" then
        pcall(self.on_clean, self)
      end
    end
    private_opts.bufnr = nil
  end)
end

---@param bufnr number|nil
---@param args string|string[]|nil
function SpurJob:__start_job(bufnr, args)
  if self:is_running() then
    error("SpurJob:run cannot be called while the job is already running")
  end
  local private_opts = private[self]
  if not private_opts then
    error("SpurJob instance is not properly initialized")
  end
  local job_id = self:__get_job_id()
  if job_id ~= nil then
    error("SpurJob is already running")
  end
  if type(self.job) ~= "table" or type(self.job.cmd) ~= "string" or self.job.cmd == "" then
    error("SpurJob command is not set")
  end
  if self.job.working_dir ~= nil and type(self.job.working_dir) ~= "string" then
    error("SpurJob working_dir must be a string or nil")
  end
  return start_job(self, bufnr, args)
end

function SpurJob:__tostring()
  return string.format("SpurJob(%s)", self:get_name())
end

function SpurJob:__on_exit(opts)
  vim.schedule(function()
    if type(self.on_exit) == "function" then
      pcall(self.on_exit, opts)
      return
    end
    pcall(function()
      if type(vim.g.display_message) == "function" then
        local config = require "spur.config"
        vim.g.display_message {
          message = "Exited: " .. self:get_name(),
          title = config.title,
        }
      end
    end)

    local private_opts = private[self]
    if type(private_opts) ~= "table" then
      return
    end
    local restart = false
    local flags = private_opts.flags
    if type(flags) == "table" and flags.restart == true then
      restart = true
    end

    local bufnr = self:get_bufnr()
    if type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) then
      vim.bo[bufnr].buflisted = false
      vim.bo[bufnr].modified = false
    end
    if restart then
      vim.schedule(function()
        pcall(function()
          self:run()
        end)
      end)
    end
  end)
end

function SpurJob:__on_start()
  vim.schedule(function()
    if type(self.on_start) == "function" then
      pcall(self.on_start, self)
    end
    pcall(function()
      if type(vim.g.display_message) == "function" then
        local config = require "spur.config"
        vim.g.display_message {
          message = "Started: " .. self:get_name(),
          title = config.title,
        }
      end
    end)
  end)
end

---@return boolean
function SpurJob:__is_available()
  if self.__type ~= "SpurJob" then
    return false
  end
  if type(self.condition) ~= "table" then
    return true
  end
  if type(self.condition.dir) ~= "string" then
    return true
  end
  local dir = vim.fn.expand(self.condition.dir)
  dir = string.sub(dir, -1) == "/" and dir or dir .. "/"
  local current_dir = vim.fn.getcwd()
  current_dir = string.sub(current_dir, -1) == "/" and current_dir or current_dir .. "/"

  local support_subdirs = self.condition.show_in_subdirs == nil
      or self.condition.show_in_subdirs == true
  if not support_subdirs then
    return dir == current_dir
  end
  return string.sub(current_dir, 1, #dir) == dir
      or string.sub(current_dir, 1, #dir + 1) == dir .. "/"
end

---@param job SpurJob
---@param bufnr number|nil
---@param args string|string[]|nil
function start_job(job, bufnr, args)
  local private_opts = private[job]
  if type(private_opts) ~= "table" then
    error("SpurJob instance is not properly initialized")
  end
  if type(job.job) ~= "table" then
    error("SpurJob instance is not properly initialized")
  end
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = nil
  end

  local jobstart = function(term)
    local working_dir = job.job.working_dir
    if type(working_dir) == "string" and working_dir ~= "" then
      working_dir = vim.fn.expand(working_dir)
    else
      working_dir = nil
    end

    local cmd = job.job.cmd
    if type(args) == "table" then
      for _, a in ipairs(args) do
        if type(a) == "string" and a ~= "" then
          cmd = cmd .. " " .. a
        end
      end
    elseif type(args) == "string" and args ~= "" then
      cmd = cmd .. " " .. args
    end

    -- NOTE: Wrap the command so that when Neovim exits,
    -- the job is also killed.
    -- This prevents orphaned processes.
    -- This is done by trapping the EXIT signal and
    -- killing the entire process group.
    local nvim_pid = vim.fn.getpid()
    local cmd_wrapper = {
      "sh",
      "-c",
      string.format([[
        (
          trap 'kill 0' EXIT
          while kill -0 %d 2>/dev/null; do sleep 1; done
          kill 0
        ) &
        exec %s
        ]],
        nvim_pid,
        cmd)
    }

    local job_id
    job_id = vim.fn.jobstart(
      cmd_wrapper,
      {
        term = term,
        cwd = working_dir,
        clear_env = job.job.clear_env,
        env = job.job.env,
        detach = false,
        on_stdout = function(...)
          if type(job.on_stdout) == "function" then
            pcall(job.on_stdout, ...)
          end
        end,
        on_exit = function(_, code, msg)
          private_opts.job_id = nil
          job:__on_exit({
            exit_code = code,
            msg = msg,
            job = job,
          })
        end,
        stderr_buffered = false,
        stdout_buffered = false,
      })
    return job_id
  end
  local job_id
  if type(bufnr) == "number" then
    vim.api.nvim_buf_call(bufnr, function()
      job_id = jobstart(true)
    end)
  else
    job_id = jobstart(false)
  end

  local config = require "spur.config"
  pcall(function()
    if job.show_headers == true then
      vim.api.nvim_chan_send(job_id, "#" .. config.prefix .. job.job.cmd .. "\n\n")
      if type(job.note) == "string" and job.note ~= "" then
        vim.api.nvim_chan_send(
          job_id,
          "#" .. config.prefix .. "Note: " .. job.note .. "\n\n")
      end
    end
    if type(bufnr) == "number" then
      vim.api.nvim_buf_call(bufnr, function()
        vim.schedule(function()
          pcall(function()
            vim.cmd("normal G")
          end)
        end)
      end)
    end
  end)
  job:__on_start()
  private_opts.job_id = job_id
end

local set_output_buf_options
function create_job_buffer(job)
  if type(job) ~= "table"
      or type(job.get_id) ~= "function"
      or job.__type ~= "SpurJob" then
    error("create_job_buffer expects a SpurJob instance in 'job' option")
  end
  local bufnr = vim.api.nvim_create_buf(false, true)
  return set_output_buf_options(bufnr, job)
end

function set_output_buf_options(bufnr, job)
  local config = require "spur.config"
  local set_opts = function()
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].buflisted = false
    vim.bo[bufnr].undolevels = -1
    vim.bo[bufnr].modified = false
    vim.bo[bufnr].filetype = config.filetype
    vim.bo[bufnr].buftype = ""
    vim.bo[bufnr].filetype = config.filetype
    vim.fn.prompt_setprompt(bufnr, "")
  end
  set_opts()
  --NOTE: set the autocmd for the terminal buffer, so that
  --when it finishes, we cannot enter the insert mode.
  --(when we enter insert mode in the closed terminal, it is deleted)
  local group = vim.api.nvim_create_augroup("SpurJobAugroup_Term", {})
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = bufnr,
    group = group,
    nested = true,
    once = true,
    callback = function()
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("stopinsert")
        vim.bo[bufnr].filetype = config.filetype
        vim.api.nvim_create_autocmd("TermEnter", {
          group = group,
          buffer = bufnr,
          callback = function() vim.cmd("stopinsert") end,
        })
      end)
    end,
  })
  local group2 = vim.api.nvim_create_augroup("SpurJobAugroup_buffer_kill", {})
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    buffer = bufnr,
    group = group2,
    once = true,
    callback = function()
      vim.schedule(function()
        pcall(function()
          job:clean()
        end)
      end)
    end,
  })
  return bufnr
end

return SpurJob
