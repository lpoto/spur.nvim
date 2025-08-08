local M = {}

--- Read a file asynchronously
--- and call the callback with the content.
---
--- @param path string
--- @param callback function
--- @diagnostic disable
function M.read_file_async(path, callback)
  if type(path) ~= "string"
      or path == ""
      or vim.fn.filereadable(path) ~= 1
  then
    return callback(nil)
  end
  local uv = vim.uv or vim.loop
  uv.fs_open(path, "r", 438, function(open_err, fd)
    if open_err or not fd then return callback(nil) end
    uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err or not stat then
        uv.fs_close(fd)
        return callback(nil)
      end
      uv.fs_read(fd, stat.size, 0, function(read_err, data)
        uv.fs_close(fd)
        if read_err or not data then return callback(nil) end
        callback(data)
      end)
    end)
  end)
end

--- Read a file synchronously
--- and require to trust the file.
---
--- @param path string
--- @return string|nil
function M.read_file_secure(path)
  if type(path) ~= "string"
      or path == ""
      or vim.fn.filereadable(path) ~= 1
  then
    return nil
  end
  local content = vim.secure.read(path)
  if type(content) == "string" and content ~= "" then
    return content
  end
  return nil
end

---@param ... string
---@return string|nil
function M.concat_path(...)
  local sep = M.get_path_separator()
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
function M.get_path_separator()
  return vim.fn.has("win32") == 1 and "\\" or "/"
end

return M
