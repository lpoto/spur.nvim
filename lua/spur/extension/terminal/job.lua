local SpurJob = require("spur.core.job")

---@class SpurTerminalJobConfig

---@class SpurTerminalJob : SpurJob
local SpurTerminalJob = setmetatable({}, { __index = SpurJob })
SpurTerminalJob.__index = SpurTerminalJob
SpurTerminalJob.__type = "SpurJob"
SpurTerminalJob.__subtype = "SpurTerminalJob"
SpurTerminalJob.__metatable = SpurTerminalJob

--- Create a new SpurTerminalJob instance.
---
---@return SpurTerminalJob
function SpurTerminalJob:new()
  local opts = {
    order = -99,
    type = "terminal",
    job = {
      cmd = "",
      name = "[Terminal]",
    }
  }
  local spur_job = SpurJob:new(opts)
  local instance = setmetatable(spur_job, SpurTerminalJob)
  ---@diagnostic disable-next-line
  return instance
end

---@param bufnr number|nil
function SpurTerminalJob:__start_job(bufnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    error("SpurTerminalJob instance is not properly initialized")
  end
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("noautocmd terminal")
    vim.cmd("noautocmd silent! startinsert")
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = bufnr,
      once = true,
      callback = function()
        vim.api.nvim_create_autocmd({ "InsertEnter", "TermEnter" }, {
          buffer = bufnr,
          callback = function()
            vim.cmd("noautocmd silent! stopinsert")
          end,
        })
      end,
    })
  end)
end

function SpurTerminalJob:__tostring()
  return string.format("SpurTerminalJob(%s)", self:get_name())
end

function SpurTerminalJob:can_restart()
  return false
end

function SpurTerminalJob:can_run_before_clean()
  return false
end

function SpurTerminalJob:__get_job_id()
  local buf = self:get_bufnr()
  if buf == nil then
    return nil
  end
  local job_id = nil
  pcall(function()
    vim.api.nvim_buf_call(buf, function()
      pcall(function()
        local id = vim.b.terminal_job_id
        local pid = vim.fn.jobpid(id)
        if type(pid) == "number" and pid > 0 then
          job_id = id
        end
      end)
    end)
  end)
  return job_id
end

return SpurTerminalJob
