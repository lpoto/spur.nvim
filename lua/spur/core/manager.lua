local M = {}

local jobs = {}
local format_job_name
local get_job_actions
local execute_job_action
local show_job_output
local initializers = {}
local quick_run_counter = 1

--- Add a job to the manager.
--- The job must be initialized before adding it.
---
---@param job table
function M.add_job(job)
  if type(job) ~= "table" then
    error("Invalid job object provided")
  end
  if job.__type == "SpurJob" then
    if type(job.get_id) ~= "function" then
      error("Invalid SpurJob object provided")
    end
    jobs[job:get_id()] = job
    return
  end
  for _, initializer in ipairs(initializers) do
    local new_job = initializer(job)
    if type(new_job) == "table" and new_job.__type == "SpurJob" then
      if type(new_job.get_id) ~= "function" then
        error("Invalid SpurJob object provided from initializer")
      end
      jobs[new_job:get_id()] = new_job
      return
    end
  end
  local new_job = require "spur.core.job":new(job)
  jobs[new_job:get_id()] = new_job
end

--- Remove a job from the manager.
--- The job must be added before removing it.
---
---@param job SpurJob
function M.remove_job(job)
  if type(job) ~= "table"
      or job.__type ~= "SpurJob"
      or type(job.get_id) ~= "function" then
    error("Invalid job object provided")
  end
  jobs[job:get_id()] = nil
end

--- Create a temporary job and run the provided
--- command. This job will be removed once its output is cleared.
---
--- If no command is provided, the user will be prompted to enter one.
---
---@param cmd string|nil
function M.quick_run(cmd)
  if type(cmd) ~= "string" or cmd == "" then
    cmd = vim.fn.input("QuickRun command: ")
  end
  if type(cmd) ~= "string" or cmd == "" then
    return
  end
  local counter = quick_run_counter
  quick_run_counter = quick_run_counter + 1
  local job
  job = require "spur.core.job":new({
    cmd = cmd,
    name = "Quick run " .. counter,
    on_clean = function()
      M.remove_job(job)
    end
  })
  M.add_job(job)
  job:run()
  require "spur.core.ui".open_job_output(job)
end

local is_quick_run

--- Select a job from the list of available jobs.
--- On selection, the user will be prompted to
--- select an action for the job.
---
--- @param filter function|nil select only from
--- @param on_select function|nil custom on select handler
--- @param skip_selection_if_one_result boolean|nil Auto select a single result
--- jobs that pass the filter.
function M.select_job(filter, on_select, skip_selection_if_one_result)
  if type(jobs) ~= "table" then
    return
  end
  local filtered_jobs = {}
  for _, job in ipairs(vim.tbl_values(jobs)) do
    if type(filter) ~= "function" then
      table.insert(filtered_jobs, job)
    else
      local ok, result = pcall(filter, job)
      if ok and result == true then
        table.insert(filtered_jobs, job)
      end
    end
  end

  table.sort(filtered_jobs, function(a, b)
    local a_running = a:is_running()
    local b_running = b:is_running()
    if a_running and not b_running then
      return true
    end
    if b_running and not a_running then
      return false
    end
    local a_output = a:get_bufnr() ~= nil
    local b_output = b:get_bufnr() ~= nil
    if a_output and not b_output then
      return true
    end
    if b_output and not a_output then
      return false
    end
    local a_qr = is_quick_run(a.name)
    local b_qr = is_quick_run(b.name)
    if a_qr and b_qr then
      return a.name < b.name
    end
    if a_qr then
      return false
    end
    if b_qr then
      return true
    end
    if a.order == b.order then
      return a:get_id() < b:get_id()
    end
    if a.order == nil then return false end
    if b.order == nil then return true end
    return a.order < b.order
  end)
  if type(filter) ~= "function" and type(on_select) ~= "function" then
    table.insert(filtered_jobs, { type = "quickrun" })
  end
  if #filtered_jobs == 0 then
    vim.notify("No jobs found", vim.log.levels.WARN, { title = "Spur.nvim" })
    return
  end
  local select = function(o)
    if o == nil then
      return
    end
    if type(o) == "table" and o.type == "quickrun" then
      return M.quick_run()
    end
    if type(on_select) == "function" then
      return on_select(o)
    end
    return M.select_job_action(o)
  end

  if #filtered_jobs == 1 and skip_selection_if_one_result == true then
    return select(filtered_jobs[1])
  end

  vim.ui.select(
    filtered_jobs,
    {
      prompt = "Select a job",
      format_item = format_job_name
    },
    select
  )
end

--- Select one of the supported actions for the provided job.
---
---@param job SpurJob
function M.select_job_action(job)
  if job == nil then
    return
  end
  if type(job) ~= "table"
      or type(job.is_running) ~= "function"
      or type(job.get_bufnr) ~= "function" then
    error("Invalid job object provided")
  end
  local options = {}
  if not job:is_running() then
    table.insert(options, { label = "Run", value = "run" })
  else
    table.insert(options, { label = "Stop", value = "stop" })
  end
  if job:get_bufnr() ~= nil then
    table.insert(options, { label = "Output", value = "output" })
    table.insert(options, { label = "Clean", value = "clean" })
  end
  local actions = get_job_actions(job)
  if #actions == 0 then
    vim.notify(
      "No actions available for this job",
      vim.log.levels.WARN,
      { title = "Spur.nvim" })
    return
  end
  if #actions == 1 then
    return execute_job_action(job, actions[1])
  end

  vim.ui.select(
    actions,
    {
      prompt = format_job_name(job),
      format_item = function(item)
        return item.label
      end
    },
    function(choice)
      execute_job_action(job, choice)
    end
  )
end

--- Add a custom handler for creating new jobs.
--- If the returned job does not have __type = 'SpurJob',
--- or the initialier fails,
--- then the next initializer will be called.
---
---@param initializer function
function M.__add_job_initializer(initializer)
  if type(initializer) == "function" then
    table.insert(initializers, initializer)
  end
end

---@param job SpurJob
---@return table[]
function get_job_actions(job)
  local options = {}
  if type(job) ~= "table"
      or type(job.is_running) ~= "function"
      or type(job.get_bufnr) ~= "function" then
    error("Invalid job object provided")
  end
  if not job:is_running() then
    table.insert(options, { label = "Run", value = "run" })
  else
    table.insert(options, { label = "Stop", value = "stop" })
  end
  if job:get_bufnr() ~= nil then
    if not job:is_quiet() then
      table.insert(options, { label = "Output", value = "output" })
    end
    table.insert(options, { label = "Clean", value = "clean" })
  end
  return options
end

---@param job SpurJob
---@param action table
function execute_job_action(job, action)
  if type(job) ~= "table"
      or type(job.run) ~= "function"
      or type(job.stop) ~= "function"
      or type(job.clean) ~= "function" then
    error("Invalid job object provided")
  end
  if type(action) ~= "table" then
    return
  end
  if action.value == "run" then
    job:run()
    show_job_output(job)
  elseif action.value == "stop" then
    job:stop()
  elseif action.value == "output" then
    show_job_output(job)
  elseif action.value == "clean" then
    job:clean()
  end
end

---@param job SpurJob
function show_job_output(job)
  if type(job) ~= "table"
      or type(job.is_quiet) ~= "function" then
    error("Invalid job object provided")
  end
  if not job:is_quiet() then
    local ui = require("spur.core.ui")
    ui.open_job_output(job)
  end
end

---@param job SpurJob|table
function format_job_name(job)
  if type(job) == "table" and job.type == "quickrun" then
    return "[Quick run]"
  end
  if type(job) ~= "table"
      or type(job.get_status) ~= "function"
      or type(job.get_name) ~= "function" then
    error("Invalid job object provided")
  end
  local status = job:get_status()
  local name = job:get_name()
  if status ~= nil then
    name = name .. " (" .. status .. ")"
  end
  return name
end

function is_quick_run(str)
  return string.match(str, "^Quick run %[%d+%]$") ~= nil
end

return M
