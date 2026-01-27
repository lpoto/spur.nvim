local M = {}
local jobs = {}
local format_job_name

local handlers = {}
local initialized = false

--- Initialize the job manager -- clearing
--- the current handlers and adding a default handler.
function M.init()
  handlers = {}
  M.add_handler(require "spur.core.handler":new())
  initialized = true
end

--- Check whether init() has already been called
--- @return boolean
function M.is_initialized()
  return initialized
end

--- Add a job handler to the manager.
--- This handler takes care of creating a new
--- job object and displaying its output.
---
--- @param handler SpurJobHandler
function M.add_handler(handler)
  if handler == nil then
    return
  end
  if type(handler) ~= "table"
      or type(handler.new) ~= "function"
      or type(handler.accepts_job) ~= "function"
      or type(handler.create_job) ~= "function"
      or type(handler.open_job_output) ~= "function"
      or type(handler.toggle_job_output) ~= "function"
      or type(handler.close_job_output) ~= "function"
  then
    error("Invalid handler object provided")
  end
  table.insert(handlers, handler)
end

--- Close all open job outputs.
---
--- @return boolean Whether any outputs were closed
function M.close_outputs()
  local did_close = false
  for _, job in pairs(jobs) do
    local handler = M.__find_handler(job, "close_job_output")
    did_close = handler:close_job_output(job) or did_close
  end
  return did_close
end

--- Add a job to the manager.
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
  local handler = M.__find_handler(job, "create_job")
  local new_job = handler:create_job(job)
  if type(new_job) ~= "table"
      or type(new_job.get_id) ~= "function"
      or new_job.__type ~= "SpurJob" then
    error("Invalid SpurJob object returned from handler")
  end
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

local job_is_available

--- Get all currently available jobs
--- @return SpurJob[]
function M.get_jobs()
  local all_jobs = vim.tbl_values(jobs)
  local filtered_jobs = {}
  if type(all_jobs) == "table" then
    for _, job in ipairs(all_jobs) do
      local ok, result = pcall(job_is_available, job)
      if ok and result == true then
        table.insert(filtered_jobs, job)
      end
    end
  end
  return filtered_jobs
end

--- Select a job from the list of available jobs.
--- On selection, the user will be prompted to
--- select an action for the job.
---
--- @param selection string|nil Preselected job name
--- @param filter function|nil select only from
--- @param on_select function|nil custom on select handler
--- @param skip_selection_if_one_result boolean|nil Auto select a single result
--- jobs that pass the filter.
function M.select_job(selection, filter, on_select, skip_selection_if_one_result)
  if type(jobs) ~= "table" then
    return
  end
  local filtered_jobs = {}
  for _, job in ipairs(vim.tbl_values(M.get_jobs())) do
    local handler = M.__find_handler(job, "__get_job_actions")
    if #handler:__get_job_actions(job) > 0 then
      if type(filter) ~= "function" then
        table.insert(filtered_jobs, job)
      else
        local ok, result = pcall(filter, job)
        if ok and result == true then
          table.insert(filtered_jobs, job)
        end
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
    if a.order == b.order then
      return a:get_id() < b:get_id()
    end
    if a.order == nil then
      return b.order ~= nil and b.order < 0
    end
    if b.order == nil then
      return a.order == nil or a.order >= 0
    end
    if a.order < 0 then
      return b.order < a.order
    end
    if b.order < 0 then
      return a.order > b.order
    end
    return a.order < b.order
  end)
  if #filtered_jobs == 0 then
    local title = require "spur.config".title
    vim.notify("No jobs found", vim.log.levels.WARN, { title = title })
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
  if type(selection) == "string" and selection ~= "" then
    for _, job in ipairs(filtered_jobs) do
      if job.name == selection then
        return select(job)
      end
    end
    for _, job in ipairs(filtered_jobs) do
      if format_job_name(job) == selection then
        return select(job)
      end
    end
  elseif #filtered_jobs == 1 and skip_selection_if_one_result == true then
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

--- Find a handler for the job.
---
--- @param job SpurJob|table
--- @param action string
function M.__find_handler(job, action)
  if type(job) ~= "table" then
    error("Invalid job data provided")
  end
  action = action or ""
  --- iterate handlers in reverse order,
  --- so latest ones added have priority
  for i = #handlers, 1, -1 do
    local handler = handlers[i]
    if handler:accepts_job(job, action) then
      return handler
    end
  end
  error("No handler found for action '" .. action .. "' for the provided job")
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
  local handler = M.__find_handler(job, "__get_job_actions")
  local actions = handler:__get_job_actions(job)
  if #actions == 0 then
    local title = require "spur.config".title
    vim.notify(
      "No actions available for this job",
      vim.log.levels.WARN,
      { title = title })
    return
  end
  local count = 0
  for _, action in ipairs(actions) do
    if action.value ~= "_back" then
      count = count + 1
    end
  end
  if count == 1 and actions[1].value == "run" then
    return handler:__execute_job_action(job, actions[1])
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
      handler:__execute_job_action(job, choice)
    end
  )
end

---@param job SpurJob|table
function format_job_name(job)
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

---@param job SpurJob
---@return boolean
function job_is_available(job)
  if type(job) ~= "table" or job.__type ~= "SpurJob" then
    return false
  end
  if type(job.__is_available) ~= "function" then
    return false
  end
  return job:__is_available()
end

return M
