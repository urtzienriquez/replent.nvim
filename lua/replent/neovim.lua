local M = {}

local active_repls = {}

local function cfg()
  return require("replent.config").options
end

function M.has_active_repl()
  local ft = require("replent.actions").effective_lang()
  local data = active_repls[ft]
  return data and vim.api.nvim_buf_is_valid(data.bufnr)
end

function M.get_job_id(ft)
  local data = active_repls[ft]
  if data and vim.api.nvim_buf_is_valid(data.bufnr) then
    return data.jobid
  end
  return nil
end

function M.start_repl(ft)
  local data = active_repls[ft]
  if data and vim.api.nvim_buf_is_valid(data.bufnr) then
    -- Already running: bring the window back if it was hidden/closed
    -- (no-op if it is already visible).
    M.reopen_win(ft)
    return
  end

  local config = cfg()

  if ft == "julia" then
    -- Reuse the channel detection logic from the tmux backend
    local channels = require("replent.tmux").julia_channels()

    if #channels == 0 then
      local cmd = config.repl_commands.julia
      M._spawn_terminal(ft, cmd)
      return
    end

    local ok, fzf = pcall(require, "fzf-lua")
    if ok then
      fzf.fzf_exec(channels, {
        prompt = "Julia Channel> ",
        winopts = { title = " Select Julia Channel ", height = 0.4, width = 0.5 },
        actions = {
          ["default"] = function(selected)
            if #selected > 0 then
              M._spawn_terminal(ft, "julia +" .. selected[1])
            end
          end,
        },
      })
    else
      vim.ui.select(channels, { prompt = "Julia channel: " }, function(ch)
        if ch then
          M._spawn_terminal(ft, "julia +" .. ch)
        end
      end)
    end
  else
    local cmd = config.repl_commands[ft]
    if not cmd then
      vim.notify("[replent] No command configured for " .. ft, vim.log.levels.ERROR)
      return
    end
    M._spawn_terminal(ft, cmd)
  end
end

-- Minimum columns to leave for the editor before using an exact-width split
local MIN_EDITOR_WIDTH = 80

-- Create a split sized/positioned per config.neovim.
local function split_window()
  local config = cfg().neovim

  if config.width > 0 then
    -- Vertical split with an exact column width
    local nw = vim.o.number and vim.o.numberwidth or 0
    local sw = config.width + MIN_EDITOR_WIDTH + 1 + nw
    if vim.fn.winwidth(0) > sw then
      local pos = config.position:find("left") and "aboveleft" or "belowright"
      vim.cmd("silent exe '" .. pos .. " " .. config.width .. "vnew'")
      return
    end
  end

  if config.height > 0 then
    -- Horizontal split with an exact row height
    if config.height < (vim.fn.winheight(0) - 1) then
      local pos = config.position:find("above") and "aboveleft" or "belowright"
      vim.cmd("silent exe '" .. pos .. " " .. config.height .. "new'")
      return
    end
  end

  -- Default: equal split (vnew creates a dedicated empty buffer;
  -- vsplit shares the current buffer which would destroy the editor
  -- when jobstart(term=true) turns it into a terminal).
  local pos = config.position:find("left") and "aboveleft" or "belowright"
  vim.cmd("silent " .. pos .. " vnew")
end

-- Apply buffer & window options to a terminal buffer/window. <Esc> is
-- buffer-local and survives window changes; winfixwidth/winfixheight are
-- window-local and must be re-applied when a window is recreated.
local function apply_options(bufnr)
  local config = cfg().neovim
  if config.esc_term then
    vim.api.nvim_buf_set_keymap(
      bufnr,
      "t",
      "<Esc>",
      "<C-\\><C-n>",
      { noremap = true, silent = true }
    )
  end
  for _, optn in ipairs(vim.fn.split(config.buffer_opts, "\n")) do
    vim.cmd("setlocal " .. optn)
  end
end

-- Re-show the REPL buffer in a window if it isn't visible already.
function M.reopen_win(ft)
  local data = active_repls[ft]
  if not data or not vim.api.nvim_buf_is_valid(data.bufnr) then
    return
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == data.bufnr then
      return
    end
  end
  split_window()
  local orphan = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_buf(0, data.bufnr)
  if orphan ~= data.bufnr and vim.api.nvim_buf_is_valid(orphan) then
    vim.api.nvim_buf_delete(orphan, { force = true })
  end
  apply_options(data.bufnr)
  -- Anchor the freshly attached window to the newest output so a hidden REPL
  -- that kept receiving code shows the tail on reopen.
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(data.bufnr), 0 })
  vim.cmd("wincmd p")
end

-- Helper to encapsulate the terminal spawning logic
function M._spawn_terminal(ft, cmd)
  split_window()

  -- Reuse the split window's buffer for the terminal so no extra
  -- "[No Name]" buffer is left behind in the buffer list.
  local bufnr = vim.api.nvim_get_current_buf()

  local jobid = vim.fn.jobstart(cmd, {
    cwd = vim.fn.getcwd(),
    term = true,
    on_exit = function()
      active_repls[ft] = nil
    end,
  })

  active_repls[ft] = { bufnr = bufnr, jobid = jobid }
  -- Note: don't nvim_buf_set_name on a terminal buffer — renaming it
  -- creates a phantom entry with the old term:// path in the buffer list.
  -- The buffer is nobuflisted anyway; term:// is fine for internal tracking.

  apply_options(bufnr)

  vim.cmd("wincmd p")
  vim.cmd("stopinsert")
end

function M.close_repl(ft)
  local data = active_repls[ft]
  if data and vim.api.nvim_buf_is_valid(data.bufnr) then
    vim.api.nvim_buf_delete(data.bufnr, { force = true })
    active_repls[ft] = nil
  end
end

function M.sync_cwd()
  local ft = require("replent.actions").effective_lang()
  local jobid = M.get_job_id(ft)
  if not jobid then
    return
  end

  local cwd = vim.fn.getcwd()
  local cd_cmd = ""
  if ft == "python" then
    cd_cmd = string.format("import os; os.chdir('%s')\n", cwd:gsub("\\", "/"))
  elseif ft == "julia" then
    cd_cmd = string.format('cd("%s")\n', cwd:gsub("\\", "/"))
  elseif ft == "matlab" then
    cd_cmd = string.format("cd '%s'\n", cwd)
  end

  if cd_cmd ~= "" then
    vim.api.nvim_chan_send(jobid, cd_cmd)
    vim.notify("[replent] Synced REPL to: " .. cwd)
  end
end

return M
