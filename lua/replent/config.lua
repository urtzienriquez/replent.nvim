--- replent.nvim configuration with sensible defaults
--- Users can override via replent.setup() or by setting vim.g.replent before
--- the plugin loads, but setup() is never required.

local M = {}

--- Default configuration
---@class ReplentConfig
---@field filetypes string[] Filetypes for which replent is active
---@field keymaps ReplentKeymapConfig Keymap overrides (set to false to disable)
---@field repl_commands table<string, string> REPL launch commands per language
---@field auto_cd boolean Automatically sync cwd when starting a REPL

---@class ReplentKeymapConfig
---@field send_line string|false Normal-mode: send current line/block
---@field send_selection string|false Visual-mode: send selection
---@field send_buffer string|false Send entire buffer
---@field start_python string|false Open Python REPL
---@field start_julia string|false Open Julia REPL
---@field start_matlab string|false Open MATLAB REPL
---@field close_python string|false Close Python REPL
---@field close_julia string|false Close Julia REPL
---@field close_matlab string|false Close MATLAB REPL
---@field sync_cwd string|false Sync working directory to REPL
---@field julia_instantiate string|false Activate + instantiate Julia project
---@field debug_block string|false Debug block detection

M.defaults = {
    filetypes = { "python", "julia", "matlab", "quarto" },
    keymaps = {
        send_line      = "<CR>",
        send_selection = "<CR>",
        send_buffer    = "<leader>sb",
        start_python   = "<leader>op",
        start_julia    = "<leader>oj",
        start_matlab   = "<leader>om",
        close_python   = "<leader>qp",
        close_julia    = "<leader>qj",
        close_matlab   = "<leader>qm",
        sync_cwd       = "<leader>cd",
        julia_instantiate = "<leader>ji",
        debug_block    = "<leader>bc",
    },
    repl_commands = {
        python = "ipython --no-confirm-exit --no-banner --quiet",
        julia  = "julia",
        matlab = "matlab -nodesktop -nosplash",
    },
    auto_cd = false,
}

--- Active (merged) configuration
---@type ReplentConfig
M.options = {}

--- Merge user config over defaults (deep merge, one level for keymaps)
---@param user? table
function M.setup(user)
    user = user or {}
    M.options = vim.tbl_deep_extend("force", M.defaults, user)
end

-- Eagerly initialise with defaults so that the plugin is usable even if the
-- user never calls setup().
M.setup()

return M
