local M = {}
local util = require("simplyfile.util")
local clipboard = require("simplyfile.clipboard")

---open folder or file
---@param dir SimplyFile.Directory
function M.open(dir)
  if not dir then return end
  if dir.is_folder then
    local main = vim.g.simplyfile_explorer.main
    local left = vim.g.simplyfile_explorer.left
    local search = vim.g.simplyfile_explorer.search
    local dirs = {}
    for _, dir in ipairs(util.dirs(dir.absolute)) do
      if dir.name:match(search) then
        table.insert(dirs, dir)
      end
    end
    vim.g.simplyfile_explorer = vim.tbl_extend("force", vim.g.simplyfile_explorer, {
      dirs = dirs,
      path = dir.absolute,
    })

    util.buf_unlocks(main.buf, left.buf)
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
        vim.api.nvim_win_set_cursor(left.win, { i, 0 })
      end
    end

    util.win_edit_config(main.win, { title = " " .. dir.name })
    util.buf_locks(main.buf, left.buf)
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
  local search = vim.g.simplyfile_explorer.search
  local parent = vim.fs.dirname(path)
  local dirs = {}
  for _, dir in ipairs(util.dirs(parent)) do
    if dir.name:match(search) then
      table.insert(dirs, dir)
    end
  end

  vim.g.simplyfile_explorer = vim.tbl_extend("force", vim.g.simplyfile_explorer, {
    path = parent,
    dirs = dirs,
  })

  util.buf_unlocks(main.buf, left.buf)
  vim.api.nvim_win_set_cursor(main.win, { 1, 0 })
  vim.api.nvim_buf_set_lines(main.buf, 0, -1, false, { "" })
  for i, d in ipairs(dirs) do
    vim.api.nvim_buf_set_lines(main.buf, i - 1, i, false, { "  " .. d.icon .. " " .. d.name })
    vim.api.nvim_buf_add_highlight(main.buf, 0, d.hl, i - 1, 0, 5)
    if d.absolute == path then
      vim.api.nvim_win_set_cursor(main.win, { i, 0 })
    end
  end

  local parent_dirs = util.dirs(vim.fs.dirname(parent))
  vim.api.nvim_buf_set_lines(left.buf, 0, -1, false, { "" })
  for i, d in ipairs(parent_dirs) do
    vim.api.nvim_buf_set_lines(left.buf, i - 1, i, false, { "  " .. d.icon .. " " .. d.name })
    vim.api.nvim_buf_add_highlight(left.buf, 0, d.hl, i - 1, 0, 5)
    if d.absolute == parent then
      vim.api.nvim_buf_add_highlight(left.buf, 0, "CursorLine", i - 1, 0, -1)
      vim.api.nvim_win_set_cursor(left.win, { i, 0 })
    end
  end

  util.win_edit_config(main.win, { title = " " .. vim.fs.basename(parent) })
  util.buf_locks(main.buf, left.buf)
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
  local pos = vim.api.nvim_win_get_cursor(0)
  vim.ui.select({ "No", "Yes" },
    { prompt = "Are You Sure Wanna Delete '" .. dir.icon .. " " .. dir.name .. "' Permanently? " }, function(item)
      if item == "Yes" then
        os.remove(dir.absolute)
        ---@diagnostic disable-next-line: missing-fields
        M.refresh { absolute = "" }
        vim.api.nvim_win_set_cursor(0, { pos[1] > 1 and pos[1] - 1 or 1, pos[2] })
      end
    end)
end

function M.search()
  local config = vim.api.nvim_win_get_config(vim.g.simplyfile_explorer.up.win)
  local buf = vim.api.nvim_create_buf(true, true)
  local win = vim.api.nvim_open_win(buf, true, config)
  local ns = vim.api.nvim_create_namespace("SimplyFile")
  local text = "Search For: "

  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    id = 1,
    end_row = 0,
    end_col = 0,
    virt_text = { { text, "@field" } },
    virt_text_pos = "inline",
    right_gravity = false,
  })

  local close = function()
    vim.cmd.stopinsert()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_del_extmark(buf, ns, 1)
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  vim.api.nvim_buf_set_keymap(buf, "i", "<ESC>", "", {
    callback = close
  })
  vim.api.nvim_buf_set_keymap(buf, "i", "<CR>", "", {
    callback = function()
      local input = vim.api.nvim_get_current_line()
      local up = vim.g.simplyfile_explorer.up.buf

      util.buf_unlocks(up)
      if input == "" then
        vim.api.nvim_buf_del_extmark(up, ns, 1)
      else
        vim.api.nvim_buf_set_extmark(up, ns, 0, 0, {
          id = 1,
          end_row = 0,
          end_col = 0,
          virt_text = { { text, "@field" }, { input, "@string" } },
          virt_text_pos = "inline",
          right_gravity = false,
        })
      end
      util.buf_locks(up)

      local new_dirs = {}
      for _, dir in ipairs(util.dirs(vim.g.simplyfile_explorer.path)) do
        if dir.name:match(input) then
          table.insert(new_dirs, dir)
        end
      end

      vim.g.simplyfile_explorer = vim.tbl_extend('force', vim.g.simplyfile_explorer, {
        dirs = new_dirs,
        search = input,
      })
      ---@diagnostic disable-next-line: missing-fields
      M.redraw { absolute = "" }
      close()
    end
  })

  vim.api.nvim_set_current_line(vim.g.simplyfile_explorer.search)

  vim.cmd("setlocal nocursorline nonumber")
  vim.cmd("startinsert!")
end

function M.paste(dir)
  local dest = vim.g.simplyfile_explorer.path
  clipboard.paste_last(dest, function()
    if dir then
      M.refresh(dir)
    else
      ---@diagnostic disable-next-line: missing-fields
      M.refresh { absolute = "" }
    end
  end)
end

function M.paste_select(dir)
  local dest = vim.g.simplyfile_explorer.path
  clipboard.paste_select(dest, function()
    if dir then
      M.refresh(dir)
    else
      ---@diagnostic disable-next-line: missing-fields
      M.refresh { absolute = "" }
    end
  end)
end

---Refresh SimplyFile explorer
---@param dir SimplyFile.Directory start cursor on this directory
function M.refresh(dir)
  if not dir then return end
  local path = vim.g.simplyfile_explorer.path
  local search = vim.g.simplyfile_explorer.search
  local dirs = {}
  for _, dir in ipairs(util.dirs(path)) do
    if dir.name:match(search) then
      table.insert(dirs, dir)
    end
  end
  vim.g.simplyfile_explorer = vim.tbl_extend("force", vim.g.simplyfile_explorer, {
    dirs = dirs,
  })
  M.redraw(dir)
end

---Redraw the ui
---@param dir SimplyFile.Directory start cursor on this directory
function M.redraw(dir)
  if not dir then return end
  local main = vim.g.simplyfile_explorer.main
  local left = vim.g.simplyfile_explorer.left
  local path = vim.g.simplyfile_explorer.path
  local dirs = vim.g.simplyfile_explorer.dirs

  util.buf_unlocks(main.buf, left.buf)
  vim.api.nvim_win_set_cursor(main.win, { 1, 0 })
  vim.api.nvim_buf_set_lines(main.buf, 0, -1, false, { "" })
  for c, d in ipairs(dirs) do
    vim.api.nvim_buf_set_lines(main.buf, c - 1, c, false, { "  " .. d.icon .. " " .. d.name })
    vim.api.nvim_buf_add_highlight(main.buf, 0, d.hl, c - 1, 0, 5)
    if d.absolute == dir.absolute then
      vim.api.nvim_win_set_cursor(main.win, { c, 0 })
    end
  end

  vim.api.nvim_buf_set_lines(left.buf, 0, -1, false, { "" })
  local parent_dirs = util.dirs(vim.fs.dirname(path))
  for i, d in ipairs(parent_dirs) do
    vim.api.nvim_buf_set_lines(left.buf, i - 1, i, false, { "  " .. d.icon .. " " .. d.name })
    vim.api.nvim_buf_add_highlight(left.buf, 0, d.hl, i - 1, 0, 5)
    if d.absolute == path then
      vim.api.nvim_buf_add_highlight(left.buf, 0, "CursorLine", i - 1, 0, -1)
      vim.api.nvim_win_set_cursor(left.win, { i, 0 })
    end
  end

  util.win_edit_config(main.win, { title = " " .. vim.fs.basename(path) })
  util.buf_locks(main.buf, left.buf)
end

M.default = {
  ["<ESC>"] = function() vim.cmd("SimplyFileClose") end,
  ["<Right>"] = M.open,
  ["<Left>"] = M.go_to_parent,
  l = M.open,
  h = M.go_to_parent,
  a = M.add,
  r = M.rename,
  d = M.delete,
  s = M.search,
  c = clipboard.copy,
  x = clipboard.cut,
  v = M.paste,
  V = M.paste_select,
}

return M
