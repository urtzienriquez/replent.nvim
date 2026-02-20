--- replent.nvim – tmux REPL helpers
--- Ported from the user's slime_utils.lua, adapted to use replent config.

local M = {}

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

--- Return the current command running in the 'last' tmux pane, or nil.
---@return string|nil
function M.last_pane_command()
    if not M.in_tmux() then return nil end
    local h = io.popen("tmux display-message -t '{last}' -p '#{pane_current_command}' 2>/dev/null")
    if not h then return nil end
    local cmd = h:read("*l")
    h:close()
    return (cmd and cmd ~= "") and cmd or nil
end

--- Return true when a supported REPL is active in the last tmux pane.
function M.has_active_repl()
    local cmd = M.last_pane_command()
    if not cmd then return false end
    for _, name in ipairs({ "python", "python3", "julia", "MATLAB", "ipython" }) do
        if cmd:find(name) then return true end
    end
    return false
end

--- Detect which REPL type ("python"|"julia"|"matlab") is running, or nil.
---@return string|nil
function M.active_repl_type()
    local cmd = M.last_pane_command()
    if not cmd then return nil end
    if cmd:find("python") or cmd:find("ipython") then return "python" end
    if cmd:find("julia") then return "julia" end
    if cmd:find("MATLAB") or cmd:find("matlab") then return "matlab" end
    return nil
end

--- Get all Julia channels from juliaup.
---@return string[]
function M.julia_channels()
    local h = io.popen("juliaup status 2>/dev/null")
    if not h then return {} end
    local out = h:read("*a")
    h:close()

    local channels = {}
    local in_table = false
    for line in out:gmatch("[^\r\n]+") do
        if line:match("Default%s+Channel") then
            in_table = true
        elseif in_table and not line:match("^%-+$") and not line:match("^%s*$") then
            local ch = line:match("%s+%*?%s+(%S+)%s+")
            if ch then table.insert(channels, ch) end
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
local function open_tmux_split(cmd)
    local cwd = vim.fn.getcwd()
    local tmux_cmd = string.format(
        "tmux split-window -h -c %s %s && tmux select-pane -l",
        vim.fn.shellescape(cwd), cmd
    )
    vim.fn.system(tmux_cmd)
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
            open_tmux_split(cfg.repl_commands.julia)
            vim.schedule(function() vim.notify("[replent] Started Julia REPL") end)
            return
        elseif #channels == 1 then
            open_tmux_split(string.format("julia +%s", channels[1]))
            vim.schedule(function()
                vim.notify(string.format("[replent] Started Julia +%s REPL", channels[1]))
            end)
            return
        else
            -- Let the user pick with fzf-lua
            local ok, fzf = pcall(require, "fzf-lua")
            if not ok then
                -- fzf-lua not available – just use default
                open_tmux_split(cfg.repl_commands.julia)
                vim.schedule(function() vim.notify("[replent] Started Julia REPL (default)") end)
                return
            end
            fzf.fzf_exec(channels, {
                prompt = "Julia Channel> ",
                winopts = { title = " Select Julia Channel ", height = 0.4, width = 0.5 },
                actions = {
                    ["default"] = function(selected)
                        if #selected == 0 then return end
                        local ch = selected[1]
                        open_tmux_split(string.format("julia +%s", ch))
                        vim.schedule(function()
                            vim.notify(string.format("[replent] Started Julia +%s REPL", ch))
                        end)
                    end,
                },
            })
            return
        end
    end

    local cmd = cfg.repl_commands[ft]
    if not cmd then
        vim.notify(string.format("[replent] No REPL command configured for %q", ft), vim.log.levels.WARN)
        return
    end
    open_tmux_split(cmd)
    vim.schedule(function() vim.notify(string.format("[replent] Started %s REPL", ft)) end)
end

--- Close the REPL for the given filetype.
---@param ft string
function M.close_repl(ft)
    if not M.in_tmux() then return end
    local exits = { python = "exit()", julia = "exit()", matlab = "exit" }
    local cmd = exits[ft]
    if cmd then
        vim.fn.system(string.format("tmux send-keys -t '{last}' %s Enter", vim.fn.shellescape(cmd)))
        vim.schedule(function() vim.notify(string.format("[replent] Closed %s REPL", ft)) end)
    end
end

--- Sync the REPL's working directory to Neovim's cwd.
function M.sync_cwd()
    if not M.in_tmux() then
        vim.notify("[replent] Not in a tmux session", vim.log.levels.ERROR)
        return
    end
    if not M.has_active_repl() then
        vim.notify("[replent] No active REPL found", vim.log.levels.WARN)
        return
    end

    local cwd = vim.fn.getcwd()
    local rt = M.active_repl_type()
    if not rt then
        vim.notify("[replent] Cannot detect REPL type", vim.log.levels.ERROR)
        return
    end

    local cd_cmds = {
        python = function(p) return string.format("import os; os.chdir('%s')", escape_path(p, "python")) end,
        julia  = function(p) return string.format('cd("%s")', escape_path(p, "julia")) end,
        matlab = function(p) return string.format("cd '%s'", escape_path(p, "matlab")) end,
    }

    local cd = cd_cmds[rt](cwd)
    vim.fn.system(string.format("tmux send-keys -t '{last}' %s Enter", vim.fn.shellescape(cd)))
    vim.schedule(function()
        vim.notify(string.format("[replent] Synced %s REPL → %s", rt, cwd))
    end)
end

return M
