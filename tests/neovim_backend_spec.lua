-- tests/neovim_backend_spec.lua
-- End-to-end tests for lua/replent/neovim.lua, the "neovim strategy" REPL
-- backend used when config.strategy = "neovim" (REPL runs in a Neovim
-- terminal split, as opposed to a tmux pane). Exercises real window/job
-- creation with a trivial, always-available "REPL" (`cat`) instead of a
-- real python/julia/matlab binary, so this runs on any machine/CI runner.

local assert = require("luassert")
local h = require("tests.helpers")

local config = require("replent.config")
local neovim = require("replent.neovim")

--- Force replent.tmux's julia channel detection to report no channels, so
--- starting a "julia" REPL deterministically falls back to the plain
--- `julia` command instead of opening an interactive channel picker
--- (juliaup may or may not be installed on the machine running the tests).
local function stub_no_julia_channels()
  package.loaded["replent.tmux"] = package.loaded["replent.tmux"] or require("replent.tmux")
  package.loaded["replent.tmux"].julia_channels = function()
    return {}
  end
end

--- Close all tracked REPLs and any windows left behind by them. Deleting a
--- REPL's terminal buffer doesn't close its split, so without this, splits
--- opened by one test would leak into the next (all `it`s in a spec file
--- share one Neovim process).
local function close_all_repls(keep_buf)
  for _, ft in ipairs({ "python", "julia", "matlab" }) do
    neovim.close_repl(ft)
  end
  h.close_extra_windows(keep_buf)
end

describe("neovim backend: starting and tracking a REPL", function()
  local buf

  before_each(function()
    config.setup({
      strategy = "neovim",
      repl_commands = { python = "cat", julia = "cat", matlab = "cat" },
    })
    stub_no_julia_channels()
    buf = h.make_buf("python", { "x = 1" })
  end)

  after_each(function()
    close_all_repls(buf)
    h.cleanup(buf)
  end)

  it("reports no active REPL before one is started", function()
    assert.is_falsy(neovim.has_active_repl())
    assert.is_nil(neovim.get_job_id("python"))
  end)

  it("starts a terminal split and tracks the job", function()
    local win_count_before = #vim.api.nvim_list_wins()
    neovim.start_repl("python")

    assert.equals(win_count_before + 1, #vim.api.nvim_list_wins())
    assert.is_true(neovim.has_active_repl())

    local jobid = neovim.get_job_id("python")
    assert.is_number(jobid)
    assert.is_true(jobid > 0)
  end)

  it("leaves the original buffer as the current buffer after spawning", function()
    neovim.start_repl("python")
    assert.equals(buf, vim.api.nvim_get_current_buf())
  end)

  it("spawns a real terminal buffer for the REPL window", function()
    neovim.start_repl("python")
    local found_terminal = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(win)
      if b ~= buf and vim.bo[b].buftype == "terminal" then
        found_terminal = true
      end
    end
    assert.is_true(found_terminal)
  end)

  it("does not start a second job when called again while one is active", function()
    neovim.start_repl("python")
    local jobid1 = neovim.get_job_id("python")
    neovim.start_repl("python")
    local jobid2 = neovim.get_job_id("python")
    assert.equals(jobid1, jobid2)
  end)

  it("falls back to the plain julia command when no juliaup channels are found", function()
    neovim.start_repl("julia")
    local jobid = neovim.get_job_id("julia")
    assert.is_number(jobid)
  end)

  it("notifies an error and starts nothing for a filetype with no configured command", function()
    local notified = {}
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notified, { msg = msg, level = level })
    end

    -- "rlang" was never given a repl_commands entry, by any test in this file.
    neovim.start_repl("rlang")

    vim.notify = orig_notify
    assert.is_nil(neovim.get_job_id("rlang"))
    assert.is_true(#notified > 0)
    assert.matches("No command configured", notified[1].msg)
  end)
end)

describe("neovim backend: window/buffer options applied to the REPL split", function()
  local buf

  before_each(function()
    config.setup({
      strategy = "neovim",
      repl_commands = { python = "cat" },
      neovim = {
        width = 80,
        min_editor_width = 80,
        height = 15,
        position = "right",
        buffer_opts = "winfixwidth winfixheight buflisted",
        esc_term = true,
      },
    })
    buf = h.make_buf("python", { "x = 1" })
  end)

  after_each(function()
    close_all_repls(buf)
    h.cleanup(buf)
  end)

  local function repl_win_and_buf()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(win)
      if b ~= buf then
        return win, b
      end
    end
  end

  it("applies winfixwidth/winfixheight to the REPL window", function()
    neovim.start_repl("python")
    local win = repl_win_and_buf()
    assert.is_true(vim.wo[win].winfixwidth)
    assert.is_true(vim.wo[win].winfixheight)
  end)

  it("respects buflisted in buffer_opts", function()
    neovim.start_repl("python")
    local _, replbuf = repl_win_and_buf()
    assert.is_true(vim.bo[replbuf].buflisted)
  end)

  it("honors 'nobuflisted' when configured", function()
    config.setup({ neovim = { buffer_opts = "winfixwidth winfixheight nobuflisted" } })
    neovim.start_repl("python")
    local _, replbuf = repl_win_and_buf()
    assert.is_false(vim.bo[replbuf].buflisted)
  end)

  it("maps <Esc> to exit terminal mode when esc_term is true", function()
    neovim.start_repl("python")
    local _, replbuf = repl_win_and_buf()
    local maps = vim.api.nvim_buf_get_keymap(replbuf, "t")
    local has_esc = false
    for _, m in ipairs(maps) do
      if m.lhs == "<Esc>" then
        has_esc = true
      end
    end
    assert.is_true(has_esc)
  end)

  it("does not map <Esc> when esc_term is false", function()
    config.setup({ neovim = { esc_term = false } })
    neovim.start_repl("python")
    local _, replbuf = repl_win_and_buf()
    local maps = vim.api.nvim_buf_get_keymap(replbuf, "t")
    local has_esc = false
    for _, m in ipairs(maps) do
      if m.lhs == "<Esc>" then
        has_esc = true
      end
    end
    assert.is_false(has_esc)
  end)
end)

describe("neovim backend: split geometry", function()
  local buf
  local orig_columns, orig_lines

  before_each(function()
    orig_columns, orig_lines = vim.o.columns, vim.o.lines
    config.setup({
      strategy = "neovim",
      repl_commands = { python = "cat" },
      neovim = {
        width = 80,
        min_editor_width = 80,
        height = 15,
        position = "right",
        buffer_opts = "winfixwidth winfixheight buflisted",
        esc_term = true,
      },
    })
    buf = h.make_buf("python", { "x = 1" })
  end)

  after_each(function()
    close_all_repls(buf)
    h.cleanup(buf)
    vim.o.columns, vim.o.lines = orig_columns, orig_lines
  end)

  it("opens an exact-width vertical split when the window is wide enough", function()
    vim.o.columns = 250
    vim.o.lines = 50
    neovim.start_repl("python")
    local repl_win
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) ~= buf then
        repl_win = win
      end
    end
    assert.equals(80, vim.api.nvim_win_get_width(repl_win))
  end)

  it("falls back to an exact-height horizontal split when too narrow", function()
    vim.o.columns = 80
    vim.o.lines = 50
    neovim.start_repl("python")
    local repl_win
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) ~= buf then
        repl_win = win
      end
    end
    assert.equals(15, vim.api.nvim_win_get_height(repl_win))
  end)
end)

describe("neovim backend: closing and reopening", function()
  local buf

  before_each(function()
    config.setup({
      strategy = "neovim",
      repl_commands = { python = "cat" },
    })
    buf = h.make_buf("python", { "x = 1" })
    neovim.start_repl("python")
  end)

  after_each(function()
    close_all_repls(buf)
    h.cleanup(buf)
  end)

  it("close_repl removes the terminal buffer and clears tracking", function()
    local repl_buf
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) ~= buf then
        repl_buf = vim.api.nvim_win_get_buf(win)
      end
    end

    neovim.close_repl("python")

    assert.is_nil(neovim.get_job_id("python"))
    assert.is_falsy(neovim.has_active_repl())
    assert.is_false(vim.api.nvim_buf_is_valid(repl_buf))
  end)

  it("reopen_win recreates a window for a hidden-but-alive REPL buffer", function()
    local repl_win
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) ~= buf then
        repl_win = win
      end
    end
    local win_count_before = #vim.api.nvim_list_wins()
    vim.api.nvim_win_close(repl_win, true)
    assert.equals(win_count_before - 1, #vim.api.nvim_list_wins())

    -- REPL job/buffer is still tracked even though its window is gone
    assert.is_true(neovim.has_active_repl())

    neovim.start_repl("python") -- data exists -> should call reopen_win, not spawn a new job
    assert.equals(win_count_before, #vim.api.nvim_list_wins())
  end)

  it("reopen_win is a no-op when the REPL window is already visible", function()
    local win_count_before = #vim.api.nvim_list_wins()
    neovim.reopen_win("python")
    assert.equals(win_count_before, #vim.api.nvim_list_wins())
  end)
end)

describe("neovim backend: sync_cwd", function()
  local buf
  local orig_chan_send
  local sent_payloads

  before_each(function()
    config.setup({
      strategy = "neovim",
      repl_commands = { python = "cat", julia = "cat", matlab = "cat" },
    })
    sent_payloads = {}
    orig_chan_send = vim.api.nvim_chan_send
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_chan_send = function(chan, data)
      table.insert(sent_payloads, { chan = chan, data = data })
    end
  end)

  after_each(function()
    vim.api.nvim_chan_send = orig_chan_send
    close_all_repls(buf)
    h.cleanup(buf)
  end)

  it("sends a python os.chdir command to the tracked job", function()
    buf = h.make_buf("python", { "x = 1" })
    neovim.start_repl("python")
    local jobid = neovim.get_job_id("python")

    neovim.sync_cwd()

    assert.equals(1, #sent_payloads)
    assert.equals(jobid, sent_payloads[1].chan)
    assert.matches("^import os; os%.chdir%('.+'%)\n$", sent_payloads[1].data)
  end)

  it("sends a julia cd(...) command to the tracked job", function()
    buf = h.make_buf("julia", { "x = 1" })
    stub_no_julia_channels()
    neovim.start_repl("julia")

    neovim.sync_cwd()

    assert.equals(1, #sent_payloads)
    assert.matches('^cd%(".+"%)\n$', sent_payloads[1].data)
  end)

  it("sends a matlab cd '...' command to the tracked job", function()
    buf = h.make_buf("matlab", { "x = 1" })
    neovim.start_repl("matlab")

    neovim.sync_cwd()

    assert.equals(1, #sent_payloads)
    assert.matches("^cd '.+'\n$", sent_payloads[1].data)
  end)

  it("does nothing when there is no active REPL for the current filetype", function()
    buf = h.make_buf("python", { "x = 1" })
    neovim.sync_cwd()
    assert.equals(0, #sent_payloads)
  end)
end)
