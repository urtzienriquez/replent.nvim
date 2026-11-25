-- Noweb documents (jnoweb: LaTeX with Julia chunks, <<...>>= to @): what <CR> sends, as R.nvim does
-- in Rnoweb. On a chunk's header, the chunk; inside it, the Julia block or line there (never past the
-- chunk); on the LaTeX around chunks, nothing: the cursor goes to the next chunk.
local M = {}

local BEGIN = "^%s*<<.*>>=%s*$"
local END = "^%s*@%s*$"

--- The chunk line `line` (1-based) is in, or whose header it is: { header, first, last (its code
--- lines), close (its @ line, or nil) }; nil on the LaTeX around chunks (or on an @ line).
---@param bufnr integer
---@param line integer
---@return table|nil
function M.chunk_at(bufnr, line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if (lines[line] or ""):match(END) then
    return nil
  end
  for i = line, 1, -1 do
    if lines[i]:match(BEGIN) then
      local close
      for j = i + 1, #lines do
        if lines[j]:match(END) then
          close = j
          break
        end
        if lines[j]:match(BEGIN) then
          break
        end
      end
      if close and close < line then
        return nil
      end
      return { header = i, first = i + 1, last = (close or #lines + 1) - 1, close = close }
    end
    if i < line and lines[i]:match(END) then
      return nil
    end
  end
  return nil
end

--- The header line of the next chunk after `line` (or the previous one, `backward`), or nil.
function M.next_header(bufnr, line, backward)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local from, to, step = line + 1, #lines, 1
  if backward then
    from, to, step = line - 1, 1, -1
  end
  for i = from, to, step do
    if lines[i]:match(BEGIN) then
      return i
    end
  end
  return nil
end

--- What <CR> sends at the cursor: text, first and last line sent, and where the cursor goes after.
--- On prose: nil (and the next chunk's header to go to).
function M.get_send_text()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local chunk = M.chunk_at(bufnr, line)
  if not chunk then
    return nil, line, line, M.next_header(bufnr, line)
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, chunk.first - 1, chunk.last, false)
  local after = (chunk.close or chunk.last) + 1
  if line == chunk.header then -- (the whole chunk)
    return table.concat(lines, "\n"), chunk.first, chunk.last, after
  end
  local text, s, e = require("replent.julia").get_send_text()
  if s and e and (s < chunk.first or e > chunk.last) then -- (never past the chunk)
    s, e = math.max(s, chunk.first), math.min(e, chunk.last)
    text = table.concat(vim.api.nvim_buf_get_lines(bufnr, s - 1, e, false), "\n")
  end
  return text, s, e, (e or line) >= chunk.last and after or nil
end

--- The code of all chunks (what <leader>sb sends: not the LaTeX), in order.
function M.all_code(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local out, inside = {}, false
  for _, l in ipairs(lines) do
    if inside and l:match(END) then
      inside = false
    elseif inside then
      out[#out + 1] = l
    elseif l:match(BEGIN) then
      inside = true
    end
  end
  return table.concat(out, "\n")
end

return M
