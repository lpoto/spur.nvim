local SpurJob = require("spur.core.job")

---@class SpurLazySqlJob : SpurJob
local SpurLazySqlJob = setmetatable({}, { __index = SpurJob })
SpurLazySqlJob.__index = SpurLazySqlJob
SpurLazySqlJob.__type = "SpurJob"
SpurLazySqlJob.__subtype = "SpurLazySqlJob"
SpurLazySqlJob.__metatable = SpurLazySqlJob

function SpurLazySqlJob:new(opts)
  local spur_job = SpurJob:new(opts)
  local instance = setmetatable(spur_job, SpurLazySqlJob)
  return instance
end

function SpurLazySqlJob:can_restart()
  return false
end

function SpurLazySqlJob:can_clean()
  return false
end

function SpurLazySqlJob:can_kill()
  return false
end

return SpurLazySqlJob
