local M = {}
local util = require("simplyfile.util")
local mapping = require("simplyfile.mapping")
local comp = require("simplyfile.components")
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
---@alias SimplyFile.IconsOverride { filetype?: table, filename?: table }
---@alias SimplyFile.Opts { keymaps?: table<string, fun(dir: SimplyFile.Directory)>, border?: { main?: border_style, left?: border_style, right?: border_style, up?: border_style }, win_opt?: { main?: table, left?: table, right?: table, up?: table }, default_keymaps?: boolean, open_on_enter?: boolean, preview?: SimplyFile.PreviewOpts, clipboard?: SimplyFile.ClipboardOpts, filters?: SimplyFile.Filter, default_filter?: SimplyFile.DefaultFilter, sorts?: SimplyFile.Sort, default_sort?: SimplyFile.DefaultSort, icons?: SimplyFile.IconsOverride }

---@alias WinBuf { win: integer, buf: integer }
---@alias SimplyFile.UpBarOpts { events?: table<string, vim.api.keyset.create_autocmd>, callback?: fun(expl: SimplyFile.ExplState): table, table }
---@alias SimplyFile.ExplState { left: WinBuf, main: WinBuf, right: WinBuf, up: WinBuf, dirs: SimplyFile.Directory[], path: string, group_id: integer, search: string, filter: SimplyFile.DefaultFilter, reverse_filter: boolean, sort: SimplyFile.DefaultSort, reverse_sort: boolean, up_bar?: SimplyFile.UpBarOpts }

---setup the simplyfile plugin
---@param opts SimplyFile.Opts?
function M.setup(opts)
  vim.g.simplyfile_config = vim.tbl_deep_extend("keep", opts or {}, {
    default_keymaps = true,
    icons = {
      filetype = {},
      filename = {},
    },
    keymaps = {},
    border = {
      main = "double",
      left = "rounded",
      right = "rounded",
      up = { "╭", "─", "╮", ":", "╯", "─", "╰", ":" },
    },
    win_opt = {
      up = {},
      left = {},
      main = {},
      right = {},
    },
    up_bar = {
      events = {
        User = {
          pattern = "SimplyFileStateChange"
        },
        DirChanged = {
          pattern = "global"
        },
      },
      -- event = "CursorMoved",
      ---@param expl SimplyFile.ExplState
      ---@return table, table
      callback = function(expl)
        local left = { { " ", "NormalFloat" } }
        local del = { " | ", "FloatBorder" }
        local function insert(text, comps)
          if not comps then return end
          for _, c in ipairs(comps) do
            table.insert(text, c)
          end
        end
        local filter = comp.filter(expl)
        insert(left, filter)

        local sort = comp.sort(expl)
        if filter and sort then
          insert(left, { del })
        end
        insert(left, sort)

        local search = comp.search(expl)
        if (filter and search) or (sort and search) then
          insert(left, { del })
        end
        insert(left, search)

        local right = {}
        insert(right, comp.cwd())
        table.insert(right, { " ", "NormalFloat" })

        return left, right
      end
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
      filesize = function(dirA, dirB)
        local a = dirA.is_folder and -5 or vim.fn.getfsize(dirA.absolute)
        local b = dirB.is_folder and -5 or vim.fn.getfsize(dirB.absolute)
        return a < b
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

  local up_bar = vim.g.simplyfile_config.up_bar
  local opts = {
    callback = function()
      ---@type SimplyFile.ExplState
      local expl = vim.g.simplyfile_explorer
      if expl then
        local ns = vim.api.nvim_create_namespace("SimplyFile")
        vim.api.nvim_buf_del_extmark(expl.up.buf, ns, 1)
        vim.api.nvim_buf_del_extmark(expl.up.buf, ns, 2)
        local text_left, text_right = up_bar.callback(expl)
        vim.api.nvim_buf_set_extmark(expl.up.buf, ns, 0, 0, {
          id = 1,
          end_row = 0,
          end_col = 0,
          virt_text = text_left or {},
          virt_text_pos = "inline",
          right_gravity = false,
        })
        vim.api.nvim_buf_set_extmark(expl.up.buf, ns, 0, 0, {
          id = 2,
          end_row = 0,
          end_col = 0,
          virt_text = text_right or {},
          virt_text_pos = "right_align",
          right_gravity = false,
        })
      end
    end,
  }
  for event, o in pairs(up_bar.events) do
    vim.api.nvim_create_autocmd(event, vim.tbl_extend("force", o, opts))
  end

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
  local row = po(5, vim.o.lines) + 4
  local half = po(30, vim.o.columns)
  local col_offset = math.floor(half / 6) - 2

  local up = {
    buf = vim.api.nvim_create_buf(false, true),
  }
  local up_none_border = vim.g.simplyfile_config.border.up == "none"
  up.win = util.open_win((half * 3) + 4 + (up_none_border and 2 or 0), 1, row - 3 + (up_none_border and 2 or 0),
    col_offset, up.buf, false)
  util.win_edit_config(up.win, {
    border = vim.g.simplyfile_config.border.up
  })
  for option, value in pairs(vim.g.simplyfile_config.win_opt.up) do
    vim.api.nvim_set_option_value(option, value, { win = up.win })
  end

  local left = {
    buf = vim.api.nvim_create_buf(false, true),
  }
  local left_none_border = vim.g.simplyfile_config.border.left == "none"
  left.win = util.open_win(half + (left_none_border and 2 or 0), height + (left_none_border and 2 or 0), row, col_offset,
    left.buf,
    false)
  util.win_edit_config(left.win, {
    border = vim.g.simplyfile_config.border.left,
  })
  if not left_none_border then
    util.win_edit_config(left.win, {
      title = " " .. vim.fs.basename(vim.fs.dirname(path)),
      title_pos = "right",
    })
  end
  for option, value in pairs(vim.g.simplyfile_config.win_opt.left) do
    vim.api.nvim_set_option_value(option, value, { win = left.win })
  end

  local main_none_border = vim.g.simplyfile_config.border.main == "none"
  local main = {
    buf = vim.api.nvim_create_buf(false, true),
  }
  main.win = util.open_win(half + (main_none_border and 2 or 0), height + (main_none_border and 2 or 0), row,
    half + 2 + col_offset,
    main.buf, true)
  util.win_edit_config(main.win,
    { title = " " .. vim.fs.basename(path), title_pos = "center", border = vim.g.simplyfile_config.border.main })
  vim.api.nvim_set_option_value("cursorline", true, { win = main.win })
  for option, value in pairs(vim.g.simplyfile_config.win_opt.main) do
    vim.api.nvim_set_option_value(option, value, { win = main.win })
  end

  local right = {
    buf = vim.api.nvim_create_buf(false, true),
  }
  local right_none_border = vim.g.simplyfile_config.border.right == "none"

  right.win = util.open_win(half + (right_none_border and 2 or 0), height + (right_none_border and 2 or 0), row,
    (half * 2) + 4 + col_offset,
    right.buf,
    false)
  util.win_edit_config(right.win, { border = vim.g.simplyfile_config.border.right })
  for option, value in pairs(vim.g.simplyfile_config.win_opt.right) do
    vim.api.nvim_set_option_value(option, value, { win = right.win })
  end

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
        if vim.g.simplyfile_config.border.right ~= "none" then
          util.win_edit_config(right.win, { title = dir.icon .. " " .. dir.name, title_pos = "left" })
        end
        util.buf_unlocks(right.buf)
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
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = main.buf,
    callback = function()
      M.close()
    end
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.g.simplyfile_explorer.group_id,
    buffer = main.buf,
    callback = function()
      local height = po(80, vim.o.lines) - 3
      local row = po(5, vim.o.lines) + 4
      local col_offset = po(5, vim.o.columns) - 2
      local half = po(30, vim.o.columns)

      local up_none_border = vim.g.simplyfile_config.border.up == "none"
      util.win_edit_config(up.win, {
        width = (half * 3) + 4 + (up_none_border and 2 or 0),
        height = 1,
        row = row - 3 + (up_none_border and 2 or 0),
        col = col_offset,
      })

      local left_none_border = vim.g.simplyfile_config.border.left == "none"
      util.win_edit_config(left.win, {
        width = half + (left_none_border and 2 or 0),
        height = height + (left_none_border and 2 or 0),
        row = row,
        col = col_offset,
      })

      local main_none_border = vim.g.simplyfile_config.border.main == "none"
      util.win_edit_config(main.win, {
        width = half + (main_none_border and 2 or 0),
        height = height + (main_none_border and 2 or 0),
        row = row,
        col = half + 2 + col_offset,
      })

      local right_none_border = vim.g.simplyfile_config.border.right == "none"
      util.win_edit_config(right.win, {
        width = half + (right_none_border and 2 or 0),
        height = height + (right_none_border and 2 or 0),
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
    pcall(vim.api.nvim_win_close, vim.g.simplyfile_explorer.up.win, true)
    pcall(vim.api.nvim_buf_delete, vim.g.simplyfile_explorer.up.buf, { force = true })
    pcall(vim.api.nvim_win_close, vim.g.simplyfile_explorer.left.win, true)
    pcall(vim.api.nvim_buf_delete, vim.g.simplyfile_explorer.left.buf, { force = true })
    pcall(vim.api.nvim_win_close, vim.g.simplyfile_explorer.main.win, true)
    pcall(vim.api.nvim_buf_delete, vim.g.simplyfile_explorer.main.buf, { force = true })
    pcall(vim.api.nvim_win_close, vim.g.simplyfile_explorer.right.win, true)
    pcall(vim.api.nvim_buf_delete, vim.g.simplyfile_explorer.right.buf, { force = true })
    vim.g.simplyfile_explorer = nil
  end
end

return M
