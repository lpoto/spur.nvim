---@class SpurConfig
---@field extensions table<string,table>|string[]|nil
---@field hl table<string,string>|nil
---@field filetype string|nil
---@field prefix string|nil
---@field title string|nil
---@field mappings SpurMappingsConfig|nil
---@field custom_hl boolean|function|nil

---@class SpurMappingsConfig
---@field actions SpurMapping|string|nil

---@class SpurMapping
---@field key string
---@field mode string[]|string

---@type SpurConfig|nil
local config = nil

local resolve_mapping

---@param opts table|nil
---@return SpurConfig
local function setup_config(opts)
  if type(opts) ~= "table" then
    opts = {}
  end
  if type(config) ~= "table" then
    config = {}
  end
  local c = vim.tbl_deep_extend("force", config, opts)

  if type(c.title) ~= "string" or c.title == "" then
    c.title = "Spur.nvim"
  end
  if type(c.filetype) ~= "string" or c.filetype == "" then
    c.filetype = "spur.nvim"
  end
  if type(c.prefix) ~= "string" or c.prefix == "" then
    c.prefix = "• [SPUR]: "
  end
  if c.custom_hl ~= false and type(c.custom_hl) ~= "function" then
    c.custom_hl = true
  end
  if type(c.extensions) ~= "table" then
    c.extensions = {}
  end
  if type(c.hl) ~= "table" then
    c.hl = {}
  end
  local hl = {}
  if type(c.hl.warn) ~= "string" then
    hl.warn = "WarningMsg"
  else
    hl.warn = c.hl.warn
  end
  if type(c.hl.info) ~= "string" then
    hl.info = "Information"
  else
    hl.info = c.hl.info
  end
  if type(c.hl.debug) ~= "string" then
    hl.debug = "Comment"
  else
    hl.debug = c.hl.debug
  end
  if type(c.hl.prefix) ~= "string" then
    hl.prefix = "NonText"
  else
    hl.prefix = c.hl.prefix
  end
  if type(c.hl.success) ~= "string" then
    hl.success = "Label"
  else
    hl.success = c.hl.success
  end
  if type(c.hl.error) ~= "string" then
    hl.error = "ErrorMsg"
  else
    hl.error = c.hl.error
  end
  c.hl = hl

  for h, link in pairs(c.hl) do
    if type(link) == "string" and link ~= "" then
      vim.api.nvim_set_hl(0, h, { link = link, italic = true })
    end
  end


  ---@type SpurMappingsConfig
  local mappings = {}
  local available_keys = { "actions" }
  local mappings_input = c.mappings
  if type(mappings_input) ~= "table" then
    ---@diagnostic disable-next-line
    mappings_input = c.keys
  end
  if type(mappings_input) == "table" then
    for k, v in pairs(mappings_input) do
      local ok, contains = pcall(vim.tbl_contains, available_keys, k)
      if ok and contains then
        local m = resolve_mapping(v)
        if m ~= nil then
          mappings[k] = m
        end
      end
    end
  end
  c.mappings = mappings

  config = c
  return config
end

---@type SpurConfig
local M = {
  __index = function(_, key)
    local c = config
    if type(c) ~= "table" then
      c = setup_config()
    end
    return c[key]
  end,
  __newindex = function(_, key, value)
    error("Cannot modify Spur config: " .. key .. " = " .. tostring(value))
  end,
  __metatable = false,
}


---@param opts table|nil
---@diagnostic disable-next-line
function M.setup(opts)
  setup_config(opts)
  return M
end

---@param default SpurMapping|string|nil
---@param action_name string
---@return SpurMapping[]
---@diagnostic disable-next-line
function M.get_mappings(action_name, default)
  local mappings = {}
  if type(action_name) ~= "string" or action_name == "" then
    return mappings
  end
  local default_m = resolve_mapping(default)
  if default_m ~= nil then
    table.insert(mappings, default_m)
  end

  if type(config) ~= "table" or type(config.mappings) ~= "table" then
    return mappings
  end
  for k, v in pairs(config.mappings) do
    local m = resolve_mapping(v)
    if type(k) == "string"
        and k ~= ""
        and m ~= nil then
      table.insert(mappings, m)
    end
  end
  return mappings
end

---@param m SpurMapping|string|nil
function resolve_mapping(m)
  if m == nil then
    return nil
  end
  local mapping = { mode = { "n" }, key = "" }
  if type(m) == "string" then
    if m ~= "" then
      mapping.key = m
    end
  elseif type(m) == "table" then
    local key = m.key
    if type(key) ~= "string" then
      key = m[1]
    end
    if type(key) == "string" and key ~= "" then
      mapping.key = key
    end
    if type(m.mode) == "string" then
      mapping.mode = { m.mode }
    elseif type(m.mode) == "table" then
      local modes = {}
      ---@diagnostic disable-next-line
      for _, m in ipairs(m.mode) do
        if type(m) == "string" then
          table.insert(modes, m)
        end
      end
      if #modes > 0 then
        mapping.mode = modes
      end
    end
  end
  if type(mapping) == "table"
      and type(mapping.key) == "string"
      and mapping.key ~= ""
      and type(mapping.mode) == "table"
      and #mapping.mode > 0 then
    return mapping
  end
  return nil
end

setmetatable(M, M)
return M
