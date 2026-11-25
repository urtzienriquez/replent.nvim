-- tests/noweb_spec.lua
-- jnoweb documents: <CR> sends a chunk from its header, the Julia there from inside it, nothing from
-- the LaTeX around chunks (the cursor goes to the next chunk); <leader>sb, the chunks' code.

local assert = require("luassert")
local h = require("tests.helpers")
local noweb = require("replent.noweb")
local actions = require("replent.actions")

local DOC = {
  "\\documentclass{article}", --  1
  "\\begin{document}", --         2
  "Some prose.", --               3
  "<<setup>>=", --                4
  "x = 1", --                     5
  "function f(a)", --             6
  "  a + 1", --                   7
  "end", --                       8
  "@", --                         9
  "More prose with \\Sexpr{x}.", -- 10
  "<<empty, child='c.jnw'>>=", -- 11
  "@", --                         12
  "<<plot>>=", --                 13
  "y = f(x)", --                  14
  "@", --                         15
  "\\end{document}", --           16
}

describe("noweb chunks", function()
  local buf
  after_each(function()
    h.cleanup(buf)
  end)

  it("finds the chunk a line is in, or whose header it is; none on prose or @", function()
    buf = h.make_buf("jnoweb", DOC)
    assert.same({ header = 4, first = 5, last = 8, close = 9 }, noweb.chunk_at(buf, 4))
    assert.same({ header = 4, first = 5, last = 8, close = 9 }, noweb.chunk_at(buf, 7))
    assert.is_nil(noweb.chunk_at(buf, 3))
    assert.is_nil(noweb.chunk_at(buf, 9))
    assert.is_nil(noweb.chunk_at(buf, 10))
    assert.same({ header = 11, first = 12, last = 11, close = 12 }, noweb.chunk_at(buf, 11)) -- (empty)
    assert.equals(13, noweb.next_header(buf, 11))
    assert.equals(4, noweb.next_header(buf, 11, true))
  end)

  it("<CR>: the chunk from its header, a block inside it, nothing on prose", function()
    buf = h.make_buf("jnoweb", DOC)
    h.set_cursor(4)
    local text, s, e, go = noweb.get_send_text()
    assert.equals("x = 1\nfunction f(a)\n  a + 1\nend", text)
    assert.same({ 5, 8, 10 }, { s, e, go })
    h.set_cursor(6)
    text, s, e = noweb.get_send_text()
    assert.equals("function f(a)\n  a + 1\nend", text)
    assert.same({ 6, 8 }, { s, e })
    h.set_cursor(3)
    text, s, e, go = noweb.get_send_text()
    assert.is_nil(text)
    assert.equals(4, go) -- (the next chunk)
  end)

  it("send_block sends and moves on; send_buffer sends only the code", function()
    buf = h.make_buf("jnoweb", DOC)
    local sent = {}
    local real = actions.slime_send
    actions.slime_send = function(t) sent[#sent + 1] = t end
    h.set_cursor(3)
    actions.send_block() -- (prose: to the next chunk, nothing sent)
    assert.same({}, sent)
    assert.equals(4, vim.api.nvim_win_get_cursor(0)[1])
    actions.send_block() -- (its header: the chunk; then after it)
    assert.equals("x = 1\nfunction f(a)\n  a + 1\nend\n", sent[1])
    assert.equals(10, vim.api.nvim_win_get_cursor(0)[1])
    sent = {}
    actions.send_buffer()
    assert.equals("x = 1\nfunction f(a)\n  a + 1\nend\ny = f(x)\n", sent[1])
    actions.slime_send = real
  end)
end)
