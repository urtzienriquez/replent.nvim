-- tests/actions_spec.lua
-- Integration tests for lua/replent/actions.lua: effective_lang resolution,
-- send_block's interaction with the per-language modules, the
-- blank-line-skipping cursor advance, and the non-smart-block fallback.

local assert = require("luassert")
local h = require("tests.helpers")

local config = require("replent.config")
local actions = require("replent.actions")

--- Stub vim.fn["slime#send"] to capture what was sent instead of requiring
--- a real REPL / vim-slime installation.
local sent
local function stub_slime_send()
  sent = nil
  vim.fn["slime#send"] = function(text)
    sent = text
  end
end

describe("actions.effective_lang", function()
  local buf

  before_each(function()
    config.setup({ strategy = "tmux" })
    stub_slime_send()
  end)

  after_each(function()
    h.cleanup(buf)
  end)

  it("returns the filetype directly for python/julia/matlab", function()
    buf = h.make_buf("python", { "x = 1" })
    assert.equals("python", actions.effective_lang())
  end)

  it("resolves jnoweb to julia", function()
    buf = h.make_buf("jnoweb", { "x = 1" })
    assert.equals("julia", actions.effective_lang())
  end)

  it("resolves quarto via chunk detection", function()
    buf = h.make_buf("quarto", { "```{python}", "1 + 1", "```" })
    assert.equals("python", actions.effective_lang())
  end)
end)

describe("actions.get_send_text: delegation", function()
  local buf

  before_each(function()
    config.setup({ strategy = "tmux" })
    stub_slime_send()
  end)

  after_each(function()
    h.cleanup(buf)
  end)

  it("delegates to the julia module for julia buffers", function()
    buf = h.make_buf("julia", { "function f()", "  1", "end" })
    h.set_cursor(1)
    local text, s, e = actions.get_send_text()
    assert.equals(1, s)
    assert.equals(3, e)
    assert.matches("^function f%(%)", text)
  end)

  it("delegates to the python module for python buffers", function()
    buf = h.make_buf("python", { "def f():", "    return 1" })
    h.set_cursor(1)
    local text, s, e = actions.get_send_text()
    assert.equals(1, s)
    assert.equals(2, e)
    assert.matches("^def f%(%):", text)
  end)

  it("delegates to the matlab module for matlab buffers", function()
    buf = h.make_buf("matlab", { "function y = f(x)", "  y = x;", "end" })
    h.set_cursor(1)
    local text, s, e = actions.get_send_text()
    assert.equals(1, s)
    assert.equals(3, e)
    assert.matches("^function y = f%(x%)", text)
  end)

  it("delegates through jnoweb to julia block detection", function()
    buf = h.make_buf("jnoweb", { "function f()", "  1", "end" })
    h.set_cursor(1)
    local _, s, e = actions.get_send_text()
    assert.equals(1, s)
    assert.equals(3, e)
  end)

  it("delegates through quarto chunk detection to the right module", function()
    buf = h.make_buf("quarto", { "```{python}", "def f():", "    return 1", "```" })
    h.set_cursor(2)
    local _, s, e = actions.get_send_text()
    assert.equals(2, s)
    assert.equals(3, e)
  end)

  it("falls back to the current line for an unsupported filetype", function()
    buf = h.make_buf("text", { "just some text", "more text" })
    h.set_cursor(1)
    local text, s, e = actions.get_send_text()
    assert.equals("just some text", text)
    assert.equals(1, s)
    assert.equals(1, e)
  end)
end)

describe("actions.send_block: sends text and advances the cursor", function()
  local buf

  before_each(function()
    config.setup({ strategy = "tmux" })
    stub_slime_send()
  end)

  after_each(function()
    h.cleanup(buf)
  end)

  it("sends a single python statement and moves to the next line", function()
    buf = h.make_buf("python", { "x = 1", "y = 2" })
    h.set_cursor(1)
    actions.send_block()
    assert.equals("x = 1\n", sent)
    assert.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("sends a whole julia function block and lands after its 'end'", function()
    buf = h.make_buf("julia", { "function f()", "  1", "end", "g()" })
    h.set_cursor(1)
    actions.send_block()
    assert.equals("function f()\n  1\nend\n", sent)
    assert.same({ 4, 0 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("appends exactly one trailing newline for matlab (no double newline)", function()
    buf = h.make_buf("matlab", { "x = 1;" })
    h.set_cursor(1)
    actions.send_block()
    assert.equals("x = 1;\n", sent)
  end)

  it("skips a run of blank lines after sending, landing on the next code line", function()
    buf = h.make_buf("python", { "x = 1", "", "", "y = 2" })
    h.set_cursor(1)
    actions.send_block()
    assert.equals("x = 1\n", sent)
    assert.same({ 4, 0 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("does not send anything when pressed on a blank line, but skips the cursor forward", function()
    buf = h.make_buf("python", { "x = 1", "", "", "y = 2" })
    h.set_cursor(2)
    actions.send_block()
    assert.is_nil(sent)
    assert.same({ 4, 0 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("sends a standalone comment and advances for python", function()
    buf = h.make_buf("python", { "# hello", "x = 1" })
    h.set_cursor(1)
    actions.send_block()
    assert.equals("# hello\n", sent)
    assert.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("lands on the last line when there is no further code after a blank run", function()
    buf = h.make_buf("python", { "x = 1", "", "" })
    h.set_cursor(1)
    actions.send_block()
    assert.equals("x = 1\n", sent)
    assert.same({ 3, 0 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("does not move the cursor for filetypes without smart blocks", function()
    buf = h.make_buf("text", { "line one", "line two" })
    h.set_cursor(1)
    actions.send_block()
    assert.equals("line one\n", sent)
    assert.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("does not call slime#send for a blank line on a non-smart-block filetype", function()
    -- Fallback get_send_text returns the raw (blank) line, which send_block's
    -- own blank-text guard still catches.
    buf = h.make_buf("text", { "", "line two" })
    h.set_cursor(1)
    actions.send_block()
    assert.is_nil(sent)
  end)
end)

describe("actions.send_selection", function()
  local buf

  before_each(function()
    config.setup({ strategy = "tmux" })
    stub_slime_send()
  end)

  after_each(function()
    h.cleanup(buf)
  end)

  it("sends the visually selected lines joined by newlines", function()
    buf = h.make_buf("python", { "a = 1", "b = 2", "c = 3", "d = 4" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! V2j")
    actions.send_selection()
    assert.equals("a = 1\nb = 2\nc = 3\n", sent)
  end)
end)

describe("actions.send_buffer", function()
  local buf

  before_each(function()
    config.setup({ strategy = "tmux" })
    stub_slime_send()
  end)

  after_each(function()
    h.cleanup(buf)
  end)

  it("sends the entire buffer contents", function()
    buf = h.make_buf("python", { "a = 1", "b = 2" })
    actions.send_buffer()
    assert.equals("a = 1\nb = 2\n", sent)
  end)
end)

describe("actions.debug_block", function()
  local buf
  local notified
  local orig_notify

  before_each(function()
    notified = {}
    orig_notify = vim.notify
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      table.insert(notified, msg)
    end
  end)

  after_each(function()
    vim.notify = orig_notify
    h.cleanup(buf)
  end)

  it("does not error for julia, python, or matlab buffers", function()
    for _, ft in ipairs({ "julia", "python", "matlab" }) do
      buf = h.make_buf(ft, { "x = 1" })
      h.set_cursor(1)
      assert.has_no.errors(function()
        actions.debug_block()
      end)
      h.cleanup(buf)
      buf = nil
    end
    assert.is_true(#notified > 0)
  end)

  it("is a no-op for filetypes without a debug module", function()
    buf = h.make_buf("text", { "x = 1" })
    h.set_cursor(1)
    assert.has_no.errors(function()
      actions.debug_block()
    end)
  end)
end)
