local M = {}

local function safe_map(mode, key, fn, desc)
  if not key or key == false then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  vim.keymap.set(mode, key, fn, { buffer = buf, silent = true, noremap = true, desc = desc })
end

function M.attach(lang_override)
  local cfg = require("replent.config").options
  local km = cfg.keymaps
  local actions = require("replent.actions")
  local backend = require("replent.backend").get()

  local lang = lang_override or vim.bo.filetype
  if lang == "quarto" then
    lang = require("replent.quarto").detect()
  end

  safe_map("n", km.send_line, function()
    actions.send_block()
  end, "Send block/line")
  safe_map("v", km.send_selection, function()
    actions.send_selection()
  end, "Send selection")
  safe_map("n", km.send_buffer, function()
    actions.send_buffer()
  end, "Send buffer")
  safe_map("n", km.sync_cwd, function()
    backend.sync_cwd()
  end, "Sync CWD")

  local map_data = {
    python = { start = km.start_python, close = km.close_python },
    julia = { start = km.start_julia, close = km.close_julia },
    matlab = { start = km.start_matlab, close = km.close_matlab },
  }

  if map_data[lang] then
    safe_map("n", map_data[lang].start, function()
      backend.start_repl(lang)
    end, "Start REPL")
    safe_map("n", map_data[lang].close, function()
      backend.close_repl(lang)
    end, "Close REPL")
  end

  if lang == "julia" then
    safe_map("n", km.julia_instantiate, function()
      actions.julia_instantiate()
    end, "Julia Pkg Instantiate")
  end
end

return M
