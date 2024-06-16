local M = {}

---get devicon highlight
local function get_highlight_name(data)
  if not data then return "NormalFloat" end

  if not data.name then
    return "NormalFloat"
  end

  return "DevIcon" .. data.name
end

---override field on {vim.g.simplyfile_explorer}
---@param value SimplyFile.ExplState
function M.override_state(value)
  vim.g.simplyfile_explorer = vim.tbl_extend("force", vim.g.simplyfile_explorer, value)
  vim.cmd("doautocmd User SimplyFileStateChange")
end

---@class SimplyFile.Directory
---@field name string name of the directory
---@field absolute string absolute path of the directory
---@field is_folder boolean true if the directory is folder otherwise false
---@field icon string nerd fonts icon that represent the directory
---@field hl string hl name of the directory icon
---@field filetype string filetype if its a file

---get all directory on {path}
---@param path string path to folder
---@return SimplyFile.Directory[] # return a table that contains all diretory or an emty table
function M.dirs(path)
  local dirs = {}
  local files = {}
  local icons_by_filename = {}
  local icons_by_extension = {}
  local ok, devicon = pcall(require, "nvim-web-devicons")

  if ok then
    icons_by_filename = devicon.get_icons_by_filename()
    icons_by_extension = devicon.get_icons_by_extension()
  end

  if vim.fn.isdirectory(path) then
    for name, type in vim.fs.dir(path, { depth = 1 }) do
      local icon = icons_by_filename[name]
      local hl = "NormalFloat"
      local filetype = vim.filetype.match { filename = name }
      if ok and icon then
        hl = get_highlight_name(icon)
      elseif ok and filetype then
        local i, h = devicon.get_icon_by_filetype(filetype, { default = true })
        hl = h
        icon = { icon = i }
      end
      if (not icon) and ok then
        local splitted_name = vim.split(name, "%.")
        icon = icons_by_extension[splitted_name[#splitted_name]] or { icon = "" }
        hl = get_highlight_name(icon)
      end
      if not icon then
        icon = { icon = "" }
      end

      local is_folder = false
      if vim.fn.isdirectory(vim.fs.normalize(path) .. "/" .. name) == 1 then
        is_folder = true
        icon = {
          icon = "",
        }
        hl = "Directory"
        filetype = 'directory'
      end
      if type == "link" then
        icon = { icon = is_folder and "" or "󱅷" }
      end

      if is_folder then
        table.insert(dirs, {
          name = name,
          absolute = vim.fs.normalize(path) .. "/" .. name,
          is_folder = is_folder,
          icon = icon.icon,
          hl = hl,
          filetype = filetype,
        })
      else
        table.insert(files, {
          name = name,
          absolute = vim.fs.normalize(path) .. "/" .. name,
          is_folder = is_folder,
          icon = icon.icon,
          hl = hl,
          filetype = filetype,
        })
      end
    end
  end

  for _, file in ipairs(files) do
    table.insert(dirs, file)
  end

  return dirs
end

function M.trim_dot(path)
  local split = vim.split(path, "/", { trimempty = true })
  local new_path = {}
  for _, dir in ipairs(split) do
    if dir == ".." then
      table.remove(new_path, #new_path)
    elseif dir == "." then
    else
      table.insert(new_path, dir)
    end
  end
  if #new_path < 1 then
    return "/"
  end

  local str = ""
  for _, dir in ipairs(new_path) do
    str = str .. "/" .. dir
  end
  return str
end

---return the {value} percent of {max}
---@param value integer
---@param max integer
---@return integer
function M.percent_of(value, max)
  return math.floor(max * (value / 100))
end

---check the file is exists or not
---@param name string path to the file
---@return boolean?
function M.file_exists(name)
  local f = io.open(name, "r")
  return f ~= nil and io.close(f)
end

---open a new window
---@param width integer
---@param height integer
---@param row integer
---@param col integer
---@param buf integer bufnr
---@param enter boolean enter to window or not
---@return integer # widow_handle
function M.open_win(width, height, row, col, buf, enter)
  return vim.api.nvim_open_win(buf, enter, {
    width = width,
    height = height,
    row = row,
    col = col,
    relative = 'editor',
    style = 'minimal',
    border = 'single',
  })
end

function M.win_edit_config(win, additional_config)
  local config = vim.api.nvim_win_get_config(win)
  config = vim.tbl_extend("force", config, additional_config)
  vim.api.nvim_win_set_config(win, config)
end

---set readonly and not modifiable on buffers
---@param ... integer
function M.buf_locks(...)
  for _, bufnr in ipairs({ ... }) do
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    vim.api.nvim_set_option_value("readonly", true, { buf = bufnr })
  end
end

---set not readonly and modifiable on buffers
---@param ... integer
function M.buf_unlocks(...)
  for _, bufnr in ipairs({ ... }) do
    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
    vim.api.nvim_set_option_value("readonly", false, { buf = bufnr })
  end
end

function M.callget(value, ...)
  if type(value) == "function" then
    return value(...)
  else
    return value
  end
end

---escape string that contain quote back slash
---to make a valid file/folder name
---@param str string
---@return string
function M.sanitize(str)
  str = str
      :gsub('\\', '\\\\')
      :gsub('"', '\\"')
      :gsub("'", "\\'")
      :gsub(" ", "\\ ")
  return str
end

---test if the {string} match one of the pattern in {patterns}
---@param str string
---@param patterns string[]
---@return boolean
function M.matches(str, patterns)
  for _, pat in ipairs(patterns or {}) do
    if str:match(pat) then return true end
  end
  return false
end

---centerize or cut the text
---@param text string
---@param len integer
---@return string
function M.text_center(text, len)
  local txt = text
  local left = true
  local curlen = #txt
  while curlen < len do
    if left then
      txt = " " .. txt
    else
      txt = txt .. " "
    end
    curlen = curlen + 1
    left = not left
  end
  if #txt > len then
    txt = txt:sub(1, len - 3) .. "..."
  end
  return txt
end

return M
