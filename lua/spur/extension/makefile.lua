local M = {}

local read_makefile
local parse_targets

function M.init()
  local makefile = vim.fn.getcwd() .. "/Makefile"
  if vim.fn.filereadable(makefile) == 1 then
    local content = read_makefile(makefile)
    if content then
      local jobs = parse_targets(content)
      for _, job in ipairs(jobs) do
        require("spur.core.manager").add_job(require "spur.core.job":new(job))
      end
    end
  end
end

function read_makefile(path)
  local content = vim.secure.read(path)
  if type(content) == "string" and content ~= "" then
    return content
  end
  return nil
end

function parse_targets(content)
  local jobs = {}
  for line in content:gmatch("[^\r\n]+") do
    local target = line:match("^([%w-_%.]+):")
    if target
        and target ~= "PHONY"
        and target ~= ".PHONY"
        and target ~= "default" then
      table.insert(jobs, {
        order = 90,
        name = "make " .. target,
        cmd = "make " .. target,
      })
    end
  end
  return jobs
end

return M
