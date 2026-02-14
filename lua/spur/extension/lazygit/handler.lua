local SpurJobHandler = require("spur.core.handler")

---@class SpurJobLazyGitCliHandler : SpurJobHandler
local SpurJobLazyGitCliHandler = setmetatable({}, { __index = SpurJobHandler })
SpurJobLazyGitCliHandler.__index = SpurJobLazyGitCliHandler
SpurJobLazyGitCliHandler.__type = "SpurHandler"
SpurJobLazyGitCliHandler.__subtype = "SpurJobLazyGitCliHandler"
SpurJobLazyGitCliHandler.__metatable = SpurJobLazyGitCliHandler

function SpurJobLazyGitCliHandler:new()
  local handler = SpurJobHandler:new()
  local instance = setmetatable(handler, SpurJobLazyGitCliHandler)
  return instance
end

--- Check whether this handler accepts the job
---
--- @param opts table Input fields for SpurJob
--- @param action string What action the job should be accepted for
--- @return boolean
function SpurJobLazyGitCliHandler:accepts_job(opts, action)
  if type(opts) ~= "table" then
    return false
  end
  -- NOTE: This handler overrides all actions
  -- of the default handler, so we accept all actions.
  if type(action) ~= "string" or action == "" then
    return false
  end
  return opts.type == "lazygit"
end

function SpurJobLazyGitCliHandler:open_job_output(job)
  local bufnr = vim.api.nvim_get_current_buf()

  local open = SpurJobHandler.open_job_output(self, job)
  local new_bufnr = nil
  vim.schedule(function()
    new_bufnr = vim.api.nvim_get_current_buf()
    local config = require "spur.config"
    local spur_filetype = config.filetype
    if open and bufnr ~= new_bufnr and spur_filetype == vim.bo.filetype then
      pcall(function()
        vim.api.nvim_command("noautocmd silent! startinsert!")
      end)
      for _, key in ipairs({ "<C-c>", "<S-Esc>", "<C-Esc>" }) do
        vim.keymap.set({ "i", "t" }, key, function()
          return "<Esc>"
        end, {
          buffer = new_bufnr,
          expr = true,
        })
      end
      for _, key in ipairs({ "<Esc>" }) do
        vim.keymap.set({ "i", "t" }, key, function()
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
        end, {
          buffer = new_bufnr,
        })
      end
    else
      new_bufnr = nil
    end
  end)
  return open
end

function SpurJobLazyGitCliHandler.__get_win_opts(title)
  local opts = SpurJobHandler.__get_win_opts(title)
  opts.border = "none"
  return opts
end

return SpurJobLazyGitCliHandler
