local SpurJobHandler = require("spur.core.handler")

---@class SpurJobDbeeHandler : SpurJobHandler
local SpurJobDbeeHandler = setmetatable({}, { __index = SpurJobHandler })
SpurJobDbeeHandler.__index = SpurJobDbeeHandler
SpurJobDbeeHandler.__type = "SpurHandler"
SpurJobDbeeHandler.__subtype = "SpurJobDbeeHandler"
SpurJobDbeeHandler.__metatable = SpurJobDbeeHandler

function SpurJobDbeeHandler:new()
  local handler = SpurJobHandler:new()
  local instance = setmetatable(handler, SpurJobDbeeHandler)
  return instance
end

--- Check whether this handler accepts the job
---
--- @param opts table Input fields for SpurJob
--- @param action string What action the job should be accepted for
--- @return boolean
function SpurJobDbeeHandler:accepts_job(opts, action)
  if type(opts) ~= "table" then
    return false
  end
  -- NOTE: This handler overrides all actions
  -- of the default handler, so we accept all actions.
  if type(action) ~= "string" or action == "" then
    return false
  end
  return opts.type == "dbee"
end

---@return SpurJob
function SpurJobDbeeHandler:create_job()
  return require "spur.extension.dbee.job":new()
end

local get_spur_source_path
local add_spur_source
local trim_name

---@param job SpurDbeeJob
---@return table[]
function SpurJobDbeeHandler:__get_job_actions(job)
  local actions = {}

  local ok, _ = pcall(function()
    local spur_source_path = get_spur_source_path()
    local spur_source_path_found = false

    local api = require "dbee.api"
    local sources = api.core.get_sources()
    local actual_sources = {}
    for _, source in ipairs(sources) do
      if type(source) == "table" then
        pcall(function()
          if source:file() == spur_source_path then
            spur_source_path_found = true
          end
        end)
        table.insert(actual_sources, source)
      end
    end
    if not spur_source_path_found then
      local new_source = add_spur_source()
      if type(new_source) == "table" then
        table.insert(actual_sources, new_source)
      end
    end
    local max_len = 0
    for _, source in ipairs(actual_sources) do
      if type(source) == "table" then
        for _, conn in ipairs(source:load()) do
          local conn_name = trim_name(conn.name)
          local name = conn_name
          if type(name) == "string" and #name > max_len then
            max_len = #name
          end
        end
      end
    end
    for _, source in ipairs(actual_sources) do
      if type(source) == "table" then
        for _, conn in ipairs(source:load()) do
          local name, order = trim_name(conn.name)
          if type(name) == "string" and type(conn.type) == "string" and conn.type ~= "" then
            if #name < max_len then
              name = name .. string.rep(" ", max_len - #name)
            end
            name = name .. "  [" .. conn.type .. "]"
          end
          local id = conn.id
          if type(name) == "string" and name ~= "" and id then
            table.insert(actions, { label = name, value = conn, order = order })
          end
        end
      end
    end
    pcall(function()
      table.sort(actions, function(a, b)
        if a.order ~= b.order then
          return a.order < b.order
        end
        return a.label < b.label
      end)
    end)
  end)

  local existing = SpurJobHandler.__get_job_actions(self, job)
  if type(existing) == "table" then
    for _, action in ipairs(existing) do
      table.insert(actions, action)
    end
  end
  if ok then
    local back_action = nil
    for i, action in ipairs(actions) do
      if type(action) == "table"
          and type(action.value) == "string"
          and action.value == "_back" then
        back_action = action
        table.remove(actions, i)
      end
    end
    table.insert(actions, { label = "[Add Connection]", value = "_add" })
    if type(back_action) == "table" then
      table.insert(actions, back_action)
    end
  end
  return actions
end

local close_query_and_output

function SpurJobDbeeHandler:__select_connection(job)
  local actions = self:__get_job_actions(job)
  vim.ui.select(actions, {
    prompt = "Select Connection",
    format_item = function(item) return item.label end,
  }, function(choice)
    if type(choice) ~= "table" or not choice.value or choice.value == "" then return end
    if choice.value == "_add" then
      return self:__add_connection(job)
    end
    if SpurJobHandler.__execute_job_action(self, job, choice) then
      return
    end
    if type(choice.value) == "table" and choice.value.id then
      local api = require "dbee.api"
      local cur_conn = api.core.get_current_connection()
      api.core.set_current_connection(choice.value.id)
      if cur_conn == nil or cur_conn.id ~= choice.value.id then
        close_query_and_output()
      end
      self:__select_action(job, choice.value)
    end
  end)
end

---@param job SpurDbeeJob
---@param action table|string
function SpurJobDbeeHandler:__execute_job_action(job, action)
  if type(action) ~= "table" or not action.label or not action.value then
    return
  end
  if action.value == "_add" then
    return self:__add_connection(job)
  end
  if type(action.value) == "table" and action.value.id then
    local api = require "dbee.api"
    local cur_conn = api.core.get_current_connection()
    api.core.set_current_connection(action.value.id)
    if cur_conn == nil or cur_conn.id ~= action.value.id then
      close_query_and_output()
    end
    self:__select_action(job, action.value)
    return
  end
  return SpurJobHandler.__execute_job_action(self, job, action)
end

local format_title

function SpurJobDbeeHandler:__select_action(job, conn, schema, actual_database)
  if type(conn) ~= "table" or not conn.id then
    return
  end
  local conn_name = trim_name(conn.name)
  if not conn_name then
    return
  end
  if type(schema) ~= "string" or schema == "" then
    if conn.id ~= nil then
      pcall(function()
        local api = require "dbee.api"
        local cur_db, _ = api.core.connection_list_databases(conn.id)
        if type(cur_db) == "string" and cur_db ~= "" then
          schema = cur_db
        end
      end)
    end
    if (type(schema) ~= "string" or schema == "") and type(conn) == "table" then
      if type(conn.url) == "string" then
        local url = conn.url
        local matched = url:match("/([%w_%-]+)$")
        if type(matched) == "string" and matched ~= "" then
          schema = matched
        end
      end
    end
  end
  if type(schema) ~= "string" or schema == "" then
    error("no schema/database found")
  end
  local structure = {}
  for _, db in ipairs(self:__get_structure(conn)) do
    if type(db) == "table" and type(db.children) == "table" and #db.children > 0 then
      if type(actual_database) == "string" and actual_database ~= "" then
        if (schema == db.name and schema ~= nil and schema ~= "") then
          for _, child in ipairs(db.children) do
            if type(child) == "table" then
              table.insert(structure, child)
            end
          end
        end
      elseif (schema == db.name or schema ~= "" and db.name == "public") then
        for _, child in ipairs(db.children) do
          if type(child) == "table" then
            table.insert(structure, child)
          end
        end
      elseif type(conn) == "table" and conn.type == "postgres" then
        db.other_schema = true
        table.insert(structure, db)
      end
    end
  end
  local options = {}
  if type(structure) == "table" then
    for _, tbl in ipairs(structure) do
      local name = tbl.name
      table.insert(options, { name = name, value = tbl })
    end
  end
  pcall(function()
    table.sort(options, function(a, b)
      if type(a.value) == "table" and a.value.other_schema == true
          and (type(b.value) ~= "table" or b.value.other_schema ~= true) then
        return false
      end
      if type(b.value) == "table" and b.value.other_schema == true
          and (type(a.value) ~= "table" or a.value.other_schema ~= true) then
        return true
      end
      if a.name == "postgres" or a.name == "mysql" then
        return false
      end
      if b.name == "postgres" or b.name == "mysql" then
        return true
      end
      return a.name < b.name
    end)
  end)
  if type(actual_database) ~= "string" or actual_database == "" then
    table.insert(options, 1, { name = "[Query]", value = "_query" })
  end


  table.insert(options, { name = "[Back]", value = "_back" })

  local schema_name = schema
  if type(actual_database) == "string" and actual_database ~= "" then
    schema_name = actual_database .. "." .. schema_name
  end
  vim.ui.select(options, {
    prompt = format_title(conn, schema_name),
    format_item = function(item) return item.name end,
  }, function(choice)
    if type(choice) ~= "table" or not choice.value or choice.value == "" then return end
    if choice.value == "_query" then
      return self:__query(job, conn, function()
        vim.schedule(function()
          self:__select_action(job, conn, schema, actual_database)
        end)
      end)
    elseif choice.value == "_back" then
      if type(actual_database) == "string" and actual_database ~= "" then
        return self:__select_action(job, conn, actual_database)
      else
        return self:__select_connection(job)
      end
    end
    if choice.value.other_schema == true then
      return self:__select_action(job, conn, choice.name, schema)
    end
    return self:__select_table(job, conn, schema, choice.value, actual_database)
  end)
end

function SpurJobDbeeHandler:__select_table(job, conn, schema, tbl, actual_database)
  if type(tbl) ~= "table" or type(tbl.name) ~= "string" or tbl.name == "" then
    return
  end
  local api = require "dbee.api"
  ---@diagnostic disable-next-line
  local helpers = api.core.connection_get_helpers(conn.id, {
    table = tbl.name,
    schema = tbl.schema
  })

  local options = {}
  if type(helpers) == "table" then
    for k, v in pairs(helpers) do
      if type(k) == "string" and v and v ~= "" then
        table.insert(options, { name = k, value = v })
      end
    end
    pcall(function()
      table.sort(options, function(a, b)
        for _, w in ipairs({ "column", "list" }) do
          if a.name:lower() == w then
            return true
          end
          if b.name:lower() == w then
            return false
          end
        end
        return a.name < b.name
      end)
    end)
  end
  table.insert(options, { name = "[Back]", value = "_back" })

  local table_name = tbl.name
  if type(schema) == "string" and schema ~= "" then
    table_name = schema .. "." .. table_name
  end
  if type(actual_database) == "string" and actual_database ~= "" then
    table_name = actual_database .. "." .. table_name
  end
  vim.ui.select(options, {
    prompt = format_title(conn, table_name),
    format_item = function(item) return item.name end,
  }, function(choice)
    if type(choice) ~= "table" or not choice.value or choice.value == "" then return end
    if choice.value == "_back" then
      return self:__select_action(job, conn, schema, actual_database)
    end
    return self:__execute_query(job, conn, choice.value, function()
      vim.schedule(function()
        self:__select_table(job, conn, schema, tbl, actual_database)
      end)
    end)
  end)
end

---@return table
function SpurJobDbeeHandler:__get_structure(conn)
  local actual = {}
  pcall(function()
    local api = require "dbee.api"
    local structure = api.core.connection_get_structure(conn.id)
    for _, db in ipairs(structure or {}) do
      if
          type(db) == "table"
          and (not db.type or db.type == "")
          and type(db.schema) == "string"
          and type(db.name) == "string"
          and db.name ~= ""
          and not vim.tbl_contains({
            "sys",
            "performance_schema",
            "information_schema",
            "mysql",
            "innodb",
            "pg_catalog",
          }, db.schema)
          and type(db.children) == "table" and #db.children > 0 then
        table.insert(actual, db)
      end
    end
  end)
  return actual
end

local counter = 0
function SpurJobDbeeHandler:__add_connection(job)
  vim.ui.input({
    prompt = "Connection Type: ",
    default = "",
  }, function(t)
    if type(t) ~= "string" or t == "" then
      return
    end
    vim.ui.input({
      prompt = "Connection Name: ",
      default = "",
    }, function(name)
      if type(name) ~= "string" or name == "" then
        return
      end
      vim.ui.input({
        prompt = "Connection URL: ",
        default = "",
      }, function(url)
        if type(url) ~= "string" or url == "" then
          return
        end
        vim.schedule(function()
          local source = add_spur_source()
          if type(source) ~= "table" then
            error("could not add dbee spur source")
          end
          local api = require "dbee.api"

          source.create = function(s, conn)
            if not conn or vim.tbl_isempty(conn) then
              error("cannot create an empty connection")
            end
            local path = s:file()
            local existing = s:load()
            conn.id = "spur_" .. counter .. "_" .. tostring(os.time())
            counter = counter + 1
            table.insert(existing, conn)
            local ok, json = pcall(vim.fn.json_encode, existing)
            if not ok then
              error("could not convert connection list to json")
            end
            local file = assert(io.open(path, "w+"), "could not open file")
            file:write(json)
            file:close()
            return conn.id
          end
          ---@diagnostic disable-next-line
          api.core.source_add_connection(source:name(), {
            type = t,
            name = name,
            url = url,
          })
          self:__select_connection(job)
        end)
      end)
    end)
  end)
end

local register_action_mappings
local last_actions_callback = nil
local last_conn = nil
local last_output_title = nil

---@param job SpurDbeeJob
function SpurJobDbeeHandler:open_job_output(job, conn, actions_callback)
  pcall(function()
    if not conn then
      conn = require("dbee.api").core.get_current_connection()
    end
  end)
  local result = job:__get_result()
  if type(result) ~= "table" or type(result.get_ui) ~= "function" then
    return false
  end
  local result_ui = result:get_ui()
  if type(result_ui) ~= "table" then
    return false
  end
  if type(actions_callback) ~= "function"
      and type(conn) == "table"
      and type(last_conn) == "table"
      and conn.id ~= nil
      and conn.id == last_conn.id
  then
    actions_callback = last_actions_callback
  else
    last_actions_callback = actions_callback
  end
  last_conn = conn

  last_output_title = format_title(conn, "Output", true)

  local winid = nil
  local winids = vim.api.nvim_list_wins()
  for _, w in ipairs(winids) do
    local buf = vim.api.nvim_win_get_buf(w)
    local filetype = vim.bo[buf].filetype
    if filetype == "dbee-result" then
      winid = w
      break
    end
  end
  if winid == nil then
    winid = self:__open_float(job, result_ui.bufnr)
  end
  result_ui:show(winid)
  pcall(function()
    if conn then
      local buf = result_ui.bufnr
      for _, k in ipairs({ "<C-b>" }) do
        vim.keymap.set({ "v", "n", "i" }, k, function()
          vim.schedule(function()
            self:__select_action(job, conn)
          end)
        end, { buffer = buf, desc = "Open database selection" })
      end
    end
  end)
  local buf = vim.api.nvim_get_current_buf()
  pcall(function()
    local filetype = vim.bo[buf].filetype
    -- check if filetype startswith dbee
    if filetype:match("^dbee") == nil then
      return
    end
    for _, k in ipairs({ "<C-O>", "<S-Tab>", "<C-I>", "<Tab>" }) do
      vim.keymap.set({ "n" }, k, function()
        self:__query(job, conn, actions_callback)
      end, { buffer = buf, desc = "Return to query editor" })
    end
  end)
  register_action_mappings(job, buf, actions_callback)
  return true
end

function SpurJobDbeeHandler:__get_output_name(...)
  if type(last_output_title) == "string" and last_output_title ~= "" then
    return last_output_title
  end
  return SpurJobHandler.__get_output_name(self, ...)
end

---@return string
function get_spur_source_path()
  local file = require "spur.util.file"
  ---@type string
  ---@diagnostic disable-next-line
  local r = file.concat_path(vim.fn.stdpath("data"), "spur", "persistence.json")
  if vim.fn.filereadable(r) == 0 then
    local parent = file.get_parent_dir(r)
    if parent ~= nil and vim.fn.isdirectory(parent) == 0 then
      vim.fn.mkdir(parent, "p")
    end
  end
  return r
end

local source_added = nil
function add_spur_source()
  if source_added ~= nil then
    return source_added
  end
  local ok, r = pcall(function()
    local api = require "dbee.api"
    local path = get_spur_source_path()
    local sources = require("dbee.sources")
    local new_source = sources.FileSource:new(path)
    new_source.name = function(_)
      return "_spur_source"
    end
    api.core.add_source(new_source)
    source_added = new_source
    return new_source
  end)
  if ok then
    return r
  end
  return source_added
end

---@param job SpurDbeeJob
function SpurJobDbeeHandler:__execute_query(job, conn, query, actions_callback)
  if job:execute_query(conn, query) then
    vim.schedule(function()
      self:open_job_output(job, conn, actions_callback)
    end)
  end
end

local last_cursor = nil

local visual_selection
function SpurJobDbeeHandler:__query(job, conn, actions_callback)
  local filename = "default"
  if type(conn) == "table" and (type(conn.id) == "string" or type(conn.id) == "number") then
    if type(conn.id) ~= "string" or conn.id ~= "" then
      filename = tostring(conn.id):gsub("[/\\]", "_")
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local fileutils = require "spur.util.file"
  local path = fileutils.concat_path(vim.fn.stdpath("data"), "spur", "editor", filename .. ".sql")
  if path == nil then
    return
  end
  pcall(function()
    if vim.fn.filereadable(path) == 0 then
      local parent = fileutils.get_parent_dir(path)
      if parent ~= nil and vim.fn.isdirectory(parent) == 0 then
        vim.fn.mkdir(parent, "p")
      end
      local file = assert(io.open(path, "w+"), "could not open file for writing")
      local name = trim_name(conn.name)
      if type(name) == "string" or name ~= "" and type(conn.type) == "string" and conn.type ~= "" then
        name = name .. " [" .. conn.type .. "]"
      end
      file:write("-- Query Editor for Connection: " .. name .. "\n\n\n")
      file:close()
    end
  end)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  close_query_and_output()

  vim.bo[buf].filetype = "sql"
  vim.bo[buf].buftype = ""
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false

  pcall(function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("edit " .. path)
    end)
  end)

  local new_cursor = nil
  pcall(function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if type(lines) == "table" and #lines > 0 then
      local row = #lines
      local col = #lines[row]
      if col > 200 then
        col = 200
      end
      new_cursor = { row, col }
    end
  end)

  local write_file_contents = function()
    pcall(function()
      vim.api.nvim_buf_call(buf, function()
        pcall(function()
          vim.cmd("silent! noautocmd write")
        end)
        vim.bo[buf].modified = false
      end)
    end)
  end

  -- on insert leave write the file
  local group = vim.api.nvim_create_augroup("SpurDbeeQuery", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = buf,
    once = false,
    callback = function()
      last_cursor = vim.api.nvim_win_get_cursor(0)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufUnload" }, {
    group = group,
    buffer = buf,
    once = false,
    callback = function()
      write_file_contents()
    end,
  })
  vim.bo[buf].modified = false

  local id
  local winid
  local close = function(force)
    local new_buf = vim.api.nvim_get_current_buf()
    local buftype = vim.bo[new_buf].buftype
    if not force then
      if buftype == "prompt" then
        return false
      end
    end
    pcall(function()
      if winid and winid ~= -1 and vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_close(winid, true)
      end
    end)
    pcall(function()
      vim.api.nvim_del_autocmd(id)
    end)
    pcall(function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
    return true
  end
  local win_opts = self.__get_win_opts(format_title(conn, "Query Editor", true))
  win_opts.style = nil
  winid = vim.api.nvim_open_win(buf, true, win_opts)

  local cursor_set = false
  pcall(function()
    if type(last_cursor) == "table" and #last_cursor == 2 then
      vim.api.nvim_win_set_cursor(winid, last_cursor)
      cursor_set = true
    end
  end)
  pcall(function()
    if not cursor_set and type(new_cursor) == "table" and #new_cursor == 2 then
      vim.api.nvim_win_set_cursor(winid, new_cursor)
    end
  end)
  id = vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    group = group,
    once = false,
    callback = function()
      vim.schedule(close)
    end,
  })
  for _, key in ipairs({ "q" }) do
    vim.keymap.set("n", key, function()
      vim.schedule(function() close(true) end)
    end, { buffer = buf, desc = "Close query window" })
  end
  for _, key in ipairs({ "Q", "<C-q>", "<S-Esc>", "<C-Esc>" }) do
    vim.keymap.set("n", key, function()
      vim.schedule(function()
        close(true)
        job:clean()
      end)
    end, { buffer = buf, desc = "Close query window" })
  end
  register_action_mappings(job, buf, actions_callback)

  for _, key in ipairs({ "bb", "BB", "bB", "Bb" }) do
    vim.keymap.set("v", key, function()
      local srow, scol, erow, ecol = visual_selection()
      local selection = vim.api.nvim_buf_get_text(0, srow, scol, erow, ecol, {})
      if type(selection) ~= "table" or #selection == 0 then
        return
      end
      local query = table.concat(selection, "\n")
      if query:gsub("%s+", "") == "" then
        return
      end
      self:__execute_query(job, conn, query, actions_callback)
    end, { buffer = buf, desc = "Execute query" })
  end
  for _, k in ipairs({ "<C-O>", "<S-Tab>", "<C-I>", "<Tab>" }) do
    vim.keymap.set({ "n" }, k, function()
      self:open_job_output(job, conn, actions_callback)
    end, { buffer = buf, desc = "Return to result window" })
  end
  pcall(function()
    local cn = require("dbee.api").core.get_current_connection()
    if cn then
      for _, k in ipairs({ "<C-b>" }) do
        vim.keymap.set({ "v", "n", "i" }, k, function()
          vim.schedule(function()
            self:__select_action(job, cn)
          end)
        end, { buffer = buf, desc = "Open database selection" })
      end
    end
  end)
end

function register_action_mappings(job, buf, actions_callback)
  local action_mappings = require "spur.config".get_mappings(
    "actions",
    {
      { key = "<C-a>",     mode = { "n", "i" } },
      { key = "<C-s>",     mode = { "n", "i" } },
      { key = "<C-q>",     mode = { "n", "i" } },
      { key = "<leader>s", mode = { "n" } },
      { key = "<leader>d", mode = { "n" } },
      { key = "<leader>q", mode = { "n" } },
      { key = "<leader>a", mode = { "n" } },
    }
  )
  for _, mapping in ipairs(action_mappings) do
    pcall(function()
      vim.keymap.set(mapping.mode, mapping.key, function()
        if type(actions_callback) == "function" then
          pcall(function()
            actions_callback()
          end)
          return
        end
        local manager = require "spur.manager"
        manager.select_job_action(job)
      end, { buffer = buf, desc = "Select job action" })
    end)
  end
end

function close_query_and_output()
  local winids = vim.api.nvim_list_wins()
  for _, win in ipairs(winids) do
    pcall(function()
      local cfg = vim.api.nvim_win_get_config(win)
      local buf = vim.api.nvim_win_get_buf(win)
      local buftype = vim.bo[buf].buftype
      local filetype = vim.bo[buf].filetype
      local name = vim.api.nvim_buf_get_name(buf)
      if type(cfg) == "table"
          and type(cfg.relative) == "string"
          and (name == ""
            and buftype == ""
            and filetype == "sql"
            or filetype:match("dbee")
          ) then
        vim.api.nvim_win_close(win, true)
      end
    end)
  end
end

function visual_selection()
  -- return to normal mode ('< and '> become available only after you exit visual mode)
  local key = vim.api.nvim_replace_termcodes("<esc>", true, false, true)
  vim.api.nvim_feedkeys(key, "x", false)

  local _, srow, scol, _ = unpack(vim.fn.getpos("'<"))
  local _, erow, ecol, _ = unpack(vim.fn.getpos("'>"))
  if ecol > 200000 then
    ecol = 20000
  end
  if srow < erow or (srow == erow and scol <= ecol) then
    return srow - 1, scol - 1, erow - 1, ecol
  else
    return erow - 1, ecol - 1, srow - 1, scol
  end
end

function format_title(conn, suffix, append_database)
  local conn_name = trim_name(conn.name)
  local title = "[" .. conn_name .. "]"
  if type(conn.type) == "string" and conn.type ~= "" then
    title = title .. "[" .. conn.type .. "]"
  end
  title = title .. " " .. suffix
  if append_database == true then
    local cur_database = require "dbee.api".core.connection_list_databases(conn.id)
    if type(cur_database) == "string" and cur_database ~= "" then
      title = title .. " (" .. cur_database .. ")"
    elseif type(conn.url) == "string" then
      local url = conn.url
      local matched = url:match("/([%w_%-]+)$")
      if type(matched) == "string" and matched ~= "" then
        title = title .. " (" .. matched .. ")"
      end
    end
  end
  return title
end

function trim_name(name)
  local order = 100
  if type(name) == "string" then
    pcall(function()
      local order_e = name:match("order=%d+")
      if type(order_e) == "string" then
        order = tonumber(order_e:match("%d+")) or 0
      end
    end)
    pcall(function()
      name = name:gsub("%s*order=%d+", "")
    end)
    pcall(function()
      name = name:match("^%s*(.-)%s*$")
    end)
  end
  if type(name) ~= "string" or name == "" then
    return nil, order
  end
  return name, order
end

return SpurJobDbeeHandler
