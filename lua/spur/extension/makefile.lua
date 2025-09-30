local M = {}

local read_makefile
local parse_targets
local get_default_files
local files_read = {}

---@class SpurMakefileConfig
---@field files string[]|nil Paths to makefiles
---@field enabled boolean|nil Whether the makefile extension is enabled
---@field async boolean|nil Whether to read files async

--- Read jobs from makefiles in the configured locations.
---
---@param config SpurMakefileConfig|nil
function M.init(config)
  if config ~= nil and type(config) ~= "table" then
    error("[Spur.makefile] init expects a table as config")
  end
  config = config or {}
  local enabled = config.enabled == nil or config.enabled == true
  if not enabled then
    return
  end
  local async = config.async == true

  local parse_jobs = function()
    if type(config.files) ~= "table" then
      config.files = get_default_files()
    end

    for _, makefile in ipairs(config.files) do
      if type(makefile) == "string" and not files_read[makefile] then
        files_read[makefile] = true
        read_makefile(makefile, async, function(content)
          if type(content) ~= "string" or content == "" then
            return
          end
          local ok, jobs = pcall(parse_targets, makefile, content)
          if ok and type(jobs) == "table" then
            for _, job in ipairs(jobs) do
              if type(job) == "table" then
                job.type = "makefile"
              end
              require("spur.manager").add_job(require "spur.core.job":new(job))
            end
          else
            error("[Spur.makefile] Failed to decode jobs from: " .. makefile)
          end
        end)
      end
    end
  end
  if async then
    vim.schedule(parse_jobs)
  else
    parse_jobs()
  end
end

function get_default_files()
  local file_util = require("spur.util.file")
  local locations = {}
  local cwd = vim.fn.getcwd()
  table.insert(locations, file_util.concat_path(cwd, "Makefile"))
  return locations
end

---@param path string
---@param async boolean
---@param callback function
function read_makefile(path, async, callback)
  local file_util = require("spur.util.file")
  if async then
    return file_util.read_file_async(path, callback)
  end
  return callback(file_util.read_file_secure(path))
end

function parse_targets(file, content)
  local working_dir = vim.fn.fnamemodify(file, ":p:h")

  local jobs = {}
  for line in content:gmatch("[^\r\n]+") do
    local target = line:match("^([%w-_%.]+):")
    if type(target) == "string"
        and target ~= ""
        and target ~= "PHONY"
        and target ~= ".PHONY"
        and target ~= "default" then
      table.insert(jobs, {
        order = 90,
        job = {
          name = "make " .. target,
          cmd = "make " .. target,
          workdir = working_dir,
        }
      })
    end
  end
  return jobs
end

return M
