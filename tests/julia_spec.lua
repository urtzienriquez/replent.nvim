-- tests/julia_spec.lua
-- Tests for lua/replent/julia.lua block/statement detection.

local assert = require("luassert")
local h = require("tests.helpers")
local julia = require("replent.julia")

describe("julia.get_send_text: plain statements", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("sends a single top-level statement as itself", function()
    buf = h.make_buf("julia", { "x = 1", "y = 2" })
    h.set_cursor(1)
    local text, s, e = julia.get_send_text()
    assert.equals("x = 1", text)
    assert.equals(1, s)
    assert.equals(1, e)
  end)

  it("returns nil for a blank line", function()
    buf = h.make_buf("julia", { "x = 1", "", "y = 2" })
    h.set_cursor(2)
    local text, s, e = julia.get_send_text()
    assert.is_nil(text)
    assert.equals(2, s)
    assert.equals(2, e)
  end)

  it("returns nil for a whitespace-only line", function()
    buf = h.make_buf("julia", { "x = 1", "   ", "y = 2" })
    h.set_cursor(2)
    local text = julia.get_send_text()
    assert.is_nil(text)
  end)

  it("sends a standalone comment line as itself (comments are not blank)", function()
    buf = h.make_buf("julia", { "x = 1", "# a comment", "y = 2" })
    h.set_cursor(2)
    local text, s, e = julia.get_send_text()
    assert.equals("# a comment", text)
    assert.equals(2, s)
    assert.equals(2, e)
  end)

  it("does not treat 'end'-prefixed identifiers as a block end", function()
    buf = h.make_buf("julia", { "endpoints = 5" })
    h.set_cursor(1)
    local text, s, e = julia.get_send_text()
    assert.equals("endpoints = 5", text)
    assert.equals(1, s)
    assert.equals(1, e)
  end)

  it("does not treat a 'for'-prefixed identifier as a block start", function()
    buf = h.make_buf("julia", { "forward = 1" })
    h.set_cursor(1)
    local text, s, e = julia.get_send_text()
    assert.equals("forward = 1", text)
    assert.equals(1, s)
    assert.equals(1, e)
  end)
end)

describe("julia.get_send_text: function blocks", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  local function make_function_buf()
    return h.make_buf("julia", {
      "function f(x)",
      "    y = x + 1",
      "    return y",
      "end",
      "",
      "z = f(1)",
    })
  end

  it("sends the whole block when cursor is on the function header", function()
    buf = make_function_buf()
    h.set_cursor(1)
    local text, s, e = julia.get_send_text()
    assert.equals(1, s)
    assert.equals(4, e)
    assert.equals("function f(x)\n    y = x + 1\n    return y\nend", text)
  end)

  it("sends the whole block when cursor is inside the body", function()
    buf = make_function_buf()
    h.set_cursor(3)
    local _, s, e = julia.get_send_text()
    assert.equals(1, s)
    assert.equals(4, e)
  end)

  it("sends only the 'end' line when cursor is on it", function()
    buf = make_function_buf()
    h.set_cursor(4)
    local text, s, e = julia.get_send_text()
    assert.equals("end", text)
    assert.equals(4, s)
    assert.equals(4, e)
  end)

  it("does not include unrelated code after the block", function()
    buf = make_function_buf()
    h.set_cursor(1)
    local _, _, e = julia.get_send_text()
    assert.is_true(e < 6)
  end)

  it("recognizes anonymous function syntax 'function(x)'", function()
    buf = h.make_buf("julia", {
      "f = function(x)",
      "    x + 1",
      "end",
    })
    h.set_cursor(1)
    local _, s, e = julia.get_send_text()
    -- anonymous function assigned via `f = function(x)` doesn't start the
    -- line with `function`, so it's treated as a plain statement unless the
    -- line itself begins with the keyword.
    assert.equals(1, s)
    assert.equals(1, e)
  end)

  it("recognizes a bare 'function(x)' block start", function()
    buf = h.make_buf("julia", {
      "function(x)",
      "    x + 1",
      "end",
    })
    h.set_cursor(1)
    local _, s, e = julia.get_send_text()
    assert.equals(1, s)
    assert.equals(3, e)
  end)
end)

describe("julia.get_send_text: nested blocks", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  local function make_nested_buf()
    return h.make_buf("julia", {
      "for i in 1:10", -- 1
      "    if i > 5", -- 2
      "        println(i)", -- 3
      "    end", -- 4
      "    x = i", -- 5
      "end", -- 6
    })
  end

  it("sends only the inner block when cursor is on the inner header", function()
    buf = make_nested_buf()
    h.set_cursor(2)
    local _, s, e = julia.get_send_text()
    assert.equals(2, s)
    assert.equals(4, e)
  end)

  it("sends only the inner block when cursor is inside the inner body", function()
    buf = make_nested_buf()
    h.set_cursor(3)
    local _, s, e = julia.get_send_text()
    assert.equals(2, s)
    assert.equals(4, e)
  end)

  it("sends the whole outer block when cursor is on the outer header", function()
    buf = make_nested_buf()
    h.set_cursor(1)
    local _, s, e = julia.get_send_text()
    assert.equals(1, s)
    assert.equals(6, e)
  end)

  it("sends the whole outer block when cursor is on a line after the inner block", function()
    buf = make_nested_buf()
    h.set_cursor(5)
    local _, s, e = julia.get_send_text()
    assert.equals(1, s)
    assert.equals(6, e)
  end)

  it("sends only the inner 'end' line when cursor is on it", function()
    buf = make_nested_buf()
    h.set_cursor(4)
    local text, s, e = julia.get_send_text()
    assert.equals("    end", text)
    assert.equals(4, s)
    assert.equals(4, e)
  end)
end)

describe("julia.get_send_text: sibling blocks", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("does not bleed into an unrelated preceding block", function()
    buf = h.make_buf("julia", {
      "function f()", -- 1
      "    1", -- 2
      "end", -- 3
      "function g()", -- 4
      "    2", -- 5
      "end", -- 6
    })
    h.set_cursor(4)
    local _, s, e = julia.get_send_text()
    assert.equals(4, s)
    assert.equals(6, e)
  end)

  it("does not bleed into an unrelated following block", function()
    buf = h.make_buf("julia", {
      "function f()",
      "    1",
      "end",
      "function g()",
      "    2",
      "end",
    })
    h.set_cursor(1)
    local _, s, e = julia.get_send_text()
    assert.equals(1, s)
    assert.equals(3, e)
  end)
end)

describe("julia.get_send_text: comments inside blocks", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("does not break block detection when a comment sits inside the body", function()
    buf = h.make_buf("julia", {
      "function f(x)",
      "    # a comment about x",
      "    y = x + 1",
      "    return y",
      "end",
    })
    h.set_cursor(1)
    local _, s, e = julia.get_send_text()
    assert.equals(1, s)
    assert.equals(5, e)
  end)

  it("resolves the owning block when cursor is on a comment inside the body", function()
    buf = h.make_buf("julia", {
      "function f(x)",
      "    # a comment about x",
      "    y = x + 1",
      "end",
    })
    h.set_cursor(2)
    local _, s, e = julia.get_send_text()
    assert.equals(1, s)
    assert.equals(4, e)
  end)
end)

describe("julia.get_send_text: other block keywords", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  local cases = {
    { name = "while", lines = { "while true", "    break", "end" } },
    { name = "struct", lines = { "struct Point", "    x", "    y", "end" } },
    { name = "mutable struct", lines = { "mutable struct Point", "    x", "end" } },
    { name = "abstract type", lines = { "abstract type Shape end" } },
    { name = "module", lines = { "module Foo", "x = 1", "end" } },
    { name = "let block", lines = { "let x = 1", "    x + 1", "end" } },
    { name = "bare let", lines = { "let", "    1", "end" } },
    { name = "quote", lines = { "quote", "    1 + 1", "end" } },
    { name = "try", lines = { "try", "    risky()", "catch e", "    handle(e)", "end" } },
    { name = "testset macro", lines = { '@testset "mytest" begin', "    @test 1 == 1", "end" } },
  }

  for _, case in ipairs(cases) do
    it("sends the whole '" .. case.name .. "' block from its header", function()
      buf = h.make_buf("julia", case.lines)
      h.set_cursor(1)
      local _, s, e = julia.get_send_text()
      assert.equals(1, s)
      assert.equals(#case.lines, e)
      h.cleanup(buf)
      buf = nil
    end)
  end
end)

describe("julia.get_send_text: edge cases", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("returns nil for an empty buffer", function()
    buf = h.make_buf("julia", { "" })
    h.set_cursor(1)
    local text = julia.get_send_text()
    assert.is_nil(text)
  end)

  it("handles an unterminated block start (no matching end) gracefully", function()
    buf = h.make_buf("julia", { "function f(x)", "    y = x + 1" })
    h.set_cursor(1)
    local text, s, e = julia.get_send_text()
    -- No matching `end` found: falls back to sending just the header line.
    assert.equals("function f(x)", text)
    assert.equals(1, s)
    assert.equals(1, e)
  end)
end)
