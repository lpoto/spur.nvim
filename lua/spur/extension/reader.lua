local M = {}

local get_default_files
local concat_path
local get_path_separator
local read_file

---@class SpurReaderConfig
---@field files string[]|nil Paths to job files

--- Read jobs from json files in the configured locations.
---
---@param config SpurReaderConfig|nil
function M.init(config)
  if config ~= nil and type(config) ~= "table" then
    error("Spur.reader.init expects a table as config")
  end
  config = config or {}

  if type(config.files) ~= "table" then
    config.files = get_default_files()
  end

  local processed = {}
  for _, job_file in ipairs(config.files) do
    if type(job_file) == "string"
        and not processed[job_file]
        and vim.fn.filereadable(job_file) == 1 then
      processed[job_file] = true
      local file_content = read_file(job_file)
      if file_content ~= nil then
        local ok, jobs = pcall(vim.json.decode, file_content)
        if ok and type(jobs) == "table" then
          for _, job in ipairs(jobs) do
            if job ~= nil then
              require("spur.core.manager").add_job(require "spur.core.job":new(job))
            end
          end
        else
          error("Failed to decode jobs from: " .. job_file)
        end
      end
    end
  end
end

---@param file string
---@return string|nil
function read_file(file)
  local content = vim.secure.read(file)
  if type(content) == "string" and content ~= "" then
    return content
  end
  return nil
end

---@return string[]
function get_default_files()
  local locations = {}
  local separator = get_path_separator()
  if type(separator) ~= "string" then
    return locations
  end
  table.insert(locations, vim.fn.expand("~"))
  table.insert(locations, concat_path(vim.fn.stdpath("data"), "spur"))
  table.insert(locations, vim.fn.getcwd())

  local files = {}
  for _, path in ipairs(locations) do
    if type(path) == "string" and path ~= "" then
      local file = concat_path(path, "spur.json")
      if file ~= nil and vim.fn.filereadable(file) == 1 then
        table.insert(files, file)
      end
      file = concat_path(path, ".spur.json")
      if file ~= nil and vim.fn.filereadable(file) == 1 then
        table.insert(files, file)
      end
    end
  end
  return files
end

---@param ... string
---@return string|nil
function concat_path(...)
  local sep = get_path_separator()
  local paths = { ... }
  local result = {}
  for _, path in ipairs(paths) do
    if type(path) == "string" and path ~= "" then
      table.insert(result, path)
    end
  end
  return table.concat(result, sep)
end

---@return string
function get_path_separator()
  return vim.fn.has("win32") == 1 and "\\" or "/"
end

return M
