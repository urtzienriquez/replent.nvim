local M = {}

local active_repls = {}

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
  if M.has_active_repl() then
    vim.notify("[replent] " .. ft .. " REPL is already open.")
    return
  end

  local cfg = require("replent.config").options

  if ft == "julia" then
    -- Reuse the channel detection logic from the tmux backend
    local channels = require("replent.tmux").julia_channels()

    if #channels == 0 then
      local cmd = cfg.repl_commands.julia
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
    local cmd = cfg.repl_commands[ft]
    if not cmd then
      vim.notify("[replent] No command configured for " .. ft, vim.log.levels.ERROR)
      return
    end
    M._spawn_terminal(ft, cmd)
  end
end

-- Helper to encapsulate the terminal spawning logic
function M._spawn_terminal(ft, cmd)
  vim.cmd("vsplit")

  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_set_current_buf(bufnr)

  local jobid = vim.fn.jobstart(cmd, {
    cwd = vim.fn.getcwd(),
    term = true,
    on_exit = function()
      active_repls[ft] = nil
    end,
  })

  active_repls[ft] = { bufnr = bufnr, jobid = jobid }
  vim.api.nvim_buf_set_name(bufnr, "REPL [" .. ft .. "]")

  vim.cmd("wincmd p")
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
