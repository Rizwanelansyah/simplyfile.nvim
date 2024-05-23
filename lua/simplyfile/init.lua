local M = {}
local util = require("simplyfile.util")
local mapping = require("simplyfile.mapping")
local po = util.percent_of

---@generic T
---@alias wrapped T | fun(): T

---@alias border_style "double" | "single" | "none" | "solid" | "rounded" | "shadow" | string[] | string[][]
---@alias SimplyFile.Show boolean | fun(dir: SimplyFile.Directory): boolean

---@alias SimplyFile.ClipboardOpts { notify?: boolean }
---@alias SimplyFile.PreviewOpts { show?: SimplyFile.Show, max_lines?: wrapped<integer> }
---@alias SimplyFile.Filter table<string, fun(dir: SimplyFile.Directory): boolean>
---@alias SimplyFile.DefaultFilter string | fun(dir: SimplyFile.Directory): boolean
---@alias SimplyFile.Sort table<string, fun(a: SimplyFile.Directory, b: SimplyFile.Directory): boolean>
---@alias SimplyFile.DefaultSort string | fun(a: SimplyFile.Directory, b: SimplyFile.Directory): boolean
---@alias SimplyFile.Opts { keymaps?: table<string, fun(dir: SimplyFile.Directory)>, border?: { main?: border_style, left?: border_style, right?: border_style, up?: border_style }, default_keymaps?: boolean, open_on_enter?: boolean, preview?: SimplyFile.PreviewOpts, clipboard?: SimplyFile.ClipboardOpts, filters?: SimplyFile.Filter, default_filter?: SimplyFile.DefaultFilter, sorts?: SimplyFile.Sort, default_sort?: SimplyFile.DefaultSort }

---@alias WinBuf { win: integer, buf: integer }
---@alias SimplyFile.ExplState { left: WinBuf, main: WinBuf, right: WinBuf, up: WinBuf, dirs: SimplyFile.Directory[], path: string, group_id: integer, search: string, filter: SimplyFile.DefaultFilter, reverse_filter: boolean, sort: SimplyFile.DefaultSort, reverse_sort: boolean }

---setup the simplyfile plugin
---@param opts SimplyFile.Opts?
function M.setup(opts)
  vim.g.simplyfile_config = vim.tbl_deep_extend("keep", opts or {}, {
    default_keymaps = true,
    keymaps = {},
    border = {
      main = "double",
      left = "rounded",
      right = "rounded",
      up = { "╭", "─", "╮", ":", "╯", "─", "╰", ":" },
    },
    open_on_enter = true,
    preview = {
      show = true,
      max_lines = function()
        return vim.o.lines
      end
    },
    clipboard = {
      notify = false,
    },
    filters = {
      start_with_dot = function(dir)
        return vim.startswith(dir.name, ".")
      end,
      file = function(dir)
        return not dir.is_folder
      end,
    },
    default_filter = function() return true end,
    sorts = {
      by_size = function(dirA, dirB)
        return vim.fn.getfsize(dirA.absolute) < vim.fn.getfsize(dirB.absolute)
      end
    },
    default_sort = function(dirA, dirB)
      local a = dirA.name
      local b = dirB.name
      if dirA.is_folder then
        a = "..." .. a
      end
      if dirB.is_folder then
        b = "..." .. b
      end
      return a < b
    end,
  } --[[@as SimplyFile.Opts]])

  vim.g.simplyfile_explorer = nil
  vim.api.nvim_create_user_command("SimplyFileOpen", M.open, {})
  vim.api.nvim_create_user_command("SimplyFileClose", M.close, {})
  if vim.g.simplyfile_config.open_on_enter then
    vim.api.nvim_create_autocmd("VimEnter", {
      callback = function()
        local path = vim.api.nvim_buf_get_name(0)
        if vim.fn.getfsize(path) == 0 then
          M.open(path)
        end
      end
    })
  end
end

---open simplyfile on normalized [path]
---@param path? string folder path or nil for (the dirname of opened buffer name | current working directory)
---for normalize function
---@see vim.fs
function M.open(path)
  local cursor_on = ""
  if vim.g.simplyfile_explorer then
    return
  end
  if type(path) ~= "string" then
    path = vim.api.nvim_buf_get_name(0)
    if path == "" then
      path = vim.fn.getcwd(0)
    elseif vim.fn.getfsize(path) ~= 0 then
      cursor_on = path
      path = vim.fs.dirname(path)
    end
  end

  if not vim.startswith(path, "/") then
    path = vim.fn.getcwd(0) .. "/" .. path
  end
  path = util.trim_dot(vim.fs.normalize(path))
  local height = po(80, vim.o.lines) - 3
  local row = po(5, vim.o.lines) + 3
  local half = po(30, vim.o.columns)
  local col_offset = math.floor(half / 6) - 2

  local up = {
    buf = vim.api.nvim_create_buf(true, true),
  }
  up.win = util.open_win((half * 3) + 4, 1, row - 3, col_offset, up.buf, false)
  util.win_edit_config(up.win, {
    border = vim.g.simplyfile_config.border.up
  })

  local left = {
    buf = vim.api.nvim_create_buf(true, true),
  }
  left.win = util.open_win(half, height, row, col_offset, left.buf, false)
  util.win_edit_config(left.win, {
    border = vim.g.simplyfile_config.border.left
  })

  local main = {
    buf = vim.api.nvim_create_buf(true, true),
  }
  main.win = util.open_win(half, height, row, half + 2 + col_offset,
    main.buf, true)
  util.win_edit_config(main.win,
    { title = " " .. vim.fs.basename(path), title_pos = "center", border = vim.g.simplyfile_config.border.main })
  vim.api.nvim_set_option_value("cursorline", true, { win = main.win })

  local right = {
    buf = vim.api.nvim_create_buf(true, true),
  }
  right.win = util.open_win(half, height, row, (half * 2) + 4 + col_offset,
    right.buf,
    false)
  util.win_edit_config(right.win, { border = vim.g.simplyfile_config.border.right })

  ---@type SimplyFile.ExplState
  vim.g.simplyfile_explorer = {
    left = left,
    main = main,
    right = right,
    up = up,
    dirs = {},
    path = path,
    group_id = vim.api.nvim_create_augroup("SimplyFile", {}),
    search = "",
    filter = vim.g.simplyfile_config.default_filter,
    reverse_filter = false,
    sort = vim.g.simplyfile_config.default_sort,
    reverse_sort = false,
  }
  mapping.reload_dirs()
  local dirs = vim.g.simplyfile_explorer.dirs

  for c, dir in ipairs(dirs) do
    vim.api.nvim_buf_set_lines(main.buf, c - 1, c, false, { "  " .. dir.icon .. " " .. dir.name })
    vim.api.nvim_buf_add_highlight(main.buf, 0, dir.hl, c - 1, 0, 5)
    if dir.absolute == cursor_on then
      vim.api.nvim_win_set_cursor(main.win, { c, 0 })
    end
  end

  local parent_dirs = util.dirs(vim.fs.dirname(path))
  for i, dir in ipairs(parent_dirs) do
    vim.api.nvim_buf_set_lines(left.buf, i - 1, i, false, { "  " .. dir.icon .. " " .. dir.name })
    vim.api.nvim_buf_add_highlight(left.buf, 0, dir.hl, i - 1, 0, 5)
    if dir.absolute == path then
      vim.api.nvim_buf_add_highlight(left.buf, 0, "CursorLine", i - 1, 0, -1)
      vim.api.nvim_win_set_cursor(left.win, { i, 0 })
    end
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = vim.g.simplyfile_explorer.group_id,
    buffer = main.buf,
    callback = function()
      local dir = vim.g.simplyfile_explorer.dirs[vim.api.nvim_win_get_cursor(main.win)[1]]
      if dir then
        util.buf_unlocks(right.buf)
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
          for c, dir in ipairs(cur_dirs) do
            vim.api.nvim_buf_set_lines(right.buf, c - 1, c, false, { "  " .. dir.icon .. " " .. dir.name })
            vim.api.nvim_buf_add_highlight(right.buf, 0, dir.hl, c - 1, 0, 5)
          end
        else
          vim.api.nvim_set_option_value("filetype", dir.filetype, {
            buf = right.buf
          })
          local max_lines = util.callget(vim.g.simplyfile_config.preview.max_lines)
          local i = 0
          for line in io.lines(dir.absolute) do
            if i >= max_lines then
              goto the_end
            end
            vim.api.nvim_buf_set_lines(right.buf, i, i + 1, false, { line })
            i = i + 1
          end
          ::the_end::
        end
        util.buf_unlocks(right.buf)
      else
        util.buf_unlocks(right.buf)
        vim.api.nvim_set_option_value("filetype", "empty", { buf = right.buf })
        vim.api.nvim_buf_set_lines(right.buf, 0, -1, false, { "" })
        util.buf_locks(right.buf)
      end
    end
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.g.simplyfile_explorer.group_id,
    buffer = main.buf,
    callback = function()
      local height = po(80, vim.o.lines) - 3
      local row = po(5, vim.o.lines) + 3
      local col_offset = po(5, vim.o.columns)
      local half = po(30, vim.o.columns)

      util.win_edit_config(up.win, {
        width = (half * 3) + 4,
        height = 1,
        row = row - 3,
        col = col_offset,
      })

      util.win_edit_config(left.win, {
        width = half,
        height = height,
        row = row,
        col = col_offset,
      })

      util.win_edit_config(main.win, {
        width = half,
        height = height,
        row = row,
        col = half + 2 + col_offset,
      })

      util.win_edit_config(right.win, {
        width = half,
        height = height,
        row = row,
        col = (half * 2) + 4 + col_offset,
      })
    end
  })

  if vim.g.simplyfile_config.default_keymaps then
    for lhs, rhs in pairs(mapping.default) do
      vim.api.nvim_buf_set_keymap(main.buf, 'n', lhs, "", {
        callback = function()
          rhs(vim.g.simplyfile_explorer.dirs[vim.api.nvim_win_get_cursor(main.win)[1]])
        end,
      })
    end
  end

  if vim.g.simplyfile_config.keymaps then
    for lhs, rhs in pairs(vim.g.simplyfile_config.keymaps) do
      vim.api.nvim_buf_set_keymap(main.buf, 'n', lhs, "", {
        callback = function()
          rhs(vim.g.simplyfile_explorer.dirs[vim.api.nvim_win_get_cursor(main.win)[1]])
        end,
      })
    end
  end

  local exp = vim.g.simplyfile_explorer
  util.buf_locks(exp.up.buf, exp.main.buf, exp.left.buf, exp.right.buf)
end

function M.close()
  if vim.g.simplyfile_explorer then
    vim.api.nvim_del_augroup_by_id(vim.g.simplyfile_explorer.group_id)
    vim.api.nvim_win_close(vim.g.simplyfile_explorer.up.win, true)
    vim.api.nvim_buf_delete(vim.g.simplyfile_explorer.up.buf, { force = true })
    vim.api.nvim_win_close(vim.g.simplyfile_explorer.left.win, true)
    vim.api.nvim_buf_delete(vim.g.simplyfile_explorer.left.buf, { force = true })
    vim.api.nvim_win_close(vim.g.simplyfile_explorer.main.win, true)
    vim.api.nvim_buf_delete(vim.g.simplyfile_explorer.main.buf, { force = true })
    vim.api.nvim_win_close(vim.g.simplyfile_explorer.right.win, true)
    vim.api.nvim_buf_delete(vim.g.simplyfile_explorer.right.buf, { force = true })
    vim.g.simplyfile_explorer = nil
  end
end

return M
