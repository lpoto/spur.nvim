local M = {}

-- TODO: Support custom configs for the window,
-- maybe for a start just a custom function that opens
-- a window (replaces open_job_output alltogether)

--- Open a new window containing the output
--- of the provided job, and return true
--- if any windows were opened.
--- No windows will be opened if the job
--- already has an output window shown.
---
--- @param job SpurJob
--- @return boolean
function M.open_job_output(job)
  if type(job) ~= "table" or type(job.get_bufnr) ~= "function" then
    error("Invalid job object provided")
  end

  local bufnr = job:get_bufnr()
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    error("SpurJob buffer is not available")
  end
  local existing_spur_windows = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      -- If the window is already open, we just focus it
      -- instead of opening a new one.
      vim.api.nvim_set_current_win(win)
      return false
    elseif "spur-output" == vim.bo[vim.api.nvim_win_get_buf(win)].filetype then
      -- collect existing spur output windows,
      -- so we can close them after we open a new window.
      table.insert(existing_spur_windows, win)
    end
  end

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.9)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    title = job:get_name(),
    title_pos = "center",
    style = "minimal",
    border = "rounded",
  }

  local win_id = vim.api.nvim_open_win(bufnr, true, win_opts)
  M.set_output_window_options(win_id, job)
  M.set_output_window_mappings(job)

  -- Go over the spur windows that existed before
  -- opening the new one, and close them, so that
  -- we always have only one output window open at a time.
  for _, win in ipairs(existing_spur_windows) do
    vim.api.nvim_win_close(win, true)
  end
  return true
end

--- Close the window containing output for
--- the provided job. And return true if
--- any windows were closed.
---
--- @param job SpurJob
--- @return boolean
function M.close_job_output(job)
  if type(job) ~= "table" or type(job.get_bufnr) ~= "function" then
    error("Invalid job object provided")
  end
  local bufnr = job:get_bufnr()
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    error("SpurJob buffer is not available")
  end
  local closed = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_win_close(win, true)
      closed = true
    end
  end
  return closed
end

--- Open the output window for the provided job,
--- or close it if it is already open.
--- Returns true if the output window was opened,
---
--- @param job SpurJob
--- @para
function M.toggle_job_output(job)
  if M.close_job_output(job) then
    return false
  end
  return M.open_job_output(job)
end

--- Add keymaps to the output window.
---
--- @param job SpurJob
function M.set_output_window_mappings(job)
  if type(job) ~= "table" or type(job.get_bufnr) ~= "function" then
    error("Invalid window ID provided")
  end
  local bufnr = job:get_bufnr()
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    error("SpurJob buffer is not available")
  end
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      M.close_job_output(job)
    end, { buffer = job:get_bufnr(), desc = "Close job output window" })
  end
  for _, key in ipairs({ "<C-a>" }) do
    vim.keymap.set({ "n", "i" }, key, function()
      local manager = require "spur.core.manager"
      manager.select_job_action(job)
    end, { buffer = job:get_bufnr(), desc = "Select job action" })
  end
end

--- Add options and autocommands to the output window.
---
--- @param win_id number
--- @param job SpurJob
function M.set_output_window_options(win_id, job)
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

  local buf = vim.api.nvim_win_get_buf(win_id)

  local group = vim.api.nvim_create_augroup("SpurJobAugroup_Win", { clear = true })
  vim.api.nvim_clear_autocmds({
    event = { "BufLeave" },
    buffer = buf,
    group = group,
  })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      local wid = vim.fn.bufwinid(buf)
      if not wid or wid == -1 or not vim.api.nvim_win_is_valid(wid) then
        return
      end
      M.close_job_output(job)
    end,
  })
end

return M
