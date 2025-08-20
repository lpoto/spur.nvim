---@class SpurDapWriter
---@field __buffer number
---@field __processing boolean
---@field __waiting boolean
---@field __write_delay_ms number
local SpurDapWriter = {}
SpurDapWriter.__index = SpurDapWriter
SpurDapWriter.__type = "SpurDapWriter"

local create_job_buffer

---@class SpurWriteInput
---@field hl string|nil
---@field message string|table


---@class SpurDapWriterNormalizedInput
---@field text string
---@field highlights SpurDapWriterHighlight[]|nil

---@class SpurDapWriterHighlight
---@field start_col number|nil
---@field end_col number|nil
---@field hl string

---@param job SpurJob
function SpurDapWriter:new(job)
  local instance = setmetatable({
    __buffer = create_job_buffer(job),
    __write_delay_ms = 50,
  }, self)
  return instance
end

---@type SpurWriteInput[]
local queue = {}
local group_inputs

---@return number|nil
function SpurDapWriter:get_bufnr()
  local bufnr = self.__buffer
  if type(bufnr) ~= "number" then
    return nil
  end
  return bufnr
end

---@param o SpurWriteInput
function SpurDapWriter:write(o)
  if not o or type(o) ~= "table" then
    return
  end
  local bufnr = self:get_bufnr()
  if type(bufnr) ~= "number" then
    return
  end
  if type(o.message) ~= "string" and type(o.message) ~= "table" then
    return
  end
  table.insert(queue, o)
  if self.__waiting then
    return
  end
  local delay = self.__write_delay_ms
  if type(delay) ~= "number" or delay < 1 then
    delay = 1
  end
  self.__waiting = true
  vim.defer_fn(function()
    self.__waiting = false
    if self.__processing then
      return
    end
    self.__processing = true
    pcall(function()
      self:__empty_queue()
    end)
    self.__processing = false
  end, delay)
end

function SpurDapWriter:write_remainder()
  if type(self.__remainder) ~= "string"
      or self.__remainder == ""
  then
    return
  end
  local remainder = self.__remainder
  self:write({
    hl = nil,
    message = remainder .. "\n",
  })
end

function SpurDapWriter:__empty_queue()
  if type(queue) ~= "table" or #queue == 0 then
    return
  end
  local processing_queue = queue
  queue = {}
  local to_write = {}
  for _, o in ipairs(processing_queue) do
    local last = to_write[#to_write]
    local n = type(last) == "table" and group_inputs(last, o)
    if type(n) == "table" then
      table.remove(to_write, #to_write)
      table.insert(to_write, n)
    else
      table.insert(to_write, o)
    end
  end
  for _, o in ipairs(to_write) do
    local lines = self:__normalize_lines(o.message, o.hl)
    if type(lines) == "table" then
      self:__write_lines(lines)
    end
  end
end

local post_process_line
local pre_process_line

---@param message string
---@return nil|SpurDapWriterNormalizedInput[]
function SpurDapWriter:__normalize_lines(message, hl)
  local lines = nil
  if type(message) == "string" then
    lines = self:__normalize_lines_from_string(message)
  end
  if type(lines) ~= "table" then
    return nil
  end
  local config = require "spur.config"
  local actual_lines = {}
  for _, line in ipairs(lines) do
    local n = post_process_line(line, hl, config)
    if n ~= nil then
      table.insert(actual_lines, n)
    end
  end
  return actual_lines
end

function SpurDapWriter:__normalize_lines_from_string(message)
  local lines = {}
  if type(message) ~= "string" then
    return lines
  end
  message = pre_process_line(message)
  if type(self.__remainder) == "string" and self.__remainder ~= "" then
    message = self.__remainder .. message
    self.__remainder = nil
  end
  local ends_with_newline = message:sub(-1) == "\n"

  for line in message:gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  local last = message:match("([^\n]*)$") -- get the last part after the last newline
  if last ~= "" then
    table.insert(lines, last)
  end

  if not ends_with_newline then
    self.__remainder = lines[#lines]
    table.remove(lines, #lines)
    if #table == 0 then
      return nil
    end
  end
  return lines
end

local focus = nil

---@param lines SpurDapWriterNormalizedInput[]
function SpurDapWriter:__write_lines(lines)
  vim.schedule(function()
    local bufnr = self:get_bufnr()
    if type(bufnr) ~= "number" then
      return
    end
    if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if type(lines) ~= "table" then
      return
    end
    local modifiable = vim.bo[bufnr].modifiable
    local readonly = vim.bo[bufnr].readonly
    local mode = vim.api.nvim_get_mode().mode
    local in_insert_mode = mode:sub(1, 1) == "i"
        or mode:sub(1, 1) == "r"
        or mode:sub(1, 1) == "R"
        or mode:sub(1, 1) == "I"
    if in_insert_mode then
      pcall(function()
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("stopinsert")
        end)
      end)
    end

    pcall(function()
      local has_focus = bufnr == vim.api.nvim_get_current_buf()
      local move_to_end = false
      if has_focus then
        local cursor = vim.api.nvim_win_get_cursor(0)
        local had_focus = focus == bufnr
        move_to_end = not had_focus or cursor[1] == vim.api.nvim_buf_line_count(bufnr)
        focus = bufnr
      else
        focus = nil
      end
      local a = -1
      local b = -1
      local last_line = vim.api.nvim_buf_line_count(bufnr)
      -- if the file is empty write on line 0 instead
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      if line_count == 0 or line_count == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == "" then
        move_to_end = has_focus
        a = 0
        b = 0
        last_line = 0
      end
      vim.bo[bufnr].modifiable = true
      vim.bo[bufnr].readonly = false

      local added = {}
      local texts = {}
      for _, line in ipairs(lines) do
        if type(line) == "table" and type(line.text) == "string" then
          table.insert(texts, line.text)
          table.insert(added, line)
        end
      end
      vim.api.nvim_buf_set_lines(bufnr, a, b, false, texts)
      local added_lines = #texts
      pcall(function()
        for i = 1, added_lines do
          local line = added[i]
          if type(line) == "table"
              and type(line.highlights) == "table"
              and #line.highlights > 0
          then
            local line_nr = last_line + i - 1
            for _, o in ipairs(line.highlights) do
              if type(o.hl) == "string" and o.hl ~= "" then
                pcall(function()
                  local start_col = o.start_col or 0
                  local end_col = o.end_col or -1
                  ---@diagnostic disable-next-line
                  vim.api.nvim_buf_add_highlight(bufnr, -1, o.hl, line_nr, start_col, end_col)
                end)
              end
            end
          end
        end
      end)

      vim.bo[bufnr].modified = false
      if move_to_end and has_focus then
        vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(bufnr), 0 })
      end
    end)
    vim.bo[bufnr].modifiable = modifiable
    vim.bo[bufnr].readonly = readonly
    if in_insert_mode then
      pcall(function()
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("startinsert")
          vim.bo[bufnr].modified = false
        end)
      end)
    end
  end)
end

function group_inputs(i1, i2)
  if type(i1) ~= "table" or type(i2) ~= "table" then
    return false
  end
  if i1.hl ~= i2.hl then
    return false
  end
  if i1.message == nil or type(i1.message) ~= type(i2.message) then
    return false
  end
  local new_message = i1.message
  if type(new_message) == "string" then
    new_message = new_message .. i2.message
  elseif type(new_message) == "table" then
    for _, line in ipairs(i2.message) do
      table.insert(new_message, line)
    end
  else
    return false
  end
  return {
    hl = i1.hl,
    message = new_message,
  }
end

---@param str string
---@return string
function pre_process_line(str)
  if type(str) ~= "string" then
    return str
  end
  local s = str:gsub('\r', '')
  return s
end

local get_default_highlights

---@param str string
---@param hl string
---@param config SpurConfig
---@return SpurDapWriterNormalizedInput|nil
function post_process_line(str, hl, config)
  if type(str) ~= "string" then
    return nil
  end
  local highlights = nil
  local old_str = str
  str = str:gsub('\27%[[%d;]*m', '')
  pcall(function()
    if type(config) == "table" then
      if type(config.custom_hl) == "function" then
        highlights = config.custom_hl(old_str)
      elseif config.custom_hl == true then
        highlights = get_default_highlights(old_str, str, hl, config)
      end
    end
    if type(highlights) ~= "table" then
      highlights = nil
    end
  end)
  return {
    text = str,
    highlights = highlights
  }
end

local ansi_to_hl

--- @param str_with_ansi string
--- @param str string
--- @param hl string|nil
--- @param config SpurConfig
--- @return SpurDapWriterHighlight[]|nil
function get_default_highlights(str_with_ansi, str, hl, config)
  if type(config) ~= "table" then
    return nil
  end
  local highlihts = {}

  if type(str) ~= "string" or str == "" then
    return nil
  end

  local prefix = config.prefix
  local prefix_len = type(config.prefix) == "string" and #prefix or 0
  if type(hl) == "string" and hl ~= "" then
    table.insert(highlihts, {
      start_col = 0,
      end_col = -1,
      hl = hl,
    })
  end
  if
      prefix_len > 0
      and #str >= prefix_len
      and str:sub(1, prefix_len) == prefix then
    table.insert(highlihts, {
      end_col = prefix_len,
      start_col = 0,
      hl = config.hl.prefix,
    })
  end
  if #highlihts > 0 then
    return highlihts
  end

  if type(str_with_ansi) == "string" and str_with_ansi ~= str then
    -- Parse ANSI escape codes for highlights
    local ansi_escape = "\27%[([%d;]*)m"
    local last_end = 1
    local col = 0
    local active_hl = nil
    local s = str_with_ansi
    while true do
      local start_idx, end_idx, codes = s:find(ansi_escape, last_end)
      if not start_idx then break end
      if start_idx > last_end then
        if active_hl then
          table.insert(highlihts, {
            start_col = col,
            end_col = col + (start_idx - last_end),
            hl = active_hl,
          })
        end
        col = col + (start_idx - last_end)
      end
      -- Only use the first code for simplicity
      local code = codes:match("(%d+)")
      active_hl = ansi_to_hl(code, config)
      last_end = end_idx + 1
    end
    -- Handle trailing text after last escape
    if last_end <= #s and active_hl then
      table.insert(highlihts, {
        start_col = col,
        end_col = -1,
        hl = active_hl,
      })
    end
    if #highlihts > 0 then
      return highlihts
    end
  end

  --- NOTE: Next we define some of our custom highlights,
  --- that are not covered by the ansi codes.
  ---
  --- These should be more sophisticated,
  --- and maybe based on the job's cmd.

  if str:match("^make: *** ") or str:match("^Makefile:") then
    table.insert(highlihts, {
      start_col = 0,
      end_col = -1,
      hl = config.hl.debug,
    })
    return highlihts
  end

  local build_successful = str:match("^BUILD SUCCESSFUL ")
  if build_successful then
    table.insert(highlihts, {
      start_col = 0,
      end_col = #build_successful,
      hl = config.hl.success,
    })
    return highlihts
  end
  local build_failed = str:match("^BUILD FAILED ")
  if build_failed then
    table.insert(highlihts, {
      start_col = 0,
      end_col = #build_failed,
      hl = config.hl.error,
    })
    return highlihts
  end
  local failure = str:match("^FAILURE: ")
  if failure then
    table.insert(highlihts, {
      start_col = 0,
      end_col = #failure,
      hl = config.hl.error,
    })
    return highlihts
  end
  for _, p in ipairs({ "^> " }) do
    if str:match(p) then
      table.insert(highlihts, {
        start_col = 0,
        end_col = -1,
        hl = config.hl.debug,
      })
      return highlihts
    end
  end

  if str:match("^> Task :") then
    table.insert(highlihts, {
      start_col = 0,
      end_col = #str,
      hl = config.hl.debug,
    })
    return highlihts
  end
  return highlihts
end

local set_output_buf_options
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

---@param ansi_code string
function ansi_to_hl(ansi_code, config)
  if type(ansi_code) == "number" then
    ansi_code = tostring(ansi_code)
  end
  if type(ansi_code) ~= "string" or ansi_code == "" then
    return nil
  end
  local map = {
    -- Foreground colors
    ["30"] = config.hl.black or "Comment",
    ["31"] = config.hl.error or "ErrorMsg",
    ["32"] = config.hl.success or "String",
    ["33"] = config.hl.warn or "WarningMsg",
    ["34"] = config.hl.info or "Information",
    ["35"] = config.hl.debug or "Comment",
    ["36"] = config.hl.hint or "Special",
    ["37"] = config.hl.default or "Normal",

    -- Bright foreground colors
    ["90"] = config.hl.black or "Comment",
    ["91"] = config.hl.error or "ErrorMsg",
    ["92"] = config.hl.success or "String",
    ["93"] = config.hl.warn or "WarningMsg",
    ["94"] = config.hl.info or "Information",
    ["95"] = config.hl.debug or "Comment",
    ["96"] = config.hl.hint or "Special",
    ["97"] = config.hl.default or "Normal",

    -- Reset and default
    ["0"] = config.hl.default or "Normal",
    ["39"] = config.hl.default or "Normal",

    -- Styles (bold, underline, etc.)
    ["1"] = config.hl.bold or "Bold",
    ["4"] = config.hl.underline or "Underlined",
    ["22"] = config.hl.default or "Normal", -- Normal intensity
    ["2"] = config.hl.default or "NonText", -- Faint

    -- Background colors (optional, map to existing highlights or define new ones)
    ["40"] = config.hl.bg_black or "Normal",
    ["41"] = config.hl.bg_error or "ErrorMsg",
    ["42"] = config.hl.bg_success or "String",
    ["43"] = config.hl.bg_warn or "WarningMsg",
    ["44"] = config.hl.bg_info or "Information",
    ["45"] = config.hl.bg_debug or "Comment",
    ["46"] = config.hl.bg_hint or "Special",
    ["47"] = config.hl.bg_default or "Normal",

    -- Bright backgrounds
    ["100"] = config.hl.bg_black or "Normal",
    ["101"] = config.hl.bg_error or "ErrorMsg",
    ["102"] = config.hl.bg_success or "String",
    ["103"] = config.hl.bg_warn or "WarningMsg",
    ["104"] = config.hl.bg_info or "Information",
    ["105"] = config.hl.bg_debug or "Comment",
    ["106"] = config.hl.bg_hint or "Special",
    ["107"] = config.hl.bg_default or "Normal",
  }
  return map[ansi_code]
end

return SpurDapWriter
