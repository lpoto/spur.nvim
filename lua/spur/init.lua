local M = {}

--- Setup the Spur module.
---
--- @param opts SpurConfig|nil
function M.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then
    error("Spur.setup expects a table as opts")
  end
  opts = opts or {}

  local config = require "spur.config".setup(opts)

  local manager = require "spur.manager"
  if not manager.is_initialized() then
    manager.init()
  end

  vim.api.nvim_exec_autocmds("User", { pattern = "SpurInit" })

  if type(opts.extensions) == "table" then
    for k, ext in pairs(opts.extensions) do
      local ext_name = type(k) == "string" and k or ext
      local o = type(ext) == "table" and ext or {}
      if type(ext_name) == "string" and ext_name ~= "" then
        local ok, mod = pcall(require, "spur.extension." .. ext_name)
        if ok and type(mod) == "table" and type(mod.init) == "function" then
          local enabled = o.enabled == nil or o.enabled == true
          if enabled then
            mod.init(o)
          end
        else
          vim.notify(
            "Failed to load Spur extension: " .. ext,
            vim.log.levels.ERROR, {
              title = config.title,
            })
        end
      end
    end
  end
end

--- Get the current Spur configuration.
---
--- @return SpurConfig
function M.config()
  return require "spur.config"
end

--- Select a job from the list of available jobs.
--- On selection, the user will be prompted to
--- select an action for the job.
---
--- @param job_name string|nil
function M.select_job(job_name)
  require "spur.manager".select_job(job_name)
end

--- Select a job from the list of available jobs,
--- that already has an output, and open its output.
---
--- If there is only a single available output,
--- it will be opened directly.
function M.select_output()
  local manager = require "spur.manager"
  manager.select_job(
    nil,
    function(job)
      return job:get_bufnr() ~= nil
          and vim.api.nvim_buf_is_valid(job:get_bufnr())
    end,
    function(job)
      if job ~= nil then
        manager.__find_handler(job, "open_job_output"):open_job_output(job)
      end
    end,
    true
  )
end

--- Select a job from the list of available jobs,
--- that already has an output, and open its output.
---
--- If there is only a single available output,
--- it will be opened directly.
---
--- If output already opened, it will be closed instead
function M.toggle_output()
  local windows = vim.api.nvim_list_wins()
  for _, win in ipairs(windows) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if vim.bo[bufnr].filetype == M.config().filetype then
      vim.api.nvim_win_close(win, true)
      return false
    end
  end
  local manager = require "spur.manager"
  if manager.close_outputs() then
    return false
  end
  M.select_output()
  return true
end

return M
