---@class SpurWriter
---@field __buffer number
---@field __processing boolean
---@field __waiting boolean
---@field __write_delay_ms number
local SpurWriter = {}
SpurWriter.__index = SpurWriter
SpurWriter.__type = "SpurWriter"

---@class SpurWriteInput
---@field hl string|nil
---@field message string|table

---@param bufnr number
function SpurWriter:new(bufnr)
  if not bufnr or type(bufnr) ~= "number" then
    error("Invalid buffer number provided. It must be a number.")
  end
  local instance = setmetatable({
    __buffer = bufnr,
    __write_delay_ms = 50,
  }, self)
  return instance
end

---@type SpurWriteInput[]
local queue = {}
local group_inputs

---@param o SpurWriteInput
function SpurWriter:write(o)
  if not o or type(o) ~= "table" then
    return
  end
  local bufnr = self.__buffer
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

function SpurWriter:write_remainder()
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

function SpurWriter:__empty_queue()
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
    local lines = self:__normalize_lines(o.message)
    if type(lines) == "table" then
      self:__write_lines(lines, o.hl)
    end
  end
end

function SpurWriter:__normalize_lines(message)
  if type(message) == "table" then
    return self:__normalize_lines_from_table(message)
  elseif type(message) == "string" then
    return self:__normalize_lines_from_string(message)
  else
    return nil
  end
end

--- NOTE: This is still unstable, and needs to be improved
--- to properly handle newlines,... as this usually receives
--- output from stdout and stderr and the lines are all weird.
function SpurWriter:__normalize_lines_from_table(message)
  local lines = {}
  if type(message) ~= "table" then
    return lines
  end
  local last_empty = 1
  for _, line in ipairs(message) do
    if type(line) == "string" then
      if line == "" then
        if last_empty > 1 then
          table.insert(lines, "")
        end
        last_empty = last_empty + 1
      elseif last_empty == 0 then
        local last_line = lines[#lines]
        if last_line:sub(-1) == " " or line:sub(1, 1) == " " then
          lines[#lines] = last_line .. line
        else
          table.insert(lines, line)
        end
      else
        last_empty = 0
        table.insert(lines, line)
      end
    end
  end
  return lines
end

function SpurWriter:__normalize_lines_from_string(message)
  local lines = {}
  if type(message) ~= "string" then
    return lines
  end
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
function SpurWriter:__write_lines(lines, hl)
  local bufnr = self.__buffer
  if type(bufnr) ~= "number" then
    return
  end
  vim.schedule(function()
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
        last_line = -1
      end
      vim.bo[bufnr].modifiable = true
      vim.bo[bufnr].readonly = false
      vim.api.nvim_buf_set_lines(bufnr, a, b, false, lines)
      local added_lines = #lines
      for i = 1, added_lines do
        local line_nr = last_line + i
        local line_text = vim.api.nvim_buf_get_lines(bufnr, line_nr, line_nr + 1, false)[1] or ""
        self:__highlight_line({
          bufnr = bufnr,
          text = line_text,
          row = line_nr,
          hl = hl,
        })
      end

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

local handle_default_highlights

function SpurWriter:__highlight_line(opts)
  pcall(function()
    local text = opts.text
    if type(text) ~= "string" or text == "" then
      return
    end
    local hl = opts.hl
    if type(hl) ~= "string" or hl == "" then
      hl = nil
    end

    local bufnr = opts.bufnr
    local row = opts.row
    local start_col = 0
    local last_col = #text
    local config = require "spur.config"
    local prefix = config.prefix
    local prefix_len = #prefix
    if
        prefix_len > 0
        and #text >= prefix_len
        and text:sub(1, prefix_len) == prefix then
      start_col = prefix_len
      ---@diagnostic disable-next-line
      vim.api.nvim_buf_add_highlight(bufnr, -1, config.hl.prefix, row, 0, start_col)
    elseif type(hl) ~= "string" or hl == "" then
      handle_default_highlights(bufnr, text, row, config)
    end
    if type(hl) ~= "string" or hl == "" then
      return
    end
    ---@diagnostic disable-next-line
    vim.api.nvim_buf_add_highlight(bufnr, -1, hl, row, start_col, last_col)
  end)
end

--- Add some custom highlights to the written row,
--- by checking for some common patterns.
---
--- If config.custom_hl is a function, it will be called instead.
---
--- If config.custom_hl ~= true, the default highlights will
--- not be applied.
function handle_default_highlights(bufnr, text, row, config)
  if type(text) ~= "string" or text == "" then
    return
  end
  if type(config) ~= "table" then
    return
  end
  if type(config.hl) ~= "table" then
    return
  end
  vim.schedule(function()
    if type(config.custom_hl) == "function" then
      return config.custom_hl(text, row)
    end
    if config.custom_hl ~= true then
      return
    end
    local build_successful = text:match("^BUILD SUCCESSFUL ")
    if build_successful then
      local partial_hl = config.hl.success
      ---@diagnostic disable-next-line
      vim.api.nvim_buf_add_highlight(bufnr, -1, partial_hl, row, 0, #build_successful)
      return
    end
    if text:match("^> Task :") then
      local partial_hl = config.hl.debug
      ---@diagnostic disable-next-line
      vim.api.nvim_buf_add_highlight(bufnr, -1, partial_hl, row, 0, -1)
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

return SpurWriter
