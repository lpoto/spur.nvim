local SpurJob = require("spur.core.job")

---@class SpurLazyGitJob : SpurJob
local SpurLazyGitJob = setmetatable({}, { __index = SpurJob })
SpurLazyGitJob.__index = SpurLazyGitJob
SpurLazyGitJob.__type = "SpurJob"
SpurLazyGitJob.__subtype = "SpurLazyGitJob"
SpurLazyGitJob.__metatable = SpurLazyGitJob

function SpurLazyGitJob:new(opts)
  local spur_job = SpurJob:new(opts)
  local instance = setmetatable(spur_job, SpurLazyGitJob)
  return instance
end

function SpurLazyGitJob:can_restart()
  return false
end

function SpurLazyGitJob:can_clean()
  return false
end

function SpurLazyGitJob:can_kill()
  return false
end

return SpurLazyGitJob
