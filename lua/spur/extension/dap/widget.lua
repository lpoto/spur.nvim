---@class SpurDapWidget
---@field kind string
---@field job SpurDapJob|nil
---@field widget table|nil
local SpurDapWidget = {}
SpurDapWidget.__index = SpurDapWidget
SpurDapWidget.__type = "SpurDapWidget"

---@param kind string
function SpurDapWidget:new(kind, job)
  if type(kind) ~= "string" or kind == "" then
    error("Invalid kind provided for SpurDapWidget")
  end
  local widgets = require('dap.ui.widgets')
  if type(widgets[kind]) ~= "table" then
    error("Unknown kind provided for SpurDapWidget: " .. kind)
  end
  if type(job) ~= "table"
      or job.__type ~= "SpurJob"
      or type(job.get_name) ~= "function"
  then
    job = nil
  end
  local instance = setmetatable({
    kind = kind,
    job = job,
  }, self)
  return instance
end

function SpurDapWidget:open()
  if type(self.kind) ~= "string" or self.kind == "" then
    error("Invalid kind for SpurDapWidget")
  end
  local widgets = require('dap.ui.widgets')
  if type(widgets[self.kind]) ~= "table" then
    error("Unknown kind for SpurDapWidget: " .. self.kind)
  end
  self:close()
  local title = "[" .. self.kind .. "]"

  if type(self.job) ~= "table"
      or self.job.__type ~= "SpurJob"
      or type(self.job.get_name) ~= "function"
  then
    self.job = nil
  else
    title = title .. " " .. self.job:get_name()
  end

  local def_win_opts = require "spur.core.handler".__get_win_opts(title)

  self.widget = widgets.centered_float(widgets[self.kind])
  if type(self.widget) == "table" then
    if type(self.widget.buf) == "number" then
      local winids = vim.api.nvim_list_wins()
      for _, winid in ipairs(winids) do
        local buf = vim.api.nvim_win_get_buf(winid)
        if buf == self.widget.buf then
          vim.api.nvim_win_set_config(winid, def_win_opts)
        end
      end
    end
  end
  vim.schedule(function()
    self:__add_widget_buf_options()
    self:__add_widget_buf_mappings()
  end)
end

function SpurDapWidget:close()
  if type(self.widget) == "table" then
    local buf = self.widget.buf
    pcall(function()
      local winids = vim.api.nvim_list_wins()
      for _, winid in ipairs(winids) do
        local win_buf = vim.api.nvim_win_get_buf(winid)
        if win_buf == buf or vim.bo[win_buf].filetype:gmatch("^dap-") then
          pcall(vim.api.nvim_win_close, winid, true)
        end
      end
    end)
    if type(buf) == "number" then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    self.widget = nil
  else
    self.widget = nil
  end
end

function SpurDapWidget:__add_widget_buf_options()
  if type(self.widget) ~= "table"
      or type(self.widget.buf) ~= "number"
      or not vim.api.nvim_buf_is_valid(self.widget.buf) then
    return
  end
  local buf = self.widget.buf
  pcall(function()
    vim.bo[buf].swapfile = false
    vim.bo[buf].bufhidden = "wipwipe"
    vim.bo[buf].buflisted = false
    vim.bo[buf].undolevels = -1
  end)

  local to_close = {}
  local winids = vim.api.nvim_list_wins()
  for _, winid in ipairs(winids) do
    if vim.api.nvim_win_get_buf(winid) == buf then
      table.insert(to_close, winid)
    end
  end

  local group = vim.api.nvim_create_augroup("SpurJobAugroup_Dap_Widget", { clear = true })
  local buf_filetype = vim.bo[buf].filetype
  local id
  id = vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    group = group,
    once = false,
    callback = function()
      local close = function()
        local config = require "spur.config"
        local new_buf = vim.api.nvim_get_current_buf()
        if buf == new_buf then
          return false
        end
        local filetype = vim.bo[new_buf].filetype
        local buftype = vim.bo[new_buf].buftype
        if buftype == "prompt"
            and filetype ~= config.filetype
            and filetype ~= buf_filetype then
          return false
        end
        pcall(function()
          for _, winid in ipairs(to_close) do
            pcall(vim.api.nvim_win_close, winid, true)
          end
        end)
        pcall(function()
          vim.api.nvim_del_autocmd(id)
        end)
        return true
      end
      vim.schedule(close)
    end
  })
end

function SpurDapWidget:__add_widget_buf_mappings()
  if type(self.widget) ~= "table"
      or type(self.widget.buf) ~= "number"
      or not vim.api.nvim_buf_is_valid(self.widget.buf) then
    return
  end
  local buf = self.widget.buf
  for _, key in ipairs({ "q", "<Esc>", "Q", "<C-q>" }) do
    vim.keymap.set("n", key, function()
      self:close()
    end, { buffer = buf, desc = "Close widget" })
  end
  if type(self.job) == "table" then
    for _, key in ipairs({ "<C-a>" }) do
      vim.keymap.set({ "n", "i" }, key, function()
        local manager = require "spur.manager"
        manager.select_job_action(self.job)
      end, { buffer = buf, desc = "Select job action" })
    end
  end
end

return SpurDapWidget
