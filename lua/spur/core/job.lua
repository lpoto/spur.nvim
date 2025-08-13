---@class SpurJob
---@field name string|nil
---@field order number|nil
---@field quiet boolean
---@field on_exit function|nil
---@field on_start function|nil
---@field on_clean function|nil
---@field job SpurJobData|nil
local SpurJob = {}
SpurJob.__index = SpurJob
SpurJob.__type = "SpurJob"

---@class SpurJobData
---@field cmd string
---@field name string
---@field working_dir string|nil

local private = setmetatable({}, { __mode = "k" })
local id_counter = 0
local create_job_buffer
local start_job
local set_output_buf_options

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
  if opts.on_exit ~= nil and type(opts.on_exit) ~= "function" then
    error("SpurJob:new expects 'on_exit' to be a function if provided")
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
  id_counter = id_counter + 1
  local private_opts = {
    id = id_counter,
    bufnr = nil,
    job_id = nil,
    writer = nil
  }
  local instance = setmetatable({
    job = jobdata,
    name = opts.name or jobdata.name,
    quiet = opts.quiet == true,
    order = opts.order or nil,
    on_exit = opts.on_exit,
    on_start = opts.on_start,
    on_clean = opts.on_clean,
  }, self)
  private[instance] = private_opts
  return instance
end

--- Check if the job is currently running.
---
--- @return boolean
function SpurJob:is_running()
  local private_opts = private[self]
  return type(private_opts) == "table" and private_opts.job_id ~= nil
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
      and private_opts.bufnr ~= nil
      and type(vim.api) == "table"
      and type(vim.api.nvim_buf_is_valid) == "function"
      and vim.api.nvim_buf_is_valid(private_opts.bufnr)
  then
    return private_opts.bufnr
  end
  return nil
end

--- Check whether output may be shown for this job.
---
--- @return boolean
function SpurJob:can_show_output()
  local bufnr = self:get_bufnr()
  return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

--- Check whether this job can be run
function SpurJob:can_run()
  local private_opts = private[self]
  return private_opts ~= nil and not self:is_running()
end

--- Run the job with the command specified when creating the instance.
--- The job cannot be run, if it is already running.
function SpurJob:run()
  local private_opts = private[self]
  if not private_opts then
    error("SpurJob instance is not properly initialized")
  end
  local existing_buf = private_opts.bufnr
  if self:is_quiet() then
    private_opts.bufnr = nil
    private_opts.writer = nil
  else
    private_opts.bufnr = create_job_buffer(self)
    if type(private_opts.bufnr) == "number" then
      private_opts.writer = require("spur.core.writer"):new(private_opts.bufnr)
    end
  end
  local ok, err = pcall(self.__start_job, self, private_opts.bufnr)
  if not ok then
    pcall(function()
      if private_opts.bufnr ~= nil and vim.api.nvim_buf_is_valid(private_opts.bufnr) then
        vim.api.nvim_buf_delete(private_opts.bufnr, { force = true })
      end
      private_opts.bufnr = nil
      private_opts.writer = nil
    end)
    error(err)
  end

  local winids = vim.api.nvim_list_wins()
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
end

--- Kills the job if it is running.
--- This does not delete the job's buffer.
function SpurJob:kill()
  local private_opts = private[self]
  if private_opts == nil then
    error("SpurJob instance is not properly initialized")
  end
  if private_opts.job_id == nil then
    return
  end
  self:__send_signal("interrupt")
  vim.fn.jobstop(private_opts.job_id)
end

--- Kills the job if it is running and deletes the job's buffer.
function SpurJob:clean()
  local private_opts = private[self]
  if private_opts == nil then
    error("SpurJob instance is not properly initialized")
  end
  self:kill()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == private_opts.bufnr then
      vim.api.nvim_win_close(win, true)
    end
  end
  if private_opts.bufnr and vim.api.nvim_buf_is_valid(private_opts.bufnr) then
    vim.api.nvim_buf_delete(private_opts.bufnr, { force = true })
    if type(self.on_clean) == "function" then
      self.on_clean(self)
    end
  end
  private_opts.bufnr = nil
  private_opts.writer = nil
end

---@param bufnr number|nil
function SpurJob:__start_job(bufnr)
  if self:is_running() then
    error("SpurJob:run cannot be called while the job is already running")
  end
  local private_opts = private[self]
  if not private_opts then
    error("SpurJob instance is not properly initialized")
  end
  if private_opts.job_id ~= nil then
    error("SpurJob is already running")
  end
  if type(self.job) ~= "table" or type(self.job.cmd) ~= "string" or self.job.cmd == "" then
    error("SpurJob command is not set")
  end
  if self.job.working_dir ~= nil and type(self.job.working_dir) ~= "string" then
    error("SpurJob working_dir must be a string or nil")
  end

  if self.quiet == true or bufnr == nil then
    start_job(self)
    return nil
  end
  vim.api.nvim_buf_call(bufnr, function() start_job(self) end)
  return bufnr
end

function SpurJob:__tostring()
  return string.format("SpurJob(%s)", self:get_name())
end

---@return SpurWriter|nil
function SpurJob:__get_writer()
  local private_opts = private[self]
  if type(private_opts) ~= "table" then
    return nil
  end
  return type(private_opts.writer) == "table" and private_opts.writer or nil
end

function SpurJob:__on_exit(opts)
  if type(self.on_exit) == "function" then
    return self.on_exit(opts)
  end
  local private_opts = private[self]
  if type(private_opts) ~= "table" then
    return
  end
  local bufnr = private_opts.bufnr
  if type(bufnr) ~= "number" then
    return
  end
  local config = require "spur.config"
  local writer = self:__get_writer()

  if writer ~= nil then
    writer:write_remainder()

    if type(opts.exit_code) == "number" then
      local hl = opts.exit_code == 0 and config.hl.info or config.hl.warn
      writer:write({
        message = "\n" .. config.prefix .. "Exited with code " .. opts.exit_code .. "\n",
        hl = hl
      })
    elseif opts.killed == true then
      writer:write({ message = "\n" .. config.prefix .. "Killed\n", hl = config.hl.warn })
    else
      writer:write({ message = "\n" .. config.prefix .. "Exited\n", hl = config.hl.info })
    end
  end

  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].modified = false
  pcall(function()
    vim.bo[bufnr].buftype = "prompt"
  end)

  vim.api.nvim_create_autocmd({ "InsertEnter" }, {
    buffer = bufnr,
    group = vim.api.nvim_create_augroup("SpurJobAugroup_Exit", { clear = false }),
    callback = function()
      vim.schedule(function()
        pcall(function()
          vim.cmd("stopinsert")
        end)
      end)
    end,
  })
  pcall(function()
    vim.api.nvim_buf_call(bufnr, function()
      pcall(function()
        vim.cmd("stopinsert")
      end)
    end)
  end)
  return nil
end

function SpurJob:__send_signal(name)
  if type(name) ~= "string" or name == "" then
    return
  end
  local config = require "spur.config"
  local writer = self:__get_writer()
  if writer ~= nil then
    writer:write({
      message = "\n" .. config.prefix .. "Signal - " .. name .. "\n",
      hl = config.hl.debug,
    })
  end
end

---@param job SpurJob
function start_job(job)
  local private_opts = private[job]
  if type(private_opts) ~= "table" then
    error("SpurJob instance is not properly initialized")
  end
  if type(job.job) ~= "table" then
    error("SpurJob instance is not properly initialized")
  end

  local parse_output = function(o)
    local writer = job:__get_writer()
    if writer ~= nil then
      writer:write({ message = o })
    end
  end

  local job_id
  job_id = vim.fn.jobstart(
    job.job.cmd,
    {
      term = false,
      cwd = job.job.working_dir,
      detach = false,
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
      on_stdout = function(_, o) parse_output(o) end,
      on_stderr = function(_, o) parse_output(o) end,
    })
  local config = require "spur.config"
  local writer = job:__get_writer()
  if writer ~= nil then
    writer:write({ message = config.prefix .. job.job.cmd .. "\n", hl = config.hl.info })
  end
  if type(job.on_start) == "function" then
    job.on_start(job)
  end
  private_opts.job_id = job_id
end

function create_job_buffer(job, on_input)
  if type(job) ~= "table"
      or type(job.get_id) ~= "function"
      or job.__type ~= "SpurJob" then
    error("create_job_buffer expects a SpurJob instance in 'job' option")
  end
  local bufnr = vim.api.nvim_create_buf(false, true)
  set_output_buf_options(bufnr)
  if type(on_input) == "function" then
    vim.fn.prompt_setcallback(bufnr, function(text)
      on_input(text, bufnr)
    end)
  end
  vim.fn.prompt_setinterrupt(bufnr, function()
    job:kill()
  end)
  return bufnr
end

function set_output_buf_options(bufnr)
  local config = require "spur.config"
  local set_opts = function()
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].buflisted = false
    vim.bo[bufnr].undolevels = -1
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].readonly = true
    vim.bo[bufnr].modified = false
    vim.bo[bufnr].filetype = config.filetype
    vim.bo[bufnr].buftype = "prompt"
    vim.fn.prompt_setprompt(bufnr, "")
  end
  set_opts()

  local group = vim.api.nvim_create_augroup("SpurJobAugroup_Insert", { clear = false })
  vim.api.nvim_create_autocmd({ "InsertEnter" }, {
    buffer = bufnr,
    group = group,
    callback = function()
      vim.schedule(function()
        pcall(set_opts)
        if bufnr ~= vim.api.nvim_get_current_buf() then
          return
        end
        -- NOTE: Move cursor to the end of file when trying to
        -- insert something.
        pcall(function()
          local last_line = vim.api.nvim_buf_line_count(bufnr)
          local last_line_text = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)
              [1] or ""
          local last_col = #last_line_text
          vim.api.nvim_win_set_cursor(0, { last_line, last_col })
        end)
        pcall(function()
          vim.cmd("stopinsert")
        end)
      end)
    end,
  })
  return bufnr
end

return SpurJob
