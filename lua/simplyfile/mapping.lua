local M = {}
local util = require("simplyfile.util")

---open folder or file
---@param dir SimplyFile.Directory
function M.open(dir)
  if not dir then return end
  if dir.is_folder then
    local main = vim.g.simplyfile_explorer.main
    local left = vim.g.simplyfile_explorer.left
    local dirs = util.dirs(dir.absolute)
    vim.g.simplyfile_explorer = vim.tbl_extend("force", vim.g.simplyfile_explorer, {
      dirs = dirs,
      path = dir.absolute,
    })

    vim.api.nvim_win_set_cursor(main.win, { 1, 0 })
    vim.api.nvim_buf_set_lines(main.buf, 0, -1, false, { "" })
    for c, d in ipairs(dirs) do
      vim.api.nvim_buf_set_lines(main.buf, c - 1, c, false, { "  " .. d.icon .. " " .. d.name })
      vim.api.nvim_buf_add_highlight(main.buf, 0, d.hl, c - 1, 0, 5)
    end

    vim.api.nvim_buf_set_lines(left.buf, 0, -1, false, { "" })
    local parent_dirs = util.dirs(vim.fs.dirname(dir.absolute))
    for i, d in ipairs(parent_dirs) do
      vim.api.nvim_buf_set_lines(left.buf, i - 1, i, false, { "  " .. d.icon .. " " .. d.name })
      vim.api.nvim_buf_add_highlight(left.buf, 0, d.hl, i - 1, 0, 5)
      if d.absolute == dir.absolute then
        vim.api.nvim_buf_add_highlight(left.buf, 0, "CursorLine", i - 1, 0, -1)
      end
    end

    util.win_edit_config(main.win, { title = " " .. dir.name })
  else
    vim.cmd [[ SimplyFileClose ]]
    vim.cmd("e " .. dir.absolute)
  end
end

---Go to the parent directory
function M.go_to_parent()
  local main = vim.g.simplyfile_explorer.main
  local left = vim.g.simplyfile_explorer.left
  local path = vim.g.simplyfile_explorer.path
  local parent = vim.fs.dirname(path)
  local dirs = util.dirs(parent)
  vim.g.simplyfile_explorer = vim.tbl_extend("force", vim.g.simplyfile_explorer, {
    path = parent,
    dirs = dirs,
  })

  vim.api.nvim_win_set_cursor(main.win, { 1, 0 })
  vim.api.nvim_buf_set_lines(main.buf, 0, -1, false, { "" })
  for c, d in ipairs(dirs) do
    vim.api.nvim_buf_set_lines(main.buf, c - 1, c, false, { "  " .. d.icon .. " " .. d.name })
    vim.api.nvim_buf_add_highlight(main.buf, 0, d.hl, c - 1, 0, 5)
    if d.absolute == path then
      vim.api.nvim_win_set_cursor(main.win, { c, 0 })
    end
  end

  local parent_dirs = util.dirs(vim.fs.dirname(parent))
  vim.api.nvim_buf_set_lines(left.buf, 0, -1, false, { "" })
  for i, d in ipairs(parent_dirs) do
    vim.api.nvim_buf_set_lines(left.buf, i - 1, i, false, { "  " .. d.icon .. " " .. d.name })
    vim.api.nvim_buf_add_highlight(left.buf, 0, d.hl, i - 1, 0, 5)
    if d.absolute == parent then
      vim.api.nvim_buf_add_highlight(left.buf, 0, "CursorLine", i - 1, 0, -1)
    end
  end

  util.win_edit_config(main.win, { title = " " .. vim.fs.basename(parent) })
end

---add new file/folder to current directory
function M.add()
  vim.ui.input({ prompt = "New File/Folder Name: " }, function(value)
    if value == nil then return end
    local path = vim.g.simplyfile_explorer.path
    local new_dir = path .. "/" .. value
    if vim.endswith(new_dir, "/") then
      if vim.fn.executable("mkdir") then
        new_dir = new_dir:sub(1, -2)
        vim.cmd("silent !mkdir -p " .. new_dir)
        ---@diagnostic disable-next-line: missing-fields
        M.refresh { absolute = new_dir }
      end
    else
      if vim.fn.executable("touch") and vim.fn.executable("mkdir") then
        local folder = vim.fs.dirname(new_dir)
        vim.cmd("silent !mkdir -p " .. folder)
        vim.cmd("silent !touch " .. new_dir)
        ---@diagnostic disable-next-line: missing-fields
        M.refresh { absolute = new_dir }
      end
    end
  end)
end

---Rename directory
---@param dir SimplyFile.Directory
function M.rename(dir)
  if not dir then return end
  vim.ui.input({ prompt = "New Name: ", default = dir.name }, function(value)
    local new_name = vim.fs.dirname(dir.absolute) .. "/" .. value
    os.rename(dir.absolute, new_name)
    ---@diagnostic disable-next-line: missing-fields
    M.refresh { absolute = new_name }
  end)
end

---Delete permanently a directory
---@param dir SimplyFile.Directory
function M.delete(dir)
  if not dir then return end
  vim.ui.select({ "No", "Yes" },
    { prompt = "Are You Sure Wanna Delete '" .. dir.icon .. " " .. dir.name .. "' Permanently? " }, function(item)
      if item == "Yes" then
        os.remove(dir.absolute)
        ---@diagnostic disable-next-line: missing-fields
        M.refresh { absolute = "" }
      end
    end)
end

---Refresh SimplyFile explorer
---@param dir SimplyFile.Directory start cursor on this directory
function M.refresh(dir)
  if not dir then return end
  local main = vim.g.simplyfile_explorer.main
  local left = vim.g.simplyfile_explorer.left
  local path = vim.g.simplyfile_explorer.path
  local dirs = util.dirs(path)
  vim.g.simplyfile_explorer = vim.tbl_extend("force", vim.g.simplyfile_explorer, {
    dirs = dirs,
  })

  vim.api.nvim_win_set_cursor(main.win, { 1, 0 })
  vim.api.nvim_buf_set_lines(main.buf, 0, -1, false, { "" })
  for i, d in ipairs(dirs) do
    vim.api.nvim_buf_set_lines(main.buf, i - 1, i, false, { "  " .. d.icon .. " " .. d.name })
    vim.api.nvim_buf_add_highlight(main.buf, 0, d.hl, i - 1, 0, 5)
    if d.absolute == dir.absolute then
      vim.api.nvim_win_set_cursor(main.win, { i, 0 })
    end
  end

  vim.api.nvim_buf_set_lines(left.buf, 0, -1, false, { "" })
  local parent_dirs = util.dirs(vim.fs.dirname(path))
  for i, d in ipairs(parent_dirs) do
    vim.api.nvim_buf_set_lines(left.buf, i - 1, i, false, { "  " .. d.icon .. " " .. d.name })
    vim.api.nvim_buf_add_highlight(left.buf, 0, d.hl, i - 1, 0, 5)
    if d.absolute == path then
      vim.api.nvim_buf_add_highlight(left.buf, 0, "CursorLine", i - 1, 0, -1)
    end
  end

  util.win_edit_config(main.win, { title = " " .. path })
end

M.default = {
  ["<ESC>"] = function() vim.cmd("SimplyFileClose") end,
  ["<Right>"] = M.open,
  ["<Left>"] = M.go_to_parent,
  a = M.add,
  r = M.rename,
  d = M.delete,
}

return M
