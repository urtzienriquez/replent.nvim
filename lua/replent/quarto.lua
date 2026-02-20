--- replent.nvim – Quarto language detection
---
--- Quarto files can contain Python, Julia, R, or MATLAB chunks.
--- We peek at the first executable code chunk to decide which REPL to use.
--- The detected language is cached per-buffer so the scan only runs once.

local M = {}

--- Cache: bufnr → detected language string ("python"|"julia"|"matlab"|nil)
local cache = {}

--- Clear the cache entry for a buffer (called on BufUnload).
local function clear_cache(bufnr)
    cache[bufnr] = nil
end

vim.api.nvim_create_autocmd("BufUnload", {
    group = vim.api.nvim_create_augroup("replent_quarto_cache", { clear = true }),
    callback = function(args) clear_cache(args.buf) end,
})

--- Languages replent can handle in Quarto files.
local SUPPORTED = { python = true, julia = true, matlab = true }

--- Scan the first ~200 lines of the buffer for a ```{lang} chunk opener
--- and return the language if it's one replent supports, otherwise nil.
---@param bufnr integer
---@return string|nil
local function detect_from_buffer(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 200, false)
    for _, line in ipairs(lines) do
        -- matches ```{python}, ```{python #label}, ```{julia opts}, etc.
        local lang = line:match("^%s*```{(%a+)")
        if lang and SUPPORTED[lang:lower()] then
            return lang:lower()
        end
    end
    return nil
end

--- Return the primary language for a Quarto buffer (cached).
---@param bufnr? integer defaults to current buffer
---@return string|nil  "python" | "julia" | "matlab" | nil
function M.detect(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if cache[bufnr] ~= nil then
        -- nil means "already scanned, nothing found" – store as false to
        -- distinguish from "not yet scanned".
        return cache[bufnr] or nil
    end

    local lang = detect_from_buffer(bufnr)
    cache[bufnr] = lang or false   -- false = scanned, not found
    return lang
end

--- Return true when the filetype is quarto and a supported language was found.
---@param bufnr? integer
---@return boolean
function M.is_active(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    return vim.bo[bufnr].filetype == "quarto" and M.detect(bufnr) ~= nil
end

return M
