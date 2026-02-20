--- replent.nvim
---
--- A lightweight Neovim REPL integration plugin built on top of vim-slime.
--- Works out of the box with no configuration required.
---
--- Optional user setup (call this *before* the plugin's autocommands fire,
--- i.e. before the first relevant filetype is opened):
---
---   require("replent").setup({
---     filetypes = { "python", "julia" },     -- restrict to fewer filetypes
---     keymaps = {
---       send_line = "<CR>",                  -- keep default
---       send_buffer = false,                 -- disable this keymap
---       start_python = "<leader>rp",         -- change this one
---     },
---     repl_commands = {
---       python = "ipython",                  -- change the launch command
---     },
---   })

local M = {}

--- Configure replent.  All fields are optional; unspecified fields fall back
--- to the defaults defined in replent.config.
---@param opts? ReplentConfig
function M.setup(opts)
    require("replent.config").setup(opts)
end

-- Convenience re-exports so users can call actions programmatically.
M.send_block      = function() require("replent.actions").send_block() end
M.send_selection  = function() require("replent.actions").send_selection() end
M.send_buffer     = function() require("replent.actions").send_buffer() end
M.start_repl      = function(ft) require("replent.tmux").start_repl(ft) end
M.close_repl      = function(ft) require("replent.tmux").close_repl(ft) end
M.sync_cwd        = function() require("replent.tmux").sync_cwd() end
M.has_active_repl = function() return require("replent.tmux").has_active_repl() end

return M
