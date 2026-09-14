-- tests/config_spec.lua
-- Tests for lua/replent/config.lua defaults and setup() merging.

local assert = require("luassert")

describe("config defaults", function()
  it("defaults to the tmux strategy", function()
    package.loaded["replent.config"] = nil
    local config = require("replent.config")
    assert.equals("tmux", config.defaults.strategy)
    assert.equals("tmux", config.options.strategy)
  end)

  it("includes python, julia, matlab, quarto and jnoweb filetypes", function()
    package.loaded["replent.config"] = nil
    local config = require("replent.config")
    local fts = config.defaults.filetypes
    assert.truthy(vim.tbl_contains(fts, "python"))
    assert.truthy(vim.tbl_contains(fts, "julia"))
    assert.truthy(vim.tbl_contains(fts, "matlab"))
    assert.truthy(vim.tbl_contains(fts, "quarto"))
    assert.truthy(vim.tbl_contains(fts, "jnoweb"))
  end)

  it("maps send_line to <CR> by default", function()
    package.loaded["replent.config"] = nil
    local config = require("replent.config")
    assert.equals("<CR>", config.defaults.keymaps.send_line)
  end)
end)

describe("config.setup", function()
  before_each(function()
    package.loaded["replent.config"] = nil
  end)

  it("deep-merges user options onto the defaults without mutating defaults", function()
    local config = require("replent.config")
    config.setup({ keymaps = { send_line = "<S-CR>" } })

    assert.equals("<S-CR>", config.options.keymaps.send_line)
    -- unrelated defaults survive the merge
    assert.equals("<leader>sb", config.options.keymaps.send_buffer)
    -- the defaults table itself is untouched
    assert.equals("<CR>", config.defaults.keymaps.send_line)
  end)

  it("overrides top-level scalar options", function()
    local config = require("replent.config")
    config.setup({ strategy = "neovim" })
    assert.equals("neovim", config.options.strategy)
  end)

  it("sets slime_target/slime_bracketed_paste for the tmux strategy", function()
    local config = require("replent.config")
    config.setup({ strategy = "tmux" })
    assert.equals("tmux", vim.g.slime_target)
    assert.equals(1, vim.g.slime_bracketed_paste)
  end)

  it("sets slime_target/slime_bracketed_paste for the neovim strategy", function()
    local config = require("replent.config")
    config.setup({ strategy = "neovim" })
    assert.equals("neovim", vim.g.slime_target)
    assert.equals(0, vim.g.slime_bracketed_paste)
  end)

  it("merges nested neovim options without dropping untouched keys", function()
    local config = require("replent.config")
    config.setup({ neovim = { width = 100 } })
    assert.equals(100, config.options.neovim.width)
    assert.equals(15, config.options.neovim.height)
    assert.equals("right", config.options.neovim.position)
  end)

  it("accepts a custom repl_commands entry while keeping the others", function()
    local config = require("replent.config")
    config.setup({ repl_commands = { python = "python3 -i" } })
    assert.equals("python3 -i", config.options.repl_commands.python)
    assert.equals("julia", config.options.repl_commands.julia)
  end)

  it("is safe to call with no arguments", function()
    local config = require("replent.config")
    config.setup()
    assert.equals("tmux", config.options.strategy)
  end)
end)
