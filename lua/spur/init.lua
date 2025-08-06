local M = {}

---@class SpurConfig
---@field extensions table<string,table>|nil

--- Setup the Spur module.
--- @param config SpurConfig|nil
function M.setup(config)
  if M.__setup_done then return end
  M.__setup_done = true

  if config ~= nil and type(config) ~= "table" then
    error("Spur.setup expects a table as config")
  end
  config = config or {}

  if type(config.extensions) == "table" then
    for k, ext in pairs(config.extensions) do
      local ext_name = type(k) == "string" and k or ext
      local opts = type(ext) == "table" and ext or {}
      if type(ext_name) == "string" and ext_name ~= "" then
        local ok, mod = pcall(require, "spur.extension." .. ext_name)
        if ok and type(mod) == "table" and type(mod.init) == "function" then
          mod.init(opts)
        else
          vim.notify(
            "Failed to load Spur extension: " .. ext,
            vim.log.levels.ERROR, {
              title = "Spur.nvim",
            })
        end
      end
    end
  end
end

--- Select a job from the list of available jobs.
--- On selection, the user will be prompted to
--- select an action for the job.
function M.select_job()
  require "spur.core.manager".select_job()
end

--- Select a job from the list of available jobs,
--- that already has an output, and open its output.
---
--- If there is only a single available output,
--- it will be opened directly.
function M.select_output()
  require "spur.core.manager".select_job(
    function(job)
      return job:get_bufnr() ~= nil
          and vim.api.nvim_buf_is_valid(job:get_bufnr())
    end,
    function(job)
      if job ~= nil then
        require "spur.core.ui".open_job_output(job)
      end
    end,
    true
  )
end

return M
