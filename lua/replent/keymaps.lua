--- replent.nvim – keymap registration
---
--- Called once per buffer attach. Each map is skipped when:
---   • the user set the key to `false` in config
---   • another mapping already exists on that key for that buffer
---     (unless `force = true` is passed, never done by default)

local M = {}

--- Set a buffer-local keymap only when the key is not already occupied
--- and the config value is not false.
---@param mode string|string[]
---@param key string|false
---@param fn function|string
---@param desc string
local function safe_map(mode, key, fn, desc)
    if not key or key == false then return end

    local buf = vim.api.nvim_get_current_buf()
    local modes = type(mode) == "table" and mode or { mode }

    for _, m in ipairs(modes) do
        -- Check if the key is already mapped for this buffer
        local existing = vim.fn.maparg(key, m, false, true)
        if existing and existing.buffer == 1 then
            -- Already mapped at buffer level – do not override
        else
            vim.keymap.set(m, key, fn, {
                buffer = buf,
                silent = true,
                noremap = true,
                desc = desc,
            })
        end
    end
end

--- Register all replent keymaps for the current buffer.
--- Called from the FileType autocommand.
---@param lang_override? string  Force a specific language (used for quarto)
function M.attach(lang_override)
    local cfg     = require("replent.config").options
    local km      = cfg.keymaps
    local actions = require("replent.actions")
    local tmux    = require("replent.tmux")
    local ft      = vim.bo.filetype

    -- For quarto buffers, detect the primary chunk language.
    -- lang is what drives REPL-launcher / block-detection keymaps;
    -- ft drives the filetype check for safe_map.
    local lang = lang_override
    if not lang then
        if ft == "quarto" then
            lang = require("replent.quarto").detect()
            if not lang then
                -- No supported language chunk found – nothing to do.
                return
            end
        else
            lang = ft
        end
    end

    -- Send current line/block (normal mode)
    safe_map("n", km.send_line, function()
        actions.send_block()
    end, "Send block/line to REPL")

    -- Send visual selection
    safe_map("v", km.send_selection, function()
        actions.send_selection()
    end, "Send selection to REPL")

    -- Send entire buffer
    safe_map("n", km.send_buffer, function()
        actions.send_buffer()
    end, "Send buffer to REPL")

    -- Sync cwd
    safe_map("n", km.sync_cwd, function()
        tmux.sync_cwd()
    end, "Sync cwd to REPL")

    -- Filetype-specific REPL launchers & closers
    if lang == "python" then
        safe_map("n", km.start_python, function()
            tmux.start_repl("python")
        end, "Start Python REPL")
        safe_map("n", km.close_python, function()
            tmux.close_repl("python")
        end, "Close Python REPL")

    elseif lang == "julia" then
        safe_map("n", km.start_julia, function()
            tmux.start_repl("julia")
        end, "Start Julia REPL")
        safe_map("n", km.close_julia, function()
            tmux.close_repl("julia")
        end, "Close Julia REPL")
        safe_map("n", km.julia_instantiate, function()
            actions.julia_instantiate()
        end, "Activate + instantiate Julia project")

    elseif lang == "matlab" then
        safe_map("n", km.start_matlab, function()
            tmux.start_repl("matlab")
        end, "Start MATLAB REPL")
        safe_map("n", km.close_matlab, function()
            tmux.close_repl("matlab")
        end, "Close MATLAB REPL")
    end

    -- Debug block detection (only for languages that support it)
    if lang == "julia" or lang == "python" then
        safe_map("n", km.debug_block, function()
            actions.debug_block()
        end, "Debug block detection")
    end
end

return M
