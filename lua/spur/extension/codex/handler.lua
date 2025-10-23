local SpurJobHandler = require("spur.core.handler")

---@class SpurJobCodexCliHandler : SpurJobHandler
local SpurJobCodexCliHandler = setmetatable({}, { __index = SpurJobHandler })
SpurJobCodexCliHandler.__index = SpurJobCodexCliHandler
SpurJobCodexCliHandler.__type = "SpurHandler"
SpurJobCodexCliHandler.__subtype = "SpurJobCodexCliHandler"
SpurJobCodexCliHandler.__metatable = SpurJobCodexCliHandler

function SpurJobCodexCliHandler:new()
  local handler = SpurJobHandler:new()
  local instance = setmetatable(handler, SpurJobCodexCliHandler)
  return instance
end

--- Check whether this handler accepts the job
---
--- @param opts table Input fields for SpurJob
--- @param action string What action the job should be accepted for
--- @return boolean
function SpurJobCodexCliHandler:accepts_job(opts, action)
  if type(opts) ~= "table" then
    return false
  end
  -- NOTE: This handler overrides all actions
  -- of the default handler, so we accept all actions.
  if type(action) ~= "string" or action == "" then
    return false
  end
  return opts.type == "codex-cli"
end

---@param job SpurJob
---@return table[]
function SpurJobCodexCliHandler:__get_job_actions(job)
  local actions = SpurJobHandler.__get_job_actions(self, job)
  local new_actions = {}
  if type(actions) == "table" then
    for _, action in ipairs(actions) do
      table.insert(new_actions, action)
      if type(action) == "table" and action.value == "run" then
        table.insert(new_actions, { label = "Resume", value = "resume" })
      end
    end
  end
  return new_actions
end

function SpurJobCodexCliHandler:__execute_job_action(job, action)
  if SpurJobHandler.__execute_job_action(self, job, action) then
    return
  end
  if type(action) == "table" and action.value == "resume" then
    vim.schedule(function()
      job:run("resume")
      vim.schedule(function()
        if job:is_running() and not job:is_quiet() then
          self:open_job_output(job)
        end
      end)
    end)
    return true
  end
  return false
end

function SpurJobCodexCliHandler:open_job_output(job)
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
        for _, key in ipairs({ "<Esc>" }) do
          vim.keymap.set({ "i", "t" }, key, function()
            self:close_job_output(job)
          end, {
            buffer = new_bufnr,
          })
        end
        for _, key in ipairs({ "<C-n>" }) do
          vim.keymap.set({ "i", "t" }, key, "<C-\\><C-N>", {
            buffer = new_bufnr,
          })
        end
        vim.keymap.set({ "i", "t" }, "<Tab>", "<Down>", { buffer = new_bufnr })
        vim.keymap.set({ "i", "t" }, "<S-Tab>", "<Up>", { buffer = new_bufnr })
      end)
    else
      new_bufnr = nil
    end
  end)
  return open
end

return SpurJobCodexCliHandler
