---@class SpurConfig
---@field extensions table<string,table>|string[]|nil
---@field hl table<string,string>|nil
---@field filetype string|nil
---@field prefix string|nil
---@field title string|nil

---@type SpurConfig|nil
local config = nil

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
  if type(c.extensions) ~= "table" then
    c.extensions = {}
  end
  if type(c.hl) ~= "table" then
    c.hl = {}
  end
  local hl = {}
  if type(c.hl.warn) ~= "string" then
    hl.warn = "Warning"
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
  c.hl = hl

  for h, link in pairs(c.hl) do
    if type(link) == "string" and link ~= "" then
      vim.api.nvim_set_hl(0, h, { link = link, italic = true })
    end
  end
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

setmetatable(M, M)
return M
