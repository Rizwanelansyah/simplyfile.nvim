local M = {}
local image = require("image")
local util = require("simplyfile.util")

---render grid mode view on {main}
---@param main { buf: integer, win: integer }
---@param dirs SimplyFile.Directory[]
---@param reload_image? boolean
---@param cursor_on? SimplyFile.Directory
function M.render(main, dirs, reload_image, cursor_on)
  if reload_image == nil then
    reload_image = true
  end
  vim.wo[main.win].cursorline = false

  if reload_image then
    for _, img in ipairs(image.get_images()) do
      if img.namespace == "simplyfile_image" then
        img:clear()
      end
    end
  end

  local icon_path = vim.g.simplyfile_config.grid_mode.icon_path
  if not icon_path then
    vim.notify("Error: field `icon_path` on `grid_mode` option is not setted")
  end
  local sel = vim.g.simplyfile_explorer.grid_pos
  local mconf = vim.api.nvim_win_get_config(main.win)
  local size = vim.g.simplyfile_config.grid_mode.size
  local gap = vim.g.simplyfile_config.grid_mode.gap
  local ipad = vim.g.simplyfile_config.grid_mode.icon_padding * 2
  local padding = vim.g.simplyfile_config.grid_mode.padding
  local fallback = vim.g.simplyfile_config.grid_mode.fallback_image
  local xmax = math.floor((mconf.width - (padding * 4) + (gap * 2)) / ((size * 2) + (gap * 2) + (ipad * 2)))
  local ymax = math.floor((mconf.height - (padding * 2)) / (size + 1 + gap + ipad))
  local col = 1
  local row = 1
  local row_off = 0
  local col_off = 0

  local ns = vim.api.nvim_create_namespace("SimplyFileGridMode")
  vim.api.nvim_buf_clear_namespace(main.buf, ns, 0, -1)
  util.buf_unlocks(main.buf)
  for i = 1, mconf.height * 2 do
    vim.api.nvim_buf_set_lines(main.buf, i - 1, i, false, { ((" "):rep(mconf.width)) })
  end

  if cursor_on then
    local filtered = vim.tbl_filter(function(dir) return dir.absolute == cursor_on.absolute end, dirs)
    if #filtered == 0 then
      cursor_on = nil
      sel[1] = 1
      sel[2] = 1
    end
  end
  for _, value in ipairs(dirs) do
    local x = (padding * 2) + col_off
    local y = padding + row_off
    local config = {
      x = mconf.col + 1 + x + ipad,
      y = mconf.row + 1 + y + (ipad / 2),
      width = size * 2,
      height = size,
      namespace = "simplyfile_image",
    }
    if reload_image then
      local img = image.from_file(icon_path(value), config)
      if img then
        img:render()
      else
        image.from_file(fallback, config):render()
      end
    end

    local col_end = x + (size * 2 + (ipad * 2))
    vim.api.nvim_buf_set_text(
      main.buf,
      y + size + ipad,
      x,
      y + size + ipad,
      col_end,
      { util.text_center(value.name, col_end - x) }
    )

    if cursor_on and value.absolute == cursor_on.absolute then
      for i = y + 1, y + size + 1 + ipad do
        vim.api.nvim_buf_add_highlight(
          main.buf,
          ns,
          "CursorLine",
          i - 1,
          x,
          col_end
        )
      end
      sel[1] = row
      sel[2] = col
    end

    if not cursor_on and row == sel[1] and col == sel[2] then
      for i = y + 1, y + size + 1 + ipad do
        vim.api.nvim_buf_add_highlight(
          main.buf,
          ns,
          "CursorLine",
          i - 1,
          x,
          col_end
        )
      end
    end

    col = col + 1
    col_off = col_off + (gap * 2) + (size * 2 + (ipad * 2))
    if col > xmax then
      if row > ymax then
        break
      end
      col = 1
      col_off = 0
      row = row + 1
      row_off = row_off + gap + 1 + size + ipad
    end
  end
  util.override_state {
    grid_pos = sel,
    grid_cols = xmax,
  }
  util.buf_locks(main.buf)
end

return M
