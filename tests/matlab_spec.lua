-- tests/matlab_spec.lua
-- Tests for lua/replent/matlab.lua block/statement detection.
--
-- These exercise the bug that motivated the rewrite: the old inline
-- detection scanned for `%%` cell markers using the Lua pattern "^%%", which
-- (since `%` escapes in Lua patterns) actually matched *any* single `%`
-- comment line, causing a stray comment to be treated as a cell boundary and
-- the whole buffer above/below to be sent. matlab.lua replaces that with
-- Julia-style block detection.

local assert = require("luassert")
local h = require("tests.helpers")
local matlab = require("replent.matlab")

describe("matlab.get_send_text: plain statements", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("sends a single top-level statement as itself", function()
    buf = h.make_buf("matlab", { "x = 1;", "y = 2;" })
    h.set_cursor(1)
    local text, s, e = matlab.get_send_text()
    assert.equals("x = 1;", text)
    assert.equals(1, s)
    assert.equals(1, e)
  end)

  it("returns nil for a blank line", function()
    buf = h.make_buf("matlab", { "x = 1;", "", "y = 2;" })
    h.set_cursor(2)
    local text, s, e = matlab.get_send_text()
    assert.is_nil(text)
    assert.equals(2, s)
    assert.equals(2, e)
  end)

  it("sends a standalone '%' comment line as itself, not as a cell boundary", function()
    buf = h.make_buf("matlab", { "x = 1;", "% just a comment", "y = 2;" })
    h.set_cursor(2)
    local text, s, e = matlab.get_send_text()
    assert.equals("% just a comment", text)
    assert.equals(2, s)
    assert.equals(2, e)
  end)

  it("regression: a comment line does not cause the whole file above to be sent", function()
    buf = h.make_buf("matlab", {
      "a = 1;", -- 1
      "b = 2;", -- 2
      "c = 3;", -- 3
      "% a comment right before the target line", -- 4
      "d = 4;", -- 5
    })
    h.set_cursor(4)
    local text, s, e = matlab.get_send_text()
    assert.equals("% a comment right before the target line", text)
    assert.equals(4, s)
    assert.equals(4, e)
  end)

  it("regression: a comment line does not cause the whole file below to be sent", function()
    buf = h.make_buf("matlab", {
      "a = 1;", -- 1
      "% a comment", -- 2
      "c = 3;", -- 3
      "d = 4;", -- 4
      "e = 5;", -- 5
    })
    h.set_cursor(2)
    local text, s, e = matlab.get_send_text()
    assert.equals("% a comment", text)
    assert.equals(2, s)
    assert.equals(2, e)
  end)

  it("does not treat 'end'-prefixed identifiers as a block end", function()
    buf = h.make_buf("matlab", { "endpoints = 5;" })
    h.set_cursor(1)
    local text, s, e = matlab.get_send_text()
    assert.equals("endpoints = 5;", text)
    assert.equals(1, s)
    assert.equals(1, e)
  end)

  it("does not treat a 'for'-prefixed identifier as a block start", function()
    buf = h.make_buf("matlab", { "format long" })
    h.set_cursor(1)
    local text, s, e = matlab.get_send_text()
    assert.equals("format long", text)
    assert.equals(1, s)
    assert.equals(1, e)
  end)
end)

describe("matlab.get_send_text: function blocks", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  local function make_function_buf()
    return h.make_buf("matlab", {
      "function y = f(x)", -- 1
      "  y = x + 1;", -- 2
      "end", -- 3
      "", -- 4
      "z = f(3);", -- 5
    })
  end

  it("sends the whole block when cursor is on the function header", function()
    buf = make_function_buf()
    h.set_cursor(1)
    local text, s, e = matlab.get_send_text()
    assert.equals(1, s)
    assert.equals(3, e)
    assert.equals("function y = f(x)\n  y = x + 1;\nend", text)
  end)

  it("sends the whole block when cursor is inside the body", function()
    buf = make_function_buf()
    h.set_cursor(2)
    local _, s, e = matlab.get_send_text()
    assert.equals(1, s)
    assert.equals(3, e)
  end)

  it("sends only the 'end' line when cursor is on it", function()
    buf = make_function_buf()
    h.set_cursor(3)
    local text, s, e = matlab.get_send_text()
    assert.equals("end", text)
    assert.equals(3, s)
    assert.equals(3, e)
  end)

  it("does not include unrelated code after the block", function()
    buf = make_function_buf()
    h.set_cursor(1)
    local _, _, e = matlab.get_send_text()
    assert.is_true(e < 5)
  end)
end)

describe("matlab.get_send_text: nested blocks", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  local function make_nested_buf()
    return h.make_buf("matlab", {
      "for i = 1:10", -- 1
      "  if mod(i, 2) == 0", -- 2
      "    disp(i)", -- 3
      "  end", -- 4
      "  x = i;", -- 5
      "end", -- 6
    })
  end

  it("sends only the inner block when cursor is on the inner header", function()
    buf = make_nested_buf()
    h.set_cursor(2)
    local _, s, e = matlab.get_send_text()
    assert.equals(2, s)
    assert.equals(4, e)
  end)

  it("sends the whole outer block when cursor is on the outer header", function()
    buf = make_nested_buf()
    h.set_cursor(1)
    local _, s, e = matlab.get_send_text()
    assert.equals(1, s)
    assert.equals(6, e)
  end)

  it("sends the whole outer block when cursor is after the inner block", function()
    buf = make_nested_buf()
    h.set_cursor(5)
    local _, s, e = matlab.get_send_text()
    assert.equals(1, s)
    assert.equals(6, e)
  end)
end)

describe("matlab.get_send_text: comments inside blocks", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("does not break block detection when a comment sits inside the body", function()
    buf = h.make_buf("matlab", {
      "function y = f(x)",
      "  % a comment about x",
      "  y = x + 1;",
      "end",
    })
    h.set_cursor(1)
    local _, s, e = matlab.get_send_text()
    assert.equals(1, s)
    assert.equals(4, e)
  end)

  it("a comment mentioning 'end' inside a block does not close the block early", function()
    buf = h.make_buf("matlab", {
      "for i = 1:10", -- 1
      "  % loop until the end", -- 2
      "  disp(i)", -- 3
      "end", -- 4
    })
    h.set_cursor(1)
    local _, s, e = matlab.get_send_text()
    assert.equals(1, s)
    assert.equals(4, e)
  end)
end)

describe("matlab.get_send_text: other block keywords", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  local cases = {
    { name = "if", lines = { "if x > 0", "  disp('pos')", "end" } },
    { name = "while", lines = { "while true", "  break", "end" } },
    { name = "switch", lines = { "switch x", "  case 1", "    disp(1)", "end" } },
    { name = "try/catch", lines = { "try", "  risky()", "catch err", "  handle(err)", "end" } },
    { name = "parfor", lines = { "parfor i = 1:10", "  f(i)", "end" } },
    { name = "classdef", lines = { "classdef Foo", "  properties", "    x", "  end", "end" } },
  }

  for _, case in ipairs(cases) do
    it("sends the whole '" .. case.name .. "' block from its header", function()
      buf = h.make_buf("matlab", case.lines)
      h.set_cursor(1)
      local _, s, e = matlab.get_send_text()
      assert.equals(1, s)
      assert.equals(#case.lines, e)
      h.cleanup(buf)
      buf = nil
    end)
  end
end)

describe("matlab.get_send_text: %% cell markers are not treated specially", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("sends only the current statement inside a %% cell, not the whole cell", function()
    buf = h.make_buf("matlab", {
      "%% Section 1", -- 1
      "a = 1;", -- 2
      "b = 2;", -- 3
      "%% Section 2", -- 4
      "c = 3;", -- 5
    })
    h.set_cursor(2)
    local text, s, e = matlab.get_send_text()
    assert.equals("a = 1;", text)
    assert.equals(2, s)
    assert.equals(2, e)
  end)

  it("treats a %% marker line itself as an ordinary comment line", function()
    buf = h.make_buf("matlab", { "%% Section 1", "a = 1;" })
    h.set_cursor(1)
    local text, s, e = matlab.get_send_text()
    assert.equals("%% Section 1", text)
    assert.equals(1, s)
    assert.equals(1, e)
  end)

  it("a function spanning a %% marker still sends the whole function body", function()
    buf = h.make_buf("matlab", {
      "%% Section", -- 1
      "function y = f(x)", -- 2
      "  y = x + 1;", -- 3
      "end", -- 4
    })
    h.set_cursor(2)
    local _, s, e = matlab.get_send_text()
    assert.equals(2, s)
    assert.equals(4, e)
  end)
end)

describe("matlab.get_send_text: sibling blocks", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("does not bleed into an unrelated preceding function", function()
    buf = h.make_buf("matlab", {
      "function f()",
      "  1;",
      "end",
      "function g()",
      "  2;",
      "end",
    })
    h.set_cursor(4)
    local _, s, e = matlab.get_send_text()
    assert.equals(4, s)
    assert.equals(6, e)
  end)

  it("does not bleed into an unrelated following function", function()
    buf = h.make_buf("matlab", {
      "function f()",
      "  1;",
      "end",
      "function g()",
      "  2;",
      "end",
    })
    h.set_cursor(1)
    local _, s, e = matlab.get_send_text()
    assert.equals(1, s)
    assert.equals(3, e)
  end)
end)

describe("matlab.get_send_text: edge cases", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("returns nil for an empty buffer", function()
    buf = h.make_buf("matlab", { "" })
    h.set_cursor(1)
    local text = matlab.get_send_text()
    assert.is_nil(text)
  end)

  it("handles an unterminated block start (no matching end) gracefully", function()
    buf = h.make_buf("matlab", { "function y = f(x)", "  y = x + 1;" })
    h.set_cursor(1)
    local text, s, e = matlab.get_send_text()
    assert.equals("function y = f(x)", text)
    assert.equals(1, s)
    assert.equals(1, e)
  end)
end)
