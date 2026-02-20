--- replent.nvim – Python block detection
--- Ported from the user's python_utils.lua

local M = {}

local BLOCK_START_PATTERNS = {
    "^%s*def%s+",
    "^%s*class%s+",
    "^%s*if%s+",
    "^%s*elif%s+",
    "^%s*else%s*:",
    "^%s*for%s+",
    "^%s*while%s+",
    "^%s*try%s*:",
    "^%s*except",
    "^%s*finally%s*:",
    "^%s*with%s+",
    "^%s*match%s+",
    "^%s*case%s+",
    "^%s*@",
}

local function is_block_start(line)
    -- Python blocks must end with a colon (optionally followed by a comment)
    if not (line:match(":%s*$") or line:match(":%s*#")) then return false end
    for _, pat in ipairs(BLOCK_START_PATTERNS) do
        if line:match(pat) then return true end
    end
    return false
end

local function indent(line)
    return #(line:match("^(%s*)"))
end

local function is_empty(line)  return line:match("^%s*$") ~= nil end
local function is_comment(line) return line:match("^%s*#") ~= nil end

--- Return (start_line, end_line) 1-indexed for the block at start_line.
---@param bufnr integer
---@param start_line integer
---@return integer, integer
function M.get_block_range(bufnr, start_line)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    start_line = start_line or vim.api.nvim_win_get_cursor(0)[1]

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if #lines == 0 then return start_line, start_line end
    if start_line < 1 or start_line > #lines then return start_line, start_line end

    local cur = lines[start_line]
    if not cur then return start_line, start_line end
    if is_empty(cur) or is_comment(cur) then return start_line, start_line end

    local cur_indent = indent(cur)

    -- On a block start – collect all indented lines below
    if is_block_start(cur) then
        local end_line = start_line
        for i = start_line + 1, #lines do
            local l = lines[i]
            if l then
                if is_empty(l) or is_comment(l) then
                    end_line = i
                elseif indent(l) > cur_indent then
                    end_line = i
                else
                    break
                end
            end
        end
        return start_line, end_line
    end

    -- Inside a block – find the owning block-start backwards
    local block_start = start_line
    for i = start_line - 1, 1, -1 do
        local l = lines[i]
        if l and not is_empty(l) and not is_comment(l) then
            if indent(l) < cur_indent then
                if is_block_start(l) then block_start = i end
                break
            end
        end
    end

    if block_start < start_line then
        local bs_indent = indent(lines[block_start])
        local end_line = block_start
        for i = block_start + 1, #lines do
            local l = lines[i]
            if l then
                if is_empty(l) or is_comment(l) then
                    end_line = i
                elseif indent(l) > bs_indent then
                    end_line = i
                else
                    break
                end
            end
        end
        return block_start, end_line
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
    if is_empty(cur) or is_comment(cur) then return nil, cursor_line, cursor_line end

    local s, e = M.get_block_range(bufnr, cursor_line)
    if s == e then return cur, s, e end

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
        "[replent/python] line %d: %q\n  indent=%d  is_block_start=%s  empty=%s  comment=%s",
        cursor_line, cur or "",
        cur and #(cur:match("^(%s*)")) or 0,
        tostring(is_block_start(cur or "")),
        tostring(is_empty(cur or "")),
        tostring(is_comment(cur or ""))
    ))

    local s, e = M.get_block_range(bufnr, cursor_line)
    vim.notify(string.format("[replent/python] block range: %d → %d", s, e))
end

return M
