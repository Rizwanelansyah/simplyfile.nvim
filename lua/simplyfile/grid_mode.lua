local M = {}
local image = require("image")
local util = require("simplyfile.util")

---render grid mode view on {main}
---@param main { buf: integer, win: integer }
---@param dirs SimplyFile.Directory[]
function M.render(main, dirs)
  for _, img in ipairs(image.get_images()) do
    if img.namespace == "simplyfile_image" then
      img:clear()
    end
  end

  local icon_path = vim.g.simplyfile_config.grid_mode.icon_path
  if not icon_path then
    vim.notify("Error: field `icon_path` on `grid_mode` option is not setted")
  end
  local mconf = vim.api.nvim_win_get_config(main.win)
  local size = vim.g.simplyfile_config.grid_mode.size
  local gap = vim.g.simplyfile_config.grid_mode.gap
  local padding = vim.g.simplyfile_config.grid_mode.padding
  local fallback = vim.g.simplyfile_config.grid_mode.fallback_image
  local max = math.floor((mconf.width - (padding * 2)) / ((size * 3) + (gap * 2)))
  local col = 1
  local row = 1
  local row_off = 0
  local col_off = 0

  util.buf_unlocks(main.buf)
  for i = 1, mconf.height do
    vim.api.nvim_buf_set_lines(main.buf, i - 1, i, false, { ((" "):rep(mconf.width)) })
  end
  for _, value in ipairs(dirs) do
    local x = padding + (col_off == 0 and 0 or 3 * size)
    local y = padding + (row_off == 0 and 0 or size) + row_off
    local config = {
      x = mconf.col + (gap * 2) + x + col_off,
      y = mconf.row + gap + y,
      width = 2 * size,
      height = size,
      namespace = "simplyfile_image",
    }
    local img = image.from_file(icon_path(value), config)
    if img then
      img:render()
    else
      image.from_file(fallback, config):render()
    end
    vim.api.nvim_buf_set_text(
      main.buf,
      y + size + 1,
      x + col_off - 1,
      y + size + 2,
      x + col_off + (size * 3) + (gap * 2) - 1,
      { util.text_center(value.name, (size * 3) + (gap * 2)) }
    )

    col = col + 1
    col_off = col_off + (col_off == 0 and 0 or 3 * size) + (gap * 2)
    if col > max then
      col = 1
      col_off = 0
      row = row + 1
      row_off = row_off + (row_off == 0 and 0 or size) + gap + 1
    end
  end
  util.buf_locks(main.buf)
end

return M
