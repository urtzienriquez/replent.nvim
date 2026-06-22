local M = {}
local active_repls = {}

local function escape_path(path, repl_type)
  if repl_type == "python" then
    return path:gsub("\\", "\\\\"):gsub("'", "\\'")
  elseif repl_type == "julia" then
    return path:gsub("\\", "\\\\"):gsub('"', '\\"')
  elseif repl_type == "matlab" then
    return path:gsub("'", "''")
  end
  return path
end

--- Return true if we are inside a tmux session.
function M.in_tmux()
  return vim.env.TMUX ~= nil
end

--- Return true if the given pane still exists in tmux.
---@param pane_id string
---@return boolean
local function pane_alive(pane_id)
  if not pane_id then
    return false
  end
  local h = io.popen("tmux display-message -t " .. vim.fn.shellescape(pane_id) .. " -p '#{pane_id}' 2>/dev/null")
  local ok = h and h:read("*l") ~= nil
  if h then h:close() end
  return ok
end

--- Return true when a REPL is tracked and its pane is still alive.
---@param ft string
function M.has_active_repl(ft)
  return pane_alive(active_repls[ft])
end

--- Return the REPL type for a tracked pane, or nil.
---@param ft string
---@return string|nil
function M.active_repl_type(ft)
  if not pane_alive(active_repls[ft]) then
    return nil
  end
  return ft
end

--- Get all Julia channels from juliaup.
---@return string[]
function M.julia_channels()
  local h = io.popen("juliaup status 2>/dev/null")
  if not h then
    return {}
  end
  local out = h:read("*a")
  h:close()

  local channels = {}
  local in_table = false
  for line in out:gmatch("[^\r\n]+") do
    if line:match("Default%s+Channel") then
      in_table = true
    elseif in_table and not line:match("^%-+$") and not line:match("^%s*$") then
      local ch = line:match("%s+%*?%s+(%S+)%s+")
      if ch then
        table.insert(channels, ch)
      end
    end
  end

  if #channels == 0 then
    local dh = io.popen("julia +default --version 2>/dev/null")
    if dh then
      local dout = dh:read("*a")
      dh:close()
      if dout:match("julia version") then
        table.insert(channels, "default")
      end
    end
  end
  return channels
end

--- Open a new tmux split and start the given command in the project cwd.
---@param cmd string Shell command to run (e.g. "ipython --quiet")
---@return string|nil pane_id of the new pane
local function open_tmux_split(cmd)
  local cwd = vim.fn.getcwd()
  vim.fn.system(string.format("tmux split-window -h -c %s %s",
    vim.fn.shellescape(cwd),
    vim.fn.shellescape("sh -c " .. vim.fn.shellescape(cmd))))
  local h = io.popen("tmux display-message -p '#{pane_id}' 2>/dev/null")
  local pane_id = h and h:read("*l") or nil
  if h then h:close() end
  vim.fn.system("tmux select-pane -l")
  return pane_id
end

--- Start a REPL for the given filetype using config.repl_commands.
---@param ft string  "python"|"julia"|"matlab"
function M.start_repl(ft)
  if not M.in_tmux() then
    vim.notify("[replent] Not in a tmux session", vim.log.levels.ERROR)
    return
  end

  local cfg = require("replent.config").options

  if ft == "julia" then
    local channels = M.julia_channels()
    if #channels == 0 then
      -- Fallback to plain julia
      local pid = open_tmux_split(cfg.repl_commands.julia)
      active_repls[ft] = pid
      vim.schedule(function()
        vim.notify("[replent] Started Julia REPL")
      end)
      return
    elseif #channels == 1 then
      local pid = open_tmux_split(string.format("julia +%s", channels[1]))
      active_repls[ft] = pid
      vim.schedule(function()
        vim.notify(string.format("[replent] Started Julia +%s REPL", channels[1]))
      end)
      return
    else
      -- Let the user pick with fzf-lua
      local ok, fzf = pcall(require, "fzf-lua")
      if ok then
        fzf.fzf_exec(channels, {
          prompt = "Julia Channel> ",
          winopts = { title = " Select Julia Channel ", height = 0.4, width = 0.5 },
          actions = {
            ["default"] = function(selected)
              if #selected == 0 then
                return
              end
              local ch = selected[1]
              local pid = open_tmux_split(string.format("julia +%s", ch))
              active_repls[ft] = pid
              vim.schedule(function()
                vim.notify(string.format("[replent] Started Julia +%s REPL", ch))
              end)
            end,
          },
        })
      else
        -- fzf-lua not available – fall back to vim.ui.select (renders as a
        -- numbered cmdline list by default; upgraded by dressing.nvim etc.)
        vim.ui.select(channels, { prompt = "Julia channel: " }, function(ch)
          if not ch then
            return
          end
          local pid = open_tmux_split(string.format("julia +%s", ch))
          active_repls[ft] = pid
          vim.schedule(function()
            vim.notify(string.format("[replent] Started Julia +%s REPL", ch))
          end)
        end)
      end
      return
    end
  end

  local cmd = cfg.repl_commands[ft]
  if not cmd then
    vim.notify(string.format("[replent] No REPL command configured for %q", ft), vim.log.levels.WARN)
    return
  end
  local pid = open_tmux_split(cmd)
  active_repls[ft] = pid
  vim.schedule(function()
    vim.notify(string.format("[replent] Started %s REPL", ft))
  end)
end

--- Close the REPL for the given filetype.
---@param ft string
function M.close_repl(ft)
  if not M.in_tmux() then
    return
  end
  local pane_id = active_repls[ft]
  if not pane_id then
    return
  end
  local exits = { python = "exit()", julia = "exit()", matlab = "exit" }
  local cmd = exits[ft]
  if cmd then
    vim.fn.system(string.format("tmux send-keys -t %s %s Enter", vim.fn.shellescape(pane_id), vim.fn.shellescape(cmd)))
    active_repls[ft] = nil
    vim.schedule(function()
      vim.notify(string.format("[replent] Closed %s REPL", ft))
    end)
  end
end

--- Sync the REPL's working directory to Neovim's cwd.
function M.sync_cwd()
  if not M.in_tmux() then
    vim.notify("[replent] Not in a tmux session", vim.log.levels.ERROR)
    return
  end

  local ft = require("replent.actions").effective_lang()
  if not M.has_active_repl(ft) then
    vim.notify("[replent] No active REPL found for " .. ft, vim.log.levels.WARN)
    return
  end

  local cwd = vim.fn.getcwd()
  local rt = M.active_repl_type(ft)
  if not rt then
    vim.notify("[replent] Cannot detect REPL type", vim.log.levels.ERROR)
    return
  end

  local cd_cmds = {
    python = function(p)
      return string.format("import os; os.chdir('%s')", escape_path(p, "python"))
    end,
    julia = function(p)
      return string.format('cd("%s")', escape_path(p, "julia"))
    end,
    matlab = function(p)
      return string.format("cd '%s'", escape_path(p, "matlab"))
    end,
  }

  local cd = cd_cmds[rt](cwd)
  local pane_id = active_repls[ft]
  vim.fn.system(string.format("tmux send-keys -t %s %s Enter", vim.fn.shellescape(pane_id), vim.fn.shellescape(cd)))
  vim.schedule(function()
    vim.notify(string.format("[replent] Synced %s REPL → %s", rt, cwd))
  end)
end

return M
