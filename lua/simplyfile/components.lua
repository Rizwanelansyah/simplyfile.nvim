local M = {}
local clipboard = require("simplyfile.clipboard")

---filter indicator for styling
---@param expl SimplyFile.ExplState
---@return table[]?
function M.filter(expl)
  if type(expl.filter) == "string" or expl.reverse_filter then
    return {
      { " : ", "@field" },
      { expl.reverse_filter and "rev " or "", "@keyword" },
      { type(expl.filter) == "string" and expl.filter or "", "@string" }
    }
  end
end

---sort indicator for styling
---@param expl SimplyFile.ExplState
---@return table[]? # inserted or not
function M.sort(expl)
  if type(expl.sort) == "string" or expl.reverse_sort then
    return {
      { "󰒺 : ", "@field" },
      { expl.reverse_sort and "rev " or "", "@keyword" },
      { type(expl.sort) == "string" and expl.sort or "", "@string" }
    }
  end
end

---search indicator for styling
---@param expl SimplyFile.ExplState
---@return table[]?
function M.search(expl)
  if expl.search ~= "" then
    return {
      { " : ", "@field" },
      { expl.search, "@string" }
    }
  end
end

---Show Current Working Directory
---@return table
function M.cwd()
  local cwd = vim.fn.getcwd(0)
  local home = vim.fn.getenv("HOME")
  if vim.startswith(cwd, home) then
    cwd = cwd:gsub("^" .. home, "~", 1)
  end
  return { { "CWD: ", "@field" }, { cwd, "@string" } }
end

function M.clipboard()
  local comps = {}
  if #clipboard.registers > 0 then
    table.insert(comps, { " :", "@field" })
    local counts = {
      copy = 0,
      cut = 0,
    }
    for _, reg in ipairs(clipboard.registers) do
      counts[reg.method] = (counts[reg.method] or 0) + 1
    end
    if counts.copy > 0 then
      table.insert(comps, { " " .. counts.copy, "@number" })
      if counts.copy > 1 then
        table.insert(comps, { " copies", "@method" })
      else
        table.insert(comps, { " copy", "@method" })
      end
    end
    if counts.cut > 0 then
      table.insert(comps, { " " .. counts.cut, "@number" })
      if counts.cut > 1 then
        table.insert(comps, { " cuts", "@method" })
      else
        table.insert(comps, { " cut", "@method" })
      end
    end
  end
  return comps
end

return M
