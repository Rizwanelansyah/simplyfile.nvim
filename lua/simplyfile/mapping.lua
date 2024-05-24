local M = {}
local util = require("simplyfile.util")
local clipboard = require("simplyfile.clipboard")

---override field on {vim.g.simplyfile_explorer}
---@param value SimplyFile.ExplState
function M.override_state(value)
  vim.g.simplyfile_explorer = vim.tbl_extend("force", vim.g.simplyfile_explorer, value)
end

---get current filter state
---@return fun(dir?: SimplyFile.Directory): boolean
function M.get_filter()
  local filter = vim.g.simplyfile_explorer.filter
  if type(filter) == "string" then
    return vim.g.simplyfile_config.filters[filter] or function() return true end
  elseif type(filter) == "function" then
    return filter
  end
  return function() return true end
end

---get current sort state
---@return fun(a: SimplyFile.Directory, b: SimplyFile.Directory): boolean
function M.get_sort()
  local sort = vim.g.simplyfile_explorer.sort
  if type(sort) == "string" then
    return vim.g.simplyfile_config.sorts[sort] or function() return true end
  elseif type(sort) == "function" then
    return sort
  end
  return function() return true end
end

function M.filter_dirs()
  if vim.g.simplyfile_explorer.filter ~= nil then
    local filter = M.get_filter()
    local dirs = vim.g.simplyfile_explorer.dirs
    local filtered_dirs = {}
    for _, dir in ipairs(dirs) do
      if vim.g.simplyfile_explorer.reverse_filter then
        if not filter(dir) then
          table.insert(filtered_dirs, dir)
        end
      else
        if filter(dir) then
          table.insert(filtered_dirs, dir)
        end
      end
    end
    M.override_state { dirs = filtered_dirs }

    local ns = vim.api.nvim_create_namespace("SimplyFile")
    local up = vim.g.simplyfile_explorer.up.buf
    if type(vim.g.simplyfile_explorer.filter) ~= "string" and not vim.g.simplyfile_explorer.reverse_filter then
      vim.api.nvim_buf_del_extmark(up, ns, 1)
      return
    end

    util.buf_unlocks(up)
    local virt_text = {}
    table.insert(virt_text, { " | ", "FloatBorder" })
    table.insert(virt_text, { " : ", "@field" })

    if vim.g.simplyfile_explorer.reverse_filter then
      table.insert(virt_text, { "reversed ", "@keyword" })
    end

    if type(vim.g.simplyfile_explorer.filter) == "string" then
      local filter_name = vim.g.simplyfile_explorer.filter
      table.insert(virt_text, { filter_name, "@string" })
    end
    table.insert(virt_text, { " | ", "FloatBorder" })

    vim.api.nvim_buf_set_extmark(up, ns, 0, 0, {
      id = 1,
      end_row = 0,
      end_col = 0,
      virt_text = virt_text,
      virt_text_pos = "inline",
      right_gravity = false,
    })
    util.buf_locks(up)
  end
end

function M.search_dirs()
  local ns = vim.api.nvim_create_namespace("SimplyFile")
  local search = vim.g.simplyfile_explorer.search
  local up = vim.g.simplyfile_explorer.up.buf

  util.buf_unlocks(up)
  if search == "" then
    vim.api.nvim_buf_del_extmark(up, ns, 2)
  else
    local virt_text = {}
    table.insert(virt_text, { " | ", "FloatBorder" })
    table.insert(virt_text, { " : ", "@field" })
    table.insert(virt_text, { search, "@string" })
    table.insert(virt_text, { " | ", "FloatBorder" })
    vim.api.nvim_buf_set_extmark(up, ns, 0, 0, {
      id = 2,
      end_row = 0,
      end_col = 0,
      virt_text = virt_text,
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end
  util.buf_locks(up)

  local dirs = vim.g.simplyfile_explorer.dirs
  local new_dirs = {}
  for _, dir in ipairs(dirs) do
    if dir.name:match(search) then
      table.insert(new_dirs, dir)
    end
  end

  vim.g.simplyfile_explorer = vim.tbl_extend('force', vim.g.simplyfile_explorer, {
    dirs = new_dirs,
  })
end

function M.sort_dirs()
  local sort = M.get_sort()
  local dirs = vim.g.simplyfile_explorer.dirs
  if vim.g.simplyfile_explorer.reverse_sort then
    table.sort(dirs, sort)
    local new_dirs = {}
    for _, dir in ipairs(dirs) do
      table.insert(new_dirs, 1, dir)
    end
    dirs = new_dirs
  else
    table.sort(dirs, sort)
  end
  M.override_state { dirs = dirs }

  local ns = vim.api.nvim_create_namespace("SimplyFile")
  local up = vim.g.simplyfile_explorer.up.buf
  if type(vim.g.simplyfile_explorer.sort) ~= "string" and not vim.g.simplyfile_explorer.reverse_sort then
    vim.api.nvim_buf_del_extmark(up, ns, 3)
    return
  end

  util.buf_unlocks(up)
  local virt_text = {}
  table.insert(virt_text, { " | ", "FloatBorder" })
  table.insert(virt_text, { "󰒺 : ", "@field" })

  if vim.g.simplyfile_explorer.reverse_sort then
    table.insert(virt_text, { "reversed ", "@keyword" })
  end

  if type(vim.g.simplyfile_explorer.sort) == "string" then
    local sort_name = vim.g.simplyfile_explorer.sort
    table.insert(virt_text, { sort_name, "@string" })
  end

  table.insert(virt_text, { " | ", "FloatBorder" })
  vim.api.nvim_buf_set_extmark(up, ns, 0, 0, {
    id = 3,
    end_row = 0,
    end_col = 0,
    virt_text = virt_text,
    virt_text_pos = "inline",
    right_gravity = false,
  })
  util.buf_locks(up)
end

function M.reload_dirs()
  M.override_state { dirs = util.dirs(vim.g.simplyfile_explorer.path) }
  M.filter_dirs()
  M.search_dirs()
  M.sort_dirs()
end

---open folder or file
---@param dir SimplyFile.Directory
function M.open(dir)
  if not dir then return end
  if dir.is_folder then
    M.override_state { path = dir.absolute, }
    M.reload_dirs()
    M.redraw(dir)
  else
    vim.cmd [[ SimplyFileClose ]]
    vim.cmd("e " .. dir.absolute)
  end
end

---Go to the parent directory
function M.go_to_parent()
  local path = vim.g.simplyfile_explorer.path
  local parent = vim.fs.dirname(path)

  M.override_state {
    path = parent,
  }
  ---@diagnostic disable-next-line: missing-fields
  M.refresh { absolute = path }
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

function M.filter(dir)
  vim.ui.select(vim.tbl_keys(vim.g.simplyfile_config.filters), {
    prompt = "Select Filter: ",
    format_item = function(item)
      return "Use '" .. item .. "' Filter"
    end,
  }, function(item)
    if item then
      M.override_state { filter = item }
      M.reload_dirs()
      if dir then
        M.redraw(dir)
      else
        ---@diagnostic disable-next-line: missing-fields
        M.redraw { absolute = "" }
      end
    end
  end)
end

function M.set_filter_to_default(dir)
  M.override_state { filter = vim.g.simplyfile_config.default_filter }
  M.reload_dirs()
  if dir then
    M.redraw(dir)
  else
    ---@diagnostic disable-next-line: missing-fields
    M.redraw { absolute = "" }
  end
end

function M.toggle_reverse_filter(dir)
  M.override_state { reverse_filter = not vim.g.simplyfile_explorer.reverse_filter }
  if dir then
    M.refresh(dir)
  else
    ---@diagnostic disable-next-line: missing-fields
    M.refresh { absolute = "" }
  end
end

function M.sort(dir)
  vim.ui.select(vim.tbl_keys(vim.g.simplyfile_config.sorts), {
    prompt = "Select Sort: ",
    format_item = function(item)
      return "Use '" .. item .. "' Sort"
    end,
  }, function(item)
    if item then
      M.override_state { sort = item }
      M.reload_dirs()
      if dir then
        M.redraw(dir)
      else
        ---@diagnostic disable-next-line: missing-fields
        M.redraw { absolute = "" }
      end
    end
  end)
end

function M.set_sort_to_default(dir)
  M.override_state { sort = vim.g.simplyfile_config.default_sort }
  M.reload_dirs()
  if dir then
    M.redraw(dir)
  else
    ---@diagnostic disable-next-line: missing-fields
    M.redraw { absolute = "" }
  end
end

function M.toggle_reverse_sort(dir)
  M.override_state { reverse_sort = not vim.g.simplyfile_explorer.reverse_sort }
  if dir then
    M.refresh(dir)
  else
    ---@diagnostic disable-next-line: missing-fields
    M.refresh { absolute = "" }
  end
end

function M.search()
  local config = vim.api.nvim_win_get_config(vim.g.simplyfile_explorer.up.win)
  local buf = vim.api.nvim_create_buf(true, true)
  local win = vim.api.nvim_open_win(buf, true, config)
  local ns = vim.api.nvim_create_namespace("SimplyFileSearchStatus")
  local text = " : "

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
      M.override_state {
        search = input,
      }
      ---@diagnostic disable-next-line: missing-fields
      M.refresh { absolute = "" }
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
  M.reload_dirs()
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
  f = M.filter,
  F = M.set_filter_to_default,
  ["<C-f>"] = M.toggle_reverse_filter,
  o = M.sort,
  O = M.set_sort_to_default,
  ["<C-o>"] = M.toggle_reverse_sort,
  c = clipboard.copy,
  x = clipboard.cut,
  v = M.paste,
  V = M.paste_select,
}

return M
