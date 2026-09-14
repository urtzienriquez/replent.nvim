-- tests/python_spec.lua
-- Tests for lua/replent/python.lua block/statement detection.

local assert = require("luassert")
local h = require("tests.helpers")
local python = require("replent.python")

describe("python.get_send_text: plain statements", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("sends a single top-level statement as itself", function()
    buf = h.make_buf("python", { "x = 1", "y = 2" })
    h.set_cursor(1)
    local text, s, e = python.get_send_text()
    assert.equals("x = 1", text)
    assert.equals(1, s)
    assert.equals(1, e)
  end)

  it("returns nil for a blank line", function()
    buf = h.make_buf("python", { "x = 1", "", "y = 2" })
    h.set_cursor(2)
    local text, s, e = python.get_send_text()
    assert.is_nil(text)
    assert.equals(2, s)
    assert.equals(2, e)
  end)

  it("returns nil for a whitespace-only line", function()
    buf = h.make_buf("python", { "x = 1", "   ", "y = 2" })
    h.set_cursor(2)
    local text = python.get_send_text()
    assert.is_nil(text)
  end)

  it("sends a standalone comment line instead of skipping it", function()
    buf = h.make_buf("python", { "x = 1", "# a comment", "y = 2" })
    h.set_cursor(2)
    local text, s, e = python.get_send_text()
    assert.equals("# a comment", text)
    assert.equals(2, s)
    assert.equals(2, e)
  end)

  it("sends an indented comment line as itself", function()
    buf = h.make_buf("python", { "if True:", "    # note", "    pass" })
    h.set_cursor(2)
    -- The comment on its own is inside the `if` block; get_send_text keys off
    -- the *current line*, and a comment line short-circuits to itself.
    local text, s, e = python.get_send_text()
    assert.equals("    # note", text)
    assert.equals(2, s)
    assert.equals(2, e)
  end)
end)

describe("python.get_send_text: def/class blocks", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  local function make_def_buf()
    return h.make_buf("python", {
      "def f(x):", -- 1
      "    y = x + 1", -- 2
      "    return y", -- 3
      "", -- 4
      "z = f(1)", -- 5
    })
  end

  it("sends the whole block when cursor is on the def header", function()
    buf = make_def_buf()
    h.set_cursor(1)
    local text, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(3, e)
    assert.equals("def f(x):\n    y = x + 1\n    return y", text)
  end)

  it("sends the whole block when cursor is inside the body", function()
    buf = make_def_buf()
    h.set_cursor(2)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(3, e)
  end)

  it("does not include the trailing blank line or following code", function()
    buf = make_def_buf()
    h.set_cursor(1)
    local _, _, e = python.get_send_text()
    assert.equals(3, e)
  end)

  it("recognizes class blocks", function()
    buf = h.make_buf("python", { "class Foo:", "    x = 1", "    y = 2" })
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(3, e)
  end)

  it("requires a trailing colon to treat a line as a block header", function()
    -- `def f(x)` without a colon (e.g. mid-multiline-signature) must not be
    -- misdetected as a block start.
    buf = h.make_buf("python", { "def f(x)", "y = 1" })
    h.set_cursor(1)
    local text, s, e = python.get_send_text()
    assert.equals("def f(x)", text)
    assert.equals(1, s)
    assert.equals(1, e)
  end)

  it("treats a colon followed by a trailing comment as a valid block header", function()
    buf = h.make_buf("python", { "if True:  # start", "    pass" })
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(2, e)
  end)
end)

describe("python.get_send_text: control flow keywords", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("sends an if/elif/else chain as separate blocks per header", function()
    buf = h.make_buf("python", {
      "if x:", -- 1
      "    a()", -- 2
      "elif y:", -- 3
      "    b()", -- 4
      "else:", -- 5
      "    c()", -- 6
    })
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(2, e)

    h.set_cursor(3)
    _, s, e = python.get_send_text()
    assert.equals(3, s)
    assert.equals(4, e)

    h.set_cursor(5)
    _, s, e = python.get_send_text()
    assert.equals(5, s)
    assert.equals(6, e)
  end)

  it("handles try/except/finally", function()
    buf = h.make_buf("python", {
      "try:", -- 1
      "    risky()", -- 2
      "except ValueError:", -- 3
      "    handle()", -- 4
      "finally:", -- 5
      "    cleanup()", -- 6
    })
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(2, e)
  end)

  it("handles for/while loops", function()
    buf = h.make_buf("python", { "for i in range(10):", "    print(i)" })
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(2, e)
  end)

  it("handles with statements", function()
    buf = h.make_buf("python", { "with open('f') as fh:", "    data = fh.read()" })
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(2, e)
  end)

  it("handles match/case", function()
    buf = h.make_buf("python", {
      "match command:", -- 1
      "    case 'go':", -- 2
      "        move()", -- 3
      "    case _:", -- 4
      "        pass", -- 5
    })
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(5, e)
  end)

  it("handles decorators as block starts spanning the decorated function", function()
    buf = h.make_buf("python", {
      "@decorator", -- 1
      "def f():", -- 2
      "    pass", -- 3
    })
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    -- The decorator line itself isn't colon-terminated, so it is not treated
    -- as a block start; it is sent on its own.
    assert.equals(1, s)
    assert.equals(1, e)
  end)
end)

describe("python.get_send_text: nested blocks and indentation", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  local function make_nested_buf()
    return h.make_buf("python", {
      "def outer():", -- 1
      "    if True:", -- 2
      "        inner()", -- 3
      "    x = 1", -- 4
      "", -- 5
      "y = 2", -- 6
    })
  end

  it("sends only the inner block from its header", function()
    buf = make_nested_buf()
    h.set_cursor(2)
    local _, s, e = python.get_send_text()
    assert.equals(2, s)
    assert.equals(3, e)
  end)

  it("sends only the inner block from inside its body", function()
    buf = make_nested_buf()
    h.set_cursor(3)
    local _, s, e = python.get_send_text()
    assert.equals(2, s)
    assert.equals(3, e)
  end)

  it("sends the whole outer block from its header", function()
    buf = make_nested_buf()
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(4, e)
  end)

  it("resolves the owning outer block from a dedented line inside it", function()
    buf = make_nested_buf()
    h.set_cursor(4)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(4, e)
  end)

  it("does not pull in top-level code after the function", function()
    buf = make_nested_buf()
    h.set_cursor(1)
    local _, _, e = python.get_send_text()
    assert.is_true(e < 6)
  end)
end)

describe("python.get_send_text: blank/comment absorption", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("absorbs interior blank lines that are followed by more block body", function()
    buf = h.make_buf("python", {
      "def f():", -- 1
      "    a = 1", -- 2
      "", -- 3 (blank, still inside the block)
      "    b = 2", -- 4
    })
    h.set_cursor(1)
    local text, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(4, e)
    assert.equals("def f():\n    a = 1\n\n    b = 2", text)
  end)

  it("absorbs interior comment lines that are followed by more block body", function()
    buf = h.make_buf("python", {
      "def f():",
      "    a = 1",
      "    # explains b",
      "    b = 2",
    })
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(4, e)
  end)

  it("does NOT absorb a trailing top-level comment after the block ends", function()
    buf = h.make_buf("python", {
      "def f():", -- 1
      "    a = 1", -- 2
      "", -- 3
      "# unrelated top-level comment", -- 4
      "g()", -- 5
    })
    h.set_cursor(1)
    local text, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(2, e)
    assert.equals("def f():\n    a = 1", text)
  end)

  it("does NOT absorb a trailing blank line with nothing indented after it", function()
    buf = h.make_buf("python", {
      "def f():", -- 1
      "    a = 1", -- 2
      "", -- 3
      "g()", -- 4
    })
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(2, e)
  end)

  it("stops at the last real code line when the block is at end of file", function()
    buf = h.make_buf("python", {
      "def f():",
      "    a = 1",
      "",
      "# trailing comment, no more code follows",
    })
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(2, e)
  end)
end)

describe("python.get_send_text: sibling blocks", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("does not bleed into an unrelated following def", function()
    buf = h.make_buf("python", {
      "def f():",
      "    1",
      "",
      "def g():",
      "    2",
    })
    h.set_cursor(1)
    local _, s, e = python.get_send_text()
    assert.equals(1, s)
    assert.equals(2, e)
  end)

  it("does not bleed into an unrelated preceding def", function()
    buf = h.make_buf("python", {
      "def f():",
      "    1",
      "",
      "def g():",
      "    2",
    })
    h.set_cursor(4)
    local _, s, e = python.get_send_text()
    assert.equals(4, s)
    assert.equals(5, e)
  end)
end)

describe("python.get_send_text: edge cases", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("returns nil for an empty buffer", function()
    buf = h.make_buf("python", { "" })
    h.set_cursor(1)
    local text = python.get_send_text()
    assert.is_nil(text)
  end)

  it("handles a block header at the very end of the file (no body)", function()
    buf = h.make_buf("python", { "x = 1", "def f():" })
    h.set_cursor(2)
    local text, s, e = python.get_send_text()
    assert.equals("def f():", text)
    assert.equals(2, s)
    assert.equals(2, e)
  end)
end)
