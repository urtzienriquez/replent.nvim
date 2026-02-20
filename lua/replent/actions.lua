--- replent.nvim – language-aware send actions

local M = {}

--- Resolve the effective language for the current buffer.
--- For quarto files, returns the detected chunk language.
--- For all others, returns vim.bo.filetype.
---@return string|nil
local function effective_lang()
    local ft = vim.bo.filetype
    if ft == "quarto" then
        return require("replent.quarto").detect()
    end
    return ft
end

--- Detect whether the current buffer has smart block detection.
---@return boolean
local function has_smart_blocks()
    local lang = effective_lang()
    return lang == "julia" or lang == "python"
end

--- Get (text, start_line, end_line) for the block/line at cursor, dispatching
--- to the language-specific module when available.
---@return string|nil, integer, integer
function M.get_send_text()
    local lang = effective_lang()

    if lang == "julia" then
        return require("replent.julia").get_send_text()
    elseif lang == "python" then
        return require("replent.python").get_send_text()
    end

    -- Fallback: send the current line
    local bufnr = vim.api.nvim_get_current_buf()
    local line  = vim.api.nvim_win_get_cursor(0)[1]
    local text  = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
    if text:match("^%s*$") then return nil, line, line end
    return text, line, line
end

--- Thin wrapper around slime#send that gives a clear error if vim-slime is
--- missing. slime#send is an autoload function, so exists() returns 0 until
--- the first call – we use pcall instead.
---@param text string
---@return boolean ok
local function slime_send(text)
    local ok, err = pcall(vim.fn["slime#send"], text)
    if not ok then
        vim.notify(
            "[replent] vim-slime not available: " .. tostring(err)
            .. "\nMake sure jpalardy/vim-slime is installed.",
            vim.log.levels.ERROR
        )
    end
    return ok
end

--- Send current block/line to the REPL and advance the cursor.
function M.send_block()
    local tmux = require("replent.tmux")
    if not tmux.has_active_repl() then
        vim.notify("[replent] No active REPL. Start one with the open-REPL keymaps.", vim.log.levels.WARN)
        return
    end

    local text, _, end_line = M.get_send_text()
    if not text then return end

    if not slime_send(text .. "\n") then return end

    -- Advance cursor past the block, skipping blank lines
    if has_smart_blocks() then
        local total = vim.api.nvim_buf_line_count(0)
        local next  = math.min(end_line + 1, total)
        vim.api.nvim_win_set_cursor(0, { next, 0 })

        if next < total then
            local rest = vim.api.nvim_buf_get_lines(0, next - 1, total, false)
            local skip = 0
            for _, l in ipairs(rest) do
                if l:match("^%s*$") then skip = skip + 1 else break end
            end
            if skip > 0 then
                vim.api.nvim_win_set_cursor(0, { math.min(next + skip, total), 0 })
            end
        end
    end
end

--- Send the visual selection to the REPL.
function M.send_selection()
    local tmux = require("replent.tmux")
    if not tmux.has_active_repl() then
        vim.notify("[replent] No active REPL. Start one with the open-REPL keymaps.", vim.log.levels.WARN)
        return
    end
    vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes("<Plug>SlimeRegionSend", true, false, true),
        "x", false
    )
    vim.cmd("normal! '>j")
end

--- Send the entire buffer to the REPL.
function M.send_buffer()
    local tmux = require("replent.tmux")
    if not tmux.has_active_repl() then
        vim.notify("[replent] No active REPL. Start one with the open-REPL keymaps.", vim.log.levels.WARN)
        return
    end
    vim.cmd("normal! ggVG")
    vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes("<Plug>SlimeRegionSend", true, false, true),
        "x", false
    )
end

--- Instantiate Julia project in the current working directory.
function M.julia_instantiate()
    local tmux = require("replent.tmux")
    if not tmux.has_active_repl() then
        vim.notify("[replent] No active REPL. Start one with <leader>oj.", vim.log.levels.WARN)
        return
    end
    slime_send('using Pkg; Pkg.activate(".")\nPkg.instantiate()\n')
end

--- Run the language-specific debug function.
function M.debug_block()
    local lang = effective_lang()
    if lang == "julia" then
        require("replent.julia").debug()
    elseif lang == "python" then
        require("replent.python").debug()
    else
        vim.notify("[replent] Block debug not supported for " .. (lang or "unknown"), vim.log.levels.WARN)
    end
end

return M
