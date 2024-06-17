local M = {}
local image = require("image")
local util = require("simplyfile.util")
local clip = require("simplyfile.clipboard")

M.images = {}

---render grid mode view on {main}
---@param ui { buf: integer, win: integer }
---@param dirs SimplyFile.Directory[]
---@param reload_image? boolean
---@param cursor_on? SimplyFile.Directory
---@param show_selected? boolean
function M.render(ui, dirs, reload_image, cursor_on, show_selected)
  if reload_image == nil then
    reload_image = true
  end
  if show_selected == nil then
    show_selected = true
  end
  M.images[ui.win] = M.images[ui.win] or {}
  vim.wo[ui.win].cursorline = false

  local get_icon = vim.g.simplyfile_config.grid_mode.get_icon
  local sel = vim.g.simplyfile_explorer.grid_pos
  local mconf = vim.api.nvim_win_get_config(ui.win)
  local size = vim.g.simplyfile_config.grid_mode.size
  local gap = vim.g.simplyfile_config.grid_mode.gap
  local ipad = vim.g.simplyfile_config.grid_mode.icon_padding * 2
  local padding = vim.g.simplyfile_config.grid_mode.padding
  local fallback = vim.g.simplyfile_config.grid_mode.fallback
  local xmax = math.floor((mconf.width - (padding * 4) + (gap * 2)) / ((size * 2) + (gap * 2) + (ipad * 2)))
  local ymax = math.floor((mconf.height - (padding * 2)) / (size + 1 + gap + ipad))
  local dcol = 1
  local drow = 1
  local col = 1
  local row = 1
  local row_off = 0
  local col_off = 0
  local index_start = vim.g.simplyfile_explorer.grid_page

  local ns = vim.api.nvim_create_namespace("SimplyFileGridMode")
  vim.api.nvim_buf_clear_namespace(ui.buf, ns, 0, -1)
  util.buf_unlocks(ui.buf)
  for i = 1, mconf.height * 2 do
    vim.api.nvim_buf_set_lines(ui.buf, i - 1, i, false, { ((" "):rep(mconf.width * 3)) })
  end

  local pos = ((sel[1] - 1) * xmax) + sel[2]
  if pos > #dirs then
    sel[2] = #dirs % xmax
    if sel[2] == 0 then
      sel[2] = xmax
    end
  end

  if cursor_on then
    local pos = 0
    for i, dir in ipairs(dirs) do
      if dir.absolute == cursor_on.absolute then
        pos = i
        break
      end
    end
    if pos == 0 then
      sel[1] = 1
      sel[2] = 1
    else
      sel[1] = math.ceil(pos / xmax)
      sel[2] = pos % xmax
      if sel[2] == 0 then
        sel[2] = xmax
      end
    end
    cursor_on = nil
  end
  local new_start = math.ceil((((sel[1] - 1) * xmax) + sel[2]) / (xmax * ymax))
  if new_start ~= index_start then
    reload_image = true
    index_start = new_start
  end

  if reload_image then
    for _, img in ipairs(M.images[ui.win]) do
      vim.schedule(function()
        img:clear()
      end)
    end
  end

  local start = ((index_start - 1) * xmax * ymax) + 1
  for i, value in ipairs(dirs) do
    if i < start then
      col = col + 1
      if col > xmax then
        col = 1
        row = row + 1
      end
      goto next
    end

    local x = (padding * 2) + col_off
    local y = padding + row_off
    local icon = get_icon(value)
    local config = {
      x = mconf.col + 1 + x + ipad,
      y = mconf.row + 1 + y + (ipad / 2),
      width = size * 2,
      height = size,
    }
    local err = false

    if type(icon) == "string" then
      local img = image.from_file(icon, config)
      if img then
        table.insert(M.images[ui.win], img)
      else
        err = true
      end
      if reload_image and not err and img then
        vim.schedule(function()
          img:render()
        end)
      end
    elseif type(icon) == "table" then
      local hl = icon[2] or "Normal"
      icon = icon[1]
      local posoff = math.floor((size - #icon) / 2)
      for i = 1, size do
        local col_start = x + ipad
        local col_end = col_start + (size * 2)
        local text = util.text_center(icon[i - posoff] or "", col_end - col_start)
        local ypos = y + i + (ipad / 2) - 1
        vim.api.nvim_buf_set_text(ui.buf, ypos, col_start, ypos, col_end, { text })
        vim.api.nvim_buf_add_highlight(ui.buf, ns, hl --[[@as string]], ypos, col_start, col_end)
      end
    end
    if err then
      if reload_image and type(fallback) == "string" then
        local img = image.from_file(fallback, config)
        if img then
          table.insert(M.images[ui.win], img)
          vim.schedule(function()
            img:render()
          end)
        end
      elseif type(fallback) == "table" then
        local hl = fallback[2] or "Normal"
        fallback = fallback[1]
        local posoff = math.floor((size - #fallback) / 2)
        for i = 1, size do
          local col_start = x + ipad
          local col_end = col_start + (size * 2)
          local text = util.text_center(fallback[i - posoff] or "", col_end - col_start)
          local ypos = y + i + (ipad / 2) - 1
          vim.api.nvim_buf_set_text(ui.buf, ypos, col_start, ypos, col_end, { text })
          vim.api.nvim_buf_add_highlight(ui.buf, ns, hl --[[@as string]], ypos, col_start, col_end)
        end
      end
    end

    local col_end = x + (size * 2 + (ipad * 2))
    vim.api.nvim_buf_set_text(ui.buf, y + size + ipad, x, y + size + ipad, col_end, {
      util.text_center(value.name, col_end - x)
    })

    if show_selected and row == sel[1] and col == sel[2] then
      for i = y, y + size + ipad do
        vim.api.nvim_buf_add_highlight(ui.buf, ns, "CursorLine", i, x, col_end)
      end
    end

    local method = clip.get_method(value)
    if method then
      if method == 'copy' then
        vim.api.nvim_buf_add_highlight(ui.buf, ns, "SimplyFileCopyMark", y + size + ipad, x, col_end)
      elseif method == 'cut' then
        vim.api.nvim_buf_add_highlight(ui.buf, ns, "SimplyFileCutMark", y + size + ipad, x, col_end)
      end
    end

    dcol = dcol + 1
    col_off = col_off + (gap * 2) + (size * 2 + (ipad * 2))
    if dcol > xmax then
      if drow == ymax then
        break
      end
      dcol = 1
      col_off = 0
      drow = drow + 1
      row_off = row_off + gap + 1 + size + ipad
    end
    col = col + 1
    if col > xmax then
      col = 1
      row = row + 1
    end
    ::next::
  end
  if vim.g.simplyfile_explorer.main.win == ui.win then
    util.override_state {
      grid_pos = sel,
      grid_cols = xmax,
      grid_page = index_start,
    }
  end
  util.buf_locks(ui.buf)
end

return M
