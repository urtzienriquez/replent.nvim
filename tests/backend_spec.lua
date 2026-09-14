-- tests/backend_spec.lua
-- Tests for lua/replent/backend.lua: strategy → backend module selection.

local assert = require("luassert")

describe("backend.get", function()
  local config = require("replent.config")

  it("returns the neovim backend when strategy = 'neovim'", function()
    config.setup({ strategy = "neovim" })
    package.loaded["replent.backend"] = nil
    local backend = require("replent.backend")
    assert.equal(require("replent.neovim"), backend.get())
  end)

  it("returns the tmux backend when strategy = 'tmux'", function()
    config.setup({ strategy = "tmux" })
    package.loaded["replent.backend"] = nil
    local backend = require("replent.backend")
    assert.equal(require("replent.tmux"), backend.get())
  end)

  it("defaults to the tmux backend for an unrecognized strategy", function()
    config.setup({ strategy = "something-else" })
    package.loaded["replent.backend"] = nil
    local backend = require("replent.backend")
    assert.equal(require("replent.tmux"), backend.get())
  end)
end)
