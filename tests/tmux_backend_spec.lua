-- tests/tmux_backend_spec.lua
-- Tests for lua/replent/tmux.lua, the "tmux strategy" REPL backend used
-- when config.strategy = "tmux" (REPL runs in a tmux pane next to Neovim,
-- as opposed to a Neovim terminal split).
--
-- Three tiers of coverage:
--   1. in_tmux() itself (pure env-var check).
--   2. Graceful behavior when NOT inside tmux (deterministic, no shell-out).
--   3. julia_channels() output parsing, with io.popen stubbed so it needs
--      neither a real tmux session nor juliaup installed.
--   4. An opt-in, gated end-to-end test that spawns a REAL tmux pane. This
--      only runs when REPLENT_TEST_TMUX=1 is set (see README) AND no other
--      tmux session already exists on the default socket -- open_tmux_split
--      in tmux.lua doesn't pass `-t`, so on a developer machine with real
--      tmux sessions running it could otherwise send commands into the
--      wrong one. CI opts in explicitly on a clean runner; local runs don't
--      by default.

local assert = require("luassert")

local config = require("replent.config")
local tmux = require("replent.tmux")

describe("tmux.in_tmux", function()
  local orig_tmux

  before_each(function()
    orig_tmux = vim.env.TMUX
  end)

  after_each(function()
    vim.env.TMUX = orig_tmux
  end)

  it("is false when $TMUX is not set", function()
    vim.env.TMUX = nil
    assert.is_false(tmux.in_tmux())
  end)

  it("is true when $TMUX is set", function()
    vim.env.TMUX = "/tmp/fake-tmux-socket,1234,0"
    assert.is_true(tmux.in_tmux())
  end)
end)

describe("tmux backend: graceful behavior outside tmux", function()
  local orig_tmux
  local notified
  local orig_notify

  before_each(function()
    orig_tmux = vim.env.TMUX
    vim.env.TMUX = nil
    config.setup({ strategy = "tmux", repl_commands = { python = "cat" } })

    notified = {}
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notified, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.env.TMUX = orig_tmux
    vim.notify = orig_notify
  end)

  it("start_repl notifies an error and starts nothing", function()
    tmux.start_repl("python")
    assert.is_false(tmux.has_active_repl("python"))
    assert.is_true(#notified > 0)
    assert.matches("Not in a tmux session", notified[1].msg)
  end)

  it("close_repl is a silent no-op", function()
    assert.has_no.errors(function()
      tmux.close_repl("python")
    end)
  end)

  it("sync_cwd notifies an error instead of erroring", function()
    tmux.sync_cwd()
    assert.is_true(#notified > 0)
    assert.matches("Not in a tmux session", notified[1].msg)
  end)
end)

describe("tmux.julia_channels: parses `juliaup status` output", function()
  local orig_popen

  before_each(function()
    orig_popen = io.popen
  end)

  after_each(function()
    io.popen = orig_popen
  end)

  --- Stub io.popen to answer canned output per command, keyed by a Lua
  --- pattern matched against the command string.
  local function stub_popen(responses)
    io.popen = function(cmd)
      for pattern, output in pairs(responses) do
        if cmd:match(pattern) then
          return {
            read = function(_, _fmt)
              return output
            end,
            close = function() end,
          }
        end
      end
      return nil
    end
  end

  it("parses multiple channels from a real juliaup status table", function()
    stub_popen({
      ["juliaup status"] = table.concat({
        " Default  Channel  Version                 Update                                     ",
        "--------------------------------------------------------------------------------------",
        "       *  1.11     1.11.9+0.x64.linux.gnu                                             ",
        "          release  1.12.7+0.x64.linux.gnu  Update to 1.13.0+0.x64.linux.gnu available ",
      }, "\n"),
    })

    local channels = tmux.julia_channels()
    assert.same({ "1.11", "release" }, channels)
  end)

  it("parses a table with a single channel", function()
    stub_popen({
      ["juliaup status"] = table.concat({
        " Default  Channel  Version                 Update  ",
        "-------------------------------------------------- ",
        "       *  1.10     1.10.4+0.x64.linux.gnu          ",
      }, "\n"),
    })

    local channels = tmux.julia_channels()
    assert.same({ "1.10" }, channels)
  end)

  it("falls back to 'default' when juliaup has no table but plain julia works", function()
    stub_popen({
      ["juliaup status"] = "",
      ["julia %+default %-%-version"] = "julia version 1.10.4\n",
    })

    local channels = tmux.julia_channels()
    assert.same({ "default" }, channels)
  end)

  it("returns an empty list when neither juliaup nor julia is available", function()
    stub_popen({
      ["juliaup status"] = "",
      ["julia %+default %-%-version"] = "",
    })

    local channels = tmux.julia_channels()
    assert.same({}, channels)
  end)

  it("returns an empty list when io.popen itself fails (command not found)", function()
    io.popen = function()
      return nil
    end
    local channels = tmux.julia_channels()
    assert.same({}, channels)
  end)
end)

describe("tmux.has_active_repl / active_repl_type", function()
  local orig_popen

  before_each(function()
    orig_popen = io.popen
  end)

  after_each(function()
    io.popen = orig_popen
  end)

  local function stub_pane_alive(alive)
    io.popen = function(cmd)
      if cmd:match("tmux display%-message") then
        return {
          read = function()
            return alive and "%1" or nil
          end,
          close = function() end,
        }
      end
      return nil
    end
  end

  it("is false for a filetype with no tracked pane", function()
    stub_pane_alive(false)
    assert.is_false(tmux.has_active_repl("nonexistent-ft"))
    assert.is_nil(tmux.active_repl_type("nonexistent-ft"))
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- Opt-in end-to-end test: spawns a REAL tmux pane on the default socket.
-- See the file header for why this is gated behind both an explicit env
-- var and a "no other sessions" safety check.
-- ─────────────────────────────────────────────────────────────

local function other_sessions_exist()
  local h = io.popen("tmux list-sessions -F '#{session_name}' 2>/dev/null")
  if not h then
    return false
  end
  local out = h:read("*a")
  h:close()
  for line in out:gmatch("[^\r\n]+") do
    if line ~= "" and line ~= "replent_e2e_test" then
      return true
    end
  end
  return false
end

local run_e2e = vim.env.REPLENT_TEST_TMUX == "1"
  and vim.fn.executable("tmux") == 1
  and not other_sessions_exist()

describe("tmux backend: end-to-end pane spawning (opt-in)", function()
  if not run_e2e then
    it("skipped: set REPLENT_TEST_TMUX=1 on a clean tmux-less machine/CI runner to enable", function()
      assert.is_true(true)
    end)
    return
  end

  local session = "replent_e2e_test"
  local orig_in_tmux

  before_each(function()
    os.execute(string.format("tmux new-session -d -s %s -x 200 -y 50 2>/dev/null", session))
    -- Stub in_tmux() rather than faking $TMUX: the real `tmux` CLI itself
    -- reads $TMUX to resolve which socket to talk to, so setting it to a
    -- fake value would break every actual `tmux ...` shell-out below.
    -- Leaving $TMUX alone lets those calls resolve the default socket
    -- normally (isolated per-test via $TMUX_TMPDIR, see the CI workflow).
    orig_in_tmux = tmux.in_tmux
    tmux.in_tmux = function()
      return true
    end
    config.setup({ strategy = "tmux", repl_commands = { python = "cat" } })
  end)

  after_each(function()
    os.execute(string.format("tmux kill-session -t %s 2>/dev/null", session))
    tmux.in_tmux = orig_in_tmux
  end)

  it("start_repl opens a real pane and has_active_repl reflects it", function()
    tmux.start_repl("python")
    vim.wait(500, function()
      return tmux.has_active_repl("python")
    end, 50)
    assert.is_true(tmux.has_active_repl("python"))
  end)

  it("close_repl sends an exit keystroke and clears tracking", function()
    tmux.start_repl("python")
    vim.wait(500, function()
      return tmux.has_active_repl("python")
    end, 50)

    tmux.close_repl("python")
    assert.is_nil(tmux.active_repl_type("python"))
  end)
end)
