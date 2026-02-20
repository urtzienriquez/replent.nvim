--- replent.nvim – Julia block detection
--- Ported from the user's julia_utils.lua

local M = {}

local BLOCK_START = {
    "^%s*function%s+",
    "^%s*function%s*%(", -- anonymous functions
    "^%s*macro%s+",
    "^%s*for%s+",
    "^%s*while%s+",
    "^%s*if%s+",
    "^%s*begin",
    "^%s*let%s+",
    "^%s*let%s*$",
    "^%s*module%s+",
    "^%s*struct%s+",
    "^%s*mutable%s+struct%s+",
    "^%s*abstract%s+type%s+",
    "^%s*quote%s*$",
    "^%s*try%s*$",
    "^%s*@testset",
}

local BLOCK_END = "^%s*end"

local function is_block_start(line)
    for _, pat in ipairs(BLOCK_START) do
        if line:match(pat) then return true end
    end
    return false
end

local function is_block_end(line)
    return line:match(BLOCK_END) ~= nil
end

--- Return (start_line, end_line) 1-indexed for the block at start_line.
---@param bufnr integer
---@param start_line integer 1-indexed
---@return integer, integer
function M.get_block_range(bufnr, start_line)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    start_line = start_line or vim.api.nvim_win_get_cursor(0)[1]

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if #lines == 0 then return start_line, start_line end
    if start_line < 1 or start_line > #lines then return start_line, start_line end

    local current_line = lines[start_line]
    if not current_line then return start_line, start_line end

    -- On a block start – find matching end
    if is_block_start(current_line) then
        local depth = 1
        for i = start_line + 1, #lines do
            local l = lines[i]
            if l then
                if is_block_start(l) then depth = depth + 1
                elseif is_block_end(l) then
                    depth = depth - 1
                    if depth == 0 then return start_line, i end
                end
            end
        end
        return start_line, start_line
    end

    -- On a block end – return just this line
    if is_block_end(current_line) then return start_line, start_line end

    -- Inside a block – search backwards for the owning start
    local block_start = nil
    local depth = 0
    for i = start_line - 1, 1, -1 do
        local l = lines[i]
        if l then
            if is_block_end(l) then
                depth = depth + 1
            elseif is_block_start(l) then
                if depth == 0 then
                    block_start = i
                    break
                else
                    depth = depth - 1
                end
            end
        end
    end

    if block_start then
        depth = 1
        for i = block_start + 1, #lines do
            local l = lines[i]
            if l then
                if is_block_start(l) then depth = depth + 1
                elseif is_block_end(l) then
                    depth = depth - 1
                    if depth == 0 then
                        if start_line >= block_start and start_line <= i then
                            return block_start, i
                        end
                        break
                    end
                end
            end
        end
    end

    return start_line, start_line
end

--- Return (text, start_line, end_line) for the block at the cursor.
---@return string|nil, integer, integer
function M.get_send_text()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    if #lines == 0 then return nil, cursor_line, cursor_line end
    if cursor_line < 1 or cursor_line > #lines then return nil, cursor_line, cursor_line end

    local cur = lines[cursor_line]
    if not cur then return nil, cursor_line, cursor_line end
    if cur:match("^%s*$") then return nil, cursor_line, cursor_line end

    local s, e = M.get_block_range(bufnr, cursor_line)
    if s == e then
        return cur, s, e
    end
    local block = vim.api.nvim_buf_get_lines(bufnr, s - 1, e, false)
    return table.concat(block, "\n"), s, e
end

--- Print debug info about block detection at the cursor.
function M.debug()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    if #lines == 0 then vim.notify("[replent] Buffer is empty") return end

    local cur = lines[cursor_line]
    vim.notify(string.format(
        "[replent/julia] line %d: %q\n  is_block_start=%s  is_block_end=%s",
        cursor_line, cur or "",
        tostring(is_block_start(cur or "")),
        tostring(is_block_end(cur or ""))
    ))

    local s, e = M.get_block_range(bufnr, cursor_line)
    vim.notify(string.format("[replent/julia] block range: %d → %d", s, e))
end

return M
