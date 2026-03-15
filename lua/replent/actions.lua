local M = {}

--- Resolve the effective language for the current buffer.
function M.effective_lang()
  local ft = vim.bo.filetype
  if ft == "quarto" then
    return require("replent.quarto").detect()
  end
  return ft
end

local function has_smart_blocks()
  local lang = M.effective_lang()
  return lang == "julia" or lang == "python" or lang == "matlab"
end

--- Find the window displaying the REPL and scroll it to the bottom
local function scroll_to_bottom(jobid)
  local bufnr = nil
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[buf].terminal_job_id == jobid then
      bufnr = buf
      break
    end
  end

  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local wins = vim.fn.win_findbuf(bufnr)
    for _, win in ipairs(wins) do
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_win_set_cursor(win, { line_count, 0 })
    end
  end
end

--- Get text for the block/line at cursor
function M.get_send_text()
  local lang = M.effective_lang()

  if lang == "julia" then
    return require("replent.julia").get_send_text()
  elseif lang == "python" then
    return require("replent.python").get_send_text()
  elseif lang == "matlab" then
    -- Simple MATLAB block detection (between %% markers)
    local bufnr = vim.api.nvim_get_current_buf()
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local start_line, end_line = cur, cur
    for i = cur - 1, 1, -1 do
      if lines[i]:match("^%%") then
        start_line = i + 1
        break
      end
      start_line = i
    end
    for i = cur + 1, #lines do
      if lines[i]:match("^%%") then
        end_line = i - 1
        break
      end
      end_line = i
    end
    local block = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
    return table.concat(block, "\n"), start_line, end_line
  end

  -- Fallback: current line
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
  return text, line, line
end

--- Internal wrapper that handles strategy-switching and scrolling
function M.slime_send(text)
  local cfg = require("replent.config").options
  local ft = M.effective_lang()
  local jobid = nil

  if cfg.strategy == "neovim" then
    vim.g.slime_target = "neovim"
    jobid = require("replent.neovim").get_job_id(ft)
    if jobid then
      vim.b.slime_config = { jobid = jobid }
    else
      vim.notify("[replent] REPL not started for " .. ft, vim.log.levels.ERROR)
      return
    end
  else
    vim.g.slime_target = "tmux"
  end

  -- Ensure MATLAB gets a proper newline to execute
  if ft == "matlab" and not text:match("\n$") then
    text = text .. "\n"
  end

  vim.fn["slime#send"](text)

  if cfg.strategy == "neovim" and jobid then
    vim.schedule(function()
      scroll_to_bottom(jobid)
    end)
  end
end

function M.send_block()
  local text, _, end_line = M.get_send_text()
  if not text or text:match("^%s*$") then
    return
  end

  M.slime_send(text .. "\n")

  if has_smart_blocks() then
    local total = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { math.min(end_line + 1, total), 0 })
  end
end

function M.send_selection()
  -- Get visual selection text manually
  local _, srow, scol, _ = unpack(vim.fn.getpos("v"))
  local _, erow, ecol, _ = unpack(vim.fn.getpos("."))
  if srow > erow then
    srow, erow = erow, srow
  end

  local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
  if #lines == 0 then
    return
  end

  local text = table.concat(lines, "\n")
  M.slime_send(text .. "\n")

  -- Exit visual mode and move down
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
  local total = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { math.min(erow + 1, total), 0 })
end

function M.send_buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local text = table.concat(lines, "\n")
  M.slime_send(text .. "\n")
  vim.notify("[replent] Sent entire buffer to REPL")
end

function M.julia_instantiate()
  M.slime_send('using Pkg; Pkg.activate(".")\nPkg.instantiate()\n')
end

function M.debug_block()
  local lang = M.effective_lang()
  if lang == "julia" then
    require("replent.julia").debug()
  elseif lang == "python" then
    require("replent.python").debug()
  end
end

return M
