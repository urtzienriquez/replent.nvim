-- tests/helpers.lua
-- Shared scaffolding for replent specs: build a scratch buffer with given
-- lines/filetype, make it current, and clean it up afterwards.

local M = {}

--- Create a scratch buffer with `lines`, set `filetype`, and make it current.
---@param filetype string
---@param lines string[]
---@return integer bufnr
function M.make_buf(filetype, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  -- Avoid firing FileType autocmds (replent's plugin/replent.lua attaches
  -- keymaps on FileType; specs exercise the Lua API directly).
  local save_ei = vim.o.eventignore
  vim.o.eventignore = "all"
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = filetype
  vim.o.eventignore = save_ei
  return buf
end

--- Move the cursor to (1-indexed) line `lnum`, column `col` (default 0).
function M.set_cursor(lnum, col)
  vim.api.nvim_win_set_cursor(0, { lnum, col or 0 })
end

--- Delete a buffer created by make_buf.
function M.cleanup(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

--- Close every window except the one showing `keep_buf` (or the first
--- window if `keep_buf` isn't visible). Deleting a buffer that's displayed
--- in a split (e.g. via close_repl) does NOT close that split -- it just
--- swaps in a fallback buffer -- so backend specs that open REPL splits
--- must call this in after_each to avoid leaking windows across tests that
--- share one Neovim process per spec file.
function M.close_extra_windows(keep_buf)
  local wins = vim.api.nvim_list_wins()
  local keep_win = nil
  for _, win in ipairs(wins) do
    if keep_buf and vim.api.nvim_win_get_buf(win) == keep_buf then
      keep_win = win
      break
    end
  end
  keep_win = keep_win or wins[1]
  for _, win in ipairs(wins) do
    if win ~= keep_win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

return M
