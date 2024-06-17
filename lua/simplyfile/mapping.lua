local M = {}
local util = require("simplyfile.util")
local clipboard = require("simplyfile.clipboard")
local grid_mode = require("simplyfile.grid_mode")

M.override_state = util.override_state

function M.next()
  local pos = vim.api.nvim_win_get_cursor(0)
  local len = #vim.g.simplyfile_explorer.dirs
  if vim.g.simplyfile_config.grid_mode.enabled then
    local gpos = vim.g.simplyfile_explorer.grid_pos
    local maxcol = vim.g.simplyfile_explorer.grid_cols
    local dirs = vim.g.simplyfile_explorer.dirs
    if gpos[2] + 1 > maxcol then
      if gpos[1] < math.ceil(#dirs / maxcol) then
        gpos[1] = gpos[1] + 1
        gpos[2] = 1
      end
    else
      gpos[2] = gpos[2] + 1
    end
    util.override_state {
      grid_pos = gpos
    }
    grid_mode.render(vim.g.simplyfile_explorer.main, dirs)
  else
    vim.api.nvim_win_set_cursor(0, { pos[1] == len and pos[1] or pos[1] + 1, 0 })
  end
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
  end
end

function M.search_dirs()
  local search = vim.g.simplyfile_explorer.search

  local dirs = vim.g.simplyfile_explorer.dirs
  local new_dirs = {}
  for _, dir in ipairs(dirs) do
    if dir.name:match(search) then
      table.insert(new_dirs, dir)
    end
  end

  M.override_state {
    dirs = new_dirs,
  }
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

---Go to Current Working Directory
function M.go_to_cwd()
  local path = vim.fn.getcwd(0)
  M.override_state { path = path }
  ---@diagnostic disable-next-line: missing-fields
  M.refresh { absolute = "" }
end

---Set currrent explorer path as Current Working Directory
function M.current_path_as_cwd()
  local path = vim.g.simplyfile_explorer.path
  vim.cmd("cd " .. path)
  M.go_to_cwd()
end

---Set dir under cursor as Current Working Directory if
---{dir} is a folder and go to {dir}
---@param dir SimplyFile.Directory
function M.under_cursor_as_cwd(dir)
  if not dir then return end
  if not dir.is_folder then return end
  vim.cmd("cd " .. dir.absolute)
  M.go_to_cwd()
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
        vim.cmd("silent !mkdir -p " .. util.sanitize(new_dir))
        ---@diagnostic disable-next-line: missing-fields
        M.refresh { absolute = new_dir }
      end
    else
      if vim.fn.executable("touch") and vim.fn.executable("mkdir") then
        local folder = vim.fs.dirname(new_dir)
        vim.cmd("silent !mkdir -p " .. util.sanitize(folder))
        vim.cmd("silent !touch " .. util.sanitize(new_dir))
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
        os.remove(util.sanitize(dir.absolute))
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
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, vim.tbl_extend('force', config, {
    style = "minimal",
  }))
  local ns = vim.api.nvim_create_namespace("SimplyFile")
  local text = "  : "

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

  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = buf,
    callback = function()
      local input = vim.api.nvim_get_current_line()
      M.override_state {
        search = input,
      }
      M.reload_dirs()
      M.reload_main()
    end,
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

function M.clear_search(dir)
  M.override_state { search = "" }
  if dir then
    M.refresh(dir)
  else
    ---@diagnostic disable-next-line: missing-fields
    M.refresh { absolute = "" }
  end
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

function M.reload_main(dir)
  local main = vim.g.simplyfile_explorer.main
  local dirs = vim.g.simplyfile_explorer.dirs
  util.buf_unlocks(main.buf)

  if vim.g.simplyfile_config.grid_mode.enabled then
    vim.schedule(function()
      grid_mode.render(main, dirs, true, dir, true)
    end)
    M.preview(M.get_dir())
  else
    vim.api.nvim_win_set_cursor(main.win, { 1, 0 })
    vim.api.nvim_buf_set_lines(main.buf, 0, -1, false, { "" })
    for c, d in ipairs(dirs) do
      vim.api.nvim_buf_set_lines(main.buf, c - 1, c, false, { "  " .. d.icon .. " " .. d.name })
      vim.api.nvim_buf_add_highlight(main.buf, 0, d.hl, c - 1, 0, 5)
      local method = clipboard.get_method(d)
      if method then
        local hl
        if method == "cut" then
          hl = "SimplyFileCutMark"
        elseif method == 'copy' then
          hl = "SimplyFileCopyMark"
        end
        vim.api.nvim_buf_add_highlight(main.buf, 0, hl, c - 1, 5, -1)
      end
      if dir and d.absolute == dir.absolute then
        vim.api.nvim_win_set_cursor(main.win, { c, 0 })
      end
    end
  end

  util.buf_locks(main.buf)
end

---Redraw the ui
---@param dir SimplyFile.Directory start cursor on this directory
function M.redraw(dir)
  if not dir then return end
  local main = vim.g.simplyfile_explorer.main
  local left = vim.g.simplyfile_explorer.left
  local path = vim.g.simplyfile_explorer.path

  M.reload_main(dir)
  util.buf_unlocks(main.buf, left.buf)

  vim.api.nvim_buf_set_lines(left.buf, 0, -1, false, { "" })
  local parent_path = vim.fs.dirname(path)
  local parent_dirs = util.dirs(parent_path)
  if vim.g.simplyfile_config.grid_mode.enabled then
    ---@diagnostic disable-next-line: missing-fields
    grid_mode.render(left, parent_dirs, true, { absolute = path }, true)
  else
    for i, d in ipairs(parent_dirs) do
      vim.api.nvim_buf_set_lines(left.buf, i - 1, i, false, { "  " .. d.icon .. " " .. d.name })
      vim.api.nvim_buf_add_highlight(left.buf, 0, d.hl, i - 1, 0, 5)
      if d.absolute == path then
        vim.api.nvim_buf_add_highlight(left.buf, 0, "CursorLine", i - 1, 0, -1)
        vim.api.nvim_win_set_cursor(left.win, { i, 0 })
      end
    end
  end

  if vim.g.simplyfile_config.border.main ~= "none" then
    util.win_edit_config(main.win, { title = " " .. vim.fs.basename(path), title_pos = "center" })
  end
  if vim.g.simplyfile_config.border.left ~= "none" then
    util.win_edit_config(left.win, { title = " " .. vim.fs.basename(parent_path), title_pos = "right" })
  end
  util.buf_locks(main.buf, left.buf)
end

function M.grid_move(dir)
  local pos = vim.g.simplyfile_explorer.grid_pos
  local maxcol = vim.g.simplyfile_explorer.grid_cols
  local dirs = vim.g.simplyfile_explorer.dirs
  local i = (pos[1] - 1) * maxcol + pos[2]

  local new_pos = {}
  new_pos[1] = pos[1]
  if dir[1] > 0 then
    local j = i
    for _ = 1, dir[1] do
      if j + maxcol > #dirs then break end
      new_pos[1] = new_pos[1] + 1
      j = j + maxcol
    end
  else
    for _ = dir[1], -1 do
      if new_pos[1] == 1 then break end
      new_pos[1] = new_pos[1] - 1
    end
  end

  new_pos[2] = pos[2]
  if dir[2] > 0 then
    local j = i
    for _ = 1, dir[2] do
      if j % maxcol == 0 or j == #dirs then break end
      new_pos[2] = new_pos[2] + 1
      j = j + 1
    end
  else
    for _ = dir[2], -1 do
      if new_pos[2] == 1 then break end
      new_pos[2] = new_pos[2] - 1
    end
  end

  util.override_state {
    grid_pos = new_pos,
  }
  local main = vim.g.simplyfile_explorer.main
  grid_mode.render(main, dirs, false)
  M.preview(M.get_dir())
end

---get directory under cursor
---@return SimplyFile.Directory?
function M.get_dir()
  if not vim.g.simplyfile_explorer then return end
  if vim.g.simplyfile_config.grid_mode.enabled then
    local pos = vim.g.simplyfile_explorer.grid_pos
    local maxcol = vim.g.simplyfile_explorer.grid_cols
    return vim.g.simplyfile_explorer.dirs[(pos[1] - 1) * maxcol + pos[2]]
  else
    local main = vim.g.simplyfile_explorer.main
    return vim.g.simplyfile_explorer.dirs[vim.api.nvim_win_get_cursor(main.win)[1]]
  end
end

---show {dir} on preview
---@param dir? SimplyFile.Directory
function M.preview(dir)
  if not vim.g.simplyfile_explorer then return end
  local right = vim.g.simplyfile_explorer.right
  if dir then
    vim.schedule(function()
      util.buf_unlocks(right.buf)
      local draw_image = vim.g.simplyfile_config.preview.image
      if draw_image then
        if vim.api.nvim_get_option_value("filetype", { buf = right.buf }) == "image_preview" then
          local images = require("image").get_images { window = right.win }
          for _, img in ipairs(images) do
            img:clear()
          end
        end
      end
      if not util.callget(vim.g.simplyfile_config.preview.show, dir) then
        vim.api.nvim_buf_set_lines(right.buf, 0, -1, false, { "--: This File/Folder is not shown by the config :--" })
        vim.api.nvim_buf_add_highlight(right.buf, 0, "ErrorMsg", 0, 0, -1)
        util.buf_locks(right.buf)
        return
      end
      if not util.file_exists(dir.absolute) then return end
      vim.api.nvim_buf_set_lines(right.buf, 0, -1, false, { "" })
      if dir.is_folder then
        vim.api.nvim_set_option_value("filetype", "list_dir", {
          buf = right.buf
        })
        local cur_dirs = util.dirs(dir.absolute)
        if vim.g.simplyfile_config.grid_mode.enabled then
          grid_mode.render(right, cur_dirs, true, nil, false)
        else
        for c, dir in ipairs(cur_dirs) do
          vim.api.nvim_buf_set_lines(right.buf, c - 1, c, false, { "  " .. dir.icon .. " " .. dir.name })
          vim.api.nvim_buf_add_highlight(right.buf, 0, dir.hl, c - 1, 0, 5)
        end
        end
      else
        if (not draw_image) or (not vim.g.simplyfile_config.preview.is_image(dir)) then
          vim.api.nvim_set_option_value("filetype", dir.filetype, {
            buf = right.buf
          })
          local max_lines = util.callget(vim.g.simplyfile_config.preview.max_lines)
          local i = 0
          local lines = {}
          for line in io.lines(dir.absolute) do
            if i >= max_lines then
              break
            end
            table.insert(lines, line)
            i = i + 1
          end
          vim.api.nvim_buf_set_text(right.buf, 0, 0, -1, -1, lines)
        else
          vim.api.nvim_set_option_value("filetype", "image_preview", {
            buf = right.buf
          })
          require("image").from_file(dir.absolute, { window = right.win, buffer = right.buf }):render()
        end
      end
      if vim.g.simplyfile_config.border.right ~= "none" then
        util.win_edit_config(right.win, { title = dir.icon .. " " .. dir.name, title_pos = "left" })
      end
      util.buf_unlocks(right.buf)
    end)
  else
    util.buf_unlocks(right.buf)
    vim.api.nvim_set_option_value("filetype", "empty", { buf = right.buf })
    vim.api.nvim_buf_set_lines(right.buf, 0, -1, false, { "" })
    if vim.g.simplyfile_config.border.right ~= "none" then
      util.win_edit_config(right.win, { title = "", title_pos = "left" })
    end
    util.buf_locks(right.buf)
  end
end

---use the get_default() instead
---@deprecated
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
  S = M.clear_search,
  f = M.filter,
  F = M.set_filter_to_default,
  ["<C-f>"] = M.toggle_reverse_filter,
  o = M.sort,
  O = M.set_sort_to_default,
  ["<C-o>"] = M.toggle_reverse_sort,
  c = clipboard.copy,
  x = clipboard.cut,
  R = clipboard.remove_from_clipboard,
  v = M.paste,
  V = M.paste_select,
  gc = M.go_to_cwd,
  ["<C-u>"] = M.under_cursor_as_cwd,
  ["<C-p>"] = M.current_path_as_cwd,
}

function M.get_default()
  if vim.g.simplyfile_config.grid_mode.enabled then
    return {
      ["<ESC>"] = function() vim.cmd("SimplyFileClose") end,
      ["<Right>"] = function() M.grid_move { 0, 1 } end,
      ["<Left>"] = function() M.grid_move { 0, -1 } end,
      ["<Up>"] = function() M.grid_move { -1, 0 } end,
      ["<Down>"] = function() M.grid_move { 1, 0 } end,
      l = function() M.grid_move { 0, 1 } end,
      h = function() M.grid_move { 0, -1 } end,
      k = function() M.grid_move { -1, 0 } end,
      j = function() M.grid_move { 1, 0 } end,
      ["<C-Left>"] = M.go_to_parent,
      ["<C-h>"] = M.go_to_parent,
      ["<CR>"] = M.open,
      a = M.add,
      r = M.rename,
      d = M.delete,
      s = M.search,
      S = M.clear_search,
      f = M.filter,
      F = M.set_filter_to_default,
      ["<C-f>"] = M.toggle_reverse_filter,
      o = M.sort,
      O = M.set_sort_to_default,
      ["<C-o>"] = M.toggle_reverse_sort,
      c = function(dir)
        clipboard.copy(dir)
        M.next()
      end,
      x = function(dir)
        clipboard.cut(dir)
        M.next()
      end,
      R = function(dir)
        clipboard.remove_from_clipboard(dir)
        M.next()
      end,
      v = M.paste,
      V = M.paste_select,
      gc = M.go_to_cwd,
      ["<C-u>"] = M.under_cursor_as_cwd,
      ["<C-p>"] = M.current_path_as_cwd,
    }
  else
    return {
      ["<ESC>"] = function() vim.cmd("SimplyFileClose") end,
      ["<Right>"] = M.open,
      ["<Left>"] = M.go_to_parent,
      l = M.open,
      h = M.go_to_parent,
      a = M.add,
      r = M.rename,
      d = M.delete,
      s = M.search,
      S = M.clear_search,
      f = M.filter,
      F = M.set_filter_to_default,
      ["<C-f>"] = M.toggle_reverse_filter,
      o = M.sort,
      O = M.set_sort_to_default,
      ["<C-o>"] = M.toggle_reverse_sort,
      c = clipboard.copy,
      x = clipboard.cut,
      R = clipboard.remove_from_clipboard,
      v = M.paste,
      V = M.paste_select,
      gc = M.go_to_cwd,
      ["<C-u>"] = M.under_cursor_as_cwd,
      ["<C-p>"] = M.current_path_as_cwd,
    }
  end
end

return M
