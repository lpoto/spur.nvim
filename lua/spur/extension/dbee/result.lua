---@class SpurDbeeResult
local SpurDbeeResult = {}
SpurDbeeResult.__index = SpurDbeeResult
SpurDbeeResult.__type = "SpurDbeeResult"

local result_ui = nil
local ocsc = nil

---@param on_exit function|nil
function SpurDbeeResult:new(on_exit)
  if type(on_exit) ~= "function" then
    on_exit = nil
  end
  local instance = setmetatable({
    __write_delay_ms = 25,
  }, self)

  local opts = vim.tbl_extend("force",
    require("dbee.config").default.result,
    {
      buffer_options = {
        bufhidden = "hide",
      },
      page_size = 5000
    })

  if result_ui == nil then
    local state = require("dbee.api.state")
    result_ui = require("dbee.ui.result"):new(state.handler(), opts)
    ocsc = result_ui.on_call_state_changed
  else
    local common = require("dbee.ui.common")
    result_ui.bufnr = common.create_blank_buffer("dbee-result", opts.buffer_options)
    common.configure_buffer_mappings(result_ui.bufnr, result_ui:get_actions(), opts.mappings)
  end

  result_ui.on_call_state_changed = function(rui, data)
    if self:is_cleaned() then
      return
    end
    local old_call = result_ui.current_call
    local old_state = type(old_call) == "table" and old_call.state or nil

    if ocsc ~= nil then
      ocsc(rui, data)
    end
    local call = result_ui.current_call
    if type(call) ~= "table" or call.id == nil then
      return
    end
    local new_state = call.state
    if new_state == "archived"
        or new_state == "executing_failed"
        or new_state == "retrieving_failed"
        or new_state == "canceled" then
      if new_state ~= old_state then
        self:on_exit(new_state, on_exit)
      end
    end
  end
  return instance
end

function SpurDbeeResult:on_exit(state, callback)
  self.__exited = true
  if type(callback) == "function" then
    pcall(callback, state)
  end
end

function SpurDbeeResult:is_exited()
  return self.__exited == true
end

function SpurDbeeResult:is_cleaned()
  return self.__cleaned == true
end

function SpurDbeeResult:set_call(call)
  if result_ui ~= nil then
    if type(call) == "table" then
      local cur_call = result_ui.current_call
      if type(cur_call) == "table" and cur_call.id ~= call.id then
        self.__exited = false
        self.__cleaned = false
      end
    end
    if self:is_exited() then
      error("Cannot set call on exited writer")
    end
    result_ui:set_call(call)
  end
end

---@return number|nil
function SpurDbeeResult:get_bufnr()
  if result_ui == nil then
    return nil
  end
  if self.__cleaned then
    return nil
  end
  if type(result_ui.bufnr) == "number" then
    return result_ui.bufnr
  end
  return nil
end

---@return table|nil
function SpurDbeeResult:get_call()
  if type(result_ui) ~= "table" then
    return nil
  end
  return result_ui.current_call
end

function SpurDbeeResult:clean()
  self.__cleaned = true
  pcall(function()
    if result_ui ~= nil then
      local bufnr = result_ui.bufnr
      if type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) then
        pcall(function()
          vim.bo[bufnr].bufhidden = "wipe"
        end)
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end)
end

function SpurDbeeResult:get_ui()
  if self.__cleaned or type(result_ui) ~= "table" then
    return nil
  end
  return result_ui
end

return SpurDbeeResult
