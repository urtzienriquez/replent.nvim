-- tests/quarto_spec.lua
-- Tests for lua/replent/quarto.lua language detection.

local assert = require("luassert")
local h = require("tests.helpers")
local quarto = require("replent.quarto")

describe("quarto.detect", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("detects a python chunk opener", function()
    buf = h.make_buf("quarto", { "---", "title: doc", "---", "", "```{python}", "1 + 1", "```" })
    assert.equals("python", quarto.detect(buf))
  end)

  it("detects a julia chunk opener", function()
    buf = h.make_buf("quarto", { "```{julia}", "1 + 1", "```" })
    assert.equals("julia", quarto.detect(buf))
  end)

  it("detects a matlab chunk opener", function()
    buf = h.make_buf("quarto", { "```{matlab}", "x = 1;", "```" })
    assert.equals("matlab", quarto.detect(buf))
  end)

  it("is case-insensitive on the language name", function()
    buf = h.make_buf("quarto", { "```{Python}", "1 + 1", "```" })
    assert.equals("python", quarto.detect(buf))
  end)

  it("detects the language when chunk options follow it", function()
    buf = h.make_buf("quarto", { "```{python, echo=FALSE}", "1 + 1", "```" })
    assert.equals("python", quarto.detect(buf))
  end)

  it("ignores unsupported languages (e.g. r) and returns nil", function()
    buf = h.make_buf("quarto", { "```{r}", "1 + 1", "```" })
    assert.is_nil(quarto.detect(buf))
  end)

  it("returns the first supported language found, in document order", function()
    buf = h.make_buf("quarto", { "```{r}", "summary(x)", "```", "```{python}", "1 + 1", "```" })
    assert.equals("python", quarto.detect(buf))
  end)

  it("returns nil for a buffer with no code chunks", function()
    buf = h.make_buf("quarto", { "# Just prose", "No chunks here." })
    assert.is_nil(quarto.detect(buf))
  end)

  it("caches the result across repeated calls (survives buffer edits until BufUnload)", function()
    buf = h.make_buf("quarto", { "```{python}", "1 + 1", "```" })
    assert.equals("python", quarto.detect(buf))
    -- Mutate the buffer to remove the chunk; cached result should stick.
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "no chunks now" })
    assert.equals("python", quarto.detect(buf))
  end)
end)

describe("quarto.is_active", function()
  local buf

  after_each(function()
    h.cleanup(buf)
  end)

  it("is true for a quarto buffer with a supported chunk", function()
    buf = h.make_buf("quarto", { "```{julia}", "1", "```" })
    assert.is_true(quarto.is_active(buf))
  end)

  it("is false for a quarto buffer with no supported chunk", function()
    buf = h.make_buf("quarto", { "prose only" })
    assert.is_false(quarto.is_active(buf))
  end)

  it("is false for a non-quarto buffer even if it looks like it has a chunk", function()
    buf = h.make_buf("markdown", { "```{python}", "1", "```" })
    assert.is_false(quarto.is_active(buf))
  end)
end)
