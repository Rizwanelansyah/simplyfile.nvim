local M = {}
local util = require("simplyfile.util")
local mapping = require("simplyfile.mapping")
local comp = require("simplyfile.components")

---@generic T
---@alias wrapped T | fun(): T

---@alias border_style "double" | "single" | "none" | "solid" | "rounded" | "shadow" | string[] | string[][]
---@alias SimplyFile.Show boolean | fun(dir: SimplyFile.Directory): boolean

---@alias SimplyFile.GridModeOpts { fallback_image: string, icon_padding?: integer, gap?: integer, size?: integer, padding?: integer, icon_path: (fun(dir: SimplyFile.Directory): string), enabled?: boolean }
---@alias SimplyFile.ClipboardOpts { notify?: boolean }
---@alias SimplyFile.PreviewOpts { show?: SimplyFile.Show, max_lines?: wrapped<integer>, image?: boolean, is_image?: fun(dir: SimplyFile.Directory): boolean }
---@alias SimplyFile.Filter table<string, fun(dir: SimplyFile.Directory): boolean>
---@alias SimplyFile.DefaultFilter string | fun(dir: SimplyFile.Directory): boolean
---@alias SimplyFile.Sort table<string, fun(a: SimplyFile.Directory, b: SimplyFile.Directory): boolean>
---@alias SimplyFile.DefaultSort string | fun(a: SimplyFile.Directory, b: SimplyFile.Directory): boolean
---@alias SimplyFile.Margin { left: wrapped<integer>, right: wrapped<integer>, down: wrapped<integer>, up: wrapped<integer>}
---@alias SimplyFile.Opts { grid_mode?: SimplyFile.GridModeOpts, margin?:SimplyFile.Margin, gap?: { v: wrapped<integer>, h: wrapped<integer> }, keymaps?: table<string, fun(dir?: SimplyFile.Directory)>, border?: { main?: border_style, left?: border_style, right?: border_style, up?: border_style }, win_opt?: { main?: table, left?: table, right?: table, up?: table }, default_keymaps?: boolean, open_on_enter?: boolean, preview?: SimplyFile.PreviewOpts, clipboard?: SimplyFile.ClipboardOpts, filters?: SimplyFile.Filter, default_filter?: SimplyFile.DefaultFilter, sorts?: SimplyFile.Sort, default_sort?: SimplyFile.DefaultSort }

---@alias WinBuf { win: integer, buf: integer }
---@alias SimplyFile.UpBarOpts { events?: table<string, vim.api.keyset.create_autocmd>, callback?: fun(expl: SimplyFile.ExplState): table, table }
---@alias SimplyFile.ExplState { grid_pos: integer[], left: WinBuf, main: WinBuf, right: WinBuf, up: WinBuf, dirs: SimplyFile.Directory[], path: string, group_id: integer, search: string, filter: SimplyFile.DefaultFilter, reverse_filter: boolean, sort: SimplyFile.DefaultSort, reverse_sort: boolean, up_bar?: SimplyFile.UpBarOpts }

---setup the simplyfile plugin
---@param opts SimplyFile.Opts?
function M.setup(opts)
  vim.g.simplyfile_config = vim.tbl_deep_extend("keep", opts or {}, {
    default_keymaps = true,
    keymaps = {},
    gap = { h = 0, v = 0 },
    grid_mode = {
      enabled = false,
      gap = 1,
      size = 4,
      padding = 1,
      icon_padding = 1,
    },
    margin = {
      left = 5,
      right = 5,
      up = 1,
      down = 1,
    },
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
          pattern = { "SimplyFileStateChange", "SimplyFileClipboardChange" }
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
        insert(right, comp.clipboard())
        table.insert(right, { " ", "NormalFloat" })
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
      end,
      image = false,
      is_image = function(dir)
        return util.matches(dir.name, { "%.png$", "%.jpe?g$", "%.gif$", "%.webp$", "%.avif$", "%.svg$" })
      end,
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
  local set_hl = function()
    vim.api.nvim_set_hl(0, "SimplyFileCutMark", { fg = "#CC5555" })
    vim.api.nvim_set_hl(0, "SimplyFileCopyMark", { fg = "#4095E4" })
    vim.api.nvim_set_hl(0, "SimplyFileCutMarkGridMode", { bg = "#CC5555", fg = "black" })
    vim.api.nvim_set_hl(0, "SimplyFileCopyMarkGridMode", { bg = "#4095E4", fg = "black" })
  end
  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = set_hl,
  })
  set_hl()

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
        if vim.fn.isdirectory(path) == 1 then
          M.open(path)
        end
      end
    })
  end

  if vim.g.simplyfile_config.preview.image then
    local ok, _ = pcall(require, "image")
    if not ok then
      vim.notify(
        "[preview image disabled]: image.nvim plugin not installed if you want previewing image please install 3rd/image.nvim first",
        vim.log.levels.ERROR)
      M.reconfig { preview = { image = false } }
    end
  end
end

---override config option and reload the ui if opened
---@param opts SimplyFile.Opts
function M.reconfig(opts)
  vim.g.simplyfile_config = vim.tbl_deep_extend("force", vim.g.simplyfile_config, opts)
  M.reload_ui()
end

---get directory under cursor
---@return SimplyFile.Directory?
function M.get_dir()
  if not vim.g.simplyfile_explorer then return end
  local main = vim.g.simplyfile_explorer.main
  return vim.g.simplyfile_explorer.dirs[vim.api.nvim_win_get_cursor(main.win)[1]]
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
    end
  end

  if vim.fn.isdirectory(path) == 0 then
    cursor_on = path
    path = vim.fs.dirname(path)
  end

  if not vim.startswith(path, "/") then
    path = vim.fn.getcwd(0) .. "/" .. path
  end
  path = util.trim_dot(vim.fs.normalize(path))
  local vgap = util.callget(vim.g.simplyfile_config.gap.v)
  local hgap = util.callget(vim.g.simplyfile_config.gap.h)
  local margin = {}
  margin.up = util.callget(vim.g.simplyfile_config.margin.up)
  margin.down = util.callget(vim.g.simplyfile_config.margin.down) + 1
  margin.left = util.callget(vim.g.simplyfile_config.margin.left)
  margin.right = util.callget(vim.g.simplyfile_config.margin.right)
  local lines = vim.o.lines - margin.up - margin.down
  local ori_columns = vim.o.columns - margin.left - margin.right - 2
  local part = math.floor(ori_columns / 3)
  local mainw = part
  local columns = part * 3
  while columns ~= ori_columns do
    mainw = mainw + 1
    columns = columns + 1
  end

  local up = {
    buf = vim.api.nvim_create_buf(false, true),
  }
  local up_none_border = vim.g.simplyfile_config.border.up == "none"
  up.win = util.open_win(
    ori_columns + (up_none_border and 2 or 0),
    1,
    margin.up + (up_none_border and 1 or 0),
    margin.left,
    up.buf, false)
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
  left.win = util.open_win(
    part - (left_none_border and 0 or 2) - hgap,
    lines - 3 - vgap - (left_none_border and 0 or 2),
    margin.up + 3 + vgap,
    margin.left,
    left.buf, false)
  util.win_edit_config(left.win, {
    border = vim.g.simplyfile_config.border.left,
  })
  if not left_none_border then
    util.win_edit_config(left.win, {
      title = " " .. vim.fs.basename(vim.fs.dirname(path)),
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
  main.win = util.open_win(
    mainw + (main_none_border and 2 or 0),
    lines - 3 - vgap - (main_none_border and 0 or 2),
    margin.up + 3 + vgap,
    margin.left + hgap + part - hgap,
    main.buf, true)
  util.win_edit_config(main.win,
    { title = " " .. vim.fs.basename(path), title_pos = "center", border = vim.g.simplyfile_config.border.main })
  vim.api.nvim_set_option_value("cursorline", true, { win = main.win })
  for option, value in pairs(vim.g.simplyfile_config.win_opt.main) do
    vim.api.nvim_set_option_value(option, value, { win = main.win })
  end

  local right = {
    buf = vim.api.nvim_create_buf(false, true),
  }
  local right_none_border = vim.g.simplyfile_config.border.right == "none"

  right.win = util.open_win(
    part - (right_none_border and 0 or 2) - hgap,
    lines - 3 - vgap - (right_none_border and 0 or 2),
    margin.up + 3 + vgap,
    margin.left + (hgap * 2) + part + mainw + 2 - hgap,
    right.buf, false)
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
    grid_pos = {1, 1},
    grid_selected = nil,
  }

  ---@diagnostic disable-next-line: missing-fields
  mapping.refresh({ absolute = cursor_on })

  if vim.g.simplyfile_config.grid_mode.enabled then
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = vim.g.simplyfile_explorer.group_id,
      buffer = main.buf,
      callback = function()
        vim.api.nvim_win_set_cursor(main.win, { 1, 0 })
      end
    })
  else
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = vim.g.simplyfile_explorer.group_id,
      buffer = main.buf,
      callback = function()
        local dir = M.get_dir()
        M.preview(dir)
      end
    })

    vim.api.nvim_create_autocmd("User", {
      pattern = "SimplyFileClipboardChange",
      callback = function()
        if not vim.g.simplyfile_explorer then return end
        mapping.redraw(M.get_dir() or { absolute = "" })
      end
    })
  end

  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = main.buf,
    callback = function()
      M.close()
    end
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.g.simplyfile_explorer.group_id,
    buffer = main.buf,
    callback = M.reload_ui,
  })

  if vim.g.simplyfile_config.default_keymaps then
    for lhs, rhs in pairs(mapping.get_default()) do
      vim.api.nvim_buf_set_keymap(main.buf, 'n', lhs, "", {
        callback = function()
          rhs(M.get_dir())
        end,
      })
    end
  end

  if vim.g.simplyfile_config.keymaps then
    for lhs, rhs in pairs(vim.g.simplyfile_config.keymaps) do
      vim.api.nvim_buf_set_keymap(main.buf, 'n', lhs, '', {
        callback = function()
          rhs(M.get_dir())
        end,
      })
    end
  end

  local exp = vim.g.simplyfile_explorer
  util.buf_locks(exp.up.buf, exp.main.buf, exp.left.buf, exp.right.buf)
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
        for c, dir in ipairs(cur_dirs) do
          vim.api.nvim_buf_set_lines(right.buf, c - 1, c, false, { "  " .. dir.icon .. " " .. dir.name })
          vim.api.nvim_buf_add_highlight(right.buf, 0, dir.hl, c - 1, 0, 5)
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

---reload ui if explorer opened
function M.reload_ui()
  if not vim.g.simplyfile_explorer then return end
  local up = vim.g.simplyfile_explorer.up
  local left = vim.g.simplyfile_explorer.left
  local right = vim.g.simplyfile_explorer.right
  local main = vim.g.simplyfile_explorer.main

  local vgap = util.callget(vim.g.simplyfile_config.gap.v)
  local hgap = util.callget(vim.g.simplyfile_config.gap.h)
  local margin = {}
  margin.up = util.callget(vim.g.simplyfile_config.margin.up)
  margin.down = util.callget(vim.g.simplyfile_config.margin.down) + 1
  margin.left = util.callget(vim.g.simplyfile_config.margin.left)
  margin.right = util.callget(vim.g.simplyfile_config.margin.right)
  local lines = vim.o.lines - margin.up - margin.down
  local ori_columns = vim.o.columns - margin.left - margin.right - 2
  local part = math.floor(ori_columns / 3)
  local mainw = part
  local columns = part * 3
  while columns ~= ori_columns do
    mainw = mainw + 1
    columns = columns + 1
  end

  local up_none_border = vim.g.simplyfile_config.border.up == "none"
  util.win_edit_config(up.win, {
    width  = ori_columns + (up_none_border and 2 or 0),
    height = 1,
    row    = margin.up + (up_none_border and 1 or 0),
    col    = margin.left,
  })

  local left_none_border = vim.g.simplyfile_config.border.left == "none"
  util.win_edit_config(left.win, {
    width  = part - (left_none_border and 0 or 2) - hgap,
    height = lines - 3 - vgap - (left_none_border and 0 or 2),
    row    = margin.up + 3 + vgap,
    col    = margin.left,
  })

  local main_none_border = vim.g.simplyfile_config.border.main == "none"
  util.win_edit_config(main.win, {
    width  = mainw + (main_none_border and 2 or 0),
    height = lines - 3 - vgap - (main_none_border and 0 or 2),
    row    = margin.up + 3 + vgap,
    col    = margin.left + hgap + part - hgap,
  })

  local right_none_border = vim.g.simplyfile_config.border.right == "none"
  util.win_edit_config(right.win, {
    width  = part - (right_none_border and 0 or 2) - hgap,
    height = lines - 3 - vgap - (right_none_border and 0 or 2),
    row    = margin.up + 3 + vgap,
    col    = margin.left + (hgap * 2) + part + mainw + 2 - hgap,
  })

  if vim.g.simplyfile_config.preview.image then
    if vim.api.nvim_get_option_value("filetype", { buf = right.buf }) == "image_preview" then
      vim.schedule(function()
        local images = require("image").get_images { window = right.win }
        for _, img in ipairs(images) do
          local new_img = require("image").from_file(img.path, { window = right.win, buffer = right.buf })
          img:clear()
          if new_img then
            new_img:render()
          end
        end
      end)
    end
  end
  if vim.g.simplyfile_config.grid_mode.enabled then
    mapping.reload_main({ absolute = "" })
  end
end

function M.close()
  local timer = vim.uv.new_timer()
  timer:start(0, 0, vim.schedule_wrap(function()
    for _, img in ipairs(require("image").get_images()) do
      if img.namespace == "simplyfile_image" then
        img:clear()
      end
    end
  end))
  if vim.g.simplyfile_explorer then
    local draw_image = vim.g.simplyfile_config.preview.preview_image
    if draw_image then
      if vim.api.nvim_get_option_value("filetype", { buf = vim.g.simplyfile_explorer.right.buf }) == "image_preview" then
        local images = require("image").get_images { window = vim.g.simplyfile_explorer.right.win }
        for _, img in ipairs(images) do
          img:clear()
        end
      end
    end

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
