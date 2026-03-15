--- replent.nvim – plugin entrypoint
---
--- Neovim sources every file under plugin/ at startup, but this file does
--- almost nothing at that point: it only registers a single FileType
--- autocommand. The heavy modules (julia.lua, python.lua, tmux.lua …) are
--- required lazily inside that callback, so the plugin has zero cost for
--- filetypes that don't match.

if vim.g.loaded_replent then return end
vim.g.loaded_replent = true

require("replent.config").setup()

vim.api.nvim_create_augroup("replent", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
    group   = "replent",
    pattern = "*",
    callback = function(args)
        local cfg = require("replent.config").options
        local ft  = vim.bo[args.buf].filetype

        local active = false
        for _, allowed in ipairs(cfg.filetypes) do
            if ft == allowed then active = true; break end
        end
        if not active then return end

        require("replent.keymaps").attach()
    end,
})
