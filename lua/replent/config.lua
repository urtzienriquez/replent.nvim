local M = {}

---@class ReplentConfig
M.defaults = {
  strategy = "tmux",
  filetypes = { "python", "julia", "matlab", "quarto", "jnoweb" },
  keymaps = {
    send_line = "<CR>",
    send_selection = "<CR>",
    send_buffer = "<leader>sb",
    start_python = "<leader>op",
    start_julia = "<leader>oj",
    start_matlab = "<leader>om",
    close_python = "<leader>qp",
    close_julia = "<leader>qj",
    close_matlab = "<leader>qm",
    sync_cwd = "<leader>cd",
    julia_instantiate = "<leader>ji",
    debug_block = "<leader>bc",
  },
  repl_commands = {
    python = "ipython --no-confirm-exit --no-banner --quiet",
    julia = "julia",
    matlab = "matlab -nodesktop -nosplash",
  },
  auto_cd = false,
  -- Options used only by the "neovim" strategy
  neovim = {
    -- Split width in columns. If the current window is wide enough the REPL
    -- opens as a vertical split of this exact width; 0 = disabled.
    width = 80,
    -- Minimum columns to leave for the editor before using an exact-width
    -- vertical split (also used if width is disabled).
    min_editor_width = 80,
    -- Split height in rows, used when the vertical split doesn't fit (e.g.
    -- narrow window). 0 = disabled (equal split is used instead).
    height = 15,
    -- Position of the REPL split: "right", "left", "below", or "above"
    position = "right",
    -- Local options applied to the REPL window. The default keeps the REPL
    -- at its fixed width/height, so external window resizes hit the editor
    -- (a plain text buffer) instead of the terminal, and the REPL text is
    -- never narrow-baked into the terminal scrollback.
    -- Set buflisted -> nobuflisted here to hide the REPL from :ls.
    buffer_opts = "winfixwidth winfixheight buflisted",
    -- Map <Esc> to exit terminal-insert mode (<C-\\><C-n>)
    esc_term = true,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(user_opts)
  M.options = vim.tbl_deep_extend("force", M.options, user_opts or {})

  if M.options.strategy == "neovim" then
    vim.g.slime_target = "neovim"
    vim.g.slime_bracketed_paste = 0
  else
    vim.g.slime_target = "tmux"
    vim.g.slime_bracketed_paste = 1
  end
end

return M
