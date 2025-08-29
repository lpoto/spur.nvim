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
  if (opts.dbee == true) then
    return true
  end
  if type(opts.job) == "table" then
    return opts.job.cmd == "dbee"
  end
  return false
end

---@return SpurJob
function SpurJobDbeeHandler:create_job()
  return require "spur.extension.dbee.job":new()
end

local get_spur_source_path
local add_spur_source

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
        if source.path == spur_source_path then
          spur_source_path_found = true
        end
        table.insert(actual_sources, source)
      end
    end
    if not spur_source_path_found then
      local new_source = add_spur_source()
      if type(new_source) == "table" then
        table.insert(actual_sources, new_source)
      end
    end
    for _, source in ipairs(actual_sources) do
      if type(source) == "table" then
        for _, conn in ipairs(source:load()) do
          local name = conn.name
          local id = conn.id
          if type(name) == "string" and name ~= "" and id then
            table.insert(actions, { label = name, value = conn })
          end
        end
      end
    end
    pcall(function()
      local cur_conn = api.core.get_current_connection()
      table.sort(actions, function(a, b)
        if cur_conn then
          if a.value.id == cur_conn.id then
            return true
          elseif b.value.id == cur_conn.id then
            return false
          end
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
    table.insert(actions, { label = "[Add Connection]", value = "_add" })
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
    if type(choice.value) == "table" and choice.value.id then
      local api = require "dbee.api"
      local cur_conn = api.core.get_current_connection()
      api.core.set_current_connection(choice.value.id)
      if cur_conn == nil or cur_conn.id ~= choice.value.id then
        close_query_and_output()
      end
      self:__select_database(job, choice.value)
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
    self:__select_database(job, action.value)
    return
  end
  return SpurJobHandler.__execute_job_action(self, job, action)
end

function SpurJobDbeeHandler:__select_database(job, conn)
  if type(conn) ~= "table" or not conn.id or type(conn.name) ~= "string" or conn.name == "" then
    return
  end
  local api = require "dbee.api"
  local cur_db, databases = api.core.connection_list_databases(conn.id)
  local options = {}
  local cur_added = type(cur_db) ~= "string" or cur_db == ""
  if type(databases) == "table" then
    for _, db in ipairs(databases) do
      table.insert(options, { name = db, value = db })
      if not cur_added and db == cur_db then
        cur_added = true
      end
    end
  end
  if not cur_added and type(cur_db) == "string" and cur_db ~= "" then
    table.insert(options, 1, { name = cur_db, value = cur_db })
  end
  local size = #options
  if size == 0 then
    return self:__select_action(job, conn, cur_db, false, false)
  end

  table.insert(options, { name = "[Query]", value = "_query" })
  table.insert(options, { name = "[Back]", value = "_back" })

  vim.ui.select(options, {
    prompt = "[" .. conn.name .. "]",
    format_item = function(item) return item.name end,
  }, function(choice)
    if type(choice) ~= "table" or not choice.value or choice.value == "" then return end
    if choice.value == "_back" then
      return self:__select_connection(job)
    end
    if choice.value == "_query" then
      return self:__query(job, conn)
    end
    if type(choice.value) ~= "string" then
      return
    end
    api.core.connection_select_database(conn.id, choice.value)
    return self:__select_action(job, conn, choice.value, #options > 1, true)
  end)
end

function SpurJobDbeeHandler:__select_action(job, conn, database, multiple_dbs, allow_query_in_tbl_sel)
  if type(conn) ~= "table" or not conn.id or type(conn.name) ~= "string" or conn.name == "" then
    return
  end
  local is_db_selection = type(database) ~= "string" or database == ""

  local structure = {}
  for _, db in ipairs(self:__get_structure(conn)) do
    if type(db) == "table" and type(db.children) == "table" and #db.children > 0 then
      if (type(database) ~= "string" or database == "") then
        table.insert(structure, db)
      elseif type(database) == "string"
          and (database == db.name or database ~= "" and db.name == "public") then
        for _, child in ipairs(db.children) do
          if type(child) == "table" then
            table.insert(structure, child)
          end
        end
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
      if a.name == "postgres" or a.name == "mysql" then
        return false
      end
      if b.name == "postgres" or b.name == "mysql" then
        return true
      end
      return a.name < b.name
    end)
  end)

  if allow_query_in_tbl_sel == true or is_db_selection then
    table.insert(options, { name = "[Query]", value = "_query" })
  end

  if multiple_dbs == true then
    table.insert(options, { name = "[Change Database]", value = "_change_db" })
  end
  table.insert(options, { name = "[Back]", value = "_back" })

  local name = database
  if is_db_selection then
    name = "[" .. conn.name .. "]"
  else
    name = "[" .. conn.name .. "] " .. name
  end

  vim.ui.select(options, {
    prompt = name,
    format_item = function(item) return item.name end,
  }, function(choice)
    if type(choice) ~= "table" or not choice.value or choice.value == "" then return end
    if choice.value == "_change_db" then
      return self:__select_database(job, conn)
    elseif choice.value == "_query" then
      return self:__query(job, conn)
    elseif choice.value == "_back" then
      if is_db_selection then
        return self:__select_connection(job)
      else
        return self:__select_database(job, conn)
      end
    end
    if is_db_selection then
      return self:__select_action(job, conn, choice.name, multiple_dbs)
    end
    return self:__select_table(job, conn, database, choice.value)
  end)
end

function SpurJobDbeeHandler:__select_table(job, conn, database, tbl)
  if type(tbl) ~= "table" or type(tbl.name) ~= "string" or tbl.name == "" then
    return
  end
  local api = require "dbee.api"
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
  if type(database) == "string" and database ~= "" then
    table_name = database .. "." .. table_name
  end
  vim.ui.select(options, {
    prompt = "[" .. conn.name .. "] " .. table_name,
    format_item = function(item) return item.name end,
  }, function(choice)
    if type(choice) ~= "table" or not choice.value or choice.value == "" then return end
    if choice.value == "_back" then
      return self:__select_action(job, conn, database, true)
    end
    return self:__execute_query(job, conn, choice.value)
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
          local api = require "dbee.api"

          source.create = function(s, conn)
            local path = s.path
            if not conn or vim.tbl_isempty(conn) then
              error("cannot create an empty connection")
            end
            local existing = s:load()
            conn.id = "file_source_" .. s.path .. tostring(os.time())
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

---@param job SpurDbeeJob
function SpurJobDbeeHandler:open_job_output(job, conn)
  local result = job:__get_result()
  if type(result) ~= "table" or type(result.get_ui) ~= "function" then
    return false
  end
  local result_ui = result:get_ui()
  if type(result_ui) ~= "table" then
    return false
  end
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
    if not conn then
      conn = require("dbee.api").core.get_current_connection()
    end
    if conn then
      local buf = result_ui.bufnr
      for _, k in ipairs({ "<C-b>" }) do
        vim.keymap.set({ "v", "n", "i" }, k, function()
          vim.schedule(function()
            self:__select_database(job, conn)
          end)
        end, { buffer = buf, desc = "Open database selection" })
      end
    end
  end)
  return true
end

function get_spur_source_path()
  local file = require "spur.util.file"
  return file.concat_path(vim.fn.stdpath("data"), "dbee", "spur.persistence.json")
end

local source_added = nil
function add_spur_source()
  if source_added ~= nil then
    return source_added
  end
  local api = require "dbee.api"
  local path = get_spur_source_path()
  local sources = require("dbee.sources")
  local new_source = sources.FileSource:new(path)

  api.core.add_source(new_source)

  source_added = new_source
  return new_source
end

---@param job SpurDbeeJob
function SpurJobDbeeHandler:__execute_query(job, conn, query, from_query_editor)
  if job:execute_query(conn, query) then
    vim.schedule(function()
      self:open_job_output(job, conn)
      vim.schedule(function()
        local buf = vim.api.nvim_get_current_buf()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        local filetype = vim.bo[buf].filetype
        if not filetype:gmatch("dbee") then
          return
        end
        for _, k in ipairs({ "<C-O>", "<S-Tab>", "<C-I>", "<Tab>" }) do
          vim.keymap.set({ "i", "n" }, k, function()
            if from_query_editor == true then
              self:__query(job, conn, true)
            end
          end, { buffer = buf, desc = "Return to query editor" })
        end
      end)
    end)
  end
end

local visual_selection
function SpurJobDbeeHandler:__query(job, conn, from_result)
  local buf = vim.api.nvim_create_buf(false, true)
  local fileutils = require "spur.util.file"
  local path = fileutils.concat_path(vim.fn.stdpath("data"), "dbee", "spur.sql")
  if path == nil then
    return
  end
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

  local cursor = nil

  pcall(function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("edit " .. path)
    end)
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
  local title = "[Query] " .. conn.name
  pcall(function()
    local cur_database = require "dbee.api".core.connection_list_databases(conn.id)
    if type(cur_database) == "string" and cur_database ~= "" then
      title = title .. " (" .. cur_database .. ")"
    end
  end)

  local win_opts = self.__get_win_opts(title)
  win_opts.style = nil
  winid = vim.api.nvim_open_win(buf, true, win_opts)
  if type(cursor) == "table" and #cursor == 2 then
    vim.api.nvim_win_set_cursor(winid, cursor)
  end
  id = vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    group = group,
    once = false,
    callback = function()
      vim.schedule(close)
    end,
  })
  for _, key in ipairs({ "q", "Q", "<C-q>" }) do
    vim.keymap.set("n", key, function()
      vim.schedule(function() close(true) end)
    end, { buffer = buf, desc = "Close query window" })
  end
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
      self:__execute_query(job, conn, query, true)
    end, { buffer = buf, desc = "Execute query" })
  end
  for _, k in ipairs({ "<C-O>", "<S-Tab>", "<C-I>", "<Tab>" }) do
    vim.keymap.set({ "i", "n" }, k, function()
      if from_result == true then
        self:open_job_output(job, conn)
      end
    end, { buffer = buf, desc = "Return to result window" })
  end
  pcall(function()
    local cn = require("dbee.api").core.get_current_connection()
    if cn then
      for _, k in ipairs({ "<C-b>" }) do
        vim.keymap.set({ "v", "n", "i" }, k, function()
          vim.schedule(function()
            self:__select_database(job, cn)
          end)
        end, { buffer = buf, desc = "Open database selection" })
      end
    end
  end)
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

return SpurJobDbeeHandler
