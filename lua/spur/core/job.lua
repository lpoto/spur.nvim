---@class SpurJob
---@field name string
---@field cmd string
---@field working_dir string|nil
---@field order number|nil
---@field quiet boolean
---@field on_exit function|nil
---@field on_start function|nil
---@field on_clean function|nil
local SpurJob = {}
SpurJob.__index = SpurJob
SpurJob.__type = "SpurJob"

local private = setmetatable({}, { __mode = "k" })
local id_counter = 0
local set_output_buf_options

--- Create a new SpurJob instance.
---
---@param opts table
---@return SpurJob
function SpurJob:new(opts)
  if type(opts) ~= "table" then
    error("SpurJob:new expects a table of options")
  end
  if opts.cmd == nil or type(opts.cmd) ~= "string" then
    error("SpurJob:new expects a 'cmd' string in options")
  end
  if opts.name ~= nil and type(opts.name) ~= "string" then
    error("SpurJob:new expects 'name' to be a string if provided")
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
  if opts.working_dir ~= nil and type(opts.working_dir) ~= "string" then
    error("SpurJob:new expects 'working_dir' to be a string if provided")
  end
  id_counter = id_counter + 1
  local private_opts = {
    id = id_counter,
    bufnr = nil,
    job_id = nil
  }
  local name = nil
  if type(opts.name) == "string" and opts.name ~= "" then
    name = opts.name
  end
  if name == nil then
    name = "SpurJob " .. private_opts.id
  end
  local instance = setmetatable({
    name = name,
    cmd = opts.cmd,
    working_dir = opts.working_dir or nil,
    quiet = opts.quiet or false,
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
---@return boolean
function SpurJob:is_running()
  local private_opts = private[self]
  return type(private_opts) == "table" and private_opts.job_id ~= nil
end

--- Check if the job is quiet, meaning output
--- buffer is not shown.
---
---@return boolean
function SpurJob:is_quiet()
  return self.quiet == true
end

--- Get the job's internal id.
--- This is NOT the job id associated with
--- the underlying Neovim job process.
---
---@return number
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
---@return string
function SpurJob:get_name()
  if type(self.name) == "string" and self.name ~= "" then
    return self.name
  end
  if self.cmd ~= nil and type(self.cmd) == "string"
  then
    return self.cmd
  end
  error("SpurJob command is not available")
end

--- Get the status associated with the job.
---
---@return string|nil
function SpurJob:get_status()
  if self:is_running() then
    return "Running"
  end
  if self:get_bufnr() ~= nil then
    return "Idle"
  end
  return nil
end

--- Get the buffer number associated with the job,
--- bufnr is only available after the job has been started,
--- and the job's buffer still exists.
---
---@return number|nil
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

--- Run the job with the command specified when creating the instance.
--- The job cannot be run, if it is already running.
function SpurJob:run()
  local private_opts = private[self]
  if not private_opts then
    error("SpurJob instance is not properly initialized")
  end
  if private_opts.job_id ~= nil then
    error("SpurJob is already running")
  end
  if type(self.cmd) ~= "string" or self.cmd == "" then
    error("SpurJob command is not set")
  end
  if self.working_dir ~= nil and type(self.working_dir) ~= "string" then
    error("SpurJob working_dir must be a string or nil")
  end

  local start_job = function()
    local job_id
    job_id = vim.fn.jobstart(
      self.cmd,
      {
        term = self.quiet ~= true,
        cwd = self.working_dir,
        detach = false,
        on_exit = function(_, code, msg)
          private_opts.job_id = nil
          if type(self.on_exit) == "function" then
            self.on_exit({
              exit_code = code,
              msg = msg,
              job = self,
            })
          end
        end
      })
    vim.api.nvim_chan_send(job_id, "SPUR: " .. self.cmd .. "\n\n")
    if type(self.on_start) == "function" then
      self.on_start(self)
    end
    private_opts.job_id = job_id
  end
  if self.quiet == true then
    start_job()
    return
  end
  private_opts.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(private_opts.bufnr, self.cmd)
  vim.api.nvim_buf_call(private_opts.bufnr, start_job)
  set_output_buf_options(private_opts.bufnr)
end

--- Kills the job if it is running.
--- This does not delete the job's buffer.
function SpurJob:stop()
  local private_opts = private[self]
  if private_opts == nil then
    error("SpurJob instance is not properly initialized")
  end
  if private_opts.job_id == nil then
    return
  end
  vim.fn.jobstop(private_opts.job_id)
end

--- Kills the job if it is running and deletes the job's buffer.
function SpurJob:clean()
  local private_opts = private[self]
  if private_opts == nil then
    error("SpurJob instance is not properly initialized")
  end
  if private_opts.job_id ~= nil then
    vim.fn.jobstop(private_opts.job_id)
  end
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
end

function SpurJob:__tostring()
  return string.format("SpurJob(%s)", self.name)
end

function set_output_buf_options(bufnr)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].undolevels = -1
  vim.bo[bufnr].filetype = "spur-output"

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
      vim.cmd("stopinsert")
      vim.bo.modifiable = false
      vim.bo.readonly = true
      vim.bo.filetype = "spur-output"
      vim.api.nvim_create_autocmd("TermEnter", {
        group = group,
        buffer = bufnr,
        callback = function() vim.cmd("stopinsert") end,
      })
    end,
  })
end

return SpurJob
