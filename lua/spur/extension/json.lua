local M = {}

local get_default_files
local read_json
local files_read = {}

---@class SpurReaderConfig
---@field files string[]|nil Paths to job files
---@field enabled boolean|nil Whether the json extension is enabled
---@field async boolean|nil Whether to read files async

--- Read jobs from json files in the configured locations.
---
---@param config SpurReaderConfig|nil
function M.init(config)
  if config ~= nil and type(config) ~= "table" then
    error("[Spur.json] init expects a table as config")
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

    for _, job_file in ipairs(config.files) do
      if type(job_file) == "string" and not files_read[job_file] then
        files_read[job_file] = true
        read_json(job_file, async, function(file_content)
          if type(file_content) ~= "string" or file_content == "" then
            return
          end
          local ok, jobs = pcall(vim.json.decode, file_content)
          if ok and type(jobs) == "table" then
            for _, job in ipairs(jobs) do
              if job ~= nil then
                require("spur.core.manager").add_job(job)
              end
            end
          else
            error("[Spur.json] Failed to decode jobs from: " .. job_file)
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

---@param file string
---@param async boolean
---@param callback function
function read_json(file, async, callback)
  local file_util = require("spur.util.file")
  if async then
    return file_util.read_file_async(file, callback)
  end
  return callback(file_util.read_file_secure(file))
end

---@return string[]
function get_default_files()
  local file_util = require("spur.util.file")
  local locations = {}

  table.insert(locations, vim.fn.expand("~"))
  table.insert(locations, file_util.concat_path(vim.fn.stdpath("data"), "spur"))
  table.insert(locations, vim.fn.getcwd())

  local files = {}
  for _, path in ipairs(locations) do
    if type(path) == "string" and path ~= "" then
      local file = file_util.concat_path(path, "spur.json")
      if file ~= nil and vim.fn.filereadable(file) == 1 then
        table.insert(files, file)
      end
      file = file_util.concat_path(path, ".spur.json")
      if file ~= nil and vim.fn.filereadable(file) == 1 then
        table.insert(files, file)
      end
    end
  end
  return files
end

return M
