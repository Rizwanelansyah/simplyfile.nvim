local M = {}
local util = require("simplyfile.util")

---@alias SimplyFile.ClipboardRegister { method: 'copy' | 'cut', dir: SimplyFile.Directory, id: integer }

---@type SimplyFile.ClipboardRegister[]
M.registers = {}

---check if the dir already on clipboard or not
---@param dir SimplyFile.Directory
---@return boolean
function M.contain(dir)
  for _, reg in ipairs(M.registers) do
    if reg.dir.absolute == dir.absolute then
      return true
    end
  end
  return false
end

function M.create_id()
  if #M.registers < 1 then
    return 1
  else
    return M.registers[#M.registers].id + 1
  end
end

---copy file/folder to clipboard entry
---@param dir SimplyFile.Directory
function M.copy(dir)
  if not dir then return end
  if M.contain(dir) then return end
  table.insert(M.registers, { method = 'copy', dir = dir, id = M.create_id() } --[[@as SimplyFile.ClipboardRegister]])
  if vim.g.simplyfile_config.clipboard.notify then
    vim.notify("copy " .. dir.name .. " added to clipboard")
  end
end

---cut file/folder to clipboard entry
---@param dir SimplyFile.Directory
function M.cut(dir)
  if not dir then return end
  if M.contain(dir) then return end
  table.insert(M.registers, { method = 'cut', dir = dir, id = M.create_id() } --[[@as SimplyFile.ClipboardRegister]])
  if vim.g.simplyfile_config.clipboard.notify then
    vim.notify("cut " .. dir.name .. " added to clipboard")
  end
end

---paste {entry} to {dest}
---@param reg SimplyFile.ClipboardRegister
---@param dest string destination path
---@param after fun()? callback if the file is pasted
function M.paste(reg, dest, after)
  if reg.method == 'copy' then
    if vim.fn.executable("cp") then
      if vim.fn.getfsize(dest .. "/" .. reg.dir.name) == -1 then
        vim.cmd("silent !cp -r " .. reg.dir.absolute .. " " .. dest .. "/")
        util.callget(after)
      else
        vim.ui.input({ prompt = "File already exists on " .. dest .. "/", default = reg.dir.name }, function(value)
          if vim.fn.getfsize(dest .. "/" .. value) ~= -1 then return end
          vim.cmd("silent !cp -r " .. reg.dir.absolute .. " " .. dest .. "/" .. value)
          util.callget(after)
        end)
      end
    end
  elseif reg.method == 'cut' then
    if vim.fn.executable("mv") then
      if vim.fn.getfsize(dest .. "/" .. reg.dir.name) == -1 then
        vim.cmd("silent !mv " .. reg.dir.absolute .. " " .. dest .. "/")
        util.callget(after)
      else
        vim.ui.input({ prompt = "File already exists on " .. dest .. "/", default = reg.dir.name }, function(value)
          if vim.fn.getfsize(dest .. "/" .. value) ~= -1 then return end
          vim.cmd("silent !mv " .. reg.dir.absolute .. " " .. dest .. "/" .. value)
          util.callget(after)
        end)
      end
    end
  end
end

---paste last clipboard entry to {dest}
---@param dest string destination path
---@param after fun()? callback if the file is pasted
function M.paste_last(dest, after)
  local type = vim.fn.getftype(dest)
  if type ~= 'dir' and type ~= 'link' then return end
  if vim.tbl_isempty(M.registers) then return end
  ---@type SimplyFile.ClipboardRegister
  local reg = table.remove(M.registers, #M.registers)
  M.paste(reg, dest, after)
end

---select the entry and paste it to {dest}
---@param dest string destination path
---@param after fun()? callback if the file is pasted
function M.paste_select(dest, after)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = util.open_win(vim.o.columns - 2, math.floor(vim.o.lines / 2) - 2, math.floor(vim.o.lines / 2) - 1, 1, buf,
    true)
  local ns = vim.api.nvim_create_namespace("SimplyFile")
  local spc = { " ", "Normal" }

  vim.api.nvim_set_option_value("cursorline", true, { win = win })
  util.win_edit_config(win,
    {
      title = "[ Clipboard ]",
      title_pos = "center",
      footer =
      "[ KeyMaps: d -> Delete Register, <CR> -> Select Register, <ESC> -> Exit ]",
      footer_pos = "center"
    })
  for i, reg in ipairs(M.registers) do
    vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { "  " })
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
      id = reg.id,
      end_row = i - 1,
      end_col = 0,
      virt_text = { { reg.method, "@method" }, spc, { reg.dir.icon, reg.dir.hl }, spc, { reg.dir.absolute, "@string" } },
      virt_text_pos = "inline",
    })
  end
  local close = function()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  vim.api.nvim_buf_set_keymap(buf, 'n', '<ESC>', "", {
    callback = close
  })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'd', "", {
    callback = function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local reg = table.remove(M.registers, row)
      vim.api.nvim_buf_del_extmark(buf, ns, reg.id)
      vim.api.nvim_del_current_line()
    end
  })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', "", {
    callback = function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local reg = table.remove(M.registers, row)
      close()
      if reg then
        M.paste(reg, dest, after)
      end
    end
  })
end

return M
