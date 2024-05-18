local M = {}
local util = require("simplyfile.util")
local mapping = require("simplyfile.mapping")
local po = util.percent_of

---@alias border_style "double" | "single" | "none" | "solid" | "rounded" | "shadow" | string[] | string[][]
---@alias SimplyFile.Opts { keymaps?: table<string, fun(dir: SimplyFile.Directory)>, border?: { main: border_style, left: border_style, right: border_style }, default_keymaps?: boolean }
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
    }
  } --[[@as SimplyFile.Opts]])
  vim.g.simplyfile_explorer = nil
  vim.api.nvim_create_user_command("SimplyFileOpen", M.open, {})
  vim.api.nvim_create_user_command("SimplyFileClose", M.close, {})
end

---open simplyfile on normalized [path]
---@param path? string folder path or nil for (the dirname of opened buffer name | current working directory)
---for normalize function
---@see vim.fs
function M.open(path)
  if vim.g.simplyfile_explorer then
    return
  end
  if type(path) ~= "string" then
    path = vim.api.nvim_buf_get_name(0)
    if path == "" then
      path = vim.fn.getcwd(0)
    else
      path = vim.fs.dirname(path)
    end
  end

  if not vim.startswith(path, "/") then
    path = vim.fn.getcwd(0) .. "/" .. path
  end
  path = util.trim_dot(vim.fs.normalize(path))
  local dirs = util.dirs(path)
  local height = po(80, vim.o.lines)
  local row = po(5, vim.o.lines)
  local col_offset = po(2.5, vim.o.columns)

  local left = {
    buf = vim.api.nvim_create_buf(true, true),
  }
  left.win = util.open_win(po(30, vim.o.columns), height, row, 0 + col_offset, left.buf, false)
  util.win_edit_config(left.win, {
    border = vim.g.simplyfile_config.border.left
  })

  local main = {
    buf = vim.api.nvim_create_buf(true, true),
  }
  main.win = util.open_win(po(30, vim.o.columns), height, row, po(30, vim.o.columns) + 3 + col_offset,
    main.buf, true)
  util.win_edit_config(main.win, { title = path, title_pos = "center", border = vim.g.simplyfile_config.border.main })
  vim.api.nvim_set_option_value("cursorline", true, { win = main.win })

  local right = {
    buf = vim.api.nvim_create_buf(true, true),
  }
  right.win = util.open_win(po(30, vim.o.columns), height, row, po(60, vim.o.columns) + 6 + col_offset,
    right.buf,
    false)
  util.win_edit_config(right.win, { border = vim.g.simplyfile_config.border.right })

  vim.g.simplyfile_explorer = {
    left = left,
    main = main,
    right = right,
    dirs = dirs,
    path = path,
  }

  for c, dir in ipairs(dirs) do
    vim.api.nvim_buf_set_lines(main.buf, c - 1, c, false, { "  " .. dir.icon .. " " .. dir.name })
    vim.api.nvim_buf_add_highlight(main.buf, 0, dir.hl, c - 1, 0, 5)
  end

  local parent_dirs = util.dirs(vim.fs.dirname(path))
  for i, dir in ipairs(parent_dirs) do
    vim.api.nvim_buf_set_lines(left.buf, i - 1, i, false, { "  " .. dir.icon .. " " .. dir.name })
    vim.api.nvim_buf_add_highlight(left.buf, 0, dir.hl, i - 1, 0, 5)
    if dir.absolute == path then
      vim.api.nvim_buf_add_highlight(left.buf, 0, "CursorLine", i - 1, 0, -1)
    end
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = main.buf,
    callback = function()
      local dir = vim.g.simplyfile_explorer.dirs[vim.api.nvim_win_get_cursor(main.win)[1]]
      if dir then
        if not util.file_exists(dir.absolute) then return end
        vim.api.nvim_buf_set_lines(right.buf, 0, -1, false, { "" })
        if dir.is_folder then
          vim.api.nvim_set_option_value("filetype", "list_dir", {
            buf = right.buf
          })
          local cur_dirs = util.dirs(dir.absolute)
          for i, dir in ipairs(cur_dirs) do
            vim.api.nvim_buf_set_lines(right.buf, i - 1, i, false, { "  " .. dir.icon .. " " .. dir.name })
            vim.api.nvim_buf_add_highlight(right.buf, 0, dir.hl, i - 1, 0, 5)
          end
        else
          vim.api.nvim_set_option_value("filetype", dir.filetype, {
            buf = right.buf
          })
          local i = 0
          for line in io.lines(dir.absolute) do
            if i > vim.o.lines then
              goto the_end
            end
            vim.api.nvim_buf_set_lines(right.buf, i, i + 1, false, { line })
            i = i + 1
          end
          ::the_end::
        end
      end
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
end

function M.close()
  if vim.g.simplyfile_explorer then
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
