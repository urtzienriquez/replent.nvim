--- replent.nvim – plugin entrypoint
---
--- Neovim sources every file under plugin/ at startup, but this file does
--- almost nothing at that point: it only registers a single FileType
--- autocommand. The heavy modules (julia.lua, python.lua, tmux.lua …) are
--- required lazily inside that callback, so the plugin has zero cost for
--- filetypes that don't match.
---
--- Guard against double-loading (Neovim does this automatically for
--- ftplugin/ files; we do it manually here for the plugin/ entrypoint).
if vim.g.loaded_replent then return end
vim.g.loaded_replent = true

-- Make sure config is initialised with defaults. This is idempotent:
-- if the user already called require("replent").setup() in their config,
-- the options are already set and this is a no-op merge.
require("replent.config").setup()

-- ─────────────────────────────────────────────────────────────────
-- Lazy FileType autocommand
-- Everything else loads only when a relevant buffer is opened.
-- ─────────────────────────────────────────────────────────────────
vim.api.nvim_create_augroup("replent", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
    group   = "replent",
    -- pattern is resolved at callback time from config so that user changes
    -- to filetypes (made via setup()) are respected even if setup() is called
    -- after this file is sourced.
    pattern = "*",
    callback = function(args)
        local cfg = require("replent.config").options
        local ft  = vim.bo[args.buf].filetype

        -- Only act on configured filetypes
        local active = false
        for _, allowed in ipairs(cfg.filetypes) do
            if ft == allowed then active = true; break end
        end
        if not active then return end

        -- Attach keymaps unconditionally. vim-slime is also lazy-loaded on
        -- the same filetypes, so slime#send may not exist yet at this point –
        -- but it will be present by the time the user presses any key.
        -- The actual send functions check for it at call time.
        require("replent.keymaps").attach()
    end,
})
