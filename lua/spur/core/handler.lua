---@class SpurJobHandler
local SpurJobHandler = {}
SpurJobHandler.__index = SpurJobHandler
SpurJobHandler.__type = "SpurJobHandler"


function SpurJobHandler:new()
  return setmetatable({}, SpurJobHandler)
end

--- @param o SpurJob or input table for a SpurJob
--- @param action string What action the job should be accepted for
--- @return boolean Whether the job handler accepts the provided job
function SpurJobHandler:accepts_job(o, action)
  -- NOTE: The default handler should accept all
  -- jobs at it will have the lowest priority.
  -- It should also accept all actions.
  return type(o) == "table"
      and type(action) == "string"
      and action ~= ""
end

---@param o table Input fields for SpurJob
---@return SpurJob
function SpurJobHandler:create_job(o)
  return require "spur.core.job":new(o)
end

--- Open the output window for the provided job,
--- or close it if it is already open.
--- Returns true if the output window was opened,
---
--- @param job SpurJob
--- @para
function SpurJobHandler:toggle_job_output(job)
  if SpurJobHandler:close_job_output(job) then
    return false
  end
  return SpurJobHandler:open_job_output(job)
end

--- Close the window containing output for
--- the provided job. And return true if
--- any windows were closed.
---
--- @param job SpurJob
--- @return boolean
function SpurJobHandler:close_job_output(job)
  if type(job) ~= "table" or type(job.get_bufnr) ~= "function" then
    error("Invalid job object provided")
  end
  local bufnr = job:get_bufnr()
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local config = require "spur.config"
  local closed = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if buf == bufnr or
        (vim.bo[buf].filetype == config.filetype
          and vim.bo[buf].buftype == "prompt")
    then
      vim.api.nvim_win_close(win, true)
      closed = true
    end
  end
  return closed
end

--- Open the output window for the provided job,
--- or focus it if it is already open.
---
--- @param job SpurJob
--- @return boolean Wether the window has been opened
function SpurJobHandler:open_job_output(job)
  if job == nil then
    return false
  end
  if type(job) ~= "table"
      or type(job.get_bufnr) ~= "function"
      or type(job.get_id) ~= "function"
      or type(job.is_quiet) ~= "function"
  then
    error("Invalid job object provided")
  end
  if job:is_quiet() then
    return false
  end
  local bufnr = job:get_bufnr()
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    error("SpurJob buffer is not available")
  end
  local config = require "spur.config"
  local existing_spur_windows = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      -- If the window is already open, we just focus it
      -- instead of opening a new one.
      vim.api.nvim_set_current_win(win)
      return false
    elseif config.filetype == vim.bo[vim.api.nvim_win_get_buf(win)].filetype then
      -- collect existing spur output windows,
      -- so we can close them after we open a new window.
      table.insert(existing_spur_windows, win)
    end
  end
  self:__open_float(job, bufnr)

  -- Go over the spur windows that existed before
  -- opening the new one, and close them, so that
  -- we always have only one output window open at a time.
  for _, win in ipairs(existing_spur_windows) do
    vim.api.nvim_win_close(win, true)
  end
  return true
end

function SpurJobHandler:__open_float(job, bufnr, name)
  if type(name) ~= "string" or name == "" then
    name = "[output] " .. job:get_name()
  end

  local win_opts = self.__get_win_opts(name)

  local win_id = vim.api.nvim_open_win(bufnr, true, win_opts)
  self:__set_output_window_options(win_id, job)
  self:__set_output_window_mappings(job)
  return win_id
end

function SpurJobHandler.__get_win_opts(title)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.9)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  return {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    title = title,
    title_pos = "center",
    style = "minimal",
    border = "rounded",
  }
end

--- Add options and autocommands to the output window.
---
--- @param win_id number
--- @param job SpurJob
function SpurJobHandler:__set_output_window_options(win_id, job)
  if type(job) ~= "table" or type(job.get_bufnr) ~= "function" then
    error("Invalid job object provided")
  end
  if type(win_id) ~= "number" or not vim.api.nvim_win_is_valid(win_id) then
    error("Invalid window ID provided")
  end
  vim.wo[win_id].wrap = true
  vim.wo[win_id].wrap = true
  vim.wo[win_id].number = false
  vim.wo[win_id].number = false
  vim.wo[win_id].relativenumber = false
  vim.wo[win_id].signcolumn = "no"
  vim.wo[win_id].statusline = ""

  local group = vim.api.nvim_create_augroup("SpurJobAugroup_Win", { clear = true })
  local id
  id = vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    group = group,
    once = false,
    callback = function()
      local close = function()
        local config = require "spur.config"
        local new_buf = vim.api.nvim_get_current_buf()
        local filetype = vim.bo[new_buf].filetype
        if job:get_bufnr() == new_buf then
          if filetype == config.filetype then
            -- If the current buffer is a spur output buffer,
            -- we don't want to close it, so we just return.
            return false
          end
        end
        local buftype = vim.bo[new_buf].buftype
        if buftype == "prompt" and filetype ~= config.filetype then
          return false
        end
        if not win_id or win_id == -1 or not vim.api.nvim_win_is_valid(win_id) then
          return false
        end
        pcall(function()
          vim.api.nvim_win_close(win_id, true)
        end)
        pcall(function()
          self:close_job_output(job)
        end)
        pcall(function()
          vim.api.nvim_del_autocmd(id)
        end)
        return true
      end
      vim.schedule(close)
    end,
  })
end

--- Add keymaps to the output window.
---
--- @param job SpurJob
function SpurJobHandler:__set_output_window_mappings(job)
  if type(job) ~= "table" or type(job.get_bufnr) ~= "function" then
    error("Invalid window ID provided")
  end
  local bufnr = job:get_bufnr()
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    error("SpurJob buffer is not available")
  end
  for _, key in ipairs({ "<C-c>", "<C-\\>" }) do
    vim.keymap.set({ "n", "i", "t" }, key, function()
      vim.schedule(function()
        job:kill()
      end)
    end, { buffer = job:get_bufnr(), desc = "Stop a running job" })
  end
  for _, key in ipairs({ "<C-x>" }) do
    vim.keymap.set({ "n", "i", "t" }, key, "<Esc>")
  end
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      vim.schedule(function()
        self:close_job_output(job)
      end)
    end, { buffer = job:get_bufnr(), desc = "Close job output window" })
  end
  for _, key in ipairs({ "Q", "<C-q>" }) do
    vim.keymap.set("n", key, function()
      vim.schedule(function()
        job:clean()
      end)
    end, { buffer = job:get_bufnr(), desc = "Clean job output" })
  end
  local action_mappings = require "spur.config".get_mappings(
    "actions",
    { key = "<C-a>", mode = { "n", "i" } }
  )
  for _, mapping in ipairs(action_mappings) do
    pcall(function()
      vim.keymap.set(mapping.mode, mapping.key, function()
        vim.schedule(function()
          local manager = require "spur.manager"
          manager.select_job_action(job)
        end)
      end, { buffer = job:get_bufnr(), desc = "Select job action" })
    end)
  end
end

---@return boolean
function SpurJobHandler:__output_is_focused(job)
  if type(job) ~= "table" or type(job.get_bufnr) ~= "function" then
    return false
  end
  local ok, buf = pcall(job.get_bufnr, job)
  if not ok or type(buf) ~= "number" then
    return false
  end
  local got_buf, cur_buf = pcall(function() return vim.api.nvim_get_current_buf() end)
  return got_buf and cur_buf == buf
end

---@param job SpurJob
---@return table[]
function SpurJobHandler:__get_job_actions(job)
  local options = {}
  if type(job) ~= "table"
      or type(job.is_running) ~= "function"
      or type(job.get_bufnr) ~= "function" then
    error("Invalid job object provided")
  end
  if job:can_run() and not job:is_running() then
    table.insert(options, { label = "Run", value = "run" })
  end
  if job:can_show_output() then
    if not job:is_quiet() and not self:__output_is_focused(job) then
      table.insert(options, { label = "Output", value = "output" })
    end
  end
  if job:is_running() then
    table.insert(options, { label = "Kill", value = "kill" })
  end
  if job:can_show_output() then
    table.insert(options, { label = "Clean", value = "clean" })
  end
  table.insert(options, { label = "[Back]", value = "_back" })
  return options
end

---@param job SpurJob
---@param action table
function SpurJobHandler:__execute_job_action(job, action)
  if type(job) ~= "table"
      or type(job.run) ~= "function"
      or type(job.kill) ~= "function"
      or type(job.clean) ~= "function" then
    error("Invalid job object provided")
  end
  if type(action) ~= "table" then
    return false
  end
  if action.value == "run" then
    vim.schedule(function()
      job:run()
      vim.schedule(function()
        if job:is_running() and not job:is_quiet() then
          self:open_job_output(job)
        end
      end)
    end)
  elseif action.value == "kill" then
    vim.schedule(function()
      job:kill()
    end)
  elseif action.value == "output" then
    vim.schedule(function()
      if not job:is_quiet() then
        self:open_job_output(job)
      end
    end)
  elseif action.value == "clean" then
    vim.schedule(function()
      job:clean()
    end)
  elseif action.value == "_back" then
    vim.schedule(function()
      local manager = require "spur.manager"
      manager.select_job()
    end)
  else
    return false
  end
  return true
end

return SpurJobHandler
