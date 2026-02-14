local SpurJobHandler = require("spur.core.handler")

---@class SpurJobLazySqlCliHandler : SpurJobHandler
local SpurJobLazySqlCliHandler = setmetatable({}, { __index = SpurJobHandler })
SpurJobLazySqlCliHandler.__index = SpurJobLazySqlCliHandler
SpurJobLazySqlCliHandler.__type = "SpurHandler"
SpurJobLazySqlCliHandler.__subtype = "SpurJobLazySqlCliHandler"
SpurJobLazySqlCliHandler.__metatable = SpurJobLazySqlCliHandler

function SpurJobLazySqlCliHandler:new()
  local handler = SpurJobHandler:new()
  local instance = setmetatable(handler, SpurJobLazySqlCliHandler)
  return instance
end

--- Check whether this handler accepts the job
---
--- @param opts table Input fields for SpurJob
--- @param action string What action the job should be accepted for
--- @return boolean
function SpurJobLazySqlCliHandler:accepts_job(opts, action)
  if type(opts) ~= "table" then
    return false
  end
  -- NOTE: This handler overrides all actions
  -- of the default handler, so we accept all actions.
  if type(action) ~= "string" or action == "" then
    return false
  end
  return opts.type == "lazysql"
end

function SpurJobLazySqlCliHandler:open_job_output(job)
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
      pcall(function()
        for _, key in ipairs({ "<C-c>", "<S-Esc>", "<C-Esc>" }) do
          vim.keymap.set({ "i", "t" }, key, function()
            self:close_job_output(job)
          end, {
            buffer = new_bufnr,
          })
        end
        for _, key in ipairs({ "<Esc>" }) do
          vim.keymap.set({ "i", "t" }, key, function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n",
              true)
          end, {
            buffer = new_bufnr,
          })
        end
      end)
    else
      new_bufnr = nil
    end
  end)
  return open
end

function SpurJobLazySqlCliHandler.__get_win_opts(title)
  local opts = SpurJobHandler.__get_win_opts(title)
  opts.border = "none"
  return opts
end

return SpurJobLazySqlCliHandler
